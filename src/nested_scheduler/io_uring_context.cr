require "./io_context"
require "ior"

module NestedScheduler
  class IoUringContext < IOContext
    # What is a good waittime? Perhaps it needs to be a backoff?
    WAIT_TIMESPEC = LibC::Timespec.new(tv_sec: 0, tv_nsec: 50_000)
    # WAIT_TIMESPEC = LibC::Timespec.new(tv_sec: 1, tv_nsec: 0)

    getter :ring

    def initialize(context = nil)
      # TODO: Add support for reuse?
      # TODO: Support for size.
      # Other flags necessary? Dunno.
      @ring = IOR::IOUring.new
      # Set up a timeout with userdata 0. There will always be one,
      # and only one of these in flight. The purpose is to allow
      # preemption of other stuff. This also has the upside that we
      # can *always* do a blocking wait. No reason to actually submit
      # it until we may want to wait though.
      @ring.sqe.timeout(pointerof(WAIT_TIMESPEC), user_data: 0)
    end

    def new : self
      self.class.new(self)
    end

    # TODO
    def add_read_event(pollable, fiber, timeout) : Nil
      s = "read event"
      LibC.write(STDOUT.fd, s.to_unsafe, s.size.to_u64)

      raise "fda"
      event = pollable.@read_event.get { Crystal::EventLoop.create_fd_read_event(pollable) }
      event.add timeout
    end

    # TODO
    def add_write_event(pollable, fiber, timeout) : Nil
      s = "write event"
      LibC.write(STDOUT.fd, s.to_unsafe, s.size.to_u64)

      raise "fda"
      event = pollable.@write_event.get { Crystal::EventLoop.create_fd_write_event(pollable) }
      event.add timeout
    end

    def accept(socket, fiber, timeout)
      Crystal::System.print_error "hello\n"
      loop do
        Crystal::System.print_error "wing wait\n"
        # TODO: Timeout..
        # TODO: Error handling if ring is full.
        ring.sqe.accept(socket, user_data: fiber.object_id)
        ring_wait do |cqe|
          Crystal::System.print_error "success\n"
          if cqe.success?
            return cqe.res
          elsif socket.closed?
            return nil
          elsif cqe.eagain?
            next
          else
            raise Socket::ConnectError.from_errno("accept")
          end
        end
      end
    end

    def send(socket, fiber, message, to addr : Socket::Address) : Int32
      slice = message.to_slice
      bytes_sent = LibC.sendto(socket.fd, slice.to_unsafe.as(Void*), slice.size, 0, addr, addr.size)
      raise Socket::Error.from_errno("Error sending datagram to #{addr}") if bytes_sent == -1
      # to_i32 is fine because string/slice sizes are an Int32
      bytes_sent.to_i32
    end

    def send(socket, fiber, slice : Bytes, errno_message : String) : Int32
      socket.evented_send(slice, errno_message) do |slice|
        LibC.send(socket.fd, slice, slice.size, 0)
      end
    end

    def socket_write(socket, fiber, slice : Bytes, errno_message : String) : Nil
      s = "socket write\n"
      LibC.write(STDOUT.fd, s.to_unsafe, s.size.to_u64)

      raise "fda"
      socket.evented_write(slice, errno_message) do |slice|
        LibC.send(socket.fd, slice, slice.size, 0)
      end
    end

    def recv(socket, fiber, slice : Bytes, errno_message : String)
      s = "recv\n"
      LibC.write(STDOUT.fd, s.to_unsafe, s.size.to_u64)

      raise "fda"
      socket.evented_read(slice, errno_message) do
        # Do we need .to_unsafe.as(Void*) ?
        LibC.recv(socket.fd, slice, slice.size, 0).to_i32
      end
    end

    def recvfrom(socket, fiber, slice, sockaddr, addrlen)
      s = "recvfrom\n"
      LibC.write(STDOUT.fd, s.to_unsafe, s.size.to_u64)

      raise "fda"
      socket.evented_read(slice, "Error receiving datagram") do |slice|
        LibC.recvfrom(socket.fd, slice, slice.size, 0, sockaddr, pointerof(addrlen))
      end
    end

    def read(io, fiber, slice : Bytes)
      loop do
        ring.sqe.read(io, slice, user_data: fiber.object_id)
        ring_wait do |cqe|
          if cqe.eagain?
            Fiber.yield
            next
          end
          if cqe.success?
            return cqe.res
          elsif cqe.bad_file_descriptor?
            raise ::IO::Error.new "File not open for reading"
          else
            raise ::IO::Error.new cqe.error_message
          end
        end
      end
    end

    def write(io, fiber, slice : Bytes)
      loop do
        ring.sqe.write(io, slice, user_data: fiber.object_id)
        ring_wait do |cqe|
          if cqe.eagain?
            Fiber.yield
            next
          end
          if cqe.success?
            return cqe.res
          elsif cqe.bad_file_descriptor?
            raise ::IO::Error.new "File not open for writing"
          else
            raise ::IO::Error.new cqe.error_message
          end
        end
      end
    end

    def sleep(fiber, time) : Nil
      Crystal::System.print_error "sleep\n"
      exit
      fiber.resume_event.add(time)
    end

    def yield(fiber)
      ring.sqe.nop(user_data: fiber.object_id)
      ring_wait { }
    end

    def prepare_close(_file)
      # Do we need to cancel pending events on the file?
    end

    def close(fd, fiber)
      ring.sqe.close(fd, user_data: fiber.object_id)
      ring_wait do |cqe|
        return if cqe.success?
        # Fixme: verify?
        return if -cqe.res == Errno::EINTR || -cqe.res == Errno::EINPROGRESS

        raise ::IO::Error.from_errno("Error closing file")
      end
    end

    def reschedule
      # TODO: Keep track of amount in flight.
      loop do
        if runnable = yield
          # Necessary? Or is it good enough to submit if ring is
          # (close to) full? Perhaps that should be a separate context
          # type (or something the context should take as input)? It
          # would be interesting for high IO cases as that would allow
          # higher utilization of the ring.
          ring.submit if ring.unsubmitted?
        else
          # Note that #wait actually don't do a syscall after
          # #submit_and_wait as there is a waiting cqe already.
          ring.submit_and_wait if ring.unsubmitted?
          # TODO: Add lookup table for unprocessed cqes where all
          # unprocessed CQEs are copied into. Needed because current
          # version will either be able to go past the max items in
          # flight, or only have at most 2 items in flight (due to
          # timeout). Which of these depends on if the other branch do
          # ring.submit or not.
          cqe = ring.wait

          if cqe.user_data.zero?
            # That is, CQE is timeout that has expired. Read the
            # timeout and try another iteration and see if anything
            # can be done now.
            ring.seen cqe
            ring.sqe.timeout(pointerof(WAIT_TIMESPEC), user_data: 0)
            next
          end

          runnable = Pointer(Fiber).new(cqe.user_data).as(Fiber)
        end
        runnable.resume unless runnable == Fiber.current
        break
      end
    end

    private def ring_wait
      Crystal::Scheduler.reschedule
      # Assumes reschedule make certain this actually get a cqe
      # without having to wait. Depends on user_data being a pointer
      # to the current Fiber.
      ring.wait do |cqe|
        yield cqe
      end
    end
  end
end

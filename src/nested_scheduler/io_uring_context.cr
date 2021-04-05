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
      # TODO: Timeout..
      # TODO: Error handling if ring is full.
      ring.sqe.accept(socket, user_data: fiber.object_id)
      ring_wait do |cqe|
        if cqe.success?
          return cqe.res
        elsif socket.closed?
          return nil
          #   elsif cqe.eagain?
          #     next
        else
          raise Socket::ConnectError.from_errno("accept", cqe.cqe_errno)
        end
      end
    end

    def send(socket, fiber, message, to addr : Socket::Address) : Int32
      slice = message.to_slice

      # No sendto in uring, falling back to sendmsg.
      vec = LibC::IOVec.new(base: slice.to_unsafe, len: slice.size)
      hdr = LibC::MsgHeader.new(
        name: addr.to_unsafe.as(LibC::SockaddrStorage*),
        namelen: LibC::SocklenT.new(sizeof(LibC::SockaddrStorage)),
        iov: pointerof(vec),
        iovlen: 1
      )

      ring.sqe.sendmsg(socket, pointerof(hdr), user_data: fiber.object_id)
      ring_wait do |cqe|
        if cqe.success?
          cqe.res.to_i32
        else
          raise ::IO::Error.from_errno("Error sending datagram to #{addr}", errno: cqe.cqe_errno)
        end
      end
    end

    def send(socket, fiber, slice : Bytes, errno_message : String) : Int32
      ring.sqe.send(socket, slice, user_data: fiber.object_id)
      ring_wait do |cqe|
        if cqe.success?
          return cqe.res
        else
          raise ::IO::Error.from_errno(errno_message, errno: cqe.cqe_errno)
        end
      end
    end

    # TODO: handle write timeout
    def socket_write(socket, fiber, slice : Bytes, errno_message : String) : Nil
      loop do
        ring.sqe.send(socket, slice, user_data: fiber.object_id)
        ring_wait do |cqe|
          case cqe
          when .success?
            bytes_written = cqe.res
            slice += bytes_written
            return if slice.size == 0
          when .eagain? then next
          else               raise ::IO::Error.from_errno(errno_message, errno: cqe.cqe_errno)
          end
        end
      end
    end

    # TODO: handle read timeout
    def recv(socket, fiber, slice : Bytes, errno_message : String)
      loop do
        ring.sqe.recv(socket, slice, user_data: fiber.object_id)
        ring_wait do |cqe|
          case cqe
          when .success? then return cqe.res
          when .eagain?  then next
          else                raise ::IO::Error.from_errno(errno_message, errno: cqe.cqe_errno)
          end
        end
      end
    end

    # todo timeout.., errmess
    def recvfrom(socket, fiber, slice, sockaddr, addrlen, errno_message : String)
      # No recvfrom in uring, falling back to recvmsg.
      vec = LibC::IOVec.new(base: slice.to_unsafe, len: slice.size)
      hdr = LibC::MsgHeader.new(
        name: sockaddr.as(LibC::SockaddrStorage*),
        namelen: addrlen,
        iov: pointerof(vec),
        iovlen: 1
      )
      # Fixme errono
      loop do
        ring.sqe.recvmsg(socket, pointerof(hdr), user_data: fiber.object_id)
        ring_wait do |cqe|
          case cqe
          when .success? then return cqe.res
          when .eagain?  then next
          else                raise ::IO::Error.from_errno(message: errno_message, errno: cqe.cqe_errno)
          end
        end
      end
    end

    # TODO: handle read timeout
    def read(io, fiber, slice : Bytes)
      # Loop due to EAGAIN. EAGAIN happens at least once during
      # scheduler setup. I'm not totally happy with doing read in a
      # loop like this but I havn't figured out a better way to make
      # it work.
      loop do
        ring.sqe.read(io, slice, user_data: fiber.object_id)
        ring_wait do |cqe|
          case cqe
          when .success?             then return cqe.res
          when .eagain?              then Fiber.yield
          when .bad_file_descriptor? then raise ::IO::Error.new "File not open for reading"
          else                            raise ::IO::Error.new cqe.error_message
          end
        end
      end
    end

    # TODO: add write timeout
    def write(io, fiber, slice : Bytes)
      loop do
        ring.sqe.write(io, slice, user_data: fiber.object_id)
        ring_wait do |cqe|
          case cqe
          when .success?             then return cqe.res
          when .bad_file_descriptor? then raise ::IO::Error.from_errno(message: "File not open for writing", errno: cqe.cqe_errno)
          when .eagain?              then Fiber.yield
          else                            raise ::IO::Error.from_errno(errno: cqe.cqe_errno)
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
        return if cqe.cqe_errno.eintr? || cqe.cqe_errno.einprogress?

        raise ::IO::Error.from_errno("Error closing file", cqe.cqe_errno)
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

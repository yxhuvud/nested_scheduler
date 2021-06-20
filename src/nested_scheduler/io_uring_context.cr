require "./io_context"
require "ior"

module NestedScheduler
  class IoUringContext < IOContext
    # What is a good waittime? Perhaps it needs to be a backoff?
    WAIT_TIMESPEC = LibC::Timespec.new(tv_sec: 0, tv_nsec: 50_000)
    # WAIT_TIMESPEC = LibC::Timespec.new(tv_sec: 1, tv_nsec: 0)

    getter :ring

    #    getter :scheduler ::Crystal::Scheduler

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

    def wait_readable(io, scheduler, timeout)
      # TODO: Actually do timeouts.
      ring.sqe.poll_add(io, user_data: userdata(scheduler))
      ring_wait do |cqe|
        yield if cqe.canceled?
        raise ::IO::Error.from_errno("poll", cqe.cqe_errno) unless cqe.success?
      end
    end

    def wait_writable(io, scheduler, timeout)
      # TODO: Actually do timeouts..
      ring.sqe.poll_add(io, :POLLOUT, user_data: userdata(scheduler))
      ring_wait do |cqe|
        yield if cqe.canceled?
        Crystal::System.print_error "\nsay wat\n"
        raise ::IO::Error.from_errno("poll", cqe.cqe_errno) unless cqe.success?
      end
    end

    def accept(socket, scheduler, timeout)
      # TODO: Timeout..
      #  loop do
      ring.sqe.accept(socket, user_data: userdata(scheduler))
      ring_wait do |cqe|
        if cqe.success?
          return cqe.res
        elsif socket.closed?
          return nil
          #    elsif cqe.eagain? # must be only non-escaping branch
        else
          raise Socket::ConnectError.from_errno("accept", cqe.cqe_errno)
          #  exit
        end
      end
      # Crystal::System.print_error "t"
      # # Nonblocking sockets return EAGAIN if there isn't an
      # # active connection attempt. To detect that wait_readable
      # # is needed but that needs to happen outside ring_wait due
      # # to the cqe needs to be marked as seen.
      # Crystal::System.print_error socket.blocking.to_s
      # wait_readable(socket, scheduler, timeout) do
      #   raise Socket::TimeoutError.new("Accept timed out")
      # end
      # end
    end

    def send(socket, scheduler, message, to addr : Socket::Address) : Int32
      slice = message.to_slice

      # No sendto in uring, falling back to sendmsg.
      vec = LibC::IOVec.new(base: slice.to_unsafe, len: slice.size)
      hdr = LibC::MsgHeader.new(
        name: addr.to_unsafe.as(LibC::SockaddrStorage*),
        namelen: LibC::SocklenT.new(sizeof(LibC::SockaddrStorage)),
        iov: pointerof(vec),
        iovlen: 1
      )

      ring.sqe.sendmsg(socket, pointerof(hdr), user_data: userdata(scheduler))
      ring_wait do |cqe|
        if cqe.success?
          cqe.res.to_i32
        else
          raise ::IO::Error.from_errno("Error sending datagram to #{addr}", errno: cqe.cqe_errno)
        end
      end
    end

    def send(socket, scheduler, slice : Bytes, errno_message : String) : Int32
      ring.sqe.send(socket, slice, user_data: userdata(scheduler))
      ring_wait do |cqe|
        if cqe.success?
          return cqe.res
        else
          raise ::IO::Error.from_errno(errno_message, errno: cqe.cqe_errno)
        end
      end
    end

    # TODO: handle write timeout, errmess
    def socket_write(socket, scheduler, slice : Bytes, errno_message : String) : Nil
      loop do
        ring.sqe.send(socket, slice, user_data: userdata(scheduler))
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
    def recv(socket, scheduler, slice : Bytes, errno_message : String)
      loop do
        ring.sqe.recv(socket, slice, user_data: userdata(scheduler))
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
    def recvfrom(socket, scheduler, slice, sockaddr, addrlen, errno_message : String)
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
        ring.sqe.recvmsg(socket, pointerof(hdr), user_data: userdata(scheduler))
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
    def read(io, scheduler, slice : Bytes)
      # Loop due to EAGAIN. EAGAIN happens at least once during
      # scheduler setup. I'm not totally happy with doing read in a
      # loop like this but I havn't figured out a better way to make
      # it work.
      loop do
        ring.sqe.read(io, slice, user_data: userdata(scheduler))
        ring_wait do |cqe|
          case cqe
          when .success? then return cqe.res
          when .eagain?
          when .bad_file_descriptor? then raise ::IO::Error.from_errno(message: "File not open for reading", errno: cqe.cqe_errno)
          else                            raise ::IO::Error.from_errno(errno: cqe.cqe_errno)
          end
        end
      end
    end

    # TODO: add write timeout
    def write(io, scheduler, slice : Bytes)
      loop do
        ring.sqe.write(io, slice, user_data: userdata(scheduler))
        ring_wait do |cqe|
          case cqe
          when .success? then return cqe.res
          when .eagain?
          when .bad_file_descriptor? then raise ::IO::Error.from_errno(message: "File not open for writing", errno: cqe.cqe_errno)
          else                            raise ::IO::Error.from_errno(errno: cqe.cqe_errno)
          end
        end
      end
    end

    def sleep(scheduler, fiber, time) : Nil
      ts = LibC::Timespec.new(tv_sec: 0, tv_nsec: 50_000)

      timespec = LibC::Timespec.new(
        tv_sec: LibC::TimeT.new(time.to_i),
        tv_nsec: time.nanoseconds
      )
      ring.sqe.timeout(pointerof(timespec), user_data: userdata(fiber))
      ring_wait(scheduler: scheduler) { }
    end

    def yield(scheduler, fiber)
      ring.sqe.nop(user_data: userdata(fiber))
      ring_wait(scheduler: scheduler) { }
    end

    def yield(fiber, to other)
      ring.sqe.nop(user_data: userdata(fiber))
      # Normally reschedule submits but here the scheduler resumes
      # explicitly.
      ring.submit
    end

    def prepare_close(_file)
      #      Crystal::System.print_error "prep close"
      # Do we need to cancel pending events on the file?
    end

    def close(fd, scheduler)
      ring.sqe.close(fd, user_data: userdata(scheduler))
      ring_wait do |cqe|
        return if cqe.success?
        return if cqe.cqe_errno.eintr? || cqe.cqe_errno.einprogress?

        raise ::IO::Error.from_errno("Error closing file", cqe.cqe_errno)
      end
    end

    def reschedule
      # Controls the ring submit as the submit_and_wait variant saves
      # us a syscall.
      loop do
        if runnable = yield
          # Submits the SQE to make certain progress is made - this
          # should make latency a bit more predictable than if
          # multiple SQEs were batched together.

          # Batching several (unrelated nonlinked) SQEs could make
          # sense in certain contexts as it could improve the
          # throughput, but lets avoid that for the basic case.
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
          # ring.submit or not. Requires ior support for iteration.
          cqe = ring.wait

          if cqe.user_data.zero?
            # That is, CQE is timeout that has expired. Read the
            # timeout and try another iteration and see if anything
            # can be done now.

            # TODO: Instead of recurring timeouts like this, make use
            # of the new timeouts on submit_and_wait
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

    private def ring_wait(scheduler = nil)
      if scheduler
        scheduler.actually_reschedule
      else
        Crystal::Scheduler.reschedule
      end

      # Assumes reschedule make certain this actually get a cqe
      # without having to wait. Depends on user_data being a pointer
      # to the current Fiber.
      ring.wait do |cqe|
        yield cqe
      end
    end

    @[AlwaysInline]
    private def userdata(scheduler : Crystal::Scheduler)
      scheduler.@current.object_id
    end

    @[AlwaysInline]
    private def userdata(fiber : Fiber)
      fiber.object_id
    end
  end
end

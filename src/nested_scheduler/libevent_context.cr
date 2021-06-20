require "./io_context"

module NestedScheduler
  class LibeventContext < IOContext
    def new : self
      self
    end

    def wait_readable(io, scheduler, timeout)
      readers = io.@readers.get { Deque(Fiber).new }
      readers << Fiber.current
      # add_read_event inlined:
      event = io.@read_event.get { Crystal::EventLoop.create_fd_read_event(io) }
      event.add timeout

      scheduler.actually_reschedule

      if io.@read_timed_out
        io.read_timed_out = false
        yield
      end
    end

    def wait_writable(io, scheduler, timeout)
      writers = io.@writers.get { Deque(Fiber).new }
      writers << Fiber.current
      # add_write_event inlined.
      event = io.@write_event.get { Crystal::EventLoop.create_fd_write_event(io) }
      event.add timeout

      scheduler.actually_reschedule

      if io.@write_timed_out
        io.write_timed_out = false
        yield
      end
    end

    def accept(socket, _scheduler, timeout)
      loop do
        client_fd = LibC.accept(socket.fd, nil, nil)

        if client_fd == -1
          if socket.closed?
            return
          elsif Errno.value == Errno::EAGAIN
            wait_readable(socket, _scheduler, timeout) do
              raise Socket::TimeoutError.new("Accept timed out")
            end
            return if socket.closed?
          else
            raise Socket::ConnectError.from_errno("accept")
          end
        else
          return client_fd
        end
      end
    end

    def connect(socket, _scheduler, addr, timeout)
      timeout = timeout.seconds unless timeout.is_a? Time::Span | Nil
      loop do
        if LibC.connect(socket.fd, addr, addr.size) == 0
          return
        end
        case Errno.value
        when Errno::EISCONN
          return
        when Errno::EINPROGRESS, Errno::EALREADY
          wait_writable(socket, _scheduler, timeout: timeout) do
            return yield ::IO::TimeoutError.new("connect timed out")
          end
        else
          return yield Socket::ConnectError.from_errno("connect")
        end
      end
    end

    def send(socket, _scheduler, message, to addr : Socket::Address) : Int32
      slice = message.to_slice
      bytes_sent = LibC.sendto(socket.fd, slice.to_unsafe.as(Void*), slice.size, 0, addr, addr.size)
      raise Socket::Error.from_errno("Error sending datagram to #{addr}") if bytes_sent == -1
      # to_i32 is fine because string/slice sizes are an Int32
      bytes_sent.to_i32
    end

    def send(socket, _scheduler, slice : Bytes, errno_message : String) : Int32
      socket.evented_send(slice, errno_message) do |slice|
        LibC.send(socket.fd, slice, slice.size, 0)
      end
    end

    def socket_write(socket, _scheduler, slice : Bytes, errno_message : String) : Nil
      socket.evented_write(slice, errno_message) do |slice|
        LibC.send(socket.fd, slice, slice.size, 0)
      end
    end

    def recv(socket, _scheduler, slice : Bytes, errno_message : String)
      socket.evented_read(slice, errno_message) do
        # Do we need .to_unsafe.as(Void*) ?
        LibC.recv(socket.fd, slice, slice.size, 0).to_i32
      end
    end

    def recvfrom(socket, _scheduler, slice, sockaddr, addrlen, errno_message)
      socket.evented_read(slice, errno_message) do |slice|
        LibC.recvfrom(socket.fd, slice, slice.size, 0, sockaddr, pointerof(addrlen))
      end
    end

    def read(io, _scheduler, slice : Bytes)
      io.evented_read(slice, "Error reading file") do
        LibC.read(io.fd, slice, slice.size).tap do |return_code|
          if return_code == -1 && Errno.value == Errno::EBADF
            raise ::IO::Error.new "File not open for reading"
          end
        end
      end
    end

    def write(io, _scheduler, slice : Bytes)
      io.evented_write(slice, "Error writing file") do |slice|
        LibC.write(io.fd, slice, slice.size).tap do |return_code|
          if return_code == -1 && Errno.value == Errno::EBADF
            raise ::IO::Error.new "File not open for writing"
          end
        end
      end
    end

    def sleep(scheduler, fiber, time) : Nil
      fiber.resume_event.add(time)
      scheduler.actually_reschedule
    end

    def yield(scheduler, fiber)
      self.sleep(scheduler, fiber, 0.seconds)
    end

    def yield(fiber : Fiber, to other)
      fiber.resume_event.add(0.seconds)
    end

    def prepare_close(file)
      file.evented_close
    end

    def close(fd, _scheduler)
      if LibC.close(fd) != 0
        case Errno.value
        when Errno::EINTR, Errno::EINPROGRESS
          # ignore
        else
          raise ::IO::Error.from_errno("Error closing file")
        end
      end
    end

    def reschedule(_scheduler)
      loop do
        if runnable = yield
          unless runnable == Fiber.current
            runnable.resume
          end
          return
        else
          Crystal::EventLoop.run_once
        end
      end
    end
  end
end

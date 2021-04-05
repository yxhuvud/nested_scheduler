require "./io_context"

module NestedScheduler
  class LibeventContext < IOContext
    def new : self
      self
    end

    def add_read_event(pollable, _fiber, timeout) : Nil
      event = pollable.@read_event.get { Crystal::EventLoop.create_fd_read_event(pollable) }
      event.add timeout
    end

    def add_write_event(pollable, _fiber, timeout) : Nil
      event = pollable.@write_event.get { Crystal::EventLoop.create_fd_write_event(pollable) }
      event.add timeout
    end

    def accept(socket, _fiber, timeout)
      loop do
        client_fd = LibC.accept(socket.fd, nil, nil)
        if client_fd == -1
          if socket.closed?
            return
          elsif Errno.value == Errno::EAGAIN
            # Slightly ping-pongy flow control here unfortunately.
            # This ends up calling Socket#add_read_event in
            # Socket#wait_readable which in turn call #add_read_event
            # above.
            # TODO: Improve this, once io_uring is supported and we
            # have full picture. This would avoid having to do
            # dispatch on the union type of io_contexts..
            socket.wait_readable(timeout: timeout, raise_if_closed: false) do
              raise ::IO::TimeoutError.new("Accept timed out")
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

    def send(socket, _fiber, message, to addr : Socket::Address) : Int32
      slice = message.to_slice
      bytes_sent = LibC.sendto(socket.fd, slice.to_unsafe.as(Void*), slice.size, 0, addr, addr.size)
      raise Socket::Error.from_errno("Error sending datagram to #{addr}") if bytes_sent == -1
      # to_i32 is fine because string/slice sizes are an Int32
      bytes_sent.to_i32
    end

    def send(socket, _fiber, slice : Bytes, errno_message : String) : Int32
      socket.evented_send(slice, errno_message) do |slice|
        LibC.send(socket.fd, slice, slice.size, 0)
      end
    end

    def socket_write(socket, _fiber, slice : Bytes, errno_message : String) : Nil
      socket.evented_write(slice, errno_message) do |slice|
        LibC.send(socket.fd, slice, slice.size, 0)
      end
    end

    def recv(socket, _fiber, slice : Bytes, errno_message : String)
      socket.evented_read(slice, errno_message) do
        # Do we need .to_unsafe.as(Void*) ?
        LibC.recv(socket.fd, slice, slice.size, 0).to_i32
      end
    end

    def recvfrom(socket, _fiber, slice, sockaddr, addrlen, errno_message)
      socket.evented_read(slice, errno_message) do |slice|
        LibC.recvfrom(socket.fd, slice, slice.size, 0, sockaddr, pointerof(addrlen))
      end
    end

    def read(io, _fiber, slice : Bytes)
      io.evented_read(slice, "Error reading file") do
        LibC.read(io.fd, slice, slice.size).tap do |return_code|
          if return_code == -1 && Errno.value == Errno::EBADF
            raise ::IO::Error.new "File not open for reading"
          end
        end
      end
    end

    def write(io, _fiber, slice : Bytes)
      io.evented_write(slice, "Error writing file") do |slice|
        LibC.write(io.fd, slice, slice.size).tap do |return_code|
          if return_code == -1 && Errno.value == Errno::EBADF
            raise ::IO::Error.new "File not open for writing"
          end
        end
      end
    end

    def sleep(fiber, time) : Nil
      fiber.resume_event.add(time)
    end

    def yield(fiber)
      sleep(fiber, 0.seconds)
    end

    def prepare_close(file)
      file.evented_close
    end

    def close(fd, _fiber)
      if LibC.close(fd) != 0
        case Errno.value
        when Errno::EINTR, Errno::EINPROGRESS
          # ignore
        else
          raise ::IO::Error.from_errno("Error closing file")
        end
      end
    end

    def reschedule
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

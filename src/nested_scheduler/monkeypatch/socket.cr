require "socket"

class Socket < IO
  include NestedScheduler::IOContext::IO

  def accept_impl
    io, fiber = context
    io.accept(self, fiber, @read_timeout)
  end

  def send(message) : Int32
    io, fiber = context
    io.send(self, fiber, message.to_slice, "Error sending datagram")
  end

  def send(message, to addr : Address) : Int32
    io, fiber = context
    io.send(self, fiber, message, addr)
  end

  private def unbuffered_read(slice : Bytes)
    io, fiber = context
    io.recv(self, fiber, slice, "Error reading socket")
  end

  private def unbuffered_write(slice : Bytes)
    io, fiber = context
    io.socket_write(self, fiber, slice, "Error writing to socket")
  end

  protected def recvfrom(slice)
    io, fiber = context
    # we will see if these will have to be moved into the context
    sockaddr = Pointer(LibC::SockaddrStorage).malloc.as(LibC::Sockaddr*)
    addrlen = LibC::SocklenT.new(sizeof(LibC::SockaddrStorage))
    # initialize sockaddr with the initialized family of the socket
    copy = sockaddr.value
    copy.sa_family = family
    sockaddr.value = copy

    bytes_read = io.recvfrom(self, fiber, slice, sockaddr, addrlen, "Error receiving datagram")

    {bytes_read, sockaddr, addrlen}
  end

  # candidates:
  # require DNS:
  # def connect(host : String, port : Int, connect_timeout = nil)

  # def connect(addr, timeout = nil)

  # private def shutdown(how) # doesnt
  # private def unbuffered_close # for line that do libc.close x_x
  # evented_close
end

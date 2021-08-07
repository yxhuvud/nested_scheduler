require "socket"

module Crystal::System::Socket
  include NestedScheduler::IOContext::IO

  def system_accept
    io, scheduler = context
    io.accept(self, scheduler, @read_timeout)
  end

  def system_send(bytes : Bytes) : Int32
    io, scheduler = context
    io.send(self, scheduler, bytes, "Error sending datagram")
  end

  def system_send_to(bytes : Bytes, addr : ::Socket::Address) : Int32
    io, scheduler = context
    io.send_to(self, scheduler, bytes, addr)
  end

  private def unbuffered_read(slice : Bytes)
    io, scheduler = context
    io.recv(self, scheduler, slice, "Error reading socket")
  end

  private def unbuffered_write(slice : Bytes)
    io, scheduler = context
    io.socket_write(self, scheduler, slice, "Error writing to socket")
  end

  protected def system_receive(slice)
    io, scheduler = context
    # we will see if these will have to be moved into the context
    sockaddr = Pointer(LibC::SockaddrStorage).malloc.as(LibC::Sockaddr*)
    # initialize sockaddr with the initialized family of the socket
    copy = sockaddr.value
    copy.sa_family = family
    sockaddr.value = copy

    addrlen = LibC::SocklenT.new(sizeof(LibC::SockaddrStorage))

    bytes_read = io.recvfrom(self, scheduler, slice, sockaddr, addrlen, "Error receiving datagram")

    {bytes_read, sockaddr, addrlen}
  end

  def system_connect(addr, timeout = nil)
    timeout = timeout.seconds unless timeout.is_a? ::Time::Span | Nil
    io, scheduler = context

    io.connect(self, scheduler, addr, timeout) do |error|
      yield error
    end
  end

  # def system_bind
  # def system_listen
  # def system_close_read
  # def system_close_write
  # def system_reuse_port?
  # def system_reuse_port=
  # def system_close
  # private def shutdown(how) # doesnt
  # private def unbuffered_close # for line that do libc.close x_x
end

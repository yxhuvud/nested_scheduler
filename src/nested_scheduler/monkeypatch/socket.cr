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

  private def system_close
    io, scheduler = context
    # Perform libevent cleanup before LibC.close. Using a file
    # descriptor after it has been closed is never defined and can
    # always lead to undefined results as the system may reuse the fd.
    # This is not specific to libevent.

    # However, will io_uring automatically cancel all outstanding ops or
    # would that be a race condintion? Who knows, not I.
    io.prepare_close(self)

    # Clear the @volatile_fd before actually closing it in order to
    # reduce the chance of reading an outdated fd value
    _fd = @volatile_fd.swap(-1)
    io, scheduler = context
    io.close(_fd, scheduler)
  end

  # def system_bind
  # def system_listen
  # def system_close_read
  # def system_close_write
  # def system_reuse_port?
  # def system_reuse_port=
  # private def shutdown(how) # doesnt
end

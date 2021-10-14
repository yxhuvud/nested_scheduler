module Crystal::System::FileDescriptor
  include NestedScheduler::IOContext::IO

  # TODO: Half the file belongs in libevent_context..

  private def unbuffered_read(slice : Bytes)
    io, scheduler = context
    io.read(self, scheduler, slice)
  end

  private def unbuffered_write(slice : Bytes)
    io, scheduler = context

    io.write(self, scheduler, slice)
  end

  private def system_info
    #  raise "TODO"
    if LibC.fstat(fd, out stat) != 0
      raise IO::Error.from_errno("Unable to get info")
    end

    FileInfo.new(stat)
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

  def self.pread(fd, buffer, offset)
    # raise "TODO"
    bytes_read = LibC.pread(fd, buffer, buffer.size, offset)

    if bytes_read == -1
      raise IO::Error.from_errno "Error reading file"
    end

    bytes_read
  end

  def self.pipe(read_blocking, write_blocking)
    pipe_fds = uninitialized StaticArray(LibC::Int, 2)
    if LibC.pipe(pipe_fds) != 0
      raise IO::Error.from_errno("Could not create pipe")
    end

    r = IO::FileDescriptor.new(pipe_fds[0], read_blocking)
    w = IO::FileDescriptor.new(pipe_fds[1], write_blocking)
    r.close_on_exec = true
    w.close_on_exec = true
    w.sync = true

    {r, w}
  end
end

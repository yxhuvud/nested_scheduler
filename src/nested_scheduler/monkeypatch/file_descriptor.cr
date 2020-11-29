module Crystal::System::FileDescriptor
  include NestedScheduler::IOContext::IO
  
  # TODO: Half the file belongs in libevent_context..

  private def unbuffered_read(slice : Bytes)
    io, fiber = context
    io.read(self, fiber, slice)
  end

  private def unbuffered_write(slice : Bytes)
    io, fiber = context

    io.write(self, fiber, slice)
  end

  private def system_info
  #  raise "TODO"
    if LibC.fstat(fd, out stat) != 0
      raise IO::Error.from_errno("Unable to get info")
    end

    FileInfo.new(stat)
  end

  private def system_close
      s = "system_close\n"
      LibC.write(STDOUT.fd, s.to_unsafe, s.size.to_u64)

    raise "TODO"
    # Perform libevent cleanup before LibC.close.
    # Using a file descriptor after it has been closed is never defined and can
    # always lead to undefined results. This is not specific to libevent.
    evented_close

    file_descriptor_close
  end

  def file_descriptor_close
   # raise "TODO"
    # Clear the @volatile_fd before actually closing it in order to
    # reduce the chance of reading an outdated fd value
    _fd = @volatile_fd.swap(-1)

    if LibC.close(_fd) != 0
      case Errno.value
      when Errno::EINTR, Errno::EINPROGRESS
        # ignore
      else
        raise IO::Error.from_errno("Error closing file")
      end
    end
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

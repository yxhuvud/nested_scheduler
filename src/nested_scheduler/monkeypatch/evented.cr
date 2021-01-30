
# Ideally, this class should not need to be monkeypatched but simply used by the libevent_context, 
module IO::Evented
  private def add_read_event(timeout = @read_timeout) : Nil
    io, fiber = context
    io.add_read_event(self, fiber, timeout)
  end

  private def add_write_event(timeout = @write_timeout) : Nil
    io, fiber = context
    io.add_write_event(self, fiber, timeout)
  end
end

# Ideally, this class should not need to be monkeypatched but simply used by the libevent_context,
require "io/evented"

module IO::Evented
  setter write_timed_out
  setter read_timed_out

  def wait_readable(timeout = @read_timeout, *, raise_if_closed = true) : Nil
    io, scheduler = context

    io.wait_readable(self, scheduler, timeout) do
      yield
    end

    check_open if raise_if_closed
  end

  # :nodoc:
  def wait_writable(timeout = @write_timeout) : Nil
    io, scheduler = context

    io.wait_writable(self, scheduler, timeout) do
      yield
    end

    check_open
  end
end

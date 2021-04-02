require "crystal/fiber_channel"

struct Crystal::FiberChannel
  def close
    @worker_in.close
  end
end

require "crystal/fiber_channel"

struct Crystal::FiberChannel
  def close
    @worker_in.write_bytes 0u64
  end

  def receive : Fiber?
    oid = @worker_out.read_bytes(UInt64)
    if oid.zero?
      @worker_out.close
      @worker_in.close
      nil
    else
      Pointer(Fiber).new(oid).as(Fiber)
    end
  end
end

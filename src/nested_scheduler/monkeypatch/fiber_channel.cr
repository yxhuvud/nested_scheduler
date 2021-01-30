struct Crystal::FiberChannel
  def send(fiber : Fiber)
    @worker_in.write_bytes(fiber.object_id)
  end

  def receive
    oid = @worker_out.read_bytes(UInt64)
    Pointer(Fiber).new(oid).as(Fiber)
  end
end

def spawn(*, name : String? = nil, same_thread = false, &block) : Fiber
  if pool = Thread.current.scheduler.pool
    pool.spawn(name: name, same_thread: same_thread, &block)
  else
    # Fiber Clean Loop and Signal Loop are set up before any pool is
    # initiated. Handle these separately.
    fiber = Fiber.new(name, &block)
    fiber.helper_fiber = true
    Crystal::Scheduler.enqueue fiber
    fiber
  end
end

module Crystal
  def self.main(&block)
    GC.init

    status =
      begin
        yield
        0
      rescue ex
        1
      end

    main_exit(status, ex)
  end

  def self.main_exit(status : Int32, exception : Exception?) : Int32
    status = Crystal::AtExitHandlers.run status, exception
    # Exit handlers can (and do! For example the whole test suite) spawn new fibers
    Thread.current.scheduler.pool.not_nil!.wait_until_done

    if exception
      STDERR.print "Unhandled exception: "
      exception.inspect_with_backtrace(STDERR)
    end

    ignore_stdio_errors { STDOUT.flush }
    ignore_stdio_errors { STDERR.flush }

    status
  end
end

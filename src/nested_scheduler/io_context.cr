module NestedScheduler # struct?
  abstract class IOContext
    abstract def new : self

    module IO
      @[AlwaysInline]
      protected def context
        scheduler = Thread.current.scheduler
        io = scheduler.io || raise "BUG: No io context when required"
        {io, scheduler}
      end
    end
  end
end

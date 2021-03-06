require "fiber"
require "./scheduler"

class Fiber
  # For thread pool fiber list
  property next2 : Fiber?
  property previous2 : Fiber?

  def run
    GC.unlock_read
    @proc.call
  rescue ex
    # TODO: Push to thread pool.
    Crystal::System.print_error "fiber run: #{name}.\n"
    if name = @name
      STDERR.print "Unhandled exception in spawn(name: #{name}): "
    else
      STDERR.print "Unhandled exception in spawn: "
    end
    ex.inspect_with_backtrace(STDERR)
    STDERR.flush
  ensure
    @alive = false
    cleanup
    Crystal::Scheduler.reschedule
  end

  def cleanup
    scheduler = Thread.current.scheduler
    # Sigh, scheduler.enqueue_free_stack is protected.
    Crystal::Scheduler.enqueue_free_stack @stack
    # Remove the current fiber from the linked list
    Fiber.fibers.delete(self)
    # monkeypatch: Is this safe with regards to thread lifecycle? Dunno.
    if pool = scheduler.pool
      pool.unregister_fiber(self)
    end
    # Delete the resume event if it was used by `yield` or `sleep`
    @resume_event.try &.free
    @timeout_event.try &.free
    @timeout_select_action = nil
    # Sigh, scheduler.enqueue_free_stack is protected.
    Crystal::Scheduler.enqueue_free_stack @stack
  end

  # TODO: move to io context
  def resume_event
    if p = Thread.current.scheduler.pool
      if p.io_context.class == NestedScheduler::IoUringContext
        Crystal::System.print_error "TODO RE\n"
        exit
      end
    end
    @resume_event ||= Crystal::EventLoop.create_resume_event(self)
  end

  # TODO: move to io context
  def timeout_event
    if p = Thread.current.scheduler.pool
      if p.io_context.class == NestedScheduler::IoUringContext
        Crystal::System.print_error "TODO TE\n"
        exit
      end
    end

    @timeout_event ||= Crystal::EventLoop.create_timeout_event(self)
  end
end

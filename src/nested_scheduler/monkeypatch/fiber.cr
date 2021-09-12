require "fiber"
require "./scheduler"

class Fiber
  # A helper fiber is a fiber which don't block thread pool exit.
  property helper_fiber : Bool
  @helper_fiber = false

  # For thread pool fiber list
  property next2 : Fiber?
  property previous2 : Fiber?

  def run
    GC.unlock_read
    @proc.call
  rescue ex
    with_pool { |pool| pool.result_handler.register_error(pool, self, ex) }
  ensure
    @alive = false
    cleanup
    Crystal::Scheduler.reschedule
  end

  def cleanup
    # Remove the current fiber from the linked list
    Fiber.fibers.delete(self)
    with_pool { |pool| pool.unregister_fiber(self) }
    # Delete the resume event if it was used by `yield` or `sleep`
    @resume_event.try &.free
    @timeout_event.try &.free
    @timeout_select_action = nil
    # Sigh, scheduler.enqueue_free_stack is protected.
    Crystal::Scheduler.enqueue_free_stack @stack
  end

  private def with_pool
    scheduler = Thread.current.scheduler
    # monkeypatch: Is this safe with regards to thread lifecycle? Dunno.
    if pool = scheduler.pool
      yield pool
    end
  end
end

require "fiber"
require "./scheduler"

class Fiber
  def self.inactive(fiber : Fiber)
    fibers.delete(fiber)
    # monkeypatch: Is this safe with regards to thread lifecycle? Dunno.
    if pool = Thread.current.scheduler.pool
      pool.unregister_fiber(fiber)
    end
  end

    # :nodoc:
  def run
    GC.unlock_read
    @proc.call
  rescue ex
    if name = @name
      STDERR.print "Unhandled exception in spawn(name: #{name}): "
    else
      STDERR.print "Unhandled exception in spawn: "
    end
    ex.inspect_with_backtrace(STDERR)
    STDERR.flush
  ensure
    {% if flag?(:preview_mt) %}
      Crystal::Scheduler.enqueue_free_stack @stack
    {% else %}
      Fiber.stack_pool.release(@stack)
    {% end %}
    # Remove the current fiber from the linked list
    ## NOTE by monkeypatch: following line is the changed one:
    Fiber.inactive(self)
    # Delete the resume event if it was used by `yield` or `sleep`
    @resume_event.try &.free
    @timeout_event.try &.free
    @timeout_select_action = nil

    @alive = false
    Crystal::Scheduler.reschedule
  end

  # Fixme:  resume_event  timeout_event
  
end

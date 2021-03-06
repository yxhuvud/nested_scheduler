require "crystal/system/thread"
require "crystal/scheduler"
require "../thread_pool"
require "../io_context"
require "../libevent_context"
require "../io_uring_context"

class ::Crystal::Scheduler
  property pool : ::NestedScheduler::ThreadPool?
  # TODO: Move io_context to Thread?
  property io_context : ::NestedScheduler::IOContext?

  def io : NestedScheduler::IOContext
    # Unfortunately I havn't figured out exactly where this is called
    # the first time (it doesn't help that the stacktrace I get don't
    # have line numbers), and as it is called sometime *before*
    # init_workers, I have no choice but to have a fallback :(.
    if context = io_context
      return context
    end
    self.io_context = NestedScheduler::LibeventContext.new
    # raise "IO Context Not yet initialized, BUG"
  end

  protected def find_target_thread
    pool.try { |p| p.next_thread! } || Thread.current
  end

  # doesn't seem to be possible to monkey patch visibility status.
  def actually_enqueue(fiber : Fiber) : Nil
    enqueue fiber
  end

  # doesn't seem to be possible to monkey patch visibility status.
  def actually_reschedule : Nil
    reschedule
  end

  def self.init_workers
    NestedScheduler::ThreadPool.new(
      NestedScheduler::LibeventContext.new,
      worker_count,
      bootstrap: true,
      name: "Root Pool"
    )
  end

  def run_loop
    loop do
      @lock.lock
      if runnable = @runnables.shift?
        @runnables << Fiber.current
        @lock.unlock
        runnable.resume
      else
        @sleeping = true
        @lock.unlock
        fiber = @fiber_channel.receive
        @lock.lock
        @sleeping = false
        @runnables << Fiber.current
        @lock.unlock
        fiber.resume
      end
    end
  end

  protected def reschedule : Nil
    io.reschedule { @lock.sync { @runnables.shift? } }

    release_free_stacks
  end

  protected def sleep(time : Time::Span) : Nil
    io.sleep(self, @current, time)
  end

  protected def yield : Nil
    io.yield(self, @current)
  end

  protected def yield(fiber : Fiber) : Nil
    io.yield(@current, to: fiber)
    resume(other)
  end

  # Expected to be called from outside and that the scheduler is
  # waiting to receive fibers through the channel. Assumes there is no
  # work left.
  def shutdown
    @fiber_channel.close
  end
end

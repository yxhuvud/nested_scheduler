require "crystal/system/thread"
require "crystal/scheduler"
require "../thread_pool"
require "../io_context"
require "../libevent_context"
require "../result"
require "../results/*"

class ::Crystal::Scheduler
  property pool : ::NestedScheduler::ThreadPool?

  def pool!
    pool || raise "BUG"
  end

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
      NestedScheduler::Results::ErrorPropagator.new,
      worker_count,
      bootstrap: true,
      name: "Root Pool"
    )
  end

  def run_loop
    fiber_channel = self.fiber_channel
    loop do
      @lock.lock
      if runnable = @runnables.shift?
        @runnables << Fiber.current
        @lock.unlock
        runnable.resume
      else
        @sleeping = true
        @lock.unlock
        unless fiber = fiber_channel.receive
          # Thread pool has signaled that it is time to shutdown in wait_until_done.
          # Do note that wait_until_done happens in the nursery origin thread.
          io.stop
          return
        end
        @lock.lock
        @sleeping = false
        @runnables << Fiber.current
        @lock.unlock
        fiber.resume
      end
    end
  end

  def populate_fiber_channel
    fiber_channel
  end

  protected def reschedule : Nil
    io.reschedule(self) { @lock.sync { @runnables.shift? } }

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
    resume(fiber)
  end

  # Expected to be called from outside and that the scheduler is
  # waiting to receive fibers through the channel. Assumes there is no
  # work left.
  def shutdown
    fiber_channel.close
  end
end

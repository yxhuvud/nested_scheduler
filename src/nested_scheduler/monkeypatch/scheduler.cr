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

  def io
    io_context || raise "IO Context Not yet initialized, BUG"
  end

  protected def find_target_thread
    pool.try { |p| p.next_thread! } || Thread.current
  end

  # doesn't seem to be possible to monkey patch visibility status.
  def actually_enqueue(fiber : Fiber) : Nil
    enqueue fiber
  end

  def self.init_workers
    NestedScheduler::ThreadPool.new(
      NestedScheduler::LibeventContext.new,
      worker_count, bootstrap: true, name: "Root Pool"
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
    io.sleep(@current, time)
    reschedule
  end

  protected def yield : Nil
    io.yield(@current)
  end

  protected def yield(fiber : Fiber) : Nil
    io.yield(@current)
    resume(fiber)
  end
end

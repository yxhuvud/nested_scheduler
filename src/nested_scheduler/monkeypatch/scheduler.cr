require "crystal/system/thread"
require "crystal/scheduler"
require "../thread_pool"
require "../libevent_context"

class ::Crystal::Scheduler
  property pool : ::NestedScheduler::ThreadPool?
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
    loop do
      if runnable = @lock.sync { @runnables.shift? }
        unless runnable == Fiber.current
          runnable.resume
        end
        break
      else
        Crystal::EventLoop.run_once
      end
    end

    {% if flag?(:preview_mt) %}
      release_free_stacks
    {% end %}
  end

  #  protected def sleep(time : Time::Span) : Nil
  #   @current.resume_event.add(time)
  #   reschedule
  # end

  # enqueue ? - probably not, simply redefining creates issues with libevent?!

end

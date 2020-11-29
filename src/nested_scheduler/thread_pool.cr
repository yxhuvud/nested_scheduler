module NestedScheduler
  class ThreadPool
    WORKER_NAME = "Worker Loop"

    property workers
    property done_channel
    property name : String?
    property fibers
    property spawned

    property io_context : ::NestedScheduler::IOContext

    def self.nursery(thread_count = 1, name = "Child pool", io_context = nil)
      unless io_context
        if p = Thread.current.scheduler.pool
          io_context ||= p.io_context
        end
        raise "Pool missing IO Context" unless io_context
      end
      if thread_count < 1
        raise ArgumentError.new "No support for nested thread pools in same thread yet"
      end
      pool = new(io_context, thread_count, name: name)
      begin
        yield pool
      # TODO: Better exception behavior. Needs to support different
      # kinds of failure modes and stacktrace propagation.
      ensure
        pool.done_channel.receive if pool.spawned.get > 0
      end
    end

    def initialize(io_context : NestedScheduler::IOContext, count = 1, bootstrap = false, @name = nil)
      @io_context = io_context
      @done_channel = Channel(Nil).new
      @rr_target = 0
      @workers = Array(Thread).new(initial_capacity: count)
      @fibers = Thread::LinkedList(Fiber).new
      @spawned = Atomic(Int32).new(0)
      @cancelled = Atomic(Int32).new(0)

      # original init_workers hijack the current thread as part of the
      # bootstrap process. Only do that when actually bootstrapping.
      thread = Thread.current
      if bootstrap
        scheduler = thread.scheduler
        scheduler.pool = self
        scheduler.io_context = io_context.new
        count -= 1
        worker_loop = Fiber.new(name: WORKER_NAME) { thread.scheduler.run_loop }
        @workers << thread
        scheduler.actually_enqueue worker_loop
      end
      pending = Atomic(Int32).new(count)
      count.times do
        @workers << Thread.new do
          scheduler = Thread.current.scheduler
          scheduler.pool = self
          scheduler.io_context = io_context.new
          fiber = scheduler.@current
          fiber.name = WORKER_NAME
          pending.sub(1)
          scheduler.run_loop
        end
      end

      # Wait for all worker threads to be fully ready to be used
      while pending.get > 0
        Fiber.yield
      end
    end

    def next_thread!
      @rr_target &+= 1
      workers[@rr_target % workers.size]
    end

    def spawn(*, name : String? = nil, &block)
      @spawned.add 1
      fiber = Fiber.new(name, &block)
      thread = next_thread!
      if pool = thread.scheduler.pool
        pool.register_fiber(fiber)
      end
      # Until support of embedding a pool in a current pool of
      # schedulers, this will be guaranteed not to be the same
      # thread. Also scheduler.enqueue isn't public so would have to
      # go through Crystal::Scheduler.enqueue, which will enqueue in
      # the scheduler family of the *current* thread. Which is
      # absolutely not what we want.
      thread.scheduler.send_fiber fiber
      fiber
    end

    # Cooperatively cancel the current pool. That means the users of
    # the pool need to actively check if it is cancelled or not.

    # TODO: Investigate cancellation contexts, a la
    # https://vorpus.org/blog/timeouts-and-cancellation-for-humans/
    def cancel
      # TBH, not totally certain it actually needs to be atomic..
      @cancelled.set 1
    end

    # Has the pool been cancelled?
    def cancelled?
      @cancelled.get > 0
    end

    def register_fiber(fiber)
      fibers.push(fiber)
    end

    def unregister_fiber(fiber)
      fibers.delete(fiber)
      old = @spawned.sub(1)
      if old == 1
        done_channel.send(nil)
      end
    end
  end
end

require "concurrent"
require "./linked_list2"
require "./monkeypatch/scheduler"

module NestedScheduler
  class ThreadPool
    enum State
      Ready
      Canceled
      Finishing
      Done
    end

    WORKER_NAME = "Worker Loop"

    property workers
    property done_channel : Channel(Nil)
    property name : String?
    property fibers : NestedScheduler::LinkedList2(Fiber)
    property spawned

    property io_context : ::NestedScheduler::IOContext
    property result_handler : ::NestedScheduler::Result

    def self.nursery(
      thread_count = 1,
      name = "Child pool",
      io_context = nil,
      result_handler = NestedScheduler::Results::ErrorPropagator.new
    )
      if thread_count < 1
        raise ArgumentError.new "No support for nested thread pools in same thread yet"
      end

      unless io_context
        if p = Thread.current.scheduler.pool
          io_context ||= p.io_context
        end
        raise "Pool missing IO Context" unless io_context
      end
      pool = new(io_context, result_handler, thread_count, name: name)
      begin
        yield pool
        # TODO: Better exception behavior. Needs to support different
        # kinds of failure modes and stacktrace propagation.
      ensure
        pool.wait_until_done
      end
      # Unfortunately the result type is a union type of all possible
      # result_handler results, which can become arbitrarily big. If
      # there was some way to ground the type to only what the given
      # result gives, then that would be nice..
      pool.result_handler.result
    end

    # Collects the return values of the fiber blocks, in unspecified order.
    # If an exception happen, it is propagated.
    macro collect(t, **options)
      NestedScheduler::ThreadPool.nursery(
        result_handler: NestedScheduler::Results::ResultCollector({{t.id}}).new,
        {{**options}}
              ) do |pl|
        {{ yield }}
      end.as(Array({{t.id}}))
    end

    def initialize(
      @io_context : NestedScheduler::IOContext,
      @result_handler : NestedScheduler::Result,
      count = 1,
      bootstrap = false,
      @name = nil
    )
      @done_channel = Channel(Nil).new capacity: 1
      @rr_target = 0
      @workers = Array(Thread).new(initial_capacity: count)
      @fibers = NestedScheduler::LinkedList2(Fiber).new
      @spawned = Atomic(Int32).new(0)
      @state = Atomic(State).new(State::Ready)
      # Not using the state, as there would be many different waiting
      # states, ie regular waiting and cancelled waiting.
      @waiting_for_done = Atomic(Int32).new(0)

      if bootstrap
        # original init_workers hijack the current thread as part of the
        # bootstrap process.
        thread = Thread.current
        count -= 1
        scheduler = thread.scheduler
        scheduler.pool = self
        # unfortunately, io happen before init_workers is run, so the
        # bootstrap scheduler needs a context.
        if ctx = scheduler.io_context
          raise "Mismatching io context" if ctx.class != io_context.class
        else
          scheduler.io_context = io_context.new
        end
        worker_loop = Fiber.new(name: WORKER_NAME) { thread.scheduler.run_loop }
        @workers << thread
        scheduler.actually_enqueue worker_loop
      end
      pending = Atomic(Int32).new(count)
      count.times do
        @workers << new_worker(io_context.new) { pending.sub(1) }
      end

      # Wait for all worker threads to be fully ready to be used
      while pending.get > 0
        Fiber.yield
      end
    end

    private def new_worker(io_context, &block)
      Thread.new do
        scheduler = Thread.current.scheduler
        scheduler.pool = self
        scheduler.io_context = io_context
        fiber = scheduler.@current
        fiber.name = WORKER_NAME
        scheduler.populate_fiber_channel
        block.call
        scheduler.run_loop
      end
    end

    def next_thread!
      @rr_target &+= 1
      workers[@rr_target % workers.size]
    end

    def spawn(*, name : String? = nil, same_thread = false, &block : -> _) : Fiber
      unless state.in?({State::Ready, State::Finishing})
        raise "Pool is #{state}, can't spawn more fibers at this point"
      end

      @spawned.add 1
      fiber = Fiber.new(name: name, &result_handler.init(&block))

      thread = resolve_thread(same_thread)
      thread.scheduler.pool!.register_fiber(fiber)
      fiber.@current_thread.set(thread)

      Crystal::Scheduler.enqueue fiber
      fiber
    end

    private def resolve_thread(same_thread)
      if same_thread
        th = Thread.current
        unless th.scheduler.pool == self
          raise "It is not possible to spawn into a different thread pool but keeping the same thread."
        else
          th
        end
      else
        # There is a need to set the thread before calling enqueue
        # because otherwise it will enqueue on calling pool.
        next_thread!
      end
    end

    # Cooperatively cancel the current pool. That means the users of
    # the pool need to actively check if it is canceled or not.

    # TODO: Investigate cancellation contexts, a la
    # https://vorpus.org/blog/timeouts-and-cancellation-for-humans/
    def cancel
      # TBH, not totally certain it actually needs to be atomic..
      return if done?

      self.state = State::Canceled
    end

    # Has the pool been canceled?
    def canceled?
      state.canceled?
    end

    def finishing?
      state.finishing?
    end

    def done?
      state.done?
    end

    def state
      @state.get
    end

    private def state=(new_state : State)
      @state.set new_state
    end

    def register_fiber(fiber)
      fibers.push(fiber)
    end

    def unregister_fiber(fiber)
      fibers.delete(fiber)
      return if fiber.helper_fiber

      previous_running = @spawned.sub(1)

      # This is probably a race condition, but I don't know how to
      # properly fix it. Basically, if several fibers are created and
      # then all finish before waiting_for_done is reached there could
      # be trouble? It is hard to think about unfortunately..

      # If @waiting_for_done == 0, then .nursery block hasn't finished yet,
      # which means there can still be new fibers that are spawned.
      if previous_running == 1 && @waiting_for_done.get > 0
        done_channel.send(nil)
      end
    end

    def inspect
      res = [] of String
      fibers.unsafe_each do |f|
        res << f.inspect
      end
      <<-EOS
        Threadpool #{name}, in #{Fiber.current.name}:
          type:         #{@io_context.class}
          jobs:         #{@spawned.get}
          passed_block: #{@waiting_for_done.get}
          canceled:    #{canceled?}
        \t#{res.join("\n\t")}
      EOS
    end

    def wait_until_done
      @waiting_for_done.set(1)
      self.state = State::Finishing
      # Potentially a race condition together with unregister_fiber?
      done_channel.receive if @spawned.get > 0
      self.state = State::Done
      current = Thread.current
      @workers.each do |th|
        th.scheduler.shutdown unless th == current
      end
    end
  end
end

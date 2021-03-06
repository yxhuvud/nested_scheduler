require "./linked_list2"

module NestedScheduler
  class ThreadPool
    enum State
      Ready
      Canceled
      Done
    end

    WORKER_NAME = "Worker Loop"

    property workers
    property done_channel : Channel(Nil)
    property name : String?
    property fibers : NestedScheduler::LinkedList2(Fiber)
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
        pool.wait_until_done
      end
    end

    def initialize(io_context : NestedScheduler::IOContext, count = 1, bootstrap = false, @name = nil)
      @io_context = io_context
      @done_channel = Channel(Nil).new capacity: 1
      @rr_target = 0
      @workers = Array(Thread).new(initial_capacity: count)
      @fibers = NestedScheduler::LinkedList2(Fiber).new
      @spawned = Atomic(Int32).new(0)
      @waiting_for_done = Atomic(Int32).new(0)
      @state = Atomic(State).new(State::Ready)

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

    def spawn(*, name : String? = nil, same_thread = false, &block)
      @spawned.add 1
      fiber = Fiber.new(name: name, &block)

      thread =
        if same_thread
          unless Thread.current.scheduler.pool == self
            raise "It is not possible to spawn into a different thread pool but keeping the same thread."
          else
            Thread.current
          end
        else
          # There is a need to set the thread before calling enqueue
          # because otherwise it will enqueue on calling pool.
          next_thread!
        end

      if pool = thread.scheduler.pool
        pool.register_fiber(fiber)
      else
        raise "BUG"
      end
      fiber.@current_thread.set(thread)

      Crystal::Scheduler.enqueue fiber
      fiber
    end

    # Cooperatively cancel the current pool. That means the users of
    # the pool need to actively check if it is canceled or not.

    # TODO: Investigate cancellation contexts, a la
    # https://vorpus.org/blog/timeouts-and-cancellation-for-humans/
    def cancel
      # TBH, not totally certain it actually needs to be atomic..
      return if state.done?

      self.state = State::Canceled
    end

    # Has the pool been canceled?
    def canceled?
      state.canceled?
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
      done_channel.receive if @spawned.get > 0
      self.state = State::Done
      @workers.each &.scheduler.shutdown
    end
  end
end

# FIXME: move to better place.
def spawn(*, name : String? = nil, same_thread = false, &block)
  if pool = Thread.current.scheduler.pool
    pool.spawn(name: name, same_thread: same_thread, &block)
  else
    # Fiber Clean Loop and Signal Loop are set up before any pool is
    # initiated. Handle these separately.
    fiber = Fiber.new(name, &block)
    fiber.helper_fiber = true
    Crystal::Scheduler.enqueue fiber
  end
end

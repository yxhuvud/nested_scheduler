module NestedScheduler
  class ThreadPool
    property workers
    property done_channel
    property name : String?
    property fibers
    property spawned

    def self.nursery(thread_count = 1, name = "Child pool")
      raise ArgumentError.new "No support for nested thread pools in same thread yet" if thread_count < 1
      pool = new(thread_count, name: name)
      yield pool
      pool.done_channel.receive if pool.spawned
    end

    def register_fiber(fiber)
      fibers.push(fiber)
    end

    def unregister_fiber(fiber)
      fibers.delete(fiber)
      first = true
      fibers.unsafe_each do
        return unless first
        first = false
      end
      done_channel.send(nil)
    end

    def initialize(count = 1, use_existing_thread = false, @name = nil)
      @done_channel = Channel(Nil).new
      @rr_target = 0
      @workers = Array(Thread).new(initial_capacity: count)
      @fibers = Thread::LinkedList(Fiber).new
      @spawned = false

      if use_existing_thread
        count -= 1
        worker_loop = Fiber.new(name: "Worker Loop") { Thread.current.scheduler.run_loop }
        register_fiber(worker_loop)
        scheduler = Thread.current.scheduler
        scheduler.pool = self
        @workers << Thread.current
        scheduler.actually_enqueue worker_loop
      end
      pending = Atomic(Int32).new(count)
      count.times do
        @workers << Thread.new do
          scheduler = Thread.current.scheduler
          scheduler.pool = self
          register_fiber(Fiber.current)
          pending.sub(1)
          scheduler.run_loop
        end
      end

      # Wait for all worker threads to be fully ready to be used
      while pending.get > 0
        Fiber.yield  if use_existing_thread
      end
    end

    def next_thread!
      @rr_target &+= 1
      workers[@rr_target % workers.size]
    end

    def spawn(*, name : String? = nil, &block)
      @spawned = true
      Fiber.new(name, &block).tap do |fiber|
        register_fiber(fiber)
        thread = next_thread!
        # Currently guaranteed not to be the same thread..

        thread.scheduler.send_fiber fiber
      end
    end
  end
end

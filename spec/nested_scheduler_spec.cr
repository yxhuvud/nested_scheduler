require "./spec_helper"

describe NestedScheduler do
  context ".nursery" do
    it "doesn't impact current thread pool" do
      worker_count = Thread.current.scheduler.pool.not_nil!.workers.size
      NestedScheduler::ThreadPool.nursery do |_|
        Thread.current.scheduler.pool.not_nil!.workers.size
          .should eq worker_count
      end
    end

    it "spawns a fiber" do
      NestedScheduler::ThreadPool.nursery { |pl| typeof(pl.spawn { }).should eq Fiber }
    end

    it "kills any started fibers" do
      100.times do
        NestedScheduler::ThreadPool.nursery { }
      end
      i = 0
      Fiber.unsafe_each do |f|
        i += 1
      end
      i.should be < 10
    end

    it "exits immediately if not spawned" do
      Time.measure do
        NestedScheduler::ThreadPool.nursery { |_| }
      end.to_f.should be < 0.0001
    end

    it "starts the pool and waits for it to finish" do
      sleep_time = 0.01
      spent_time = Time.measure do
        NestedScheduler::ThreadPool.nursery name: "t" do |pl|
          100.times do |i|
            pl.spawn(name: "fiber#{i}") do
              sleep sleep_time
            end
          end
        end
      end.to_f

      spent_time.should be > sleep_time
      spent_time.should be < 5 * sleep_time
    end

    it "executes" do
      # capacity needed as otherwise the pool won't ever exit as the
      # channel isn't consumed. Why, because nursery doesn't return
      # until all the fibers are done..
      chan = Channel(Int32).new capacity: 10
      NestedScheduler::ThreadPool.nursery do |pl|
        10.times { |i| pl.spawn(name: "fiber: #{i}") { chan.send i } }
      end
      values = Array(Int32).new(10) { |i| chan.receive }
      values.sort.should eq [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    end

    it "can be soft canceled" do
      count = 0
      NestedScheduler::ThreadPool.nursery do |pl|
        pl.spawn do
          sleep 0.01
          pl.cancel
        end
        pl.spawn do
          pl.canceled?.should be_false
          loop do
            break if pl.canceled?
            count += 1
            sleep 0.001
          end
        end
      end
      count.should be > 7 # allow for some overhead..
    end

    it "re-raise fiber exceptions by default" do
      ex = expect_raises NotImplementedError do
        NestedScheduler::ThreadPool.nursery do |pl|
          pl.spawn { raise NotImplementedError.new("fail") }
        end
      end

      ex.message.should eq "Not Implemented: fail"
    end
  end

  context "spawning original worker threads" do
    it "spawns the correct number" do
      pool = Thread.current.scheduler.pool.not_nil!
      pool.@workers.size.should eq ENV["CRYSTAL_WORKERS"]?.try(&.to_i) || 4
    end

    it "runs in the root pool" do
      Thread.current.scheduler.pool.not_nil!
        .name.should eq "Root Pool"
    end

    it "doesn't break basic spawning" do
      chan = Channel(Int32).new

      spawn { chan.send 1 }

      res = chan.receive
      res.should eq 1
    end

    it "doesn't break basic spawning1" do
      chan = Channel(Int32).new

      spawn { chan.send 1 }
      spawn { chan.send 2 }

      res = chan.receive + chan.receive
      res.should eq 3
    end

    it "doesn't break basic spawning2" do
      chan = Channel(Int32).new

      spawn { chan.send 1 }
      spawn { chan.send 2 }

      res = chan.receive + chan.receive
      res.should eq 3
    end

    it "doesn't break basic spawning3" do
      chan = Channel(Int32).new

      spawn chan.send(1)

      res = chan.receive
      res.should eq 1
    end

    it "doesn't break basic spawning4" do
      chan = Channel(Int32).new

      spawn chan.send(1)
      spawn chan.send(2)

      res = chan.receive + chan.receive
      res.should eq 3
    end

    it "can nest spawns" do
      executed = false
      NestedScheduler::ThreadPool.nursery do |pl|
        pl.spawn { spawn { executed = true } }
      end
      executed.should eq true
    end
  end
end

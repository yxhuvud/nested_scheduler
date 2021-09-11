require "./spec_helper"

describe NestedScheduler::Results::ResultCollector do
  it "on success" do
    res =
      NestedScheduler::ThreadPool.collect(Int32) do |pl|
        pl.spawn { 1 }
        pl.spawn { 2 }
      end
    typeof(res).should eq Array(Int32)
    res.not_nil!.sort.should eq [1, 2]

    res2 =
      NestedScheduler::ThreadPool.collect(Float64) do |pl|
        pl.spawn { 1.0 }
        pl.spawn { 2.0 }
      end
    typeof(res2).should eq Array(Float64)
    res2.not_nil!.sort.should eq [1.0, 2.0]
  end

  # ok, it would be really nice if this was possible to catch compile-time.
  it "on mismatching type" do
    res = expect_raises ArgumentError do
      NestedScheduler::ThreadPool.nursery(result_handler: NestedScheduler::Results::ResultCollector(Int32).new) do |pl|
        pl.spawn { "wat" }
      end
    end

    res.message.should eq "Expected block to return Int32, but got String"
  end

  it "on error" do
    ex = expect_raises NotImplementedError do
      NestedScheduler::ThreadPool.nursery(result_handler: NestedScheduler::Results::ResultCollector(Int32).new) do |pl|
        pl.spawn { raise NotImplementedError.new "wat" }
      end
    end
    ex.message.should eq "Not Implemented: wat"
  end
end

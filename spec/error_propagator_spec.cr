require "./spec_helper"

describe NestedScheduler::Results::ErrorPropagator do
  it "on success" do
    executed = false
    res =
      NestedScheduler::ThreadPool.nursery(result_handler: NestedScheduler::Results::ErrorPropagator.new) do |pl|
        pl.spawn { executed = true }
      end
    res.should be_nil
    executed.should be_true
  end

  it "on error" do
    ex = expect_raises Exception do
      NestedScheduler::ThreadPool.nursery(result_handler: NestedScheduler::Results::ErrorPropagator.new) do |pl|
        pl.spawn { raise "wat" }
      end
    end
    ex.message.should eq "wat"
  end
end

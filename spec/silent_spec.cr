require "./spec_helper"

describe NestedScheduler::Results::Silent do
  it "on success" do
    res =
      NestedScheduler::ThreadPool.nursery(result_handler: NestedScheduler::Results::Silent.new) do |pl|
        pl.spawn { 1 }
        pl.spawn { 2 }
      end
    res.should eq nil
  end

  it "on error" do
    res =
      NestedScheduler::ThreadPool.nursery(result_handler: NestedScheduler::Results::Silent.new) do |pl|
        pl.spawn { raise NotImplementedError.new "wat" }
      end
    res.should eq nil
  end
end

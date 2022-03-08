require "./spec_helper"

# Use methods to get something sensible in the stack traces.
private def raiser
  raise "wat"
end

private def will_raise
  NestedScheduler::ThreadPool.nursery(result_handler: NestedScheduler::Results::ErrorPropagator.new) do |pl|
    pl.spawn { raiser }
  end
end

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
      will_raise
    end
    ex.inspect_with_backtrace
      .should match(
        # unfortunately the will_raise ends up in the wrong file. Dunno why..
        /from error_propagator_spec.cr:5:3 in 'raiser'(.*\n)*.*in 'will_raise'/
      )
    ex.message.should eq "wat"
  end
end

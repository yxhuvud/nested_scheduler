require "./spec_helper"

describe "main" do
  it "will wait for all fibers to complete" do
    command = "crystal run -Dpreview_mt spec/examples/example.cr"
    output = "passed\ndone!\n"
    result = `#{command}`
    result.should eq output
  end
end

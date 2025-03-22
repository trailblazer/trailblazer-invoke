require "test_helper"

class PriateApiTest < Minitest::Spec
  it "exposes {Invoke.initial_wrap_static} which we need in Operation" do
    initial_wrap_static = Trailblazer::Invoke.initial_wrap_static

    assert_equal initial_wrap_static.size, 2
    assert_equal initial_wrap_static[0].class, Trailblazer::Activity::TaskWrap::Pipeline::Row
  end
end

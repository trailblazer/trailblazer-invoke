require "test_helper"

class MatcherTest < Minitest::Spec
  let(:matcher) do
    {
      success:    ->(*) { raise },
      not_found:  ->(ctx, model:, **) { @render = "404, #{model} not found" },
      not_authorized: ->(*) { snippet },
    }
  end

  let(:dsl) do
    dsl = Trailblazer::Invoke::Matcher::DSL.new

    dsl.success do |ctx, model:, **|
      @render = model.inspect
    end.failure do |*|
      @render = "failure"
    end.not_authorized do |ctx, model:, **|
      @render = "not authorized: #{model}"
    end

    dsl
  end

  # it "yields the runtime DSL block when no {:exec_context} passed" do
  #   ctx = {model: Object}

  #   assert_equal Trailblazer::Invoke::Matcher.(:success, [ctx, **ctx], matcher: matcher, merge: dsl.to_h, exec_context: nil), %(Object)
  #   assert_equal @render, %(Object)
  # end

  it "instance_exec's when {:exec_context} passed" do
    ctx = {model: Object}
    controller = Object.new

    #@ Matcher.call
    assert_equal Trailblazer::Invoke::Matcher.(:success, [ctx, **ctx], matcher: matcher, merge: dsl.to_h, exec_context: controller), %(Object)
    assert_equal controller.instance_variable_get(:@render), %(Object)

    assert_equal Trailblazer::Invoke::Matcher.(:not_found, [ctx, **ctx], matcher: matcher, merge: dsl.to_h, exec_context: controller), %(404, Object not found)
    assert_equal controller.instance_variable_get(:@render), %(404, Object not found)

    #@ Matcher::Value.call
    value = Trailblazer::Invoke::Matcher::Value.new(matcher, dsl, controller)
    assert_equal value.(:success, [ctx, **ctx], exec_context: controller), %(Object)
  end
end


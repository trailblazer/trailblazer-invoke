# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "trailblazer/invoke"
require "trailblazer/activity/dsl/linear"
require "trailblazer/developer"

require "minitest/autorun"

Minitest::Spec.class_eval do
  require "trailblazer/activity/testing"
  T = Trailblazer::Activity::Testing

  require "trailblazer/core"
  CU = Trailblazer::Core::Utils

  def assert_equal(expected, asserted, *args)
    super(asserted, expected, *args)
  end
end

# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "trailblazer/invoke"
require "trailblazer/activity/dsl/linear"
require "trailblazer/developer"
require "trailblazer/core"

require "minitest/autorun"

Minitest::Spec.class_eval do
  T = Trailblazer::Core
  CU = Trailblazer::Core::Utils

  def assert_equal(expected, asserted, *args)
    super(asserted, expected, *args)
  end
end

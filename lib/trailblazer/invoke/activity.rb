# Load this file to add {Railway.__} (the canonical invoke) to all Activity subclasses.

Trailblazer::Invoke.module!(Trailblazer::Activity::DSL::Linear::Strategy.singleton_class) # Add {Railway.__}. # FIXME: remove and make users do it manually?
Trailblazer::Activity.module_eval do
  def self.call(*args, **options, &block)
    Trailblazer::Activity::DSL::Linear::Strategy.__(*args, options, &block)
  end
end
# TODO: test me.

module Trailblazer
  module Invoke
    module Activity
      def self.configure!(&block)
        Trailblazer::Invoke.module!(Trailblazer::Activity::DSL::Linear::Strategy.singleton_class, &block) # Adds {Railway.__}.
      end
    end
  end
end

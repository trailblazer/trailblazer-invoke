# Load this file to add {Railway.__} (the canonical invoke) to all Activity subclasses.

Trailblazer::Invoke.module!(Trailblazer::Activity::DSL::Linear::Strategy.singleton_class) # Add {Railway.__}.
# TODO: test me.

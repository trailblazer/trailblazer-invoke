require_relative "invoke/version"
require "trailblazer/invoke/matcher"

module Trailblazer
  module Invoke
    def self.module!(target, canonical_invoke_name: :__, canonical_wtf_name: "#{canonical_invoke_name}?", &arguments_block)
      arguments_block = ->(*) { {} } unless block_given?

      # DISCUSS: store arguments_block in a class instance variable and refrain from using {define_method}?
      target.define_method(canonical_invoke_name) do |activity, options, **kws, &block|
        Canonical.__(activity, options, my_dynamic_arguments: arguments_block, **kws, &block)
      end

      target.define_method(canonical_wtf_name) do |activity, options, **kws, &block|
        Canonical.__?(activity, options, my_dynamic_arguments: arguments_block, **kws, &block)
      end
    end

    # This module implements the end user's top level entry point for running activities.
    # By "overriding" **kws they can inject any {flow_options} or other {Runtime.call} options needed.

    # Currently, "Canonical" implies that some options-compiler is executed to
    # aggregate flow_options, Runtime.call options like :invoke_method, circuit_options,
    # etc.
    module Canonical
      module_function

      def __(activity, options, my_dynamic_arguments:, **kws, &block)
        Trailblazer::Invoke.(
          activity,
          options,
          **my_dynamic_arguments.(activity, options, **kws), # represents {:invoke_method} and {:present_options}
          **kws,
          &block
        )
      end

      def __?(*args, **kws, &block)
        __(
          *args,
          invoke_method: Trailblazer::Developer::Wtf.method(:invoke),
          **kws,
          &block
        )
      end
    end

    module_function

    # @public
    # Top-level entry point.
    def call(activity, ctx, default_matcher: {}, matcher_context: self, **options, &block)
      return Call.(activity, ctx, **options) unless block_given?

      WithMatcher.(activity, ctx, default_matcher: default_matcher, matcher_context: matcher_context, **options, &block)
    end

    module Call
      module_function

      # We run the Adapter here, which in turn will run your business operation, then the matcher
      # or whatever you have configured.
      #
      # This method is basically replacing {Operation.call_with_public_interface}, from a logic perspective.
      #
      # NOTE: {:invoke_method} is *not* activity API, that's us here using it.
      def call(activity, ctx, flow_options: {}, extensions: [], invoke_method: Trailblazer::Activity::TaskWrap.method(:invoke), circuit_options: {}, initial_wrap_static: Invoke::INITIAL_WRAP_STATIC, **, &block) # TODO: test {flow_options}
        pipeline = Activity::TaskWrap::Pipeline.new(initial_wrap_static + extensions)

        container_activity = Activity::TaskWrap.container_activity_for(activity, wrap_static: pipeline)

        invoke_method.( # FIXME: run Advance using this, not its own wtf?/call invocation.
          activity,
          [
            ctx,
            flow_options
          ],

          container_activity: container_activity,
          exec_context: self,
          # wrap_runtime: {activity => ->(*) { snippet }} # TODO: use wrap_runtime once https://github.com/trailblazer/trailblazer-developer/issues/46 is fixed.
          **circuit_options
        )
      end


    end

    require "trailblazer/activity/dsl/linear" # DISCUSS: do we want that here? where should we compile INITIAL_WRAP_STATIC?
    def initial_wrap_static
      # Instead of creating the {ctx} manually, use an In() filter for the outermost activity.
      # Currently, the interface is a bit awkward, but we're going to fix this.
    # The "beginning" of the wrap_static pipeline for the top activity that's invoked.
      top_level_activity = Class.new(Activity::Railway) do
        # DISCUSS: let's use {Subprocess()} as a well-defined "hook" when building the taskWrap for the
        # top-level activity.
        step Subprocess(Activity::Railway),
          In() => ->(ctx, **) { ctx } # wrap hash into Trailblazer::Context, super awkward.
          # Inject(nil) => ->(*) {  } # FIXME: we should be using I/O's internal logic for the "default_ctx" here by making it think there are Inject()s even though most of the times, there aren't.
      end

      in_extension_with_call_task = top_level_activity.to_h[:config][:wrap_static].values.first.to_a[0..1] # no Out() extension. FIXME: maybe I/O should have some semi-private API for that?

      in_extension_with_call_task # [#<Extension In()>, #<Extension {call_task}>]
    end

    INITIAL_WRAP_STATIC = initial_wrap_static() # DISCUSS: this should be done per Activity subclass so we can do Subprocess(activity).

    module WithMatcher # FIXME
      # module_function

      # Adds the matcher logic to invoking an activity via an "endpoint" (actually, this is not related to endpoints at all).
      def self.call(activity, ctx, flow_options: {}, matcher_context:, default_matcher:, matcher_extension: Matcher.Extension(), **kws, &block)
        matcher = Matcher::DSL.new.instance_exec(&block)

        matcher_value = Matcher::Value.new(default_matcher, matcher, matcher_context)

        flow_options = flow_options.merge(matcher_value: matcher_value) # matchers will be executed in Adapter's taskWrap.

        Call.(activity, ctx, flow_options: flow_options, extensions: [matcher_extension], **kws) # TODO: we *might* be overriding {:extensions} here.
      end
    end # Invoke
  end
end

=begin
1. less cool option, but also less changes:
  pass Activity into initial_wrap_static(activity) in #__ which will compute the wrap_static for the actual activity at runtime
  retrieve class dependency fields (in C.D. specific code by overriding Subprocess), build initial_wrap_static/variable mapping based on that
2. every Activity::Strategy keeps its wrap_static in a class field.
  C.D. could add to that at compile time
  Subprocess would generically retrieve the nested's wrap_static
  problem here is that mixing Inject() with an already compiled I/O pipe will need some work.

where do we benefit from a Strategy.initial_wrap_static per subclass?
  class dependencies
  NOT for setting container path, because we need Subprocess :id for that from the containing activity

goal
  injecting deps per step, specific, even if we use multiple {:http} deps across one OP.
  e.g.
                          vvvv-step vvv-kwargs
    memo.operation.create.validate.http = MockedHttp
=end


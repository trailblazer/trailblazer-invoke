require_relative "invoke/version"
require "trailblazer/activity/dsl/linear"
require "trailblazer/invoke/matcher"


module Trailblazer
  module Invoke
    def self.module!(target, canonical_invoke_name: :__, canonical_wtf_name: "#{canonical_invoke_name}?", &arguments_block)
      options_compiler = Options.build(block: arguments_block) # DISCUSS: pass {:steps} here to make it more obvious?

      # DISCUSS: store arguments_block in a class instance variable and refrain from using {define_method}?
      target.define_method(canonical_invoke_name) do |activity, options, **kws, &block|
        Canonical.__(activity, options, options_compiler: options_compiler, **kws, &block)
      end

      target.define_method(canonical_wtf_name) do |activity, options, **kws, &block|
        Canonical.__?(activity, options, options_compiler: options_compiler, **kws, &block)
      end
    end

# IDEA: pipeline for {options_compiler} so we can have
#  user options like
#    alias
#    tracing turned on by whatever condition
#  features like
#    pro: add :present_options and wtf invoke/options.

    # Dynamic options per invocation.
    # Implements a pipeline (like the taskWrap) to merge options that are passed to canonical-invoke.
    #
    # 1. @steps can be altered by the application and its gems.
    # 2. We then add the user block from module!
    # 3.   we then add the runtime canonical #invoke options as another step at runtime. maybe this can be improved?
    class Options
      singleton_class.instance_variable_set(:@steps, []) # TODO: this is private API so far, but will be public one day soon for your extension!
      # This is where we can plug in additional canonical-invoke options compiler, e.g. from {trailblazer-pro}.

      def self.build(steps: singleton_class.instance_variable_get(:@steps), block:)
        arguments_block = block ? HeuristicMerge.build(block) : Passthrough

        pipeline = Activity::TaskWrap::Pipeline.new(steps + [Activity::TaskWrap::Pipeline.Row("user_block", arguments_block)])

        new(pipeline)
      end

      def initialize(pipeline)
        @pipeline = pipeline
      end

      def call(*args, adds_for_options_compiler: [], **kws) # DISCUSS: remove this and pass {} in #__.
        adds_for_options_compiler = merge_user_options_from_canonical_invoke(adds_for_options_compiler, **kws)

        pipeline = Activity::Adds.(@pipeline, *adds_for_options_compiler) # DISCUSS: this could be sped up?

        # TODO: allow easy debugging.
        # pp pipeline

        options, _ = pipeline.({}, [args, kws])

        # TODO: allow easy debugging.
        # pp options

        options
      end

      # @private
      def merge_user_options_from_canonical_invoke(adds_for_options_compiler, **kws)
        adds_for_options_compiler + [
          [
            HeuristicMerge.build(->(*) {

              kws # let deep_merge do the work.
            }), # TODO: constant.
            id: "user options",
            append: nil
          ]
        ]
      end

      # DISCUSS: unfortunately, we cannot use deep_merge by hashie as it converts Hash instances with a default to
      # simple hashes without default. That doesn't play well with wrap_runtime.
      module HeuristicMerge
        def self.build(proc)
          ->(options, (args, kws)) do
            options_from_step = proc.(*args, **kws, aggregate: options)

            # feature of invoke: merge {circuit_options.wrap_runtime}
            # if has_wrap_runtime?(options)
              options_from_step = merge_wrap_runtime(options, options_from_step)
            # end

            # FIXME: of course, that's not final.
            bla_options = options.merge(options_from_step)


            new_options =
            [:flow_options, :circuit_options].inject(bla_options) do |memo, key|
              if option1 = options_from_step[key]
                if option2 = options[key]
                  memo.merge(key => option2.merge(option1))
                else
                  memo.merge(key => option1)
                end
              else
                memo
              end
            end

            return new_options, [args, kws]
          end
        end

        # TODO: merge {:wrap_runtime}
        # TODO: this should actually be handled in hashie. This code part might be implemented by hashie soon.
        def self.merge_wrap_runtime(options, options_from_step)
          return options_from_step unless original_wrap_runtime = wrap_runtime_for(options)
          return options_from_step unless mergable_wrap_runtime = wrap_runtime_for(options_from_step)

          default_existing_ext = original_wrap_runtime.default
          default_mergable_ext = mergable_wrap_runtime.default

          new_default = merge_extensions(default_existing_ext, default_mergable_ext)
# puts "@@@@@ #{new_default.inspect}"

          new_wrap_runtime = Hash.new(new_default)

          keys_to_merge = original_wrap_runtime.keys | mergable_wrap_runtime.keys
          keys_to_merge.each do |task|
            new_wrap_runtime[task] = merge_extensions(original_wrap_runtime[task], mergable_wrap_runtime[task])
          end

          options_from_step[:circuit_options][:wrap_runtime] = new_wrap_runtime # DISCUSS: is it safe to mutate here?
          options_from_step
        end

        def self.wrap_runtime_for(options)
          return unless options.key?(:circuit_options) && options[:circuit_options].key?(:wrap_runtime)

          options[:circuit_options][:wrap_runtime]
        end

        def self.merge_extensions(original_ext, ext)
          return original_ext if ext.nil?
          return ext if original_ext.nil?

          Activity::TaskWrap::Extension.new(*(original_ext.instance_variable_get(:@extension_rows) + ext.instance_variable_get(:@extension_rows)))
        end
      end

      Passthrough = ->(*args) { args }  # NOOP.

      # require "hashie/extensions/deep_merge"
      # class Hash < Hash
      #   include Hashie::Extensions::DeepMerge
      # end
    end

    # This module implements the end user's top level entry point for running activities.
    # By "overriding" **kws they can inject any {flow_options} or other {Runtime.call} options needed.

    # Currently, "Canonical" implies that some options-compiler is executed to
    # aggregate flow_options, Runtime.call options like :invoke_method, circuit_options,
    # etc.
    module Canonical
      module_function

      def __(activity, options, options_compiler:, **kws, &block)
        Trailblazer::Invoke.(
          activity,
          options,
          **options_compiler.(activity, options, **kws), # represents {:invoke_method} and {:present_options}
          # **kws, # this is merged per default, in {#merge_user_options_from_canonical_invoke}
          &block
        )
      end

      def __?(*args, **kws, &block)
        __(
          *args,
          **Trailblazer::Developer::Wtf.options_for_canonical_invoke, # DISCUSS: technically, we're overriding {:adds_for_options_compiler} here.
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
      #
      # TODO:
      # @param :task_wrap_for_activity
      # @param
      def call(activity, ctx, flow_options: {}, extensions: [], invoke_method: Trailblazer::Activity::TaskWrap.method(:invoke), circuit_options: {}, invoke_task_wrap: Invoke::INVOKE_TASK_WRAP, **options, &block) # TODO: test {flow_options}
        # {invoke_task_wrap}: create a {Context}, maybe run a matcher.

        # DISCUSS: we could also simply create a Trailblazer::Context here manually.
        task_wrap_extensions_for_activity = task_wrap_extensions_for_activity_for(activity, **options)

        pipeline = Activity::DSL::Linear::Normalizer::TaskWrap.compile_task_wrap_ary_from_extensions(task_wrap_extensions_for_activity, extensions, {task: activity, **options})
        # pipeline  = DSL.pipe_for_composable_input(**options)  # FIXME: rename filters consistently
        # input     = Pipe::Input.new(pipeline)

        task_wrap = invoke_task_wrap + pipeline # send our Invoke steps piggyback with the activity's tw.

          # this could also be achieved using Subprocess and the tw merging logic, but please not at runtime (for now).
        task_wrap_pipeline = Activity::TaskWrap::Pipeline.new(task_wrap)

        container_activity = Activity::TaskWrap.container_activity_for(activity, wrap_static: task_wrap_pipeline)

        invoke_method.(
          activity,
          [
            ctx,
            flow_options
          ],

          container_activity: container_activity,
          exec_context: nil,
          **circuit_options
        )
      end

      # Basically, fetch `activity{:task_wrap_extensions}` and compile it.
      def task_wrap_extensions_for_activity_for(activity, task_wrap_extensions_for_activity: nil, **options)
        return task_wrap_extensions_for_activity if task_wrap_extensions_for_activity

        # DISCUSS: we're mimicking Subprocess-with-intial_task_wrap=logic here.
        # Subprocess(activity), subprocess: true
        _initial_task_wrap_extensions = Activity::DSL::Linear::Normalizer::TaskWrap.compile_initial_task_wrap({task: activity, **options}, subprocess: true, task: activity) # FIXME: test {**options}
      end
    end

    require "trailblazer/activity/dsl/linear" # DISCUSS: do we want that here? where should we compile INVOKE_TASK_WRAP?
    # TODO: rename to {#task_wrap_for_invoke}
    def invoke_task_wrap
      in_pipe, _ = Trailblazer::Activity::DSL::Linear::VariableMapping.merge_instructions_from_dsl()

      [
        Trailblazer::Activity::TaskWrap::Pipeline.Row("invoke.default_ctx", in_pipe)
      ]
    end

    INVOKE_TASK_WRAP = invoke_task_wrap() # DISCUSS: this should be done per Activity subclass so we can do Subprocess(activity).

    module WithMatcher # FIXME
      # module_function

      # Adds the matcher logic to invoking an activity via an "endpoint" (actually, this is not related to endpoints at all).
      def self.call(activity, ctx, flow_options: {}, matcher_context:, default_matcher:, matcher_extension: Matcher::NORMALIZER_TASK_WRAP_EXTENSION, extensions: [], **kws, &block)
        matcher = Matcher::DSL.new.instance_exec(&block)

        matcher_value = Matcher::Value.new(default_matcher, matcher, matcher_context)

        flow_options = flow_options.merge(matcher_value: matcher_value) # matchers will be executed in Adapter's taskWrap.

        Call.(activity, ctx, flow_options: flow_options, extensions: [*extensions, matcher_extension], **kws) # TODO: we *might* be overriding {:extensions} here.
      end
    end # Invoke
  end
end

=begin
1. less cool option, but also less changes:
  pass Activity into invoke_task_wrap(activity) in #__ which will compute the wrap_static for the actual activity at runtime
  retrieve class dependency fields (in C.D. specific code by overriding Subprocess), build invoke_task_wrap/variable mapping based on that
2. every Activity::Strategy keeps its wrap_static in a class field.
  C.D. could add to that at compile time
  Subprocess would generically retrieve the nested's wrap_static
  problem here is that mixing Inject() with an already compiled I/O pipe will need some work.

where do we benefit from a Strategy.invoke_task_wrap per subclass?
  class dependencies
  NOT for setting container path, because we need Subprocess :id for that from the containing activity

goal
  injecting deps per step, specific, even if we use multiple {:http} deps across one OP.
  e.g.
                          vvvv-step vvv-kwargs
    memo.operation.create.validate.http = MockedHttp
=end


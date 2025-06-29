require "test_helper"

# Tests the combination of {#module!} and {#__}.
class CanonicalInvokeTest < Minitest::Spec
  after { Trailblazer::Invoke::Options.singleton_class.instance_variable_set(:@steps, []) }

  class Create < Trailblazer::Activity::FastTrack
    step :model
    include T.def_steps(:model)
  end

  class Capture < Trailblazer::Activity::Railway
    def self.capture_flow_options((ctx, flow_options), **)
      ctx[:captured_flow_options] = flow_options.inspect

      return Trailblazer::Activity::Right, [ctx, flow_options]
    end

    def self.capture_circuit_options((ctx, flow_options), **circuit_options)
      ctx[:captured_circuit_options] = circuit_options.inspect

      return Trailblazer::Activity::Right, [ctx, flow_options]
    end

    step task: method(:capture_flow_options) # FIXME: {step task: :method} is still wrapped in Option.
    step task: method(:capture_circuit_options)

  end

  def render(content)
    @render = content
  end

  let(:ctx) { {seq: [], model: Object} }

  let(:create_trace) do
    %(CanonicalInvokeTest::Create
|-- \e[32mStart.default\e[0m
|-- \e[32mmodel\e[0m
`-- End.success
)
  end

  # _FLOW_OPTIONS = {
  #   context_options: {
  #     aliases: {"model": :record},
  #     container_class: Trailblazer::Context::Container::WithAliases,
  #   }
  # }





  it "allows merging {:wrap_runtime}" do
    # TODO.
  end








  # Generic behavior tests, the fact that module! hasn't got any return hash is mostly irrelevant.
  describe "module!(self) without options" do
    let(:kernel) {
      Class.new { Trailblazer::Invoke.module!(self) }.new
    }

    it "{#__} calls the activity, and returns original resultset" do
      signal, (ctx,) = kernel.__(Create, self.ctx)

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal ctx.class, Trailblazer::Context::Container#::WithAliases
      assert_equal ctx[:model], Object
      assert_equal ctx.keys, [:seq, :model]
    end

    it "{#__?} returns original result set and prints trace" do
      signal, ctx = nil

      stdout, _ = capture_io do
        signal, (ctx,) = kernel.__?(Create, self.ctx)
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal ctx.class, Trailblazer::Context::Container#::WithAliases
      assert_equal ctx[:model], Object
      assert_equal ctx.keys, [:seq, :model]
      assert_equal stdout, create_trace
    end

    # DISCUSS: this test case has nothing to do with the empty module! block.
    it "{#__} accepts {:task_wrap_extensions_for_activity} option" do
      def my_call_task(wrap_ctx, original_args)
        # original_args[0][0][:i_was_here] = true

        wrap_ctx[:return_signal] = Object
        wrap_ctx[:return_args] = {i_was_here: true}

        return wrap_ctx, original_args
      end

      my_task_wrap_extensions = [
        Trailblazer::Activity::TaskWrap::Extension([method(:my_call_task), id: "task_wrap.call_task", prepend: nil])
      ]

      signal, (ctx,) = kernel.__(Create, self.ctx, task_wrap_extensions_for_activity: my_task_wrap_extensions)

      assert_equal signal, Object
      assert_equal CU.inspect(ctx), %({:i_was_here=>true})
    end

    # DISCUSS: this test case has nothing to do with the empty module! block.
    it "{#__} grabs `activity{:task_wrap_extensions}` if not passed (see {:task_wrap_extensions_for_activity}) and passed invoke {**options} to the extensions" do
      activity = Class.new(Trailblazer::Activity::Railway) do
        # This usually happens in extensions such as {trailblazer-dependency}.
        def self.adds_instruction(task_wrap, id: nil, **)
          Trailblazer::Activity::TaskWrap::Extension(
          # Return an ADDS instruction.
            [
              ->(wrap_ctx, original_args) { original_args[0][0][:tw] = "hello from taskWrap #{id.inspect}"; return wrap_ctx, original_args },
              id: "xxx",
              prepend: nil
            ]
          ).(task_wrap)
        end

        ext = method(:adds_instruction)

        @state.update!(:fields) do |fields|
          exts = fields[:task_wrap_extensions] # [call_task]
          exts = exts + [ext]
          fields.merge(task_wrap_extensions: exts)
        end
      end

      # We can inject options when using canonical invoke.
      signal, (ctx, flow_options) = kernel.__(activity, {}, id: "tw ID xxx")
      assert_equal CU.inspect(ctx.to_h), %({:tw=>\"hello from taskWrap \\\"tw ID xxx\\\"\"})
    end

    # DISCUSS: this test case has nothing to do with the empty module! block.
    it "{#__} accepts {:invoke_task_wrap} option" do
      def my_task_wrap_step(wrap_ctx, original_args)
        original_args[0][0][:seq] << :i_was_here

        return wrap_ctx, original_args
      end

      my_task_wrap = [
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my.step", method(:my_task_wrap_step)) # gets added before call_task from {Activity}.
      ]

      signal, (ctx,) = kernel.__(Create, self.ctx, invoke_task_wrap: my_task_wrap)

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal CU.inspect(ctx), %({:seq=>[:i_was_here, :model], :model=>Object})
    end
  end

  MY_INVOKE_METHOD = ->(activity, args, **circuit_options) { Trailblazer::Activity::TaskWrap.invoke(activity, args, **circuit_options, my_invoke: true) }

  #@@@ Test {Invoke.call}-specific options.
  # DISCUSS: why is this needed? for __? and injecting circuit_options and flow_options?
  it "you can bypass options-compiler and simple pass {:flow_options} and friends to {#invoke}" do # TODO: test circuit_options, flow_options, invoke_method
    kernel = Class.new {
      Trailblazer::Invoke.module!(self) do
        {
          flow_options:     {origin: "i am set in canonical user block"}, # shouldn't be visible.
          circuit_options:  {from: "from canonical user block"},
          invoke_method:    ->(*) { raise }, # never gets called.
        }
      end
    }.new

    my_overrides = {
      flow_options:     {override_everything: true},
      circuit_options:  {override: "circuit_options!"},
      invoke_method:    MY_INVOKE_METHOD,
    }

    my_passthrough_options_compiler = ->(*, **kws) { kws }

    signal, (ctx,) = kernel.__(Capture, self.ctx, **my_overrides, options_compiler: my_passthrough_options_compiler)

    assert_equal CU.strip(CU.inspect(ctx.to_h)), %({:seq=>[], :model=>Object, :captured_flow_options=>\"{:override_everything=>true}\", :captured_circuit_options=>\"{:exec_context=>#<CanonicalInvokeTest::Capture:0x>, :override=>\\\"circuit_options!\\\", :my_invoke=>true, :wrap_runtime=>{}, :activity=>#<Trailblazer::Activity:0x>, :runner=>Trailblazer::Activity::TaskWrap::Runner}\"})

#     # Tracing is done through {:circuit_options}, we override {flow_options} and need to set {:stack} and friends.
#     stdout, _ = capture_io do
#       signal, (ctx,) = kernel.__?(Capture, self.ctx, flow_options: my_overrides[:flow_options].merge(Trailblazer::Developer::Trace.invoke_options_compiler_step(Capture, self.ctx)[:flow_options]), options_compiler: my_passthrough_options_compiler)
#     end

#     # assert_create_run(signal, ctx)
#     assert_equal stdout, %(CanonicalInvokeTest::Capture
# |-- \e[32mStart.default\e[0m
# |-- \e[32m#<Method: #<Class:>.capture_flow_options>\e[0m
# |-- \e[32m#<Method: #<Class:>.capture_circuit_options>\e[0m
# `-- End.success
# )
#     assert_equal CU.inspect(ctx[:captured_flow_options]).keys, [1]
  end

  it "{#__} accepts {:flow_options}, {:circuit_options} and {:invoke_method} which are deep-merged with options-compiler" do
    kernel = Class.new {
      Trailblazer::Invoke.module!(self) do
        {
          flow_options:     {origin: "i am set in canonical user block"}, # shouldn't be visible.
          circuit_options:  {from: "from canonical user block"},
          invoke_method:    ->(*) { raise }, # never gets called.
        }
      end
    }.new

    my_merged_options = {
      flow_options:     {override_everything: true},
      circuit_options:  {override: "circuit_options!"},
      invoke_method:    MY_INVOKE_METHOD,
    }

    signal, (ctx,) = kernel.__(Capture, self.ctx, **my_merged_options)

    assert_equal CU.strip(CU.inspect(ctx.to_h)), %({:seq=>[], :model=>Object, :captured_flow_options=>\"{:origin=>\\\"i am set in canonical user block\\\", :override_everything=>true}\", :captured_circuit_options=>\"{:exec_context=>#<CanonicalInvokeTest::Capture:0x>, :from=>\\\"from canonical user block\\\", :override=>\\\"circuit_options!\\\", :my_invoke=>true, :wrap_runtime=>{}, :activity=>#<Trailblazer::Activity:0x>, :runner=>Trailblazer::Activity::TaskWrap::Runner}\"})

    # Tracing is done through {:circuit_options}, we override {flow_options} and need to set {:stack} and friends.
    stdout, _ = capture_io do
      signal, (ctx,) = kernel.__?(Capture, self.ctx, flow_options: my_merged_options[:flow_options].merge(Trailblazer::Developer::Trace.invoke_options_compiler_step(Capture, self.ctx)[:flow_options]))
    end

    # assert_create_run(signal, ctx)
    assert_equal stdout, %(CanonicalInvokeTest::Capture
|-- \e[32mStart.default\e[0m
|-- \e[32m#<Method: #<Class:>.capture_flow_options>\e[0m
|-- \e[32m#<Method: #<Class:>.capture_circuit_options>\e[0m
`-- End.success
)
    assert CU.inspect(ctx[:captured_flow_options]) =~ /:origin/
    assert CU.inspect(ctx[:captured_flow_options]) =~ /:override_everything/
    assert CU.inspect(ctx[:captured_circuit_options]) =~ /:from/
    assert_equal CU.inspect(ctx[:captured_circuit_options]) =~ /:my_invoke/, nil # this is not present as wtf overrides {:invoke_method}.
  end

  # TODO: test {:extensions} option for {#__}.
  # TODO: test that we only merge on one level.
  it "steps from options-compiler and user block are deep-merged (currently on the first level, only)" do
    my_options_step_1 = ->(activity, options, **options_for_invoke) do
      {
        circuit_options: {
          step_1: {option: true}
        },
        flow_options: {
          step_1_flow: true
        },
        invoke_method: :step_1,

        # non_heuristic_hash: {key: true},
      }
    end
    my_options_step_1 = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step_1)

    my_options_step_2 = ->(activity, options, **options_for_invoke) do
      {
        circuit_options: {
          step_2: {option: false}
        },
        flow_options: {
          step_2_flow: {some: :option}
        },
        invoke_method: :step_2,

        # non_heuristic_hash: {more: 1},
      }
    end
    my_options_step_2 = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step_2)

    # this would happen in plugin gems.
    steps = Trailblazer::Invoke::Options.singleton_class.instance_variable_get(:@steps)
    steps = steps + [
      Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step_1", my_options_step_1),
      Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step_2", my_options_step_2),
    ]
    Trailblazer::Invoke::Options.singleton_class.instance_variable_set(:@steps, steps)


  # user block wins over options compiler, and is deep-merged.
    kernel = Class.new do
      Trailblazer::Invoke.module!(self) do |*|
        {
          # This doesn't override {:circuit_options} from above, but merges both.
          circuit_options: {
            override_everything: true
          },
          flow_options: {
            user_block: true
          },
          invoke_method: MY_INVOKE_METHOD # wins
        }
      end
    end.new

    signal, (ctx, flow_options) = kernel.__(Capture, {})

    assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
    assert_equal CU.strip(CU.inspect(ctx.to_h)), %({:captured_flow_options=>\"{:step_1_flow=>true, :step_2_flow=>{:some=>:option}, :user_block=>true}\", :captured_circuit_options=>\"{:exec_context=>#<CanonicalInvokeTest::Capture:0x>, :step_1=>{:option=>true}, :step_2=>{:option=>false}, :override_everything=>true, :my_invoke=>true, :wrap_runtime=>{}, :activity=>#<Trailblazer::Activity:0x>, :runner=>Trailblazer::Activity::TaskWrap::Runner}\"})
  end

  # empty block,

  # adds_for_options_compiler


  #@@@ Test how the {module!} block behaves.
  describe "module!(self) with dynamic args" do
    it "allows passing arbitrary options to {#__}, such as {:enable_tracing} and allows setting {:invoke_method} and {:flow_options}" do
      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |activity, options, enable_tracing:, **|
          # This tests we can pass arbitrary options such as {:enable_tracing},
          # and that we can set invoke_method

          options_with_aliasing = {
            flow_options: {
              context_options: {
                aliases: {"model": :record},
                container_class: Trailblazer::Context::Container::WithAliases,
              },
            },
            # **runtime_call_keywords, # {:invoke_method}
          }

          enable_tracing ? Trailblazer::Developer::Wtf.options_for_invoke(**options_with_aliasing) : options_with_aliasing
        end
      end.new

    signal, ctx = nil

    # no tracing
      stdout, _ = capture_io do
        signal, (ctx,) = kernel.__(Create, self.ctx, enable_tracing: false)
      end

      assert_equal stdout, ""
      assert_create_run(signal, ctx)

    # tracing with {:enable_tracing}.
      stdout, _ = capture_io do
        signal, (ctx,) = kernel.__(Create, self.ctx, enable_tracing: true)
      end

      assert_equal stdout, create_trace
      assert_create_run(signal, ctx)

    # tracing by __?
      stdout, _ = capture_io do
        signal, (ctx,) = kernel.__?(Create, self.ctx, enable_tracing: false) # DISCUSS: __? still overrides {:enable_tracing}.
      end

      assert_equal stdout, create_trace
      assert_create_run(signal, ctx)
    end

    it "block receives activity, options and arbitrary keywords" do
      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |activity, options, **kws|
          {
            flow_options: {
              arguments_we_can_see: [activity, CU.inspect(options), CU.inspect(kws)],
            },
          }
        end
      end.new

      signal, (ctx, flow_options) = kernel.__(Create, self.ctx, enable_tracing: false)

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal ctx[:model], Object
      assert_equal ctx[:record], nil
      assert_equal flow_options[:arguments_we_can_see], [CanonicalInvokeTest::Create, "{:seq=>[], :model=>Object}", "{:enable_tracing=>false, :aggregate=>{}}"]
    end

    it "we can set {:circuit_options}" do
      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |*args|
          Trailblazer::Developer::Wtf.options_for_invoke(
            circuit_options: {
              present_options: {render_method: ->(renderer:, **) { renderer.inspect }}
            },
          )
        end
      end.new

      signal, ctx = nil

      stdout, _ = capture_io do
        signal, (ctx, flow_options) = kernel.__(Create, self.ctx)
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal stdout, %(Trailblazer::Developer::Wtf::Renderer\n)
    end

    def add_1(wrap_ctx, original_args)
      ctx, = original_args[0]
      ctx[:seq] << [1, wrap_ctx[:task]]
      # ctx[:seq] << 1

      return wrap_ctx, original_args # yay to mutable state. not.
    end

    def add_2(wrap_ctx, original_args)
      ctx, = original_args[0]
      ctx[:seq] << 2

      return wrap_ctx, original_args # yay to mutable state. not.
    end

    def add_3(wrap_ctx, original_args)
      ctx, = original_args[0]
      ctx[:seq] << 3

      return wrap_ctx, original_args # yay to mutable state. not.
    end

    it "each step can add to {:wrap_runtime}, which is merged by us" do
      my_task_wrap_ext_1 = Trailblazer::Activity::TaskWrap.Extension([method(:add_1), id: "my.add_1", prepend: "task_wrap.call_task"])
      my_task_wrap_ext_2 = Trailblazer::Activity::TaskWrap.Extension([method(:add_2), id: "my.add_2", prepend: "task_wrap.call_task"])
      my_task_wrap_ext_3 = Trailblazer::Activity::TaskWrap.Extension([method(:add_3), id: "my.add_3", prepend: "task_wrap.call_task"])


      # TODO: test wrap_runtime nil

      # exemplary plugin/gem:
      my_options_step = ->(activity, options, **options_for_invoke) do
        {
          circuit_options: {wrap_runtime: Hash.new(my_task_wrap_ext_1), bla: 1}
        }
      end
      my_options_step_1 = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step)

      # exemplary plugin/gem:
      my_options_step = ->(activity, options, **options_for_invoke) do
        {
          circuit_options: {wrap_runtime: Hash.new(my_task_wrap_ext_2), blubb: 2}
        }
      end
      my_options_step_2 = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step)

      my_options_step = ->(activity, options, **options_for_invoke) do
        {
          circuit_options: {wrap_runtime: {Create => my_task_wrap_ext_3}}
        }
      end
      my_options_step_3 = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step)


      # this would happen in plugin gems.
      steps = Trailblazer::Invoke::Options.singleton_class.instance_variable_get(:@steps)
      steps = steps + [
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step_1", my_options_step_1),
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step_2", my_options_step_2),
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step_3", my_options_step_3),
      ]
      Trailblazer::Invoke::Options.singleton_class.instance_variable_set(:@steps, steps)


      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |*|
          {
            circuit_options: {wrap_runtime: {Create => my_task_wrap_ext_2}}
          }
        end
      end.new

      signal, (ctx, flow_options) = kernel.__(Create, self.ctx)

# NOTE that the default from wrap_runtime is also applied with Create as it is merged with the explicit steps.
      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal CU.inspect(ctx.to_h), %({:seq=>[[1, CanonicalInvokeTest::Create], 2, 3, 2, [1, #<Trailblazer::Activity::Start semantic=:default>], 2, [1, #<Trailblazer::Activity::TaskBuilder::Task user_proc=model>], 2, :model, [1, #<Trailblazer::Activity::End semantic=:success>], 2], :model=>Object})
    end

    def save_circuit_options(wrap_ctx, original_args)
      circuit_options = original_args[1]
      original_args[0][0][:saved_circuit_options] = circuit_options.slice(:read_from_top_level).inspect

      return wrap_ctx, original_args
    end
    # Test circuit_options is merged, and we can access {:aggregate}
    it "we can access {:aggregate} when arguments are compiled" do
      my_task_wrap_ext = Trailblazer::Activity::TaskWrap.Extension(
        [method(:save_circuit_options), id: "my.save_circuit_options", prepend: "task_wrap.call_task"]
      )

      my_options_step = ->(activity, options, **options_for_invoke) do
        {
          circuit_options: {
            wrap_runtime: Hash.new(my_task_wrap_ext)
          }
        }
      end
      my_options_step = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step)

      my_setter_step = ->(*) { {top_level: true} }
      my_setter_step = Trailblazer::Invoke::Options::HeuristicMerge.build(my_setter_step)

      my_aggregate_reader_step = ->(activity, options, aggregate:, **options_for_invoke) do
        {
          circuit_options: {read_from_top_level: aggregate[:top_level]}
        }
      end
      my_aggregate_reader_step = Trailblazer::Invoke::Options::HeuristicMerge.build(my_aggregate_reader_step)

      steps = Trailblazer::Invoke::Options.singleton_class.instance_variable_get(:@steps)
      steps = steps + [
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step", my_options_step),
        # set {:top_level} and read it in the next step.
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_setter_step", my_setter_step),
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_aggregate_reader_step", my_aggregate_reader_step),
      ]
      Trailblazer::Invoke::Options.singleton_class.instance_variable_set(:@steps, steps)

      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |*|
          {
            # This doesn't override {:circuit_options} from above, but merges both.
            # circuit_options: {
            #   override_everything: true,
            # }
          }
        end
      end.new

      signal, (ctx, flow_options) = kernel.__(Create, self.ctx)

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal CU.inspect(ctx[:saved_circuit_options]), %({:read_from_top_level=>true})
    end

    it "the user block wins over previous steps, we override {:invoke_method}" do # DISCUSS: this is already covered implicitly above.
      my_options_step = ->(*) do
        {
          invoke_method: Object, # never called, hopefully.
        }
      end
      my_options_step = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step)

      steps = Trailblazer::Invoke::Options.singleton_class.instance_variable_get(:@steps)
      steps = steps + [
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step", my_options_step),
      ]
      Trailblazer::Invoke::Options.singleton_class.instance_variable_set(:@steps, steps)

      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |*|
          {
            # invoke_method: Trailblazer::Developer::Wtf.method(:invoke)
            **Trailblazer::Developer::Wtf.options_for_invoke
          }
        end
      end.new

      signal, ctx = nil

      stdout, _ = capture_io do
        signal, (ctx, flow_options) = kernel.__(Create, self.ctx)
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal stdout, create_trace
    end

    it "accepts {:adds_for_options_compiler} from {Developer}" do
      my_options_step = ->(*) do
        {
          # invoke_method: Object, # never called, hopefully.
        }
      end
      my_options_step = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step)

      steps = Trailblazer::Invoke::Options.singleton_class.instance_variable_get(:@steps)
      steps = steps + [
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step", my_options_step),
      ]
      Trailblazer::Invoke::Options.singleton_class.instance_variable_set(:@steps, steps)

      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |*|
          {
            # invoke_method: Trailblazer::Developer::Wtf.method(:invoke)
            # TODO: add something here.
          }
        end
      end.new

      signal, ctx, flow_options = nil

      stdout, _ = capture_io do
        signal, (ctx, flow_options) = kernel.__(
          Create,
          self.ctx,

          **Trailblazer::Developer::Wtf.options_for_canonical_invoke # TODO: test the option explicitly .
        )
      end

      assert_equal flow_options[:stack].to_a.size, 8

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal stdout, create_trace
    end

    it "{#__} accepts {:adds_for_options_compiler} option to add additional option compilation steps for options-compiler" do
      my_options_step = ->(*) do
        {
          flow_options:{
            my_options_step: true,
          }
        }
      end
      my_options_step = Trailblazer::Invoke::Options::HeuristicMerge.build(my_options_step)

      steps = Trailblazer::Invoke::Options.singleton_class.instance_variable_get(:@steps)
      steps = steps + [
        Trailblazer::Activity::TaskWrap::Pipeline.Row("my_options_step", my_options_step),
      ]
      Trailblazer::Invoke::Options.singleton_class.instance_variable_set(:@steps, steps)

      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |*|
          {
            flow_options: {
              my_user_block: true,
            }
          }
        end
      end.new

      # This is the interface for extensions like wtf and trailblazer-pro.
      # We use the automatic "deep merge" wrapper.
      my_options_via_adds = Trailblazer::Invoke::Options::HeuristicMerge.build(
        ->(activity, options, **kws) {
          {
            flow_options: {
              activity: activity,
              ctx: options.inspect
            }
          }
        }
      )

      my_adds = [
        [my_options_via_adds, id: "my_options_via_adds", append: nil]
      ]

      signal, (ctx, flow_options) = kernel.__(
        Capture, {},
        adds_for_options_compiler: my_adds
      )

      assert_equal CU.strip(CU.inspect(ctx.to_h)), %({:captured_flow_options=>\"{:my_options_step=>true, :my_user_block=>true, :activity=>CanonicalInvokeTest::Capture, :ctx=>\\\"{}\\\"}\", :captured_circuit_options=>\"{:exec_context=>#<CanonicalInvokeTest::Capture:0x>, :wrap_runtime=>{}, :activity=>#<Trailblazer::Activity:0x>, :runner=>Trailblazer::Activity::TaskWrap::Runner}\"})
    end
  end

  describe "with matcher interface" do
    let(:kernel) do
      Class.new do
        Trailblazer::Invoke.module!(self) do |*|
          {
            # invoke_method: Trailblazer::Developer::Wtf.method(:invoke),
            **Trailblazer::Developer::Wtf.options_for_invoke
          }
        end
      end.new
    end

    it "{#__} accepts a block/matcher and doesn't (unfortunately) exec block in its original context, and provides a {:default_matcher}" do
      signal, ctx = nil

    # success
      stdout, _ = capture_io do
        signal, (ctx, flow_options) = kernel.__(Create, self.ctx) do
          success { |ctx, model:, **| @render = model.inspect }
        end
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal CU.inspect(ctx.inspect), %(#<Trailblazer::Context::Container wrapped_options={:seq=>[:model], :model=>Object} mutable_options={}>)
      assert_equal stdout, create_trace
      assert_equal @render, nil # block executed in different context.

    # failure
      stdout, _ = capture_io do
        signal, (ctx, flow_options) = kernel.__(Create, {model: false, seq: []}) do
          failure { |ctx, model:, **| @render = model.inspect + " failed" }
        end
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:failure>)
      assert_equal stdout, %(CanonicalInvokeTest::Create
|-- \e[32mStart.default\e[0m
|-- \e[33mmodel\e[0m
`-- End.failure
)
      assert_equal @render, nil
    end

    it "accepts {:default_matcher} and {:matcher_context}" do
      default_matcher = {failure: ->(ctx, model:, **) { @render = model.inspect + " failed" }}

    # success
      signal, (ctx, flow_options) = kernel.__(Create, self.ctx, matcher_context: self, default_matcher: default_matcher) do
        success { |ctx, model:, **| @render = model.inspect }
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal @render, %(Object)

    # failure
      signal, (ctx, flow_options) = kernel.__(Create, {model: false, seq: []}, matcher_context: self, default_matcher: default_matcher) do
        success { |ctx, model:, **| @render = model.inspect }
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:failure>)
      assert_equal @render, %(false failed)
    end
  end

  def assert_create_run(signal, ctx)
    assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
    assert_equal ctx[:model], Object
    assert_equal ctx[:record], Object
    assert_equal ctx.keys, [:seq, :model, :record]
  end
end

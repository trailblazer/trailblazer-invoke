require "test_helper"

# Tests #__()
class CanonicalInvokeTest < Minitest::Spec
  class Create < Trailblazer::Activity::FastTrack
    step :model
    include T.def_steps(:model)
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

  describe "module!(self) without options" do
    let(:kernel) {
      Class.new { Trailblazer::Invoke.module!(self) }.new
    }

    it "calls the activity, and returns original resultset" do
      signal, (ctx,) = kernel.__(Create, self.ctx)

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal ctx.class, Trailblazer::Context::Container#::WithAliases
      assert_equal ctx[:model], Object
      assert_equal ctx.keys, [:seq, :model]

      # TODO: test flow_options

      stdout, _ = capture_io do
        signal, (ctx,) = kernel.__?(Create, self.ctx)
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal ctx.class, Trailblazer::Context::Container#::WithAliases
      assert_equal ctx[:model], Object
      assert_equal ctx.keys, [:seq, :model]
      assert_equal stdout, create_trace
    end

    it "allows passing {:flow_options} to {#__}" do
      _FLOW_OPTIONS = {
        context_options: {
          aliases: {"model": :record},
          container_class: Trailblazer::Context::Container::WithAliases,
        }
      }

      signal, (ctx,) = kernel.__(Create, self.ctx, flow_options: _FLOW_OPTIONS)

      assert_equal ctx.class, Trailblazer::Context::Container::WithAliases
      assert_create_run(signal, ctx)

      stdout, _ = capture_io do
        signal, (ctx,) = kernel.__?(Create, self.ctx, flow_options: _FLOW_OPTIONS)
      end

      assert_create_run(signal, ctx)
      assert_equal stdout, create_trace
    end

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

  describe "module!(self) with dynamic args" do
    it "allows passing arbitrary options to {#__}, such as {:enable_tracing} and allows setting {:invoke_method} and {:flow_options}" do
      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |activity, options, enable_tracing:, **|
          # This tests we can pass arbitrary options such as {:enable_tracing},
          # and that we can set invoke_method
          runtime_call_keywords = enable_tracing ? {invoke_method: Trailblazer::Developer::Wtf.method(:invoke)} : {}

          {
            flow_options: {
              context_options: {
                aliases: {"model": :record},
                container_class: Trailblazer::Context::Container::WithAliases,
              },
            },

            **runtime_call_keywords, # {:invoke_method}
          }
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
      assert_equal flow_options[:arguments_we_can_see], [CanonicalInvokeTest::Create, "{:seq=>[], :model=>Object}", "{:enable_tracing=>false}"]
    end

    it "we can set {:circuit_options}" do
      kernel = Class.new do
        Trailblazer::Invoke.module!(self) do |*|
          {
            invoke_method: Trailblazer::Developer::Wtf.method(:invoke),

            circuit_options: {
              present_options: {render_method: ->(renderer:, **) { renderer.inspect }}
            },
          }
        end
      end.new

      signal, ctx = nil

      stdout, _ = capture_io do
        signal, (ctx, flow_options) = kernel.__(Create, self.ctx)
      end

      assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
      assert_equal stdout, %(Trailblazer::Developer::Wtf::Renderer\n)
    end
  end

  describe "with matcher interface" do
    let(:kernel) do
      Class.new do
        Trailblazer::Invoke.module!(self) do |*|
          {
            invoke_method: Trailblazer::Developer::Wtf.method(:invoke),
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

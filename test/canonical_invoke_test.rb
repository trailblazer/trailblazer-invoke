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

    it "calls the activity" do
      signal, (ctx,) = kernel.__(Create, self.ctx)
      assert_equal ctx[:model], Object
      assert_equal ctx.keys, [:seq, :model]

      stdout, _ = capture_io do
        signal, (ctx,) = kernel.__?(Create, self.ctx)
      end

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
      assert_equal ctx[:model], Object
      assert_equal ctx[:record], Object
      assert_equal ctx.keys, [:seq, :model, :record]

      stdout, _ = capture_io do
        signal, (ctx,) = kernel.__?(Create, self.ctx, flow_options: _FLOW_OPTIONS)
      end

      assert_equal ctx[:model], Object
      assert_equal ctx.keys, [:seq, :model, :record]
      assert_equal stdout, create_trace
    end
  end

end

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
      assert_equal stdout, %(CanonicalInvokeTest::Create
|-- \e[32mStart.default\e[0m
|-- \e[32mmodel\e[0m
`-- End.success
)
    end

  end

  it "can be used without setting dynamic_args" do


          kernel = Class.new do
      include Trailblazer::Invoke.module!(self)


      def __(operation, ctx, flow_options: FLOW_OPTIONS, **, &block)
        super
      end

      FLOW_OPTIONS = {
        context_options: {
          aliases: {"model": :record},
          container_class: Trailblazer::Context::Container::WithAliases,
        }
      }
    end

    signal, (ctx,) = kernel.new.__(Create, self.ctx) # FLOW_OPTIONS are applied!

    assert_equal ctx[:record], Object

    stdout, _ = capture_io do
      signal, (ctx,) = kernel.new.__?(Create, self.ctx) # FLOW_OPTIONS are applied!
    end

    assert_equal ctx[:record], Object
    assert_equal stdout, %(RuntimeTest::Create
|-- \e[32mStart.default\e[0m
|-- \e[32mmodel\e[0m
`-- End.success
)
  end
end

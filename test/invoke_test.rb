require "test_helper"

# This tests {Invoke.call}, the top-level entry point for end users.
class InvokeTest < Minitest::Spec
  class Create < Trailblazer::Activity::FastTrack
    step :model
    include T.def_steps(:model)
  end

  def render(content)
    @render = content
  end

  let(:ctx) { {seq: [], model: Object} }

  it "without block, accepts operation and {ctx}, and returns original returnset" do
    signal, (result, _) = Trailblazer::Invoke.(Create, ctx)

    assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
    assert_equal result.class, Trailblazer::Context::Container
    assert_equal CU.inspect(result.to_h), %({:seq=>[:model], :model=>Object})
  end

  it "it accepts {:flow_options}" do
    flow_options_with_aliasing = {
      context_options: {
        aliases: {"model": :record},
        container_class: Trailblazer::Context::Container::WithAliases,
      }
    }

    signal, (result, _) = Trailblazer::Invoke.(Create, ctx, flow_options: flow_options_with_aliasing)

    assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
    assert_equal result.class, Trailblazer::Context::Container::WithAliases
    assert_equal CU.inspect(result.to_h), %({:seq=>[:model], :model=>Object, :record=>Object})
    assert_equal result[:record], Object
  end

  it "accepts {:default_matcher}" do # DISCUSS: we don't need the explicit block in this case.
    default_matcher = {
      success:    ->(ctx, model:, **) { render "201, #{model}" },
      not_found:  ->(ctx, model:, **) { render "404, #{model} not found" },
      not_authorized: ->(*) { snippet },
    }

    signal, (result, _) = Trailblazer::Invoke.(Create, ctx, matcher_context: self, default_matcher: default_matcher) do
    end

    assert_equal @render, %(201, Object)
  end

  it "accepts a block" do
    signal, (result, _) = Trailblazer::Invoke.(Create, ctx, matcher_context: self) do
      success { |ctx, model:, **| render model.inspect }
    end

    assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
    assert_equal result.class, Trailblazer::Context::Container
    assert_equal CU.inspect(result.to_h), %({:seq=>[:model], :model=>Object})
    assert_equal @render, %(Object)
  end







  # FIXME: what is this test?
  it "using {Runtime::Matcher.call} without a Protocol" do
    ctx = {seq: [], model: Object}

    Trailblazer::Invoke::WithMatcher.(Create, ctx, default_matcher: {}, matcher_context: self) do
      success { |ctx, model:, **| render model.inspect }
    end

    assert_equal @render, %(Object)
  end
end

class ProtocolTest < Minitest::Spec
  def render(text)
    @rendered = text
  end

  class Create < Trailblazer::Activity::Railway
    include T.def_steps(:model, :validate, :save, :cc_check)

    def model(ctx, model: true, **)
      return unless model
      ctx[:model] = Object
    end

    step :model,    Output(:failure) => End(:not_found)
    # step :cc_check, Output(:failure) => End(:cc_invalid)
    # step :validate, Output(:failure) => End(:my_validation_error)
    step :save
  end


  it "{Runtime::Matcher.call} matcher block" do
    default_matcher = {
      success:    ->(*) { raise },
      not_found:  ->(ctx, model:, **) { render "404, #{model} not found" },
      not_authorized: ->(*) { snippet },
    }

    action_protocol = Class.new(Trailblazer::Activity::Railway) do
      terminus :not_authorized
      terminus :not_authenticated
      terminus :not_found
      step :authenticate, Output(:failure) => End(:not_authenticated)
      step :policy, Output(:failure) => End(:not_authorized)
      step Subprocess(Create), Output(:not_found) => Track(:not_found)
      include T.def_steps(:authenticate, :policy)
    end

    # this is usually in a controller action.
    matcher_block = Proc.new do
      success { |ctx, model:, **| render model.inspect }
      failure { |*| render "failure" }
      not_authorized { |ctx, model:, **| render "not authorized: #{model}" }
    end

    ctx = {seq: [], model: {id: 1}}

    Trailblazer::Invoke::WithMatcher.(action_protocol, ctx, default_matcher: default_matcher, matcher_context: self, &matcher_block)
    assert_equal @rendered, %(Object)

    ctx = {seq: [], model: {id: 1}}

    Trailblazer::Invoke::WithMatcher.(action_protocol, ctx.merge(model: false), default_matcher: default_matcher, matcher_context: self, &matcher_block)
    assert_equal @rendered, %(404, false not found)

    ctx = {seq: [], model: {id: 1}}

    Trailblazer::Invoke::WithMatcher.(action_protocol, ctx.merge(save: false), default_matcher: default_matcher, matcher_context: self, &matcher_block)
    assert_equal @rendered, %(failure)

    ctx = {seq: [], model: {id: 1}}

    Trailblazer::Invoke::WithMatcher.(action_protocol, ctx.merge(policy: false), default_matcher: default_matcher, matcher_context: self, &matcher_block)
    assert_equal @rendered, %(not authorized: {:id=>1})

    ctx = {seq: [], model: {id: 1}}

    assert_raises KeyError do
      Trailblazer::Invoke::WithMatcher.(action_protocol, ctx.merge(authenticate: false), default_matcher: default_matcher, matcher_context: self, &matcher_block)
      # assert_equal @rendered, %(404, false not found)
    end

    # endpoint "bla", ctx: {} do
    #   success do |ctx, model:, **|
    #     render model.inspect
    #   end
    # end

    # run "bla", ctx: {} do
    #   render model.inspect
    # end

    # Trailblazer::Invoke::WithMatcher.call ctx, adapter: action_adapter do
    #   success { |ctx, model:, **| render model.inspect }
    #   failure { |*| render "failure" }
    #   not_authorized { |ctx, model:, **| render "not authorized: #{model}" }
    # end
  end

  it "returns a {Trailblazer::Context}, and allows {flow_options}" do
    ctx = {seq: [], model: {id: 1}} # ordinary hash.

    flow_options_with_aliasing = {
      context_options: {
        aliases: {"model": :object},
        container_class: Trailblazer::Context::Container::WithAliases,
      }
    }

    signal, ((ctx, flow_options), circuit_options) = Trailblazer::Invoke::WithMatcher.(Create, ctx, default_matcher: default_matcher, matcher_context: self, flow_options: flow_options_with_aliasing, &matcher_block)

    assert_equal ctx.class, Trailblazer::Context::Container::WithAliases
    # assert_equal ctx.inspect, %(#<Trailblazer::Context::Container wrapped_options={:seq=>[:authenticate, :policy, :save], :model=>{:id=>1}} mutable_options={:model=>Object}>)
    assert_equal ctx.keys.inspect, %([:seq, :model, :object])
    assert_equal ctx[:seq].inspect, %([:save])
    assert_equal ctx[:model].inspect, %(Object)
    assert_equal ctx[:object].inspect, %(Object)
  end

  it "accepts {:flow_options} / USES  THE CORRECT ctx in TW and can access {:model} from the domain_activity" do # FIXME: two tests?
    protocol = Class.new(Trailblazer::Activity::Railway) do
      step task: :save
      terminus :not_found
      terminus :not_authenticated
      terminus :not_authorized

      def save((ctx, flow_options), **)
        ctx = ctx.merge(model: flow_options[:model])
        return Trailblazer::Activity::Right, [ctx, flow_options]
      end
    end

    # ctx doesn't contain {:model}, yet.
    Trailblazer::Invoke::WithMatcher.(protocol,  {}, flow_options: {model: Object}, default_matcher: default_matcher, matcher_context: self, &matcher_block)
    assert_equal @rendered, %(Object)
  end

  it "accepts {:circuit_options}" do
    stdout, _ = capture_io do
      Trailblazer::Invoke.(
        Create, {seq: []},

        circuit_options: {start_task: Trailblazer::Activity::Introspect.Nodes(Create, id: :model).task},
        invoke_method: Trailblazer::Developer::Wtf.method(:invoke), # needed for this test to see the trace.

        default_matcher: default_matcher, matcher_context: self, &matcher_block
      )
    end

    assert_equal @rendered, %(Object)
    assert_equal stdout, %(ProtocolTest::Create
|-- \e[32mmodel\e[0m
|-- \e[32msave\e[0m
`-- End.success
)
  end

  let(:matcher_block) do
    # this is usually in a controller action.
    matcher_block = Proc.new do
      success { |ctx, model:, **| render model.inspect }
    end
  end

  let(:default_matcher) { {} }

  it "Matcher.() allows other keyword arguments such as {:invoke_method}" do
    # ctx doesn't contain {:model}, yet.
    stdout, _ = capture_io do
      Trailblazer::Invoke::WithMatcher.(Create, {seq: []}, invoke_method: Trailblazer::Developer::Wtf.method(:invoke), default_matcher: default_matcher, matcher_context: self, &matcher_block)
    end

    assert_equal @rendered, %(Object)
    assert_equal stdout, %(ProtocolTest::Create
|-- \e[32mStart.default\e[0m
|-- \e[32mmodel\e[0m
|-- \e[32msave\e[0m
`-- End.success
)
  end

  it "PROTOTYPING canonical invoke" do
    # Must produce hash with :invoke_method, :circuit_options, :flow_options
    my_dynamic_arguments = ->(activity, options, flow_options_merge:, **) {
      runtime_call_keywords = [Create].include?(activity) ? {invoke_method: Trailblazer::Developer::Wtf.method(:invoke)} : {}

      circuit_options_option = {
        circuit_options: {
          present_options: {render_method: ->(renderer:, **) { renderer.inspect },}
        }
      }

      flow_options = flow_options_merge # this is to test that we can pass arbitrary data inside this block.
      flow_options_option = {flow_options: flow_options}

      {
        **runtime_call_keywords,
        **flow_options_option,
        **circuit_options_option,
      }
    }

    my_kernel = Class.new do
      Trailblazer::Invoke.module!(self, &my_dynamic_arguments)
    end

    my_kernel = my_kernel.new

    stdout, _ = capture_io do
      my_kernel.__(
        Create, {seq: []},
        default_matcher: default_matcher, matcher_context: self,

        flow_options_merge: {bla: 1}, # TODO: test that bla is there.
        &matcher_block
      )
    end

    assert_equal @rendered, %(Object)
    assert_equal stdout, %(Trailblazer::Developer::Wtf::Renderer
)

    # Test that the "decider" for {:invoke_method} really works.
    update_operation = Class.new(Trailblazer::Activity::Railway)

    stdout, _ = capture_io do
      my_kernel.__(
        update_operation, {model: "Yes!"},
        default_matcher: default_matcher, matcher_context: self,

        flow_options_merge: {bla: 1}, # TODO: test that bla is there.
        &matcher_block
      )
    end

    assert_equal @rendered, %("Yes!")
    assert_equal stdout, ""

  # We can override {:invoke_method}:
    stdout, _ = capture_io do
      my_kernel.__(
        update_operation, {model: "Yes!"},
        default_matcher: default_matcher, matcher_context: self,

        invoke_method: Trailblazer::Developer::Wtf.method(:invoke),

        flow_options_merge: {bla: 1}, # TODO: test that bla is there.
        &matcher_block
      )
    end

    assert_equal @rendered, %("Yes!")
    assert_equal stdout, %(Trailblazer::Developer::Wtf::Renderer
)
  end
end

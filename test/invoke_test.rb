require "test_helper"

# TODO: remove this test once we have everything covered in canonical_invoke_test.
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

end

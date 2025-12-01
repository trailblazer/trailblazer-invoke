require "test_helper"

class ActivityFileTest < Minitest::Spec
  it "adds XXX" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step :capture

      def capture(ctx, model:, record: nil, **)
        ctx[:model_in_capture] = "#{model.inspect} / alias:#{record.inspect}"
      end
    end

    require "trailblazer/invoke/activity" # Installs {Trailblazer::Activity.()}.

    signal, (ctx, _) = Trailblazer::Activity.(activity, model: true)

    assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
    assert_equal CU.inspect(ctx.to_h), %({:model=>true, :model_in_capture=>\"true / alias:nil\"})

    # test aliasing.
    Trailblazer::Invoke::Activity.configure! do # TODO: this shouldn't print a warning.
      {
        flow_options: {
          context_options: {
            aliases: {"model": :record},
            container_class: Trailblazer::Context::Container::WithAliases,
          },
        },
      }
    end

    signal, (ctx, _) = Trailblazer::Activity.(activity, model: true)

    assert_equal signal.inspect, %(#<Trailblazer::Activity::End semantic=:success>)
    # now we got aliasing.
    assert_equal CU.inspect(ctx.to_h), %({:model=>true, :record=>true, :model_in_capture=>\"true / alias:true\"})
  end
end

# Trailblazer::Invoke

Finally, a canonical implementation for invoking operations and activities.

Allows to configure injected variables like `flow_options` (for instance, to control which operation should use tracing, or to use `ctx` aliases.)

Provides a matcher block syntax to easily handle different operation outcomes.

This is mostly used internally, but the new `trailblazer-rails` controller layer will expose the optional matcher interface.

## Usage

NOTE: this is still WIP.

### Configure

Set default options using the block for `module!`.

```ruby
# config/initializers/trailblazer.rb
require "trailblazer/invoke"

Trailblazer::Invoke.module!(self) do |activity, options, **|
  # Return a hash that provides default options for invoking an operation.

  # For example, automatically trace operations when the {WTF} environment variable is set.
  options = ENV[:WTF] ? {invoke_method: Trailblazer::Developer::Wtf.method(:invoke)} : {}

  # Or, set a "global" ctx alias for "contract.default".
  {
    flow_options: {
      context_options: {
        aliases: {"contract.default": :contract},
        container_class: Trailblazer::Context::Container::WithAliases,
      }
    },
    **options,
  }
end
```

### Invoke

Use the "canonical invoke" to run operations and activities.

```ruby
signal, (ctx,) = __(Memo::Operation::Create, params: params)

ctx[:contract] #=> <Reform::Form ...>
```

The operation will now be run with the options configured via `module!`, allowing you to configure it to use aliasing, tracing, and whatever else you need.

Note that in future versions we will make `__()` an internal concept, as `Operation.call` will simply use the canonical invoke.

### Matcher

The canonical invoke provides an optional block to handle outcomes.

```ruby
signal, (ctx,) = __(Memo::Operation::Create, params: params) do
  success { |ctx, model:, **| render model }
  failure { |ctx, contract:, **| ... }
  not_found { ...  }
end
```


## Notes

before this, all gems had to override public_call etc, ordering problems, issues with activity vs OP, etc.
this also allows for compiling options like flow_options and present_options, invoke_method, etc
gems like pro can now in a central place, add their options on each OP call.



invoke is about "centralizing" how OPs and activities are called, configuring what gets injected, and provides a matcher block syntax

E.g. when you want to have a "global" wtf? ENV variable

Basically invoke provides a "central" method to invoke OPs, and some super simple mechanism to compile various options for each call (like tracing yes/no)


invoke compiles its own container_activity and uses the TaskWrap.invoke( container_activity: ) option.



idea is to have an "endpoint" for running activities, like a "meta activity", so everything is consistent.

we also create the Context instance

DISCUSS: don't override call to plug in another wrap_runtime, use an Options step.




1. invoking an OP is all about passing options
2. this used to be quite "messy", wtf calling trace calling TaskWrap.invoke, manually merging options etc, plus your own monkey-patches
3. options merging is now done by options-compiler
  6. TODO: merging {:wrap_runtime}.
4. invoking the actual activity is always TaskWrap.invoke
5. also supports block/matcher syntax

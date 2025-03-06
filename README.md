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

invoke is about "centralizing" how OPs and activities are called, configuring what gets injected, and provides a matcher block syntax

E.g. when you want to have a "global" wtf? ENV variable

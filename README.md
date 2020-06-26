# SafeExecEnv

It is often desirable to run natively compiled code (C, C++, Rust, ..) from a BEAM
application via a binding. The motivation may be better performance or simply to access
an external library that already exists. The problem is that if that native code crashes
then, unlike with native BEAM processest, he entire VM will crash, taking your
application along with it, 

SafeExecEnv provides a safe(r) way to run natively compiled code from a BEAM application.
If the native code in question can be reasonably expected to never crash, then this
precaution is unecessary, but if native code that might crash is being run then this
library provides a layer of insulation between the code being executed and the virtual
machine the main application is being run on.

## Installation

The package can be installed by adding `safe_exec_env` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:safe_exec_env, "~> 0.1.0"}
  ]
end
```

Docs can be found at [https://hexdocs.pm/safe_exec_env](https://hexdocs.pm/safe_exec_env).


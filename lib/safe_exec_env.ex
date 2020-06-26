defmodule SafeExecEnv do
  @moduledoc """
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

  Using SafeExecEnv is easy; simply add it to a Supervisor:

      defmodule MyApplication do
        def start(_type, _args) do
          children = [SafeExecEnv]
          opts = [strategy: :one_for_one, name: MyApplication.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  Then you may run functions safely by calling SafeExecEnv::exec with the function. Captured,
  anonymous, and Module / Function / Arguments (MFA) style function passing is supported.

  SafeExecEnv works by spawning a second BEAM VM to run the functions in. If that VM crashes
  then the SafeExecEnv server will also crash. When supervised, this will cause the SafeExenv
  to be restarted, and the external VM will be started again. Calls to SafeExecEnv may
  fail during that time, and will need to be tried again once available.
  """

  require Logger
  use GenServer

  @ets_table_name :safe_exec_env
  @safe_exec_node_name "SafeExecEnv_"

  @doc """
  Executes a function in the safe executable environment and returns the result.
  The SafeExecEnv server is presumed to be started.
  """
  @spec exec(fun :: function) :: any | {:error, reason :: String.t()}
  def exec(fun) when is_function(fun) do
    me = self()

    f = fn ->
      rv =
        try do
          fun.()
        rescue
          e -> {:error, e}
        end

      Process.send(me, rv, [])
    end

    try do
      Node.spawn(node_name(), f)
      return_value()
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Executes a function with the provided argument (in usual "MFA" form) in the safe 
  executable environment and returns the result. The SafeExecEnv server is presumed to be
  started.
  """
  @spec exec(module :: atom, fun :: atom, args :: list) :: any | {:error, reason :: String.t()}
  def exec(module, fun, args) do
    me = self()

    f = fn ->
      rv =
        try do
          apply(module, fun, args)
        rescue
          e -> {:error, e}
        end

      Process.send(me, rv, [])
    end

    try do
      Node.spawn(node_name(), f)
      return_value()
    rescue
      e -> {:error, e}
    end
  end

  @doc "Returns the name of the BEAM node being used as the safe exec environment"
  @spec get() :: String.t()
  def get() do
    case node_name() do
      nil -> GenServer.call(__MODULE__, :start_node)
      node -> node
    end
  end

  @doc "Returns true if the node is running and reachable, otherwise false"
  @spec is_alive?() :: boolean
  def is_alive?() do
    case Node.ping(node_name()) do
      :pong -> true
      _ -> false
    end
  end

  @doc false
  @spec start_link(args :: any) :: {:ok, pid}
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    start_node()
    {:ok, :ok}
  end

  @impl GenServer
  def handle_call(:start_node, _, state) do
    node = start_node()
    {:reply, node, state}
  end

  defp return_value() do
    receive do
      rv -> rv
    end
  end

  defp start_ets() do
    if :ets.info(@ets_table_name) == :undefined do
      @ets_table_name =
        :ets.new(@ets_table_name, [:named_table, :public, {:read_concurrency, true}])
    end
  end

  defp start_node() do
    check_distribution()
    start_ets()
    {:ok, node} = SafeExecEnv.ExternNode.start(generate_node_name(), self())
    :ets.insert(@ets_table_name, {:safe_exec_node, node})
    node
  end

  defp check_distribution(), do: :erlang.get_cookie() |> has_cookie?()

  defp has_cookie?(:nocookie) do
    Logger.error(
      "SafeExecEnv can not start as the BEAM was not started in distributed mode. Start the vm with the name or sname command line option."
    )

    Process.exit(self(), :kill)
    false
  end

  defp has_cookie?(_), do: true

  defp node_name() do
    case :ets.lookup(@ets_table_name, :safe_exec_node) do
      [] -> nil
      [{_key, value}] -> value
    end
  end

  defp generate_node_name() do
    node()
    |> Atom.to_string()
    |> String.split("@")
    |> (fn [x | _] -> @safe_exec_node_name <> x end).()
    |> String.to_charlist()
  end
end

defmodule SafeExecEnv.ExternNode do
  @moduledoc false
  @timeout_period 5000

  def start(name, linkTo) when is_bitstring(name) do
    name
    |> String.to_charlist()
    |> start(linkTo)
  end

  def start(name, linkTo) when is_list(name) do
    host = :net_adm.localhost()
    start(host, name, linkTo, :net_kernel.longnames())
  end

  defp start(host, name, linkTo, true) do
    :net_adm.dns_hostname(host)
    |> create_node_name(name)
    |> (fn node -> start_node_if_mia(node, linkTo, Node.ping(node)) end).()
  end

  defp start(host, name, linkTo, _short_node_names) do
    host_name_only(host)
    |> create_node_name(name)
    |> (fn node -> start_node_if_mia(node, linkTo, Node.ping(node)) end).()
  end

  defp create_node_name({:ok, host}, name), do: create_node_name(host, name)
  defp create_node_name(host, name), do: List.to_atom(name ++ ~c"@" ++ host)

  defp start_node_if_mia(node, _linkTo, :pong), do: {:ok, node}

  defp start_node_if_mia(node, linkTo, _) do
    spawn(__MODULE__, :spawn_node, [self(), node, linkTo])

    receive do
      {:result, result} -> result
    end
  end

  def stop(node) do
    Node.spawn(node, :erlang, :halt, [])
    :ok
  end

  def spawn_node(parent, node, linkTo) do
    waiter = register_unique_name()
    erl_command = command(node, waiter)
    Port.open({:spawn, erl_command}, [:stream])

    receive do
      {:slave_started, slave_pid} ->
        slave_node = node(slave_pid)
        Process.unregister(waiter)
        Process.flag(:trap_exit, true)
        Process.link(linkTo)
        Process.link(slave_pid)
        Node.monitor(slave_node, true)
        send(parent, {:result, {:ok, slave_node}})
        one_way_link(parent, slave_pid, slave_node)
    after
      @timeout_period ->
        # If it seems that the node was partially started,
        # try to kill it.
        case :net_adm.ping(node) do
          :pong -> stop(node)
          _ -> :ok
        end

        send(parent, {:result, {:error, :timeout}})
    end
  end

  defp one_way_link(master, slave_pid, slave_node) do
    receive do
      {:nodedown, ^slave_node} ->
        Process.unlink(master)
        Process.exit(master, :kill)

      {:EXIT, ^master, _reason} ->
        Process.unlink(slave_pid)
        send(slave_pid, {:nodedown, node()})

      {:EXIT, ^slave_pid, _reason} ->
        Process.unlink(master)
        Process.exit(master, :kill)

      _msg ->
        one_way_link(master, slave_pid, slave_node)
    end
  end

  defp register_unique_name(), do: register_unique_name(0)

  defp register_unique_name(number) do
    name = String.to_atom("slave_waiter_" <> Integer.to_string(number))

    try do
      Process.register(self(), name)
      name
    rescue
      _ in ArgumentError -> register_unique_name(number + 1)
    end
  end

  def command(name, waiter) do
    cookie =
      :erlang.get_cookie()
      |> Atom.to_charlist()

    args =
      :code.get_path()
      |> Enum.reduce(~c'-setcookie "' ++ cookie ++ ~c'" -hidden -pa ', fn path, acc ->
        acc ++ ~c" " ++ path
      end)
      |> add_boot_file_to_args()

    erl_binary = System.find_executable("erl")

    "#{erl_binary} -detached -noinput -master #{node()} #{cli_node_name_switch()} #{name} -s #{__MODULE__} slave_start #{node()} #{waiter} #{args}"
  end

  defp add_boot_file_to_args(args) when is_list(args) do
    if File.exists?(File.cwd!() <> "/bin/start_clean.boot") do
      args ++ ~c" -boot " ++ String.to_charlist(File.cwd()) ++ ~c"/bin/start_clean"
    else
      args
    end
  end

  defp cli_node_name_switch(), do: cli_node_name_switch(:net_kernel.longnames())
  defp cli_node_name_switch(true), do: "-name"
  defp cli_node_name_switch(_), do: "-sname"

  def slave_start([master, waiter]),
    do: spawn(__MODULE__, :wait_for_master_to_die, [master, waiter])

  def wait_for_master_to_die(master, waiter) do
    Process.flag(:trap_exit, true)
    Node.monitor(master, true)
    send({waiter, master}, {:slave_started, self()})
    child_monitor_loop(master)
  end

  def child_monitor_loop(master) do
    receive do
      {:nodedown, ^master} -> System.halt()
      _ -> child_monitor_loop(master)
    end
  end

  def host_name_only([]), do: []
  def host_name_only([?. | _]), do: []
  def host_name_only([h | t]), do: [h | host_name_only(t)]
end

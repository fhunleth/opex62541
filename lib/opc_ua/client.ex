defmodule OpcUA.Client do
  use OpcUA.Common

  @config_keys ["requestedSessionTimeout", "secureChannelLifeTime", "timeout"]

   @moduledoc """

  OPC UA Client API module.

  This module provides functions for configuration, read/write nodes attributes and discovery of a OPC UA Client.

  `OpcUA.Client` is implemented as a `__using__` macro so that you can put it in any module,
  you can initialize your Client manually (see `test/client_tests`) or by overwriting
  `configuration/0` and `monitored_items` to autoset the configuration and subscription items. It also helps you to
  handle Client's "subscription" events (monitorItems) by overwriting `handle_subscription/2` callback.

  The following example shows a module that takes its configuration from the enviroment (see `test/client_tests/terraform_test.exs`):

  ```elixir
  defmodule MyClient do
    use OpcUA.Client
    alias OpcUA.Client

    # Use the `init` function to configure your Client.
    def init({parent_pid, 103} = _user_init_state, opc_ua_client_pid) do
      %{parent_pid: parent_pid}
    end

    def configuration(), do: Application.get_env(:opex62541, :configuration, [])
    def monitored_items(), do: Application.get_env(:opex62541, :monitored_items, [])

    def handle_write(write_event, %{parent_pid: parent_pid} = state) do
      send(parent_pid, write_event)
      state
    end
  end
  ```

  Because it is small a GenServer, it accepts the same [options](https://hexdocs.pm/elixir/GenServer.html#module-how-to-supervise) for supervision
  to configure the child spec and passes them along to `GenServer`:

  ```elixir
  defmodule MyModule do
    use OpcUA.Client, restart: :transient, shutdown: 10_000
  end
  ```
  """

  @type conn_params ::
          {:hostname, binary()}
          | {:port, non_neg_integer()}
          | {:users, keyword()}


  @type config_options ::
          {:config, map()}
          | {:conn, conn_params}

  @doc """
  Optional callback that gets the Server configuration and discovery connection parameters.
  """
  @callback configuration(term()) :: config_options

  #TODO:
  @type monitored_items_options ::
          {:config, map()}
          | {:connection, {binary(), non_neg_integer()}}

  @callback monitored_items(term()) :: monitored_items_options

  @doc """
  Optional callback that handles node values updates from a Client to a Server.

  It's first argument will a tuple, in which its first element is the `node_id` of the monitored node
  and the second element is the updated value.

  the second argument it's the GenServer state (Parent process).
  """
  @callback handle_monitored_data({integer(), integer(), any()}, term()) :: term()

  @callback handle_deleted_monitored_item(integer(), integer(), term()) :: term()

  @callback handle_subscription_timeout(integer(), term()) :: term()

  @callback handle_deleted_subscription(integer(), term()) :: term()

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use GenServer, Keyword.drop(opts, [:configuration])
      @behaviour OpcUA.Client

      alias __MODULE__

      def start_link(user_initial_params \\ []) do
        GenServer.start_link(__MODULE__, user_initial_params, unquote(opts))
      end

      @impl true
      def init(user_initial_params) do
        send self(), :init
        {:ok, user_initial_params}
      end

      @impl true
      def handle_info(:init, user_initial_params) do

        # Client Terraform
        {:ok, c_pid} = OpcUA.Client.start_link()
        configuration = apply(__MODULE__, :configuration, [user_initial_params])
        monitored_items = apply(__MODULE__, :monitored_items, [user_initial_params])

        OpcUA.Client.set_config(c_pid)

        # configutation = [config: list(), connection: list()]
        set_client_config(c_pid, configuration, :config)
        set_client_config(c_pid, configuration, :conn)

        # address_space = [namespace: "", namespace: "", variable: %VariableNode{}, ...]
        set_client_monitored_items(c_pid, monitored_items)

        # User initialization.
        user_state = apply(__MODULE__, :init, [user_initial_params, c_pid])

        {:noreply, user_state}
      end

      def handle_info({:timeout, subscription_id}, state) do
        state = apply(__MODULE__, :handle_subscription_timeout, [subscription_id, state])
        {:noreply, state}
      end

      def handle_info({:delete, subscription_id}, state) do
        state = apply(__MODULE__, :handle_deleted_subscription, [subscription_id, state])
        {:noreply, state}
      end

      def handle_info({:data, subscription_id, monitored_id, value}, state) do
        state = apply(__MODULE__, :handle_monitored_data, [{subscription_id, monitored_id, value}, state])
        {:noreply, state}
      end

      def handle_info({:delete, subscription_id, monitored_id}, state) do
        state = apply(__MODULE__, :handle_deleted_monitored_item, [subscription_id, monitored_id, state])
        {:noreply, state}
      end

      @impl true
      def handle_subscription_timeout(subscription_id, state) do
        require Logger
        Logger.warn("No handle_subscription_timeout/2 clause in #{__MODULE__} provided for #{inspect(subscription_id)}")
        state
      end

      @impl true
      def handle_deleted_subscription(subscription_id, state) do
        require Logger
        Logger.warn("No handle_deleted_subscription/2 clause in #{__MODULE__} provided for #{inspect(subscription_id)}")
        state
      end

      @impl true
      def handle_monitored_data(changed_data_event, state) do
        require Logger
        Logger.warn("No handle_monitored_data/2 clause in #{__MODULE__} provided for #{inspect(changed_data_event)}")
        state
      end

      @impl true
      def handle_deleted_monitored_item(subscription_id, monitored_id, state) do
        require Logger
        Logger.warn("No handle_deleted_monitored_item/3 clause in #{__MODULE__} provided for #{inspect({subscription_id, monitored_id})}")
        state
      end

      @impl true
      def configuration(_user_init_state), do: []

      @impl true
      def monitored_items(_user_init_state), do: []

      defp set_client_config(c_pid, configuration, type) do
        config_params = Keyword.get(configuration, type, [])
        Enum.each(config_params, fn(config_param) -> GenServer.call(c_pid, {type, config_param}) end)
      end

      defp set_client_monitored_items(c_pid, monitored_items) do
        Enum.each(monitored_items, fn(monitored_item) -> GenServer.call(c_pid, {:add, {:monitored_item, monitored_item}}) end)
      end

      defoverridable  start_link: 0,
                      start_link: 1,
                      configuration: 1,
                      monitored_items: 1,
                      handle_subscription_timeout: 2,
                      handle_deleted_subscription: 2,
                      handle_monitored_data: 2,
                      handle_deleted_monitored_item: 3
    end
  end

  # Configuration & Lifecycle functions

  @doc """
    Starts up a OPC UA Client GenServer.
  """
  @spec start_link(term(), list()) :: {:ok, pid} | {:error, term} | {:error, :einval}
  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, {args, self()}, opts)
  end

  @doc """
    Stops a OPC UA Client GenServer.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  @doc """
    Gets the state of the OPC UA Client.
  """
  @spec get_state(GenServer.server()) :: {:ok, binary()} | {:error, term} | {:error, :einval}
  def get_state(pid) do
    GenServer.call(pid, {:config, {:get_state, nil}})
  end

  @doc """
    Sets the OPC UA Client configuration.
  """
  @spec set_config(GenServer.server(), map()) :: :ok | {:error, term} | {:error, :einval}
  def set_config(pid, args \\ %{}) when is_map(args) do
    GenServer.call(pid, {:config, {:set_config, args}})
  end

  @doc """
    Gets the OPC UA Client current Configuration.
  """
  @spec get_config(GenServer.server()) :: {:ok, map()} | {:error, term} | {:error, :einval}
  def get_config(pid) do
    GenServer.call(pid, {:config, {:get_config, nil}})
  end

  @doc """
    Resets the OPC UA Client.
  """
  @spec reset(GenServer.server()) :: :ok | {:error, term} | {:error, :einval}
  def reset(pid) do
    GenServer.call(pid, {:config, {:reset_client, nil}})
  end

  # Connection functions

  @doc """
    Connects the OPC UA Client by a url.
    The following must be filled:
    * `:url` -> binary().
  """
  @spec connect_by_url(GenServer.server(), list()) :: :ok | {:error, term} | {:error, :einval}
  def connect_by_url(pid, args) when is_list(args) do
    GenServer.call(pid, {:conn, {:by_url, args}})
  end

  @doc """
    Connects the OPC UA Client by a url using a username and a password.
    The following must be filled:
    * `:url` -> binary().
    * `:user` -> binary().
    * `:password` -> binary().
  """
  @spec connect_by_username(GenServer.server(), list()) :: :ok | {:error, term} | {:error, :einval}
  def connect_by_username(pid, args) when is_list(args) do
    GenServer.call(pid, {:conn, {:by_username, args}})
  end

  @doc """
    Connects the OPC UA Client by a url without a session.
    The following must be filled:
    * `:url` -> binary().
  """
  @spec connect_no_session(GenServer.server(), list()) :: :ok | {:error, term} | {:error, :einval}
  def connect_no_session(pid, args) when is_list(args) do
    GenServer.call(pid, {:conn, {:no_session, args}})
  end

  @doc """
    Disconnects the OPC UA Client.
  """
  @spec disconnect(GenServer.server()) :: :ok | {:error, term} | {:error, :einval}
  def disconnect(pid) do
    GenServer.call(pid, {:conn, {:disconnect, nil}})
  end

  # Discovery functions

  @doc """
    Finds Servers Connected to a Discovery Server.
    The following must be filled:
    * `:url` -> binary().
  """
  @spec find_servers_on_network(GenServer.server(), binary()) :: :ok | {:error, term} | {:error, :einval}
  def find_servers_on_network(pid, url) when is_binary(url) do
    GenServer.call(pid, {:discovery, {:find_servers_on_network, url}})
  end

  @doc """
    Finds Servers Connected to a Discovery Server.
    The following must be filled:
    * `:url` -> binary().
  """
  @spec find_servers(GenServer.server(), binary()) :: :ok | {:error, term} | {:error, :einval}
  def find_servers(pid, url) when is_binary(url) do
    GenServer.call(pid, {:discovery, {:find_servers, url}})
  end

  @doc """
    Get endpoints from a OPC UA Server.
    The following must be filled:
    * `:url` -> binary().
  """
  @spec get_endpoints(GenServer.server(), binary()) :: :ok | {:error, term} | {:error, :einval}
  def get_endpoints(pid, url) when is_binary(url) do
    GenServer.call(pid, {:discovery, {:get_endpoints, url}})
  end

  # Subscriptions and Monitored Items functions.

  @doc """
    Sends an OPC UA Server request to start subscription (to monitored items, events, etc).
  """
  @spec add_subscription(GenServer.server()) :: {:ok, integer()} | {:error, term} | {:error, :einval}
  def add_subscription(pid) do
    GenServer.call(pid, {:subscription, {:subscription, nil}})
  end

  @doc """
    Sends an OPC UA Server request to delete a subscription.
  """
  @spec delete_subscription(GenServer.server(), integer()) :: :ok | {:error, term} | {:error, :einval}
  def delete_subscription(pid, subscription_id) when is_integer(subscription_id) do
    GenServer.call(pid, {:subscription, {:delete, subscription_id}})
  end

  @doc """
    Adds a monitored item used to request a server for notifications of each change of value in a specific node.
    The following option must be filled:
    * `:subscription_id` -> integer().
    * `:monitored_item` -> %NodeId{}.
  """
  @spec add_monitored_item(GenServer.server(), list()) :: {:ok, integer()} | {:error, term} | {:error, :einval}
  def add_monitored_item(pid, args) when is_list(args) do
    GenServer.call(pid, {:subscription, {:monitored_item, args}})
  end

  @doc """
    Adds a monitored item used to request a server for notifications of each change of value in a specific node.
    The following option must be filled:
    * `:subscription_id` -> integer().
    * `:monitored_item_id` -> integer().
  """
  @spec delete_monitored_item(GenServer.server(), list()) :: :ok | {:error, term} | {:error, :einval}
  def delete_monitored_item(pid, args) when is_list(args) do
    GenServer.call(pid, {:subscription, {:delete_monitored_item, args}})
  end

  @doc false
  def command(pid, request) do
    GenServer.call(pid, request)
  end

  # Handlers
  def init({_args, controlling_process}) do
    lib_dir =
      :opex62541
      |> :code.priv_dir()
      |> to_string()
      |> set_ld_library_path()

    executable = lib_dir <> "/opc_ua_client"

    port =
      Port.open({:spawn_executable, to_charlist(executable)}, [
        {:args, []},
        {:packet, 2},
        :use_stdio,
        :binary,
        :exit_status
      ])

    state = %State{port: port, controlling_process: controlling_process}
    {:ok, state}
  end

  # Lifecycle Handlers

  def handle_call({:config, {:get_state, nil}}, caller_info, state) do
    call_port(state, :get_client_state, caller_info, nil)
    {:noreply, state}
  end

  def handle_call({:config, {:set_config, args}}, caller_info, state) do
    c_args =
      Enum.reduce(args, %{}, fn {key, value}, acc ->
        if is_nil(value) or key not in @config_keys do
          acc
        else
          Map.put(acc, key, value)
        end
      end)

    call_port(state, :set_client_config, caller_info, c_args)
    {:noreply, state}
  end

  def handle_call({:config, {:get_config, nil}}, caller_info, state) do
    call_port(state, :get_client_config, caller_info, nil)
    {:noreply, state}
  end

  def handle_call({:config, {:reset_client, nil}}, caller_info, state) do
    call_port(state, :reset_client, caller_info, nil)
    {:noreply, state}
  end

  # Connect to a Server Handlers

  def handle_call({:conn, {:by_url, args}}, caller_info, state) do
    url = Keyword.fetch!(args, :url)
    call_port(state, :connect_client_by_url, caller_info, url)
    {:noreply, state}
  end

  def handle_call({:conn, {:by_username, args}}, caller_info, state) do
    url = Keyword.fetch!(args, :url)
    username = Keyword.fetch!(args, :user)
    password = Keyword.fetch!(args, :password)

    c_args = {url, username, password}
    call_port(state, :connect_client_by_username, caller_info, c_args)
    {:noreply, state}
  end

  def handle_call({:conn, {:no_session, args}}, caller_info, state) do
    url = Keyword.fetch!(args, :url)
    call_port(state, :connect_client_no_session, caller_info, url)
    {:noreply, state}
  end

  def handle_call({:conn, {:disconnect, nil}}, caller_info, state) do
    call_port(state, :disconnect_client, caller_info, nil)
    {:noreply, state}
  end

  # Discovery Handlers.

  def handle_call({:discovery, {:find_servers_on_network, url}}, caller_info, state) do
    call_port(state, :find_servers_on_network, caller_info, url)
    {:noreply, state}
  end

  def handle_call({:discovery, {:find_servers, url}}, caller_info, state) do
    call_port(state, :find_servers, caller_info, url)
    {:noreply, state}
  end

  def handle_call({:discovery, {:get_endpoints, url}}, caller_info, state) do
    call_port(state, :get_endpoints, caller_info, url)
    {:noreply, state}
  end

  # Subscriptions and Monitored Items functions.

  def handle_call({:subscription, {:subscription, nil}}, caller_info, state) do
    call_port(state, :add_subscription, caller_info, nil)
    {:noreply, state}
  end

  def handle_call({:subscription, {:delete, subscription_id}}, caller_info, state) do
    call_port(state, :delete_subscription, caller_info, subscription_id)
    {:noreply, state}
  end

  def handle_call({:subscription, {:monitored_item, args}}, caller_info, state) do
    with  monitored_item <- Keyword.fetch!(args, :monitored_item) |> to_c(),
          subscription_id <- Keyword.fetch!(args, :subscription_id),
          true <- is_integer(subscription_id) do
      c_args = {monitored_item, subscription_id}
      call_port(state, :add_monitored_item, caller_info, c_args)
      {:noreply, state}
    else
      _ ->
        {:reply, {:error, :einval} ,state}
    end
  end

  def handle_call({:subscription, {:delete_monitored_item, args}}, caller_info, state) do
    with  monitored_item_id <- Keyword.fetch!(args, :monitored_item_id),
          subscription_id <- Keyword.fetch!(args, :subscription_id),
          true <- is_integer(monitored_item_id),
          true <- is_integer(subscription_id) do
      c_args = {subscription_id, monitored_item_id}
      call_port(state, :delete_monitored_item, caller_info, c_args)
      {:noreply, state}
    else
      _ ->
        {:reply, {:error, :einval} ,state}
    end
  end

  # Catch all

  def handle_call(invalid_call, _caller_info, state) do
    Logger.error("#{__MODULE__} Invalid call: #{inspect(invalid_call)}")
    {:reply, {:error, :einval}, state}
  end

  def handle_info({_port, {:exit_status, code}}, state) do
    Logger.warn("(#{__MODULE__}) Error code: #{inspect(code)}.")
    # retrying delay
    Process.sleep(@c_timeout)
    {:stop, :restart, state}
  end

  def handle_info({:EXIT, _port, reason}, state) do
    Logger.debug("(#{__MODULE__}) Exit reason: #{inspect(reason)}")
    # retrying delay
    Process.sleep(@c_timeout)
    {:stop, :restart, state}
  end

  def handle_info(msg, state) do
    Logger.warn("(#{__MODULE__}) Unhandled message: #{inspect(msg)}.")
    {:noreply, state}
  end

  # Subscription C message handlers
  defp handle_c_response(
         {:subscription, {:data, subscription_id, monitored_id, c_value}},
         %{controlling_process: c_pid} = state
       ) do
    value = parse_c_value(c_value)
    send(c_pid, {:data, subscription_id, monitored_id, value})
    state
  end

  defp handle_c_response(
         {:subscription, message},
         %{controlling_process: c_pid} = state
       ) do
    send(c_pid, message)
    state
  end

  # Lifecycle C Handlers

  defp handle_c_response({:get_client_state, caller_metadata, client_state}, state) do
    str_client_state = charlist_to_string(client_state)
    GenServer.reply(caller_metadata, str_client_state)
    state
  end

  defp handle_c_response({:set_client_config, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:get_client_config, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:reset_client, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  # Connect to a Server C Handlers

  defp handle_c_response({:connect_client_by_url, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:connect_client_by_username, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:connect_client_no_session, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:disconnect_client, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  # Discovery functions C Handlers

  defp handle_c_response({:find_servers_on_network, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:find_servers, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:get_endpoints, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  # Subscriptions and Monitored Items functions.

  defp handle_c_response({:add_subscription, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:delete_subscription, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:add_monitored_item, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp handle_c_response({:delete_monitored_item, caller_metadata, c_response}, state) do
    GenServer.reply(caller_metadata, c_response)
    state
  end

  defp charlist_to_string({:ok, charlist}), do: {:ok, to_string(charlist)}
  defp charlist_to_string(error_response), do: error_response
end

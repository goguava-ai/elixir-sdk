defmodule Guava.Auth.APIKey do
  @moduledoc "API-key authentication."
  @enforce_keys [:key]
  defstruct [:key]
  @type t :: %__MODULE__{key: String.t()}
end

defmodule Guava.Auth.Deploy do
  @moduledoc "Guava-deploy token-file authentication."
  defstruct token_path: "/var/run/secrets/guava/token"
  @type t :: %__MODULE__{token_path: Path.t()}
end

defmodule Guava.Auth.CLI do
  @moduledoc """
  CLI-session authentication with OAuth token refresh.

  The refreshed access token is cached in a process-global `Agent` keyed by
  config path, mirroring the Python SDK's lazy singleton.
  """
  require Logger

  defstruct config_path: nil
  @type t :: %__MODULE__{config_path: Path.t()}

  @refresh_buffer_seconds 60

  @doc "Whether a usable CLI session exists (config present with a refresh token)."
  @spec exists?() :: boolean()
  def exists? do
    case Guava.Config.read_cli_config() do
      %{"refresh_token" => _} -> true
      _ -> false
    end
  end

  @doc "Build a CLI auth handle from the current config."
  @spec new() :: t()
  def new, do: %__MODULE__{config_path: Guava.Config.cli_config_path()}

  @doc "Return CLI auth headers, refreshing the access token when near expiry."
  @spec headers(t()) :: [{String.t(), String.t()}]
  def headers(%__MODULE__{} = cli) do
    state = ensure_agent(cli)
    now = System.system_time(:second)

    state =
      if state.expires_at - now <= @refresh_buffer_seconds do
        refresh(cli, state)
      else
        state
      end

    [
      {"authorization", "Bearer #{state.access_token}"},
      {"x-guava-org-id", state.org_id}
    ]
  end

  # ---- token cache (process-global singleton keyed by config path) ----

  defp agent_name(path), do: {:global, {__MODULE__, path}}

  defp ensure_agent(%__MODULE__{config_path: path}) do
    name = agent_name(path)

    case :global.whereis_name({__MODULE__, path}) do
      :undefined ->
        config = Guava.Config.read_cli_config() || %{}

        initial = %{
          access_token: config["access_token"],
          expires_at: config["expires_at"] || 0,
          refresh_token: config["refresh_token"],
          org_id: config["org_id"],
          base_url: config["base_url"] || Guava.Config.base_url()
        }

        case Agent.start(fn -> initial end, name: name) do
          {:ok, _pid} -> initial
          {:error, {:already_started, _pid}} -> Agent.get(name, & &1)
        end

      _pid ->
        Agent.get(name, & &1)
    end
  end

  defp refresh(%__MODULE__{config_path: path}, state) do
    Logger.debug("Refreshing Guava CLI access token...")
    url = URI.merge(state.base_url, "/oauth/token") |> to_string()

    resp =
      Req.post!(url, form: [grant_type: "refresh_token", refresh_token: state.refresh_token])

    token = resp.body

    new_state = %{
      state
      | access_token: token["access_token"],
        expires_at: System.system_time(:second) + (token["expires_in"] || 0)
    }

    Agent.update(agent_name(path), fn _ -> new_state end)
    new_state
  end
end

defmodule Guava.Auth do
  @moduledoc """
  Authentication strategies for the Guava API.

  Resolves credentials in the same order as the Python SDK:

    1. An explicit API key.
    2. A Guava-deploy token file at `/var/run/secrets/guava/token`.
    3. The `GUAVA_API_KEY` environment variable.
    4. A logged-in CLI session (`$config/guava/config.json`) with OAuth refresh.
  """

  alias Guava.Auth.{APIKey, Deploy, CLI}

  @deploy_token_path "/var/run/secrets/guava/token"

  @type t :: APIKey.t() | Deploy.t() | CLI.t()

  @doc "The path checked for a Guava-deploy token."
  @spec deploy_token_path() :: Path.t()
  def deploy_token_path, do: @deploy_token_path

  @doc """
  Resolve an auth strategy from an explicit `api_key` (or `nil`) and the
  environment. Raises `Guava.Error` (type `:auth`) when nothing is available.
  """
  @spec resolve(String.t() | nil) :: t()
  def resolve(api_key \\ nil)

  def resolve(api_key) when is_binary(api_key), do: %APIKey{key: api_key}

  def resolve(nil) do
    cond do
      key = Application.get_env(:guava, :api_key) ->
        %APIKey{key: key}

      File.exists?(@deploy_token_path) ->
        %Deploy{token_path: @deploy_token_path}

      key = System.get_env("GUAVA_API_KEY") ->
        %APIKey{key: key}

      CLI.exists?() ->
        CLI.new()

      true ->
        raise Guava.Error,
          type: :auth,
          message:
            "Unable to authenticate to Guava. You must do one of the following:\n" <>
              "- Sign in using the Guava CLI.\n" <>
              "- Provide an API key via the GUAVA_API_KEY environment variable.\n" <>
              "- Provide the API key to Guava.Client.new/1, or config :guava, api_key: ..."
    end
  end

  @doc "Return the auth headers for a strategy, refreshing tokens if needed."
  @spec headers(t()) :: [{String.t(), String.t()}]
  def headers(%APIKey{key: key}), do: [{"authorization", "Bearer #{key}"}]

  def headers(%Deploy{token_path: path}) do
    token = path |> File.read!() |> String.trim()
    [{"authorization", "Bearer gva-deploy2-#{token}"}]
  end

  def headers(%CLI{} = cli), do: CLI.headers(cli)
end

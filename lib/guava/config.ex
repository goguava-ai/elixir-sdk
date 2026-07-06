defmodule Guava.Config do
  @moduledoc """
  Resolves the Guava base URL and locates the CLI config file.

  Mirrors `guava.utils.get_base_url` / `cli_config_path`.
  """

  @default_base_url "https://app.goguava.ai/"

  @doc "The default Guava base URL."
  @spec default_base_url() :: String.t()
  def default_base_url, do: @default_base_url

  @doc """
  Resolve the base URL.

  Precedence: `config :guava, base_url: ...`, then the `GUAVA_BASE_URL` env var,
  then a `base_url` in the CLI config, then the default.
  """
  @spec base_url() :: String.t()
  def base_url do
    cond do
      url = Application.get_env(:guava, :base_url) -> url
      url = System.get_env("GUAVA_BASE_URL") -> url
      config = read_cli_config() -> Map.get(config, "base_url", @default_base_url)
      true -> @default_base_url
    end
  end

  @doc "Path to the CLI config file (`$config/guava/config.json`)."
  @spec cli_config_path() :: Path.t()
  def cli_config_path do
    Path.join([platform_config_dir(), "guava", "config.json"])
  end

  @doc "Read and parse the CLI config, or `nil` if it does not exist / is invalid."
  @spec read_cli_config() :: map() | nil
  def read_cli_config do
    path = cli_config_path()

    with true <- File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, json} <- Jason.decode(body) do
      json
    else
      _ -> nil
    end
  end

  @doc """
  Platform config directory, mirroring Rust `dirs::config_dir()`:
  `$APPDATA` on Windows, `~/Library/Application Support` on macOS, else
  `$XDG_CONFIG_HOME` or `~/.config`.
  """
  @spec platform_config_dir() :: Path.t()
  def platform_config_dir do
    case :os.type() do
      {:win32, _} ->
        System.get_env("APPDATA") ||
          raise("Could not determine config directory: APPDATA is not set")

      {:unix, :darwin} ->
        Path.join([home!(), "Library", "Application Support"])

      {:unix, _} ->
        System.get_env("XDG_CONFIG_HOME") || Path.join(home!(), ".config")
    end
  end

  defp home! do
    System.user_home() || raise("Could not determine config directory: home directory is unknown")
  end
end

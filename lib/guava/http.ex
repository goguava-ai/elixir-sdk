defmodule Guava.HTTP do
  @moduledoc false
  # Internal HTTP helpers: URL joining, header construction, and a request
  # wrapper that raises Guava.Error (type :http/:transport) on failure. Also
  # emits [:guava, :http, :request, :start|:stop|:exception] telemetry spans.

  alias Guava.Auth

  @sdk_name "elixir-sdk"

  @doc "The SDK name sent in the x-guava-sdk header."
  def sdk_name, do: @sdk_name

  @doc "The SDK version string."
  @spec sdk_version() :: String.t()
  def sdk_version do
    case Application.spec(:guava, :vsn) do
      nil -> "0+unknown"
      vsn -> to_string(vsn)
    end
  end

  @doc "Join a relative path onto the client's HTTP base URL."
  @spec http_url(Guava.Client.t(), String.t()) :: String.t()
  def http_url(%{base_url: base}, path), do: base |> URI.merge(path) |> to_string()

  @doc "Join a relative path onto the client's WebSocket base URL (ws/wss)."
  @spec ws_url(Guava.Client.t(), String.t()) :: String.t()
  def ws_url(client, path) do
    url = http_url(client, path)

    cond do
      String.starts_with?(url, "https://") -> "wss://" <> String.trim_leading(url, "https://")
      String.starts_with?(url, "http://") -> "ws://" <> String.trim_leading(url, "http://")
      true -> raise Guava.Error, message: "Invalid base URL: #{url}"
    end
  end

  @doc "All headers for a request: auth plus SDK identification headers."
  @spec headers(Guava.Client.t()) :: [{String.t(), String.t()}]
  def headers(%{auth: auth}) do
    Auth.headers(auth) ++
      [
        {"x-guava-platform", platform()},
        {"x-guava-runtime", "elixir"},
        {"x-guava-runtime-version", System.version()},
        {"x-guava-sdk", @sdk_name},
        {"x-guava-sdk-version", sdk_version()}
      ]
  end

  defp platform do
    case :os.type() do
      {:win32, _} -> "Windows"
      {:unix, :darwin} -> "Darwin"
      {:unix, name} -> name |> to_string() |> String.capitalize()
    end
  end

  @doc """
  Perform a request and return the parsed response body (a map/list) on success.

  `opts` are Req options (`:params`, `:json`, `:form`, ...). The client's
  `:req_options` are merged in (used to inject test plugs).
  """
  @spec request!(Guava.Client.t(), atom(), String.t(), keyword()) :: term()
  def request!(client, method, path, opts \\ []) do
    url = http_url(client, path)

    req_opts =
      [method: method, url: url, headers: headers(client)]
      |> ensure_body(method, opts)
      |> Keyword.merge(opts)
      |> Keyword.merge(client.req_options)

    :telemetry.span([:guava, :http, :request], %{method: method, url: url}, fn ->
      response =
        try do
          Req.request!(req_opts)
        rescue
          e in Guava.Error ->
            reraise(e, __STACKTRACE__)

          e ->
            reraise(
              Guava.Error.exception(type: :transport, message: Exception.message(e), url: url),
              __STACKTRACE__
            )
        end

      check!(response, url)
      {response.body, %{status: response.status}}
    end)
  end

  @body_methods [:post, :put, :patch]
  @body_opts [:json, :form, :form_multipart, :body]

  @doc false
  # The Guava API's frontend rejects body-less POST/PUT/PATCH with HTTP 411
  # (Length Required). Ensure such requests send an empty body so a
  # `content-length: 0` header is emitted.
  def ensure_body(base, method, opts) do
    if method in @body_methods and not Enum.any?(@body_opts, &Keyword.has_key?(opts, &1)) do
      Keyword.put(base, :body, "")
    else
      base
    end
  end

  @doc "Raise `Guava.Error` (type :http, with body) unless the response is 2xx."
  @spec check!(Req.Response.t(), String.t()) :: Req.Response.t()
  def check!(%Req.Response{status: status} = resp, _url) when status in 200..299, do: resp

  def check!(%Req.Response{} = resp, url) do
    raise Guava.Error,
      type: :http,
      status: resp.status,
      body: body_string(resp.body),
      url: url
  end

  defp body_string(body) when is_binary(body), do: body
  defp body_string(body), do: Jason.encode!(body)
end

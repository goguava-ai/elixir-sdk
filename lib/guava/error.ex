defmodule Guava.Error do
  @moduledoc """
  The single error type raised/returned across the SDK.

  Public functions come in two forms: the primary returns
  `{:ok, result} | {:error, %Guava.Error{}}`, and a `!` variant raises this
  exception. Use `wrap/1` to turn a raising call into a tagged tuple.

  `:type` is one of:

    * `:http` — a non-2xx HTTP response (`:status`, `:body` populated)
    * `:auth` — no credentials could be resolved
    * `:transport` — a network/transport failure
    * `:closed` — a realtime socket closed
    * `:unknown` — anything else
  """
  defexception [:type, :status, :message, :body, :url]

  @type t :: %__MODULE__{
          type: :http | :auth | :transport | :closed | :unknown,
          status: pos_integer() | nil,
          message: String.t(),
          body: String.t() | nil,
          url: String.t() | nil
        }

  @impl true
  def exception(opts) when is_list(opts) do
    type = opts[:type] || :unknown
    message = opts[:message] || default_message(type, opts)
    struct(__MODULE__, Keyword.put(opts, :message, message))
  end

  def exception(message) when is_binary(message),
    do: %__MODULE__{type: :unknown, message: message}

  defp default_message(:http, opts), do: "HTTP #{opts[:status]} for #{opts[:url]}: #{opts[:body]}"
  defp default_message(type, _opts), do: "Guava error (#{type})"

  @doc """
  Run `fun`, returning `{:ok, result}`; if it raises a `Guava.Error`, return
  `{:error, error}`. Other exceptions propagate.
  """
  @spec wrap((-> result)) :: {:ok, result} | {:error, t()} when result: var
  def wrap(fun) do
    {:ok, fun.()}
  rescue
    e in __MODULE__ -> {:error, e}
  end
end

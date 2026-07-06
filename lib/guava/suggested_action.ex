defmodule Guava.SuggestedAction do
  @moduledoc """
  An action suggested in response to a caller's request, returned from an
  `on_action_request` handler.
  """
  @enforce_keys [:key]
  defstruct [:key, :description]
  @type t :: %__MODULE__{key: String.t(), description: String.t() | nil}

  @doc "Build a suggested action."
  @spec new(String.t(), String.t() | nil) :: t()
  def new(key, description \\ nil), do: %__MODULE__{key: key, description: description}
end

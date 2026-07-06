defmodule Guava.Internal do
  @moduledoc false
  # Small internal helpers shared across modules.

  @doc "A 5-character lowercase hex key, matching Python's `uuid4().hex[:5]`."
  @spec random_key() :: String.t()
  def random_key do
    :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower) |> binary_part(0, 5)
  end

  @doc "A random lowercase hex token of `n` bytes (2*n hex chars)."
  @spec random_hex(pos_integer()) :: String.t()
  def random_hex(n) do
    :crypto.strong_rand_bytes(n) |> Base.encode16(case: :lower)
  end

  @doc "Current unix time in milliseconds."
  @spec now_ms() :: integer()
  def now_ms, do: System.system_time(:millisecond)
end

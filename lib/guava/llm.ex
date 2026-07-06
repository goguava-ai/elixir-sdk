defmodule Guava.LLM do
  @moduledoc """
  Thin wrapper over Guava's server-side LLM endpoint (`v1/llm/generate`).

  Used by the higher-level helpers (`Guava.IntentRecognizer`,
  `Guava.DatetimeFilter`, `Guava.DateRangeParser`) and available directly.
  """
  alias Guava.{Error, HTTP}

  @doc """
  Generate text from `prompt`, returning `{:ok, text} | {:error, %Guava.Error{}}`.
  When `json_schema` is given, the server constrains the output to match it and
  the returned string is JSON.
  """
  @spec generate(Guava.Client.t(), String.t(), map() | nil) ::
          {:ok, String.t()} | {:error, Error.t()}
  def generate(client, prompt, json_schema \\ nil),
    do: Error.wrap(fn -> generate!(client, prompt, json_schema) end)

  @doc "Like `generate/3`, but returns the text or raises `Guava.Error`."
  @spec generate!(Guava.Client.t(), String.t(), map() | nil) :: String.t()
  def generate!(client, prompt, json_schema \\ nil) do
    payload =
      if json_schema, do: %{prompt: prompt, json_schema: json_schema}, else: %{prompt: prompt}

    HTTP.request!(client, :post, "v1/llm/generate", json: payload, receive_timeout: 60_000)[
      "text"
    ]
  end
end

defmodule Guava.IntentRecognizer do
  @moduledoc """
  Match a caller intent against a fixed set of choices using the Guava LLM
  endpoint, constrained so only the provided choices can be returned.
  """
  alias Guava.{LLM, SuggestedAction}

  @enforce_keys [:client, :choices]
  defstruct [:client, :choices]

  @type t :: %__MODULE__{
          client: Guava.Client.t(),
          choices: [String.t()] | %{String.t() => String.t()}
        }

  @doc """
  Build a recognizer. `choices` is a list of choice strings, or a map from
  choice to a longer disambiguating description.
  """
  @spec new(Guava.Client.t(), [String.t()] | %{String.t() => String.t()}) :: t()
  def new(client, choices), do: %__MODULE__{client: client, choices: choices}

  @doc """
  Classify `intent`. Returns a list of `Guava.SuggestedAction` ordered by
  likelihood, or `nil` if nothing plausibly matches.
  """
  @spec classify(t(), String.t()) ::
          {:ok, [SuggestedAction.t()] | nil} | {:error, Guava.Error.t()}
  def classify(%__MODULE__{} = r, intent), do: Guava.Error.wrap(fn -> classify!(r, intent) end)

  @doc "Like `classify/2`, but returns the matches or raises `Guava.Error`."
  @spec classify!(t(), String.t()) :: [SuggestedAction.t()] | nil
  def classify!(%__MODULE__{} = r, intent) do
    keys = choice_keys(r.choices)

    schema = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["possible_matches"],
      "properties" => %{
        "possible_matches" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => keys},
          "description" =>
            "Choices that could match the caller's intent, ordered by likelihood. Include all plausible matches."
        }
      }
    }

    prompt = build_prompt(r.choices, intent, keys)
    text = LLM.generate!(r.client, prompt, schema)
    matched = Jason.decode!(text)["possible_matches"]

    cond do
      matched in [nil, []] -> nil
      is_map(r.choices) -> Enum.map(matched, &SuggestedAction.new(&1, r.choices[&1]))
      true -> Enum.map(matched, &SuggestedAction.new/1)
    end
  end

  defp choice_keys(choices) when is_map(choices), do: Map.keys(choices)
  defp choice_keys(choices) when is_list(choices), do: choices

  defp build_prompt(choices, intent, keys) do
    base = """
    Classify the intent below into the most appropriate choice(s) from the list.

    Intent: <intent>#{intent}</intent>
    Available Choices: #{inspect(keys)}

    Rules:
    - Default to returning a single choice — the one that best matches the intent.
    - Only return additional choices when the intent is genuinely ambiguous.
    - Order matches by likelihood (most likely first).
    - If no choice plausibly matches, return an empty list.
    """

    if is_map(choices) do
      descriptions = Enum.map_join(choices, "\n  ", fn {k, v} -> "#{k}: #{v}" end)
      base <> "\n\nDetailed descriptions of each choice:\n  " <> descriptions
    else
      String.trim(base)
    end
  end
end

defmodule Guava.DatetimeFilter do
  @moduledoc "Filter ISO-8601 datetime slots by natural-language query, via the LLM endpoint."
  alias Guava.LLM

  @enforce_keys [:client, :source_list]
  defstruct [:client, :source_list]
  @type t :: %__MODULE__{client: Guava.Client.t(), source_list: [String.t()]}

  @doc "Build a filter over `source_list` (ISO-8601 datetime strings)."
  @spec new(Guava.Client.t(), [String.t()]) :: t()
  def new(client, source_list), do: %__MODULE__{client: client, source_list: source_list}

  @doc "Return `{:ok, {matching, fallback}}` slots for `query`, each capped at `max_results`."
  @spec filter(t(), String.t(), pos_integer()) ::
          {:ok, {[String.t()], [String.t()]}} | {:error, Guava.Error.t()}
  def filter(%__MODULE__{} = f, query, max_results \\ 5),
    do: Guava.Error.wrap(fn -> filter!(f, query, max_results) end)

  @doc "Like `filter/3`, but returns `{matching, fallback}` or raises `Guava.Error`."
  @spec filter!(t(), String.t(), pos_integer()) :: {[String.t()], [String.t()]}
  def filter!(%__MODULE__{} = f, query, max_results \\ 5) do
    schema = %{
      "type" => "object",
      "required" => ["matching_appointments", "other_appointments"],
      "properties" => %{
        "matching_appointments" => %{"type" => "array", "items" => %{"type" => "string"}},
        "other_appointments" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    }

    today = Date.utc_today() |> Calendar.strftime("%B %d, %Y")

    prompt = """
    Return datetime slots from the list that match the query.
    If none match, return close alternatives in other_appointments instead.
    Never return datetimes that are not in the list.

    Query: <query>#{query}</query>
    Today's Date: #{today}
    Available slots:
    #{Enum.join(f.source_list, "\n")}

    Return at most #{max_results} items per list.
    """

    result = f.client |> LLM.generate!(prompt, schema) |> Jason.decode!()

    {
      Enum.take(result["matching_appointments"] || [], max_results),
      Enum.take(result["other_appointments"] || [], max_results)
    }
  end
end

defmodule Guava.DateRangeParser do
  @moduledoc "Parse natural-language time expressions into concrete date ranges via the LLM endpoint."
  alias Guava.LLM

  @enforce_keys [:client]
  defstruct [:client]
  @type t :: %__MODULE__{client: Guava.Client.t()}

  @doc "Build a parser."
  @spec new(Guava.Client.t()) :: t()
  def new(client), do: %__MODULE__{client: client}

  @doc """
  Return `{start_date, end_date}` for the range described by `query`, extended
  by `buffer_days` on each side and clamped to today..today+1yr.
  """
  @spec parse(t(), String.t(), non_neg_integer()) ::
          {:ok, {Date.t(), Date.t()}} | {:error, Guava.Error.t()}
  def parse(%__MODULE__{} = p, query, buffer_days \\ 1),
    do: Guava.Error.wrap(fn -> parse!(p, query, buffer_days) end)

  @doc "Like `parse/3`, but returns `{start_date, end_date}` or raises `Guava.Error`."
  @spec parse!(t(), String.t(), non_neg_integer()) :: {Date.t(), Date.t()}
  def parse!(%__MODULE__{} = p, query, buffer_days \\ 1) do
    today = Date.utc_today()
    max_date = Date.add(today, 365)

    schema = %{
      "type" => "object",
      "required" => ["start_date", "end_date"],
      "properties" => %{
        "start_date" => %{"type" => "string", "format" => "date"},
        "end_date" => %{"type" => "string", "format" => "date"}
      }
    }

    prompt = """
    Extract the date or date range the user is asking about.
    If the query mentions a specific day, start_date and end_date should both be that day.
    If the query mentions a range like "next week", use the full range.
    Dates must be between #{Date.to_iso8601(today)} and #{Date.to_iso8601(max_date)}.
    If the query doesn't contain a clear date, default to the next 7 days.

    Query: <query>#{query}</query>
    Today's date: #{Date.to_iso8601(today)} (#{Calendar.strftime(today, "%A")})
    """

    result = p.client |> LLM.generate!(String.trim(prompt), schema) |> Jason.decode!()

    parsed_start = Date.from_iso8601!(result["start_date"])
    parsed_end = Date.from_iso8601!(result["end_date"])

    start = clamp(Date.add(parsed_start, -buffer_days), today, max_date)
    finish = clamp(Date.add(parsed_end, buffer_days), today, max_date)
    {start, finish}
  end

  defp clamp(date, min, max) do
    date |> max_date(min) |> min_date(max)
  end

  defp max_date(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
  defp min_date(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)
end

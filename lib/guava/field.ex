defmodule Guava.Field do
  @moduledoc """
  A structured-data collection instruction given to the agent during a call.

  Mirrors `guava.types.Field`. The `key` is used later with
  `Guava.Call.get_field/2` to retrieve the collected value.

  Field types requiring options (`"multiple_choice"`, `"calendar_slot"`) must
  supply either `:choices` (a small static list) or set `:searchable` and
  register a handler via `c:Guava.Agent.handle_search_query/4`.
  """
  require Logger

  @enforce_keys [:key]
  defstruct item_type: "field",
            key: nil,
            description: "",
            question: "",
            field_type: "text",
            required: true,
            choices: [],
            searchable: false

  @type t :: %__MODULE__{
          item_type: String.t(),
          key: String.t(),
          description: String.t(),
          question: String.t(),
          field_type: String.t(),
          required: boolean(),
          choices: [String.t()],
          searchable: boolean()
        }

  @iso_8601 ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?/

  @doc """
  Build and validate a `Guava.Field`.

  Accepts a keyword list or map of attributes. Raises `ArgumentError` for
  invalid combinations, matching the Python SDK's validation:

    * `"datetime"` collection is not implemented.
    * `:choices` are only valid for `"multiple_choice"` / `"calendar_slot"`.
    * `"calendar_slot"` choices must be ISO-8601 (`YYYY-MM-DDTHH:MM`).
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs) do
    field = struct!(__MODULE__, attrs)
    validate!(field)
    field
  end

  @doc false
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = field) do
    cond do
      field.field_type == "datetime" ->
        raise ArgumentError, "Datetime collection is not yet implemented."

      field.field_type == "calendar_slot" ->
        Enum.each(field.choices, fn c ->
          unless is_binary(c) and Regex.match?(@iso_8601, c) do
            raise ArgumentError,
                  "calendar_slot choices must be ISO-8601 (YYYY-MM-DDTHH:MM), got: #{inspect(c)}"
          end
        end)

      (field.choices != [] or field.searchable) and
          field.field_type not in ["multiple_choice", "calendar_slot"] ->
        raise ArgumentError, "Field type #{field.field_type} does not support choices."

      true ->
        :ok
    end

    if length(field.choices) >= 10 do
      Logger.warning(
        "Performance degrades with a large number of choices for a multiple choice field. " <>
          "Use a searchable field with on_search_query/3 instead."
      )
    end

    field
  end
end

defmodule Guava.SerializableField do
  @moduledoc """
  Wire representation of a `Guava.Field`.

  Replaces the non-serializable choice-generator with the `:is_search_field`
  flag. Produced from a `Guava.Field` when building a task.
  """
  @derive Jason.Encoder
  @enforce_keys [:key]
  defstruct item_type: "field",
            key: nil,
            description: "",
            question: "",
            field_type: "text",
            required: true,
            choices: [],
            is_search_field: false

  @type t :: %__MODULE__{
          item_type: String.t(),
          key: String.t(),
          description: String.t(),
          question: String.t(),
          field_type: String.t(),
          required: boolean(),
          choices: [String.t()],
          is_search_field: boolean()
        }

  @doc "Build a `Guava.SerializableField` from a validated `Guava.Field`."
  @spec from_field(Guava.Field.t()) :: t()
  def from_field(%Guava.Field{} = f) do
    %__MODULE__{
      key: f.key,
      description: f.description,
      question: f.question,
      field_type: f.field_type,
      required: f.required,
      choices: f.choices,
      is_search_field: f.searchable
    }
  end
end

defmodule Guava.Say do
  @moduledoc """
  A checklist item instructing the agent to say a statement verbatim.

  Mirrors `guava.types.Say`. A random `:key` is generated when omitted.
  """
  @derive Jason.Encoder
  @enforce_keys [:statement, :key]
  defstruct item_type: "say", statement: nil, key: nil

  @type t :: %__MODULE__{item_type: String.t(), statement: String.t(), key: String.t()}

  @doc "Create a `Guava.Say`, generating a random key if none is given."
  @spec new(String.t(), String.t() | nil) :: t()
  def new(statement, key \\ nil) do
    %__MODULE__{statement: statement, key: key || Guava.Internal.random_key()}
  end
end

defmodule Guava.Todo do
  @moduledoc """
  A free-form checklist item describing something for the agent to do.

  Mirrors `guava.types.Todo`. A random `:key` is generated when omitted.
  """
  @derive Jason.Encoder
  @enforce_keys [:description, :key]
  defstruct item_type: "todo", key: nil, description: nil

  @type t :: %__MODULE__{item_type: String.t(), key: String.t(), description: String.t()}

  @doc "Create a `Guava.Todo`, generating a random key if none is given."
  @spec new(String.t(), String.t() | nil) :: t()
  def new(description, key \\ nil) do
    %__MODULE__{description: description, key: key || Guava.Internal.random_key()}
  end
end

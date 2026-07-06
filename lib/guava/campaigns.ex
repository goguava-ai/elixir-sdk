defmodule Guava.Contact do
  @moduledoc "A campaign contact to dial."
  @derive Jason.Encoder
  @enforce_keys [:phone_number]
  defstruct phone_number: nil, data: %{}, outreach_modalities: nil

  @type t :: %__MODULE__{
          phone_number: String.t(),
          data: map(),
          outreach_modalities: [String.t()] | nil
        }

  @doc "Build a contact."
  @spec new(String.t(), keyword()) :: t()
  def new(phone_number, opts \\ []) do
    %__MODULE__{
      phone_number: phone_number,
      data: opts[:data] || %{},
      outreach_modalities: opts[:outreach_modalities]
    }
  end
end

defmodule Guava.Campaign do
  @moduledoc "An outbound calling campaign."
  defstruct [:id, :name, :data]
  @type t :: %__MODULE__{id: String.t(), name: String.t(), data: map()}

  @doc false
  def from_map(m), do: %__MODULE__{id: m["id"], name: m["name"], data: m}
end

defmodule Guava.Campaigns do
  @moduledoc """
  List, fetch, and manage outbound campaigns and their contacts.
  """
  alias Guava.{Campaign, Contact, HTTP}

  @type result(x) :: {:ok, x} | {:error, Guava.Error.t()}

  @doc "List all campaigns."
  @spec list(Guava.Client.t()) :: result([Campaign.t()])
  def list(client), do: Guava.Error.wrap(fn -> list!(client) end)

  @spec list!(Guava.Client.t()) :: [Campaign.t()]
  def list!(client) do
    client |> HTTP.request!(:get, "v1/campaigns") |> Enum.map(&Campaign.from_map/1)
  end

  @doc "Fetch a campaign by its code."
  @spec get_by_code(Guava.Client.t(), String.t()) :: result(Campaign.t())
  def get_by_code(client, campaign_code),
    do: Guava.Error.wrap(fn -> get_by_code!(client, campaign_code) end)

  @spec get_by_code!(Guava.Client.t(), String.t()) :: Campaign.t()
  def get_by_code!(client, campaign_code) do
    client |> HTTP.request!(:get, "v1/campaigns/#{campaign_code}") |> Campaign.from_map()
  end

  @doc """
  Upload contacts to a campaign by code (v2 endpoint).

  ## Options
    * `:allow_duplicates` (default `false`)
    * `:accepted_terms_of_service` (default `false`)
    * `:outreach_modalities` — applied to contacts that don't set their own.
  """
  @spec upload_contacts(Guava.Client.t(), String.t(), [Contact.t()], keyword()) :: result(map())
  def upload_contacts(client, campaign_code, contacts, opts \\ []),
    do: Guava.Error.wrap(fn -> upload_contacts!(client, campaign_code, contacts, opts) end)

  @spec upload_contacts!(Guava.Client.t(), String.t(), [Contact.t()], keyword()) :: map()
  def upload_contacts!(client, campaign_code, contacts, opts \\ []) do
    contacts = apply_default_modalities(contacts, opts[:outreach_modalities])

    HTTP.request!(client, :post, "v2/campaigns/#{campaign_code}/contacts",
      params: [
        allow_duplicates: to_string(opts[:allow_duplicates] || false),
        accepted_terms_of_service: to_string(opts[:accepted_terms_of_service] || false)
      ],
      json: %{contacts: contacts}
    )
  end

  @doc "Get a campaign's status."
  @spec status(Guava.Client.t(), String.t()) :: result(map())
  def status(client, campaign_id), do: Guava.Error.wrap(fn -> status!(client, campaign_id) end)

  @spec status!(Guava.Client.t(), String.t()) :: map()
  def status!(client, campaign_id),
    do: HTTP.request!(client, :get, "v1/campaigns/#{campaign_id}/status")

  @doc "Whether a campaign has contacts left to call. Returns `{:ok, boolean}`."
  @spec has_callable_contacts(Guava.Client.t(), String.t()) :: result(boolean())
  def has_callable_contacts(client, campaign_id),
    do: Guava.Error.wrap(fn -> has_callable_contacts!(client, campaign_id) end)

  @spec has_callable_contacts!(Guava.Client.t(), String.t()) :: boolean()
  def has_callable_contacts!(client, campaign_id) do
    body = HTTP.request!(client, :get, "v1/campaigns/#{campaign_id}/has-callable-contacts")
    Map.get(body, "has_callable_contacts", true)
  end

  @doc "Update a campaign's attributes (e.g. `%{enabled: false}`)."
  @spec update(Guava.Client.t(), String.t(), map()) :: result(map())
  def update(client, campaign_id, attrs),
    do: Guava.Error.wrap(fn -> update!(client, campaign_id, attrs) end)

  @spec update!(Guava.Client.t(), String.t(), map()) :: map()
  def update!(client, campaign_id, attrs),
    do: HTTP.request!(client, :patch, "v1/campaigns/#{campaign_id}", json: attrs)

  @doc "Delete a campaign."
  @spec delete(Guava.Client.t(), String.t()) :: result(map())
  def delete(client, campaign_id), do: Guava.Error.wrap(fn -> delete!(client, campaign_id) end)

  @spec delete!(Guava.Client.t(), String.t()) :: map()
  def delete!(client, campaign_id),
    do: HTTP.request!(client, :delete, "v1/campaigns/#{campaign_id}")

  defp apply_default_modalities(contacts, nil), do: contacts

  defp apply_default_modalities(contacts, modalities) do
    Enum.map(contacts, fn c -> %{c | outreach_modalities: c.outreach_modalities || modalities} end)
  end
end

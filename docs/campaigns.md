# Campaigns

Campaigns drive bulk outbound calling. You manage campaigns and their contacts
with `Guava.Campaigns`, then serve calls with an agent via
`Guava.attach_campaign/3`.

## Managing campaigns

```elixir
client = Guava.Client.new()

Guava.Campaigns.list(client)                      # => [%Guava.Campaign{}, ...]
campaign = Guava.Campaigns.get_by_code(client, "camp_abc")
Guava.Campaigns.status(client, campaign.id)
Guava.Campaigns.has_callable_contacts?(client, campaign.id)
Guava.Campaigns.update(client, campaign.id, %{enabled: false})
Guava.Campaigns.delete(client, campaign.id)
```

A `Guava.Campaign` has `:id`, `:name`, and the raw `:data`.

## Uploading contacts

```elixir
contacts = [
  Guava.Contact.new("+14155550100", data: %{"name" => "Ada", "order_id" => 4471}),
  Guava.Contact.new("+14155550111", data: %{"name" => "Alan"})
]

Guava.Campaigns.upload_contacts(client, "camp_abc", contacts,
  allow_duplicates: false,
  accepted_terms_of_service: true
)
```

Each contact's `:data` map is delivered to your agent as **initial call
variables** when that contact is dialed — read them with
`Guava.Call.get_variable/3`.

Options:

- `:allow_duplicates` (default `false`)
- `:accepted_terms_of_service` (default `false`) — you must have the right to
  contact these numbers.
- `:outreach_modalities` — applied to contacts that don't set their own
  (currently `["sms"]`).

## Serving campaign calls

```elixir
defmodule SurveyAgent do
  use Guava.Agent, name: "Nova", organization: "Acme"

  @impl true
  def handle_start(call, state) do
    Guava.Call.reach_person(call, Guava.Call.get_variable(call, "name", "there"))
    {:noreply, state}
  end

  @impl true
  def handle_task_complete("reach_person", call, state) do
    if Guava.Call.get_field(call, "contact_availability") == "available" do
      run_survey(call)
    else
      Guava.Call.hangup(call)
    end

    {:noreply, state}
  end
end

# Supervised, or blocking for a script:
{Guava.Channel, agent: SurveyAgent, campaign: "camp_abc"}
Guava.attach_campaign(SurveyAgent, "camp_abc")
```

The channel connects to the campaign and, for each contact the server
dispatches, runs your agent against that call.

Next: [Messaging](messaging.md).

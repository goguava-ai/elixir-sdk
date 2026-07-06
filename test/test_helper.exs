# Load a repo-root .env (KEY=VALUE per line) so live tests can pick up
# GUAVA_API_KEY / GUAVA_AGENT_NUMBER without exporting them. Existing env vars
# win, and this is a no-op when .env is absent.
if File.exists?(".env") do
  ".env"
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    line = String.trim(line)

    unless line == "" or String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = value |> String.trim() |> String.trim("\"") |> String.trim("'")
          if System.get_env(key) in [nil, ""], do: System.put_env(key, value)

        _ ->
          :ok
      end
    end
  end)
end

# Normalize known credentials in case they arrived wrapped in quotes/whitespace.
for key <- ~w(GUAVA_API_KEY GUAVA_AGENT_NUMBER GUAVA_BASE_URL) do
  case System.get_env(key) do
    nil -> :ok
    "" -> :ok
    v -> System.put_env(key, v |> String.trim() |> String.trim("\"") |> String.trim("'"))
  end
end

# Live tests hit the real Guava API and require GUAVA_API_KEY. They are excluded
# by default; run them with `mix test --include live`.
ExUnit.start(exclude: [:live])

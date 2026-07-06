defmodule Guava.ClientTest do
  # async: false — several tests mutate process-global env vars.
  use ExUnit.Case, async: false

  alias Guava.{Auth, Client, Error, HTTP}

  # Ensure no ambient credentials leak in from the host: clear the env key and
  # point XDG_CONFIG_HOME at an empty dir so no real CLI config is found.
  defp isolate_credentials do
    System.delete_env("GUAVA_API_KEY")
    prev = System.get_env("XDG_CONFIG_HOME")
    empty = Path.join(System.tmp_dir!(), "guava_noconfig_#{System.unique_integer([:positive])}")
    File.mkdir_p!(empty)
    System.put_env("XDG_CONFIG_HOME", empty)

    on_exit(fn ->
      if prev, do: System.put_env("XDG_CONFIG_HOME", prev), else: System.delete_env("XDG_CONFIG_HOME")
      File.rm_rf(empty)
    end)
  end

  defp stub_client do
    Client.new!(
      api_key: "test-key",
      base_url: "https://app.goguava.ai/",
      req_options: [plug: {Req.Test, GuavaStub}]
    )
  end

  # Capture request shape and return canned JSON.
  defp stub(fun) do
    Req.Test.stub(GuavaStub, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      parsed = if body == "", do: nil, else: Jason.decode!(body)

      send(
        self(),
        {:req, conn.method, conn.request_path, conn.query_params, parsed, conn.req_headers}
      )

      fun.(conn)
    end)
  end

  describe "URL joining" do
    test "http_url joins onto trailing-slash base" do
      assert HTTP.http_url(stub_client(), "v1/phone-numbers") ==
               "https://app.goguava.ai/v1/phone-numbers"
    end

    test "ws_url converts https to wss" do
      assert HTTP.ws_url(stub_client(), "v2/connect-call/abc") ==
               "wss://app.goguava.ai/v2/connect-call/abc"
    end

    test "ws_url converts http to ws" do
      c = Client.new!(api_key: "k", base_url: "http://localhost:8080/")
      assert HTTP.ws_url(c, "v2/x") == "ws://localhost:8080/v2/x"
    end
  end

  describe "new/1" do
    test "returns {:ok, client}" do
      assert {:ok, %Client{}} = Client.new(api_key: "k")
    end

    test "returns {:error, %Guava.Error{type: :auth}} when no credentials" do
      isolate_credentials()
      assert {:error, %Error{type: :auth}} = Client.new()
    end
  end

  describe "headers" do
    test "include auth and sdk identification" do
      headers = HTTP.headers(stub_client())
      assert {"authorization", "Bearer test-key"} in headers
      assert {"x-guava-sdk", "elixir-sdk"} in headers
      assert List.keyfind(headers, "x-guava-sdk-version", 0)
      assert List.keyfind(headers, "x-guava-runtime", 0) == {"x-guava-runtime", "elixir"}
    end
  end

  describe "auth resolution" do
    test "explicit api key wins" do
      assert %Auth.APIKey{key: "abc"} = Auth.resolve("abc")
    end

    test "falls back to GUAVA_API_KEY" do
      System.put_env("GUAVA_API_KEY", "envkey")
      on_exit(fn -> System.delete_env("GUAVA_API_KEY") end)
      assert %Auth.APIKey{key: "envkey"} = Auth.resolve(nil)
    end

    test "raises Guava.Error (:auth) when nothing available" do
      isolate_credentials()
      assert_raise Error, ~r/authenticate/, fn -> Auth.resolve(nil) end
    end

    test "APIKey headers" do
      assert Auth.headers(%Auth.APIKey{key: "k"}) == [{"authorization", "Bearer k"}]
    end

    test "Deploy headers read and prefix the token" do
      path = Path.join(System.tmp_dir!(), "guava_deploy_#{System.unique_integer([:positive])}")
      File.write!(path, "  sekret\n")
      on_exit(fn -> File.rm(path) end)

      assert Auth.headers(%Auth.Deploy{token_path: path}) == [
               {"authorization", "Bearer gva-deploy2-sekret"}
             ]
    end
  end

  describe "client HTTP methods (bang variants return values)" do
    test "create_webrtc_agent! with ttl" do
      stub(fn conn -> Req.Test.json(conn, %{"webrtc_code" => "wc123"}) end)
      assert Client.create_webrtc_agent!(stub_client(), 3600) == "wc123"
      assert_received {:req, "POST", "/v1/webrtc-agents", %{"ttl_sec" => "3600"}, _, _}
    end

    test "create_sip_agent! and create_sip_agent tuple" do
      stub(fn conn -> Req.Test.json(conn, %{"sip_code" => "sc123"}) end)
      assert Client.create_sip_agent!(stub_client()) == "sc123"
      assert {:ok, "sc123"} = Client.create_sip_agent(stub_client())
    end

    test "create_outbound! returns call_id and sends params" do
      stub(fn conn -> Req.Test.json(conn, %{"call_id" => "call_1"}) end)
      assert Client.create_outbound!(stub_client(), "+14155550100", "+14155550111") == "call_1"

      assert_received {:req, "POST", "/v2/create-outbound",
                       %{"from_number" => "+14155550100", "to_number" => "+14155550111"}, _, _}
    end

    test "list_numbers! maps to structs" do
      stub(fn conn ->
        Req.Test.json(conn, [
          %{"phone_number" => "+14155550100"},
          %{"phone_number" => "+14155550111"}
        ])
      end)

      assert [
               %Guava.PhoneNumberInfo{phone_number: "+14155550100"},
               %Guava.PhoneNumberInfo{phone_number: "+14155550111"}
             ] = Client.list_numbers!(stub_client())
    end

    test "send_sms! posts json body" do
      stub(fn conn -> Req.Test.json(conn, %{"ok" => true}) end)
      assert Client.send_sms!(stub_client(), "+14155550100", "+14155550111", "hi") == :ok

      assert_received {:req, "POST", "/v1/send-sms", _,
                       %{
                         "from_number" => "+14155550100",
                         "to_number" => "+14155550111",
                         "message" => "hi"
                       }, _}
    end

    test "check_sdk_deprecation! returns status" do
      stub(fn conn -> Req.Test.json(conn, %{"deprecation_status" => "supported"}) end)
      assert Client.check_sdk_deprecation!(stub_client()) == "supported"

      assert_received {:req, "POST", "/v1/check-sdk-deprecation", %{"sdk_name" => "elixir-sdk"},
                       _, _}
    end

    test "next_sms! returns first message when present" do
      stub(fn conn ->
        Req.Test.json(conn, %{"messages" => [%{"id" => "m1", "content" => "hello"}]})
      end)

      assert %{"id" => "m1", "content" => "hello"} =
               Client.next_sms!(stub_client(), "+14155550100", "+14155550111", timeout: 1.0)
    end

    test "next_sms! returns nil on timeout" do
      stub(fn conn -> Req.Test.json(conn, %{"messages" => []}) end)

      assert Client.next_sms!(stub_client(), "+14155550100", "+14155550111",
               timeout: 0.05,
               poll_interval: 0.01
             ) == nil
    end
  end

  describe "ensure_body (HTTP 411 regression)" do
    test "adds an empty body to body-less POST/PUT/PATCH" do
      assert HTTP.ensure_body([], :post, []) == [body: ""]
      assert HTTP.ensure_body([], :put, []) == [body: ""]
      assert HTTP.ensure_body([], :patch, []) == [body: ""]
    end

    test "does not touch GET/DELETE" do
      assert HTTP.ensure_body([], :get, []) == []
      assert HTTP.ensure_body([], :delete, []) == []
    end

    test "leaves requests that already carry a body alone" do
      assert HTTP.ensure_body([], :post, json: %{a: 1}) == []
      assert HTTP.ensure_body([], :post, form: [a: 1]) == []
      assert HTTP.ensure_body([], :post, body: "x") == []
    end
  end

  describe "error handling" do
    test "non-2xx: tuple form returns {:error, %Guava.Error{}}, bang raises" do
      stub(fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"detail" => "bad number"})
      end)

      assert {:error, %Error{type: :http, status: 422, body: body}} =
               Client.create_sip_agent(stub_client())

      assert body =~ "bad number"

      err = assert_raise Error, fn -> Client.create_sip_agent!(stub_client()) end
      assert err.status == 422
    end
  end
end

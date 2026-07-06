defmodule Guava.HelpersTest do
  use ExUnit.Case, async: false

  alias Guava.{Client, DatetimeFilter, DocumentQA, IntentRecognizer, LLM, RAG, SuggestedAction}

  defp client do
    Client.new!(
      api_key: "k",
      base_url: "https://app.goguava.ai/",
      req_options: [plug: {Req.Test, GuavaStub}]
    )
  end

  defp stub(fun) do
    Req.Test.stub(GuavaStub, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      parsed = if body == "", do: nil, else: Jason.decode!(body)
      send(self(), {:req, conn.method, conn.request_path, parsed})
      fun.(conn, parsed)
    end)
  end

  describe "chunk_document" do
    test "keeps a small doc as a single chunk" do
      assert RAG.chunk_document("hello\n\nworld") == ["hello\n\nworld"]
    end

    test "splits on paragraph boundaries past chunk_size and overlaps" do
      p1 = String.duplicate("a", 40)
      p2 = String.duplicate("b", 40)
      p3 = String.duplicate("c", 40)
      doc = Enum.join([p1, p2, p3], "\n\n")

      chunks = RAG.chunk_document(doc, 50, 40)
      assert length(chunks) >= 2
      assert Enum.all?(chunks, &is_binary/1)
      assert Enum.any?(chunks, &String.contains?(&1, p2))
    end

    test "drops blank paragraphs" do
      assert RAG.chunk_document("a\n\n\n\nb") == ["a\n\nb"]
    end
  end

  describe "LLM.generate" do
    test "generate! posts prompt and returns text; generate returns {:ok, _}" do
      stub(fn conn, _ -> Req.Test.json(conn, %{"text" => "hi"}) end)
      assert LLM.generate!(client(), "say hi") == "hi"
      assert {:ok, "hi"} = LLM.generate(client(), "say hi")
      assert_received {:req, "POST", "/v1/llm/generate", %{"prompt" => "say hi"}}
    end

    test "includes json_schema when provided" do
      stub(fn conn, _ -> Req.Test.json(conn, %{"text" => "{}"}) end)
      LLM.generate!(client(), "x", %{"type" => "object"})

      assert_received {:req, "POST", "/v1/llm/generate",
                       %{"json_schema" => %{"type" => "object"}}}
    end
  end

  describe "IntentRecognizer" do
    test "classify! into suggested actions (list choices)" do
      stub(fn conn, _ ->
        Req.Test.json(conn, %{"text" => Jason.encode!(%{"possible_matches" => ["sales"]})})
      end)

      r = IntentRecognizer.new(client(), ["sales", "support"])

      assert [%SuggestedAction{key: "sales", description: nil}] =
               IntentRecognizer.classify!(r, "buy stuff")
    end

    test "attaches descriptions for map choices" do
      stub(fn conn, _ ->
        Req.Test.json(conn, %{"text" => Jason.encode!(%{"possible_matches" => ["sales"]})})
      end)

      r = IntentRecognizer.new(client(), %{"sales" => "buying", "support" => "help"})

      assert {:ok, [%SuggestedAction{key: "sales", description: "buying"}]} =
               IntentRecognizer.classify(r, "buy")
    end

    test "returns nil when nothing matches" do
      stub(fn conn, _ ->
        Req.Test.json(conn, %{"text" => Jason.encode!(%{"possible_matches" => []})})
      end)

      r = IntentRecognizer.new(client(), ["sales"])
      assert IntentRecognizer.classify!(r, "weather?") == nil
    end
  end

  describe "DatetimeFilter" do
    test "filter! returns matched and other slots, capped" do
      stub(fn conn, _ ->
        Req.Test.json(conn, %{
          "text" =>
            Jason.encode!(%{
              "matching_appointments" => [
                "2026-07-03T10:00",
                "2026-07-03T11:00",
                "2026-07-03T12:00"
              ],
              "other_appointments" => ["2026-07-04T09:00"]
            })
        })
      end)

      f = DatetimeFilter.new(client(), ["2026-07-03T10:00", "2026-07-03T11:00"])
      {matched, other} = DatetimeFilter.filter!(f, "morning", 2)
      assert matched == ["2026-07-03T10:00", "2026-07-03T11:00"]
      assert other == ["2026-07-04T09:00"]
    end
  end

  describe "DocumentQA (server mode)" do
    test "reconciles documents on construction and asks scoped questions" do
      Req.Test.stub(GuavaStub, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        parsed = if body == "", do: nil, else: Jason.decode!(body)
        send(self(), {:req, conn.method, conn.request_path, parsed})

        case {conn.method, conn.request_path} do
          {"GET", "/v1/rag/documents"} -> Req.Test.json(conn, [])
          {"POST", "/v1/rag/documents"} -> Req.Test.json(conn, %{"key" => parsed["key"]})
          {"POST", "/v1/rag/ask"} -> Req.Test.json(conn, %{"answer" => "The deductible is $500."})
        end
      end)

      qa = DocumentQA.new(client(), documents: ["The deductible is $500."])
      assert_received {:req, "GET", "/v1/rag/documents", _}
      assert_received {:req, "POST", "/v1/rag/documents", %{"text" => "The deductible is $500."}}

      assert {:ok, "The deductible is $500."} = DocumentQA.ask(qa, "What is the deductible?")
      assert DocumentQA.ask!(qa, "again") == "The deductible is $500."

      assert_received {:req, "POST", "/v1/rag/ask",
                       %{"question" => "What is the deductible?", "document_keys" => keys}}

      assert is_list(keys) and length(keys) == 1
    end
  end
end

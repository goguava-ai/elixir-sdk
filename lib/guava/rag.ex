defmodule Guava.RAG.VectorStore do
  @moduledoc """
  Behaviour for a vector store backing local-mode `Guava.DocumentQA`.

  Implementations handle embedding internally: callers pass plain text and get
  plain text back. The store is any term (typically a struct) passed as the
  first argument to each callback.
  """
  @callback add_texts(store :: term(), texts :: [String.t()]) :: [String.t()]
  @callback upsert_texts(store :: term(), ids :: [String.t()], texts :: [String.t()]) :: :ok
  @callback delete(store :: term(), ids :: [String.t()]) :: :ok
  @callback search(store :: term(), query :: String.t(), k :: pos_integer()) :: [String.t()]
  @callback clear(store :: term()) :: :ok
  @callback count(store :: term()) :: non_neg_integer()
end

defmodule Guava.RAG.GenerationModel do
  @moduledoc """
  Behaviour for a QA generation model backing local-mode `Guava.DocumentQA`.
  """
  @callback generate(
              model :: term(),
              prompt :: String.t(),
              system_instruction :: String.t() | nil
            ) :: String.t()
end

defmodule Guava.RAG.EmbeddingModel do
  @moduledoc "Behaviour for an embedding model used by vector-store implementations."
  @callback ndims(model :: term()) :: pos_integer()
  @callback embed(model :: term(), texts :: [String.t()]) :: [[float()]]
end

defmodule Guava.RAG do
  @moduledoc "Retrieval-augmented-generation helpers."

  @doc """
  Split a document into overlapping chunks on paragraph boundaries.

  Paragraphs (separated by blank lines) are grouped until `chunk_size`
  characters, then a new chunk begins. With `overlap > 0`, the last paragraph
  of a chunk is carried into the next to preserve cross-boundary context.
  """
  @spec chunk_document(String.t(), pos_integer(), non_neg_integer()) :: [String.t()]
  def chunk_document(document, chunk_size \\ 5000, overlap \\ 200) do
    paragraphs =
      document
      |> String.split("\n\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {chunks, current, _len} =
      Enum.reduce(paragraphs, {[], [], 0}, fn para, {chunks, current, len} ->
        para_len = String.length(para)

        {chunks, current, len} =
          if len + para_len > chunk_size and current != [] do
            chunk = current |> Enum.reverse() |> Enum.join("\n\n")

            if overlap > 0 do
              last = hd(current)
              {[chunk | chunks], [last], String.length(last)}
            else
              {[chunk | chunks], [], 0}
            end
          else
            {chunks, current, len}
          end

        {chunks, [para | current], len + para_len}
      end)

    chunks =
      if current == [],
        do: chunks,
        else: [current |> Enum.reverse() |> Enum.join("\n\n") | chunks]

    Enum.reverse(chunks)
  end
end

defmodule Guava.RAG.ServerRAG do
  @moduledoc """
  RAG via the Guava server API (`v1/rag/*`). Uploads plain-text documents; the
  server stores and answers over them. Handles content-addressed keys and
  namespace scoping.
  """
  require Logger
  alias Guava.HTTP

  @doc "Derive a deterministic 16-char key from document content."
  @spec content_key(String.t()) :: String.t()
  def content_key(text) do
    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end

  @doc "Apply a namespace prefix to a key when a namespace is set."
  @spec prefixed_key(String.t() | nil, String.t()) :: String.t()
  def prefixed_key(nil, key), do: key
  def prefixed_key(ns, key), do: "#{ns}.#{key}"

  @doc "Upload (or replace) a document by key."
  @spec upload_document(Guava.Client.t(), String.t(), String.t()) :: map()
  def upload_document(client, key, text) do
    HTTP.request!(client, :post, "v1/rag/documents",
      json: %{key: key, text: text},
      receive_timeout: 60_000
    )
  end

  @doc "Delete a document by key."
  @spec delete_document(Guava.Client.t(), String.t()) :: :ok
  def delete_document(client, key) do
    HTTP.request!(client, :delete, "v1/rag/documents/#{key}", receive_timeout: 30_000)
    :ok
  end

  @doc "List stored documents."
  @spec list_documents(Guava.Client.t()) :: [map()]
  def list_documents(client),
    do: HTTP.request!(client, :get, "v1/rag/documents", receive_timeout: 30_000)

  @doc "Ask a question, optionally scoped to `document_keys`, with optional `instructions`."
  @spec ask(Guava.Client.t(), String.t(), [String.t()] | nil, String.t() | nil) :: String.t()
  def ask(client, question, document_keys \\ nil, instructions \\ nil) do
    payload =
      %{question: question}
      |> maybe_put(:document_keys, document_keys)
      |> maybe_put(:instructions, instructions)

    body = HTTP.request!(client, :post, "v1/rag/ask", json: payload, receive_timeout: 120_000)
    if body["warning"], do: Logger.warning("Guava RAG: #{body["warning"]}")
    body["answer"]
  end

  @doc """
  Sync server state to match `documents`.

  Returns the set of tracked keys. When `ids` is `nil`, keys are content
  hashes and unchanged documents are skipped; stale documents in the namespace
  are deleted.
  """
  @spec reconcile(Guava.Client.t(), String.t() | nil, [String.t()], [String.t()] | nil) ::
          MapSet.t()
  def reconcile(client, namespace, documents, ids) do
    desired =
      if ids do
        ids
        |> Enum.zip(documents)
        |> Map.new(fn {k, doc} -> {prefixed_key(namespace, k), doc} end)
      else
        Map.new(documents, fn doc -> {prefixed_key(namespace, content_key(doc)), doc} end)
      end

    existing = client |> list_documents() |> Enum.map(& &1["key"]) |> MapSet.new()

    scoped =
      if namespace do
        existing |> Enum.filter(&String.starts_with?(&1, "#{namespace}.")) |> MapSet.new()
      else
        existing
      end

    tracked =
      Enum.reduce(desired, MapSet.new(), fn {key, doc}, acc ->
        if ids != nil or not MapSet.member?(existing, key), do: upload_document(client, key, doc)
        MapSet.put(acc, key)
      end)

    stale = MapSet.difference(scoped, MapSet.new(Map.keys(desired)))
    Enum.each(stale, &delete_document(client, &1))

    tracked
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule Guava.DocumentQA do
  @moduledoc """
  Question-answering over documents.

  **Server mode** (default): documents are uploaded to the Guava server, which
  answers questions over them. No local vector store needed.

      qa = Guava.DocumentQA.new(client, documents: [policy_text, faq_text])
      {:ok, answer} = Guava.DocumentQA.ask(qa, "What is the deductible?")

  **Local mode**: pass a `:store` (implementing `Guava.RAG.VectorStore`) and a
  `:generation_model` (implementing `Guava.RAG.GenerationModel`), each as a
  `{module, state}` tuple.
  """
  require Logger
  alias Guava.RAG
  alias Guava.RAG.ServerRAG

  @default_instructions "You are a virtual agent. Your task is to answer questions using " <>
                          "ONLY the provided supporting document excerpts. If the answer is not " <>
                          "in the provided context, say so. Just answer the question — do not offer " <>
                          "any follow-ups."

  defstruct mode: :server,
            client: nil,
            namespace: nil,
            instructions: nil,
            tracked_keys: nil,
            store: nil,
            generation_model: nil,
            chunk_size: 5000,
            chunk_overlap: 200

  @type t :: %__MODULE__{}

  @doc """
  Build a `DocumentQA`.

  ## Options
    * `:documents` — string or list of strings to index at construction.
    * `:ids` — optional stable ids for the documents (enables later update).
    * `:namespace` — scope this instance's documents on the server.
    * `:instructions` — system instruction for answering.
    * `:store`, `:generation_model` — switch to local mode (`{module, state}`).
    * `:chunk_size`, `:chunk_overlap` — local-mode chunking.
  """
  @spec new(Guava.Client.t(), keyword()) :: t()
  def new(client, opts \\ []) do
    documents = opts[:documents] |> normalize_docs()
    ids = opts[:ids]

    if opts[:store] do
      qa = %__MODULE__{
        mode: :local,
        client: client,
        instructions: opts[:instructions],
        store: opts[:store],
        generation_model:
          opts[:generation_model] || raise(ArgumentError, "local mode requires :generation_model"),
        chunk_size: opts[:chunk_size] || 5000,
        chunk_overlap: opts[:chunk_overlap] || 200
      }

      index_local(qa, documents, ids)
    else
      tracked =
        if documents != [],
          do: ServerRAG.reconcile(client, opts[:namespace], documents, ids),
          else: MapSet.new()

      %__MODULE__{
        mode: :server,
        client: client,
        namespace: opts[:namespace],
        instructions: opts[:instructions],
        tracked_keys: tracked
      }
    end
  end

  @doc "Answer `question` over this instance's documents. Returns `{:ok, answer} | {:error, _}`."
  @spec ask(t(), String.t(), pos_integer()) :: {:ok, String.t()} | {:error, Guava.Error.t()}
  def ask(qa, question, k \\ 5), do: Guava.Error.wrap(fn -> ask!(qa, question, k) end)

  @doc "Like `ask/3`, but returns the answer or raises `Guava.Error`."
  @spec ask!(t(), String.t(), pos_integer()) :: String.t()
  def ask!(qa, question, k \\ 5)

  def ask!(%__MODULE__{mode: :server} = qa, question, _k) do
    keys = if MapSet.size(qa.tracked_keys) > 0, do: MapSet.to_list(qa.tracked_keys), else: nil
    ServerRAG.ask(qa.client, question, keys, qa.instructions)
  end

  def ask!(%__MODULE__{mode: :local} = qa, question, k) do
    {store_mod, store_state} = qa.store
    {gen_mod, gen_state} = qa.generation_model
    chunks = store_mod.search(store_state, question, k)
    context = Enum.join(chunks, "\n\n---\n\n")

    gen_mod.generate(
      gen_state,
      "Context:\n#{context}\n\nQuestion: #{question}",
      qa.instructions || @default_instructions
    )
  end

  @doc "Add or replace a document by key. Returns the updated `DocumentQA`."
  @spec upsert_document(t(), String.t(), String.t()) :: t()
  def upsert_document(%__MODULE__{mode: :server} = qa, key, text) do
    full_key = ServerRAG.prefixed_key(qa.namespace, key)
    ServerRAG.upload_document(qa.client, full_key, text)
    %{qa | tracked_keys: MapSet.put(qa.tracked_keys, full_key)}
  end

  @doc "Add a document (content-addressed). Returns the updated `DocumentQA`."
  @spec add_document(t(), String.t()) :: t()
  def add_document(%__MODULE__{mode: :server} = qa, text) do
    full_key = ServerRAG.prefixed_key(qa.namespace, ServerRAG.content_key(text))
    ServerRAG.upload_document(qa.client, full_key, text)
    %{qa | tracked_keys: MapSet.put(qa.tracked_keys, full_key)}
  end

  @doc "Delete a document by key. Returns the updated `DocumentQA`."
  @spec delete_document(t(), String.t()) :: t()
  def delete_document(%__MODULE__{mode: :server} = qa, key) do
    full_key = ServerRAG.prefixed_key(qa.namespace, key)
    ServerRAG.delete_document(qa.client, full_key)
    %{qa | tracked_keys: MapSet.delete(qa.tracked_keys, full_key)}
  end

  @doc "Delete all documents tracked by this instance. Returns the updated `DocumentQA`."
  @spec clear(t()) :: t()
  def clear(%__MODULE__{mode: :server} = qa) do
    Enum.each(qa.tracked_keys, &ServerRAG.delete_document(qa.client, &1))
    %{qa | tracked_keys: MapSet.new()}
  end

  defp normalize_docs(nil), do: []
  defp normalize_docs(doc) when is_binary(doc), do: [doc]
  defp normalize_docs(docs) when is_list(docs), do: docs

  defp index_local(%__MODULE__{store: {store_mod, store_state}} = qa, documents, nil) do
    chunks = Enum.flat_map(documents, &RAG.chunk_document(&1, qa.chunk_size, qa.chunk_overlap))
    if chunks != [], do: store_mod.add_texts(store_state, chunks)
    qa
  end

  defp index_local(%__MODULE__{store: {store_mod, store_state}} = qa, documents, ids) do
    {all_ids, all_chunks} =
      ids
      |> Enum.zip(documents)
      |> Enum.reduce({[], []}, fn {key, doc}, {ids_acc, chunks_acc} ->
        chunks = RAG.chunk_document(doc, qa.chunk_size, qa.chunk_overlap)
        chunk_ids = Enum.with_index(chunks, fn _c, i -> "#{key}:#{i}" end)
        {ids_acc ++ chunk_ids, chunks_acc ++ chunks}
      end)

    if all_chunks != [], do: store_mod.upsert_texts(store_state, all_ids, all_chunks)
    qa
  end
end

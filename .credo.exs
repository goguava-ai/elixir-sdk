%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/examples/"]
      },
      strict: true,
      checks: %{
        disabled: [
          # Long moduledoc lines / prompt strings are intentional.
          {Credo.Check.Readability.MaxLineLength, false},
          # Discriminated-union decoders (events/frames) are inherently branchy
          # but perfectly clear; cyclomatic/cond checks fight that pattern.
          {Credo.Check.Refactor.CyclomaticComplexity, false},
          {Credo.Check.Refactor.CondStatements, false},
          # `call_id` is a valid custom Logger metadata key (declared in config).
          {Credo.Check.Warning.LoggerMetadataKeys, false},
          # Style opinions the formatter doesn't enforce; we reference some
          # modules fully-qualified on purpose and don't hand-sort alias groups.
          {Credo.Check.Readability.AliasOrder, false},
          {Credo.Check.Design.AliasUsage, false}
        ],
        extra: [
          {Credo.Check.Refactor.Nesting, max_nesting: 3}
        ]
      }
    }
  ]
}

import Config

# `call_id` is attached per call (see Guava.Call.Runtime) for correlated logs.
config :logger, :console, metadata: [:call_id]

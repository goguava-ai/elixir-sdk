# Local development

The Guava Elixir SDK develops like any Elixir project: install Erlang + Elixir on
your machine, then `mix deps.get && mix test`. There is **no virtualenv step** —
Mix always keeps dependencies in a per-project `deps/` and compiles to a
per-project `_build/`, so projects are isolated automatically.

The toolchain is pinned in [`.tool-versions`](../.tool-versions):

```
erlang 27.3.4.13
elixir 1.18.4-otp-27
```

## Recommended: a version manager

[`mise`](https://mise.jdx.dev) (modern, fast) or [`asdf`](https://asdf-vm.com)
(long-standing standard) both read `.tool-versions` and install the exact
versions this repo targets:

```bash
# mise
curl https://mise.run | sh
mise install                 # reads .tool-versions
mix deps.get && mix test

# asdf
asdf plugin add erlang && asdf plugin add elixir
asdf install                 # reads .tool-versions
mix deps.get && mix test
```

**Caveat:** both compile Erlang from source, which needs build packages:

```bash
sudo apt install build-essential autoconf m4 libssl-dev libncurses-dev \
                 libssh-dev unixodbc-dev libgmp-dev
```

The system Erlang from `apt install erlang` is **not** sufficient — Ubuntu's
package is split and omits pieces some deps need (e.g. `parsetools` headers),
which breaks `earmark_parser`/`mint`.

## No sudo? Precompiled Erlang + Elixir into `~/.local`

If you can't install build packages, download the precompiled builds that CI uses
([builds.hex.pm](https://builds.hex.pm)) — no compilation, no sudo. Pick the OTP
tarball for your distro (`ubuntu-24.04`, `ubuntu-22.04`, …) and the matching
Elixir `-otp-27` zip:

```bash
# --- complete Erlang/OTP 27 ---
mkdir -p ~/.local/otp
curl -fsSL https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/OTP-27.3.4.13.tar.gz \
  | tar -xz -C ~/.local/otp --strip-components=1
( cd ~/.local/otp && ./Install -minimal "$PWD" )

# --- Elixir 1.18.4 (built for OTP 27) ---
mkdir -p ~/.local/elixir
curl -fsSL https://builds.hex.pm/builds/elixir/v1.18.4-otp-27.zip -o /tmp/elixir.zip
unzip -q -o /tmp/elixir.zip -d ~/.local/elixir && rm /tmp/elixir.zip

# --- put both on PATH (add to ~/.bashrc / ~/.zshrc) ---
export PATH="$HOME/.local/otp/bin:$HOME/.local/elixir/bin:$PATH"

# --- one-time hex + rebar ---
mix local.hex --force && mix local.rebar --force
```

Verify: `elixir --version` should report `Elixir 1.18.4 (compiled with
Erlang/OTP 27)`. Then `mix deps.get && mix test` runs the suite natively.

List available versions for your distro:

```bash
curl -s https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt
curl -s https://builds.hex.pm/builds/elixir/builds.txt | grep otp-27
```

## Docker fallback

If you'd rather not install anything, use the pinned container via `./emix`
(see the [README](../README.md#docker-optional-fallback)). Its `_build`/`deps`
live in named volumes, so it never writes into — or clobbers — your native build.

## Examples

Runnable examples live in [`examples/`](../examples). See
[`examples/help_desk.exs`](../examples/help_desk.exs) for a self-contained agent
built on the same toolchain.

# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.20.2-erlang-29.0.3-debian-trixie-20260713-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260713-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20260713-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=trixie-20260713-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
# `ca-certificates` is not in the generated list and is needed here: this
# build downloads CLDR locale data and the ICU word-break dictionaries over
# HTTPS. Without it those fetches fail and the image is quietly missing the
# data the app needs.
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# The ICU word-break dictionaries are downloaded, not vendored, and they land
# in the unicode_string dep's priv — so this belongs with the deps, where it
# caches, rather than later where every code change would re-fetch 16MB.
#
# Missing them does not fail the build or the boot. It degrades: a Japanese or
# Thai line stops being segmented and arrives as one token, so the sheet reads
# as prose and answers nothing. Silent wrong-shaped output is why this is a
# build step and not a runtime fallback.
RUN mix unicode.string.download.dictionaries

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

# CLDR locale data, downloaded into this app's own priv — hence after compile,
# unlike the dictionaries above. Without it every locale falls back and the
# whole premise of the app goes with it.
RUN mix localize.download_locales

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/localize_pad ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]

FROM rust:1.88-bookworm AS builder

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN cargo build --release --bin remote_control_relay_rust

FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --create-home --uid 10001 relayuser

COPY --from=builder /app/target/release/remote_control_relay_rust /usr/local/bin/remote-control-relay

USER relayuser
WORKDIR /home/relayuser

EXPOSE 8787

ENV HOST=0.0.0.0
ENV PORT=8787

ENTRYPOINT ["/usr/local/bin/remote-control-relay"]

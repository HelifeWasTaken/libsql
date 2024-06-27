# build sqld
FROM rust:slim-bullseye AS chef
RUN apt update \
    && apt install -y libclang-dev clang \
        build-essential tcl protobuf-compiler file \
        libssl-dev pkg-config git tcl cmake \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# We need to install and set as default the toolchain specified in rust-toolchain.toml
# Otherwise cargo-chef will build dependencies using wrong toolchain
# This also prevents planner and builder steps from installing the toolchain over and over again
COPY rust-toolchain.toml rust-toolchain.toml
RUN cat rust-toolchain.toml | grep "channel" | awk '{print $3}' | sed 's/\"//g' > toolchain.txt \
    && rustup update $(cat toolchain.txt) \
    && rustup default $(cat toolchain.txt) \
    && rm toolchain.txt rust-toolchain.toml \
    && cargo install cargo-chef

FROM chef AS planner
ARG BUILD_DEBUG=false
ENV CARGO_PROFILE_RELEASE_DEBUG=$BUILD_DEBUG
RUN echo $CARGO_PROFILE_RELEASE_DEBUG
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
ARG BUILD_DEBUG=false
ENV CARGO_PROFILE_RELEASE_DEBUG=$BUILD_DEBUG
COPY --from=planner /recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json
COPY . .
ARG ENABLE_FEATURES=""
RUN if [ "$ENABLE_FEATURES" == "" ]; then \
        cargo build -p libsql-server --release ; \
    else \
        cargo build -p libsql-server --features "$ENABLE_FEATURES" --release ; \
    fi
# runtime
FROM debian:bullseye-slim
RUN apt update

EXPOSE 5001 8080
VOLUME [ "/var/lib/sqld" ]

RUN groupadd --system --gid 666 sqld
RUN adduser --system --home /var/lib/sqld --uid 666 --gid 666 sqld
WORKDIR /var/lib/sqld
USER sqld

COPY docker-entrypoint.sh /usr/local/bin

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /target/release/sqld /bin/sqld

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/bin/sqld"]

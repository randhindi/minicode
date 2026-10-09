# Build stage
FROM rust:1.82 AS build
WORKDIR /src
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
ENV RUST_LOG=info
COPY --from=build /src/target/release/demo /usr/local/bin/demo
ENTRYPOINT ["demo", "--port", "${PORT}"]

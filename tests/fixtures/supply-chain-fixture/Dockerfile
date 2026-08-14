ARG TARGETPLATFORM=linux/amd64
FROM golang:1.26.6-bookworm@sha256:433f9dc4f8ea3a1ce4e28f9f15d0f7c056b10475307f886d6f1ac1ccc4abd976 AS test

WORKDIR /src
ARG TARGETPLATFORM
RUN test "$TARGETPLATFORM" = "linux/amd64"
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN go test ./...

FROM test AS build

ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64
RUN go build -trimpath -buildvcs=false -ldflags="-buildid=" -o /out/supply-chain-fixture ./cmd/server

FROM scratch AS runtime

LABEL org.opencontainers.image.source="https://github.com/Franklindot04/k8s-internal-developer-platform"

USER 65532:65532
EXPOSE 8080
COPY --from=build /out/supply-chain-fixture /supply-chain-fixture
ENTRYPOINT ["/supply-chain-fixture"]

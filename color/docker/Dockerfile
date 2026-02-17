FROM golang:1.26-alpine3.23@sha256:d4c4845f5d60c6a974c6000ce58ae079328d03ab7f721a0734277e69905473e5 AS builder

WORKDIR /app

COPY . .

# Build arguments for version information
ARG VERSION=dev
ARG BUILD_DATE=unknown
ARG GIT_COMMIT=unknown

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo \
    -ldflags="-s -w \
    -X 'github.com/davidaparicio/color/internal/version.Version=${VERSION}' \
    -X 'github.com/davidaparicio/color/internal/version.BuildDate=${BUILD_DATE}' \
    -X 'github.com/davidaparicio/color/internal/version.GitCommit=${GIT_COMMIT}'" \
    -o app webcolor_ff.go

FROM scratch

WORKDIR /app

# Copy the binary
COPY --from=builder /app/app /app/app

# Copy static assets and templates
COPY --from=builder /app/assets /app/assets
COPY --from=builder /app/demo-flags.goff.yaml /app/demo-flags.goff.yaml

ENTRYPOINT ["/app/app"]
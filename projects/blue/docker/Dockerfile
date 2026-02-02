FROM golang:1.25-alpine3.23@sha256:660f0b83cf50091e3777e4730ccc0e63e83fea2c420c872af5c60cb357dcafb2 AS builder

WORKDIR /app

# Copy dependency files first (cached unless go.mod/go.sum change)
COPY go.mod go.sum ./

# Download dependencies (cached layer)
RUN go mod download

# Copy source code (changes frequently)
COPY . .

# Build arguments for version information
ARG VERSION=dev
ARG BUILD_DATE=unknown
ARG GIT_COMMIT=unknown

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo \
    -ldflags="-s -w \
    -X 'github.com/davidaparicio/microsvcs/projects/blue/internal/version.Version=${VERSION}' \
    -X 'github.com/davidaparicio/microsvcs/projects/blue/internal/version.BuildDate=${BUILD_DATE}' \
    -X 'github.com/davidaparicio/microsvcs/projects/blue/internal/version.GitCommit=${GIT_COMMIT}'" \
    -o app webcolor_ff.go

FROM scratch

WORKDIR /app

# Copy CA certificates for HTTPS connections
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the binary
COPY --from=builder /app/app /app/app

# Copy static assets and templates
COPY --from=builder /app/assets /app/assets
COPY --from=builder /app/demo-flags.goff.yaml /app/demo-flags.goff.yaml

ENTRYPOINT ["/app/app"]
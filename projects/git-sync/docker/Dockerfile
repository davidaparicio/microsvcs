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
    -X 'github.com/davidaparicio/microsvcs/projects/git-sync/internal/version.Version=${VERSION}' \
    -X 'github.com/davidaparicio/microsvcs/projects/git-sync/internal/version.BuildDate=${BUILD_DATE}' \
    -X 'github.com/davidaparicio/microsvcs/projects/git-sync/internal/version.GitCommit=${GIT_COMMIT}'" \
    -o git-sync main.go

FROM scratch

WORKDIR /app

# Copy CA certificates for HTTPS git operations
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the binary
COPY --from=builder /app/git-sync /app/git-sync

ENTRYPOINT ["/app/git-sync"]

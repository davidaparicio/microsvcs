package sync

import (
	"testing"
	"time"

	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/config"
	"github.com/stretchr/testify/assert"
)

// Regression test: health checks must not block while a sync is in flight
// (Sync used to hold the status RWMutex for the whole clone/pull, causing
// Kubernetes probe timeouts on slow syncs).
func TestHealthCheckNotBlockedDuringSync(t *testing.T) {
	cfg := &config.Config{
		RepoURL:    "https://github.com/test/repo.git",
		Branch:     "main",
		TargetPath: t.TempDir(),
	}

	syncer, err := NewSyncer(cfg)
	assert.NoError(t, err)

	// Simulate an in-flight sync
	syncer.syncMu.Lock()
	defer syncer.syncMu.Unlock()

	done := make(chan struct{})
	go func() {
		syncer.IsHealthy()
		syncer.GetStatus()
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("IsHealthy/GetStatus blocked while a sync is in flight")
	}
}

func TestShortCommit(t *testing.T) {
	tests := []struct {
		name   string
		commit string
		want   string
	}{
		{"full sha", "54a8d74ea3cf6fdcadfac10ee4a4f2553d4562f6", "54a8d74"},
		{"exactly seven", "54a8d74", "54a8d74"},
		{"shorter than seven", "54a8", "54a8"},
		{"empty", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, shortCommit(tt.commit))
		})
	}
}

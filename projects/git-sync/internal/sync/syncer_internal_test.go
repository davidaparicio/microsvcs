package sync

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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

func TestCopyFileReplacesAtomically(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src.yaml")
	dst := filepath.Join(dir, "dst.yaml")
	require.NoError(t, os.WriteFile(src, []byte("new"), 0640))
	require.NoError(t, os.WriteFile(dst, []byte("old content"), 0600))

	require.NoError(t, copyFile(src, dst))

	got, err := os.ReadFile(dst)
	require.NoError(t, err)
	assert.Equal(t, "new", string(got))
	info, err := os.Stat(dst)
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0640), info.Mode().Perm())

	entries, err := os.ReadDir(dir)
	require.NoError(t, err)
	assert.Len(t, entries, 2, "temp file must not be left behind")
}

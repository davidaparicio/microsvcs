package sync_test

import (
	"testing"

	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/config"
	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/sync"
	"github.com/stretchr/testify/assert"
)

func TestNewSyncer(t *testing.T) {
	cfg := &config.Config{
		RepoURL:    "https://github.com/test/repo.git",
		Branch:     "main",
		TargetPath: "/tmp/test",
	}

	syncer, err := sync.NewSyncer(cfg)
	assert.NoError(t, err)
	assert.NotNil(t, syncer)
}

func TestGetStatus(t *testing.T) {
	cfg := &config.Config{
		RepoURL:    "https://github.com/test/repo.git",
		Branch:     "main",
		TargetPath: "/tmp/test",
	}

	syncer, err := sync.NewSyncer(cfg)
	assert.NoError(t, err)

	status := syncer.GetStatus()
	assert.NotNil(t, status)
	assert.Equal(t, false, status["healthy"])
	assert.Equal(t, "https://github.com/test/repo.git", status["repoURL"])
	assert.Equal(t, "main", status["branch"])
}

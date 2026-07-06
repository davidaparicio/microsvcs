package git_test

import (
	"testing"

	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/config"
	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/git"
	"github.com/stretchr/testify/assert"
)

func TestNewClient(t *testing.T) {
	cfg := &config.Config{
		RepoURL: "https://github.com/test/repo.git",
		Branch:  "main",
	}

	client, err := git.NewClient(cfg)
	assert.NoError(t, err)
	assert.NotNil(t, client)
	assert.NotEmpty(t, client.WorkDir())
}

func TestClientClose(t *testing.T) {
	cfg := &config.Config{
		RepoURL: "https://github.com/test/repo.git",
		Branch:  "main",
	}

	client, err := git.NewClient(cfg)
	assert.NoError(t, err)
	assert.DirExists(t, client.WorkDir())

	assert.NoError(t, client.Close())
	assert.NoDirExists(t, client.WorkDir())
}

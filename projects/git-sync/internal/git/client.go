package git

import (
	"context"
	"fmt"
	"os"

	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/config"
	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing"
)

type Client struct {
	cfg     *config.Config
	workDir string
	repo    *git.Repository
}

func NewClient(cfg *config.Config) (*Client, error) {
	// Create temporary work directory with unique name
	workDir, err := os.MkdirTemp("", "git-sync-work-*")
	if err != nil {
		return nil, fmt.Errorf("failed to create work directory: %w", err)
	}

	return &Client{
		cfg:     cfg,
		workDir: workDir,
	}, nil
}

func (c *Client) Sync(ctx context.Context) (string, error) {
	if c.repo == nil {
		return c.clone(ctx)
	}
	return c.pull(ctx)
}

func (c *Client) clone(ctx context.Context) (string, error) {
	fmt.Printf("Cloning repository: %s (branch: %s)\n", c.cfg.RepoURL, c.cfg.Branch)

	repo, err := git.PlainCloneContext(ctx, c.workDir, false, &git.CloneOptions{
		URL:           c.cfg.RepoURL,
		ReferenceName: plumbing.NewBranchReferenceName(c.cfg.Branch),
		SingleBranch:  true,
		Depth:         1, // Shallow clone for efficiency
	})
	if err != nil {
		return "", fmt.Errorf("clone failed: %w", err)
	}

	c.repo = repo
	return c.getHeadCommit()
}

func (c *Client) pull(ctx context.Context) (string, error) {
	fmt.Printf("Pulling latest changes from branch: %s\n", c.cfg.Branch)

	w, err := c.repo.Worktree()
	if err != nil {
		return "", fmt.Errorf("failed to get worktree: %w", err)
	}

	err = w.PullContext(ctx, &git.PullOptions{
		ReferenceName: plumbing.NewBranchReferenceName(c.cfg.Branch),
		SingleBranch:  true,
	})

	// Ignore "already up to date" errors
	if err != nil && err != git.NoErrAlreadyUpToDate {
		return "", fmt.Errorf("pull failed: %w", err)
	}

	return c.getHeadCommit()
}

func (c *Client) getHeadCommit() (string, error) {
	ref, err := c.repo.Head()
	if err != nil {
		return "", fmt.Errorf("failed to get HEAD: %w", err)
	}
	return ref.Hash().String(), nil
}

func (c *Client) WorkDir() string {
	return c.workDir
}

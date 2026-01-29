package sync

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/config"
	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/git"
)

type Syncer struct {
	cfg        *config.Config
	git        *git.Client
	mu         sync.RWMutex
	lastSync   time.Time
	lastCommit string
	syncCount  int64
	errorCount int64
	healthy    bool
}

func NewSyncer(cfg *config.Config) (*Syncer, error) {
	gitClient, err := git.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create git client: %w", err)
	}

	return &Syncer{
		cfg:     cfg,
		git:     gitClient,
		healthy: false,
	}, nil
}

func (s *Syncer) Sync(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	fmt.Printf("[%s] Starting sync from %s (branch: %s)\n",
		time.Now().Format(time.RFC3339), s.cfg.RepoURL, s.cfg.Branch)

	// Clone or pull repository
	commit, err := s.git.Sync(ctx)
	if err != nil {
		s.errorCount++
		s.healthy = false
		return fmt.Errorf("git sync failed: %w", err)
	}

	// Copy files from source path to target path
	if err := s.copyFiles(); err != nil {
		s.errorCount++
		s.healthy = false
		return fmt.Errorf("file copy failed: %w", err)
	}

	s.lastSync = time.Now()
	s.lastCommit = commit
	s.syncCount++
	s.healthy = true

	fmt.Printf("[%s] Sync completed successfully (commit: %s)\n",
		time.Now().Format(time.RFC3339), commit[:7])

	return nil
}

func (s *Syncer) copyFiles() error {
	sourcePath := filepath.Join(s.git.WorkDir(), s.cfg.SourcePath)

	// Ensure target directory exists
	if err := os.MkdirAll(s.cfg.TargetPath, 0755); err != nil {
		return fmt.Errorf("failed to create target directory: %w", err)
	}

	// Check if source is a file or directory
	sourceInfo, err := os.Stat(sourcePath)
	if err != nil {
		return fmt.Errorf("failed to stat source path: %w", err)
	}

	// If source is a single file, copy it directly
	if !sourceInfo.IsDir() {
		targetFile := filepath.Join(s.cfg.TargetPath, filepath.Base(sourcePath))
		return copyFile(sourcePath, targetFile)
	}

	// Walk source directory and copy files
	return filepath.Walk(sourcePath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip .git directory
		if info.IsDir() && info.Name() == ".git" {
			return filepath.SkipDir
		}

		// Calculate relative path
		relPath, err := filepath.Rel(sourcePath, path)
		if err != nil {
			return err
		}

		targetPath := filepath.Join(s.cfg.TargetPath, relPath)

		if info.IsDir() {
			return os.MkdirAll(targetPath, info.Mode())
		}

		return copyFile(path, targetPath)
	})
}

func copyFile(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer sourceFile.Close()

	destFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer destFile.Close()

	if _, err := io.Copy(destFile, sourceFile); err != nil {
		return err
	}

	// Preserve file permissions
	sourceInfo, err := os.Stat(src)
	if err != nil {
		return err
	}
	return os.Chmod(dst, sourceInfo.Mode())
}

func (s *Syncer) GetStatus() map[string]any {
	s.mu.RLock()
	defer s.mu.RUnlock()

	return map[string]any{
		"healthy":    s.healthy,
		"lastSync":   s.lastSync,
		"lastCommit": s.lastCommit,
		"syncCount":  s.syncCount,
		"errorCount": s.errorCount,
		"repoURL":    s.cfg.RepoURL,
		"branch":     s.cfg.Branch,
		"targetPath": s.cfg.TargetPath,
	}
}

func (s *Syncer) IsHealthy() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.healthy
}

package config

import (
	"fmt"
	"os"
)

type Config struct {
	// Git repository settings
	RepoURL    string // GIT_REPO_URL
	Branch     string // GIT_BRANCH (default: main)
	SourcePath string // GIT_SOURCE_PATH (path within repo, default: /)

	// File system settings
	TargetPath string // TARGET_PATH (where to write files)

	// Sync settings
	SyncInterval string // SYNC_INTERVAL (cron format, default: "*/5 * * * *" = every 5 min)
	SyncOnce     bool   // SYNC_ONCE (run once and exit, default: false)

	// Server settings
	Port string // PORT (default: 8080)
}

func LoadFromEnv() *Config {
	return &Config{
		RepoURL:      os.Getenv("GIT_REPO_URL"),
		Branch:       getEnvOrDefault("GIT_BRANCH", "main"),
		SourcePath:   getEnvOrDefault("GIT_SOURCE_PATH", "/"),
		TargetPath:   getEnvOrDefault("TARGET_PATH", "/data"),
		SyncInterval: getEnvOrDefault("SYNC_INTERVAL", "*/5 * * * *"),
		SyncOnce:     os.Getenv("SYNC_ONCE") == "true",
		Port:         getEnvOrDefault("PORT", "8080"),
	}
}

func (c *Config) Validate() error {
	if c.RepoURL == "" {
		return fmt.Errorf("GIT_REPO_URL is required")
	}
	if c.TargetPath == "" {
		return fmt.Errorf("TARGET_PATH is required")
	}
	return nil
}

func getEnvOrDefault(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}

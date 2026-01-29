package sync_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/config"
	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/sync"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
)

// FeatureFlagConfig represents the structure of demo-flags.goff.yaml
type FeatureFlagConfig struct {
	ColorBox struct {
		Variations  map[string]string `yaml:"variations"`
		Targeting   []interface{}     `yaml:"targeting"`
		DefaultRule struct {
			Percentage map[string]int `yaml:"percentage"`
		} `yaml:"defaultRule"`
		Disable bool `yaml:"disable"`
	} `yaml:"color-box"`
}

// TestE2E_SyncDemoFlags tests the full sync workflow with the real microsvcs repository
// This test validates that git-sync can:
// 1. Clone the microsvcs repository
// 2. Sync the color/demo-flags.goff.yaml file
// 3. Correctly copy it to the target directory
// 4. The file contains the expected percentage values
func TestE2E_SyncDemoFlags(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping E2E test in short mode")
	}

	// Create temporary directory for synced files
	tmpDir, err := os.MkdirTemp("", "git-sync-e2e-*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Configure syncer to sync the color directory from the real repo
	cfg := &config.Config{
		RepoURL:      "https://github.com/davidaparicio/microsvcs.git",
		Branch:       "main",
		SourcePath:   "/color",
		TargetPath:   tmpDir,
		SyncInterval: "*/5 * * * *",
		Port:         "8080",
	}

	// Create syncer
	syncer, err := sync.NewSyncer(cfg)
	require.NoError(t, err, "Failed to create syncer")
	require.NotNil(t, syncer, "Syncer should not be nil")

	// Run sync with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	t.Log("Starting sync from microsvcs repository...")
	err = syncer.Sync(ctx)
	require.NoError(t, err, "Sync should complete without errors")

	// Verify syncer is healthy
	assert.True(t, syncer.IsHealthy(), "Syncer should be healthy after successful sync")

	// Check syncer status
	status := syncer.GetStatus()
	assert.True(t, status["healthy"].(bool), "Status should indicate healthy")
	assert.NotEmpty(t, status["lastCommit"], "Should have a commit hash")
	assert.Equal(t, int64(1), status["syncCount"], "Should have synced once")
	assert.Equal(t, int64(0), status["errorCount"], "Should have no errors")

	t.Logf("Sync completed. Commit: %s", status["lastCommit"])

	// Verify the demo-flags.goff.yaml file was synced
	syncedFilePath := filepath.Join(tmpDir, "demo-flags.goff.yaml")
	_, err = os.Stat(syncedFilePath)
	require.NoError(t, err, "demo-flags.goff.yaml should exist in target directory")

	// Read and parse the YAML file
	fileContent, err := os.ReadFile(syncedFilePath)
	require.NoError(t, err, "Should be able to read demo-flags.goff.yaml")

	var flagConfig FeatureFlagConfig
	err = yaml.Unmarshal(fileContent, &flagConfig)
	require.NoError(t, err, "Should be able to parse YAML")

	// Validate expected values
	t.Run("ValidatePercentageValues", func(t *testing.T) {
		percentages := flagConfig.ColorBox.DefaultRule.Percentage

		assert.Equal(t, 5, percentages["green_var"], "green_var should be 5")
		assert.Equal(t, 10, percentages["red_var"], "red_var should be 10")
		assert.Equal(t, 35, percentages["default_var"], "default_var should be 35")

		t.Logf("Percentage values: green=%d, red=%d, default=%d",
			percentages["green_var"],
			percentages["red_var"],
			percentages["default_var"])
	})

	t.Run("ValidateDisableFlag", func(t *testing.T) {
		assert.False(t, flagConfig.ColorBox.Disable, "disable should be false")
		t.Logf("Disable flag: %v", flagConfig.ColorBox.Disable)
	})

	t.Run("ValidateVariations", func(t *testing.T) {
		variations := flagConfig.ColorBox.Variations

		assert.NotEmpty(t, variations, "Should have variations defined")
		assert.Equal(t, "red", variations["red_var"], "red_var should map to 'red'")
		assert.Equal(t, "green", variations["green_var"], "green_var should map to 'green'")
		assert.Equal(t, "grey", variations["default_var"], "default_var should map to 'grey'")

		t.Logf("Found %d color variations", len(variations))
	})

	// Test that the file content matches expected structure
	t.Run("ValidateFileContent", func(t *testing.T) {
		fileStr := string(fileContent)

		assert.Contains(t, fileStr, "color-box:", "File should contain color-box key")
		assert.Contains(t, fileStr, "variations:", "File should contain variations section")
		assert.Contains(t, fileStr, "defaultRule:", "File should contain defaultRule section")
		assert.Contains(t, fileStr, "percentage:", "File should contain percentage section")
		assert.Contains(t, fileStr, "green_var: 5", "File should contain green_var: 5")
		assert.Contains(t, fileStr, "red_var: 10", "File should contain red_var: 10")
		assert.Contains(t, fileStr, "default_var: 35", "File should contain default_var: 35")
		assert.Contains(t, fileStr, "disable: false", "File should contain disable: false")
	})
}

// TestE2E_SyncSpecificFile tests syncing a single file (README.md)
func TestE2E_SyncSpecificFile(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping E2E test in short mode")
	}

	tmpDir, err := os.MkdirTemp("", "git-sync-readme-*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	cfg := &config.Config{
		RepoURL:      "https://github.com/davidaparicio/microsvcs.git",
		Branch:       "main",
		SourcePath:   "/README.md",
		TargetPath:   tmpDir,
		SyncInterval: "*/5 * * * *",
		Port:         "8080",
	}

	syncer, err := sync.NewSyncer(cfg)
	require.NoError(t, err)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	t.Log("Syncing README.md...")
	err = syncer.Sync(ctx)
	require.NoError(t, err)

	// Verify README.md exists
	readmePath := filepath.Join(tmpDir, "README.md")
	content, err := os.ReadFile(readmePath)
	require.NoError(t, err, "README.md should exist")

	// Verify it's actually the microsvcs README
	readmeContent := string(content)
	assert.Contains(t, readmeContent, "microsvcs", "README should mention microsvcs")

	t.Logf("Successfully synced README.md (%d bytes)", len(content))
}

// TestE2E_MultipleSyncs tests that multiple syncs work correctly
func TestE2E_MultipleSyncs(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping E2E test in short mode")
	}

	tmpDir, err := os.MkdirTemp("", "git-sync-multi-*")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	cfg := &config.Config{
		RepoURL:      "https://github.com/davidaparicio/microsvcs.git",
		Branch:       "main",
		SourcePath:   "/color",
		TargetPath:   tmpDir,
		SyncInterval: "*/5 * * * *",
		Port:         "8080",
	}

	syncer, err := sync.NewSyncer(cfg)
	require.NoError(t, err)

	ctx := context.Background()

	// First sync
	t.Log("Performing first sync...")
	err = syncer.Sync(ctx)
	require.NoError(t, err)

	status1 := syncer.GetStatus()
	commit1 := status1["lastCommit"].(string)

	// Second sync (should pull, but might be already up-to-date)
	t.Log("Performing second sync...")
	err = syncer.Sync(ctx)
	require.NoError(t, err)

	status2 := syncer.GetStatus()
	commit2 := status2["lastCommit"].(string)
	syncCount := status2["syncCount"].(int64)

	// Verify both syncs completed
	assert.Equal(t, int64(2), syncCount, "Should have synced twice")
	assert.Equal(t, commit1, commit2, "Commits should be the same (repo hasn't changed)")
	assert.True(t, syncer.IsHealthy(), "Should remain healthy after multiple syncs")

	t.Logf("Completed %d syncs successfully", syncCount)
}

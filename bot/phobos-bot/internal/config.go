package internal

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type ConfigYAMLTopLevel struct {
	Bot ConfigYAMLForUnmarshaling `yaml:"bot"`
}

type ConfigYAMLForUnmarshaling struct {
	DatabasePath string `yaml:"database_path"`
}

func GetConfig() (BotConfig, error) {
	// First try to get config path from environment variable
	envConfigPath := os.Getenv("CONFIG_FILE_PATH")
	if envConfigPath != "" {
		return readConfigFile(envConfigPath)
	}

	// Get the executable path and look for config file next to the executable
	execPath, err := os.Executable()
	if err != nil {
		return BotConfig{}, fmt.Errorf("failed to get executable path: %w", err)
	}

	execDir := filepath.Dir(execPath)
	configPath := filepath.Join(execDir, "config.yaml")
	return readConfigFile(configPath)
}

func readConfigFile(configPath string) (BotConfig, error) {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return BotConfig{}, err
	}

	var yamlConfig ConfigYAMLTopLevel
	if err := yaml.Unmarshal(data, &yamlConfig); err != nil {
		return BotConfig{}, err
	}

	// Only read database path from config file as it's essential to locate the database
	config := BotConfig{
		DatabasePath: yamlConfig.Bot.DatabasePath,
	}

	// Apply environment variables for essential parameters
	applyEnvOverrides(&config)

	return config, nil
}

func applyEnvOverrides(config *BotConfig) {
	// Database path can be overridden via environment variable
	if envDatabasePath := os.Getenv("DATABASE_PATH"); envDatabasePath != "" {
		config.DatabasePath = envDatabasePath
	}

	// Also allow token to be provided via environment for initial setup
	if envToken := os.Getenv("TELEGRAM_BOT_TOKEN"); envToken != "" {
		config.Token = envToken
	}
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func (c BotConfig) GetClientAddScriptPath() string {
	return c.ScriptsDir + "/vps-client-add.sh"
}

func (c BotConfig) GetClientRemoveScriptPath() string {
	return c.ScriptsDir + "/vps-client-remove.sh"
}
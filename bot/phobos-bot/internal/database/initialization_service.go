package database

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"phobos-bot/internal"
)

type InitializationService struct {
	dbManager *DBManager
}

func NewInitializationService(dbManager *DBManager) *InitializationService {
	return &InitializationService{
		dbManager: dbManager,
	}
}

func (is *InitializationService) InitializeDatabase(messagesFile string, defaultConfigs map[string]interface{}) error {
	// Verify schema exists and is correct version
	if err := is.dbManager.InitializeSchema(); err != nil {
		return fmt.Errorf("database schema check failed: %w", err)
	}

	// Do not load default message templates since they should already exist in the database
	// The database is expected to contain all required data

	// Set default configuration values if provided and they don't already exist
	if defaultConfigs != nil {
		configRepo := NewConfigRepository(is.dbManager.GetDB())
		for key, value := range defaultConfigs {
			// Check if the config key already exists in the database
			exists, err := configRepo.ConfigExists(key)
			if err != nil {
				return fmt.Errorf("failed to check config existence %s: %w", key, err)
			}
			if !exists {
				// Config doesn't exist, so we can safely set the default
				var err error
				switch v := value.(type) {
				case string:
					err = configRepo.SetString(key, v, "")
				case int:
					err = configRepo.SetInt(key, v, "")
				case bool:
					err = configRepo.SetBool(key, v, "")
				case float64: // JSON numbers are float64
					err = configRepo.SetInt(key, int(v), "")
				default:
					err = configRepo.SetString(key, fmt.Sprintf("%v", v), "")
				}
				if err != nil {
					return fmt.Errorf("failed to set default config %s: %w", key, err)
				}
			}
		}

		// Update descriptions for specific configuration options by setting them again with the proper description
		if _, ok := defaultConfigs["health_server_enabled"]; ok {
			if err := configRepo.SetBool("health_server_enabled", defaultConfigs["health_server_enabled"].(bool), "Controls whether the health server is enabled. When enabled, provides HTTP endpoints at /health and /metrics for monitoring bot status and metrics."); err != nil {
				return fmt.Errorf("failed to set health_server_enabled with description: %w", err)
			}
		}

		if _, ok := defaultConfigs["health_server_port"]; ok {
			if err := configRepo.SetInt("health_server_port", defaultConfigs["health_server_port"].(int), "Port number for the health server HTTP endpoints. Default is 8080 with endpoints at /health and /metrics"); err != nil {
				return fmt.Errorf("failed to set health_server_port with description: %w", err)
			}
		}
	}

	return nil
}

// loadDefaultMessages loads default message templates from a JSON file into the database
func (is *InitializationService) loadDefaultMessages(messagesFile string) error {
	// Read the messages file
	file, err := os.Open(messagesFile)
	if err != nil {
		return fmt.Errorf("failed to open messages file: %w", err)
	}
	defer file.Close()

	bytes, err := io.ReadAll(file)
	if err != nil {
		return fmt.Errorf("failed to read messages file: %w", err)
	}

	var messages map[string]string
	if err := json.Unmarshal(bytes, &messages); err != nil {
		return fmt.Errorf("failed to parse messages file: %w", err)
	}

	// Save messages to database using the message template repository
	templateRepo := NewMessageTemplateRepository(is.dbManager.GetDB())
	for key, text := range messages {
		if err := templateRepo.UpdateMessage(key, text); err != nil {
			return fmt.Errorf("failed to save message template %s: %w", key, err)
		}
	}

	return nil
}


// CreateAdminUser creates an admin user with the provided user ID
func (is *InitializationService) CreateAdminUser(userID int64) error {
	userRepo := NewUserRepository(is.dbManager.GetDB())

	// Register the user with basic level first
	if err := userRepo.RegisterUser(userID, ""); err != nil {
		return fmt.Errorf("failed to register admin user: %w", err)
	}

	if err := userRepo.UpdateUserLevel(userID, internal.Admin); err != nil {
		return fmt.Errorf("failed to set admin level: %w", err)
	}

	return nil
}
package database

import (
	"database/sql"
	"fmt"
	"strconv"
	"time"

	"phobos-bot/internal"
)

type ConfigRepository struct {
	db *sql.DB
}

func NewConfigRepository(db *sql.DB) *ConfigRepository {
	return &ConfigRepository{
		db: db,
	}
}

func (cr *ConfigRepository) ConfigExists(key string) (bool, error) {
	err := cr.db.QueryRow(`
		SELECT 1
		FROM configuration
		WHERE config_key = ?
		LIMIT 1
	`, key).Scan(new(int))

	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("failed to check config existence: %w", err)
	}

	return true, nil
}

func (cr *ConfigRepository) GetString(key string) (string, error) {
	var value string
	err := cr.db.QueryRow(`
		SELECT config_value
		FROM configuration
		WHERE config_key = ?
	`, key).Scan(&value)

	if err != nil {
		if err == sql.ErrNoRows {
			return "", fmt.Errorf("config key not found: %w", err)
		}
		return "", fmt.Errorf("failed to get config value: %w", err)
	}

	return value, nil
}

func (cr *ConfigRepository) GetInt(key string) (int, error) {
	var value string
	err := cr.db.QueryRow(`
		SELECT config_value
		FROM configuration
		WHERE config_key = ?
	`, key).Scan(&value)
	
	if err != nil {
		if err == sql.ErrNoRows {
			return 0, fmt.Errorf("config key not found: %w", err)
		}
		return 0, fmt.Errorf("failed to get config value: %w", err)
	}

	intVal, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("failed to convert config value to int: %w", err)
	}

	return intVal, nil
}

func (cr *ConfigRepository) GetBool(key string) (bool, error) {
	var value string
	err := cr.db.QueryRow(`
		SELECT config_value
		FROM configuration
		WHERE config_key = ?
	`, key).Scan(&value)
	
	if err != nil {
		if err == sql.ErrNoRows {
			return false, fmt.Errorf("config key not found: %w", err)
		}
		return false, fmt.Errorf("failed to get config value: %w", err)
	}

	boolVal, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("failed to convert config value to bool: %w", err)
	}

	return boolVal, nil
}

func (cr *ConfigRepository) GetDuration(key string) (time.Duration, error) {
	var value string
	err := cr.db.QueryRow(`
		SELECT config_value
		FROM configuration
		WHERE config_key = ?
	`, key).Scan(&value)
	
	if err != nil {
		if err == sql.ErrNoRows {
			return 0, fmt.Errorf("config key not found: %w", err)
		}
		return 0, fmt.Errorf("failed to get config value: %w", err)
	}

	duration, err := time.ParseDuration(value)
	if err != nil {
		return 0, fmt.Errorf("failed to parse duration: %w", err)
	}

	return duration, nil
}

func (cr *ConfigRepository) SetString(key, value, description string) error {
	_, err := cr.db.Exec(`
		INSERT OR REPLACE INTO configuration 
		(config_key, config_value, data_type, description, updated_at) 
		VALUES (?, ?, 'string', ?, CURRENT_TIMESTAMP)
	`, key, value, description)
	
	if err != nil {
		return fmt.Errorf("failed to set string config: %w", err)
	}

	return nil
}

func (cr *ConfigRepository) SetInt(key string, value int, description string) error {
	_, err := cr.db.Exec(`
		INSERT OR REPLACE INTO configuration 
		(config_key, config_value, data_type, description, updated_at) 
		VALUES (?, ?, 'int', ?, CURRENT_TIMESTAMP)
	`, key, strconv.Itoa(value), description)
	
	if err != nil {
		return fmt.Errorf("failed to set int config: %w", err)
	}

	return nil
}

func (cr *ConfigRepository) SetBool(key string, value bool, description string) error {
	_, err := cr.db.Exec(`
		INSERT OR REPLACE INTO configuration 
		(config_key, config_value, data_type, description, updated_at) 
		VALUES (?, ?, 'bool', ?, CURRENT_TIMESTAMP)
	`, key, strconv.FormatBool(value), description)
	
	if err != nil {
		return fmt.Errorf("failed to set bool config: %w", err)
	}

	return nil
}

func (cr *ConfigRepository) SetDuration(key string, value time.Duration, description string) error {
	_, err := cr.db.Exec(`
		INSERT OR REPLACE INTO configuration 
		(config_key, config_value, data_type, description, updated_at) 
		VALUES (?, ?, 'duration', ?, CURRENT_TIMESTAMP)
	`, key, value.String(), description)
	
	if err != nil {
		return fmt.Errorf("failed to set duration config: %w", err)
	}

	return nil
}

func (cr *ConfigRepository) GetConfig(key string) (*internal.ConfigValue, error) {
	row := cr.db.QueryRow(`
		SELECT config_key, config_value, data_type, description, updated_at
		FROM configuration
		WHERE config_key = ?
	`, key)

	var configValue internal.ConfigValue
	var updatedAt time.Time
	
	err := row.Scan(&configValue.Key, &configValue.Value, &configValue.Type, &configValue.Description, &updatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("config key not found: %w", err)
		}
		return nil, fmt.Errorf("failed to get config: %w", err)
	}
	configValue.UpdatedAt = updatedAt

	return &configValue, nil
}

func (cr *ConfigRepository) GetAllConfigs() (map[string]*internal.ConfigValue, error) {
	rows, err := cr.db.Query(`
		SELECT config_key, config_value, data_type, description, updated_at
		FROM configuration
		ORDER BY config_key
	`)
	
	if err != nil {
		return nil, fmt.Errorf("failed to get all configs: %w", err)
	}
	defer rows.Close()

	configs := make(map[string]*internal.ConfigValue)
	for rows.Next() {
		var configValue internal.ConfigValue
		var updatedAt time.Time
		
		err := rows.Scan(&configValue.Key, &configValue.Value, &configValue.Type, &configValue.Description, &updatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan config: %w", err)
		}
		configValue.UpdatedAt = updatedAt

		configs[configValue.Key] = &configValue
	}

	return configs, nil
}

func (cr *ConfigRepository) DeleteConfig(key string) error {
	_, err := cr.db.Exec(`
		DELETE FROM configuration
		WHERE config_key = ?
	`, key)

	if err != nil {
		return fmt.Errorf("failed to delete config: %w", err)
	}

	return nil
}

func (cr *ConfigRepository) retryOperation(operation func() error, maxRetries int) error {
	var err error
	for attempt := 0; attempt <= maxRetries; attempt++ {
		err = operation()
		if err == nil {
			return nil
		}

		if attempt < maxRetries {
			waitTime := time.Duration(1<<uint(attempt)) * time.Second
			time.Sleep(waitTime)
		}
	}
	return err
}

func (cr *ConfigRepository) GetStringWithRetry(key string, maxRetries int) (string, error) {
	var value string
	var finalErr error

	err := cr.retryOperation(func() error {
		queryErr := cr.db.QueryRow(`
			SELECT config_value
			FROM configuration
			WHERE config_key = ?
		`, key).Scan(&value)

		if queryErr != nil {
			if queryErr == sql.ErrNoRows {
				finalErr = fmt.Errorf("config key not found: %w", queryErr)
				return nil
			}
			return queryErr
		}
		return nil
	}, maxRetries)

	if err != nil {
		return "", fmt.Errorf("failed to get config value after retries: %w", err)
	}

	if finalErr != nil {
		return "", finalErr
	}

	return value, nil
}

func (cr *ConfigRepository) GetIntWithRetry(key string, maxRetries int) (int, error) {
	var value string
	var finalErr error

	err := cr.retryOperation(func() error {
		queryErr := cr.db.QueryRow(`
			SELECT config_value
			FROM configuration
			WHERE config_key = ?
		`, key).Scan(&value)

		if queryErr != nil {
			if queryErr == sql.ErrNoRows {
				finalErr = fmt.Errorf("config key not found: %w", queryErr)
				return nil
			}
			return queryErr
		}
		return nil
	}, maxRetries)

	if err != nil {
		return 0, fmt.Errorf("failed to get config value after retries: %w", err)
	}

	if finalErr != nil {
		return 0, finalErr
	}

	intVal, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("failed to convert config value to int: %w", err)
	}

	return intVal, nil
}

func (cr *ConfigRepository) GetBoolWithRetry(key string, maxRetries int) (bool, error) {
	var value string
	var finalErr error

	err := cr.retryOperation(func() error {
		queryErr := cr.db.QueryRow(`
			SELECT config_value
			FROM configuration
			WHERE config_key = ?
		`, key).Scan(&value)

		if queryErr != nil {
			if queryErr == sql.ErrNoRows {
				finalErr = fmt.Errorf("config key not found: %w", queryErr)
				return nil
			}
			return queryErr
		}
		return nil
	}, maxRetries)

	if err != nil {
		return false, fmt.Errorf("failed to get config value after retries: %w", err)
	}

	if finalErr != nil {
		return false, finalErr
	}

	boolVal, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("failed to convert config value to bool: %w", err)
	}

	return boolVal, nil
}

func (cr *ConfigRepository) GetStringOrDefault(key string, defaultValue string, isCritical bool) (string, error) {
	value, err := cr.GetStringWithRetry(key, 3)
	if err != nil {
		if isCritical {
			return "", fmt.Errorf("CRITICAL config %s failed: %w", key, err)
		}
		return defaultValue, nil
	}
	return value, nil
}

func (cr *ConfigRepository) GetIntOrDefault(key string, defaultValue int, isCritical bool) (int, error) {
	value, err := cr.GetIntWithRetry(key, 3)
	if err != nil {
		if isCritical {
			return 0, fmt.Errorf("CRITICAL config %s failed: %w", key, err)
		}
		return defaultValue, nil
	}
	return value, nil
}

func (cr *ConfigRepository) GetBoolOrDefault(key string, defaultValue bool, isCritical bool) (bool, error) {
	value, err := cr.GetBoolWithRetry(key, 3)
	if err != nil {
		if isCritical {
			return false, fmt.Errorf("CRITICAL config %s failed: %w", key, err)
		}
		return defaultValue, nil
	}
	return value, nil
}
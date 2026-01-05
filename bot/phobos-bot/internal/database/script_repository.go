package database

import (
	"database/sql"
	"fmt"
)

type Script struct {
	ScriptKey   string `json:"script_key"`
	ScriptName  string `json:"script_name"`
	Description string `json:"description"`
}

type ScriptRepository struct {
	db *sql.DB
}

func NewScriptRepository(db *sql.DB) *ScriptRepository {
	return &ScriptRepository{
		db: db,
	}
}

func (sr *ScriptRepository) GetScriptName(key string) (string, error) {
	var scriptName string
	err := sr.db.QueryRow(`
		SELECT script_name
		FROM scripts
		WHERE script_key = ?
	`, key).Scan(&scriptName)

	if err != nil {
		if err == sql.ErrNoRows {
			return "", fmt.Errorf("script not found: %s", key)
		}
		return "", fmt.Errorf("failed to get script name: %w", err)
	}

	return scriptName, nil
}

func (sr *ScriptRepository) SetScriptName(key, name, description string) error {
	_, err := sr.db.Exec(`
		INSERT INTO scripts (script_key, script_name, description, updated_at)
		VALUES (?, ?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(script_key) DO UPDATE SET
			script_name = excluded.script_name,
			description = excluded.description,
			updated_at = CURRENT_TIMESTAMP
	`, key, name, description)

	if err != nil {
		return fmt.Errorf("failed to set script name: %w", err)
	}

	return nil
}

func (sr *ScriptRepository) GetAllScripts() (map[string]interface{}, error) {
	rows, err := sr.db.Query(`
		SELECT script_key, script_name, description
		FROM scripts
		ORDER BY script_key
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to get all scripts: %w", err)
	}
	defer rows.Close()

	scripts := make(map[string]interface{})
	for rows.Next() {
		var script Script
		err := rows.Scan(&script.ScriptKey, &script.ScriptName, &script.Description)
		if err != nil {
			return nil, fmt.Errorf("failed to scan script: %w", err)
		}
		scripts[script.ScriptKey] = &script
	}

	return scripts, nil
}

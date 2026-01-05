package database

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"phobos-bot/internal"
)

type messageTemplateRepository struct {
	db *sql.DB
}

func NewMessageTemplateRepository(db *sql.DB) internal.MessageTemplateRepository {
	return &messageTemplateRepository{
		db: db,
	}
}

func (mtr *messageTemplateRepository) GetMessage(key string) (*internal.MessageTemplate, error) {
	row := mtr.db.QueryRow(`
		SELECT message_key, template_text, language_code, version, created_at, updated_at
		FROM message_templates
		WHERE message_key = ?
	`, key)

	var template internal.MessageTemplate
	var createdAt, updatedAt time.Time
	
	err := row.Scan(&template.MessageKey, &template.TemplateText, &template.LanguageCode, &template.Version, &createdAt, &updatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("message template not found: %w", err)
		}
		return nil, fmt.Errorf("failed to get message template: %w", err)
	}
	
	template.CreatedAt = createdAt
	template.UpdatedAt = updatedAt

	return &template, nil
}

func (mtr *messageTemplateRepository) UpdateMessage(key, text string) error {
	result, err := mtr.db.Exec(`
		INSERT OR REPLACE INTO message_templates 
		(message_key, template_text, updated_at) 
		VALUES (?, ?, CURRENT_TIMESTAMP)
	`, key, text)
	
	if err != nil {
		return fmt.Errorf("failed to update message template: %w", err)
	}
	
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}
	
	if rowsAffected == 0 {
		return fmt.Errorf("failed to update message template: no rows affected")
	}
	
	return nil
}

func (mtr *messageTemplateRepository) GetAllMessages() (map[string]*internal.MessageTemplate, error) {
	rows, err := mtr.db.Query(`
		SELECT message_key, template_text, language_code, version, created_at, updated_at
		FROM message_templates
		ORDER BY message_key
	`)
	
	if err != nil {
		return nil, fmt.Errorf("failed to get all message templates: %w", err)
	}
	defer rows.Close()

	messages := make(map[string]*internal.MessageTemplate)
	for rows.Next() {
		var template internal.MessageTemplate
		var createdAt, updatedAt time.Time
		
		err := rows.Scan(&template.MessageKey, &template.TemplateText, &template.LanguageCode, &template.Version, &createdAt, &updatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan message template: %w", err)
		}
		template.CreatedAt = createdAt
		template.UpdatedAt = updatedAt

		messages[template.MessageKey] = &template
	}

	return messages, nil
}

func (mtr *messageTemplateRepository) RenderTemplate(key string, data map[string]interface{}) (string, error) {
	template, err := mtr.GetMessage(key)
	if err != nil {
		return "", fmt.Errorf("failed to get message template for rendering: %w", err)
	}

	result := template.TemplateText

	for placeholder, value := range data {
		placeholderStr := fmt.Sprintf("{{%s}}", placeholder)
		result = strings.ReplaceAll(result, placeholderStr, fmt.Sprintf("%v", value))
	}

	return result, nil
}
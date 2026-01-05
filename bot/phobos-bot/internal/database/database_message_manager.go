package database

import (
	"phobos-bot/internal"
)

func NewDatabaseMessageManager(templateRepo internal.MessageTemplateRepository) *internal.DatabaseMessageManager {
	return &internal.DatabaseMessageManager{
		TemplateRepo: templateRepo,
	}
}


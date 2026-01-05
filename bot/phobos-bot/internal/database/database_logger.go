package database

import (
	"fmt"
	"sync"
	"time"

	"phobos-bot/internal"
)

type DatabaseLogger struct {
	logRepo *LogRepository
	mu      sync.Mutex
}

func NewDatabaseLogger(logRepo *LogRepository) *DatabaseLogger {
	return &DatabaseLogger{
		logRepo: logRepo,
	}
}

func (dl *DatabaseLogger) Log(event internal.LogEvent) {
	// Make a copy of the event to ensure timestamp is set correctly
	eventCopy := event
	if eventCopy.Timestamp.IsZero() {
		eventCopy.Timestamp = time.Now()
	}

	// Log to database in a goroutine to avoid blocking
	go func() {
		err := dl.logRepo.LogEvent(eventCopy)
		if err != nil {
			// If logging to DB fails, log error to stderr
			fmt.Printf("Failed to log event to database: %v\n", err)
		}
	}()
}

func (dl *DatabaseLogger) Close() {
	// Nothing to close for database logger
}
package database

import (
	"database/sql"
	"fmt"
	"strconv"
	"time"

	"phobos-bot/internal"
)

type LogRepository struct {
	db *sql.DB
}

func NewLogRepository(db *sql.DB) *LogRepository {
	return &LogRepository{
		db: db,
	}
}

func (lr *LogRepository) LogEvent(event internal.LogEvent) error {
	logLevel := event.LogLevel
	if logLevel == "" {
		logLevel = string(internal.LogLevelInfo)
	}

	_, err := lr.db.Exec(`
		INSERT INTO logs (user_id, client_name, command, script_exit_code, script_output, error, is_premium, user_level, log_level, timestamp)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, event.UserID, event.ClientName, event.Command, event.ScriptExitCode, event.ScriptOutput, event.Error, event.IsPremium, event.UserLevel, logLevel, event.Timestamp)

	if err != nil {
		return fmt.Errorf("failed to log event: %w", err)
	}

	return nil
}

func (lr *LogRepository) GetLogsByUser(userID int64, limit int, offset int) ([]internal.LogEvent, error) {
	query := `
		SELECT user_id, client_name, command, script_exit_code, script_output, error, is_premium, user_level, log_level, timestamp
		FROM logs
		WHERE user_id = ?
		ORDER BY timestamp DESC
		LIMIT ? OFFSET ?
	`

	rows, err := lr.db.Query(query, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to get logs by user: %w", err)
	}
	defer rows.Close()

	var logs []internal.LogEvent
	for rows.Next() {
		var logEvent internal.LogEvent
		var nullScriptOutput sql.NullString
		var nullError sql.NullString
		var nullUserLevel sql.NullString
		var nullLogLevel sql.NullString

		err := rows.Scan(
			&logEvent.UserID,
			&logEvent.ClientName,
			&logEvent.Command,
			&logEvent.ScriptExitCode,
			&nullScriptOutput,
			&nullError,
			&logEvent.IsPremium,
			&nullUserLevel,
			&nullLogLevel,
			&logEvent.Timestamp,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan log: %w", err)
		}

		if nullScriptOutput.Valid {
			logEvent.ScriptOutput = nullScriptOutput.String
		}
		if nullError.Valid {
			logEvent.Error = nullError.String
		}
		if nullUserLevel.Valid {
			logEvent.UserLevel = nullUserLevel.String
		}
		if nullLogLevel.Valid {
			logEvent.LogLevel = nullLogLevel.String
		}

		logs = append(logs, logEvent)
	}

	return logs, nil
}

func (lr *LogRepository) GetLogsByCommand(command string, limit int, offset int) ([]internal.LogEvent, error) {
	query := `
		SELECT user_id, client_name, command, script_exit_code, script_output, error, is_premium, user_level, log_level, timestamp
		FROM logs
		WHERE command = ?
		ORDER BY timestamp DESC
		LIMIT ? OFFSET ?
	`

	rows, err := lr.db.Query(query, command, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to get logs by command: %w", err)
	}
	defer rows.Close()

	var logs []internal.LogEvent
	for rows.Next() {
		var logEvent internal.LogEvent
		var nullScriptOutput sql.NullString
		var nullError sql.NullString
		var nullUserLevel sql.NullString
		var nullLogLevel sql.NullString

		err := rows.Scan(
			&logEvent.UserID,
			&logEvent.ClientName,
			&logEvent.Command,
			&logEvent.ScriptExitCode,
			&nullScriptOutput,
			&nullError,
			&logEvent.IsPremium,
			&nullUserLevel,
			&nullLogLevel,
			&logEvent.Timestamp,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan log: %w", err)
		}

		if nullScriptOutput.Valid {
			logEvent.ScriptOutput = nullScriptOutput.String
		}
		if nullError.Valid {
			logEvent.Error = nullError.String
		}
		if nullUserLevel.Valid {
			logEvent.UserLevel = nullUserLevel.String
		}
		if nullLogLevel.Valid {
			logEvent.LogLevel = nullLogLevel.String
		}

		logs = append(logs, logEvent)
	}

	return logs, nil
}

func (lr *LogRepository) GetLogsByTimeRange(start, end time.Time) ([]internal.LogEvent, error) {
	query := `
		SELECT user_id, client_name, command, script_exit_code, script_output, error, is_premium, user_level, log_level, timestamp
		FROM logs
		WHERE timestamp BETWEEN ? AND ?
		ORDER BY timestamp DESC
	`

	rows, err := lr.db.Query(query, start, end)
	if err != nil {
		return nil, fmt.Errorf("failed to get logs by time range: %w", err)
	}
	defer rows.Close()

	var logs []internal.LogEvent
	for rows.Next() {
		var logEvent internal.LogEvent
		var nullScriptOutput sql.NullString
		var nullError sql.NullString
		var nullUserLevel sql.NullString
		var nullLogLevel sql.NullString

		err := rows.Scan(
			&logEvent.UserID,
			&logEvent.ClientName,
			&logEvent.Command,
			&logEvent.ScriptExitCode,
			&nullScriptOutput,
			&nullError,
			&logEvent.IsPremium,
			&nullUserLevel,
			&nullLogLevel,
			&logEvent.Timestamp,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan log: %w", err)
		}

		if nullScriptOutput.Valid {
			logEvent.ScriptOutput = nullScriptOutput.String
		}
		if nullError.Valid {
			logEvent.Error = nullError.String
		}
		if nullUserLevel.Valid {
			logEvent.UserLevel = nullUserLevel.String
		}
		if nullLogLevel.Valid {
			logEvent.LogLevel = nullLogLevel.String
		}

		logs = append(logs, logEvent)
	}

	return logs, nil
}

func (lr *LogRepository) CleanupOldLogs(before time.Time) error {
	_, err := lr.db.Exec(`
		DELETE FROM logs
		WHERE timestamp < ?
	`, before)

	if err != nil {
		return fmt.Errorf("failed to clean up old logs: %w", err)
	}

	return nil
}

func (lr *LogRepository) GetRecentLogs(limit int, userFilter string) ([]internal.LogEvent, error) {
	var query string
	var args []interface{}

	if userFilter != "" {
		query = `
			SELECT user_id, client_name, command, script_exit_code, script_output, error, is_premium, user_level, log_level, timestamp
			FROM logs
			WHERE user_id = ? OR username = ?
			ORDER BY timestamp DESC
			LIMIT ?
		`
		userID, err := strconv.ParseInt(userFilter, 10, 64)
		if err != nil {
			args = []interface{}{0, userFilter, limit}
		} else {
			args = []interface{}{userID, userFilter, limit}
		}
	} else {
		query = `
			SELECT user_id, client_name, command, script_exit_code, script_output, error, is_premium, user_level, log_level, timestamp
			FROM logs
			ORDER BY timestamp DESC
			LIMIT ?
		`
		args = []interface{}{limit}
	}

	rows, err := lr.db.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to get recent logs: %w", err)
	}
	defer rows.Close()

	var logs []internal.LogEvent
	for rows.Next() {
		var logEvent internal.LogEvent
		var userLevel sql.NullString
		var clientName sql.NullString
		var scriptExitCode sql.NullInt64
		var scriptOutput sql.NullString
		var errorMsg sql.NullString

		err := rows.Scan(&logEvent.UserID, &clientName, &logEvent.Command, &scriptExitCode, &scriptOutput, &errorMsg, &logEvent.IsPremium, &userLevel, &logEvent.Timestamp)
		if err != nil {
			return nil, fmt.Errorf("failed to scan log: %w", err)
		}

		if clientName.Valid {
			logEvent.ClientName = clientName.String
		}
		if scriptExitCode.Valid {
			logEvent.ScriptExitCode = int(scriptExitCode.Int64)
		}
		if scriptOutput.Valid {
			logEvent.ScriptOutput = scriptOutput.String
		}
		if errorMsg.Valid {
			logEvent.Error = errorMsg.String
		}
		if userLevel.Valid {
			logEvent.UserLevel = userLevel.String
		}

		logs = append(logs, logEvent)
	}

	return logs, nil
}

func (lr *LogRepository) DeleteLogsOlderThan(before time.Time) (int, error) {
	result, err := lr.db.Exec(`
		DELETE FROM logs
		WHERE timestamp < ?
	`, before)

	if err != nil {
		return 0, fmt.Errorf("failed to delete old logs: %w", err)
	}

	count, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("failed to get rows affected: %w", err)
	}

	return int(count), nil
}
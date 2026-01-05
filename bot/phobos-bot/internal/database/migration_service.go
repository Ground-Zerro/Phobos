package database

import (
	"database/sql"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type Migration struct {
	Version     int
	Description string
	SQL         string
	AppliedAt   *time.Time
}

type MigrationService struct {
	db             *sql.DB
	migrationsPath string
}

func NewMigrationService(db *sql.DB, migrationsPath string) *MigrationService {
	return &MigrationService{
		db:             db,
		migrationsPath: migrationsPath,
	}
}

func (ms *MigrationService) InitializeMigrationsTable() error {
	_, err := ms.db.Exec(`
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version INTEGER PRIMARY KEY,
			description TEXT NOT NULL,
			applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		)
	`)
	if err != nil {
		return fmt.Errorf("failed to create schema_migrations table: %w", err)
	}
	return nil
}

func (ms *MigrationService) GetAppliedMigrations() (map[int]*Migration, error) {
	rows, err := ms.db.Query(`
		SELECT version, description, applied_at
		FROM schema_migrations
		ORDER BY version
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to query applied migrations: %w", err)
	}
	defer rows.Close()

	applied := make(map[int]*Migration)
	for rows.Next() {
		var m Migration
		err := rows.Scan(&m.Version, &m.Description, &m.AppliedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan migration: %w", err)
		}
		applied[m.Version] = &m
	}

	return applied, nil
}

func (ms *MigrationService) GetAvailableMigrations() ([]*Migration, error) {
	files, err := os.ReadDir(ms.migrationsPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read migrations directory: %w", err)
	}

	var migrations []*Migration
	for _, file := range files {
		if file.IsDir() || !strings.HasSuffix(file.Name(), ".sql") {
			continue
		}

		migration, err := ms.parseMigrationFile(filepath.Join(ms.migrationsPath, file.Name()))
		if err != nil {
			return nil, fmt.Errorf("failed to parse migration %s: %w", file.Name(), err)
		}

		migrations = append(migrations, migration)
	}

	sort.Slice(migrations, func(i, j int) bool {
		return migrations[i].Version < migrations[j].Version
	})

	return migrations, nil
}

func (ms *MigrationService) parseMigrationFile(path string) (*Migration, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	content, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}

	filename := filepath.Base(path)
	var version int
	var description string

	parts := strings.SplitN(filename, "_", 2)
	if len(parts) < 2 {
		return nil, fmt.Errorf("invalid migration filename format: %s", filename)
	}

	_, err = fmt.Sscanf(parts[0], "%d", &version)
	if err != nil {
		return nil, fmt.Errorf("invalid version number in filename: %s", filename)
	}

	description = strings.TrimSuffix(parts[1], ".sql")
	description = strings.ReplaceAll(description, "_", " ")

	sqlContent := string(content)
	upSQL := ms.extractUpMigration(sqlContent)

	return &Migration{
		Version:     version,
		Description: description,
		SQL:         upSQL,
	}, nil
}

func (ms *MigrationService) extractUpMigration(content string) string {
	lines := strings.Split(content, "\n")
	var upSQL []string
	inUpSection := false
	inDownSection := false

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)

		if strings.HasPrefix(trimmed, "-- UP Migration") {
			inUpSection = true
			inDownSection = false
			continue
		}

		if strings.HasPrefix(trimmed, "-- DOWN Migration") {
			inUpSection = false
			inDownSection = true
			continue
		}

		if inDownSection {
			continue
		}

		if !inUpSection && !strings.HasPrefix(trimmed, "--") && trimmed != "" {
			inUpSection = true
		}

		if inUpSection && !strings.HasPrefix(trimmed, "-- DOWN") {
			upSQL = append(upSQL, line)
		}
	}

	return strings.TrimSpace(strings.Join(upSQL, "\n"))
}

func (ms *MigrationService) RunPendingMigrations() (int, error) {
	if err := ms.InitializeMigrationsTable(); err != nil {
		return 0, err
	}

	applied, err := ms.GetAppliedMigrations()
	if err != nil {
		return 0, err
	}

	available, err := ms.GetAvailableMigrations()
	if err != nil {
		return 0, err
	}

	count := 0
	for _, migration := range available {
		if _, exists := applied[migration.Version]; exists {
			continue
		}

		if err := ms.runMigration(migration); err != nil {
			return count, fmt.Errorf("failed to run migration %d: %w", migration.Version, err)
		}

		count++
	}

	return count, nil
}

func (ms *MigrationService) runMigration(migration *Migration) error {
	tx, err := ms.db.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	_, err = tx.Exec(migration.SQL)
	if err != nil {
		return fmt.Errorf("failed to execute migration SQL: %w", err)
	}

	_, err = tx.Exec(`
		INSERT INTO schema_migrations (version, description, applied_at)
		VALUES (?, ?, CURRENT_TIMESTAMP)
	`, migration.Version, migration.Description)
	if err != nil {
		return fmt.Errorf("failed to record migration: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

func (ms *MigrationService) GetMigrationStatus() ([]*Migration, error) {
	applied, err := ms.GetAppliedMigrations()
	if err != nil {
		return nil, err
	}

	available, err := ms.GetAvailableMigrations()
	if err != nil {
		return nil, err
	}

	var status []*Migration
	for _, migration := range available {
		if appliedMigration, exists := applied[migration.Version]; exists {
			migration.AppliedAt = appliedMigration.AppliedAt
		}
		status = append(status, migration)
	}

	return status, nil
}

func (ms *MigrationService) GetCurrentVersion() (int, error) {
	var version sql.NullInt64
	err := ms.db.QueryRow(`
		SELECT MAX(version)
		FROM schema_migrations
	`).Scan(&version)

	if err != nil {
		return 0, fmt.Errorf("failed to get current version: %w", err)
	}

	if !version.Valid {
		return 0, nil
	}

	return int(version.Int64), nil
}

package database

import (
	"database/sql"
	_ "embed"
	"fmt"
	"os"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

//go:embed schema.sql
var schemaSQL string

type DBManager struct {
	db *sql.DB
}



func NewDBManager(databasePath string) (*DBManager, error) {
	// Check if the database file exists
	if _, err := os.Stat(databasePath); os.IsNotExist(err) {
		return nil, fmt.Errorf("database file does not exist: %s", databasePath)
	}

	db, err := sql.Open("sqlite3", databasePath+"?_busy_timeout=10000&_journal_mode=WAL")
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	dbm := &DBManager{
		db: db,
	}

	// Set connection pool settings
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Test database connection
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return dbm, nil
}

func (dbm *DBManager) InitializeSchema() error {
	// Check if the configuration table exists by trying to query it
	var schemaVersion int
	err := dbm.db.QueryRow("SELECT CAST(config_value AS INTEGER) FROM configuration WHERE config_key = 'schema_version'").Scan(&schemaVersion)

	if err != nil {
		return fmt.Errorf("schema is not properly initialized in the database. Please ensure the database contains the required tables and schema: %w", err)
	}

	if schemaVersion != 1 {
		return fmt.Errorf("unsupported schema version: %d, expected: 1", schemaVersion)
	}

	return nil
}

func (dbm *DBManager) Close() error {
	return dbm.db.Close()
}

func (dbm *DBManager) GetDB() *sql.DB {
	return dbm.db
}
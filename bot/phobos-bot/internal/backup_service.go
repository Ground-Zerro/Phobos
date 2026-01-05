package internal

import (
	"compress/gzip"
	"database/sql"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type BackupService struct {
	db              *sql.DB
	dbPath          string
	backupDir       string
	enabled         bool
	intervalHours   int
	retentionDays   int
	stopChan        chan struct{}
	logger          Logger
}

type BackupInfo struct {
	Filename  string
	Path      string
	Size      int64
	CreatedAt time.Time
}

func NewBackupService(db *sql.DB, dbPath string, backupDir string, enabled bool, intervalHours int, retentionDays int, logger Logger) *BackupService {
	return &BackupService{
		db:            db,
		dbPath:        dbPath,
		backupDir:     backupDir,
		enabled:       enabled,
		intervalHours: intervalHours,
		retentionDays: retentionDays,
		stopChan:      make(chan struct{}),
		logger:        logger,
	}
}

func (bs *BackupService) Start() error {
	if !bs.enabled {
		log.Println("Backup service is disabled")
		return nil
	}

	if err := os.MkdirAll(bs.backupDir, 0755); err != nil {
		return fmt.Errorf("failed to create backup directory: %w", err)
	}

	go bs.runBackupLoop()
	log.Printf("Backup service started (interval: %d hours, retention: %d days)", bs.intervalHours, bs.retentionDays)
	return nil
}

func (bs *BackupService) Stop() {
	close(bs.stopChan)
	log.Println("Backup service stopped")
}

func (bs *BackupService) runBackupLoop() {
	ticker := time.NewTicker(time.Duration(bs.intervalHours) * time.Hour)
	defer ticker.Stop()

	bs.CreateBackup()

	for {
		select {
		case <-ticker.C:
			bs.CreateBackup()
			bs.CleanupOldBackups()
		case <-bs.stopChan:
			return
		}
	}
}

func (bs *BackupService) CreateBackup() (string, error) {
	timestamp := time.Now().Format("2006-01-02-15-04-05")
	filename := fmt.Sprintf("phobos-bot-%s.db.gz", timestamp)
	backupPath := filepath.Join(bs.backupDir, filename)

	log.Printf("Creating backup: %s", filename)

	_, err := bs.db.Exec("PRAGMA wal_checkpoint(TRUNCATE)")
	if err != nil {
		bs.logger.Log(LogEvent{
			Command: "backup_create",
			Error:   fmt.Sprintf("WAL checkpoint failed: %v", err),
		})
	}

	sourceFile, err := os.Open(bs.dbPath)
	if err != nil {
		bs.logger.Log(LogEvent{
			Command: "backup_create",
			Error:   fmt.Sprintf("Failed to open source database: %v", err),
		})
		return "", fmt.Errorf("failed to open source database: %w", err)
	}
	defer sourceFile.Close()

	destFile, err := os.Create(backupPath)
	if err != nil {
		bs.logger.Log(LogEvent{
			Command: "backup_create",
			Error:   fmt.Sprintf("Failed to create backup file: %v", err),
		})
		return "", fmt.Errorf("failed to create backup file: %w", err)
	}
	defer destFile.Close()

	gzipWriter := gzip.NewWriter(destFile)
	defer gzipWriter.Close()

	_, err = io.Copy(gzipWriter, sourceFile)
	if err != nil {
		bs.logger.Log(LogEvent{
			Command: "backup_create",
			Error:   fmt.Sprintf("Failed to copy database: %v", err),
		})
		return "", fmt.Errorf("failed to copy database: %w", err)
	}

	if err := bs.verifyBackup(backupPath); err != nil {
		bs.logger.Log(LogEvent{
			Command: "backup_verify",
			Error:   fmt.Sprintf("Backup verification failed for %s: %v", filename, err),
		})
		os.Remove(backupPath)
		return "", fmt.Errorf("backup verification failed: %w", err)
	}

	fileInfo, _ := os.Stat(backupPath)
	bs.logger.Log(LogEvent{
		Command:      "backup_create",
		ScriptOutput: fmt.Sprintf("Backup created: %s (size: %d bytes)", filename, fileInfo.Size()),
	})

	log.Printf("Backup created successfully: %s", filename)
	return backupPath, nil
}

func (bs *BackupService) verifyBackup(backupPath string) error {
	tempFile, err := os.CreateTemp("", "verify-*.db")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	tempPath := tempFile.Name()
	tempFile.Close()
	defer os.Remove(tempPath)

	backupFile, err := os.Open(backupPath)
	if err != nil {
		return fmt.Errorf("failed to open backup file: %w", err)
	}
	defer backupFile.Close()

	gzipReader, err := gzip.NewReader(backupFile)
	if err != nil {
		return fmt.Errorf("failed to create gzip reader: %w", err)
	}
	defer gzipReader.Close()

	destFile, err := os.Create(tempPath)
	if err != nil {
		return fmt.Errorf("failed to create temp database: %w", err)
	}
	defer destFile.Close()

	_, err = io.Copy(destFile, gzipReader)
	if err != nil {
		return fmt.Errorf("failed to decompress backup: %w", err)
	}
	destFile.Close()

	testDB, err := sql.Open("sqlite3", tempPath)
	if err != nil {
		return fmt.Errorf("failed to open test database: %w", err)
	}
	defer testDB.Close()

	var count int
	err = testDB.QueryRow("SELECT COUNT(*) FROM sqlite_master WHERE type='table'").Scan(&count)
	if err != nil {
		return fmt.Errorf("failed to query test database: %w", err)
	}

	if count == 0 {
		return fmt.Errorf("backup database contains no tables")
	}

	return nil
}

func (bs *BackupService) CleanupOldBackups() error {
	backups, err := bs.ListBackups()
	if err != nil {
		return err
	}

	cutoffTime := time.Now().AddDate(0, 0, -bs.retentionDays)
	deletedCount := 0

	for _, backup := range backups {
		if backup.CreatedAt.Before(cutoffTime) {
			if err := os.Remove(backup.Path); err != nil {
				log.Printf("Failed to delete old backup %s: %v", backup.Filename, err)
				continue
			}
			deletedCount++
			log.Printf("Deleted old backup: %s", backup.Filename)
		}
	}

	if deletedCount > 0 {
		bs.logger.Log(LogEvent{
			Command:      "backup_cleanup",
			ScriptOutput: fmt.Sprintf("Deleted %d old backup(s)", deletedCount),
		})
	}

	return nil
}

func (bs *BackupService) ListBackups() ([]*BackupInfo, error) {
	entries, err := os.ReadDir(bs.backupDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read backup directory: %w", err)
	}

	var backups []*BackupInfo
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		if !strings.HasPrefix(entry.Name(), "phobos-bot-") || !strings.HasSuffix(entry.Name(), ".db.gz") {
			continue
		}

		fullPath := filepath.Join(bs.backupDir, entry.Name())
		info, err := os.Stat(fullPath)
		if err != nil {
			continue
		}

		backups = append(backups, &BackupInfo{
			Filename:  entry.Name(),
			Path:      fullPath,
			Size:      info.Size(),
			CreatedAt: info.ModTime(),
		})
	}

	sort.Slice(backups, func(i, j int) bool {
		return backups[i].CreatedAt.After(backups[j].CreatedAt)
	})

	return backups, nil
}

func (bs *BackupService) RestoreBackup(backupFilename string) error {
	backupPath := filepath.Join(bs.backupDir, backupFilename)

	if _, err := os.Stat(backupPath); os.IsNotExist(err) {
		return fmt.Errorf("backup file not found: %s", backupFilename)
	}

	tempFile, err := os.CreateTemp("", "restore-*.db")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	tempPath := tempFile.Name()
	tempFile.Close()
	defer os.Remove(tempPath)

	backupFile, err := os.Open(backupPath)
	if err != nil {
		return fmt.Errorf("failed to open backup file: %w", err)
	}
	defer backupFile.Close()

	gzipReader, err := gzip.NewReader(backupFile)
	if err != nil {
		return fmt.Errorf("failed to create gzip reader: %w", err)
	}
	defer gzipReader.Close()

	destFile, err := os.Create(tempPath)
	if err != nil {
		return fmt.Errorf("failed to create temp database: %w", err)
	}

	_, err = io.Copy(destFile, gzipReader)
	destFile.Close()
	if err != nil {
		return fmt.Errorf("failed to decompress backup: %w", err)
	}

	testDB, err := sql.Open("sqlite3", tempPath)
	if err != nil {
		return fmt.Errorf("failed to verify restored database: %w", err)
	}

	var count int
	err = testDB.QueryRow("SELECT COUNT(*) FROM sqlite_master WHERE type='table'").Scan(&count)
	testDB.Close()
	if err != nil {
		return fmt.Errorf("restored database verification failed: %w", err)
	}

	bs.db.Close()

	backupCurrentDB := bs.dbPath + ".before-restore-" + time.Now().Format("2006-01-02-15-04-05")
	if err := os.Rename(bs.dbPath, backupCurrentDB); err != nil {
		return fmt.Errorf("failed to backup current database: %w", err)
	}

	if err := os.Rename(tempPath, bs.dbPath); err != nil {
		os.Rename(backupCurrentDB, bs.dbPath)
		return fmt.Errorf("failed to restore database: %w", err)
	}

	bs.logger.Log(LogEvent{
		Command:      "backup_restore",
		ScriptOutput: fmt.Sprintf("Database restored from: %s", backupFilename),
	})

	log.Printf("Database restored from backup: %s", backupFilename)
	log.Println("Please restart the bot to use the restored database")

	return nil
}

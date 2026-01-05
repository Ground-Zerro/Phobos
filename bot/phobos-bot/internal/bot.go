package internal

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"text/template"
	"time"

	"github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

// Interfaces for database repositories
type UserRepository interface {
	RegisterUser(userID int64, username string) error
	GetUserByUserID(userID int64) (*User, error)
	GetUserByUsername(username string) (*User, error)
	UpdateUserLevel(userID int64, level UserLevel) error
	UpdateUserPremium(userID int64, expiresAt *time.Time, reason string) error
	IsPremium(userID int64) (bool, error)
	IsModerator(userID int64) (bool, error)
	IsAdmin(userID int64) (bool, error)
	UpdateUserActivity(userID int64) error
	SearchUsers(query string) ([]*User, error)
	MarkUserConfigDeleted(userID int64) error
	GetUsersWithDeletionMarker() ([]*User, error)
	HasPrivilege(userID int64, privilege UserLevel) (bool, error)
	CleanupExpiredPremium() (int, error)
	GetExpiredPremiumUsers() ([]*User, error)
	GetAllUsers() ([]*User, error)
	SetUserLevel(userID int64, level string) error
	SetPremiumStatus(userID int64, expiresAt *time.Time, reason string) error
	GetModeratorAndAdminUsers() ([]*User, error)
}

type LogRepository interface {
	LogEvent(event LogEvent) error
	GetRecentLogs(limit int, userFilter string) ([]LogEvent, error)
	DeleteLogsOlderThan(before time.Time) (int, error)
}

type FeedbackRepository interface {
	SaveFeedback(feedback Feedback) error
	GetFeedbackByUser(userID int64) ([]Feedback, error)
	GetAllFeedback(limit int, offset int) ([]Feedback, error)
	GetUnprocessedFeedback(limit int) ([]Feedback, error)
	GetFeedbackByID(feedbackID int64) (*Feedback, error)
	RespondToFeedback(feedbackID int64, response string, respondedBy int64) error
}


type BlocklistRepository interface {
	IsBlocked(userID int64, username string) (bool, error)
	AddToBlocklist(userID int64, username, reason string, blockedBy int64) error
	RemoveFromBlocklist(userID int64) error
}

type MessageTemplateRepository interface {
	GetMessage(key string) (*MessageTemplate, error)
	UpdateMessage(key, text string) error
	GetAllMessages() (map[string]*MessageTemplate, error)
	RenderTemplate(key string, data map[string]interface{}) (string, error)
}

type ConfigRepository interface {
	GetString(key string) (string, error)
	GetInt(key string) (int, error)
	GetBool(key string) (bool, error)
	GetDuration(key string) (time.Duration, error)
	SetString(key, value, description string) error
	SetInt(key string, value int, description string) error
	SetBool(key string, value bool, description string) error
	SetDuration(key string, value time.Duration, description string) error
	GetConfig(key string) (*ConfigValue, error)
	GetAllConfigs() (map[string]*ConfigValue, error)
	DeleteConfig(key string) error
}

type ScriptRepository interface {
	GetScriptName(key string) (string, error)
	SetScriptName(key, name, description string) error
	GetAllScripts() (map[string]interface{}, error)
}

// Add the ScriptRunner and WireGuardService implementations to the internal package
type DefaultScriptRunner struct {
	ClientAddScriptPath    string
	ClientRemoveScriptPath string
	Timeout                time.Duration
}

func (r *DefaultScriptRunner) RunScript(ctx context.Context, clientName string) (output string, exitCode int, err error) {
	ctx, cancel := context.WithTimeout(ctx, r.Timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, r.ClientAddScriptPath, clientName)

	bytes, err := cmd.CombinedOutput()
	output = string(bytes)

	if err != nil {
		exitCode = -1
		if exitError, ok := err.(*exec.ExitError); ok {
			exitCode = exitError.ExitCode()
		}
		return output, exitCode, err
	}

	return output, 0, nil
}

func (r *DefaultScriptRunner) RunRemoveScript(ctx context.Context, clientName string) (output string, exitCode int, err error) {
	ctx, cancel := context.WithTimeout(ctx, r.Timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, r.ClientRemoveScriptPath, clientName)

	bytes, err := cmd.CombinedOutput()
	output = string(bytes)

	if err != nil {
		exitCode = -1
		if exitError, ok := err.(*exec.ExitError); ok {
			exitCode = exitError.ExitCode()
		}
		return output, exitCode, err
	}

	return output, 0, nil
}



// BotConfig struct - all values except DatabasePath will be loaded from database after initialization
type BotConfig struct {
	Token                     string
	ScriptsDir                string
	DatabasePath              string
	ScriptTimeout             time.Duration
	ClientsDir                string
	WGInterface               string
	WatchdogEnabled           bool
	WatchdogCheckInterval     time.Duration
	WatchdogInactiveThreshold time.Duration
	MaxTestDuration           time.Duration
	RestrictNewUsers          bool  // Loaded from database after initialization
	MaxClients                int   // Loaded from database after initialization
	HealthServerEnabled       bool  // Loaded from database after initialization
	HealthServerPort          int   // Loaded from database after initialization
}

// User structure to match database
type User struct {
	UserID            int64     `json:"user_id"`
	Username          string    `json:"username"`
	UserLevel         string    `json:"user_level"`
	PremiumExpiresAt  *time.Time `json:"premium_expires_at"`
	PremiumReason     *string    `json:"premium_reason"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

// UserLevel type
type UserLevel string

const (
	Basic      UserLevel = "basic"
	Premium    UserLevel = "premium"
	Moderator  UserLevel = "moderator"
	Admin      UserLevel = "admin"
)

const (
	DeletedConfigMarkerTimestamp = 0
)

type LogLevel string

const (
	LogLevelNone    LogLevel = "NONE"
	LogLevelError   LogLevel = "ERROR"
	LogLevelWarning LogLevel = "WARNING"
	LogLevelInfo    LogLevel = "INFO"
	LogLevelDebug   LogLevel = "DEBUG"
	LogLevelTrace   LogLevel = "TRACE"
)

type LogEvent struct {
	Timestamp      time.Time `json:"timestamp"`
	UserID         int64     `json:"user_id"`
	Username       string    `json:"username"`
	ClientName     string    `json:"client_name"`
	Command        string    `json:"command"`
	ScriptExitCode int       `json:"script_exit_code"`
	ScriptOutput   string    `json:"script_output"`
	Error          string    `json:"error"`
	IsPremium      bool      `json:"is_premium"`
	UserLevel      string    `json:"user_level"`
	LogLevel       string    `json:"log_level"`
}

// Feedback structure (same as before)
type Feedback struct {
	ID          int64      `json:"id"`
	UserID      int64      `json:"user_id"`
	Username    string     `json:"username"`
	Message     string     `json:"message"`
	Processed   bool       `json:"processed"`
	Response    *string    `json:"response"`
	RespondedAt *time.Time `json:"responded_at"`
	RespondedBy *int64     `json:"responded_by"`
	Timestamp   time.Time  `json:"timestamp"`
}

// ClientActivity structure to match database
type ClientActivity struct {
	ClientName string    `json:"client_name"`
	UserID     int64     `json:"user_id"`
	LastSeen   time.Time `json:"last_seen"`
	FirstSeen  time.Time `json:"first_seen"`
}

type MessageTemplate struct {
	MessageKey    string    `json:"message_key"`
	TemplateText  string    `json:"template_text"`
	LanguageCode  string    `json:"language_code"`
	Version       int       `json:"version"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type ConfigValue struct {
	Key         string    `json:"config_key"`
	Value       string    `json:"config_value"`
	Type        string    `json:"data_type"`
	Description string    `json:"description"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// Logger interface (same as before)
type Logger interface {
	Log(event LogEvent)
	Close()
}

// ScriptRunner interface (same as before)
type ScriptRunner interface {
	RunScript(ctx context.Context, clientName string) (output string, exitCode int, err error)
	RunRemoveScript(ctx context.Context, clientName string) (output string, exitCode int, err error)
}

// WireGuardService interface (same as before)
type WireGuardStats struct {
	Status        string
	LastHandshake string
	Transfer      string
	Connected     bool
}

type WireGuardService interface {
	GetClientStats(clientName string) (*WireGuardStats, error)
	GetAllPeerStats() (map[string]*WireGuardStats, error)
}

// BotAPI interface (same as before)
type BotAPI interface {
	Send(interface{}) (tgbotapi.Message, error)
}

type BotAPIAdapter struct {
	*tgbotapi.BotAPI
}

func (a *BotAPIAdapter) Send(c interface{}) (tgbotapi.Message, error) {
	return a.BotAPI.Send(c.(tgbotapi.Chattable))
}

// Updated ClientWatchdog to use database repositories
type ClientWatchdog struct {
	config              BotConfig
	userRepo            UserRepository
	wgService           WireGuardService
	scriptRunner        ScriptRunner
	logger              Logger
	stopChan            chan struct{}
	wg                  sync.WaitGroup
}

type DefaultWireGuardService struct {
	ClientsDir  string
	WGInterface string
}

func (s *DefaultWireGuardService) GetClientStats(clientName string) (*WireGuardStats, error) {
	privateKey, err := s.readClientPrivateKey(clientName)
	if err != nil {
		return nil, err
	}
	publicKey, err := s.getPublicKeyFromPrivate(privateKey)
	if err != nil {
		return nil, err
	}
	wgOutput, err := s.getWireGuardOutput()
	if err != nil {
		return nil, err
	}
	return s.parsePeerStats(wgOutput, publicKey)
}

func (s *DefaultWireGuardService) GetAllPeerStats() (map[string]*WireGuardStats, error) {
	wgOutput, err := s.getWireGuardOutput()
	if err != nil {
		return nil, err
	}

	peerStats := make(map[string]*WireGuardStats)
	entries, err := os.ReadDir(s.ClientsDir)
	if err != nil {
		return nil, err
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		clientName := entry.Name()
		privateKey, err := s.readClientPrivateKey(clientName)
		if err != nil {
			continue
		}

		publicKey, err := s.getPublicKeyFromPrivate(privateKey)
		if err != nil {
			continue
		}

		stats, err := s.parsePeerStats(wgOutput, publicKey)
		if err != nil {
			continue
		}

		peerStats[clientName] = stats
	}

	return peerStats, nil
}

func (s *DefaultWireGuardService) readClientPrivateKey(clientName string) (string, error) {
	configPath := fmt.Sprintf("%s/%s/%s.conf", s.ClientsDir, clientName, clientName)
	data, err := os.ReadFile(configPath)
	if err != nil {
		return "", err
	}
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "PrivateKey") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				return strings.TrimSpace(parts[1]), nil
			}
		}
	}
	return "", fmt.Errorf("PrivateKey not found in config")
}

func (s *DefaultWireGuardService) getPublicKeyFromPrivate(privateKey string) (string, error) {
	cmd := exec.Command("wg", "pubkey")
	cmd.Stdin = strings.NewReader(privateKey)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(output)), nil
}

func (s *DefaultWireGuardService) getWireGuardOutput() (string, error) {
	cmd := exec.Command("wg", "show", s.WGInterface)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", err
	}
	return string(output), nil
}

func (s *DefaultWireGuardService) parsePeerStats(wgOutput, publicKey string) (*WireGuardStats, error) {
	lines := strings.Split(wgOutput, "\n")
	var inPeer bool
	var handshakeSeconds int64
	var rxBytes, txBytes int64
	var hasHandshake bool
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "peer:") {
			peerKey := strings.TrimSpace(strings.TrimPrefix(line, "peer:"))
			inPeer = (peerKey == publicKey)
			continue
		}
		if !inPeer {
			continue
		}
		if strings.HasPrefix(line, "peer:") || strings.HasPrefix(line, "interface:") {
			break
		}
		if strings.HasPrefix(line, "latest handshake:") {
			hasHandshake = true
			handshakeStr := strings.TrimSpace(strings.TrimPrefix(line, "latest handshake:"))
			handshakeSeconds = parseHandshake(handshakeStr)
		}
		if strings.HasPrefix(line, "transfer:") {
			transferStr := strings.TrimSpace(strings.TrimPrefix(line, "transfer:"))
			rxBytes, txBytes = parseTransfer(transferStr)
		}
	}
	if !hasHandshake {
		return &WireGuardStats{
			Status:        "never_connected",
			LastHandshake: "—",
			Transfer:      "—",
			Connected:     false,
		}, nil
	}
	status := "inactive"
	if handshakeSeconds < 180 {
		status = "active"
	}
	return &WireGuardStats{
		Status:        status,
		LastHandshake: formatHandshakeTime(handshakeSeconds),
		Transfer:      formatTransfer(rxBytes, txBytes),
		Connected:     true,
	}, nil
}

// DatabaseMessageManager for handling message templates from the database
type DatabaseMessageManager struct {
	TemplateRepo MessageTemplateRepository
}

func (dmm *DatabaseMessageManager) GetMessage(name string, data map[string]interface{}) (string, error) {
	messageTemplate, err := dmm.TemplateRepo.GetMessage(name)
	if err != nil {
		return "", fmt.Errorf("message template not found: %s, error: %w", name, err)
	}

	if data == nil || len(data) == 0 {
		return messageTemplate.TemplateText, nil
	}

	tmpl, err := template.New(name).Parse(messageTemplate.TemplateText)
	if err != nil {
		return "", fmt.Errorf("failed to parse template %s: %w", name, err)
	}

	var buf strings.Builder
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("failed to execute template %s: %w", name, err)
	}

	return buf.String(), nil
}

// Helper functions for WireGuard service
func parseHandshake(handshakeStr string) int64 {
	var totalSeconds int64
	parts := strings.Split(handshakeStr, ",")
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if strings.Contains(part, "day") {
			fields := strings.Fields(part)
			if len(fields) >= 1 {
				days, _ := strconv.ParseInt(fields[0], 10, 64)
				totalSeconds += days * 86400
			}
		} else if strings.Contains(part, "hour") {
			fields := strings.Fields(part)
			if len(fields) >= 1 {
				hours, _ := strconv.ParseInt(fields[0], 10, 64)
				totalSeconds += hours * 3600
			}
		} else if strings.Contains(part, "minute") {
			fields := strings.Fields(part)
			if len(fields) >= 1 {
				minutes, _ := strconv.ParseInt(fields[0], 10, 64)
				totalSeconds += minutes * 60
			}
		} else if strings.Contains(part, "second") {
			fields := strings.Fields(part)
			if len(fields) >= 1 {
				seconds, _ := strconv.ParseInt(fields[0], 10, 64)
				totalSeconds += seconds
			}
		}
	}
	return totalSeconds
}

func parseTransfer(transferStr string) (int64, int64) {
	parts := strings.Split(transferStr, ",")
	var rxBytes, txBytes int64
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if strings.Contains(part, "received") {
			rxBytes = parseBytes(part)
		} else if strings.Contains(part, "sent") {
			txBytes = parseBytes(part)
		}
	}
	return rxBytes, txBytes
}

func parseBytes(bytesStr string) int64 {
	fields := strings.Fields(bytesStr)
	if len(fields) < 2 {
		return 0
	}
	valueStr := fields[0]
	unit := fields[1]
	value, err := strconv.ParseFloat(valueStr, 64)
	if err != nil {
		return 0
	}
	switch unit {
	case "B":
		return int64(value)
	case "KiB":
		return int64(value * 1024)
	case "MiB":
		return int64(value * 1024 * 1024)
	case "GiB":
		return int64(value * 1024 * 1024 * 1024)
	case "TiB":
		return int64(value * 1024 * 1024 * 1024 * 1024)
	default:
		return 0
	}
}

func formatHandshakeTime(seconds int64) string {
	if seconds < 60 {
		return fmt.Sprintf("%d сек. назад", seconds)
	} else if seconds < 3600 {
		minutes := seconds / 60
		return fmt.Sprintf("%d мин. назад", minutes)
	} else if seconds < 86400 {
		hours := seconds / 3600
		return fmt.Sprintf("%d ч. назад", hours)
	} else {
		days := seconds / 86400
		return fmt.Sprintf("%d дн. назад", days)
	}
}

func formatBytes(bytes int64) string {
	if bytes < 1024 {
		return fmt.Sprintf("%d B", bytes)
	} else if bytes < 1024*1024 {
		return fmt.Sprintf("%.2f KB", float64(bytes)/1024)
	} else if bytes < 1024*1024*1024 {
		return fmt.Sprintf("%.2f MB", float64(bytes)/(1024*1024))
	} else {
		return fmt.Sprintf("%.2f GB", float64(bytes)/(1024*1024*1024))
	}
}

func formatTransfer(rxBytes, txBytes int64) string {
	if rxBytes == 0 && txBytes == 0 {
		return "—"
	}
	return fmt.Sprintf("↓ %s / ↑ %s", formatBytes(rxBytes), formatBytes(txBytes))
}

func NewClientWatchdog(
	config BotConfig,
	userRepo UserRepository,
	wgService WireGuardService,
	scriptRunner ScriptRunner,
	logger Logger,
) *ClientWatchdog {
	return &ClientWatchdog{
		config:       config,
		userRepo:     userRepo,
		wgService:    wgService,
		scriptRunner: scriptRunner,
		logger:       logger,
		stopChan:     make(chan struct{}),
	}
}

func (w *ClientWatchdog) Start() {
	w.wg.Add(1)
	go func() {
		defer w.wg.Done()
		ticker := time.NewTicker(w.config.WatchdogCheckInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				w.checkAndCleanup()
			case <-w.stopChan:
				return
			}
		}
	}()
}

func (w *ClientWatchdog) Stop() {
	close(w.stopChan)
	w.wg.Wait()
}

func (w *ClientWatchdog) checkAndCleanup() {
	startTime := time.Now()

	entries, err := os.ReadDir(w.config.ClientsDir)
	if err != nil {
		w.logger.Log(LogEvent{
			Timestamp: time.Now(),
			Command:   "watchdog_read_dir_error",
			Error:     err.Error(),
		})
		return
	}

	var clientNames []string
	for _, entry := range entries {
		if entry.IsDir() {
			clientNames = append(clientNames, strings.ToLower(entry.Name()))
		}
	}

	allPeerStats, err := w.wgService.GetAllPeerStats()
	if err != nil {
		w.logger.Log(LogEvent{
			Timestamp: time.Now(),
			Command:   "watchdog_get_all_stats_error",
			Error:     err.Error(),
		})
		allPeerStats = make(map[string]*WireGuardStats)
	}

	var toRemove []string
	for _, clientName := range clientNames {
		// Get user by username (first try exact match)
		user, err := w.userRepo.GetUserByUsername(clientName)
		if err != nil {
			// If exact match fails, we need to try a case-insensitive match
			// The repository doesn't support case-insensitive lookup, so we'll try other approaches
			// First, try to find user with a method that allows case-insensitive search
			users, searchErr := w.userRepo.SearchUsers(clientName) // This uses LIKE query which might help
			if searchErr != nil || len(users) == 0 {
				// If user not found by username, it means the client configuration exists
				// but there's no corresponding registered user in the database.
				// This typically happens when configs are created manually via admin scripts.
				// In this case, we create a user record with the client name as username
				// and NULL user_id to indicate no Telegram user is associated with this config.

				// Register the user in the database with NULL user_id (using 0 as the ID parameter)
				// This will create a user with the client name as username and NULL user_id
				registerErr := w.userRepo.RegisterUser(0, clientName)
				if registerErr != nil {
					w.logger.Log(LogEvent{
						Timestamp: time.Now(),
						Command:   "watchdog_register_user_error",
						Error:     registerErr.Error(),
						Username:  clientName,
						ClientName: clientName,
					})
					continue
				}

				// Get the user after registration to ensure we have the data
				user, err = w.userRepo.GetUserByUsername(clientName)
				if err != nil {
					w.logger.Log(LogEvent{
						Timestamp: time.Now(),
						Command:   "watchdog_get_user_after_register_error",
						Error:     err.Error(),
						Username:  clientName,
						ClientName: clientName,
					})
					continue
				}
			} else {
				// Found user through search - use the first match
				user = users[0]
			}
		}

		if user.UpdatedAt.Unix() == DeletedConfigMarkerTimestamp {
			// If the configuration has reappeared (the client directory exists), reset the marker
			clientDir := fmt.Sprintf("%s/%s", w.config.ClientsDir, clientName)
			if _, err := os.Stat(clientDir); err == nil {
				// Configuration exists again, reset the marker to current time
				if err := w.userRepo.UpdateUserActivity(user.UserID); err != nil {
					w.logger.Log(LogEvent{
						Timestamp: time.Now(),
						Command:   "watchdog_marker_reset_error",
						Error:     fmt.Sprintf("Failed to reset marker for user %d: %v", user.UserID, err),
						UserID:    user.UserID,
						ClientName: clientName,
					})
				} else {
					// Update user object to reflect new timestamp
					user.UpdatedAt = time.Now()
					w.logger.Log(LogEvent{
						Timestamp:  time.Now(),
						Command:    "watchdog_marker_reset",
						UserID:     user.UserID,
						ClientName: clientName,
					})
				}
			} else {
				continue // Skip users with the special marker if configuration doesn't exist
			}
		}

		// Check max test duration using the user's created_at timestamp
		// This applies to all users regardless of protection level
		if w.config.MaxTestDuration > 0 {
			if time.Since(user.CreatedAt) >= w.config.MaxTestDuration {
				// Check if user has protection before removing
				isProtected := user.UserLevel == string(Premium) ||
					user.UserLevel == string(Moderator) ||
					user.UserLevel == string(Admin)

				if !isProtected {
					toRemove = append(toRemove, clientName)
				}
				continue
			}
		}

		stats, hasStats := allPeerStats[clientName]
		if hasStats {
			if stats.Status == "active" {
				// Update the user's updated_at timestamp in the users table for all users
				// Use the actual UserID from the user object (which may be 0 for NULL user_ids)
				updateErr := w.userRepo.UpdateUserActivity(user.UserID)
				if updateErr != nil {
					w.logger.Log(LogEvent{
						Timestamp: time.Now(),
						Command:   "watchdog_user_activity_update_error",
						Error:     updateErr.Error(),
						UserID:    user.UserID,
						ClientName: clientName,
					})
				}
				// For active users, check if they have protected status to skip deletion
				isProtected := user.UserLevel == string(Premium) ||
					user.UserLevel == string(Moderator) ||
					user.UserLevel == string(Admin)

				if isProtected {
					continue // Protected users continue without deletion check
				}
				// Non-protected active users continue to next cycle check
				continue
			} else {
				// For inactive users, check if they have protection before considering for deletion
				isProtected := user.UserLevel == string(Premium) ||
					user.UserLevel == string(Moderator) ||
					user.UserLevel == string(Admin)

				if isProtected {
					// Protected users are not deleted even if inactive
					continue
				}

				// Check if unprotected user has been inactive beyond the threshold based on their updated_at
				if time.Since(user.UpdatedAt) >= w.config.WatchdogInactiveThreshold {
					toRemove = append(toRemove, clientName)
				}
			}
		} else {
			// If we can't get WireGuard stats, check if user has protection first
			isProtected := user.UserLevel == string(Premium) ||
				user.UserLevel == string(Moderator) ||
				user.UserLevel == string(Admin)

			if isProtected {
				// Protected users are not deleted even if stats unavailable
				continue
			}

			// If we can't get WireGuard stats, check against the user's last updated time for unprotected users
			if time.Since(user.UpdatedAt) >= w.config.WatchdogInactiveThreshold {
				toRemove = append(toRemove, clientName)
			}
		}
	}

	for _, clientName := range toRemove {
		w.removeInactiveClient(clientName)
	}

	duration := time.Since(startTime)
	w.logger.Log(LogEvent{
		Timestamp: time.Now(),
		Command:   "watchdog_cycle_completed",
		Error:     fmt.Sprintf("Processed %d clients, removed %d clients in %v", len(clientNames), len(toRemove), duration),
	})
}

func (w *ClientWatchdog) removeInactiveClient(clientName string) {
	// First, get the user to get their userID for marking
	user, err := w.userRepo.GetUserByUsername(clientName)
	if err != nil {
		// If exact match fails, try case-insensitive search
		users, searchErr := w.userRepo.SearchUsers(clientName)
		if searchErr != nil || len(users) == 0 {
			// If user not found by username, try to parse the clientName as a numeric userID
			userID, parseErr := strconv.ParseInt(clientName, 10, 64)
			if parseErr != nil {
				// If clientName is neither a known username nor a numeric ID, we can't mark it
				w.logger.Log(LogEvent{
					Timestamp: time.Now(),
					Command:   "watchdog_user_not_found_for_marking",
					Error:     fmt.Sprintf("Could not find user for marking: %s", clientName),
					ClientName: clientName,
				})
			} else {
				// Try to get user by ID
				user, err = w.userRepo.GetUserByUserID(userID)
				if err != nil {
					w.logger.Log(LogEvent{
						Timestamp: time.Now(),
						Command:   "watchdog_get_user_by_id_for_marking_error",
						Error:     err.Error(),
						ClientName: clientName,
					})
				}
			}
		} else {
			// Found user through search - use the first match
			user = users[0]
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	output, exitCode, err := w.scriptRunner.RunRemoveScript(ctx, clientName)
	if err != nil || exitCode != 0 {
		errMsg := ""
		if err != nil {
			errMsg = err.Error()
		}
		w.logger.Log(LogEvent{
			Timestamp:      time.Now(),
			ClientName:     clientName,
			Command:        "watchdog_remove_failed",
			ScriptOutput:   output,
			ScriptExitCode: exitCode,
			Error:          errMsg,
		})
		return
	}

	// Mark the user in the database to indicate their config was deleted
	if user != nil {
		markErr := w.userRepo.MarkUserConfigDeleted(user.UserID)
		if markErr != nil {
			w.logger.Log(LogEvent{
				Timestamp: time.Now(),
				Command:   "watchdog_mark_deleted_error",
				Error:     markErr.Error(),
				UserID:    user.UserID,
				ClientName: clientName,
			})
		}
	}

	w.logger.Log(LogEvent{
		Timestamp:    time.Now(),
		ClientName:   clientName,
		Command:      "watchdog_removed",
		ScriptOutput: output,
	})
}
package database

import (
	"database/sql"
	"testing"
	"time"

	"phobos-bot/internal"
	_ "github.com/mattn/go-sqlite3"
)

// Schema for testing purposes
const testSchema = `-- Users table
CREATE TABLE IF NOT EXISTS users (
    user_id INTEGER PRIMARY KEY,
    username TEXT,
    user_level TEXT NOT NULL DEFAULT 'basic',
    premium_expires_at DATETIME,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_user_level ON users(user_level);

-- Logs table
CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    client_name TEXT,
    command TEXT,
    script_exit_code INTEGER,
    script_output TEXT,
    error TEXT,
    is_premium BOOLEAN,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_user_id ON logs(user_id);

-- Feedback table
CREATE TABLE IF NOT EXISTS feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    message TEXT NOT NULL,
    processed BOOLEAN DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);


-- Blocked users table
CREATE TABLE IF NOT EXISTS blocked_users (
    user_id INTEGER PRIMARY KEY,
    username TEXT,
    reason TEXT,
    blocked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    blocked_by INTEGER,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Message templates table
CREATE TABLE IF NOT EXISTS message_templates (
    message_key TEXT PRIMARY KEY,
    template_text TEXT NOT NULL,
    language_code TEXT DEFAULT 'ru',
    version INTEGER DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Configuration table
CREATE TABLE IF NOT EXISTS configuration (
    config_key TEXT PRIMARY KEY,
    config_value TEXT NOT NULL,
    data_type TEXT NOT NULL DEFAULT 'string',  -- string, int, bool, duration
    description TEXT,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);`

// TestBasicDatabaseFunctionality tests the basic database functionality
func TestBasicDatabaseFunctionality(t *testing.T) {
	// Create an in-memory database for testing
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("Failed to open in-memory database: %v", err)
	}
	defer db.Close()

	// Initialize schema by executing the SQL directly
	_, err = db.Exec(testSchema)
	if err != nil {
		t.Fatalf("Failed to execute schema: %v", err)
	}
	
	// Insert initial schema version record
	_, err = db.Exec(`INSERT INTO configuration (config_key, config_value, data_type, description) VALUES ('schema_version', '1', 'int', 'Database schema version')`)
	if err != nil {
		t.Fatalf("Failed to insert schema version: %v", err)
	}

	// Test user repository
	userRepo := NewUserRepository(db)

	// Test user registration
	userID := int64(123456789)
	username := "test_user"
	err = userRepo.RegisterUser(userID, username)
	if err != nil {
		t.Fatalf("Failed to register user: %v", err)
	}

	// Test getting user by ID
	user, err := userRepo.GetUserByUserID(userID)
	if err != nil {
		t.Fatalf("Failed to get user by ID: %v", err)
	}
	if user.UserID != userID || user.Username != username || string(user.UserLevel) != string(internal.Basic) {
		t.Errorf("User data mismatch: got %+v", user)
	}

	// Test updating user level to premium
	err = userRepo.UpdateUserLevel(userID, internal.Premium)
	if err != nil {
		t.Fatalf("Failed to update user level: %v", err)
	}

	// Test premium status
	isPremium, err := userRepo.IsPremium(userID)
	if err != nil {
		t.Fatalf("Failed to check premium status: %v", err)
	}
	if !isPremium {
		t.Error("User should be premium after updating level")
	}

	// Test message template repository
	templateRepo := NewMessageTemplateRepository(db)

	// Add a test template
	testKey := "test_message"
	testTemplate := "Hello {{name}}!"
	err = templateRepo.UpdateMessage(testKey, testTemplate)
	if err != nil {
		t.Fatalf("Failed to update message: %v", err)
	}

	// Get the template back
	template, err := templateRepo.GetMessage(testKey)
	if err != nil {
		t.Fatalf("Failed to get message: %v", err)
	}

	if template.TemplateText != testTemplate {
		t.Errorf("Template text mismatch: got %s, want %s", template.TemplateText, testTemplate)
	}

	// Test rendering template
	rendered, err := templateRepo.RenderTemplate(testKey, map[string]interface{}{"name": "World"})
	if err != nil {
		t.Fatalf("Failed to render template: %v", err)
	}

	expected := "Hello World!"
	if rendered != expected {
		t.Errorf("Rendered template mismatch: got %s, want %s", rendered, expected)
	}

	// Test getting non-existent template returns error
	_, err = templateRepo.GetMessage("non_existent_key")
	if err == nil {
		t.Error("Expected error when getting non-existent template")
	}


	// Test feedback repository
	feedbackRepo := NewFeedbackRepository(db)
	
	feedback := internal.Feedback{
		UserID:    userID,
		Username:  username,
		Timestamp: time.Now(),
		Message:   "Test feedback message",
	}
	
	err = feedbackRepo.SaveFeedback(feedback)
	if err != nil {
		t.Fatalf("Failed to save feedback: %v", err)
	}

	feedbacks, err := feedbackRepo.GetFeedbackByUser(userID)
	if err != nil {
		t.Fatalf("Failed to get feedback: %v", err)
	}
	
	if len(feedbacks) == 0 {
		t.Error("Should have at least one feedback")
	}

	// Test blocklist repository
	blocklistRepo := NewBlocklistRepository(db)
	
	err = blocklistRepo.AddToBlocklist(userID, username, "Test reason", 0)
	if err != nil {
		t.Fatalf("Failed to add to blocklist: %v", err)
	}

	isBlocked, err := blocklistRepo.IsBlocked(userID, username)
	if err != nil {
		t.Fatalf("Failed to check block status: %v", err)
	}
	if !isBlocked {
		t.Error("User should be blocked after adding to blocklist")
	}

	// Test configuration repository
	configRepo := NewConfigRepository(db)
	
	testConfigKey := "max_test_duration_minutes"
	testConfigValue := 60
	err = configRepo.SetInt(testConfigKey, testConfigValue, "Maximum test duration in minutes")
	if err != nil {
		t.Fatalf("Failed to set config: %v", err)
	}

	retrievedValue, err := configRepo.GetInt(testConfigKey)
	if err != nil {
		t.Fatalf("Failed to get config: %v", err)
	}
	
	if retrievedValue != testConfigValue {
		t.Errorf("Config value mismatch: got %d, want %d", retrievedValue, testConfigValue)
	}
}

// TestDatabaseErrorHandling tests error handling without fallbacks
func TestDatabaseErrorHandling(t *testing.T) {
	// Create an in-memory database for testing
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("Failed to open in-memory database: %v", err)
	}
	defer db.Close()

	// Initialize schema by executing the SQL directly
	_, err = db.Exec(testSchema)
	if err != nil {
		t.Fatalf("Failed to execute schema: %v", err)
	}
	
	// Insert initial schema version record
	_, err = db.Exec(`INSERT INTO configuration (config_key, config_value, data_type, description) VALUES ('schema_version', '1', 'int', 'Database schema version')`)
	if err != nil {
		t.Fatalf("Failed to insert schema version: %v", err)
	}

	// Test user repository
	userRepo := NewUserRepository(db)

	// Test getting non-existent user returns error
	_, err = userRepo.GetUserByUserID(999999) // non-existent user
	if err == nil {
		t.Error("Expected error when getting non-existent user")
	}

	// Test message template repository error handling
	templateRepo := NewMessageTemplateRepository(db)
	
	// Test getting non-existent template returns error
	_, err = templateRepo.GetMessage("non_existent")
	if err == nil {
		t.Error("Expected error when getting non-existent template")
	}
}

// TestUserLevelLogic tests that user levels work correctly with access controls
func TestUserLevelLogic(t *testing.T) {
	// Create an in-memory database for testing
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("Failed to open in-memory database: %v", err)
	}
	defer db.Close()

	// Initialize schema by executing the SQL directly
	_, err = db.Exec(testSchema)
	if err != nil {
		t.Fatalf("Failed to execute schema: %v", err)
	}
	
	// Insert initial schema version record
	_, err = db.Exec(`INSERT INTO configuration (config_key, config_value, data_type, description) VALUES ('schema_version', '1', 'int', 'Database schema version')`)
	if err != nil {
		t.Fatalf("Failed to insert schema version: %v", err)
	}

	userRepo := NewUserRepository(db)

	// Create users with different levels
	basicUserID := int64(111111111)
	premiumUserID := int64(222222222)
	modUserID := int64(333333333)
	adminUserID := int64(444444444)

	// Register all users (they get basic level by default)
	err = userRepo.RegisterUser(basicUserID, "basic_user")
	if err != nil {
		t.Fatalf("Failed to register basic user: %v", err)
	}

	err = userRepo.RegisterUser(premiumUserID, "premium_user")
	if err != nil {
		t.Fatalf("Failed to register premium user: %v", err)
	}
	err = userRepo.UpdateUserLevel(premiumUserID, internal.Premium)
	if err != nil {
		t.Fatalf("Failed to update premium user: %v", err)
	}

	err = userRepo.RegisterUser(modUserID, "mod_user")
	if err != nil {
		t.Fatalf("Failed to register mod user: %v", err)
	}
	err = userRepo.UpdateUserLevel(modUserID, internal.Moderator)
	if err != nil {
		t.Fatalf("Failed to update mod user: %v", err)
	}

	err = userRepo.RegisterUser(adminUserID, "admin_user")
	if err != nil {
		t.Fatalf("Failed to register admin user: %v", err)
	}
	err = userRepo.UpdateUserLevel(adminUserID, internal.Admin)
	if err != nil {
		t.Fatalf("Failed to update admin user: %v", err)
	}

	// Test level checks
	isBasicPrem, err := userRepo.IsPremium(basicUserID)
	if err != nil {
		t.Fatalf("Error checking basic user premium status: %v", err)
	}
	if isBasicPrem {
		t.Error("Basic user should not be premium")
	}

	isPremiumPrem, err := userRepo.IsPremium(premiumUserID)
	if err != nil {
		t.Fatalf("Error checking premium user premium status: %v", err)
	}
	if !isPremiumPrem {
		t.Error("Premium user should be premium")
	}

	isModMod, err := userRepo.IsModerator(modUserID)
	if err != nil {
		t.Fatalf("Error checking mod status: %v", err)
	}
	if !isModMod {
		t.Error("Mod user should be moderator")
	}

	isAdmin, err := userRepo.IsAdmin(adminUserID)
	if err != nil {
		t.Fatalf("Error checking admin status: %v", err)
	}
	if !isAdmin {
		t.Error("Admin user should be admin")
	}
}
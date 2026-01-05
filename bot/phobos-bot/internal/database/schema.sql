-- SQLite schema for Phobos Bot

-- Users table
CREATE TABLE IF NOT EXISTS users (
    user_id INTEGER,
    username TEXT NOT NULL,
    user_level TEXT NOT NULL DEFAULT 'basic',
    premium_expires_at DATETIME,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, username)
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_user_level ON users(user_level);

-- Logs table
CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    client_name TEXT,
    command TEXT,
    script_exit_code INTEGER,
    script_output TEXT,
    error TEXT,
    is_premium BOOLEAN,
    user_level TEXT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_user_id ON logs(user_id);

-- Feedback table
CREATE TABLE IF NOT EXISTS feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    message TEXT NOT NULL,
    processed BOOLEAN DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);


-- Blocked users table
CREATE TABLE IF NOT EXISTS blocked_users (
    user_id INTEGER,
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
);
-- SQL script to cleanup personal data from phobos-bot.db before publication
-- This script removes all user data, logs, feedback, and blocked users
-- while preserving database structure, message templates, and configuration

BEGIN TRANSACTION;

-- Delete all user data
DELETE FROM users;

-- Delete all logs
DELETE FROM logs;

-- Delete all feedback
DELETE FROM feedback;

-- Delete all blocked users
DELETE FROM blocked_users;

-- Clear sensitive configuration values (bot token, etc.)
-- Keep structure but clear sensitive data
UPDATE configuration
SET config_value = ''
WHERE config_key IN (
    'bot_token',
    'scripts_dir',
    'clients_dir'
);

-- Optional: Reset auto-increment counters
DELETE FROM sqlite_sequence WHERE name IN ('logs', 'feedback');

-- Vacuum to reclaim space and clean up the database
VACUUM;

COMMIT;

-- Verify cleanup
SELECT 'Users count: ' || COUNT(*) FROM users;
SELECT 'Logs count: ' || COUNT(*) FROM logs;
SELECT 'Feedback count: ' || COUNT(*) FROM feedback;
SELECT 'Blocked users count: ' || COUNT(*) FROM blocked_users;
SELECT 'Message templates count: ' || COUNT(*) FROM message_templates;
SELECT 'Configuration entries count: ' || COUNT(*) FROM configuration;

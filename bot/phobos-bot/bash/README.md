# Bot Management Scripts

> **Статус:** Бот имеет полностью работающий функционал, но не является законченным продуктом. Это гибкая основа для доработки под свои нужды.

## Database Cleanup Scripts

### cleanup-db.py

Python script for cleaning up personal data from the database before publication.

**Usage:**
```bash
cd /root/bot/phobos-bot/bash
python3 cleanup-db.py
```

**What it does:**
- Creates automatic backup in `../backups/` directory
- Removes all users, logs, feedback
- Clears sensitive configuration (bot_token, scripts_dir, clients_dir)
- Runs VACUUM to optimize database
- Shows statistics before and after cleanup

**Files cleaned:**
- Users: ALL removed
- Logs: ALL removed
- Feedback: ALL removed
- Sensitive config values: cleared

**Files preserved:**
- Database structure
- Message templates
- System configuration

See `DATABASE-CLEANUP-INFO.md` for detailed information.

### cleanup-db.sh

Bash wrapper for database cleanup (uses sqlite3).

**Usage:**
```bash
cd /root/bot/phobos-bot/bash
sudo ./cleanup-db.sh
```

### cleanup-db.sql

Raw SQL script for manual cleanup.

**Usage:**
```bash
cd /root/bot/phobos-bot
sqlite3 phobos-bot.db < bash/cleanup-db.sql
```

## bot_toggle.sh

Smart toggle script for Phobos Bot management.

### Features

- **Auto-detection**: Automatically detects bot and service state
- **Toggle behavior**: Stops running bot, starts stopped bot
- **Service creation**: Creates systemd service if it doesn't exist
- **Colored output**: Clear status messages with emojis
- **Log display**: Shows last 15 lines of system log when starting

### Usage

```bash
# Run from anywhere (must use sudo)
sudo /root/bot/phobos-bot/bash/bot_toggle.sh

# Or from the bash directory
cd /root/bot/phobos-bot/bash
sudo ./bot_toggle.sh
```

### Behavior

**If service doesn't exist:**
- Creates `/etc/systemd/system/phobos-bot.service`
- Links to bot binary in current directory
- Enables and starts the service
- Shows last 15 lines of logs

**If bot is running:**
- Stops the bot
- Shows confirmation message
- Displays current status

**If bot is stopped:**
- Starts the bot
- Shows success message
- Displays last 15 lines of logs
- Shows current status

### Requirements

- Must be run as root (use sudo)
- Bot binary must exist at `/root/bot/phobos-bot/bot`
- If binary doesn't exist, build it first:
  ```bash
  cd /root/bot/phobos-bot
  go build -o bot cmd/bot/main.go
  ```

### Service File Location

The script creates the service file at:
```
/etc/systemd/system/phobos-bot.service
```

Service configuration:
- **Type**: simple
- **User**: root
- **WorkingDirectory**: Auto-detected from script location
- **Restart**: always (10 seconds delay)
- **Enabled**: yes (starts on boot)

### Examples

**First run (service doesn't exist):**
```
⚠️  Service phobos-bot does not exist
ℹ️  Creating systemd service...
✅ Service created and enabled
ℹ️  Starting phobos-bot...
✅ Bot started successfully

ℹ️  Last 15 lines of system log:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
... (log output)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Current status:
● phobos-bot.service - Phobos Bot
     Loaded: loaded
     Active: active (running)
     ...
```

**Toggle running bot (stops):**
```
ℹ️  Bot is running, stopping it...
✅ Bot stopped successfully

ℹ️  Current status:
○ phobos-bot.service - Phobos Bot
     Active: inactive (dead)
     ...
```

**Toggle stopped bot (starts):**
```
ℹ️  Bot is not running, starting it...
✅ Bot started successfully

ℹ️  Last 15 lines of system log:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
... (log output)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Current status:
● phobos-bot.service - Phobos Bot
     Active: active (running)
     ...
```

### Troubleshooting

**"This script must be run as root"**
- Solution: Use `sudo` before the command

**"Bot binary not found"**
- Solution: Build the bot first:
  ```bash
  cd /root/bot/phobos-bot
  go build -o bot cmd/bot/main.go
  ```

**"Failed to start bot"**
- Check the logs shown in the output
- Verify bot binary has execute permissions: `chmod +x /root/bot/phobos-bot/bot`
- Check for port conflicts or missing dependencies

### Manual Service Commands

If you need more control, use systemctl directly:

```bash
# Start bot
sudo systemctl start phobos-bot

# Stop bot
sudo systemctl stop phobos-bot

# Restart bot
sudo systemctl restart phobos-bot

# Check status
sudo systemctl status phobos-bot

# View logs
sudo journalctl -u phobos-bot -n 50 --no-pager

# Follow logs in real-time
sudo journalctl -u phobos-bot -f

# Enable on boot
sudo systemctl enable phobos-bot

# Disable on boot
sudo systemctl disable phobos-bot
```

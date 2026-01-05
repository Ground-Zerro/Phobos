# Configuration for Phobos Bot

The Phobos Bot now supports flexible configuration file location options:

## Configuration File Location

The bot looks for the configuration file in the following order:

1. **Command-line flag**: `./bot -config /path/to/config.yaml`
2. **Environment variable**: `CONFIG_FILE_PATH=/path/to/config.yaml ./bot`
3. **Current directory**: `./config.yaml` in the directory where the bot is executed (default)

## Usage

```bash
# Using the default location (./config.yaml)
./bot

# Specifying config location via command-line flag
./bot -config /custom/path/config.yaml

# Using environment variable
CONFIG_FILE_PATH=/path/to/config.yaml ./bot
```

## Configuration File Format

The config.yaml file should have the following format:

```yaml
bot:
  database_path: "phobos-bot.db"
```

All other configuration values (like bot token, script directories, etc.) are stored in the database and can be configured via the bot's admin interface or directly in the database.
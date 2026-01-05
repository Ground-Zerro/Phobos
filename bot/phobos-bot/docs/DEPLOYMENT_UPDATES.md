# Deployment Script Updates

## Required Changes for Deployment Scripts

For any deployment script (like `/root/bot/bot_deploy.sh`), the following updates are required to support the new configuration behavior:

### 1. Update Service Configuration
If your deployment script creates a systemd service, update the ExecStart line to include the config path:

```
ExecStart=/path/to/bot/binary -config /path/to/bot/directory/config.yaml
```

### 2. Ensure Working Directory
Make sure the service runs in the correct working directory where config.yaml is located:

```
WorkingDirectory=/path/to/bot/directory
```

### 3. Configuration File
Ensure that the config.yaml file exists in the correct location before starting the service.

### 4. Example Updated Service File
[Unit]
Description=Phobos Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/path/to/bot/directory
ExecStart=/path/to/bot/binary -config /path/to/bot/directory/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target

## Backwards Compatibility
Note: The /etc/phobos-bot/config.yaml fallback has been completely removed. The bot will now only look for config.yaml in the current directory (where the bot binary is located) by default, or at a location specified via the -config flag or CONFIG_FILE_PATH environment variable.
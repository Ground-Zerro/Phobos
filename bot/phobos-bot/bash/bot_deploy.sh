

set -e  # Exit immediately if a command exits with a non-zero status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_DIR="/opt/Phobos/bot/phobos-bot"
BINARY_NAME="bot"
SERVICE_NAME="phobos-bot"

print_status() {
    echo -e "\033[1;34m>>> $1\033[0m"
}

print_success() {
    echo -e "\033[1;32m>>> $1\033[0m"
}

print_error() {
    echo -e "\033[1;31m>>> $1\033[0m"
}

if [[ ":$PATH:" != *":/usr/local/go/bin:"* ]] && [[ ":$PATH:" != *":$GOROOT/bin:"* ]]; then
    export PATH="$PATH:/usr/local/go/bin:$GOROOT/bin"
    print_status "Added Go paths to PATH environment variable"
fi

if [[ ":$PATH:" != *":/root/.local/bin:"* ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$PATH:/root/.local/bin:$HOME/.local/bin"
    print_status "Added local binary paths to PATH environment variable"
fi

echo "=== Phobos Bot Deployment Script ==="

if [ -d "$BOT_DIR" ]; then
    cd "$BOT_DIR"
    print_status "Changed to bot directory: $BOT_DIR"
else
    print_error "Bot directory does not exist: $BOT_DIR"
    exit 1
fi

if ! command -v go &> /dev/null; then
    if [ -f "/usr/local/go/bin/go" ]; then
        export PATH="$PATH:/usr/local/go/bin"
    elif [ -f "$HOME/go/bin/go" ]; then
        export PATH="$PATH:$HOME/go/bin"
    elif [ -f "/usr/bin/go" ]; then
        export PATH="$PATH:/usr/bin"
    fi
    
    if ! command -v go &> /dev/null; then
        print_error "Go is not installed or not in PATH"
        exit 1
    fi
fi

GO_VERSION=$(go version | sed -E 's/.*go([0-9]+)\.([0-9]+).*/\1.\2/')
MAJOR=$(echo "$GO_VERSION" | cut -d'.' -f1)
MINOR=$(echo "$GO_VERSION" | cut -d'.' -f2)

if [[ $MAJOR -lt 1 ]] || { [[ $MAJOR -eq 1 ]] && [[ $MINOR -lt 20 ]]; }; then
    print_error "Go version 1.20 or higher is required. Current version: go$GO_VERSION"
    exit 1
else
    print_status "Go version check passed: go$GO_VERSION"
fi

print_status "Verifying Go dependencies..."
if go mod verify; then
    print_success "Dependencies verified successfully"
else
    print_error "Dependency verification failed"
    exit 1
fi

CONFIG_FILE="$BOT_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file does not exist: $CONFIG_FILE"
    exit 1
else
    print_status "Configuration file found: $CONFIG_FILE"
fi

if command -v python3 &> /dev/null; then
    if python3 -c "import yaml; open('$CONFIG_FILE', 'r'); print('YAML is valid')" &> /dev/null; then
        print_success "Configuration file is properly formatted YAML"
    else
        print_error "Configuration file has invalid YAML format"
        exit 1
    fi
elif command -v yq &> /dev/null; then
    if yq read "$CONFIG_FILE" &> /dev/null; then
        print_success "Configuration file is properly formatted YAML"
    else
        print_error "Configuration file has invalid YAML format"
        exit 1
    fi
else
    print_status "Warning: Python3 or yq not available, skipping YAML validation"
fi


SERVICE_FILE_PATH="/etc/systemd/system/$SERVICE_NAME.service"
if [ ! -f "$SERVICE_FILE_PATH" ]; then
    print_status "Systemd service file does not exist: $SERVICE_FILE_PATH"
    print_status "Creating systemd service file from template..."

    BOT_TOKEN=$(grep "token:" "$CONFIG_FILE" | sed 's/.*token: "\([^"]*\)".*/\1/' | head -n1)
    SCRIPTS_DIR=$(grep "scripts_dir:" "$CONFIG_FILE" | sed 's/.*scripts_dir: "\([^"]*\)".*/\1/' | head -n1)
    LOG_FILE_PATH=$(grep "log_file_path:" "$CONFIG_FILE" | sed 's/.*log_file_path: "\([^"]*\)".*/\1/' | head -n1)
    SCRIPT_TIMEOUT=$(grep "script_timeout_seconds:" "$CONFIG_FILE" | sed 's/.*script_timeout_seconds: \(.*\)/\1/' | head -n1)

    sudo tee "$SERVICE_FILE_PATH" > /dev/null <<EOF

[Unit]
Description=Phobos Telegram Bot
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/$BINARY_NAME
Restart=always
RestartSec=10

Environment="CONFIG_FILE_PATH=$CONFIG_FILE"

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -eq 0 ]; then
        print_success "Systemd service file created successfully"
    else
        print_error "Failed to create systemd service file"
        exit 1
    fi
else
    print_status "Systemd service file exists: $SERVICE_FILE_PATH"

    if grep -q "YOUR_BOT_TOKEN_HERE" "$SERVICE_FILE_PATH"; then
        print_status "Service file contains placeholder token, updating with config values..."

        BOT_TOKEN=$(grep "token:" "$CONFIG_FILE" | sed 's/.*token: "\([^"]*\)".*/\1/' | head -n1)
        SCRIPTS_DIR=$(grep "scripts_dir:" "$CONFIG_FILE" | sed 's/.*scripts_dir: "\([^"]*\)".*/\1/' | head -n1)
        LOG_FILE_PATH=$(grep "log_file_path:" "$CONFIG_FILE" | sed 's/.*log_file_path: "\([^"]*\)".*/\1/' | head -n1)
        SCRIPT_TIMEOUT=$(grep "script_timeout_seconds:" "$CONFIG_FILE" | sed 's/.*script_timeout_seconds: \(.*\)/\1/' | head -n1)

        sudo sed -i "s|Environment=\"TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN_HERE\"|Environment=\"CONFIG_FILE_PATH=$CONFIG_FILE\"|g" "$SERVICE_FILE_PATH"
        sudo sed -i "/Environment=\"VPS_CLIENT_SCRIPT_PATH\|Environment=\"LOG_FILE_PATH\|Environment=\"SCRIPT_TIMEOUT_SECONDS/d" "$SERVICE_FILE_PATH"
    fi

    print_success "Service file properly configured"
fi

print_status "Reloading systemd daemon..."
if sudo systemctl daemon-reload; then
    print_success "Systemd daemon reloaded successfully"
else
    print_error "Failed to reload systemd daemon"
    exit 1
fi

if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    print_error "This script requires root privileges or passwordless sudo access to manage systemd services"
    exit 1
else
    print_status "Script has appropriate permissions for deployment"
fi

print_status "Building Phobos Bot..."

if CGO_ENABLED=1 go build -o "$BINARY_NAME" ./cmd/bot/; then
    print_success "Successfully built the bot binary"
else
    print_error "Failed to build the bot"
    exit 1
fi

if [ ! -f "$BINARY_NAME" ]; then
    print_error "Binary file was not created"
    exit 1
fi

print_status "Binary created successfully: $BINARY_NAME"

if ! systemctl list-unit-files --type=service | grep -q "$SERVICE_NAME.service"; then
    print_status "Service file exists but system hasn't loaded it. Enabling the service..."
    sudo systemctl enable "$SERVICE_NAME.service"
    if [ $? -eq 0 ]; then
        print_success "Service enabled successfully"
    else
        print_error "Failed to enable the service"
        exit 1
    fi
fi

sudo systemctl daemon-reload

print_status "Checking service status before restart..."

if systemctl list-units --type=service | grep -q "$SERVICE_NAME.service"; then
    systemctl is-active --quiet "$SERVICE_NAME" && print_status "Service is currently running" || print_status "Service is currently stopped"
else
    print_status "Service is not loaded yet but will be started"
fi

print_status "Restarting $SERVICE_NAME service..."

if sudo systemctl restart "$SERVICE_NAME"; then
    print_success "Successfully restarted $SERVICE_NAME service"
else
    print_error "Failed to restart $SERVICE_NAME service"
    exit 1
fi

print_status "Waiting for service to start..."

sleep 3

if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    print_success "$SERVICE_NAME service is running"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l --quiet
else
    print_error "$SERVICE_NAME service failed to start"
    sudo journalctl -u "$SERVICE_NAME" --no-pager -n 20
    exit 1
fi

print_status "Deployment completed successfully!"
print_success "Phobos Bot has been updated and restarted."
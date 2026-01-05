#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BOT_BINARY="$BOT_DIR/bot"
SERVICE_NAME="phobos-bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check for command line arguments
STOP_ONLY=false
if [ $# -gt 0 ]; then
    case $1 in
        "stop")
            STOP_ONLY=true
            ;;
        *)
            echo "Usage: $0 [stop]"
            echo "  stop - only stop the bot service if running"
            exit 0
            ;;
    esac
fi

echo_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

service_exists() {
    systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"
}

service_is_running() {
    systemctl is-active --quiet "$SERVICE_NAME"
}

create_service() {
    echo_info "Creating systemd service..."

    if [ ! -f "$BOT_BINARY" ]; then
        echo_error "Bot binary not found at: $BOT_BINARY"
        echo_info "Please build the bot first with: go build -o bot cmd/bot/main.go"
        exit 1
    fi

    # Check if config file exists in the expected location
    CONFIG_FILE="$BOT_DIR/config.yaml"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo_warning "Configuration file not found at: $CONFIG_FILE"
        echo_info "Please create config.yaml in the bot directory before starting the service"
        echo_info "The bot will look for config.yaml in its current directory by default."
        echo_info "Example config.yaml content:"
        echo "  bot:"
        echo "    database_path: \"phobos-bot.db\""
        exit 1
    fi

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Phobos Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_BINARY -config $BOT_DIR/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"

    echo_success "Service created and enabled"
}

show_logs() {
    echo ""
    echo_info "Last 15 lines of system log:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    journalctl -u "$SERVICE_NAME" -n 15 --no-pager
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_root

if $STOP_ONLY; then
    # Only stop mode - stop if running and exit
    if service_is_running; then
        echo_info "Bot is running, stopping it..."
        systemctl stop "$SERVICE_NAME"
        sleep 1

        if ! service_is_running; then
            echo_success "Bot stopped successfully"
        else
            echo_error "Failed to stop bot"
            exit 1
        fi
    else
        echo_info "Bot is not running, nothing to stop."
    fi
else
    # Original toggle behavior
    if ! service_exists; then
        echo_warning "Service $SERVICE_NAME does not exist"
        create_service

        echo_info "Starting $SERVICE_NAME..."
        systemctl start "$SERVICE_NAME"
        sleep 2

        if service_is_running; then
            echo_success "Bot started successfully"
            show_logs
        else
            echo_error "Failed to start bot"
            show_logs
            exit 1
        fi
    else
        if service_is_running; then
            echo_info "Bot is running, stopping it..."
            systemctl stop "$SERVICE_NAME"
            sleep 1

            if ! service_is_running; then
                echo_success "Bot stopped successfully"
            else
                echo_error "Failed to stop bot"
                exit 1
            fi
        else
            echo_info "Bot is not running, starting it..."
            systemctl start "$SERVICE_NAME"
            sleep 2

            if service_is_running; then
                echo_success "Bot started successfully"
                show_logs
            else
                echo_error "Failed to start bot"
                show_logs
                exit 1
            fi
        fi
    fi
fi

echo ""
echo_info "Current status:"
systemctl status "$SERVICE_NAME" --no-pager -l

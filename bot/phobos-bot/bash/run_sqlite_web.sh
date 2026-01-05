#!/bin/bash

# Script to install and run sqlite_web

# Configuration variables
DB_PATH="/opt/Phobos/bot/phobos-bot/phobos-bot.db"
VENV_PATH="/tmp/sqlite_web_venv"

# Function to get the public IP address
get_public_ip() {
    # Method 1: Get the IP of the default network interface
    local ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')

    # Method 2: If the above failed, try to get IP from eth0 or similar interface
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi

    # Method 3: If still no IP, try using curl to get public IP
    if [ -z "$ip" ]; then
        ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
    fi

    echo "$ip"
}

# Function to check if sqlite_web processes are running
are_processes_running() {
    local pids=$(pgrep -f "sqlite_web.*$DB_PATH")
    if [ -n "$pids" ]; then
        return 0  # Processes are running
    else
        return 1  # No processes running
    fi
}

# Function to stop existing sqlite_web processes
stop_existing_processes() {
    # Find processes running sqlite_web with the specific database path
    local pids=$(pgrep -f "sqlite_web.*$DB_PATH")

    if [ -n "$pids" ]; then
        echo "Найдены запущенные процессы sqlite_web. Остановка..."
        for pid in $pids; do
            echo "Остановка процесса с PID: $pid"
            kill "$pid" 2>/dev/null || true
            # Wait a moment for the process to terminate
            sleep 1
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                echo "Принудительная остановка процесса с PID: $pid"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        echo "Существующие процессы sqlite_web остановлены."
    fi
}

# Check if processes are running and act accordingly
if are_processes_running; then
    # Processes are running, so stop them
    stop_existing_processes
    # After stopping, exit with appropriate message
    echo "Процесс sqlite_web был остановлен."
    exit 0
else
    # No processes running, so start a new one
    echo "sqlite_web не запущен. Запуск нового процесса..."
fi

# Get the public IP
PUBLIC_IP=$(get_public_ip)

# Check if we got an IP
if [ -z "$PUBLIC_IP" ]; then
    echo "Error: Could not determine public IP address"
    exit 1
fi

# Install sqlite_web in a virtual environment if not already installed
if ! command -v "$VENV_PATH/bin/sqlite_web" &> /dev/null; then
    echo "Setting up virtual environment and installing sqlite_web..."

    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 is not installed"
        exit 1
    fi

    # Check if python3-venv is available, install if not
    if ! python3 -m venv --help >/dev/null 2>&1; then
        echo "Installing python3-venv package..."
        if command -v apt &> /dev/null; then
            # Check if we're running as root, if not use sudo
            if [ "$EUID" -ne 0 ]; then
                sudo apt update && sudo apt install -y python3-venv
            else
                apt update && apt install -y python3-venv
            fi
        else
            echo "Error: Package manager not found to install python3-venv. Please install manually."
            exit 1
        fi
    fi

    # Try to create virtual environment
    if ! python3 -m venv "$VENV_PATH" 2>/dev/null; then
        echo "Error: Failed to create virtual environment."
        exit 1
    fi

    # Activate virtual environment and install sqlite-web
    source "$VENV_PATH/bin/activate"

    # Install sqlite-web in the virtual environment
    pip install sqlite-web

    # Deactivate virtual environment
    deactivate
else
    echo "Virtual environment already exists, using existing installation."
fi

# Check if the database file exists
if [ ! -f "$DB_PATH" ]; then
    echo "Error: Database file does not exist at $DB_PATH"
    exit 1
fi

# Activate virtual environment and run sqlite_web
if [ -f "$VENV_PATH/bin/activate" ]; then
    source "$VENV_PATH/bin/activate"
    # Create the log file if it doesn't exist and ensure proper permissions
    if [ ! -f "/var/log/sqlite_web.log" ]; then
        sudo touch /var/log/sqlite_web.log 2>/dev/null
        sudo chown $(whoami):$(id -gn) /var/log/sqlite_web.log 2>/dev/null || true
    fi
    "$VENV_PATH/bin/sqlite_web" "$DB_PATH" --port 801 --host "$PUBLIC_IP" > /var/log/sqlite_web.log 2>&1 &
    deactivate
else
    echo "Error: Virtual environment not found at $VENV_PATH"
    exit 1
fi

# Display access message
echo "Доступ к SQLite открыт: http://$PUBLIC_IP:801/"
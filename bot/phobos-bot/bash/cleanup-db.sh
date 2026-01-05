#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

DB_FILE="phobos-bot.db"
BACKUP_FILE="backups/phobos-bot.db.backup-$(date +%Y%m%d-%H%M%S)"
SQL_SCRIPT="bash/cleanup-db.sql"

echo "=== Phobos Bot Database Cleanup Script ==="
echo ""

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database file '$DB_FILE' not found!"
    exit 1
fi

if [ ! -f "$SQL_SCRIPT" ]; then
    echo "Error: SQL script '$SQL_SCRIPT' not found!"
    exit 1
fi

echo "1. Creating backup..."
cp "$DB_FILE" "$BACKUP_FILE"
if [ $? -eq 0 ]; then
    echo "   Backup created: $BACKUP_FILE"
else
    echo "   Error: Failed to create backup!"
    exit 1
fi

echo ""
echo "2. Database statistics BEFORE cleanup:"
sqlite3 "$DB_FILE" "SELECT 'Users: ' || COUNT(*) FROM users; SELECT 'Logs: ' || COUNT(*) FROM logs; SELECT 'Feedback: ' || COUNT(*) FROM feedback; SELECT 'Blocked users: ' || COUNT(*) FROM blocked_users;"

echo ""
echo "3. Cleaning up database..."
sqlite3 "$DB_FILE" < "$SQL_SCRIPT"

if [ $? -eq 0 ]; then
    echo "   Cleanup completed successfully!"
else
    echo "   Error: Cleanup failed!"
    echo "   Restoring from backup..."
    cp "$BACKUP_FILE" "$DB_FILE"
    exit 1
fi

echo ""
echo "4. Database statistics AFTER cleanup:"
sqlite3 "$DB_FILE" "SELECT 'Users: ' || COUNT(*) FROM users; SELECT 'Logs: ' || COUNT(*) FROM logs; SELECT 'Feedback: ' || COUNT(*) FROM feedback; SELECT 'Blocked users: ' || COUNT(*) FROM blocked_users;"

echo ""
echo "5. Database size:"
ls -lh "$DB_FILE" | awk '{print "   Current: " $5}'
ls -lh "$BACKUP_FILE" | awk '{print "   Backup:  " $5}'

echo ""
echo "=== Cleanup complete ==="
echo "Backup saved as: $BACKUP_FILE"
echo ""
echo "To restore from backup:"
echo "  cp $BACKUP_FILE $DB_FILE"
echo ""
echo "Note: This script should be run from the bash directory:"
echo "  cd /root/bot/phobos-bot/bash"
echo "  sudo ./cleanup-db.sh"

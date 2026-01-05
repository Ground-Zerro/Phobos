#!/usr/bin/env python3
import sqlite3
import shutil
import os
from datetime import datetime

DB_FILE = "phobos-bot.db"
BACKUP_DIR = "backups"

def create_backup():
    if not os.path.exists(DB_FILE):
        print(f"Error: Database file '{DB_FILE}' not found!")
        return None

    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = os.path.join(BACKUP_DIR, f"phobos-bot.db.backup-{timestamp}")

    print(f"Creating backup: {backup_file}")
    shutil.copy2(DB_FILE, backup_file)
    print(f"Backup created successfully!")
    return backup_file

def get_existing_tables(conn):
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    return [row[0] for row in cursor.fetchall()]

def get_stats(conn):
    cursor = conn.cursor()
    stats = {}

    existing_tables = get_existing_tables(conn)
    tables = ['users', 'logs', 'feedback', 'blocked_users', 'blocklist', 'message_templates', 'configuration']

    for table in tables:
        if table in existing_tables:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            stats[table] = cursor.fetchone()[0]
        else:
            stats[table] = 0

    return stats

def print_stats(stats, title):
    print(f"\n{title}")
    print("-" * 50)
    print(f"Users:             {stats.get('users', 0)}")
    print(f"Logs:              {stats.get('logs', 0)}")
    print(f"Feedback:          {stats.get('feedback', 0)}")
    print(f"Blocked users:     {stats.get('blocked_users', 0)}")
    print(f"Blocklist:         {stats.get('blocklist', 0)}")
    print(f"Message templates: {stats.get('message_templates', 0)}")
    print(f"Configuration:     {stats.get('configuration', 0)}")
    print("-" * 50)

def cleanup_database():
    print("\n=== Phobos Bot Database Cleanup ===\n")

    backup_file = create_backup()
    if not backup_file:
        return

    conn = sqlite3.connect(DB_FILE)

    print("\n1. Database statistics BEFORE cleanup:")
    stats_before = get_stats(conn)
    print_stats(stats_before, "Statistics BEFORE")

    print("\n2. Cleaning up database...")
    cursor = conn.cursor()

    try:
        cursor.execute("BEGIN TRANSACTION")

        existing_tables = get_existing_tables(conn)

        if 'users' in existing_tables:
            print("   - Deleting users...")
            cursor.execute("DELETE FROM users")

        if 'logs' in existing_tables:
            print("   - Deleting logs...")
            cursor.execute("DELETE FROM logs")

        if 'feedback' in existing_tables:
            print("   - Deleting feedback...")
            cursor.execute("DELETE FROM feedback")

        if 'blocked_users' in existing_tables:
            print("   - Deleting blocked users...")
            cursor.execute("DELETE FROM blocked_users")

        if 'blocklist' in existing_tables:
            print("   - Deleting blocklist entries...")
            cursor.execute("DELETE FROM blocklist")

        if 'configuration' in existing_tables:
            print("   - Clearing sensitive configuration...")
            cursor.execute("""
                UPDATE configuration
                SET config_value = ''
                WHERE config_key IN ('bot_token', 'scripts_dir', 'clients_dir')
            """)

        if 'sqlite_sequence' in existing_tables:
            print("   - Resetting auto-increment counters...")
            cursor.execute("DELETE FROM sqlite_sequence WHERE name IN ('logs', 'feedback')")

        cursor.execute("COMMIT")

        print("   - Running VACUUM to reclaim space...")
        conn.execute("VACUUM")

        print("\n   Cleanup completed successfully!")

    except Exception as e:
        print(f"\n   Error during cleanup: {e}")
        cursor.execute("ROLLBACK")
        print(f"   Restoring from backup: {backup_file}")
        conn.close()
        shutil.copy2(backup_file, DB_FILE)
        return

    print("\n3. Database statistics AFTER cleanup:")
    stats_after = get_stats(conn)
    print_stats(stats_after, "Statistics AFTER")

    print("\n4. Database file sizes:")
    db_size = os.path.getsize(DB_FILE)
    backup_size = os.path.getsize(backup_file)
    print(f"   Current database: {db_size:,} bytes ({db_size / 1024:.2f} KB)")
    print(f"   Backup file:      {backup_size:,} bytes ({backup_size / 1024:.2f} KB)")
    print(f"   Space saved:      {backup_size - db_size:,} bytes ({(backup_size - db_size) / 1024:.2f} KB)")

    conn.close()

    print(f"\n=== Cleanup complete ===")
    print(f"Backup saved as: {backup_file}")
    print(f"\nTo restore from backup:")
    print(f"  Copy '{backup_file}' to '{DB_FILE}'")

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(os.path.join(script_dir, '..'))
    cleanup_database()

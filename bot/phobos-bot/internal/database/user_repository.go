package database

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"phobos-bot/internal"
)

type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{
		db: db,
	}
}

func (ur *UserRepository) RegisterUser(userID int64, username string) error {
	if userID == 0 {
		_, err := ur.db.Exec(`
			INSERT OR IGNORE INTO users (user_id, username, user_level, created_at, updated_at)
			VALUES (NULL, ?, 'basic', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		`, username)
		if err != nil {
			return fmt.Errorf("failed to register user without user_id: %w", err)
		}
	} else {
		_, err := ur.db.Exec(`
			INSERT INTO users (user_id, username, user_level, created_at, updated_at)
			VALUES (?, ?, 'basic', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
			ON CONFLICT(user_id) DO UPDATE SET
				username = excluded.username,
				updated_at = CURRENT_TIMESTAMP
			WHERE users.username != excluded.username
		`, userID, username)
		if err != nil {
			return fmt.Errorf("failed to register/update user: %w", err)
		}
	}

	return nil
}

func (ur *UserRepository) GetUserByUserID(userID int64) (*internal.User, error) {
	row := ur.db.QueryRow(`
		SELECT user_id, username, user_level, premium_expires_at, premium_reason, created_at, updated_at
		FROM users
		WHERE user_id = ?
	`, userID)

	var user internal.User
	var userIDFromDB sql.NullInt64
	var premiumExpires sql.NullTime
	var premiumReason sql.NullString

	err := row.Scan(&userIDFromDB, &user.Username, &user.UserLevel, &premiumExpires, &premiumReason, &user.CreatedAt, &user.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("user not found: %w", err)
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	if userIDFromDB.Valid {
		user.UserID = userIDFromDB.Int64
	} else {
		user.UserID = 0
	}

	if premiumExpires.Valid {
		user.PremiumExpiresAt = &premiumExpires.Time
	}

	if premiumReason.Valid {
		user.PremiumReason = &premiumReason.String
	}

	return &user, nil
}

func (ur *UserRepository) GetUserByUsername(username string) (*internal.User, error) {
	row := ur.db.QueryRow(`
		SELECT user_id, username, user_level, premium_expires_at, premium_reason, created_at, updated_at
		FROM users
		WHERE username = ?
	`, username)

	var user internal.User
	var userIDFromDB sql.NullInt64
	var premiumExpires sql.NullTime
	var premiumReason sql.NullString

	err := row.Scan(&userIDFromDB, &user.Username, &user.UserLevel, &premiumExpires, &premiumReason, &user.CreatedAt, &user.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("user not found: %w", err)
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	if userIDFromDB.Valid {
		user.UserID = userIDFromDB.Int64
	} else {
		user.UserID = 0
	}

	if premiumExpires.Valid {
		user.PremiumExpiresAt = &premiumExpires.Time
	}

	if premiumReason.Valid {
		user.PremiumReason = &premiumReason.String
	}

	return &user, nil
}

func (ur *UserRepository) UpdateUserLevel(userID int64, level internal.UserLevel) error {
	_, err := ur.db.Exec(`
		UPDATE users
		SET user_level = ?, updated_at = CURRENT_TIMESTAMP
		WHERE user_id = ?
	`, level, userID)

	if err != nil {
		return fmt.Errorf("failed to update user level: %w", err)
	}

	return nil
}

func (ur *UserRepository) UpdateUserPremium(userID int64, expiresAt *time.Time, reason string) error {
	var expiresAtVal *time.Time
	if expiresAt != nil && !expiresAt.IsZero() {
		expiresAtVal = expiresAt
	}

	var reasonVal *string
	if reason != "" {
		reasonVal = &reason
	}

	_, err := ur.db.Exec(`
		UPDATE users
		SET user_level = ?, premium_expires_at = ?, premium_reason = ?, updated_at = CURRENT_TIMESTAMP
		WHERE user_id = ?
	`, internal.Premium, expiresAtVal, reasonVal, userID)

	if err != nil {
		return fmt.Errorf("failed to update user premium: %w", err)
	}

	return nil
}

func (ur *UserRepository) IsPremium(userID int64) (bool, error) {
	var userLevel string
	var expiresAt sql.NullTime
	err := ur.db.QueryRow(`
		SELECT user_level, premium_expires_at
		FROM users
		WHERE user_id = ?
	`, userID).Scan(&userLevel, &expiresAt)

	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("failed to check premium status: %w", err)
	}

	if userLevel == string(internal.Admin) || userLevel == string(internal.Moderator) {
		return true, nil
	}

	if userLevel != string(internal.Premium) {
		return false, nil
	}

	if !expiresAt.Valid {
		return true, nil
	}

	return time.Now().Before(expiresAt.Time), nil
}

func (ur *UserRepository) IsModerator(userID int64) (bool, error) {
	var userLevel string
	err := ur.db.QueryRow(`
		SELECT user_level
		FROM users
		WHERE user_id = ?
	`, userID).Scan(&userLevel)

	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("failed to check moderator status: %w", err)
	}

	return userLevel == string(internal.Moderator) || userLevel == string(internal.Admin), nil
}

func (ur *UserRepository) IsAdmin(userID int64) (bool, error) {
	var userLevel string
	err := ur.db.QueryRow(`
		SELECT user_level
		FROM users
		WHERE user_id = ?
	`, userID).Scan(&userLevel)

	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("failed to check admin status: %w", err)
	}

	return userLevel == string(internal.Admin), nil
}

func (ur *UserRepository) UpdateUserActivity(userID int64) error {
	_, err := ur.db.Exec(`
		UPDATE users
		SET updated_at = CURRENT_TIMESTAMP
		WHERE user_id = ?
	`, userID)

	if err != nil {
		return fmt.Errorf("failed to update user activity: %w", err)
	}

	return nil
}

func (ur *UserRepository) GetUsersByLevel(level internal.UserLevel) ([]*internal.User, error) {
	rows, err := ur.db.Query(`
		SELECT user_id, username, user_level, premium_expires_at, premium_reason, created_at, updated_at
		FROM users
		WHERE user_level = ?
		ORDER BY user_id
	`, level)

	if err != nil {
		return nil, fmt.Errorf("failed to get users by level: %w", err)
	}
	defer rows.Close()

	var users []*internal.User
	for rows.Next() {
		var user internal.User
		var userIDFromDB sql.NullInt64
		var premiumExpires sql.NullTime
		var premiumReason sql.NullString

		err := rows.Scan(&userIDFromDB, &user.Username, &user.UserLevel, &premiumExpires, &premiumReason, &user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}

		if userIDFromDB.Valid {
			user.UserID = userIDFromDB.Int64
		} else {
			user.UserID = 0
		}

		if premiumExpires.Valid {
			user.PremiumExpiresAt = &premiumExpires.Time
		}

		if premiumReason.Valid {
			user.PremiumReason = &premiumReason.String
		}

		users = append(users, &user)
	}

	return users, nil
}

func (ur *UserRepository) SearchUsers(query string) ([]*internal.User, error) {
	searchPattern := "%" + strings.ToLower(query) + "%"
	rows, err := ur.db.Query(`
		SELECT user_id, username, user_level, premium_expires_at, premium_reason, created_at, updated_at
		FROM users
		WHERE LOWER(username) LIKE ? OR (user_id IS NOT NULL AND CAST(user_id AS TEXT) LIKE ?)
		ORDER BY user_id
	`, searchPattern, searchPattern)

	if err != nil {
		return nil, fmt.Errorf("failed to search users: %w", err)
	}
	defer rows.Close()

	var users []*internal.User
	for rows.Next() {
		var user internal.User
		var userIDFromDB sql.NullInt64
		var premiumExpires sql.NullTime
		var premiumReason sql.NullString

		err := rows.Scan(&userIDFromDB, &user.Username, &user.UserLevel, &premiumExpires, &premiumReason, &user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}

		if userIDFromDB.Valid {
			user.UserID = userIDFromDB.Int64
		} else {
			user.UserID = 0
		}

		if premiumExpires.Valid {
			user.PremiumExpiresAt = &premiumExpires.Time
		}

		if premiumReason.Valid {
			user.PremiumReason = &premiumReason.String
		}

		users = append(users, &user)
	}

	return users, nil
}

func (ur *UserRepository) MarkUserConfigDeleted(userID int64) error {
	_, err := ur.db.Exec(`
		UPDATE users
		SET updated_at = datetime(0, 'unixepoch')
		WHERE user_id = ?
	`, userID)

	if err != nil {
		return fmt.Errorf("failed to mark user config as deleted: %w", err)
	}

	return nil
}

func (ur *UserRepository) GetUsersWithDeletionMarker() ([]*internal.User, error) {
	rows, err := ur.db.Query(`
		SELECT user_id, username, user_level, premium_expires_at, premium_reason, created_at, updated_at
		FROM users
		WHERE updated_at = datetime(0, 'unixepoch')
		ORDER BY user_id
	`)

	if err != nil {
		return nil, fmt.Errorf("failed to get users with deletion marker: %w", err)
	}
	defer rows.Close()

	var users []*internal.User
	for rows.Next() {
		var user internal.User
		var userIDFromDB sql.NullInt64
		var premiumExpires sql.NullTime
		var premiumReason sql.NullString

		err := rows.Scan(&userIDFromDB, &user.Username, &user.UserLevel, &premiumExpires, &premiumReason, &user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}

		if userIDFromDB.Valid {
			user.UserID = userIDFromDB.Int64
		} else {
			user.UserID = 0
		}

		if premiumExpires.Valid {
			user.PremiumExpiresAt = &premiumExpires.Time
		}

		if premiumReason.Valid {
			user.PremiumReason = &premiumReason.String
		}

		users = append(users, &user)
	}

	return users, nil
}

func (ur *UserRepository) HasPrivilege(userID int64, privilege internal.UserLevel) (bool, error) {
	var userLevel string
	var expiresAt sql.NullTime

	err := ur.db.QueryRow(`
		SELECT user_level, premium_expires_at
		FROM users
		WHERE user_id = ?
	`, userID).Scan(&userLevel, &expiresAt)

	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("failed to check privilege: %w", err)
	}

	currentLevel := internal.UserLevel(userLevel)

	switch privilege {
	case internal.Basic:
		return true, nil
	case internal.Premium:
		if currentLevel != internal.Premium {
			return false, nil
		}
		if !expiresAt.Valid {
			return true, nil
		}
		return time.Now().Before(expiresAt.Time), nil
	case internal.Moderator:
		return currentLevel == internal.Moderator || currentLevel == internal.Admin, nil
	case internal.Admin:
		return currentLevel == internal.Admin, nil
	default:
		return false, nil
	}
}

func (ur *UserRepository) CleanupExpiredPremium() (int, error) {
	result, err := ur.db.Exec(`
		UPDATE users
		SET user_level = ?
		WHERE user_level = ?
		  AND premium_expires_at IS NOT NULL
		  AND premium_expires_at < CURRENT_TIMESTAMP
	`, internal.Basic, internal.Premium)

	if err != nil {
		return 0, fmt.Errorf("failed to cleanup expired premium: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("failed to get rows affected: %w", err)
	}

	return int(rowsAffected), nil
}

func (ur *UserRepository) GetExpiredPremiumUsers() ([]*internal.User, error) {
	rows, err := ur.db.Query(`
		SELECT user_id, username, user_level, premium_expires_at, premium_reason, created_at, updated_at
		FROM users
		WHERE user_level = ?
		  AND premium_expires_at IS NOT NULL
		  AND premium_expires_at < CURRENT_TIMESTAMP
		ORDER BY premium_expires_at DESC
	`, internal.Premium)

	if err != nil {
		return nil, fmt.Errorf("failed to get expired premium users: %w", err)
	}
	defer rows.Close()

	var users []*internal.User
	for rows.Next() {
		var user internal.User
		var userIDFromDB sql.NullInt64
		var premiumExpires sql.NullTime
		var premiumReason sql.NullString

		err := rows.Scan(&userIDFromDB, &user.Username, &user.UserLevel, &premiumExpires, &premiumReason, &user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}

		if userIDFromDB.Valid {
			user.UserID = userIDFromDB.Int64
		} else {
			user.UserID = 0
		}

		if premiumExpires.Valid {
			user.PremiumExpiresAt = &premiumExpires.Time
		}

		if premiumReason.Valid {
			user.PremiumReason = &premiumReason.String
		}

		users = append(users, &user)
	}

	return users, nil
}

func (ur *UserRepository) SetUserLevel(userID int64, level string) error {
	_, err := ur.db.Exec(`
		UPDATE users
		SET user_level = ?
		WHERE user_id = ?
	`, level, userID)

	if err != nil {
		return fmt.Errorf("failed to set user level: %w", err)
	}

	return nil
}

func (ur *UserRepository) GetAllUsers() ([]*internal.User, error) {
	rows, err := ur.db.Query(`
		SELECT user_id, username, user_level, premium_expires_at, premium_reason, created_at, updated_at
		FROM users
		ORDER BY created_at DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to get all users: %w", err)
	}
	defer rows.Close()

	var users []*internal.User
	for rows.Next() {
		var user internal.User
		var userIDFromDB sql.NullInt64
		var premiumExpires sql.NullTime
		var premiumReason sql.NullString

		err := rows.Scan(&userIDFromDB, &user.Username, &user.UserLevel, &premiumExpires, &premiumReason, &user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}

		if userIDFromDB.Valid {
			user.UserID = userIDFromDB.Int64
		} else {
			user.UserID = 0
		}

		if premiumExpires.Valid {
			user.PremiumExpiresAt = &premiumExpires.Time
		}

		if premiumReason.Valid {
			user.PremiumReason = &premiumReason.String
		}

		users = append(users, &user)
	}

	return users, nil
}

func (ur *UserRepository) GetModeratorAndAdminUsers() ([]*internal.User, error) {
	rows, err := ur.db.Query(`
		SELECT user_id, username, user_level, premium_expires_at, premium_reason, created_at, updated_at
		FROM users
		WHERE user_level IN ('moderator', 'admin')
		ORDER BY user_id
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to get moderator and admin users: %w", err)
	}
	defer rows.Close()

	var users []*internal.User
	for rows.Next() {
		var user internal.User
		var userIDFromDB sql.NullInt64
		var premiumExpires sql.NullTime
		var premiumReason sql.NullString

		err := rows.Scan(&userIDFromDB, &user.Username, &user.UserLevel, &premiumExpires, &premiumReason, &user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}

		if userIDFromDB.Valid {
			user.UserID = userIDFromDB.Int64
		} else {
			user.UserID = 0
		}

		if premiumExpires.Valid {
			user.PremiumExpiresAt = &premiumExpires.Time
		}

		if premiumReason.Valid {
			user.PremiumReason = &premiumReason.String
		}

		users = append(users, &user)
	}

	return users, nil
}

func (ur *UserRepository) SetPremiumStatus(userID int64, expiresAt *time.Time, reason string) error {
	var expiresAtVal *time.Time
	if expiresAt != nil && !expiresAt.IsZero() {
		expiresAtVal = expiresAt
	}

	var reasonVal *string
	if reason != "" {
		reasonVal = &reason
	}

	_, err := ur.db.Exec(`
		UPDATE users
		SET user_level = ?, premium_expires_at = ?, premium_reason = ?
		WHERE user_id = ?
	`, internal.Premium, expiresAtVal, reasonVal, userID)

	if err != nil {
		return fmt.Errorf("failed to set premium status: %w", err)
	}

	return nil
}
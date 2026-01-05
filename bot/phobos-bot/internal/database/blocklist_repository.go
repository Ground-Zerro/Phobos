package database

import (
	"database/sql"
	"fmt"
	"time"
)

type BlockedUser struct {
	UserID    int64     `json:"user_id"`
	Username  string    `json:"username"`
	Reason    string    `json:"reason"`
	BlockedAt time.Time `json:"blocked_at"`
	BlockedBy int64     `json:"blocked_by"`
}

type BlocklistRepository struct {
	db *sql.DB
}

func NewBlocklistRepository(db *sql.DB) *BlocklistRepository {
	return &BlocklistRepository{
		db: db,
	}
}

func (br *BlocklistRepository) IsBlocked(userID int64, username string) (bool, error) {
	var userLevel string
	var premiumExpiresAt sql.NullTime

	if userID != 0 {
		err := br.db.QueryRow(`
			SELECT user_level, premium_expires_at FROM users WHERE user_id = ?
		`, userID).Scan(&userLevel, &premiumExpiresAt)

		if err != nil {
			if err == sql.ErrNoRows {
				return false, nil
			}
			return false, fmt.Errorf("failed to check user block status by user_id: %w", err)
		}

		if userLevel == "ban" {
			if !premiumExpiresAt.Valid {
				return true, nil
			}
			if time.Now().Before(premiumExpiresAt.Time) {
				return true, nil
			}
			return false, nil
		}
	}

	if username != "" {
		err := br.db.QueryRow(`
			SELECT user_level, premium_expires_at FROM users WHERE username = ? AND user_id IS NULL
		`, username).Scan(&userLevel, &premiumExpiresAt)

		if err != nil {
			if err == sql.ErrNoRows {
				return false, nil
			}
			return false, fmt.Errorf("failed to check user block status by username: %w", err)
		}

		if userLevel == "ban" {
			if !premiumExpiresAt.Valid {
				return true, nil
			}
			if time.Now().Before(premiumExpiresAt.Time) {
				return true, nil
			}
			return false, nil
		}
	}

	return false, nil
}

func (br *BlocklistRepository) AddToBlocklist(userID int64, username, reason string, blockedBy int64) error {
	var reasonVal *string
	if reason != "" {
		reasonVal = &reason
	}

	_, err := br.db.Exec(`
		UPDATE users
		SET user_level = 'ban',
		    premium_expires_at = NULL,
		    premium_reason = ?,
		    updated_at = CURRENT_TIMESTAMP
		WHERE user_id = ?
	`, reasonVal, userID)

	if err != nil {
		return fmt.Errorf("failed to block user: %w", err)
	}

	return nil
}

func (br *BlocklistRepository) RemoveFromBlocklist(userID int64) error {
	_, err := br.db.Exec(`
		UPDATE users
		SET user_level = 'basic',
		    premium_expires_at = NULL,
		    premium_reason = NULL,
		    updated_at = CURRENT_TIMESTAMP
		WHERE user_id = ? AND user_level = 'ban'
	`, userID)

	if err != nil {
		return fmt.Errorf("failed to unblock user: %w", err)
	}

	return nil
}

func (br *BlocklistRepository) GetBlockedUsers(limit, offset int) ([]BlockedUser, error) {
	query := `
		SELECT user_id, username, updated_at
		FROM users
		WHERE user_level = 'ban'
		ORDER BY updated_at DESC
		LIMIT ? OFFSET ?
	`

	rows, err := br.db.Query(query, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to get blocked users: %w", err)
	}
	defer rows.Close()

	var blockedUsers []BlockedUser
	for rows.Next() {
		var blockedUser BlockedUser
		var blockedAt time.Time

		err := rows.Scan(&blockedUser.UserID, &blockedUser.Username, &blockedAt)
		if err != nil {
			return nil, fmt.Errorf("failed to scan blocked user: %w", err)
		}
		blockedUser.BlockedAt = blockedAt
		blockedUser.Reason = ""
		blockedUser.BlockedBy = 0

		blockedUsers = append(blockedUsers, blockedUser)
	}

	return blockedUsers, nil
}

func (br *BlocklistRepository) GetUserBlockInfo(userID int64) (*BlockedUser, bool, error) {
	row := br.db.QueryRow(`
		SELECT user_id, username, updated_at
		FROM users
		WHERE user_id = ? AND user_level = 'ban'
	`, userID)

	var blockedUser BlockedUser
	var blockedAt time.Time

	err := row.Scan(&blockedUser.UserID, &blockedUser.Username, &blockedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, false, nil
		}
		return nil, false, fmt.Errorf("failed to get user block info: %w", err)
	}
	blockedUser.BlockedAt = blockedAt
	blockedUser.Reason = ""
	blockedUser.BlockedBy = 0

	return &blockedUser, true, nil
}
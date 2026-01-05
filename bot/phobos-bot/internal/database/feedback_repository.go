package database

import (
	"database/sql"
	"fmt"
	"time"

	"phobos-bot/internal"
)

type FeedbackRepository struct {
	db *sql.DB
}

func NewFeedbackRepository(db *sql.DB) *FeedbackRepository {
	return &FeedbackRepository{
		db: db,
	}
}

func (fr *FeedbackRepository) SaveFeedback(feedback internal.Feedback) error {
	_, err := fr.db.Exec(`
		INSERT INTO feedback (user_id, message, created_at)
		VALUES (?, ?, ?)
	`, feedback.UserID, feedback.Message, feedback.Timestamp)

	if err != nil {
		return fmt.Errorf("failed to save feedback: %w", err)
	}

	return nil
}

func (fr *FeedbackRepository) GetFeedbackByUser(userID int64) ([]internal.Feedback, error) {
	query := `
		SELECT id, user_id, message, processed, response, responded_at, responded_by, created_at
		FROM feedback
		WHERE user_id = ?
		ORDER BY created_at DESC
	`

	rows, err := fr.db.Query(query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get feedback by user: %w", err)
	}
	defer rows.Close()

	var feedbacks []internal.Feedback
	for rows.Next() {
		var feedback internal.Feedback
		var timestamp time.Time
		var response sql.NullString
		var respondedAt sql.NullTime
		var respondedBy sql.NullInt64

		err := rows.Scan(&feedback.ID, &feedback.UserID, &feedback.Message, &feedback.Processed, &response, &respondedAt, &respondedBy, &timestamp)
		if err != nil {
			return nil, fmt.Errorf("failed to scan feedback: %w", err)
		}
		feedback.Timestamp = timestamp
		if response.Valid {
			feedback.Response = &response.String
		}
		if respondedAt.Valid {
			feedback.RespondedAt = &respondedAt.Time
		}
		if respondedBy.Valid {
			feedback.RespondedBy = &respondedBy.Int64
		}

		feedbacks = append(feedbacks, feedback)
	}

	return feedbacks, nil
}

func (fr *FeedbackRepository) GetAllFeedback(limit int, offset int) ([]internal.Feedback, error) {
	query := `
		SELECT id, user_id, message, processed, response, responded_at, responded_by, created_at
		FROM feedback
		ORDER BY created_at DESC
		LIMIT ? OFFSET ?
	`

	rows, err := fr.db.Query(query, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to get all feedback: %w", err)
	}
	defer rows.Close()

	var feedbacks []internal.Feedback
	for rows.Next() {
		var feedback internal.Feedback
		var timestamp time.Time
		var response sql.NullString
		var respondedAt sql.NullTime
		var respondedBy sql.NullInt64

		err := rows.Scan(&feedback.ID, &feedback.UserID, &feedback.Message, &feedback.Processed, &response, &respondedAt, &respondedBy, &timestamp)
		if err != nil {
			return nil, fmt.Errorf("failed to scan feedback: %w", err)
		}
		feedback.Timestamp = timestamp
		if response.Valid {
			feedback.Response = &response.String
		}
		if respondedAt.Valid {
			feedback.RespondedAt = &respondedAt.Time
		}
		if respondedBy.Valid {
			feedback.RespondedBy = &respondedBy.Int64
		}

		feedbacks = append(feedbacks, feedback)
	}

	return feedbacks, nil
}

func (fr *FeedbackRepository) MarkFeedbackProcessed(feedbackID int64) error {
	_, err := fr.db.Exec(`
		UPDATE feedback
		SET processed = 1
		WHERE id = ?
	`, feedbackID)

	if err != nil {
		return fmt.Errorf("failed to mark feedback as processed: %w", err)
	}

	return nil
}

func (fr *FeedbackRepository) GetUnprocessedFeedback(limit int) ([]internal.Feedback, error) {
	query := `
		SELECT id, user_id, message, processed, response, responded_at, responded_by, created_at
		FROM feedback
		WHERE processed = 0
		ORDER BY created_at DESC
		LIMIT ?
	`

	rows, err := fr.db.Query(query, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to get unprocessed feedback: %w", err)
	}
	defer rows.Close()

	var feedbacks []internal.Feedback
	for rows.Next() {
		var feedback internal.Feedback
		var timestamp time.Time
		var response sql.NullString
		var respondedAt sql.NullTime
		var respondedBy sql.NullInt64

		err := rows.Scan(&feedback.ID, &feedback.UserID, &feedback.Message, &feedback.Processed, &response, &respondedAt, &respondedBy, &timestamp)
		if err != nil {
			return nil, fmt.Errorf("failed to scan feedback: %w", err)
		}
		feedback.Timestamp = timestamp
		if response.Valid {
			feedback.Response = &response.String
		}
		if respondedAt.Valid {
			feedback.RespondedAt = &respondedAt.Time
		}
		if respondedBy.Valid {
			feedback.RespondedBy = &respondedBy.Int64
		}

		feedbacks = append(feedbacks, feedback)
	}

	return feedbacks, nil
}

func (fr *FeedbackRepository) RespondToFeedback(feedbackID int64, response string, respondedBy int64) error {
	_, err := fr.db.Exec(`
		UPDATE feedback
		SET response = ?, responded_at = CURRENT_TIMESTAMP, responded_by = ?, processed = 1
		WHERE id = ?
	`, response, respondedBy, feedbackID)

	if err != nil {
		return fmt.Errorf("failed to respond to feedback: %w", err)
	}

	return nil
}

func (fr *FeedbackRepository) GetFeedbackByID(feedbackID int64) (*internal.Feedback, error) {
	query := `
		SELECT id, user_id, message, processed, response, responded_at, responded_by, created_at
		FROM feedback
		WHERE id = ?
	`

	var feedback internal.Feedback
	var timestamp time.Time
	var response sql.NullString
	var respondedAt sql.NullTime
	var respondedBy sql.NullInt64

	err := fr.db.QueryRow(query, feedbackID).Scan(&feedback.ID, &feedback.UserID, &feedback.Message, &feedback.Processed, &response, &respondedAt, &respondedBy, &timestamp)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("feedback not found")
		}
		return nil, fmt.Errorf("failed to get feedback by ID: %w", err)
	}

	feedback.Timestamp = timestamp
	if response.Valid {
		feedback.Response = &response.String
	}
	if respondedAt.Valid {
		feedback.RespondedAt = &respondedAt.Time
	}
	if respondedBy.Valid {
		feedback.RespondedBy = &respondedBy.Int64
	}

	return &feedback, nil
}
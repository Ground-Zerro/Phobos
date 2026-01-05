package internal

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

type userRateLimit struct {
	lastCommandTime map[string]time.Time
	lastCreateTime  time.Time
	mu              sync.Mutex
}

type rateLimiter struct {
	users      map[int64]*userRateLimit
	mu         sync.RWMutex
	configRepo ConfigRepository
}

func newRateLimiter(configRepo ConfigRepository) *rateLimiter {
	return &rateLimiter{
		users:      make(map[int64]*userRateLimit),
		configRepo: configRepo,
	}
}

func (rl *rateLimiter) canExecuteCommand(userID int64, command string) bool {
	intervalMinutes, err := rl.configRepo.GetInt("rate_limit_interval_minutes")
	if err != nil {
		intervalMinutes = 1
	}

	rateLimitedCommandsStr, err := rl.configRepo.GetString("rate_limited_commands")
	if err != nil {
		rateLimitedCommandsStr = "create,stat"
	}

	rateLimitedCommands := strings.Split(rateLimitedCommandsStr, ",")
	isRateLimited := false
	for _, cmd := range rateLimitedCommands {
		if strings.TrimSpace(cmd) == command {
			isRateLimited = true
			break
		}
	}

	if !isRateLimited {
		return true
	}

	rl.mu.Lock()
	if _, exists := rl.users[userID]; !exists {
		rl.users[userID] = &userRateLimit{
			lastCommandTime: make(map[string]time.Time),
		}
	}
	rl.mu.Unlock()

	user := rl.users[userID]
	user.mu.Lock()
	defer user.mu.Unlock()

	lastTime, exists := user.lastCommandTime[command]
	if exists && time.Since(lastTime) < time.Duration(intervalMinutes)*time.Minute {
		return false
	}

	user.lastCommandTime[command] = time.Now()
	return true
}
func (rl *rateLimiter) cleanup() {
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		for userID, user := range rl.users {
			user.mu.Lock()
			if time.Since(user.lastCreateTime) > 24*time.Hour {
				delete(rl.users, userID)
			}
			user.mu.Unlock()
		}
		rl.mu.Unlock()
	}
}

func sendMessageWithHTML(bot BotAPI, chatID int64, text string) {
	msg := tgbotapi.NewMessage(chatID, text)
	if strings.ContainsAny(text, "<>") {
		msg.ParseMode = "HTML"
	}
	msg.DisableWebPagePreview = true
	bot.Send(msg)
}

func (h *BotHandler) sendMessageAndTrack(chatID int64, userID int64, text string) int {
	msg := tgbotapi.NewMessage(chatID, text)
	if strings.ContainsAny(text, "<>") {
		msg.ParseMode = "HTML"
	}
	msg.DisableWebPagePreview = true
	sentMsg, err := h.bot.Send(msg)
	if err != nil {
		return 0
	}

	h.mu.Lock()
	if state, exists := h.userStates[userID]; exists {
		state.LastBotMessageID = sentMsg.MessageID
	} else {
		h.userStates[userID] = &UserState{
			LastBotMessageID: sentMsg.MessageID,
		}
	}
	h.mu.Unlock()

	return sentMsg.MessageID
}

type stateType int

const (
	confirmationStateType stateType = iota
	feedbackStateType
	deletionStateType
	feedbackResponseStateType
	feedbackSetDateStateType
)

type UserState struct {
	StateType        stateType
	ClientName       string
	InProgress       bool
	LastBotMessageID int
	FeedbackID       int64
	TargetUserID     int64
	TargetUserLevel  string
}

type BotHandler struct {
	bot                BotAPI
	config             BotConfig
	userRepo           UserRepository
	logRepo            LogRepository
	scriptRunner       ScriptRunner
	messageManager     *DatabaseMessageManager
	feedbackRepo       FeedbackRepository
	blocklistRepo      BlocklistRepository
	configRepo         ConfigRepository
	scriptRepo         ScriptRepository
	rateLimiter        *rateLimiter
	userStates         map[int64]*UserState
	mu                 sync.RWMutex
	cachedBotName      string
	wgService          WireGuardService
}

// DatabaseMessageManager is defined in the database package

func NewBotHandler(
	bot BotAPI,
	config BotConfig,
	userRepo UserRepository,
	logRepo LogRepository,
	scriptRunner ScriptRunner,
	messageManager *DatabaseMessageManager,
	feedbackRepo FeedbackRepository,
	blocklistRepo BlocklistRepository,
	configRepo ConfigRepository,
	scriptRepo ScriptRepository,
	wgService WireGuardService,
) *BotHandler {
	botName, _ := messageManager.GetMessage("bot_name", nil)
	rl := newRateLimiter(configRepo)
	go rl.cleanup()
	return &BotHandler{
		bot:            bot,
		config:         config,
		userRepo:       userRepo,
		logRepo:        logRepo,
		scriptRunner:   scriptRunner,
		messageManager: messageManager,
		feedbackRepo:   feedbackRepo,
		blocklistRepo:  blocklistRepo,
		configRepo:     configRepo,
		scriptRepo:     scriptRepo,
		rateLimiter:    rl,
		userStates:     make(map[int64]*UserState),
		cachedBotName:  botName,
		wgService:      wgService,
	}
}

func (h *BotHandler) isBlockedUser(userID int64, username string, chatID int64, timestamp time.Time, command string) bool {
	isBlocked, err := h.blocklistRepo.IsBlocked(userID, username)
	if err != nil {
		// For blocklist checking, if there's an error, we'll log it but continue without blocking
		// This is reasonable behavior as we don't want to block users due to database errors
		h.logRepo.LogEvent(LogEvent{
			Timestamp: timestamp,
			UserID:    userID,
			Username:  username,
			Command:   "blocklist_check_error",
			Error:     err.Error(),
		})
		return false
	}

	if isBlocked {
		blockedText, _ := h.messageManager.GetMessage("blocked_user", nil)
		msg := tgbotapi.NewMessage(chatID, blockedText)
		h.bot.Send(msg)
		h.logRepo.LogEvent(LogEvent{
			Timestamp: timestamp,
			UserID:    userID,
			Username:  username,
			Command:   command,
			Error:     "User is blocked",
		})
		return true
	}
	return false
}

func (h *BotHandler) HandleMessage(update tgbotapi.Update) {
	if update.Message == nil {
		return
	}

	// Auto-register user if they don't exist
	err := h.userRepo.RegisterUser(update.Message.From.ID, update.Message.From.UserName)
	if err != nil {
		// If user registration fails, log the error but continue processing
		// We don't want to stop processing messages just because of a DB error
		h.logRepo.LogEvent(LogEvent{
			Timestamp: update.Message.Time(),
			UserID:    update.Message.From.ID,
			Username:  update.Message.From.UserName,
			Command:   "user_registration_error",
			Error:     err.Error(),
		})
	}

	if h.isBlockedUser(update.Message.From.ID, update.Message.From.UserName, update.Message.Chat.ID, update.Message.Time(), "blocked_attempt") {
		return
	}

	clientName := h.getClientName(update.Message.From)

	h.mu.RLock()
	userState, exists := h.userStates[update.Message.From.ID]
	h.mu.RUnlock()

	if exists && userState.StateType == feedbackStateType && !update.Message.IsCommand() {
		feedback := Feedback{
			UserID:    update.Message.From.ID,
			Username:  update.Message.From.UserName,
			Timestamp: update.Message.Time(),
			Message:   update.Message.Text,
		}

		err := h.feedbackRepo.SaveFeedback(feedback)
		if err != nil {
			h.logRepo.LogEvent(LogEvent{
				Timestamp: update.Message.Time(),
				UserID:    update.Message.From.ID,
				Username:  update.Message.From.UserName,
				Command:   "feedback_save_error",
				Error:     err.Error(),
			})
			feedbackErrorText, _ := h.messageManager.GetMessage("feedback_error", nil)
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, feedbackErrorText)
		} else {
			h.mu.Lock()
			delete(h.userStates, update.Message.From.ID)
			h.mu.Unlock()
			feedbackReceivedText, _ := h.messageManager.GetMessage("feedback_received", nil)
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, feedbackReceivedText)

			moderatorsAndAdmins, err := h.userRepo.GetModeratorAndAdminUsers()
			if err == nil {
				feedbackID := int64(0)
				latestFeedbacks, fbErr := h.feedbackRepo.GetFeedbackByUser(update.Message.From.ID)
				if fbErr == nil && len(latestFeedbacks) > 0 {
					feedbackID = latestFeedbacks[0].ID
				}

				senderUser, senderErr := h.userRepo.GetUserByUserID(update.Message.From.ID)
				isModeratorOrAdmin := false
				if senderErr == nil && (senderUser.UserLevel == string(Moderator) || senderUser.UserLevel == string(Admin)) {
					isModeratorOrAdmin = true
				}

				for _, admin := range moderatorsAndAdmins {
					go func(adminUser *User, fbID int64, isModerator bool) {
						notificationText := fmt.Sprintf(
							"📬 Новая обратная связь\n\n"+
								"От: @%s (ID: %d)\n"+
								"Время: %s\n\n"+
								"Сообщение:\n%s",
							update.Message.From.UserName,
							update.Message.From.ID,
							update.Message.Time().Format("2006-01-02 15:04:05"),
							update.Message.Text,
						)

						var keyboard tgbotapi.InlineKeyboardMarkup
						if isModerator {
							keyboard = tgbotapi.NewInlineKeyboardMarkup(
								tgbotapi.NewInlineKeyboardRow(
									tgbotapi.NewInlineKeyboardButtonData("✅ Прочитано", fmt.Sprintf("fb_read_%d", fbID)),
								),
							)
						} else {
							keyboard = tgbotapi.NewInlineKeyboardMarkup(
								tgbotapi.NewInlineKeyboardRow(
									tgbotapi.NewInlineKeyboardButtonData("💬 Ответить", fmt.Sprintf("fb_reply_%d", fbID)),
									tgbotapi.NewInlineKeyboardButtonData("👤 Сменить уровень", fmt.Sprintf("fb_level_%d", fbID)),
								),
								tgbotapi.NewInlineKeyboardRow(
									tgbotapi.NewInlineKeyboardButtonData("🗑 Удалить конфиг", fmt.Sprintf("fb_delete_%d", fbID)),
									tgbotapi.NewInlineKeyboardButtonData("✅ Прочитано", fmt.Sprintf("fb_read_%d", fbID)),
								),
							)
						}

						msg := tgbotapi.NewMessage(adminUser.UserID, notificationText)
						msg.DisableWebPagePreview = true
						msg.ReplyMarkup = keyboard
						_, sendErr := h.bot.Send(msg)
						if sendErr == nil {
							h.logRepo.LogEvent(LogEvent{
								Timestamp:  update.Message.Time(),
								UserID:     adminUser.UserID,
								Username:   adminUser.Username,
								ClientName: clientName,
								Command:    "feedback_notification_sent",
							})
						}
					}(admin, feedbackID, isModeratorOrAdmin)
				}
			}
		}

		logEvent := LogEvent{
			Timestamp:  update.Message.Time(),
			UserID:     update.Message.From.ID,
			Username:   update.Message.From.UserName,
			ClientName: clientName,
			Command:    "feedback_sent",
		}
		h.logRepo.LogEvent(logEvent)
		return
	}

	if exists && userState.StateType == feedbackResponseStateType && !update.Message.IsCommand() {
		responseText := update.Message.Text

		targetUser, err := h.userRepo.GetUserByUserID(userState.TargetUserID)
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка: пользователь не найден")
			h.mu.Lock()
			delete(h.userStates, update.Message.From.ID)
			h.mu.Unlock()
			return
		}

		supportResponseText, _ := h.messageManager.GetMessage("feedback_support_response", map[string]interface{}{
			"response": responseText,
		})

		msg := tgbotapi.NewMessage(userState.TargetUserID, supportResponseText)
		msg.ParseMode = "HTML"
		msg.DisableWebPagePreview = true
		_, sendErr := h.bot.Send(msg)
		if sendErr != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка отправки сообщения пользователю")
			h.logRepo.LogEvent(LogEvent{
				Timestamp: update.Message.Time(),
				UserID:    update.Message.From.ID,
				Username:  update.Message.From.UserName,
				Command:   "feedback_send_error",
				Error:     sendErr.Error(),
			})
			h.mu.Lock()
			delete(h.userStates, update.Message.From.ID)
			h.mu.Unlock()
			return
		}

		err = h.feedbackRepo.RespondToFeedback(userState.FeedbackID, responseText, update.Message.From.ID)
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка сохранения ответа")
			return
		}

		sentConfirmText, _ := h.messageManager.GetMessage("feedback_response_sent", map[string]interface{}{
			"username": targetUser.Username,
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, sentConfirmText)

		h.mu.Lock()
		delete(h.userStates, update.Message.From.ID)
		h.mu.Unlock()

		h.logRepo.LogEvent(LogEvent{
			Timestamp:    update.Message.Time(),
			UserID:       update.Message.From.ID,
			Username:     update.Message.From.UserName,
			Command:      "feedback_responded",
			ScriptOutput: responseText,
		})
		return
	}

	if exists && userState.StateType == feedbackSetDateStateType && !update.Message.IsCommand() {
		if h.checkFeedbackProcessed(userState.FeedbackID, update.Message.Chat.ID) {
			h.mu.Lock()
			delete(h.userStates, update.Message.From.ID)
			h.mu.Unlock()
			return
		}

		dateStr := update.Message.Text
		parsedDate, err := parseDateString(dateStr)
		if err != nil {
			invalidDateText, _ := h.messageManager.GetMessage("feedback_invalid_date", nil)
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, invalidDateText)

			deleteMsg := tgbotapi.NewDeleteMessage(update.Message.Chat.ID, update.Message.MessageID)
			h.bot.Send(deleteMsg)
			return
		}

		feedback, err := h.feedbackRepo.GetFeedbackByID(userState.FeedbackID)
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка: обратная связь не найдена")
			h.mu.Lock()
			delete(h.userStates, update.Message.From.ID)
			h.mu.Unlock()
			return
		}

		feedbackUser, err := h.userRepo.GetUserByUserID(feedback.UserID)
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка: пользователь не найден")
			h.mu.Lock()
			delete(h.userStates, update.Message.From.ID)
			h.mu.Unlock()
			return
		}

		level := userState.TargetUserLevel

		err = h.userRepo.SetUserLevel(feedback.UserID, level)
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка установки уровня")
			h.logRepo.LogEvent(LogEvent{
				Timestamp: update.Message.Time(),
				UserID:    update.Message.From.ID,
				Username:  update.Message.From.UserName,
				Command:   "feedback_level_change_error",
				Error:     err.Error(),
			})
			h.mu.Lock()
			delete(h.userStates, update.Message.From.ID)
			h.mu.Unlock()
			return
		}

		if level == "premium" || level == "ban" {
			err = h.userRepo.SetPremiumStatus(feedback.UserID, &parsedDate, fmt.Sprintf("Set by moderator %s", update.Message.From.UserName))
			if err != nil {
				sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка установки статуса premium")
				h.mu.Lock()
				delete(h.userStates, update.Message.From.ID)
				h.mu.Unlock()
				return
			}
		}

		responseText := fmt.Sprintf("User level changed to %s until %s", level, parsedDate.Format("2006-01-02 15:04"))
		err = h.feedbackRepo.RespondToFeedback(userState.FeedbackID, responseText, update.Message.From.ID)
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка сохранения ответа")
			return
		}

		successText, _ := h.messageManager.GetMessage("feedback_level_changed", map[string]interface{}{
			"username":   feedbackUser.Username,
			"user_id":    feedback.UserID,
			"level":      level,
			"expires_at": parsedDate.Format("2006-01-02 15:04"),
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, successText)

		h.mu.Lock()
		delete(h.userStates, update.Message.From.ID)
		h.mu.Unlock()

		h.logRepo.LogEvent(LogEvent{
			Timestamp:    update.Message.Time(),
			UserID:       update.Message.From.ID,
			Username:     update.Message.From.UserName,
			Command:      "feedback_level_changed",
			ScriptOutput: responseText,
		})
		return
	}

	command := update.Message.Command()

	if update.Message.IsCommand() {
		deleteMsg := tgbotapi.NewDeleteMessage(
			update.Message.Chat.ID,
			update.Message.MessageID,
		)
		_, _ = h.bot.Send(deleteMsg)

		h.mu.Lock()
		if state, exists := h.userStates[update.Message.From.ID]; exists && state.LastBotMessageID != 0 {
			deleteBotMsg := tgbotapi.NewDeleteMessage(
				update.Message.Chat.ID,
				state.LastBotMessageID,
			)
			_, _ = h.bot.Send(deleteBotMsg)
			state.LastBotMessageID = 0
		}
		h.mu.Unlock()
	}

	logEvent := LogEvent{
		Timestamp:  update.Message.Time(),
		UserID:     update.Message.From.ID,
		Username:   update.Message.From.UserName,
		ClientName: clientName,
		Command:    command,
	}

	// Get user level for logging
	user, err := h.userRepo.GetUserByUserID(update.Message.From.ID)
	if err != nil {
		logEvent.UserLevel = "unknown"
	} else {
		logEvent.UserLevel = user.UserLevel
	}

	switch command {
	case "start":
		h.handleStart(update, user)
		logEvent.Command = "start"
	case "create":
		h.handleCreate(update, clientName, user)
		logEvent.Command = "create"
	case "help":
		h.handleHelp(update)
		logEvent.Command = "help"
	case "info":
		h.handleInfo(update)
		logEvent.Command = "info"
	case "selfhost":
		h.handleSelfhost(update)
		logEvent.Command = "selfhost"
	case "stat":
		h.handleStat(update, clientName, user)
		logEvent.Command = "stat"
	case "feedback":
		h.handleFeedback(update)
		h.mu.Lock()
		h.userStates[update.Message.From.ID] = &UserState{
			StateType:  feedbackStateType,
			InProgress: false,
		}
		h.mu.Unlock()
		logEvent.Command = "feedback"
	case "premium":
		h.handlePremium(update)
		logEvent.Command = "premium"
	case "delete":
		h.handleDelete(update, clientName, user)
		logEvent.Command = "delete"
	case "logs":
		h.handleLogs(update, user)
		logEvent.Command = "logs"
	case "users":
		h.handleUsers(update, user)
		logEvent.Command = "users"
	case "feedbacklist":
		h.handleFeedbackList(update, user)
		logEvent.Command = "feedbacklist"
	case "setlevel":
		h.handleSetLevel(update, user)
		logEvent.Command = "setlevel"
	case "setpremium":
		h.handleSetPremium(update, user)
		logEvent.Command = "setpremium"
	case "block":
		h.handleBlock(update, user)
		logEvent.Command = "block"
	case "unblock":
		h.handleUnblock(update, user)
		logEvent.Command = "unblock"
	case "config":
		h.handleConfig(update, user)
		logEvent.Command = "config"
	case "stats":
		h.handleStats(update, user)
		logEvent.Command = "stats"
	case "cleanuplogs":
		h.handleCleanupLogs(update, user)
		logEvent.Command = "cleanuplogs"
	case "backup":
		h.handleBackup(update, user)
		logEvent.Command = "backup"
	case "admin":
		h.handleAdmin(update, user)
		logEvent.Command = "admin"
	default:
		unknownText, _ := h.messageManager.GetMessage("unknown_command", nil)
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, unknownText)
		logEvent.Command = "unknown_command"
	}

	h.logRepo.LogEvent(logEvent)
}

func (h *BotHandler) getClientName(user *tgbotapi.User) string {
	if user.UserName != "" {
		return user.UserName
	}
	return strconv.FormatInt(user.ID, 10)
}

func (h *BotHandler) handleStart(update tgbotapi.Update, user *User) {
	// Use config values from h.config instead of database
	maxClients := h.config.MaxClients
	if h.config.MaxTestDuration > 0 && user.UserLevel != string(Premium) {
		// In this case, we'll use the config's MaxTestDuration as a way to determine
		// how many max clients to show based on the test duration settings
		// Or we could retrieve this from database if needed
		// For now, we'll use a default approach or the existing count logic
	}

	currentClients := h.countClients(user.UserLevel == string(Premium))
	availableSlots := maxClients - currentClients
	if availableSlots < 0 {
		availableSlots = 0
	}

	watchdogThresholdHours := int(h.config.WatchdogInactiveThreshold.Hours())
	maxTestDurationHours := int(h.config.MaxTestDuration.Hours())

	welcomeText, err := h.messageManager.GetMessage("start_welcome", map[string]interface{}{
		"bot_name":                  h.cachedBotName,
		"max_clients":               maxClients,
		"available_slots":           availableSlots,
		"watchdog_threshold_hours":  watchdogThresholdHours,
		"max_test_duration_hours":   maxTestDurationHours,
	})
	if err != nil {
		log.Printf("Error getting start_welcome template: %v", err)
		welcomeText = "Ошибка загрузки сообщения приветствия. Попробуйте позже."
	}
	h.sendMessageAndTrack(update.Message.Chat.ID, update.Message.From.ID, welcomeText)
}

func (h *BotHandler) countClients(isPremium bool) int {
	if isPremium {
		return 0
	}

	entries, err := os.ReadDir(h.config.ClientsDir)
	if err != nil {
		return 0
	}

	count := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		clientName := entry.Name()
		user, err := h.userRepo.GetUserByUsername(clientName)
		if err != nil {
			users, searchErr := h.userRepo.SearchUsers(clientName)
			if searchErr != nil || len(users) == 0 {
				userID, parseErr := strconv.ParseInt(clientName, 10, 64)
				if parseErr != nil {
					count++
					continue
				}
				user, err = h.userRepo.GetUserByUserID(userID)
				if err != nil {
					count++
					continue
				}
			} else {
				user = users[0]
			}
		}

		isPremiumUser, err := h.userRepo.IsPremium(user.UserID)
		if err != nil {
			isPremiumUser = false
		}

		isProtected := isPremiumUser ||
			user.UserLevel == string(Moderator) ||
			user.UserLevel == string(Admin)

		if !isProtected {
			count++
		}
	}
	return count
}

func (h *BotHandler) handleCreate(update tgbotapi.Update, clientName string, user *User) {
	isPremium, err := h.userRepo.IsPremium(update.Message.From.ID)
	if err != nil {
		isPremium = false
	}

	// Admin and moderator users should bypass all restrictions
	isPrivileged := user.UserLevel == string(Admin) || user.UserLevel == string(Moderator)

	if !isPremium && !isPrivileged && !h.rateLimiter.canExecuteCommand(update.Message.From.ID, "create") {
		rateLimitText, _ := h.messageManager.GetMessage("create_rate_limited", nil)
		msg := tgbotapi.NewMessage(update.Message.Chat.ID, rateLimitText)
		h.bot.Send(msg)
		return
	}

	clientName = strings.ToLower(clientName)
	clientDir := fmt.Sprintf("%s/%s", h.config.ClientsDir, clientName)
	_, statErr := os.Stat(clientDir)
	isNewClient := os.IsNotExist(statErr)

	// Check if test duration limit applies - Since client_activity table is removed,
	// we can only check the user's created_at time as a proxy for when they first registered
	if !isPremium && !isPrivileged && h.config.MaxTestDuration > 0 {
		if time.Since(user.CreatedAt) >= h.config.MaxTestDuration {
			testLimitText, _ := h.messageManager.GetMessage("test_limit_exceeded", nil)
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, testLimitText)
			h.logRepo.LogEvent(LogEvent{
				Timestamp:  update.Message.Time(),
				UserID:     update.Message.From.ID,
				Username:   update.Message.From.UserName,
				ClientName: clientName,
				Command:    "create_test_limit_exceeded",
				Error:      "Test duration limit exceeded",
				IsPremium:  isPremium,
				UserLevel:  user.UserLevel,
			})
			return
		}
	}

	// Use config values from h.config instead of database
	if !isPremium && !isPrivileged && h.config.RestrictNewUsers && isNewClient {
		restrictedText, _ := h.messageManager.GetMessage("restricted_new_users", nil)
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, restrictedText)
		h.logRepo.LogEvent(LogEvent{
			Timestamp:  update.Message.Time(),
			UserID:     update.Message.From.ID,
			Username:   update.Message.From.UserName,
			ClientName: clientName,
			Command:    "create_restricted",
			Error:      "New user creation restricted",
			IsPremium:  isPremium,
			UserLevel:  user.UserLevel,
		})
		return
	}

	// Use config values from h.config instead of database
	if !isPremium && !isPrivileged && h.config.MaxClients > 0 && isNewClient {
		currentClients := h.countClients(isPremium)
		if currentClients >= h.config.MaxClients {
			restrictedText, _ := h.messageManager.GetMessage("restricted_new_users", nil)
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, restrictedText)
			h.logRepo.LogEvent(LogEvent{
				Timestamp:  update.Message.Time(),
				UserID:     update.Message.From.ID,
				Username:   update.Message.From.UserName,
				ClientName: clientName,
				Command:    "create_max_clients_reached",
				Error:      fmt.Sprintf("Max clients reached: %d/%d", currentClients, h.config.MaxClients),
				IsPremium:  isPremium,
				UserLevel:  user.UserLevel,
			})
			return
		}
	}

	ctx := context.Background()
	output, exitCode, err := h.scriptRunner.RunScript(ctx, clientName)

	if exitCode != 0 && (strings.Contains(output, "уже существует") || strings.Contains(output, "already exists")) {
		h.mu.Lock()
		h.userStates[update.Message.From.ID] = &UserState{
			StateType:  confirmationStateType,
			ClientName: clientName,
			InProgress: false,
		}
		h.mu.Unlock()

		var statusText, lastHandshake, transfer string
		stats, err := h.wgService.GetClientStats(clientName)
		if err == nil {
			switch stats.Status {
			case "active":
				statusText, _ = h.messageManager.GetMessage("stat_status_active", nil)
			case "inactive":
				statusText, _ = h.messageManager.GetMessage("stat_status_inactive", nil)
			case "never_connected":
				statusText, _ = h.messageManager.GetMessage("stat_status_never_connected", nil)
			default:
				statusText, _ = h.messageManager.GetMessage("stat_status_inactive", nil)
			}
			lastHandshake = stats.LastHandshake
			transfer = stats.Transfer
		} else {
			statusText = "—"
			lastHandshake = "—"
			transfer = "—"
		}

		inlineKeyboard := tgbotapi.NewInlineKeyboardMarkup(
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("🔄 Пересоздать", "create_recreate"),
				tgbotapi.NewInlineKeyboardButtonData("🔗 Сгенерировать ссылку", "create_generate_link"),
			),
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("❌ Отмена", "create_cancel"),
			),
		)

		existsText, _ := h.messageManager.GetMessage("create_exists", map[string]interface{}{
			"status":         statusText,
			"last_handshake": lastHandshake,
			"transfer":       transfer,
		})

		msg := tgbotapi.NewMessage(update.Message.Chat.ID, existsText)
		msg.ReplyMarkup = inlineKeyboard
		h.bot.Send(msg)

		logEvent := LogEvent{
			Timestamp:      update.Message.Time(),
			UserID:         update.Message.From.ID,
			Username:       update.Message.From.UserName,
			ClientName:     clientName,
			Command:        "create_existing",
			ScriptExitCode: exitCode,
			ScriptOutput:   output,
			Error:          "Client already exists, waiting for confirmation",
			IsPremium:      isPremium,
			UserLevel:      user.UserLevel,
		}
		h.logRepo.LogEvent(logEvent)
		return
	}

	var response string
	var logError string

	if err != nil {
		logError = err.Error()
		errorText, _ := h.messageManager.GetMessage("create_error", nil)
		response = errorText
	} else if exitCode != 0 {
		logError = fmt.Sprintf("Script exited with code %d", exitCode)
		errorText, _ := h.messageManager.GetMessage("create_error", nil)
		response = errorText
	} else {
		downloadLink := h.extractDownloadLink(output)
		if downloadLink != "" {
			response = downloadLink
		} else {
			noLinkText, _ := h.messageManager.GetMessage("create_no_link", nil)
			response = noLinkText
		}
	}

	msg := tgbotapi.NewMessage(update.Message.Chat.ID, response)
	if strings.Contains(response, "<code>") {
		msg.ParseMode = "HTML"
	}
	h.bot.Send(msg)

	// Since client_activity table is removed, we no longer update client activity
	// Client activity tracking is now handled through user activity in the users table

	logEvent := LogEvent{
		Timestamp:      update.Message.Time(),
		UserID:         update.Message.From.ID,
		Username:       update.Message.From.UserName,
		ClientName:     clientName,
		Command:        "create",
		ScriptExitCode: exitCode,
		ScriptOutput:   output,
		Error:          logError,
		IsPremium:      isPremium,
		UserLevel:      user.UserLevel,
	}
	h.logRepo.LogEvent(logEvent)
}

func (h *BotHandler) handleHelp(update tgbotapi.Update) {
	helpText, _ := h.messageManager.GetMessage("help_text", map[string]interface{}{
		"bot_name": h.cachedBotName,
	})
	h.sendMessageAndTrack(update.Message.Chat.ID, update.Message.From.ID, helpText)
}

func (h *BotHandler) handleInfo(update tgbotapi.Update) {
	infoText, _ := h.messageManager.GetMessage("info_text", map[string]interface{}{
		"bot_name": h.cachedBotName,
	})
	h.sendMessageAndTrack(update.Message.Chat.ID, update.Message.From.ID, infoText)
}

func (h *BotHandler) handleSelfhost(update tgbotapi.Update) {
	selfhostText, _ := h.messageManager.GetMessage("selfhost_info", map[string]interface{}{
		"bot_name": h.cachedBotName,
	})
	h.sendMessageAndTrack(update.Message.Chat.ID, update.Message.From.ID, selfhostText)
}

func (h *BotHandler) handleFeedback(update tgbotapi.Update) {
	feedbackRequestText, _ := h.messageManager.GetMessage("feedback_request", nil)

	keyboard := tgbotapi.NewInlineKeyboardMarkup(
		tgbotapi.NewInlineKeyboardRow(
			tgbotapi.NewInlineKeyboardButtonData("❌ Отмена", "feedback_cancel"),
		),
	)

	msg := tgbotapi.NewMessage(update.Message.Chat.ID, feedbackRequestText)
	msg.ReplyMarkup = keyboard
	if strings.ContainsAny(feedbackRequestText, "<>") {
		msg.ParseMode = "HTML"
	}
	msg.DisableWebPagePreview = true
	h.bot.Send(msg)

	h.mu.Lock()
	h.userStates[update.Message.From.ID] = &UserState{
		StateType: feedbackStateType,
	}
	h.mu.Unlock()
}

func (h *BotHandler) handlePremium(update tgbotapi.Update) {
	userID := update.Message.From.ID

	user, err := h.userRepo.GetUserByUserID(userID)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка получения информации о пользователе")
		return
	}

	if user.UserLevel == string(Admin) || user.UserLevel == string(Moderator) {
		activeText, _ := h.messageManager.GetMessage("premium_status_active", map[string]interface{}{
			"expiration_date": "Бессрочно (уровень " + user.UserLevel + ")",
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, activeText)
		return
	}

	isPremium, err := h.userRepo.IsPremium(userID)
	if err != nil {
		isPremium = false
	}

	if !isPremium {
		if user.PremiumExpiresAt != nil && !user.PremiumExpiresAt.IsZero() {
			expiredText, _ := h.messageManager.GetMessage("premium_status_expired", map[string]interface{}{
				"expiration_date": user.PremiumExpiresAt.Format("2006-01-02 15:04"),
			})
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, expiredText)
		} else {
			noPremiumText, _ := h.messageManager.GetMessage("premium_status_none", nil)
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, noPremiumText)
		}
		return
	}

	if user.PremiumExpiresAt != nil && !user.PremiumExpiresAt.IsZero() {
		activeText, _ := h.messageManager.GetMessage("premium_status_active", map[string]interface{}{
			"expiration_date": user.PremiumExpiresAt.Format("2006-01-02 15:04"),
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, activeText)
	} else {
		activeText, _ := h.messageManager.GetMessage("premium_status_active", map[string]interface{}{
			"expiration_date": "Бессрочно",
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, activeText)
	}
}

func (h *BotHandler) checkFeedbackProcessed(feedbackID int64, chatID int64) bool {
	feedback, err := h.feedbackRepo.GetFeedbackByID(feedbackID)
	if err != nil {
		sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: обратная связь не найдена")
		return true
	}

	if feedback.RespondedBy != nil && *feedback.RespondedBy != 0 {
		moderator, err := h.userRepo.GetUserByUserID(*feedback.RespondedBy)
		moderatorUsername := "неизвестен"
		if err == nil {
			moderatorUsername = moderator.Username
		}

		action := "прочитано"
		if feedback.Response != nil {
			action = *feedback.Response
		}

		respondedAt := "неизвестно"
		if feedback.RespondedAt != nil {
			respondedAt = feedback.RespondedAt.Format("2006-01-02 15:04:05")
		}

		alreadyProcessedText, _ := h.messageManager.GetMessage("feedback_already_processed", map[string]interface{}{
			"moderator_username": moderatorUsername,
			"moderator_id":       *feedback.RespondedBy,
			"action":             action,
			"responded_at":       respondedAt,
		})
		sendMessageWithHTML(h.bot, chatID, alreadyProcessedText)
		return true
	}

	return false
}

func parseDateString(dateStr string) (time.Time, error) {
	dateStr = strings.TrimSpace(dateStr)

	parts := strings.Split(dateStr, " ")
	if len(parts) != 2 {
		return time.Time{}, fmt.Errorf("invalid format: expected 'DD-MM-YYYY HH:MM'")
	}

	datePart := parts[0]
	timePart := parts[1]

	dateParts := strings.Split(datePart, "-")
	if len(dateParts) != 3 {
		return time.Time{}, fmt.Errorf("invalid date format: expected DD-MM-YYYY")
	}

	timeParts := strings.Split(timePart, ":")
	if len(timeParts) != 2 {
		return time.Time{}, fmt.Errorf("invalid time format: expected HH:MM")
	}

	day, err := strconv.Atoi(dateParts[0])
	if err != nil || day < 1 || day > 31 {
		return time.Time{}, fmt.Errorf("invalid day: must be 1-31")
	}

	month, err := strconv.Atoi(dateParts[1])
	if err != nil || month < 1 || month > 12 {
		return time.Time{}, fmt.Errorf("invalid month: must be 1-12")
	}

	year, err := strconv.Atoi(dateParts[2])
	if err != nil || year < 2000 || year > 2100 {
		return time.Time{}, fmt.Errorf("invalid year: must be 2000-2100")
	}

	hour, err := strconv.Atoi(timeParts[0])
	if err != nil || hour < 0 || hour > 23 {
		return time.Time{}, fmt.Errorf("invalid hour: must be 0-23")
	}

	minute, err := strconv.Atoi(timeParts[1])
	if err != nil || minute < 0 || minute > 59 {
		return time.Time{}, fmt.Errorf("invalid minute: must be 0-59")
	}

	return time.Date(year, time.Month(month), day, hour, minute, 0, 0, time.Local), nil
}

func (h *BotHandler) handleDelete(update tgbotapi.Update, clientName string, user *User) {
	clientName = strings.ToLower(clientName)
	clientDir := fmt.Sprintf("%s/%s", h.config.ClientsDir, clientName)
	_, statErr := os.Stat(clientDir)

	if os.IsNotExist(statErr) {
		noConfigText, _ := h.messageManager.GetMessage("delete_no_config", nil)
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, noConfigText)
		return
	}

	var statusText, lastHandshake, transfer string
	stats, err := h.wgService.GetClientStats(clientName)
	if err == nil {
		switch stats.Status {
		case "active":
			statusText, _ = h.messageManager.GetMessage("stat_status_active", nil)
		case "inactive":
			statusText, _ = h.messageManager.GetMessage("stat_status_inactive", nil)
		case "never_connected":
			statusText, _ = h.messageManager.GetMessage("stat_status_never_connected", nil)
		default:
			statusText, _ = h.messageManager.GetMessage("stat_status_inactive", nil)
		}
		lastHandshake = stats.LastHandshake
		transfer = stats.Transfer
	} else {
		statusText = "—"
		lastHandshake = "—"
		transfer = "—"
	}

	h.mu.Lock()
	h.userStates[update.Message.From.ID] = &UserState{
		StateType:  deletionStateType,
		ClientName: clientName,
		InProgress: false,
	}
	h.mu.Unlock()

	buttonYes, _ := h.messageManager.GetMessage("button_yes", nil)
	buttonNo, _ := h.messageManager.GetMessage("button_no", nil)
	inlineKeyboard := tgbotapi.NewInlineKeyboardMarkup(
		tgbotapi.NewInlineKeyboardRow(
			tgbotapi.NewInlineKeyboardButtonData(buttonYes, "delete_confirm_yes"),
			tgbotapi.NewInlineKeyboardButtonData(buttonNo, "delete_confirm_no"),
		),
	)

	deleteConfirmationText, _ := h.messageManager.GetMessage("delete_confirmation", map[string]interface{}{
		"status":         statusText,
		"last_handshake": lastHandshake,
		"transfer":       transfer,
	})

	msg := tgbotapi.NewMessage(update.Message.Chat.ID, deleteConfirmationText)
	msg.ReplyMarkup = inlineKeyboard
	h.bot.Send(msg)
}

func (h *BotHandler) HandleCallbackQuery(update tgbotapi.Update) {
	if update.CallbackQuery == nil {
		return
	}
	if h.isBlockedUser(update.CallbackQuery.From.ID, update.CallbackQuery.From.UserName, update.CallbackQuery.Message.Chat.ID, update.CallbackQuery.Message.Time(), "blocked_callback_attempt") {
		return
	}

	callbackData := update.CallbackQuery.Data
	chatID := update.CallbackQuery.Message.Chat.ID
	user := update.CallbackQuery.From

	clientName := h.getClientName(user)

	callbackConfig := tgbotapi.NewCallback(update.CallbackQuery.ID, "")
	h.bot.Send(callbackConfig)

	if strings.HasPrefix(callbackData, "fb_reply_") {
		currentUser, err := h.userRepo.GetUserByUserID(user.ID)
		if err != nil || !h.checkPrivilege(currentUser, Moderator) {
			h.sendInsufficientPermissions(chatID)
			return
		}

		feedbackIDStr := strings.TrimPrefix(callbackData, "fb_reply_")
		feedbackID, err := strconv.ParseInt(feedbackIDStr, 10, 64)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: неверный ID обратной связи")
			return
		}

		if h.checkFeedbackProcessed(feedbackID, chatID) {
			return
		}

		feedback, err := h.feedbackRepo.GetFeedbackByID(feedbackID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: обратная связь не найдена")
			return
		}

		feedbackUser, err := h.userRepo.GetUserByUserID(feedback.UserID)
		username := fmt.Sprintf("%d", feedback.UserID)
		if err == nil {
			username = feedbackUser.Username
		}

		requestText, _ := h.messageManager.GetMessage("feedback_request_response", map[string]interface{}{
			"username": username,
			"user_id":  feedback.UserID,
			"message":  feedback.Message,
		})

		keyboard := tgbotapi.NewInlineKeyboardMarkup(
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("❌ Отмена", fmt.Sprintf("fb_cancel_%d", feedbackID)),
			),
		)

		msg := tgbotapi.NewMessage(chatID, requestText)
		msg.ReplyMarkup = keyboard
		msg.ParseMode = "HTML"
		h.bot.Send(msg)

		h.mu.Lock()
		h.userStates[user.ID] = &UserState{
			StateType:    feedbackResponseStateType,
			FeedbackID:   feedbackID,
			TargetUserID: feedback.UserID,
		}
		h.mu.Unlock()
		return
	}

	if strings.HasPrefix(callbackData, "fb_level_") {
		currentUser, err := h.userRepo.GetUserByUserID(user.ID)
		if err != nil || !h.checkPrivilege(currentUser, Moderator) {
			h.sendInsufficientPermissions(chatID)
			return
		}

		feedbackIDStr := strings.TrimPrefix(callbackData, "fb_level_")
		feedbackID, err := strconv.ParseInt(feedbackIDStr, 10, 64)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: неверный ID обратной связи")
			return
		}

		if h.checkFeedbackProcessed(feedbackID, chatID) {
			return
		}

		feedback, err := h.feedbackRepo.GetFeedbackByID(feedbackID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: обратная связь не найдена")
			return
		}

		feedbackUser, err := h.userRepo.GetUserByUserID(feedback.UserID)
		username := fmt.Sprintf("%d", feedback.UserID)
		if err == nil {
			username = feedbackUser.Username
		}

		selectLevelText, _ := h.messageManager.GetMessage("feedback_select_level", map[string]interface{}{
			"username": username,
			"user_id":  feedback.UserID,
		})

		keyboard := tgbotapi.NewInlineKeyboardMarkup(
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("🚫 Ban", fmt.Sprintf("fb_lvl_ban_%d", feedbackID)),
				tgbotapi.NewInlineKeyboardButtonData("👤 Basic", fmt.Sprintf("fb_lvl_basic_%d", feedbackID)),
			),
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("⭐️ Premium", fmt.Sprintf("fb_lvl_premium_%d", feedbackID)),
				tgbotapi.NewInlineKeyboardButtonData("🛡 Moderator", fmt.Sprintf("fb_lvl_moderator_%d", feedbackID)),
			),
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("👑 Admin", fmt.Sprintf("fb_lvl_admin_%d", feedbackID)),
			),
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("❌ Отмена", fmt.Sprintf("fb_cancel_%d", feedbackID)),
			),
		)

		msg := tgbotapi.NewMessage(chatID, selectLevelText)
		msg.ReplyMarkup = keyboard
		h.bot.Send(msg)
		return
	}

	if strings.HasPrefix(callbackData, "fb_lvl_") {
		currentUser, err := h.userRepo.GetUserByUserID(user.ID)
		if err != nil || !h.checkPrivilege(currentUser, Moderator) {
			h.sendInsufficientPermissions(chatID)
			return
		}

		parts := strings.Split(strings.TrimPrefix(callbackData, "fb_lvl_"), "_")
		if len(parts) != 2 {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: неверный формат команды")
			return
		}

		level := parts[0]
		feedbackID, err := strconv.ParseInt(parts[1], 10, 64)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: неверный ID обратной связи")
			return
		}

		if h.checkFeedbackProcessed(feedbackID, chatID) {
			return
		}

		feedback, err := h.feedbackRepo.GetFeedbackByID(feedbackID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: обратная связь не найдена")
			return
		}

		requestDateText, _ := h.messageManager.GetMessage("feedback_request_date", nil)

		keyboard := tgbotapi.NewInlineKeyboardMarkup(
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("📅 Месяц", fmt.Sprintf("fb_date_month_%s_%d", level, feedbackID)),
				tgbotapi.NewInlineKeyboardButtonData("♾ Навсегда", fmt.Sprintf("fb_date_forever_%s_%d", level, feedbackID)),
			),
			tgbotapi.NewInlineKeyboardRow(
				tgbotapi.NewInlineKeyboardButtonData("❌ Отмена", fmt.Sprintf("fb_cancel_%d", feedbackID)),
			),
		)

		msg := tgbotapi.NewMessage(chatID, requestDateText)
		msg.ReplyMarkup = keyboard
		h.bot.Send(msg)

		h.mu.Lock()
		h.userStates[user.ID] = &UserState{
			StateType:       feedbackSetDateStateType,
			FeedbackID:      feedbackID,
			TargetUserID:    feedback.UserID,
			TargetUserLevel: level,
		}
		h.mu.Unlock()
		return
	}

	if strings.HasPrefix(callbackData, "fb_date_month_") || strings.HasPrefix(callbackData, "fb_date_forever_") {
		currentUser, err := h.userRepo.GetUserByUserID(user.ID)
		if err != nil || !h.checkPrivilege(currentUser, Moderator) {
			h.sendInsufficientPermissions(chatID)
			return
		}

		var dateType, level string
		var feedbackID int64

		if strings.HasPrefix(callbackData, "fb_date_month_") {
			dateType = "month"
			parts := strings.Split(strings.TrimPrefix(callbackData, "fb_date_month_"), "_")
			if len(parts) != 2 {
				sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: неверный формат команды")
				return
			}
			level = parts[0]
			feedbackID, err = strconv.ParseInt(parts[1], 10, 64)
		} else {
			dateType = "forever"
			parts := strings.Split(strings.TrimPrefix(callbackData, "fb_date_forever_"), "_")
			if len(parts) != 2 {
				sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: неверный формат команды")
				return
			}
			level = parts[0]
			feedbackID, err = strconv.ParseInt(parts[1], 10, 64)
		}

		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: неверный ID обратной связи")
			return
		}

		if h.checkFeedbackProcessed(feedbackID, chatID) {
			return
		}

		feedback, err := h.feedbackRepo.GetFeedbackByID(feedbackID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: обратная связь не найдена")
			return
		}

		feedbackUser, err := h.userRepo.GetUserByUserID(feedback.UserID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: пользователь не найден")
			return
		}

		var expiresAt *time.Time
		expiresAtStr := "Бессрочно"
		if dateType == "month" {
			exp := time.Now().AddDate(0, 0, 32)
			expiresAt = &exp
			expiresAtStr = exp.Format("2006-01-02 15:04")
		}

		err = h.userRepo.SetUserLevel(feedback.UserID, level)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка установки уровня")
			h.logRepo.LogEvent(LogEvent{
				Timestamp: update.CallbackQuery.Message.Time(),
				UserID:    user.ID,
				Username:  user.UserName,
				Command:   "feedback_level_change_error",
				Error:     err.Error(),
			})
			return
		}

		if level == "premium" || level == "ban" {
			err = h.userRepo.SetPremiumStatus(feedback.UserID, expiresAt, fmt.Sprintf("Set by moderator %s", user.UserName))
			if err != nil {
				sendMessageWithHTML(h.bot, chatID, "❌ Ошибка установки статуса premium")
				return
			}
		}

		responseText := fmt.Sprintf("User level changed to %s until %s", level, expiresAtStr)
		err = h.feedbackRepo.RespondToFeedback(feedbackID, responseText, user.ID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка сохранения ответа")
			return
		}

		successText, _ := h.messageManager.GetMessage("feedback_level_changed", map[string]interface{}{
			"username":   feedbackUser.Username,
			"user_id":    feedback.UserID,
			"level":      level,
			"expires_at": expiresAtStr,
		})
		sendMessageWithHTML(h.bot, chatID, successText)

		h.mu.Lock()
		delete(h.userStates, user.ID)
		h.mu.Unlock()

		h.logRepo.LogEvent(LogEvent{
			Timestamp:    update.CallbackQuery.Message.Time(),
			UserID:       user.ID,
			Username:     user.UserName,
			Command:      "feedback_level_changed",
			ScriptOutput: responseText,
		})
		return
	}

	if strings.HasPrefix(callbackData, "fb_delete_") {
		currentUser, err := h.userRepo.GetUserByUserID(user.ID)
		if err != nil || !h.checkPrivilege(currentUser, Moderator) {
			h.sendInsufficientPermissions(chatID)
			return
		}

		feedbackIDStr := strings.TrimPrefix(callbackData, "fb_delete_")
		feedbackID, err := strconv.ParseInt(feedbackIDStr, 10, 64)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: неверный ID обратной связи")
			return
		}

		if h.checkFeedbackProcessed(feedbackID, chatID) {
			return
		}

		feedback, err := h.feedbackRepo.GetFeedbackByID(feedbackID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: обратная связь не найдена")
			return
		}

		feedbackUser, err := h.userRepo.GetUserByUserID(feedback.UserID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка: пользователь не найден")
			return
		}

		clientName := feedbackUser.Username
		if clientName == "" {
			clientName = fmt.Sprintf("%d", feedback.UserID)
		}

		ctx := context.Background()
		output, exitCode, scriptErr := h.scriptRunner.RunRemoveScript(ctx, clientName)

		responseText := fmt.Sprintf("User configuration deleted (exit code: %d)", exitCode)
		if scriptErr != nil {
			responseText = fmt.Sprintf("User configuration deletion attempted but failed: %s", scriptErr.Error())
		}

		err = h.feedbackRepo.RespondToFeedback(feedbackID, responseText, user.ID)
		if err != nil {
			sendMessageWithHTML(h.bot, chatID, "❌ Ошибка сохранения ответа")
			return
		}

		successText, _ := h.messageManager.GetMessage("feedback_config_deleted", map[string]interface{}{
			"username": feedbackUser.Username,
			"user_id":  feedback.UserID,
		})
		sendMessageWithHTML(h.bot, chatID, successText)

		h.logRepo.LogEvent(LogEvent{
			Timestamp:      update.CallbackQuery.Message.Time(),
			UserID:         user.ID,
			Username:       user.UserName,
			Command:        "feedback_config_deleted",
			ScriptExitCode: exitCode,
			ScriptOutput:   output,
		})
		return
	}

	if strings.HasPrefix(callbackData, "fb_read_") {
		currentUser, err := h.userRepo.GetUserByUserID(user.ID)
		if err != nil || !h.checkPrivilege(currentUser, Moderator) {
			h.sendInsufficientPermissions(chatID)
			return
		}

		deleteMsg := tgbotapi.NewDeleteMessage(chatID, update.CallbackQuery.Message.MessageID)
		_, _ = h.bot.Send(deleteMsg)

		callback := tgbotapi.NewCallback(update.CallbackQuery.ID, "✅ Сообщение закрыто")
		h.bot.Send(callback)

		return
	}

	if strings.HasPrefix(callbackData, "fb_cancel_") {
		h.mu.Lock()
		delete(h.userStates, user.ID)
		h.mu.Unlock()

		cancelText, _ := h.messageManager.GetMessage("feedback_action_cancelled", nil)
		sendMessageWithHTML(h.bot, chatID, cancelText)

		h.logRepo.LogEvent(LogEvent{
			Timestamp: update.CallbackQuery.Message.Time(),
			UserID:    user.ID,
			Username:  user.UserName,
			Command:   "feedback_action_cancelled",
		})
		return
	}

	if callbackData == "feedback_cancel" {
		h.mu.Lock()
		delete(h.userStates, user.ID)
		h.mu.Unlock()

		cancelText := "❌ Ввод обратной связи отменён"
		sendMessageWithHTML(h.bot, chatID, cancelText)

		logEvent := LogEvent{
			Timestamp:  update.CallbackQuery.Message.Time(),
			UserID:     user.ID,
			Username:   user.UserName,
			ClientName: clientName,
			Command:    "feedback_cancelled",
		}
		h.logRepo.LogEvent(logEvent)
		return
	}

	if callbackData == "delete_confirm_yes" || callbackData == "delete_confirm_no" {
		h.mu.RLock()
		userState, exists := h.userStates[user.ID]
		h.mu.RUnlock()

		if exists && userState.StateType == deletionStateType && !userState.InProgress {
			h.mu.Lock()
			userState.InProgress = true
			h.userStates[user.ID] = userState
			h.mu.Unlock()

			if callbackData == "delete_confirm_yes" {
				ctx := context.Background()
				output, exitCode, err := h.scriptRunner.RunRemoveScript(ctx, userState.ClientName)

				var response string
				if err != nil || exitCode != 0 {
					errorText, _ := h.messageManager.GetMessage("delete_error", nil)
					response = errorText
				} else {
					successText, _ := h.messageManager.GetMessage("delete_success", nil)
					response = successText
				}

				sendMessageWithHTML(h.bot, chatID, response)

				logEvent := LogEvent{
					Timestamp:      update.CallbackQuery.Message.Time(),
					UserID:         user.ID,
					Username:       user.UserName,
					ClientName:     userState.ClientName,
					Command:        "delete_confirmed",
					ScriptExitCode: exitCode,
					ScriptOutput:   output,
				}
				h.logRepo.LogEvent(logEvent)
			} else if callbackData == "delete_confirm_no" {
				cancelledText, _ := h.messageManager.GetMessage("delete_cancelled", nil)
				sendMessageWithHTML(h.bot, chatID, cancelledText)

				logEvent := LogEvent{
					Timestamp:  update.CallbackQuery.Message.Time(),
					UserID:     user.ID,
					Username:   user.UserName,
					ClientName: userState.ClientName,
					Command:    "delete_cancelled",
				}
				h.logRepo.LogEvent(logEvent)
			}

			h.mu.Lock()
			delete(h.userStates, user.ID)
			h.mu.Unlock()
		}
		return
	}

	if callbackData == "create_recreate" || callbackData == "create_confirm_yes" || callbackData == "create_confirm_no" || callbackData == "create_generate_link" || callbackData == "create_cancel" {
		h.mu.RLock()
		userState, exists := h.userStates[user.ID]
		h.mu.RUnlock()

		if exists && userState.StateType == confirmationStateType && !userState.InProgress {
			h.mu.Lock()
			userState.InProgress = true
			h.userStates[user.ID] = userState
			h.mu.Unlock()

			if callbackData == "create_recreate" || callbackData == "create_confirm_yes" {
				h.removeClient(userState.ClientName)

				ctx := context.Background()
				output, exitCode, err := h.scriptRunner.RunScript(ctx, userState.ClientName)

				var response string
				if err != nil || exitCode != 0 {
					errorText, _ := h.messageManager.GetMessage("create_error", nil)
					response = errorText
				} else {
					downloadLink := h.extractDownloadLink(output)
					if downloadLink != "" {
						response = downloadLink
					} else {
						noLinkText, _ := h.messageManager.GetMessage("create_no_link", nil)
						response = noLinkText
					}
				}

				sendMessageWithHTML(h.bot, chatID, response)

				logEvent := LogEvent{
					Timestamp:      update.CallbackQuery.Message.Time(),
					UserID:         user.ID,
					Username:       user.UserName,
					ClientName:     userState.ClientName,
					Command:        "create_recreate_confirmed",
					ScriptExitCode: exitCode,
					ScriptOutput:   output,
					Error:          "",
				}
				h.logRepo.LogEvent(logEvent)
			} else if callbackData == "create_generate_link" {
				scriptName, err := h.scriptRepo.GetScriptName("generate_install_command")
				if err != nil {
					sendMessageWithHTML(h.bot, chatID, "❌ Ошибка генерации ссылки")
				} else {
					scriptPath := h.config.ScriptsDir + "/" + scriptName
					ctx := context.Background()
					ctx, cancel := context.WithTimeout(ctx, h.config.ScriptTimeout)
					defer cancel()

					cmd := exec.CommandContext(ctx, scriptPath, userState.ClientName, "600")
					output, err := cmd.CombinedOutput()

					if err != nil {
						sendMessageWithHTML(h.bot, chatID, "❌ Ошибка генерации ссылки")
					} else {
						installCommand := ""
						lines := strings.Split(string(output), "\n")
						for _, line := range lines {
							trimmedLine := strings.TrimSpace(line)
							if strings.HasPrefix(trimmedLine, "wget -O -") {
								installCommand = trimmedLine
								break
							}
						}

						if installCommand == "" {
							sendMessageWithHTML(h.bot, chatID, "❌ Ошибка генерации ссылки")
						} else {
							response := "🔗 Новая установочная ссылка сгенерирована:\n\n<code>" + installCommand + "</code>\n\nСсылка действительна 10 минут"
							sendMessageWithHTML(h.bot, chatID, response)
						}

						logEvent := LogEvent{
							Timestamp:      update.CallbackQuery.Message.Time(),
							UserID:         user.ID,
							Username:       user.UserName,
							ClientName:     userState.ClientName,
							Command:        "create_link_generated",
							ScriptExitCode: 0,
							ScriptOutput:   installCommand,
						}
						h.logRepo.LogEvent(logEvent)
					}
				}
			} else if callbackData == "create_confirm_no" || callbackData == "create_cancel" {
				cancelText := "❌ Действие отменено"
				sendMessageWithHTML(h.bot, chatID, cancelText)

				logEvent := LogEvent{
					Timestamp:      update.CallbackQuery.Message.Time(),
					UserID:         user.ID,
					Username:       user.UserName,
					ClientName:     userState.ClientName,
					Command:        "create_cancelled",
					ScriptExitCode: 0,
					ScriptOutput:   "",
					Error:          "",
				}
				h.logRepo.LogEvent(logEvent)
			}

			h.mu.Lock()
			delete(h.userStates, user.ID)
			h.mu.Unlock()
		}
		return
	}

	var response string
	switch callbackData {
	case "/create":
		createCallbackText, _ := h.messageManager.GetMessage("callback_create", nil)
		response = createCallbackText
	case "/info":
		infoText, _ := h.messageManager.GetMessage("info_text", map[string]interface{}{
			"bot_name": h.cachedBotName,
		})
		response = infoText
	case "/help":
		helpText, _ := h.messageManager.GetMessage("help_text", map[string]interface{}{
			"bot_name": h.cachedBotName,
		})
		response = helpText
	default:
		unknownText, _ := h.messageManager.GetMessage("unknown_command", nil)
		response = unknownText
	}

	sendMessageWithHTML(h.bot, chatID, response)

	h.logRepo.LogEvent(LogEvent{
		Timestamp:  update.CallbackQuery.Message.Time(),
		UserID:     user.ID,
		Username:   user.UserName,
		ClientName: clientName,
		Command:    "callback_" + callbackData,
	})
}
func (h *BotHandler) extractDownloadLink(output string) string {
	lines := strings.Split(output, "\n")
	var downloadLink string
	var expirationLine string
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.Contains(line, "wget -O - ") && strings.Contains(line, "/init/") && strings.Contains(line, ".sh") {
			downloadLink = line
		}
		if downloadLink == "" && strings.Contains(line, "curl -sL ") && strings.Contains(line, "/init/") && strings.Contains(line, ".sh") {
			downloadLink = strings.Replace(line, "curl -sL", "wget -O -", 1)
		}
		if strings.Contains(line, "ВАЖНО: Токен действителен до") {
			expirationLine = line
		}
	}
	if downloadLink != "" {
		expirationInfo := ""
		if expirationLine != "" {
			expirationInfo = strings.Replace(expirationLine, "Токен", "Ссылка", 1)
		}
		successText, _ := h.messageManager.GetMessage("create_success", map[string]interface{}{
			"download_link":  downloadLink,
			"expiration_info": expirationInfo,
		})
		return successText
	}
	return ""
}

func (h *BotHandler) removeClient(clientName string) {
	ctx := context.Background()
	_, _, _ = h.scriptRunner.RunRemoveScript(ctx, clientName)
}
func (h *BotHandler) handleStat(update tgbotapi.Update, clientName string, user *User) {
	isPremium, err := h.userRepo.IsPremium(update.Message.From.ID)
	if err != nil {
		isPremium = false
	}

	if !isPremium && !h.rateLimiter.canExecuteCommand(update.Message.From.ID, "stat") {
		rateLimitText, _ := h.messageManager.GetMessage("create_rate_limited", nil)
		msg := tgbotapi.NewMessage(update.Message.Chat.ID, rateLimitText)
		h.bot.Send(msg)
		return
	}

	clientName = strings.ToLower(clientName)
	stats, err := h.wgService.GetClientStats(clientName)
	if err != nil {
		if os.IsNotExist(err) {
			noConfigText, _ := h.messageManager.GetMessage("stat_no_config", nil)
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, noConfigText)
		} else {
			errorText, _ := h.messageManager.GetMessage("stat_error", nil)
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, errorText)
		}
		h.logRepo.LogEvent(LogEvent{
			Timestamp:  update.Message.Time(),
			UserID:     update.Message.From.ID,
			Username:   update.Message.From.UserName,
			ClientName: clientName,
			Command:    "stat_error",
			Error:      err.Error(),
		})
		return
	}
	var statusText string
	switch stats.Status {
	case "active":
		statusText, _ = h.messageManager.GetMessage("stat_status_active", nil)
	case "inactive":
		statusText, _ = h.messageManager.GetMessage("stat_status_inactive", nil)
	case "never_connected":
		statusText, _ = h.messageManager.GetMessage("stat_status_never_connected", nil)
	default:
		statusText, _ = h.messageManager.GetMessage("stat_status_inactive", nil)
	}

	timeRemainingText := ""
	isPremium, err = h.userRepo.IsPremium(update.Message.From.ID)
	if err != nil {
		isPremium = false
	}

	if !isPremium && h.config.MaxTestDuration > 0 {
		// Since client_activity table is removed, we can only use user's created_at time
		elapsed := time.Since(user.CreatedAt)
		remaining := h.config.MaxTestDuration - elapsed
		if remaining > 0 {
			hoursRemaining := int(remaining.Hours())
			timeRemainingMsg, _ := h.messageManager.GetMessage("stat_time_remaining", map[string]interface{}{
				"hours": hoursRemaining,
			})
			timeRemainingText = "\n" + timeRemainingMsg
		}
	}

	headerText, _ := h.messageManager.GetMessage("stat_header", map[string]interface{}{
		"status":         statusText,
		"last_handshake": stats.LastHandshake,
		"transfer":       stats.Transfer,
		"time_remaining": timeRemainingText,
	})
	sendMessageWithHTML(h.bot, update.Message.Chat.ID, headerText)
}
func (h *BotHandler) sendHelpMessage(update tgbotapi.Update) {
	helpText, _ := h.messageManager.GetMessage("help_text", map[string]interface{}{
		"bot_name": h.cachedBotName,
	})

	h.sendMessageAndTrack(update.Message.Chat.ID, update.Message.From.ID, helpText)
}

func (h *BotHandler) checkPrivilege(user *User, requiredLevel UserLevel) bool {
	if user == nil {
		return false
	}

	hasPrivilege, err := h.userRepo.HasPrivilege(user.UserID, requiredLevel)
	if err != nil {
		return false
	}
	return hasPrivilege
}

func (h *BotHandler) sendInsufficientPermissions(chatID int64) {
	msg, _ := h.messageManager.GetMessage("insufficient_permissions", nil)
	sendMessageWithHTML(h.bot, chatID, msg)
}

func (h *BotHandler) handleLogs(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Moderator) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := strings.Fields(update.Message.CommandArguments())
	limit := 20
	var userFilter string

	if len(args) > 0 {
		userFilter = args[0]
	}
	if len(args) > 1 {
		if l, err := strconv.Atoi(args[1]); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	logs, err := h.logRepo.GetRecentLogs(limit, userFilter)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка получения логов")
		return
	}

	if len(logs) == 0 {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "Логов не найдено")
		return
	}

	var response strings.Builder
	response.WriteString(fmt.Sprintf("📋 Последние %d логов:\n\n", len(logs)))

	for _, log := range logs {
		timestamp := log.Timestamp.Format("2006-01-02 15:04:05")
		response.WriteString(fmt.Sprintf("🕐 %s | @%s (ID: %d)\n", timestamp, log.Username, log.UserID))
		response.WriteString(fmt.Sprintf("▫️ Команда: %s\n", log.Command))
		if log.Error != "" {
			response.WriteString(fmt.Sprintf("⚠️ Ошибка: %s\n", log.Error))
		}
		response.WriteString("\n")
	}

	sendMessageWithHTML(h.bot, update.Message.Chat.ID, response.String())
}

func (h *BotHandler) handleUsers(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Moderator) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := strings.Fields(update.Message.CommandArguments())
	limit := 20
	var levelFilter string

	if len(args) > 0 {
		levelFilter = args[0]
	}
	if len(args) > 1 {
		if l, err := strconv.Atoi(args[1]); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	users, err := h.userRepo.GetAllUsers()
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка получения списка пользователей")
		return
	}

	var filteredUsers []*User
	for _, u := range users {
		if levelFilter == "" || u.UserLevel == levelFilter {
			filteredUsers = append(filteredUsers, u)
		}
	}

	if len(filteredUsers) > limit {
		filteredUsers = filteredUsers[:limit]
	}

	if len(filteredUsers) == 0 {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "Пользователей не найдено")
		return
	}

	var response strings.Builder
	response.WriteString(fmt.Sprintf("👥 Пользователи (показано %d):\n\n", len(filteredUsers)))

	for _, u := range filteredUsers {
		response.WriteString(fmt.Sprintf("ID: %d | @%s\n", u.UserID, u.Username))
		response.WriteString(fmt.Sprintf("▫️ Уровень: %s\n", u.UserLevel))
		response.WriteString(fmt.Sprintf("▫️ Создан: %s\n", u.CreatedAt.Format("2006-01-02")))
		response.WriteString(fmt.Sprintf("▫️ Активность: %s\n", u.UpdatedAt.Format("2006-01-02 15:04")))
		if u.PremiumExpiresAt != nil {
			response.WriteString(fmt.Sprintf("▫️ Premium до: %s\n", u.PremiumExpiresAt.Format("2006-01-02")))
		}
		response.WriteString("\n")
	}

	sendMessageWithHTML(h.bot, update.Message.Chat.ID, response.String())
}

func (h *BotHandler) handleFeedbackList(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Moderator) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := strings.Fields(update.Message.CommandArguments())
	limit := 10

	if len(args) > 0 {
		if l, err := strconv.Atoi(args[0]); err == nil && l > 0 && l <= 50 {
			limit = l
		}
	}

	feedbacks, err := h.feedbackRepo.GetUnprocessedFeedback(limit)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка получения обратной связи")
		return
	}

	if len(feedbacks) == 0 {
		msg, _ := h.messageManager.GetMessage("feedbacklist_empty", nil)
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	headerMsg, _ := h.messageManager.GetMessage("feedbacklist_header", map[string]interface{}{
		"count": len(feedbacks),
	})

	var response strings.Builder
	response.WriteString(headerMsg + "\n\n")

	for _, fb := range feedbacks {
		userInfo, _ := h.userRepo.GetUserByUserID(fb.UserID)
		username := ""
		if userInfo != nil {
			username = userInfo.Username
		}

		itemMsg, _ := h.messageManager.GetMessage("feedbacklist_item", map[string]interface{}{
			"id":        fb.ID,
			"username":  username,
			"user_id":   fb.UserID,
			"timestamp": fb.Timestamp.Format("2006-01-02 15:04"),
			"message":   fb.Message,
		})
		response.WriteString(itemMsg + "\n\n")
	}

	sendMessageWithHTML(h.bot, update.Message.Chat.ID, response.String())
}

func (h *BotHandler) handleSetLevel(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Admin) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := strings.Fields(update.Message.CommandArguments())
	if len(args) < 2 {
		msg, _ := h.messageManager.GetMessage("invalid_command_format", map[string]interface{}{
			"usage": "/setlevel <user_id> <level>",
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	targetUserID, err := strconv.ParseInt(args[0], 10, 64)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Неверный user_id")
		return
	}

	level := args[1]
	validLevels := map[string]bool{"basic": true, "premium": true, "moderator": true, "admin": true}
	if !validLevels[level] {
		msg, _ := h.messageManager.GetMessage("setlevel_invalid_level", nil)
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	err = h.userRepo.SetUserLevel(targetUserID, level)
	if err != nil {
		msg, _ := h.messageManager.GetMessage("user_not_found", map[string]interface{}{
			"user_id": targetUserID,
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	msg, _ := h.messageManager.GetMessage("setlevel_success", map[string]interface{}{
		"user_id": targetUserID,
		"level":   level,
	})
	sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)

	h.logRepo.LogEvent(LogEvent{
		UserID:       update.Message.From.ID,
		Username:     update.Message.From.UserName,
		Command:      "setlevel",
		ScriptOutput: fmt.Sprintf("Set user %d to level %s", targetUserID, level),
		Timestamp:    update.Message.Time(),
	})
}

func (h *BotHandler) handleSetPremium(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Admin) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := strings.Fields(update.Message.CommandArguments())
	if len(args) < 2 {
		msg, _ := h.messageManager.GetMessage("invalid_command_format", map[string]interface{}{
			"usage": "/setpremium <user_id> <days|permanent> [reason]",
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	targetUserID, err := strconv.ParseInt(args[0], 10, 64)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Неверный user_id")
		return
	}

	reason := ""
	if len(args) > 2 {
		reason = strings.Join(args[2:], " ")
	}

	var expiresAt *time.Time
	var responseMsg string

	if args[1] == "permanent" {
		expiresAt = nil
		err = h.userRepo.SetPremiumStatus(targetUserID, expiresAt, reason)
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка установки премиум-статуса")
			return
		}
		responseMsg, _ = h.messageManager.GetMessage("setpremium_permanent", map[string]interface{}{
			"user_id": targetUserID,
		})
	} else {
		days, err := strconv.Atoi(args[1])
		if err != nil || days <= 0 {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Неверное количество дней")
			return
		}

		expiration := time.Now().AddDate(0, 0, days)
		expiresAt = &expiration
		err = h.userRepo.SetPremiumStatus(targetUserID, expiresAt, reason)
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка установки премиум-статуса")
			return
		}
		responseMsg, _ = h.messageManager.GetMessage("setpremium_success", map[string]interface{}{
			"user_id":    targetUserID,
			"expiration": expiration.Format("2006-01-02"),
		})
	}

	sendMessageWithHTML(h.bot, update.Message.Chat.ID, responseMsg)
}

func (h *BotHandler) handleBlock(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Admin) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := update.Message.CommandArguments()
	parts := strings.SplitN(args, " ", 2)

	if len(parts) < 2 {
		msg, _ := h.messageManager.GetMessage("invalid_command_format", map[string]interface{}{
			"usage": "/block <user_id> <reason>",
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	targetUserID, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Неверный user_id")
		return
	}

	reason := parts[1]

	err = h.blocklistRepo.AddToBlocklist(targetUserID, update.Message.From.UserName, reason, update.Message.From.ID)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка блокировки пользователя")
		return
	}

	msg, _ := h.messageManager.GetMessage("block_success", map[string]interface{}{
		"user_id": targetUserID,
		"reason":  reason,
	})
	sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
}

func (h *BotHandler) handleUnblock(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Admin) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := strings.Fields(update.Message.CommandArguments())
	if len(args) < 1 {
		msg, _ := h.messageManager.GetMessage("invalid_command_format", map[string]interface{}{
			"usage": "/unblock <user_id>",
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	targetUserID, err := strconv.ParseInt(args[0], 10, 64)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Неверный user_id")
		return
	}

	isBlocked, err := h.blocklistRepo.IsBlocked(targetUserID, "")
	if err != nil || !isBlocked {
		msg, _ := h.messageManager.GetMessage("unblock_not_blocked", map[string]interface{}{
			"user_id": targetUserID,
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	err = h.blocklistRepo.RemoveFromBlocklist(targetUserID)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка разблокировки пользователя")
		return
	}

	msg, _ := h.messageManager.GetMessage("unblock_success", map[string]interface{}{
		"user_id": targetUserID,
	})
	sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
}

func (h *BotHandler) handleConfig(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Admin) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := strings.Fields(update.Message.CommandArguments())
	if len(args) < 1 {
		msg, _ := h.messageManager.GetMessage("invalid_command_format", map[string]interface{}{
			"usage": "/config <key> [value]",
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	key := args[0]

	if len(args) == 1 {
		configValue, err := h.configRepo.GetConfig(key)
		if err != nil {
			msg, _ := h.messageManager.GetMessage("config_not_found", map[string]interface{}{
				"key": key,
			})
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
			return
		}

		msg, _ := h.messageManager.GetMessage("config_show", map[string]interface{}{
			"key":   key,
			"value": configValue.Value,
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
	} else {
		value := strings.Join(args[1:], " ")

		err := h.configRepo.SetString(key, value, "Updated via /config command")
		if err != nil {
			sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка обновления конфигурации")
			return
		}

		msg, _ := h.messageManager.GetMessage("config_updated", map[string]interface{}{
			"key":   key,
			"value": value,
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
	}
}

func (h *BotHandler) handleStats(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Admin) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	allUsers, _ := h.userRepo.GetAllUsers()

	userCounts := map[string]int{
		"total":      len(allUsers),
		"basic":      0,
		"premium":    0,
		"moderators": 0,
		"admins":     0,
	}

	for _, u := range allUsers {
		switch u.UserLevel {
		case "basic":
			userCounts["basic"]++
		case "premium":
			userCounts["premium"]++
		case "moderator":
			userCounts["moderators"]++
		case "admin":
			userCounts["admins"]++
		}
	}

	activeConfigs := h.countClients(false)
	totalConfigs := h.countClients(false) + h.countClients(true)

	feedbacks, _ := h.feedbackRepo.GetUnprocessedFeedback(1000)
	unprocessedFeedback := len(feedbacks)
	allFeedbacks, _ := h.feedbackRepo.GetAllFeedback(10000, 0)
	totalFeedback := len(allFeedbacks)

	header, _ := h.messageManager.GetMessage("stats_header", nil)
	usersMsg, _ := h.messageManager.GetMessage("stats_users", map[string]interface{}{
		"total":      userCounts["total"],
		"basic":      userCounts["basic"],
		"premium":    userCounts["premium"],
		"moderators": userCounts["moderators"],
		"admins":     userCounts["admins"],
	})
	configsMsg, _ := h.messageManager.GetMessage("stats_configs", map[string]interface{}{
		"active": activeConfigs,
		"total":  totalConfigs,
	})
	feedbackMsg, _ := h.messageManager.GetMessage("stats_feedback", map[string]interface{}{
		"unprocessed": unprocessedFeedback,
		"total":       totalFeedback,
	})

	response := fmt.Sprintf("%s\n\n%s\n\n%s\n\n%s", header, usersMsg, configsMsg, feedbackMsg)
	sendMessageWithHTML(h.bot, update.Message.Chat.ID, response)
}

func (h *BotHandler) handleCleanupLogs(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Admin) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	args := strings.Fields(update.Message.CommandArguments())
	if len(args) < 1 {
		msg, _ := h.messageManager.GetMessage("invalid_command_format", map[string]interface{}{
			"usage": "/cleanuplogs <days>",
		})
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
		return
	}

	days, err := strconv.Atoi(args[0])
	if err != nil || days <= 0 {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Неверное количество дней")
		return
	}

	cutoffDate := time.Now().AddDate(0, 0, -days)
	count, err := h.logRepo.DeleteLogsOlderThan(cutoffDate)
	if err != nil {
		sendMessageWithHTML(h.bot, update.Message.Chat.ID, "❌ Ошибка очистки логов")
		return
	}

	msg, _ := h.messageManager.GetMessage("cleanuplogs_success", map[string]interface{}{
		"count": count,
		"days":  days,
	})
	sendMessageWithHTML(h.bot, update.Message.Chat.ID, msg)
}

func (h *BotHandler) handleBackup(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Admin) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	sendMessageWithHTML(h.bot, update.Message.Chat.ID, "ℹ️ Команда /backup находится в разработке.\nИспользуйте BackupService для управления резервными копиями.")
}

func (h *BotHandler) handleAdmin(update tgbotapi.Update, user *User) {
	if !h.checkPrivilege(user, Moderator) {
		h.sendInsufficientPermissions(update.Message.Chat.ID)
		return
	}

	var adminText string

	if h.checkPrivilege(user, Admin) {
		adminText, _ = h.messageManager.GetMessage("admin_commands_admin", nil)
	} else {
		adminText, _ = h.messageManager.GetMessage("admin_commands_moderator", nil)
	}

	h.sendMessageAndTrack(update.Message.Chat.ID, update.Message.From.ID, adminText)
}
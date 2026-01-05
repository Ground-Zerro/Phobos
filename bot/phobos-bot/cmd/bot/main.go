package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
	"phobos-bot/internal"
	"phobos-bot/internal/database"
)

const workerPoolSize = 10

func main() {
	var configPath string
	flag.StringVar(&configPath, "config", "", "Path to configuration file (default: ./config.yaml)")
	flag.Parse()

	// Get the executable path for relative path calculations
	execPath, err := os.Executable()
	if err != nil {
		log.Printf("Warning: could not get executable path: %v. Using working directory.", err)
		execPath = "./" // fallback to current directory
	}
	execDir := filepath.Dir(execPath)

	// Set environment variable for config path if provided via flag
	if configPath != "" {
		os.Setenv("CONFIG_FILE_PATH", configPath)
	}

	config, err := internal.GetConfig()
	if err != nil {
		log.Fatalf("Failed to get configuration: %v", err)
	}

	// Initialize database
	dbManager, err := database.NewDBManager(config.DatabasePath)
	if err != nil {
		log.Fatalf("Failed to create database manager: %v", err)
	}
	defer dbManager.Close()

	initService := database.NewInitializationService(dbManager)
	defaultConfigs := map[string]interface{}{
		"script_timeout_seconds":              int(config.ScriptTimeout.Seconds()),
		"watchdog_enabled":                    config.WatchdogEnabled,
		"watchdog_check_interval_minutes":     int(config.WatchdogCheckInterval.Minutes()),
		"watchdog_inactive_threshold_minutes": int(config.WatchdogInactiveThreshold.Minutes()),
		"max_test_duration_minutes":           int(config.MaxTestDuration.Minutes()),
		"restrict_new_users":                  config.RestrictNewUsers,
		"max_clients":                         config.MaxClients,
		"rate_limit_interval_minutes":         1,
		"rate_limited_commands":               "create,stat",
		"backup_enabled":                      true,
		"backup_interval_hours":               24,
		"backup_retention_days":               7,
		"backup_directory":                    filepath.Join(execDir, "backups"),
		"config_reload_interval_minutes":      5,
		"log_level":                           "INFO",
	}

	if err := initService.InitializeDatabase("", defaultConfigs); err != nil {
		log.Fatalf("Database verification failed: %v", err)
	}

	migrationService := database.NewMigrationService(dbManager.GetDB(), filepath.Join(execDir, "migrations"))
	migrationsRun, err := migrationService.RunPendingMigrations()
	if err != nil {
		log.Fatalf("Database migrations failed: %v", err)
	}
	if migrationsRun > 0 {
		log.Printf("Successfully applied %d database migration(s)", migrationsRun)
	}

	// Initialize repositories
	userRepo := database.NewUserRepository(dbManager.GetDB())
	logRepo := database.NewLogRepository(dbManager.GetDB())
	feedbackRepo := database.NewFeedbackRepository(dbManager.GetDB())
	blocklistRepo := database.NewBlocklistRepository(dbManager.GetDB())
	templateRepo := database.NewMessageTemplateRepository(dbManager.GetDB())
	configRepo := database.NewConfigRepository(dbManager.GetDB())
	scriptRepo := database.NewScriptRepository(dbManager.GetDB())

	scriptsDirVal, err := configRepo.GetStringOrDefault("scripts_dir", "", true)
	if err != nil {
		log.Fatalf("CRITICAL: Failed to get scripts dir from database: %v", err)
	}
	config.ScriptsDir = scriptsDirVal

	clientsDirVal, err := configRepo.GetStringOrDefault("clients_dir", "", true)
	if err != nil {
		log.Fatalf("CRITICAL: Failed to get clients dir from database: %v", err)
	}
	config.ClientsDir = clientsDirVal

	wgInterfaceVal, err := configRepo.GetStringOrDefault("wg_interface", "", true)
	if err != nil {
		log.Fatalf("CRITICAL: Failed to get wg interface from database: %v", err)
	}
	config.WGInterface = wgInterfaceVal

	tokenVal, err := configRepo.GetStringOrDefault("bot_token", "", true)
	if err != nil {
		log.Fatalf("CRITICAL: Failed to get bot token from database: %v", err)
	}
	config.Token = tokenVal

	scriptTimeoutVal, err := configRepo.GetIntOrDefault("script_timeout_seconds", 120, false)
	if err != nil {
		log.Printf("WARNING: Failed to get script timeout from database, using default: %v", err)
	}
	config.ScriptTimeout = time.Duration(scriptTimeoutVal) * time.Second

	watchdogEnabledVal, err := configRepo.GetBoolOrDefault("watchdog_enabled", true, false)
	if err != nil {
		log.Printf("WARNING: Failed to get watchdog enabled from database, using default: %v", err)
	}
	config.WatchdogEnabled = watchdogEnabledVal

	watchdogIntervalVal, err := configRepo.GetIntOrDefault("watchdog_check_interval_minutes", 5, false)
	if err != nil {
		log.Printf("WARNING: Failed to get watchdog check interval from database, using default: %v", err)
	}
	config.WatchdogCheckInterval = time.Duration(watchdogIntervalVal) * time.Minute

	watchdogThresholdVal, err := configRepo.GetIntOrDefault("watchdog_inactive_threshold_minutes", 60, false)
	if err != nil {
		log.Printf("WARNING: Failed to get watchdog inactive threshold from database, using default: %v", err)
	}
	config.WatchdogInactiveThreshold = time.Duration(watchdogThresholdVal) * time.Minute

	maxTestDurationVal, err := configRepo.GetIntOrDefault("max_test_duration_minutes", 1440, false)
	if err != nil {
		log.Printf("WARNING: Failed to get max test duration from database, using default: %v", err)
	}
	config.MaxTestDuration = time.Duration(maxTestDurationVal) * time.Minute

	restrictNewUsersVal, err := configRepo.GetBoolOrDefault("restrict_new_users", false, false)
	if err != nil {
		log.Printf("WARNING: Failed to get restrict new users from database, using default: %v", err)
	}
	config.RestrictNewUsers = restrictNewUsersVal

	maxClientsVal, err := configRepo.GetIntOrDefault("max_clients", 100, false)
	if err != nil {
		log.Printf("WARNING: Failed to get max clients from database, using default: %v", err)
	}
	config.MaxClients = maxClientsVal

	configReloadIntervalVal, err := configRepo.GetIntOrDefault("config_reload_interval_minutes", 5, false)
	if err != nil {
		log.Printf("WARNING: Failed to get config reload interval from database, using default: %v", err)
	}
	configReloadInterval := time.Duration(configReloadIntervalVal) * time.Minute

	configReloader := internal.NewConfigReloader(&config, configRepo, configReloadInterval)
	configReloader.Start()

	// Initialize services
	logger := database.NewDatabaseLogger(logRepo)
	dbMessageManager := database.NewDatabaseMessageManager(templateRepo)

	// Initialize bot
	bot, err := tgbotapi.NewBotAPI(config.Token)
	if err != nil {
		log.Fatalf("Failed to initialize bot: %v", err)
	}


	// Set bot commands - getting descriptions from database
	startDesc, err := dbMessageManager.GetMessage("command_start_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get start command description: %v", err)
	}

	createDesc, err := dbMessageManager.GetMessage("command_create_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get create command description: %v", err)
	}

	statDesc, err := dbMessageManager.GetMessage("command_stat_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get stat command description: %v", err)
	}

	infoDesc, err := dbMessageManager.GetMessage("command_info_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get info command description: %v", err)
	}

	selfhostDesc, err := dbMessageManager.GetMessage("command_selfhost_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get selfhost command description: %v", err)
	}

	helpDesc, err := dbMessageManager.GetMessage("command_help_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get help command description: %v", err)
	}

	feedbackDesc, err := dbMessageManager.GetMessage("command_feedback_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get feedback command description: %v", err)
	}

	premiumDesc, err := dbMessageManager.GetMessage("command_premium_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get premium command description: %v", err)
	}

	deleteDesc, err := dbMessageManager.GetMessage("command_delete_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get delete command description: %v", err)
	}

	adminDesc, err := dbMessageManager.GetMessage("command_admin_description", nil)
	if err != nil {
		log.Fatalf("Critical error: Could not get admin command description: %v", err)
	}

	commands := tgbotapi.NewSetMyCommands(
		tgbotapi.BotCommand{Command: "start", Description: startDesc},
		tgbotapi.BotCommand{Command: "create", Description: createDesc},
		tgbotapi.BotCommand{Command: "stat", Description: statDesc},
		tgbotapi.BotCommand{Command: "delete", Description: deleteDesc},
		tgbotapi.BotCommand{Command: "info", Description: infoDesc},
		tgbotapi.BotCommand{Command: "selfhost", Description: selfhostDesc},
		tgbotapi.BotCommand{Command: "premium", Description: premiumDesc},
		tgbotapi.BotCommand{Command: "help", Description: helpDesc},
		tgbotapi.BotCommand{Command: "feedback", Description: feedbackDesc},
		tgbotapi.BotCommand{Command: "admin", Description: adminDesc},
	)
	if _, err := bot.Request(commands); err != nil {
		log.Fatalf("Critical error: Failed to set bot commands: %v", err)
	}

	clientAddScript, err := scriptRepo.GetScriptName("client_add")
	if err != nil {
		log.Fatalf("CRITICAL: Failed to get client_add script name: %v", err)
	}

	clientRemoveScript, err := scriptRepo.GetScriptName("client_remove")
	if err != nil {
		log.Fatalf("CRITICAL: Failed to get client_remove script name: %v", err)
	}

	scriptRunner := &internal.DefaultScriptRunner{
		ClientAddScriptPath:    config.ScriptsDir + "/" + clientAddScript,
		ClientRemoveScriptPath: config.ScriptsDir + "/" + clientRemoveScript,
		Timeout:                config.ScriptTimeout,
	}

	wgService := &internal.DefaultWireGuardService{
		ClientsDir:  config.ClientsDir,
		WGInterface: config.WGInterface,
	}

	var watchdog *internal.ClientWatchdog
	if config.WatchdogEnabled {
		watchdog = internal.NewClientWatchdog(config, userRepo, wgService, scriptRunner, logger)
		watchdog.Start()
		log.Println("Watchdog started")
	}

	// Load health server configuration
	healthServerEnabledVal, err := configRepo.GetBoolOrDefault("health_server_enabled", true, false)
	if err != nil {
		log.Printf("WARNING: Failed to get health server enabled from database, using default: %v", err)
	}
	config.HealthServerEnabled = healthServerEnabledVal

	healthServerPortVal, err := configRepo.GetIntOrDefault("health_server_port", 8080, false)
	if err != nil {
		log.Printf("WARNING: Failed to get health server port from database, using default: %v", err)
	}
	config.HealthServerPort = healthServerPortVal

	var healthServer *internal.HealthServer
	if config.HealthServerEnabled {
		healthServer = internal.NewHealthServer(dbManager.GetDB(), config.HealthServerPort)
		if err := healthServer.Start(); err != nil {
			log.Printf("WARNING: Failed to start health server: %v", err)
		}
		defer healthServer.Stop()
	} else {
		log.Println("Health server is disabled")
	}

	backupEnabledVal, _ := configRepo.GetBoolOrDefault("backup_enabled", true, false)
	backupIntervalVal, _ := configRepo.GetIntOrDefault("backup_interval_hours", 24, false)
	backupRetentionVal, _ := configRepo.GetIntOrDefault("backup_retention_days", 7, false)
	backupDirectoryVal, _ := configRepo.GetStringOrDefault("backup_directory", filepath.Join(execDir, "backups"), false)

	// If the backup directory is a relative path, make it relative to the executable location
	if !filepath.IsAbs(backupDirectoryVal) {
		backupDirectoryVal = filepath.Join(execDir, backupDirectoryVal)
	}

	backupService := internal.NewBackupService(
		dbManager.GetDB(),
		config.DatabasePath,
		backupDirectoryVal,
		backupEnabledVal,
		backupIntervalVal,
		backupRetentionVal,
		logger,
	)
	if err := backupService.Start(); err != nil {
		log.Printf("WARNING: Failed to start backup service: %v", err)
	}
	defer backupService.Stop()

	botAdapter := &internal.BotAPIAdapter{BotAPI: bot}
	handler := internal.NewBotHandler(botAdapter, config, userRepo, logRepo, scriptRunner, dbMessageManager, feedbackRepo, blocklistRepo, configRepo, scriptRepo, wgService)

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60

	updates := bot.GetUpdatesChan(u)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	sem := make(chan struct{}, workerPoolSize)

	go func() {
		<-sigChan
		log.Println("Shutdown signal received, cleaning up...")
		cancel()
		bot.StopReceivingUpdates()
	}()

	log.Println("Bot is running...")

	for {
		select {
		case update := <-updates:
			sem <- struct{}{}
			go func(update tgbotapi.Update) {
				defer func() { <-sem }()

				if update.Message != nil {
					handler.HandleMessage(update)
				} else if update.CallbackQuery != nil {
					handler.HandleCallbackQuery(update)
				}
			}(update)

		case <-ctx.Done():
			if watchdog != nil {
				log.Println("Stopping watchdog...")
				watchdog.Stop()
				log.Println("Watchdog stopped")
			}
			log.Println("Stopping config reloader...")
			configReloader.Stop()
			log.Println("Bot stopped")
			return
		}
	}
}
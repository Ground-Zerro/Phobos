package internal

import (
	"log"
	"sync"
	"time"
)

type ConfigReloader struct {
	config         *BotConfig
	configRepo     ConfigRepository
	reloadInterval time.Duration
	stopChan       chan struct{}
	resetChan      chan struct{}  // Channel to signal interval change
	wg             sync.WaitGroup
	mu             sync.RWMutex
}

func NewConfigReloader(config *BotConfig, configRepo ConfigRepository, reloadInterval time.Duration) *ConfigReloader {
	return &ConfigReloader{
		config:         config,
		configRepo:     configRepo,
		reloadInterval: reloadInterval,
		stopChan:       make(chan struct{}),
		resetChan:      make(chan struct{}, 1), // Buffered to prevent blocking
	}
}

func (cr *ConfigReloader) Start() {
	cr.wg.Add(1)
	go cr.run()
	log.Printf("ConfigReloader started with interval: %v", cr.reloadInterval)
}

func (cr *ConfigReloader) Stop() {
	close(cr.stopChan)
	cr.wg.Wait()
	log.Println("ConfigReloader stopped")
}

func (cr *ConfigReloader) run() {
	defer cr.wg.Done()

	for {
		// Get the current interval
		cr.mu.RLock()
		currentInterval := cr.reloadInterval
		cr.mu.RUnlock()

		// Create timer with current interval
		timer := time.NewTimer(currentInterval)

		select {
		case <-timer.C:
			cr.reloadConfig()
		case <-cr.resetChan:
			// Interval changed, stop current timer and restart loop
			if !timer.Stop() {
				// Timer already fired, drain the channel if necessary
				select {
				case <-timer.C:
				default:
				}
			}
			// Continue to the next iteration to get new interval
		case <-cr.stopChan:
			// Stop timer if not already stopped
			if !timer.Stop() {
				// Timer already fired, drain the channel if necessary
				select {
				case <-timer.C:
				default:
				}
			}
			return
		}
	}
}

func (cr *ConfigReloader) reloadConfig() {
	cr.mu.Lock()
	defer cr.mu.Unlock()

	scriptTimeoutVal, err := cr.configRepo.GetInt("script_timeout_seconds")
	if err == nil {
		newTimeout := time.Duration(scriptTimeoutVal) * time.Second
		if cr.config.ScriptTimeout != newTimeout {
			log.Printf("Config parameter changed: script_timeout_seconds = %d", scriptTimeoutVal)
			cr.config.ScriptTimeout = newTimeout
		}
	}

	watchdogEnabledVal, err := cr.configRepo.GetBool("watchdog_enabled")
	if err == nil {
		if cr.config.WatchdogEnabled != watchdogEnabledVal {
			log.Printf("Config parameter changed: watchdog_enabled = %v", watchdogEnabledVal)
			cr.config.WatchdogEnabled = watchdogEnabledVal
		}
	}

	watchdogCheckIntervalVal, err := cr.configRepo.GetInt("watchdog_check_interval_minutes")
	if err == nil {
		newInterval := time.Duration(watchdogCheckIntervalVal) * time.Minute
		if cr.config.WatchdogCheckInterval != newInterval {
			log.Printf("Config parameter changed: watchdog_check_interval_minutes = %d", watchdogCheckIntervalVal)
			cr.config.WatchdogCheckInterval = newInterval
		}
	}

	watchdogInactiveThresholdVal, err := cr.configRepo.GetInt("watchdog_inactive_threshold_minutes")
	if err == nil {
		newThreshold := time.Duration(watchdogInactiveThresholdVal) * time.Minute
		if cr.config.WatchdogInactiveThreshold != newThreshold {
			log.Printf("Config parameter changed: watchdog_inactive_threshold_minutes = %d", watchdogInactiveThresholdVal)
			cr.config.WatchdogInactiveThreshold = newThreshold
		}
	}

	maxTestDurationVal, err := cr.configRepo.GetInt("max_test_duration_minutes")
	if err == nil {
		newDuration := time.Duration(maxTestDurationVal) * time.Minute
		if cr.config.MaxTestDuration != newDuration {
			log.Printf("Config parameter changed: max_test_duration_minutes = %d", maxTestDurationVal)
			cr.config.MaxTestDuration = newDuration
		}
	}

	restrictNewUsersVal, err := cr.configRepo.GetBool("restrict_new_users")
	if err == nil {
		if cr.config.RestrictNewUsers != restrictNewUsersVal {
			log.Printf("Config parameter changed: restrict_new_users = %v", restrictNewUsersVal)
			cr.config.RestrictNewUsers = restrictNewUsersVal
		}
	}

	maxClientsVal, err := cr.configRepo.GetInt("max_clients")
	if err == nil {
		if cr.config.MaxClients != maxClientsVal {
			log.Printf("Config parameter changed: max_clients = %d", maxClientsVal)
			cr.config.MaxClients = maxClientsVal
		}
	}

	healthServerEnabledVal, err := cr.configRepo.GetBool("health_server_enabled")
	if err == nil {
		if cr.config.HealthServerEnabled != healthServerEnabledVal {
			log.Printf("Config parameter changed: health_server_enabled = %v", healthServerEnabledVal)
			cr.config.HealthServerEnabled = healthServerEnabledVal
		}
	}

	healthServerPortVal, err := cr.configRepo.GetInt("health_server_port")
	if err == nil {
		if cr.config.HealthServerPort != healthServerPortVal {
			log.Printf("Config parameter changed: health_server_port = %d", healthServerPortVal)
			cr.config.HealthServerPort = healthServerPortVal
		}
	}

	reloadIntervalVal, err := cr.configRepo.GetInt("config_reload_interval_minutes")
	if err == nil {
		newReloadInterval := time.Duration(reloadIntervalVal) * time.Minute
		if cr.reloadInterval != newReloadInterval {
			log.Printf("Config parameter changed: config_reload_interval_minutes = %d", reloadIntervalVal)
			cr.reloadInterval = newReloadInterval

			// Signal the run loop to reset the timer
			select {
			case cr.resetChan <- struct{}{}:
				// Sent the reset signal
			default:
				// Channel is full, reset signal already pending
			}
		}
	}
}

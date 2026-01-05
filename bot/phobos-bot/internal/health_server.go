package internal

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

type HealthStatus string

const (
	StatusRunning  HealthStatus = "running"
	StatusDegraded HealthStatus = "degraded"
	StatusError    HealthStatus = "error"
)

type ComponentStatus struct {
	Name      string       `json:"name"`
	Status    HealthStatus `json:"status"`
	LastCheck time.Time    `json:"last_check"`
	Error     string       `json:"error,omitempty"`
}

type HealthResponse struct {
	Status     HealthStatus       `json:"status"`
	Timestamp  time.Time          `json:"timestamp"`
	Components []*ComponentStatus `json:"components"`
	Errors     []string           `json:"errors,omitempty"`
}

type MetricsResponse struct {
	TotalUsers       int64   `json:"total_users"`
	ActiveUsers      int64   `json:"active_users"`
	TotalConfigs     int64   `json:"total_configs"`
	DatabaseSize     int64   `json:"database_size_bytes"`
	UptimeSeconds    float64 `json:"uptime_seconds"`
	LastHealthCheck  string  `json:"last_health_check"`
}

type HealthServer struct {
	db               *sql.DB
	port             int
	status           HealthStatus
	components       map[string]*ComponentStatus
	errors           []string
	mu               sync.RWMutex
	startTime        time.Time
	server           *http.Server
}

func NewHealthServer(db *sql.DB, port int) *HealthServer {
	return &HealthServer{
		db:         db,
		port:       port,
		status:     StatusRunning,
		components: make(map[string]*ComponentStatus),
		errors:     make([]string, 0),
		startTime:  time.Now(),
	}
}

func (hs *HealthServer) Start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", hs.handleHealth)
	mux.HandleFunc("/metrics", hs.handleMetrics)

	hs.server = &http.Server{
		Addr:         fmt.Sprintf(":%d", hs.port),
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  15 * time.Second,
	}

	hs.updateComponentStatus("database", StatusRunning, "")
	hs.updateComponentStatus("bot", StatusRunning, "")

	go func() {
		log.Printf("Health server started on port %d", hs.port)
		if err := hs.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Health server error: %v", err)
		}
	}()

	go hs.periodicHealthCheck()

	return nil
}

func (hs *HealthServer) Stop() error {
	if hs.server != nil {
		return hs.server.Close()
	}
	return nil
}

func (hs *HealthServer) periodicHealthCheck() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		hs.checkDatabaseHealth()
	}
}

func (hs *HealthServer) checkDatabaseHealth() {
	err := hs.db.Ping()
	if err != nil {
		hs.updateComponentStatus("database", StatusError, err.Error())
		hs.addError(fmt.Sprintf("Database ping failed: %v", err))
	} else {
		hs.updateComponentStatus("database", StatusRunning, "")
	}
}

func (hs *HealthServer) updateComponentStatus(name string, status HealthStatus, errorMsg string) {
	hs.mu.Lock()
	defer hs.mu.Unlock()

	hs.components[name] = &ComponentStatus{
		Name:      name,
		Status:    status,
		LastCheck: time.Now(),
		Error:     errorMsg,
	}

	overallStatus := StatusRunning
	for _, comp := range hs.components {
		if comp.Status == StatusError {
			overallStatus = StatusError
			break
		} else if comp.Status == StatusDegraded {
			overallStatus = StatusDegraded
		}
	}
	hs.status = overallStatus
}

func (hs *HealthServer) addError(errorMsg string) {
	hs.mu.Lock()
	defer hs.mu.Unlock()

	hs.errors = append(hs.errors, errorMsg)
	if len(hs.errors) > 10 {
		hs.errors = hs.errors[len(hs.errors)-10:]
	}
}

func (hs *HealthServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	hs.mu.RLock()
	defer hs.mu.RUnlock()

	components := make([]*ComponentStatus, 0, len(hs.components))
	for _, comp := range hs.components {
		components = append(components, comp)
	}

	response := HealthResponse{
		Status:     hs.status,
		Timestamp:  time.Now(),
		Components: components,
		Errors:     hs.errors,
	}

	w.Header().Set("Content-Type", "application/json")

	statusCode := http.StatusOK
	if hs.status == StatusDegraded {
		statusCode = http.StatusOK
	} else if hs.status == StatusError {
		statusCode = http.StatusServiceUnavailable
	}
	w.WriteHeader(statusCode)

	json.NewEncoder(w).Encode(response)
}

func (hs *HealthServer) handleMetrics(w http.ResponseWriter, r *http.Request) {
	var totalUsers, activeUsers, totalConfigs int64
	var dbSize int64

	hs.db.QueryRow("SELECT COUNT(*) FROM users").Scan(&totalUsers)
	hs.db.QueryRow("SELECT COUNT(*) FROM users WHERE updated_at > datetime('now', '-24 hours')").Scan(&activeUsers)

	rows, err := hs.db.Query("SELECT username FROM users")
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			totalConfigs++
		}
	}

	hs.db.QueryRow("SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()").Scan(&dbSize)

	uptime := time.Since(hs.startTime).Seconds()

	response := MetricsResponse{
		TotalUsers:      totalUsers,
		ActiveUsers:     activeUsers,
		TotalConfigs:    totalConfigs,
		DatabaseSize:    dbSize,
		UptimeSeconds:   uptime,
		LastHealthCheck: time.Now().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (hs *HealthServer) UpdateBotStatus(status HealthStatus, errorMsg string) {
	hs.updateComponentStatus("bot", status, errorMsg)
	if errorMsg != "" {
		hs.addError(errorMsg)
	}
}

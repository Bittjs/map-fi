package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// --- DTO & STRUCTS ---

type AuthDeviceRequest struct {
	DeviceToken string `json:"device_token"`
}

type AuthDeviceResponse struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
}

type CreatePointRequest struct {
	SSID        string  `json:"ssid"`
	Password    string  `json:"password,omitempty"`
	Latitude    float64 `json:"lat"`
	Longitude   float64 `json:"lon"`
	DatasetType string  `json:"dataset_type,omitempty"`
}

type PointResponse struct {
	ID          string    `json:"id"`
	RegionID    int       `json:"region_id"`
	SSID        string    `json:"ssid"`
	Password    string    `json:"password,omitempty"`
	DatasetType string    `json:"dataset_type"`
	Latitude    float64   `json:"lat"`
	Longitude   float64   `json:"lon"`
	IsDeleted   bool      `json:"is_deleted"`
	UpdatedAt   time.Time `json:"updated_at"`
	Upvotes     int       `json:"upvotes"`
	Downvotes   int       `json:"downvotes"`
}

type PointStatsResponse struct {
	PointID    string         `json:"point_id"`
	RegionID   int            `json:"region_id"`
	Days       int            `json:"days"`
	Counts     map[string]int `json:"counts"`
	Checks     int            `json:"checks"`
	Complaints int            `json:"complaints"`
}

type CreateFeedbackRequest struct {
	PointID  string `json:"ap_id"`
	RegionID int    `json:"region_id"`
	Type     string `json:"type"`
}

type SyncResponse struct {
	ServerTime time.Time       `json:"server_time"`
	Points     []PointResponse `json:"points"`
}

// --- СЕРВЕРНЫЙ КОНТЕКСТ ---

// Простой in-memory rate limiter: не более одного запроса на ключ
// в течение minInterval.
type rateLimiter struct {
	mu          sync.Mutex
	attempts    map[string]time.Time
	minInterval time.Duration
}

func newRateLimiter(minInterval time.Duration) *rateLimiter {
	return &rateLimiter{attempts: make(map[string]time.Time), minInterval: minInterval}
}

func (rl *rateLimiter) allow(key string) bool {
	now := time.Now()
	rl.mu.Lock()
	defer rl.mu.Unlock()
	last, ok := rl.attempts[key]
	if !ok || now.Sub(last) >= rl.minInterval {
		rl.attempts[key] = now
		return true
	}
	return false
}

type Application struct {
	db              *pgxpool.Pool
	pointLimiter    *rateLimiter
	feedbackLimiter *rateLimiter
}

func main() {
	dbUrl := os.Getenv("DATABASE_URL")
	if dbUrl == "" {
		dbUrl = "postgres://postgres:postgres@localhost:5432/postgres?sslmode=disable"
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbUrl)
	if err != nil {
		log.Fatalf("Ошибка подключения к БД: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("База данных недоступна: %v", err)
	}

	app := &Application{
		db:              pool,
		pointLimiter:    newRateLimiter(10 * time.Second),
		feedbackLimiter: newRateLimiter(5 * time.Second),
	}

	router := http.NewServeMux()

	// Маршруты API v1
	router.HandleFunc("POST /api/v1/auth/device", app.handleAuthDevice)
	router.HandleFunc("GET /api/v1/sync", app.handleSync)
	router.HandleFunc("GET /api/v1/regions", app.handleListRegions)
	router.HandleFunc("GET /api/v1/points/{id}/stats", app.handlePointStats)
	router.HandleFunc("POST /api/v1/points", app.handleCreatePoint)
	router.HandleFunc("POST /api/v1/feedbacks", app.handleCreateFeedback)

	server := &http.Server{
		Addr:         ":23125",
		Handler:      router,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	log.Println("Сервер бэкенда запущен на :23125")
	if err := server.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}

// --- ХЕЛПЕРЫ ---

func hashDeviceToken(token string) []byte {
	h := sha256.Sum256([]byte(token))
	return h[:]
}

// Слои dataset_type, доступные роли. Роль по умолчанию видит только public.
func allowedDatasetsForRole(role string) []string {
	switch role {
	case "volunteer":
		return []string{"public", "volunteer_test"}
	case "admin":
		return []string{"public", "volunteer_test", "dev_test"}
	default:
		return []string{"public"}
	}
}

// Роль пользователя по ID; при отсутствии/ошибке — default.
func (app *Application) userRole(ctx context.Context, userID string) string {
	if userID == "" {
		return "default"
	}
	var role string
	err := app.db.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, userID).Scan(&role)
	if err != nil {
		return "default"
	}
	return role
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

// --- ХЕНДЛЕРЫ ---

// 1. POST /api/v1/auth/device — Авторизация/регистрация устройства
func (app *Application) handleAuthDevice(w http.ResponseWriter, r *http.Request) {
	var req AuthDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.DeviceToken == "" {
		writeError(w, http.StatusBadRequest, "Неверный формат запроса или отсутствует device_token")
		return
	}

	tokenHash := hashDeviceToken(req.DeviceToken)

	var userID, role string
	var isBanned bool

	// Создаем пользователя, если не существует (UPSERT)
	query := `
		INSERT INTO users (device_token_hash) 
		VALUES ($1)
		ON CONFLICT (device_token_hash) 
		DO UPDATE SET device_token_hash = EXCLUDED.device_token_hash
		RETURNING id, role, is_banned;
	`

	err := app.db.QueryRow(r.Context(), query, tokenHash).Scan(&userID, &role, &isBanned)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Ошибка работы с базой данных")
		log.Printf("Err auth: %v", err)
		return
	}

	if isBanned {
		writeError(w, http.StatusForbidden, "Доступ устройства заблокирован")
		return
	}

	writeJSON(w, http.StatusOK, AuthDeviceResponse{
		UserID: userID,
		Role:   role,
	})
}

// 2. GET /api/v1/sync — Дельта-синхронизация (ролевой фильтр слоёв)
func (app *Application) handleSync(w http.ResponseWriter, r *http.Request) {
	regionIDStr := r.URL.Query().Get("region_id")
	sinceStr := r.URL.Query().Get("since")

	if regionIDStr == "" {
		writeError(w, http.StatusBadRequest, "Параметр region_id обязателен")
		return
	}

	regionID, err := strconv.Atoi(regionIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "Параметр region_id должен быть числом")
		return
	}

	var sinceTime time.Time
	if sinceStr != "" {
		sinceTime, err = time.Parse(time.RFC3339, sinceStr)
		if err != nil {
			writeError(w, http.StatusBadRequest, "Неверный формат времени 'since' (ожидается RFC3339/ISO8601)")
			return
		}
	}

// Ролевой фильтр слоёв dataset_type по заголовку X-User-ID
	role := app.userRole(r.Context(), r.Header.Get("X-User-ID"))
	datasets := allowedDatasetsForRole(role)

	query := `
		SELECT ap.id, ap.region_id, ap.dataset_type, ap.ssid, COALESCE(ap.password, ''),
		       ST_Y(ap.geo_point) as lat, ST_X(ap.geo_point) as lon, ap.is_deleted, ap.updated_at,
		       (SELECT count(*) FROM ap_feedbacks f
		        WHERE f.ap_id = ap.id AND f.region_id = ap.region_id
		          AND f.status = 'accepted' AND f.type = 'verify') AS upvotes,
		       (SELECT count(*) FROM ap_feedbacks f
		        WHERE f.ap_id = ap.id AND f.region_id = ap.region_id
		          AND f.status = 'accepted' AND f.type <> 'verify') AS downvotes
		FROM access_points ap
		WHERE ap.region_id = $1 AND ap.dataset_type = ANY($2) AND ap.updated_at > $3
		ORDER BY ap.updated_at ASC
		LIMIT 5000;`

	rows, err := app.db.Query(r.Context(), query, regionID, datasets, sinceTime)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Ошибка запроса синхронизации")
		log.Printf("Err sync: %v", err)
		return
	}
	defer rows.Close()

	points := []PointResponse{}
	for rows.Next() {
		var p PointResponse
		err := rows.Scan(
			&p.ID, &p.RegionID, &p.DatasetType, &p.SSID, &p.Password,
			&p.Latitude, &p.Longitude, &p.IsDeleted, &p.UpdatedAt,
			&p.Upvotes, &p.Downvotes,
		)
		if err != nil {
			continue
		}
		points = append(points, p)
	}

	writeJSON(w, http.StatusOK, SyncResponse{
		ServerTime: time.Now().UTC(),
		Points:     points,
	})
}

// 3. POST /api/v1/points — Создание точки с автоопределением региона через PostGIS
func (app *Application) handleCreatePoint(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID") // Идентификатор передается из Middleware авторизации
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "Заголовок X-User-ID обязателен")
		return
	}

	if !app.pointLimiter.allow(userID) {
		writeError(w, http.StatusTooManyRequests, "Слишком много запросов. Подождите немного.")
		return
	}

	var req CreatePointRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Неверный формат JSON")
		return
	}

	if req.SSID == "" || req.Latitude == 0 || req.Longitude == 0 {
		writeError(w, http.StatusBadRequest, "Заполните обязательные поля: ssid, lat, lon")
		return
	}

	if req.DatasetType == "" {
		req.DatasetType = "public"
	}

	// 1. Авто-определение region_id по координатам WGS84 через ST_Contains
	var regionID int
	regionQuery := `
		SELECT id FROM regions 
		WHERE ST_Contains(polygon, ST_SetSRID(ST_MakePoint($1, $2), 4326)) 
		LIMIT 1;
	`
	err := app.db.QueryRow(r.Context(), regionQuery, req.Longitude, req.Latitude).Scan(&regionID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// Если геометрия не попала ни в один регион, задаем дефолтный регион
			regionID = 0
		} else {
			writeError(w, http.StatusInternalServerError, "Ошибка гео-определения региона")
			return
		}
	}

	// 2. Вставка точки доступа
	insertQuery := `
		INSERT INTO access_points (region_id, dataset_type, ssid, password, author_id, geo_point)
		VALUES ($1, $2, $3, $4, $5, ST_SetSRID(ST_MakePoint($6, $7), 4326))
		RETURNING id, updated_at;
	`

	var pointID string
	var updatedAt time.Time

	err = app.db.QueryRow(
		r.Context(), insertQuery,
		regionID, req.DatasetType, req.SSID, req.Password, userID, req.Longitude, req.Latitude,
	).Scan(&pointID, &updatedAt)

	if err != nil {
		writeError(w, http.StatusInternalServerError, "Ошибка сохранения точки")
		log.Printf("Err create point: %v", err)
		return
	}

	writeJSON(w, http.StatusCreated, PointResponse{
		ID:          pointID,
		RegionID:    regionID,
		SSID:        req.SSID,
		Password:    req.Password,
		DatasetType: req.DatasetType,
		Latitude:    req.Latitude,
		Longitude:   req.Longitude,
		IsDeleted:   false,
		UpdatedAt:   updatedAt,
		Upvotes:     0,
		Downvotes:   0,
	})
}

// 4. POST /api/v1/feedbacks — Отправка отзыва по точке
func (app *Application) handleCreateFeedback(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "Заголовок X-User-ID обязателен")
		return
	}

	if !app.feedbackLimiter.allow(userID) {
		writeError(w, http.StatusTooManyRequests, "Слишком много запросов. Подождите немного.")
		return
	}

	var req CreateFeedbackRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Неверный формат JSON")
		return
	}

	query := `
		INSERT INTO ap_feedbacks (ap_id, region_id, user_id, type)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (ap_id, region_id, user_id) 
		DO UPDATE SET type = EXCLUDED.type, created_at = CURRENT_TIMESTAMP
		RETURNING id;
	`

	var feedbackID string
	err := app.db.QueryRow(r.Context(), query, req.PointID, req.RegionID, userID, req.Type).Scan(&feedbackID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Ошибка отправки отзыва (проверьте существование ap_id и region_id)")
		log.Printf("Err feedback: %v", err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{
		"id":     feedbackID,
		"status": "accepted",
	})
}

// 5. GET /api/v1/regions — Список регионов для клиента
func (app *Application) handleListRegions(w http.ResponseWriter, r *http.Request) {
	rows, err := app.db.Query(r.Context(), `SELECT id, name FROM regions ORDER BY id`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Ошибка запроса регионов")
		log.Printf("Err regions: %v", err)
		return
	}
	defer rows.Close()

	type region struct {
		ID   int    `json:"id"`
		Name string `json:"name"`
	}
	regions := []region{}
	for rows.Next() {
		var rg region
		if err := rows.Scan(&rg.ID, &rg.Name); err != nil {
			continue
		}
		regions = append(regions, rg)
	}

	writeJSON(w, http.StatusOK, map[string]any{"regions": regions})
}

// 6. GET /api/v1/points/{id}/stats — Агрегированные отзывы по точке за период
func (app *Application) handlePointStats(w http.ResponseWriter, r *http.Request) {
	pointID := r.PathValue("id")
	regionIDStr := r.URL.Query().Get("region_id")
	daysStr := r.URL.Query().Get("days")

	if pointID == "" {
		writeError(w, http.StatusBadRequest, "Не указан id точки")
		return
	}
	regionID, err := strconv.Atoi(regionIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "Параметр region_id обязателен и должен быть числом")
		return
	}

	days := 30
	if daysStr != "" {
		days, err = strconv.Atoi(daysStr)
		if err != nil {
			writeError(w, http.StatusBadRequest, "Параметр days должен быть числом")
			return
		}
	}
	if days <= 0 {
		days = 30
	}
	if days > 3650 {
		days = 3650
	}

	since := time.Now().UTC().Add(-time.Duration(days) * 24 * time.Hour)

	query := `
		SELECT type, count(*)
		FROM ap_feedbacks
		WHERE ap_id = $1 AND region_id = $2
		  AND status = 'accepted' AND created_at >= $3
		GROUP BY type;`

	rows, err := app.db.Query(r.Context(), query, pointID, regionID, since)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Ошибка запроса статистики точки")
		log.Printf("Err stats: %v", err)
		return
	}
	defer rows.Close()

	counts := map[string]int{}
	for rows.Next() {
		var t string
		var c int
		if err := rows.Scan(&t, &c); err != nil {
			continue
		}
		counts[t] = c
	}

	checks, complaints := aggregateCounts(counts)

	writeJSON(w, http.StatusOK, PointStatsResponse{
		PointID:    pointID,
		RegionID:   regionID,
		Days:       days,
		Counts:     counts,
		Checks:     checks,
		Complaints: complaints,
	})
}

// Вспомогательный расчёт агрегатов отзывов (используется и в тестах).
// verify считается проверкой (green), остальные типы — жалобами (red).
func aggregateCounts(counts map[string]int) (checks, complaints int) {
	for k, v := range counts {
		if k == "verify" {
			checks += v
		} else {
			complaints += v
		}
	}
	return checks, complaints
}

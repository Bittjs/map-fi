-- 002: индексы для статистики отзывов (GET /api/v1/points/{id}/stats)
-- Применение: psql -U postgres -d postgres -f server/setup/002_feedback_stats.sql
CREATE INDEX IF NOT EXISTS idx_feedbacks_ap_created
    ON ap_feedbacks (ap_id, created_at);
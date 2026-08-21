CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TYPE user_role AS ENUM ('default', 'volunteer', 'admin');
CREATE TYPE dataset_type AS ENUM ('public', 'volunteer_test', 'dev_test');
CREATE TYPE feedback_type AS ENUM ('verify', 'wrong_password', 'point_not_found', 'spam_fake', 'other');
CREATE TYPE moderation_status AS ENUM ('pending', 'accepted', 'rejected');

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_token_hash BYTEA NOT NULL UNIQUE,
    role user_role NOT NULL DEFAULT 'default',
    is_banned BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Таблица гео-границ регионов для авто-определения region_id
CREATE TABLE regions (
    id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    polygon GEOMETRY(MultiPolygon, 4326) NOT NULL
);
CREATE INDEX idx_regions_polygon ON regions USING GIST(polygon);

-- Таблица точек доступа
CREATE TABLE access_points (
    id UUID DEFAULT gen_random_uuid(),
    region_id INT NOT NULL,
    dataset_type dataset_type NOT NULL DEFAULT 'public',
    ssid VARCHAR(64) NOT NULL,
    password VARCHAR(64),
    author_id UUID NOT NULL REFERENCES users(id),
    geo_point GEOMETRY(Point, 4326) NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (id, region_id)
) PARTITION BY LIST (region_id);

CREATE TABLE ap_default PARTITION OF access_points DEFAULT;
CREATE TABLE ap_novosibirsk PARTITION OF access_points FOR VALUES IN (54);
CREATE TABLE ap_moscow PARTITION OF access_points FOR VALUES IN (77);

CREATE INDEX idx_ap_geo ON access_points USING GIST(geo_point);
CREATE INDEX idx_ap_region_updated ON access_points(region_id, updated_at DESC);

-- Таблица отзывов
CREATE TABLE ap_feedbacks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ap_id UUID NOT NULL,
    region_id INT NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    type feedback_type NOT NULL,
    status moderation_status NOT NULL DEFAULT 'accepted',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (ap_id, region_id) REFERENCES access_points(id, region_id) ON DELETE CASCADE,
    CONSTRAINT uk_user_ap_feedback UNIQUE (ap_id, region_id, user_id)
);

CREATE INDEX idx_feedbacks_ap_type ON ap_feedbacks(ap_id, type);

-- Пример загрузки границ регионов (Новосибирская область и Москва - упрощенные полигоны)
INSERT INTO regions (id, name, polygon) VALUES 
(54, 'Новосибирская область', ST_GeomFromText('MULTIPOLYGON(((82.0 54.0, 84.0 54.0, 84.0 56.0, 82.0 56.0, 82.0 54.0)))', 4326)),
(77, 'Москва', ST_GeomFromText('MULTIPOLYGON(((37.0 55.0, 38.0 55.0, 38.0 56.0, 37.0 56.0, 37.0 55.0)))', 4326));
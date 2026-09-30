-- ============================================================
--  Smart City Parking – PostgreSQL Schema
-- ============================================================

-- Enable pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
--  DRIVERS
-- ============================================================
CREATE TABLE drivers (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(100) NOT NULL,
    phone           VARCHAR(20),
    email           VARCHAR(100),
    license_number  VARCHAR(30)  NOT NULL UNIQUE,
    created_at      TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- ============================================================
--  VEHICLES
-- ============================================================
CREATE TABLE vehicles (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id       UUID        NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    license_plate   VARCHAR(15)  NOT NULL UNIQUE,
    make            VARCHAR(50),
    model           VARCHAR(50),
    year            INTEGER     CHECK (year BETWEEN 1886 AND EXTRACT(YEAR FROM NOW())::INTEGER + 1),
    color           VARCHAR(20),
    vehicle_type    VARCHAR(10),                          -- e.g. 'car', 'motorcycle', 'truck'
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE
);

-- ============================================================
--  ZONES
-- ============================================================
CREATE TABLE zones (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_code               VARCHAR(50)     NOT NULL UNIQUE,
    name                    VARCHAR(100)    NOT NULL,
    location_description    VARCHAR(200),
    coordinates             POINT,                        -- PostgreSQL geometric type
    hourly_rate             NUMERIC(5, 2)   NOT NULL CHECK (hourly_rate >= 0),
    max_duration_minutes    INTEGER         CHECK (max_duration_minutes > 0),
    zone_type               VARCHAR(20),                  -- e.g. 'street', 'garage', 'lot'
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE
);

-- ============================================================
--  ENFORCEMENT_OFFICERS
-- ============================================================
CREATE TABLE enforcement_officers (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    badge_number    VARCHAR(50)  NOT NULL UNIQUE,
    full_name       VARCHAR(100) NOT NULL,
    role            VARCHAR(20),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- ============================================================
--  APPEAL_REVIEWERS
-- ============================================================
CREATE TABLE appeal_reviewers (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name   VARCHAR(100) NOT NULL,
    department  VARCHAR(50),
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- ============================================================
--  SENSORS
-- ============================================================
CREATE TABLE sensors (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_id         UUID        NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
    sensor_code     VARCHAR(50)  NOT NULL UNIQUE,
    spot_number     INTEGER,
    status          VARCHAR(20)  NOT NULL DEFAULT 'active',   -- 'active', 'offline', 'maintenance'
    last_heartbeat  TIMESTAMP
);

-- ============================================================
--  PARKING_SESSIONS
-- ============================================================
CREATE TABLE parking_sessions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id      UUID        NOT NULL REFERENCES vehicles(id),
    zone_id         UUID        NOT NULL REFERENCES zones(id),
    sensor_id       UUID        REFERENCES sensors(id),
    start_time      TIMESTAMP   NOT NULL,
    end_time        TIMESTAMP,
    duration_minutes INTEGER    GENERATED ALWAYS AS (
                        EXTRACT(EPOCH FROM (end_time - start_time)) / 60
                    ) STORED,
    amount_due      NUMERIC(8, 2) CHECK (amount_due >= 0),
    session_status  VARCHAR(20)  NOT NULL DEFAULT 'active',   -- 'active', 'completed', 'overstay'
    entry_method    VARCHAR(20),                              -- 'sensor', 'app', 'kiosk'
    created_at      TIMESTAMP   NOT NULL DEFAULT NOW(),
    CONSTRAINT end_after_start CHECK (end_time IS NULL OR end_time > start_time)
);

-- ============================================================
--  PAYMENTS
-- ============================================================
CREATE TABLE payments (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID        NOT NULL REFERENCES parking_sessions(id),
    driver_id       UUID        NOT NULL REFERENCES drivers(id),
    transaction_ref VARCHAR(50)  NOT NULL UNIQUE,
    amount          NUMERIC(8, 2) NOT NULL CHECK (amount >= 0),
    payment_method  VARCHAR(20),                              -- 'card', 'app', 'cash', 'rfid'
    payment_status  VARCHAR(20)  NOT NULL DEFAULT 'pending',  -- 'pending', 'completed', 'failed', 'refunded'
    paid_at         TIMESTAMP,
    gateway_response VARCHAR(100),
    created_at      TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- ============================================================
--  VIOLATIONS
-- ============================================================
CREATE TABLE violations (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID        REFERENCES parking_sessions(id),
    vehicle_id      UUID        NOT NULL REFERENCES vehicles(id),
    zone_id         UUID        NOT NULL REFERENCES zones(id),
    issued_by       UUID        NOT NULL REFERENCES enforcement_officers(id),
    violation_code  VARCHAR(30)  NOT NULL,
    violation_type  VARCHAR(100) NOT NULL,
    fine_amount     NUMERIC(8, 2) NOT NULL CHECK (fine_amount >= 0),
    violation_status VARCHAR(20) NOT NULL DEFAULT 'unpaid',   -- 'unpaid', 'paid', 'appealed', 'waived'
    issued_at       TIMESTAMP   NOT NULL DEFAULT NOW(),
    notes           TEXT,
    evidence_url    VARCHAR(255)
);

-- ============================================================
--  APPEALS
-- ============================================================
CREATE TABLE appeals (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    violation_id    UUID        NOT NULL REFERENCES violations(id),
    driver_id       UUID        NOT NULL REFERENCES drivers(id),
    reason          TEXT        NOT NULL,
    appeal_status   VARCHAR(20)  NOT NULL DEFAULT 'pending',  -- 'pending', 'under_review', 'resolved'
    submitted_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
    reviewed_at     TIMESTAMP,
    reviewed_by     UUID        REFERENCES appeal_reviewers(id),
    outcome         VARCHAR(20),                              -- 'upheld', 'overturned', 'partial'
    outcome_notes   TEXT
);

-- ============================================================
--  PAYMENT_AUDIT_LOG
-- ============================================================
CREATE TABLE payment_audit_log (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id  UUID        NOT NULL REFERENCES payments(id),
    action      VARCHAR(30)  NOT NULL,
    old_status  VARCHAR(20),
    new_status  VARCHAR(20),
    changed_at  TIMESTAMP   NOT NULL DEFAULT NOW(),
    changed_by  VARCHAR(100)
);

-- ============================================================
--  INDEXES  (performance-critical foreign keys & filter columns)
-- ============================================================
CREATE INDEX idx_vehicles_driver_id           ON vehicles(driver_id);
CREATE INDEX idx_sensors_zone_id              ON sensors(zone_id);
CREATE INDEX idx_parking_sessions_vehicle_id  ON parking_sessions(vehicle_id);
CREATE INDEX idx_parking_sessions_zone_id     ON parking_sessions(zone_id);
CREATE INDEX idx_parking_sessions_sensor_id   ON parking_sessions(sensor_id);
CREATE INDEX idx_parking_sessions_start_time  ON parking_sessions(start_time);
CREATE INDEX idx_payments_session_id          ON payments(session_id);
CREATE INDEX idx_payments_driver_id           ON payments(driver_id);
CREATE INDEX idx_payments_payment_status      ON payments(payment_status);
CREATE INDEX idx_violations_vehicle_id        ON violations(vehicle_id);
CREATE INDEX idx_violations_zone_id           ON violations(zone_id);
CREATE INDEX idx_violations_session_id        ON violations(session_id);
CREATE INDEX idx_violations_issued_by         ON violations(issued_by);
CREATE INDEX idx_violations_issued_at         ON violations(issued_at);
CREATE INDEX idx_appeals_violation_id         ON appeals(violation_id);
CREATE INDEX idx_appeals_driver_id            ON appeals(driver_id);
CREATE INDEX idx_appeals_reviewed_by          ON appeals(reviewed_by);
CREATE INDEX idx_payment_audit_log_payment_id ON payment_audit_log(payment_id);

-- ============================================================
--  TRIGGER – auto-update drivers.updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_drivers_updated_at
    BEFORE UPDATE ON drivers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
--  TRIGGER – auto-insert payment audit log row on status change
-- ============================================================
CREATE OR REPLACE FUNCTION log_payment_status_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.payment_status IS DISTINCT FROM NEW.payment_status THEN
        INSERT INTO payment_audit_log (payment_id, action, old_status, new_status, changed_by)
        VALUES (NEW.id, 'status_change', OLD.payment_status, NEW.payment_status, current_user);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_payment_audit
    AFTER UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION log_payment_status_change();

-- ============================================================
--  TRIGGER – mark violation status 'appealed' when appeal filed
-- ============================================================
CREATE OR REPLACE FUNCTION flag_violation_appealed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE violations SET violation_status = 'appealed' WHERE id = NEW.violation_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_violation_appealed
    AFTER INSERT ON appeals
    FOR EACH ROW EXECUTE FUNCTION flag_violation_appealed();

-- ============================================================
--  VIEWS
-- ============================================================

-- Active parking sessions with driver & zone detail
CREATE VIEW v_active_sessions AS
SELECT
    ps.id              AS session_id,
    v.license_plate,
    d.full_name        AS driver_name,
    d.phone            AS driver_phone,
    z.zone_code,
    z.name             AS zone_name,
    ps.start_time,
    ps.entry_method,
    ps.session_status
FROM parking_sessions ps
JOIN vehicles  v ON v.id = ps.vehicle_id
JOIN drivers   d ON d.id = v.driver_id
JOIN zones     z ON z.id = ps.zone_id
WHERE ps.session_status = 'active';

-- Outstanding (unpaid) violations
CREATE VIEW v_outstanding_violations AS
SELECT
    vio.id             AS violation_id,
    vio.violation_code,
    vio.violation_type,
    vio.fine_amount,
    vio.issued_at,
    veh.license_plate,
    d.full_name        AS driver_name,
    d.phone,
    z.zone_code,
    eo.full_name       AS officer_name
FROM violations vio
JOIN vehicles              veh ON veh.id  = vio.vehicle_id
JOIN drivers               d   ON d.id    = veh.driver_id
JOIN zones                 z   ON z.id    = vio.zone_id
JOIN enforcement_officers  eo  ON eo.id   = vio.issued_by
WHERE vio.violation_status = 'unpaid';

-- Revenue summary per zone
CREATE VIEW v_zone_revenue AS
SELECT
    z.zone_code,
    z.name                        AS zone_name,
    COUNT(p.id)                   AS total_payments,
    COALESCE(SUM(p.amount), 0)    AS total_revenue,
    COALESCE(AVG(p.amount), 0)    AS avg_payment
FROM zones z
LEFT JOIN parking_sessions ps ON ps.zone_id = z.id
LEFT JOIN payments          p  ON p.session_id = ps.id AND p.payment_status = 'completed'
GROUP BY z.id, z.zone_code, z.name;

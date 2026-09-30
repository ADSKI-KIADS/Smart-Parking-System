-- ============================================================
--  Smart City Parking — PostgreSQL Query Collection
--  Sections 6 to 10 (Assignments 2, 3)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- SECTION 6 · DML AND BASIC QUERIES
-- ────────────────────────────────────────────────────────────

-- ── ALTER TABLE ─────────────────────────────────────────────

-- 6.A1  Add loyalty_tier column to drivers
ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS loyalty_tier VARCHAR(20) DEFAULT 'bronze';

-- 6.A2  Modify gateway_response in payments to TEXT
ALTER TABLE payments
    ALTER COLUMN gateway_response TYPE TEXT;

-- 6.A3  Add positive-rate constraint to zones
ALTER TABLE zones
    ADD CONSTRAINT chk_hourly_rate_positive CHECK (hourly_rate > 0);

-- 6.A4  Add NOT NULL constraint on violation_type
ALTER TABLE violations
    ALTER COLUMN violation_type SET NOT NULL;

-- 6.A5  Rename column notes → officer_notes in violations (safe rename)
ALTER TABLE violations
    RENAME COLUMN notes TO officer_notes;


-- ── UPDATE ──────────────────────────────────────────────────

-- 6.U1  Mark all sessions older than 24h with no end_time as expired
UPDATE parking_sessions
SET    session_status = 'expired'
WHERE  session_status = 'active'
  AND  start_time < NOW() - INTERVAL '24 hours'
  AND  end_time IS NULL;

-- 6.U2  Upgrade drivers with >5 payments to 'gold' tier
UPDATE drivers d
SET    loyalty_tier = 'gold'
WHERE  (SELECT COUNT(*) FROM payments p WHERE p.driver_id = d.id) > 5;

-- 6.U3  Mark unpaid violations older than 90 days as 'overdue'
UPDATE violations
SET    violation_status = 'overdue'
WHERE  violation_status = 'unpaid'
  AND  issued_at < NOW() - INTERVAL '90 days';

-- 6.U4  Deactivate sensors with no heartbeat for 30+ days
UPDATE sensors
SET    status = 'inactive'
WHERE  status = 'active'
  AND  last_heartbeat < NOW() - INTERVAL '30 days';

-- 6.U5  Raise hourly rate by 10% for all garage zones
UPDATE zones
SET    hourly_rate = ROUND(hourly_rate * 1.10, 2)
WHERE  zone_type = 'garage';


-- ── DELETE ──────────────────────────────────────────────────

-- 6.D1  Delete cancelled sessions with no associated payment
DELETE FROM parking_sessions
WHERE  session_status = 'cancelled'
  AND  id NOT IN (SELECT DISTINCT session_id FROM payments);

-- 6.D2  Remove failed payments older than 1 year
-- (audit rows reference payments, so they are removed first)
DELETE FROM payment_audit_log
WHERE  payment_id IN (
    SELECT id FROM payments
    WHERE  payment_status = 'failed'
      AND  created_at < NOW() - INTERVAL '1 year'
);

DELETE FROM payments
WHERE  payment_status = 'failed'
  AND  created_at < NOW() - INTERVAL '1 year';

-- 6.D3  Delete dismissed violations with no appeal
DELETE FROM violations
WHERE  violation_status = 'dismissed'
  AND  id NOT IN (SELECT DISTINCT violation_id FROM appeals);

-- 6.D4  Remove inactive sensors that have never tracked a session
DELETE FROM sensors
WHERE  status = 'inactive'
  AND  id NOT IN (SELECT DISTINCT sensor_id FROM parking_sessions);

-- 6.D5  Delete appeal_reviewers who are inactive and have no reviews
DELETE FROM appeal_reviewers
WHERE  is_active = FALSE
  AND  id NOT IN (SELECT DISTINCT reviewed_by FROM appeals WHERE reviewed_by IS NOT NULL);


-- ── BASIC SELECT ────────────────────────────────────────────

-- 6.S1  All active drivers ordered by name
SELECT id, full_name, phone, email, license_number
FROM   drivers
ORDER  BY full_name;

-- 6.S2  Top 10 most expensive parking sessions
SELECT id, vehicle_id, zone_id, duration_minutes, amount_due, session_status
FROM   parking_sessions
ORDER  BY amount_due DESC
LIMIT  10;

-- 6.S3  Zones with hourly rate between 1 and 3, limited to 5 rows, offset 0
SELECT zone_code, name, hourly_rate, zone_type
FROM   zones
WHERE  hourly_rate BETWEEN 1.00 AND 3.00
ORDER  BY hourly_rate
LIMIT  5 OFFSET 0;

-- 6.S4  Second page of violations (rows 11–20)
SELECT id, violation_code, violation_type, fine_amount, violation_status
FROM   violations
ORDER  BY issued_at DESC
LIMIT  10 OFFSET 10;

-- 6.S5  Aliases and filtering — active vehicles with alias labels
SELECT
    v.license_plate                    AS plate,
    v.make || ' ' || v.model          AS vehicle_name,
    v.year                             AS manufacture_year,
    v.color                            AS body_color,
    v.vehicle_type                     AS type
FROM   vehicles v
WHERE  v.is_active = TRUE
ORDER  BY vehicle_name;


-- ── STRING FUNCTIONS ─────────────────────────────────────────

-- 6.STR1  CONCAT — full contact label for each driver
SELECT
    CONCAT(full_name, ' | ', phone, ' | ', email) AS contact_label,
    license_number
FROM   drivers
ORDER  BY full_name
LIMIT  20;

-- 6.STR2  UPPER — normalize zone codes for display
SELECT
    UPPER(zone_code)           AS zone_code_upper,
    UPPER(zone_type)           AS zone_type_upper,
    name,
    hourly_rate
FROM   zones
ORDER  BY zone_code_upper;

-- 6.STR3  LOWER — normalize violation types for reporting
SELECT
    violation_code,
    LOWER(violation_type)      AS violation_type_normalized,
    fine_amount,
    LOWER(violation_status)    AS status_normalized
FROM   violations
ORDER  BY fine_amount DESC
LIMIT  20;

-- 6.STR4  SUBSTRING — extract first 3 chars of license plate as area code
SELECT
    license_plate,
    SUBSTRING(license_plate FROM 1 FOR 3)  AS area_code,
    make,
    model,
    color
FROM   vehicles
ORDER  BY area_code;

-- 6.STR5  CONCAT + UPPER + SUBSTRING combined — badge display label
SELECT
    CONCAT(UPPER(SUBSTRING(full_name FROM 1 FOR 1)), '. ', badge_number) AS display_label,
    role,
    is_active
FROM   enforcement_officers
ORDER  BY badge_number
LIMIT  20;


-- ── DATE FUNCTIONS ───────────────────────────────────────────

-- 6.DT1  EXTRACT year and month from parking sessions
SELECT
    id,
    start_time,
    EXTRACT(YEAR  FROM start_time) AS session_year,
    EXTRACT(MONTH FROM start_time) AS session_month,
    duration_minutes,
    amount_due
FROM   parking_sessions
ORDER  BY start_time DESC
LIMIT  20;

-- 6.DT2  Sessions started within the last 30 days
SELECT
    id,
    vehicle_id,
    zone_id,
    start_time,
    amount_due,
    session_status
FROM   parking_sessions
WHERE  start_time >= NOW() - INTERVAL '30 days'
ORDER  BY start_time DESC;

-- 6.DT3  Age of each driver account in days
SELECT
    full_name,
    created_at,
    CURRENT_DATE - created_at::date         AS account_age_days,
    EXTRACT(YEAR FROM AGE(created_at))      AS account_age_years
FROM   drivers
ORDER  BY account_age_days DESC
LIMIT  20;

-- 6.DT4  Payments made today (using CURRENT_DATE)
SELECT
    id,
    transaction_ref,
    amount,
    payment_method,
    payment_status,
    paid_at
FROM   payments
WHERE  DATE(paid_at) = CURRENT_DATE
ORDER  BY paid_at DESC;

-- 6.DT5  Violations issued in the last 90 days with days-since label
SELECT
    violation_code,
    violation_type,
    fine_amount,
    issued_at,
    CURRENT_DATE - issued_at::date          AS days_since_issued
FROM   violations
WHERE  issued_at >= NOW() - INTERVAL '90 days'
ORDER  BY issued_at DESC;


-- ── WHERE CONDITIONS ─────────────────────────────────────────

-- 6.W1  Completed payments over 50 units made by card
SELECT transaction_ref, amount, payment_method, payment_status, paid_at
FROM   payments
WHERE  payment_status = 'completed'
  AND  amount > 50
  AND  payment_method = 'card'
ORDER  BY amount DESC;

-- 6.W2  Active zones with hourly rate > 2 and max duration >= 120 min
SELECT zone_code, name, hourly_rate, max_duration_minutes, zone_type
FROM   zones
WHERE  is_active = TRUE
  AND  hourly_rate > 2
  AND  max_duration_minutes >= 120
ORDER  BY hourly_rate DESC;

-- 6.W3  Unpaid violations with fine > 100
SELECT violation_code, violation_type, fine_amount, issued_at
FROM   violations
WHERE  violation_status = 'unpaid'
  AND  fine_amount > 100
ORDER  BY fine_amount DESC;


-- ── ORDER BY ────────────────────────────────────────────────

-- 6.OB1  Sessions ordered by amount_due descending, then start_time ascending
SELECT id, zone_id, start_time, duration_minutes, amount_due, session_status
FROM   parking_sessions
ORDER  BY amount_due DESC, start_time ASC
LIMIT  20;

-- 6.OB2  Drivers ordered by created_at descending (newest first)
SELECT full_name, email, license_number, created_at
FROM   drivers
ORDER  BY created_at DESC
LIMIT  20;


-- ── LIMIT / OFFSET ───────────────────────────────────────────

-- 6.LO1  Page 1 of violations (10 per page)
SELECT violation_code, violation_type, fine_amount, violation_status, issued_at
FROM   violations
ORDER  BY issued_at DESC
LIMIT  10 OFFSET 0;

-- 6.LO2  Page 2 of violations
SELECT violation_code, violation_type, fine_amount, violation_status, issued_at
FROM   violations
ORDER  BY issued_at DESC
LIMIT  10 OFFSET 10;

-- 6.LO3  Top 5 highest fines ever issued
SELECT violation_code, violation_type, fine_amount, vehicle_id
FROM   violations
ORDER  BY fine_amount DESC
LIMIT  5;


-- ────────────────────────────────────────────────────────────
-- SECTION 7 · MULTI-TABLE QUERIES AND JOINS
-- ────────────────────────────────────────────────────────────

-- ── INNER JOIN ───────────────────────────────────────────────

-- 7.IJ1  Drivers and their vehicles (only drivers who have vehicles)
SELECT
    d.full_name                         AS driver_name,
    d.license_number                    AS driver_license,
    v.license_plate                     AS plate,
    v.make || ' ' || v.model            AS vehicle,
    v.year,
    v.color,
    v.vehicle_type
FROM   drivers d
INNER  JOIN vehicles v ON v.driver_id = d.id
ORDER  BY d.full_name;

-- 7.IJ2  Parking sessions with their completed payments
SELECT
    ps.id                               AS session_id,
    ps.start_time,
    ps.end_time,
    ps.duration_minutes,
    ps.amount_due,
    p.transaction_ref,
    p.amount                            AS amount_paid,
    p.payment_method,
    p.payment_status
FROM   parking_sessions ps
INNER  JOIN payments p ON p.session_id = ps.id
WHERE  p.payment_status = 'completed'
ORDER  BY ps.start_time DESC;

-- 7.IJ3  Violations linked to their enforcement officer
SELECT
    v.violation_code,
    v.violation_type,
    v.fine_amount,
    v.issued_at,
    eo.badge_number,
    eo.full_name                        AS officer_name,
    eo.role
FROM   violations v
INNER  JOIN enforcement_officers eo ON eo.id = v.issued_by
ORDER  BY v.issued_at DESC;


-- ── LEFT JOIN ───────────────────────────────────────────────

-- 7.LJ1  All drivers including those with no vehicles
SELECT
    d.full_name,
    d.license_number,
    v.license_plate                     AS plate,
    v.make,
    v.model
FROM   drivers d
LEFT   JOIN vehicles v ON v.driver_id = d.id
ORDER  BY d.full_name;

-- 7.LJ2  All parking sessions including those with no payment yet
SELECT
    ps.id                               AS session_id,
    ps.start_time,
    ps.amount_due,
    ps.session_status,
    p.transaction_ref,
    p.payment_status
FROM   parking_sessions ps
LEFT   JOIN payments p ON p.session_id = ps.id
ORDER  BY ps.start_time DESC;

-- 7.LJ3  All violations including those with no appeal filed
SELECT
    v.violation_code,
    v.violation_type,
    v.fine_amount,
    v.violation_status,
    a.appeal_status,
    a.submitted_at                      AS appeal_date
FROM   violations v
LEFT   JOIN appeals a ON a.violation_id = v.id
ORDER  BY v.issued_at DESC;


-- ── RIGHT JOIN ───────────────────────────────────────────────

-- 7.RJ1  All zones including those with no sessions recorded
SELECT
    z.zone_code,
    z.name,
    z.zone_type,
    z.hourly_rate,
    ps.id                               AS session_id,
    ps.start_time
FROM   parking_sessions ps
RIGHT  JOIN zones z ON z.id = ps.zone_id
ORDER  BY z.zone_code;

-- 7.RJ2  All enforcement officers including those with no violations issued
SELECT
    eo.badge_number,
    eo.full_name                        AS officer_name,
    eo.role,
    v.violation_code,
    v.fine_amount,
    v.issued_at
FROM   violations v
RIGHT  JOIN enforcement_officers eo ON eo.id = v.issued_by
ORDER  BY eo.badge_number;


-- ── FULL JOIN ───────────────────────────────────────────────

-- 7.FJ1  All sessions and all payments (matched and unmatched)
SELECT
    ps.id                               AS session_id,
    ps.amount_due,
    ps.session_status,
    p.id                                AS payment_id,
    p.amount                            AS amount_paid,
    p.payment_status
FROM   parking_sessions ps
FULL   JOIN payments p ON p.session_id = ps.id
ORDER  BY COALESCE(ps.start_time, p.created_at) DESC;

-- 7.FJ2  All violations and all appeals — see unmatched on both sides
SELECT
    v.id                                AS violation_id,
    v.violation_type,
    v.fine_amount,
    a.id                                AS appeal_id,
    a.appeal_status,
    a.outcome
FROM   violations v
FULL   JOIN appeals a ON a.violation_id = v.id
ORDER  BY v.issued_at DESC NULLS LAST;


-- ── CROSS JOIN ───────────────────────────────────────────────

-- 7.CJ1  Cartesian product of zone_types × payment_methods (pricing matrix)
SELECT
    z_types.zone_type,
    pm.payment_method,
    'Combination for pricing analysis' AS note
FROM   (SELECT DISTINCT zone_type FROM zones)        z_types
CROSS  JOIN (SELECT DISTINCT payment_method FROM payments) pm
ORDER  BY z_types.zone_type, pm.payment_method;


-- ── NATURAL JOIN ─────────────────────────────────────────────

-- 7.NJ1  Natural join between payments and payment_audit_log on payment_id
--        NOTE: Natural join matches columns with identical names.
--        payment_audit_log.payment_id = payments.id — we need an alias approach:
SELECT
    p.transaction_ref,
    p.amount,
    p.payment_status,
    pal.action,
    pal.old_status,
    pal.new_status,
    pal.changed_at
FROM   payment_audit_log pal
NATURAL JOIN (
    SELECT id AS payment_id, transaction_ref, amount, payment_status
    FROM   payments
) p
ORDER  BY pal.changed_at DESC
LIMIT  20;


-- ── SELF JOIN ───────────────────────────────────────────────

-- 7.SJ1  Find drivers registered with the same phone area code (first 5 digits)
SELECT
    d1.full_name            AS driver_a,
    d2.full_name            AS driver_b,
    SUBSTRING(d1.phone FROM 1 FOR 5) AS shared_area_code
FROM   drivers d1
JOIN   drivers d2
    ON  SUBSTRING(d1.phone FROM 1 FOR 5) = SUBSTRING(d2.phone FROM 1 FOR 5)
    AND d1.id < d2.id          -- avoid duplicates and self-match
ORDER  BY shared_area_code
LIMIT  20;

-- 7.SJ2  Find sensors in the same zone (sibling sensors)
SELECT
    s1.sensor_code          AS sensor_a,
    s2.sensor_code          AS sensor_b,
    s1.zone_id,
    s1.status               AS status_a,
    s2.status               AS status_b
FROM   sensors s1
JOIN   sensors s2
    ON  s1.zone_id = s2.zone_id
    AND s1.id < s2.id
ORDER  BY s1.zone_id
LIMIT  20;


-- ── MULTI-TABLE: USERS + VEHICLES + SESSIONS + PAYMENTS ─────

-- 7.MT1  Full chain: driver → vehicle → session → payment
SELECT
    d.full_name                         AS driver,
    v.license_plate                     AS plate,
    v.make || ' ' || v.model            AS vehicle,
    z.zone_code,
    z.name                              AS zone_name,
    ps.start_time,
    ps.duration_minutes,
    ps.amount_due,
    p.payment_method,
    p.payment_status
FROM   drivers d
JOIN   vehicles v         ON v.driver_id   = d.id
JOIN   parking_sessions ps ON ps.vehicle_id = v.id
JOIN   zones z            ON z.id           = ps.zone_id
LEFT   JOIN payments p    ON p.session_id   = ps.id
ORDER  BY ps.start_time DESC
LIMIT  30;

-- 7.MT2  Violations + Appeals + Driver + Officer full chain
SELECT
    d.full_name                         AS driver,
    v_t.license_plate                   AS plate,
    viol.violation_code,
    viol.violation_type,
    viol.fine_amount,
    eo.full_name                        AS officer,
    a.appeal_status,
    a.outcome,
    ar.full_name                        AS reviewer
FROM   violations viol
JOIN   vehicles v_t       ON v_t.id          = viol.vehicle_id
JOIN   drivers d          ON d.id            = (SELECT driver_id FROM vehicles WHERE id = viol.vehicle_id)
JOIN   enforcement_officers eo ON eo.id      = viol.issued_by
LEFT   JOIN appeals a     ON a.violation_id  = viol.id
LEFT   JOIN appeal_reviewers ar ON ar.id     = a.reviewed_by
ORDER  BY viol.issued_at DESC
LIMIT  30;


-- ────────────────────────────────────────────────────────────
-- SECTION 8 · ADVANCED FILTERING AND CONDITIONAL LOGIC
-- ────────────────────────────────────────────────────────────

-- ── BETWEEN ──────────────────────────────────────────────────

-- 8.B1  Sessions with duration between 30 and 120 minutes
SELECT id, vehicle_id, zone_id, duration_minutes, amount_due, session_status
FROM   parking_sessions
WHERE  duration_minutes BETWEEN 30 AND 120
ORDER  BY duration_minutes;

-- 8.B2  Violations with fine between 50 and 200
SELECT violation_code, violation_type, fine_amount, violation_status, issued_at
FROM   violations
WHERE  fine_amount BETWEEN 50 AND 200
ORDER  BY fine_amount DESC;

-- 8.B3  Payments made between two specific dates
SELECT transaction_ref, amount, payment_method, payment_status, paid_at
FROM   payments
WHERE  paid_at BETWEEN '2024-01-01' AND '2024-12-31'
ORDER  BY paid_at;

-- 8.B4  Zones with hourly rate between 1.5 and 4.0
SELECT zone_code, name, hourly_rate, zone_type, max_duration_minutes
FROM   zones
WHERE  hourly_rate BETWEEN 1.5 AND 4.0
ORDER  BY hourly_rate;


-- ── IN ───────────────────────────────────────────────────────

-- 8.IN1  Sessions with specific statuses
SELECT id, vehicle_id, zone_id, session_status, amount_due
FROM   parking_sessions
WHERE  session_status IN ('active', 'overstay')
ORDER  BY amount_due DESC;

-- 8.IN2  Violations of specific types
SELECT violation_code, violation_type, fine_amount, issued_at
FROM   violations
WHERE  violation_type IN ('overtime_parking', 'no_payment', 'wrong_zone')
ORDER  BY issued_at DESC;

-- 8.IN3  Payments using card or app
SELECT transaction_ref, amount, payment_method, payment_status, paid_at
FROM   payments
WHERE  payment_method IN ('card', 'app')
  AND  payment_status = 'completed'
ORDER  BY paid_at DESC;

-- 8.IN4  Officers with roles officer or supervisor
SELECT badge_number, full_name, role, is_active
FROM   enforcement_officers
WHERE  role IN ('officer', 'supervisor')
ORDER  BY badge_number;


-- ── LIKE / ILIKE ─────────────────────────────────────────────

-- 8.LK1  Drivers whose name starts with 'A'
SELECT full_name, email, license_number
FROM   drivers
WHERE  full_name ILIKE 'a%'
ORDER  BY full_name;

-- 8.LK2  Zones located in 'Downtown' or 'Midtown'
SELECT zone_code, name, location_description, zone_type
FROM   zones
WHERE  name ILIKE '%downtown%' OR name ILIKE '%midtown%'
ORDER  BY zone_code;

-- 8.LK3  Vehicles with license plate containing 'AB'
SELECT license_plate, make, model, year, color
FROM   vehicles
WHERE  license_plate LIKE '%AB%'
ORDER  BY license_plate;

-- 8.LK4  Payments whose transaction_ref starts with 'TXN'
SELECT transaction_ref, amount, payment_method, payment_status
FROM   payments
WHERE  transaction_ref LIKE 'TXN%'
ORDER  BY paid_at DESC
LIMIT  20;


-- ── IS NULL / IS NOT NULL ────────────────────────────────────

-- 8.N1  Appeals not yet reviewed (reviewed_at IS NULL)
SELECT id, violation_id, driver_id, appeal_status, submitted_at
FROM   appeals
WHERE  reviewed_at IS NULL
ORDER  BY submitted_at;

-- 8.N2  Violations with no notes recorded
SELECT violation_code, violation_type, fine_amount, issued_at
FROM   violations
WHERE  officer_notes IS NULL;

-- 8.N3  Sessions with no end_time (still active or data issue)
SELECT id, vehicle_id, zone_id, start_time, session_status
FROM   parking_sessions
WHERE  end_time IS NULL
ORDER  BY start_time DESC
LIMIT  20;

-- 8.N4  Appeals that have been reviewed (reviewed_by IS NOT NULL)
SELECT id, violation_id, appeal_status, outcome, reviewed_at
FROM   appeals
WHERE  reviewed_by IS NOT NULL
ORDER  BY reviewed_at DESC;


-- ── CASE WHEN THEN END ───────────────────────────────────────

-- 8.C1  Classify sessions by duration
SELECT
    id,
    duration_minutes,
    amount_due,
    CASE
        WHEN duration_minutes < 30  THEN 'short'
        WHEN duration_minutes < 120 THEN 'medium'
        WHEN duration_minutes < 300 THEN 'long'
        ELSE                             'extended'
    END                                 AS duration_category,
    session_status
FROM   parking_sessions
ORDER  BY duration_minutes;

-- 8.C2  Classify violations by fine severity
SELECT
    violation_code,
    violation_type,
    fine_amount,
    CASE
        WHEN fine_amount < 50   THEN 'low'
        WHEN fine_amount < 150  THEN 'medium'
        WHEN fine_amount < 300  THEN 'high'
        ELSE                         'severe'
    END                             AS severity,
    violation_status
FROM   violations
ORDER  BY fine_amount DESC;

-- 8.C3  Payment status label with action required
SELECT
    transaction_ref,
    amount,
    payment_status,
    CASE payment_status
        WHEN 'completed' THEN 'No action needed'
        WHEN 'pending'   THEN 'Awaiting confirmation'
        WHEN 'failed'    THEN 'Retry or contact support'
        WHEN 'refunded'  THEN 'Amount returned to customer'
        ELSE                  'Unknown — investigate'
    END                      AS action_label
FROM   payments
ORDER  BY created_at DESC
LIMIT  20;

-- 8.C4  Driver loyalty tier with CASE on payment count
SELECT
    d.full_name,
    COUNT(p.id)         AS total_payments,
    CASE
        WHEN COUNT(p.id) >= 20 THEN 'platinum'
        WHEN COUNT(p.id) >= 10 THEN 'gold'
        WHEN COUNT(p.id) >= 5  THEN 'silver'
        ELSE                        'bronze'
    END                 AS computed_tier
FROM   drivers d
LEFT   JOIN payments p ON p.driver_id = d.id
GROUP  BY d.id, d.full_name
ORDER  BY total_payments DESC;


-- ────────────────────────────────────────────────────────────
-- SECTION 9 · AGGREGATE FUNCTIONS AND GROUP BY
-- ────────────────────────────────────────────────────────────

-- ── COUNT / SUM / AVG / MIN / MAX ────────────────────────────

-- 9.AG1  Total revenue, average payment, min and max payment
SELECT
    COUNT(*)                            AS total_payments,
    SUM(amount)                         AS total_revenue,
    ROUND(AVG(amount), 2)               AS avg_payment,
    MIN(amount)                         AS min_payment,
    MAX(amount)                         AS max_payment
FROM   payments
WHERE  payment_status = 'completed';

-- 9.AG2  Session statistics per zone
SELECT
    z.zone_code,
    z.name                              AS zone_name,
    z.zone_type,
    COUNT(ps.id)                        AS total_sessions,
    ROUND(AVG(ps.duration_minutes), 1)  AS avg_duration_min,
    SUM(ps.amount_due)                  AS total_revenue,
    MIN(ps.amount_due)                  AS min_charge,
    MAX(ps.amount_due)                  AS max_charge
FROM   zones z
LEFT   JOIN parking_sessions ps ON ps.zone_id = z.id
GROUP  BY z.id, z.zone_code, z.name, z.zone_type
ORDER  BY total_revenue DESC NULLS LAST;

-- 9.AG3  Violation statistics per violation type
SELECT
    violation_type,
    COUNT(*)                            AS total_violations,
    SUM(fine_amount)                    AS total_fines,
    ROUND(AVG(fine_amount), 2)          AS avg_fine,
    MIN(fine_amount)                    AS min_fine,
    MAX(fine_amount)                    AS max_fine
FROM   violations
GROUP  BY violation_type
ORDER  BY total_fines DESC;

-- 9.AG4  Monthly revenue report
SELECT
    EXTRACT(YEAR  FROM paid_at)         AS year,
    EXTRACT(MONTH FROM paid_at)         AS month,
    COUNT(*)                            AS payment_count,
    SUM(amount)                         AS monthly_revenue,
    ROUND(AVG(amount), 2)               AS avg_amount
FROM   payments
WHERE  payment_status = 'completed'
GROUP  BY year, month
ORDER  BY year, month;


-- ── HAVING ───────────────────────────────────────────────────

-- 9.HV1  Zones with more than 3 sessions
SELECT
    z.zone_code,
    z.name,
    COUNT(ps.id)                        AS session_count,
    SUM(ps.amount_due)                  AS total_revenue
FROM   zones z
JOIN   parking_sessions ps ON ps.zone_id = z.id
GROUP  BY z.id, z.zone_code, z.name
HAVING COUNT(ps.id) > 3
ORDER  BY session_count DESC;

-- 9.HV2  Drivers with total fines > 500 (high-risk drivers)
SELECT
    d.full_name,
    COUNT(v.id)                         AS violation_count,
    SUM(v.fine_amount)                  AS total_fines
FROM   drivers d
JOIN   vehicles vh  ON vh.driver_id   = d.id
JOIN   violations v ON v.vehicle_id   = vh.id
GROUP  BY d.id, d.full_name
HAVING SUM(v.fine_amount) > 500
ORDER  BY total_fines DESC;

-- 9.HV3  Payment methods used more than 10 times
SELECT
    payment_method,
    COUNT(*)                            AS usage_count,
    SUM(amount)                         AS total_amount
FROM   payments
WHERE  payment_status = 'completed'
GROUP  BY payment_method
HAVING COUNT(*) > 10
ORDER  BY usage_count DESC;


-- ── ROLLUP ───────────────────────────────────────────────────

-- 9.RO1  Revenue by zone_type and zone_code with subtotals
SELECT
    COALESCE(z.zone_type, 'ALL TYPES')  AS zone_type,
    COALESCE(z.zone_code, 'SUBTOTAL')   AS zone_code,
    COUNT(ps.id)                        AS sessions,
    SUM(ps.amount_due)                  AS revenue
FROM   zones z
JOIN   parking_sessions ps ON ps.zone_id = z.id
GROUP  BY ROLLUP(z.zone_type, z.zone_code)
ORDER  BY z.zone_type NULLS LAST, z.zone_code NULLS LAST;

-- 9.RO2  Violation fines by violation_type and status with grand total
SELECT
    COALESCE(violation_type, 'ALL TYPES')   AS violation_type,
    COALESCE(violation_status, 'TOTAL')     AS violation_status,
    COUNT(*)                                AS count,
    SUM(fine_amount)                        AS total_fines,
    ROUND(AVG(fine_amount), 2)              AS avg_fine
FROM   violations
GROUP  BY ROLLUP(violation_type, violation_status)
ORDER  BY violation_type NULLS LAST, violation_status NULLS LAST;


-- ── GROUPING SETS ────────────────────────────────────────────

-- 9.GS1  Sessions grouped by zone_type, entry_method, and status independently
SELECT
    zone_type,
    entry_method,
    session_status,
    COUNT(*)                            AS session_count,
    SUM(amount_due)                     AS total_revenue
FROM   parking_sessions ps
JOIN   zones z ON z.id = ps.zone_id
GROUP  BY GROUPING SETS (
    (zone_type),
    (entry_method),
    (session_status),
    ()
)
ORDER  BY zone_type NULLS LAST, entry_method NULLS LAST, session_status NULLS LAST;

-- 9.GS2  Payments grouped by method and status with grouping level indicator
SELECT
    CASE WHEN GROUPING(payment_method) = 1 THEN 'ALL METHODS' ELSE payment_method END AS method,
    CASE WHEN GROUPING(payment_status) = 1 THEN 'ALL STATUSES' ELSE payment_status END AS status,
    GROUPING(payment_method)            AS grp_method,
    GROUPING(payment_status)            AS grp_status,
    COUNT(*)                            AS count,
    SUM(amount)                         AS total
FROM   payments
GROUP  BY GROUPING SETS (
    (payment_method, payment_status),
    (payment_method),
    (payment_status),
    ()
)
ORDER  BY grp_method, grp_status, payment_method NULLS LAST;


-- ── JOIN + AGGREGATION ───────────────────────────────────────

-- 9.JA1  Driver summary: sessions, total spent, violations, appeals
--        (each part is aggregated separately, then joined, so that
--         joining several one-to-many tables does not multiply the sums)
SELECT
    d.full_name,
    COALESCE(s.total_sessions, 0)       AS total_sessions,
    COALESCE(s.total_paid, 0)           AS total_paid,
    COALESCE(v.total_violations, 0)     AS total_violations,
    COALESCE(a.total_appeals, 0)        AS total_appeals
FROM   drivers d
LEFT   JOIN (
    SELECT vh.driver_id,
           COUNT(DISTINCT ps.id)                                   AS total_sessions,
           SUM(p.amount) FILTER (WHERE p.payment_status = 'completed') AS total_paid
    FROM   vehicles vh
    JOIN   parking_sessions ps ON ps.vehicle_id = vh.id
    LEFT   JOIN payments p     ON p.session_id  = ps.id
    GROUP  BY vh.driver_id
) s ON s.driver_id = d.id
LEFT   JOIN (
    SELECT vh.driver_id, COUNT(*) AS total_violations
    FROM   vehicles vh
    JOIN   violations viol ON viol.vehicle_id = vh.id
    GROUP  BY vh.driver_id
) v ON v.driver_id = d.id
LEFT   JOIN (
    SELECT driver_id, COUNT(*) AS total_appeals
    FROM   appeals
    GROUP  BY driver_id
) a ON a.driver_id = d.id
ORDER  BY total_paid DESC;

-- 9.JA2  Zone revenue vs. violation fines — analytical comparison
SELECT
    z.zone_code,
    z.zone_type,
    COALESCE(s.revenue, 0)              AS session_revenue,
    COALESCE(v.fines, 0)                AS total_fines,
    COALESCE(s.sessions, 0)             AS sessions,
    COALESCE(v.violations, 0)           AS violations
FROM   zones z
LEFT   JOIN (
    SELECT zone_id, SUM(amount_due) AS revenue, COUNT(*) AS sessions
    FROM   parking_sessions
    GROUP  BY zone_id
) s ON s.zone_id = z.id
LEFT   JOIN (
    SELECT zone_id, SUM(fine_amount) AS fines, COUNT(*) AS violations
    FROM   violations
    GROUP  BY zone_id
) v ON v.zone_id = z.id
ORDER  BY session_revenue DESC;


-- ────────────────────────────────────────────────────────────
-- SECTION 10 · SUBQUERIES
-- ────────────────────────────────────────────────────────────

-- ── SCALAR SUBQUERY IN WHERE ─────────────────────────────────

-- 10.SQ1  Sessions where amount_due > overall average
SELECT id, vehicle_id, zone_id, duration_minutes, amount_due, session_status
FROM   parking_sessions
WHERE  amount_due > (
    SELECT AVG(amount_due)
    FROM   parking_sessions
)
ORDER  BY amount_due DESC;

-- 10.SQ2  Violations with fine_amount > average fine
SELECT violation_code, violation_type, fine_amount, violation_status
FROM   violations
WHERE  fine_amount > (
    SELECT AVG(fine_amount) FROM violations
)
ORDER  BY fine_amount DESC;


-- ── SUBQUERY WITH IN ─────────────────────────────────────────

-- 10.IN1  Drivers who own vehicles that received violations
SELECT full_name, email, license_number
FROM   drivers
WHERE  id IN (
    SELECT DISTINCT driver_id
    FROM   vehicles
    WHERE  id IN (SELECT DISTINCT vehicle_id FROM violations)
)
ORDER  BY full_name;

-- 10.IN2  Sessions that generated at least one payment
SELECT id, amount_due, session_status, start_time
FROM   parking_sessions
WHERE  id IN (SELECT DISTINCT session_id FROM payments)
ORDER  BY start_time DESC;

-- 10.IN3  Zones that have had violations issued
SELECT zone_code, name, zone_type, hourly_rate
FROM   zones
WHERE  id IN (SELECT DISTINCT zone_id FROM violations)
ORDER  BY zone_code;


-- ── CORRELATED SUBQUERY ──────────────────────────────────────

-- 10.CO1  Sessions where amount_due > avg for that specific zone
SELECT
    ps.id,
    ps.zone_id,
    ps.duration_minutes,
    ps.amount_due,
    (SELECT ROUND(AVG(ps2.amount_due), 2)
     FROM parking_sessions ps2
     WHERE ps2.zone_id = ps.zone_id)   AS zone_avg_amount
FROM   parking_sessions ps
WHERE  ps.amount_due > (
    SELECT AVG(ps2.amount_due)
    FROM   parking_sessions ps2
    WHERE  ps2.zone_id = ps.zone_id
)
ORDER  BY ps.zone_id, ps.amount_due DESC;

-- 10.CO2  Drivers whose latest payment was a 'completed' status
SELECT full_name, email, license_number
FROM   drivers d
WHERE  (
    SELECT payment_status
    FROM   payments p
    WHERE  p.driver_id = d.id
    ORDER  BY p.created_at DESC
    LIMIT  1
) = 'completed';


-- ── EXISTS SUBQUERY ──────────────────────────────────────────

-- 10.EX1  Drivers who have filed at least one appeal
SELECT full_name, email, license_number
FROM   drivers d
WHERE  EXISTS (
    SELECT 1 FROM appeals a WHERE a.driver_id = d.id
)
ORDER  BY full_name;

-- 10.EX2  Zones with at least one active sensor
SELECT zone_code, name, zone_type, hourly_rate
FROM   zones z
WHERE  EXISTS (
    SELECT 1 FROM sensors s
    WHERE  s.zone_id = z.id AND s.status = 'active'
)
ORDER  BY zone_code;

-- 10.EX3  Violations that have been contested via an appeal
SELECT violation_code, violation_type, fine_amount, violation_status
FROM   violations v
WHERE  EXISTS (
    SELECT 1 FROM appeals a WHERE a.violation_id = v.id
)
ORDER  BY fine_amount DESC;


-- ── ALL SUBQUERY ─────────────────────────────────────────────

-- 10.AL1  Sessions with amount_due greater than ALL session amounts in zone Z001
SELECT id, zone_id, duration_minutes, amount_due, session_status
FROM   parking_sessions
WHERE  amount_due > ALL (
    SELECT ps2.amount_due
    FROM   parking_sessions ps2
    JOIN   zones z ON z.id = ps2.zone_id
    WHERE  z.zone_code = 'Z001'
)
ORDER  BY amount_due DESC;

-- 10.AL2  Violations with fine greater than ALL fines of type 'overtime_parking'
SELECT violation_code, violation_type, fine_amount, violation_status
FROM   violations
WHERE  fine_amount > ALL (
    SELECT fine_amount
    FROM   violations
    WHERE  violation_type = 'overtime_parking'
)
ORDER  BY fine_amount DESC;


-- ── ROW-VALUED (TUPLE) SUBQUERY ──────────────────────────────

-- 10.RV1  Sessions where (vehicle_id, zone_id) matches a known violation pair
SELECT
    ps.id                               AS session_id,
    ps.vehicle_id,
    ps.zone_id,
    ps.start_time,
    ps.amount_due
FROM   parking_sessions ps
WHERE  (ps.vehicle_id, ps.zone_id) IN (
    SELECT vehicle_id, zone_id
    FROM   violations
    WHERE  violation_status IN ('unpaid', 'overdue')
)
ORDER  BY ps.start_time DESC;

-- 10.RV2  Drivers whose (id, license_number) pair appears in a high-violation lookup
SELECT full_name, license_number, email
FROM   drivers
WHERE  (id, license_number) IN (
    SELECT d.id, d.license_number
    FROM   drivers d
    JOIN   vehicles vh  ON vh.driver_id  = d.id
    JOIN   violations v ON v.vehicle_id  = vh.id
    GROUP  BY d.id, d.license_number
    HAVING COUNT(v.id) >= 2
)
ORDER  BY full_name;


-- ── SUBQUERY IN SELECT (scalar) ──────────────────────────────

-- 10.SS1  Each zone with its total session count as a column
SELECT
    z.zone_code,
    z.name,
    z.hourly_rate,
    (SELECT COUNT(*) FROM parking_sessions ps WHERE ps.zone_id = z.id) AS session_count,
    (SELECT COALESCE(SUM(ps.amount_due), 0) FROM parking_sessions ps WHERE ps.zone_id = z.id) AS total_revenue
FROM   zones z
ORDER  BY total_revenue DESC;

-- 10.SS2  Each driver with their last payment date and total payment count
SELECT
    d.full_name,
    d.email,
    (SELECT COUNT(*)    FROM payments p WHERE p.driver_id = d.id)               AS payment_count,
    (SELECT MAX(paid_at) FROM payments p WHERE p.driver_id = d.id)              AS last_payment_date,
    (SELECT COALESCE(SUM(amount), 0) FROM payments p
     WHERE p.driver_id = d.id AND p.payment_status = 'completed')               AS total_spent
FROM   drivers d
ORDER  BY total_spent DESC;

-- 10.SS3  Multi-row subquery — top 5 highest-revenue zones
SELECT zone_code, name, zone_type, hourly_rate
FROM   zones
WHERE  id IN (
    SELECT zone_id
    FROM   parking_sessions
    GROUP  BY zone_id
    ORDER  BY SUM(amount_due) DESC
    LIMIT  5
)
ORDER  BY zone_code;

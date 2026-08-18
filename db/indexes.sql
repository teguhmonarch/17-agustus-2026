-- Indexes & extensions for the Customer Intelligence Platform.
-- Run AFTER the dump has been restored. Built with high maintenance_work_mem.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- exact lookups (email / phone / id). PK on user_id already exists (ws_user_pk).
CREATE INDEX IF NOT EXISTS idx_user_email_lower ON ws_user (lower(user_email));
CREATE INDEX IF NOT EXISTS idx_user_msisdn      ON ws_user (msisdn);
CREATE INDEX IF NOT EXISTS idx_user_msisdn_norm ON ws_user (regexp_replace(coalesce(msisdn,''),'[^0-9]','','g'));

-- fuzzy / partial name search + name-similarity in duplicate detection.
CREATE INDEX IF NOT EXISTS idx_user_fullname_trgm ON ws_user USING gin (full_name gin_trgm_ops);

-- relational joins (orders / transactions / activity).
CREATE INDEX IF NOT EXISTS idx_orders_user   ON ws_orders (user_id);
CREATE INDEX IF NOT EXISTS idx_tx_order       ON ws_transactions (order_id);
CREATE INDEX IF NOT EXISTS idx_activity_user  ON ws_user_activity (user_id);

ANALYZE ws_user;
ANALYZE ws_orders;
ANALYZE ws_transactions;
ANALYZE ws_user_activity;

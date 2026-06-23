-- =============================================================================
-- vault/postgres-init.sql
--
-- Executed once by PostgreSQL on first container start.
-- Creates the payments table that the payments-app reads and writes to.
-- Dynamic Vault users are granted access to this table only (see setup.sh).
-- =============================================================================

CREATE TABLE IF NOT EXISTS payments (
    id          BIGSERIAL PRIMARY KEY,
    reference   VARCHAR(64)    NOT NULL,
    amount      NUMERIC(12, 2) NOT NULL,
    currency    VARCHAR(3)     NOT NULL DEFAULT 'USD',
    status      VARCHAR(32)    NOT NULL DEFAULT 'PENDING',
    created_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Pay Day worker D1 schema. Identity is the cross-device sync anchor; the
-- send ledger records every Peppol transmission for support and idempotency.

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  apple_sub TEXT UNIQUE NOT NULL,
  email TEXT,
  name TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS peppol_sends (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  idempotency_key TEXT,
  invoice_number TEXT NOT NULL,
  recipient_endpoint TEXT NOT NULL,
  transmission_id TEXT,
  status TEXT NOT NULL,
  charged INTEGER NOT NULL DEFAULT 0,
  reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_peppol_sends_user ON peppol_sends(user_id, created_at DESC);

-- A send is uniquely identified by (user, idempotency_key); the route claims
-- this slot before transmitting so a retry/double-tap can never transmit or
-- charge twice. SQLite treats NULL keys as distinct, so legacy rows don't clash.
CREATE UNIQUE INDEX IF NOT EXISTS idx_peppol_sends_idem ON peppol_sends(user_id, idempotency_key);

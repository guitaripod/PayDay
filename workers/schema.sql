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
  invoice_number TEXT NOT NULL,
  recipient_endpoint TEXT NOT NULL,
  transmission_id TEXT,
  status TEXT NOT NULL,
  reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_peppol_sends_user ON peppol_sends(user_id, created_at DESC);

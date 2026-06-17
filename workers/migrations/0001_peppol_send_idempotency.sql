-- Adds idempotency to the live peppol_sends ledger (run once against prod D1):
--   CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) \
--     npx wrangler d1 execute payday --remote --file migrations/0001_peppol_send_idempotency.sql
-- ALTER TABLE ... ADD COLUMN is a no-op-safe one-shot; rerunning errors on the
-- existing column, which is fine (the unique index uses IF NOT EXISTS).

ALTER TABLE peppol_sends ADD COLUMN idempotency_key TEXT;
ALTER TABLE peppol_sends ADD COLUMN charged INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS idx_peppol_sends_idem ON peppol_sends(user_id, idempotency_key);

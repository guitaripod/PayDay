import type { Env } from '../env'

/// Tables that hold rows keyed to a mako user id. Every table in schema.sql or
/// migrations/ with a user_id column must be listed here, which test/account.test.ts
/// enforces so a future user-keyed table cannot be forgotten by the purge.
export const USER_TABLES = ['peppol_sends'] as const

/// Erases every row this worker keeps for `userId` in one D1 batch, so a partial
/// failure leaves nothing half-deleted. peppol_sends is deleted before the legacy
/// users row because peppol_sends.user_id references users(id). The per-table
/// counts (the users row is reported under `users`) and the total let the caller
/// log proof of erasure without writing the user id anywhere.
export async function purgeUser(
  env: Env,
  userId: string
): Promise<{ deleted: Record<string, number>; total: number }> {
  const results = await env.DB.batch([
    env.DB.prepare('DELETE FROM peppol_sends WHERE user_id = ?').bind(userId),
    env.DB.prepare('DELETE FROM users WHERE id = ?').bind(userId),
  ])
  const deleted: Record<string, number> = {
    peppol_sends: results[0]?.meta?.changes ?? 0,
    users: results[1]?.meta?.changes ?? 0,
  }
  const total = Object.values(deleted).reduce((sum, count) => sum + count, 0)
  return { deleted, total }
}

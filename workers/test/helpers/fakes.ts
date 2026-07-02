/// Minimal in-memory fakes for KV and D1, enough to exercise the worker's
/// routes in plain vitest without the Workers runtime.

export function makeFakeKV(): KVNamespace {
  const store = new Map<string, string>()
  return {
    async get(key: string, type?: string) {
      const value = store.get(key)
      if (value === undefined) return null
      return type === 'json' ? JSON.parse(value) : value
    },
    async put(key: string, value: string) {
      store.set(key, value)
    },
    async delete(key: string) {
      store.delete(key)
    },
    async list() {
      return { keys: [...store.keys()].map((name) => ({ name })), list_complete: true, cacheStatus: null }
    },
  } as unknown as KVNamespace
}

type Row = Record<string, unknown>

/// A tiny D1 fake that understands only the statements this worker issues
/// (users insert/select/update, and the peppol_sends idempotency ledger:
/// select-by-key, claim-insert, and the status/charged/transmission updates).
/// It is deliberately not a SQL engine — just enough to verify route wiring and
/// the exactly-once send/charge semantics.
export function makeFakeD1(): D1Database {
  const users: Row[] = []
  const sends: Row[] = []

  function prepare(sql: string) {
    const binds: unknown[] = []
    const stmt = {
      bind(...args: unknown[]) {
        binds.push(...args)
        return stmt
      },
      async first<T>() {
        if (/FROM users WHERE apple_sub/.test(sql)) {
          return (users.find((u) => u.apple_sub === binds[0]) as T) ?? null
        }
        if (/FROM users WHERE id/.test(sql)) {
          return (users.find((u) => u.id === binds[0]) as T) ?? null
        }
        if (/FROM peppol_sends WHERE user_id = \? AND idempotency_key = \? AND status = 'accepted'/.test(sql)) {
          return (sends.find((s) => s.user_id === binds[0] && s.idempotency_key === binds[1] && s.status === 'accepted') as T) ?? null
        }
        if (/SELECT id FROM peppol_sends WHERE user_id = \? AND idempotency_key = \?/.test(sql)) {
          return (sends.find((s) => s.user_id === binds[0] && s.idempotency_key === binds[1]) as T) ?? null
        }
        return null
      },
      async run() {
        let changes = 0
        if (/INSERT INTO users/.test(sql)) {
          users.push({ id: binds[0], apple_sub: binds[1], email: binds[2], name: binds[3] })
          changes = 1
        } else if (/UPDATE users/.test(sql)) {
          const u = users.find((x) => x.id === binds[2])
          if (u) {
            u.email = binds[0]
            u.name = binds[1]
            changes = 1
          }
        } else if (/INSERT INTO peppol_sends/.test(sql)) {
          const existing = sends.find((s) => s.user_id === binds[1] && s.idempotency_key === binds[2])
          const accepted = /'accepted', 0\)/.test(sql)
          if (existing) {
            if (/DO UPDATE/.test(sql) && existing.status !== 'accepted') {
              existing.transmission_id = binds[5] ?? null
              existing.status = 'accepted'
              existing.reason = null
              existing.charged = 0
              changes = 1
            }
          } else {
            sends.push({
              id: binds[0],
              user_id: binds[1],
              idempotency_key: binds[2],
              invoice_number: binds[3],
              recipient_endpoint: binds[4],
              transmission_id: binds[5] ?? null,
              status: accepted ? 'accepted' : (binds[6] ?? 'failed'),
              charged: 0,
              reason: accepted ? null : (binds[7] ?? null),
            })
            changes = 1
          }
        } else if (/UPDATE peppol_sends SET charged = 1/.test(sql)) {
          const row = sends.find((s) => s.id === binds[0])
          if (row) {
            row.charged = 1
            changes = 1
          }
        }
        return { success: true, meta: { changes } }
      },
      async all<T>() {
        return { results: [] as T[], success: true, meta: {} }
      },
    }
    return stmt
  }

  return {
    prepare,
    __users: users,
    __sends: sends,
  } as unknown as D1Database
}

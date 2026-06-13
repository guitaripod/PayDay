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
/// (users insert/select/update, peppol_sends insert). It is deliberately not a
/// SQL engine — just enough to verify route wiring and the send ledger write.
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
        return null
      },
      async run() {
        if (/INSERT INTO users/.test(sql)) {
          users.push({ id: binds[0], apple_sub: binds[1], email: binds[2], name: binds[3] })
        } else if (/UPDATE users/.test(sql)) {
          const u = users.find((x) => x.id === binds[2])
          if (u) {
            u.email = binds[0]
            u.name = binds[1]
          }
        } else if (/INSERT INTO peppol_sends/.test(sql)) {
          sends.push({
            id: binds[0],
            user_id: binds[1],
            invoice_number: binds[2],
            recipient_endpoint: binds[3],
            transmission_id: binds[4],
            status: binds[5],
            reason: binds[6],
          })
        }
        return { success: true, meta: {} }
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

/// <reference types="vite/client" />
import schema from '../schema.sql?raw'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import app from '../src/index'
import { USER_TABLES } from '../src/lib/purge'
import { makeEnv, type TestEnv } from './helpers/env'

const migrations = import.meta.glob('../migrations/*.sql', {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>

const ALICE = 'user-alice'
const BOB = 'user-bob'
const KEYS: Record<string, string> = {
  'alice-key': ALICE,
  'bob-key': BOB,
}

type SendRow = { id: string; user_id: string; status: string }
type UserRow = { id: string; apple_sub: string }

function fakeRows<T>(env: TestEnv, table: '__sends' | '__users'): T[] {
  return (env.DB as unknown as Record<string, T[]>)[table]
}

function seedUser(env: TestEnv, userId: string, sends: number) {
  fakeRows<UserRow>(env, '__users').push({ id: userId, apple_sub: `apple-${userId}` })
  for (let i = 0; i < sends; i++) {
    fakeRows<SendRow>(env, '__sends').push({ id: `${userId}-send-${i}`, user_id: userId, status: 'accepted' })
  }
}

function deleteAccount(env: TestEnv, token?: string) {
  return app.request(
    '/v1/account',
    { method: 'DELETE', headers: token ? { authorization: `Bearer ${token}` } : {} },
    env
  )
}

function stubMako() {
  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input.toString()
    if (!url.endsWith('/v1/identity/me')) return new Response('not mocked', { status: 404 })
    const token = new Headers(init?.headers).get('authorization')?.replace('Bearer ', '') ?? ''
    const userId = KEYS[token]
    return userId
      ? new Response(JSON.stringify({ user_id: userId, app_id: 'payday' }), { status: 200 })
      : new Response('{}', { status: 401 })
  })
}

/// Returns the names of every table whose CREATE TABLE body declares a user_id column.
function userKeyedTables(sql: string): string[] {
  const tables: string[] = []
  for (const match of sql.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?(\w+) \(([\s\S]*?)\n\);/g)) {
    const [, name, body] = match
    if (body.split('\n').some((line) => /^\s*user_id\s/.test(line))) tables.push(name)
  }
  return tables
}

let env: TestEnv

beforeEach(() => {
  env = makeEnv()
  stubMako()
})

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('DELETE /v1/account', () => {
  it('erases the caller Peppol transmission records and answers 204 with no body', async () => {
    seedUser(env, ALICE, 2)
    seedUser(env, BOB, 1)
    const log = vi.spyOn(console, 'log').mockImplementation(() => {})

    const res = await deleteAccount(env, 'alice-key')

    expect(res.status).toBe(204)
    expect(await res.text()).toBe('')
    expect(fakeRows<SendRow>(env, '__sends').filter((s) => s.user_id === ALICE)).toHaveLength(0)
    expect(fakeRows<SendRow>(env, '__sends').filter((s) => s.user_id === BOB)).toHaveLength(1)
    expect(fakeRows<UserRow>(env, '__users').map((u) => u.id)).toEqual([BOB])
    expect(log).toHaveBeenCalledWith(JSON.stringify({ event: 'account_purge', total: 3 }))
  })

  it('is idempotent: a second call with nothing left is another 204', async () => {
    seedUser(env, ALICE, 2)
    const log = vi.spyOn(console, 'log').mockImplementation(() => {})

    expect((await deleteAccount(env, 'alice-key')).status).toBe(204)
    expect((await deleteAccount(env, 'alice-key')).status).toBe(204)
    expect(log).toHaveBeenLastCalledWith(JSON.stringify({ event: 'account_purge', total: 0 }))
  })

  it('rejects a missing bearer with missing_bearer and deletes nothing', async () => {
    seedUser(env, ALICE, 2)

    const res = await deleteAccount(env)

    expect(res.status).toBe(401)
    expect(await res.json()).toEqual({ error: 'missing_bearer' })
    expect(fakeRows<SendRow>(env, '__sends')).toHaveLength(2)
  })

  it('rejects a token mako refuses with invalid_token and deletes nothing', async () => {
    seedUser(env, ALICE, 2)

    const res = await deleteAccount(env, 'unknown-key')

    expect(res.status).toBe(401)
    expect(await res.json()).toEqual({ error: 'invalid_token' })
    expect(fakeRows<SendRow>(env, '__sends')).toHaveLength(2)
  })

  it('covers every table in schema.sql and migrations/ that has a user_id column', () => {
    const sources = [schema, ...Object.keys(migrations).sort().map((path) => migrations[path])]
    const userTables = sources.flatMap(userKeyedTables)

    expect(Object.keys(migrations)).not.toHaveLength(0)
    expect(userTables).toContain('peppol_sends')
    expect(userTables.filter((table) => !(USER_TABLES as readonly string[]).includes(table))).toEqual([])
  })
})

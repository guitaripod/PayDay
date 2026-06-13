import { Hono } from 'hono'
import * as jose from 'jose'
import type { AppVars, Env } from '../env'
import { mintAppJWT, verifyAppJWT } from '../lib/jwt'
import { sha256Hex } from '../lib/crypto'

const APPLE_ISSUER = 'https://appleid.apple.com'
const APPLE_JWKS_URL = new URL('https://appleid.apple.com/auth/keys')
const NONCE_TTL_SECONDS = 5 * 60

const appleJWKS = jose.createRemoteJWKSet(APPLE_JWKS_URL, {
  cacheMaxAge: 10 * 60 * 1000,
  cooldownDuration: 30 * 1000,
})

type AppleAuthBody = {
  identityToken: string
  rawNonce?: string
  fullName?: { givenName?: string; familyName?: string }
}

export const authRoutes = new Hono<{ Bindings: Env; Variables: AppVars }>()

authRoutes.post('/v1/auth/apple', async (c) => {
  let body: AppleAuthBody
  try {
    body = await c.req.json<AppleAuthBody>()
  } catch {
    return c.json({ error: 'invalid_json' }, 400)
  }
  if (!body.identityToken) return c.json({ error: 'identityToken_required' }, 400)

  let payload: jose.JWTPayload
  try {
    const verified = await jose.jwtVerify(body.identityToken, appleJWKS, {
      issuer: APPLE_ISSUER,
      audience: c.env.APPLE_CLIENT_ID,
      algorithms: ['RS256'],
      clockTolerance: '10s',
    })
    payload = verified.payload
  } catch (err) {
    console.error('apple_verify_failed:', (err as Error).message)
    return c.json({ error: 'apple_token_invalid' }, 401)
  }

  const appleSub = payload.sub
  if (!appleSub) return c.json({ error: 'apple_token_missing_sub' }, 401)

  const tokenNonce = payload.nonce as string | undefined
  if (body.rawNonce) {
    const expected = await sha256Hex(body.rawNonce)
    if (!tokenNonce || expected !== tokenNonce) {
      return c.json({ error: 'nonce_mismatch' }, 401)
    }
  }

  if (tokenNonce) {
    const nonceKey = `nonce:${tokenNonce}`
    const seen = await c.env.AUTH_NONCE.get(nonceKey)
    if (seen) return c.json({ error: 'nonce_replayed' }, 401)
    await c.env.AUTH_NONCE.put(nonceKey, '1', { expirationTtl: NONCE_TTL_SECONDS })
  }

  const email = (payload.email as string | undefined) || null
  const givenName = body.fullName?.givenName ?? null
  const familyName = body.fullName?.familyName ?? null
  const displayName = [givenName, familyName].filter(Boolean).join(' ') || null

  const existing = await c.env.DB.prepare('SELECT id, email, name FROM users WHERE apple_sub = ?')
    .bind(appleSub)
    .first<{ id: string; email: string | null; name: string | null }>()

  let userId: string
  let finalEmail: string | null
  let finalName: string | null

  if (existing) {
    userId = existing.id
    finalEmail = existing.email ?? email
    finalName = existing.name ?? displayName
    if ((!existing.email && email) || (!existing.name && displayName)) {
      await c.env.DB.prepare('UPDATE users SET email = ?, name = ? WHERE id = ?')
        .bind(finalEmail, finalName, userId)
        .run()
    }
  } else {
    userId = crypto.randomUUID()
    finalEmail = email
    finalName = displayName
    await c.env.DB.prepare('INSERT INTO users (id, apple_sub, email, name) VALUES (?, ?, ?, ?)')
      .bind(userId, appleSub, finalEmail, finalName)
      .run()
  }

  const token = await mintAppJWT(
    { uid: userId, email: finalEmail ?? undefined, name: finalName ?? undefined },
    c.env.APP_JWT_SECRET
  )

  return c.json({ token, user: { id: userId, email: finalEmail, name: finalName } })
})

authRoutes.post('/v1/auth/refresh', async (c) => {
  const header = c.req.header('Authorization')
  if (!header?.startsWith('Bearer ')) return c.json({ error: 'missing_bearer' }, 401)

  let claims
  try {
    claims = await verifyAppJWT(header.slice(7), c.env.APP_JWT_SECRET)
  } catch {
    return c.json({ error: 'invalid_token' }, 401)
  }

  const row = await c.env.DB.prepare('SELECT id, email, name FROM users WHERE id = ?')
    .bind(claims.uid)
    .first<{ id: string; email: string | null; name: string | null }>()
  if (!row) return c.json({ error: 'user_not_found' }, 404)

  const token = await mintAppJWT(
    { uid: row.id, email: row.email ?? undefined, name: row.name ?? undefined },
    c.env.APP_JWT_SECRET
  )
  return c.json({ token, user: { id: row.id, email: row.email, name: row.name } })
})

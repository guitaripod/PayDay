import { describe, expect, it } from 'vitest'
import { mintAppJWT, verifyAppJWT } from '../src/lib/jwt'
import { APP_JWT_SECRET } from './helpers/env'

describe('app jwt', () => {
  it('round-trips claims', async () => {
    const token = await mintAppJWT({ uid: 'user-1', email: 'a@b.c', name: 'A' }, APP_JWT_SECRET)
    const claims = await verifyAppJWT(token, APP_JWT_SECRET)
    expect(claims.uid).toBe('user-1')
    expect(claims.email).toBe('a@b.c')
  })

  it('rejects a token signed with the wrong secret', async () => {
    const token = await mintAppJWT({ uid: 'user-1' }, APP_JWT_SECRET)
    await expect(verifyAppJWT(token, 'other-secret')).rejects.toThrow()
  })
})

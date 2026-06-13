import * as jose from 'jose'

const APP_JWT_ISSUER = 'payday'
const APP_JWT_AUDIENCE = 'payday-ios'
const APP_JWT_EXPIRY = '30d'

export type AppClaims = { uid: string; email?: string; name?: string }

const secretBytes = (secret: string): Uint8Array => new TextEncoder().encode(secret)

export async function mintAppJWT(claims: AppClaims, secret: string): Promise<string> {
  return new jose.SignJWT({ ...claims })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(APP_JWT_EXPIRY)
    .setIssuer(APP_JWT_ISSUER)
    .setAudience(APP_JWT_AUDIENCE)
    .setSubject(claims.uid)
    .sign(secretBytes(secret))
}

export async function verifyAppJWT(token: string, secret: string): Promise<AppClaims> {
  const { payload } = await jose.jwtVerify(token, secretBytes(secret), {
    issuer: APP_JWT_ISSUER,
    audience: APP_JWT_AUDIENCE,
    algorithms: ['HS256'],
    clockTolerance: '5s',
  })
  const uid = payload.uid as string | undefined
  if (!uid) throw new Error('app_jwt_missing_uid')
  return {
    uid,
    email: payload.email as string | undefined,
    name: payload.name as string | undefined,
  }
}

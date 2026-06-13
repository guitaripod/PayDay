export type Env = {
  AUTH_NONCE: KVNamespace
  FX_CACHE: KVNamespace
  DB: D1Database

  APP_JWT_SECRET: string
  APPLE_CLIENT_ID: string
  APPLE_TEAM_ID: string

  PEPPOL_PROVIDER: string
  PEPPOL_API_KEY: string
  PEPPOL_API_SECRET: string
  PEPPOL_GATEWAY_BASE: string
  PEPPOL_LEGAL_ENTITY_ID: string

  SUPPORTED_CURRENCIES: string
  ENVIRONMENT: string
}

export type AppVars = {
  userId: string
}

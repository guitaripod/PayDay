// Validate a UBL file against Recommand's EN16931/PEPPOL-BIS schematron via the
// PLAYGROUND (free, simulated AS4, no real delivery). Prints the FULL error list.
//   PEPPOL_API_KEY/SECRET/LEGAL_ENTITY_ID from workers/.dev.vars (playground).
//   usage: node scripts/peppol-validate.mjs <ubl.xml> [recipient]
import { readFileSync } from 'node:fs'

const [, , fixturePath, recipient = '0037:003735595497'] = process.argv
const key = process.env.PEPPOL_API_KEY
const secret = process.env.PEPPOL_API_SECRET
const company = process.env.PEPPOL_LEGAL_ENTITY_ID
if (!key || !secret || !company) {
  console.error('Missing PEPPOL_API_KEY/SECRET/LEGAL_ENTITY_ID env')
  process.exit(1)
}
const xml = readFileSync(fixturePath, 'utf8')
const auth = 'Basic ' + Buffer.from(`${key}:${secret}`).toString('base64')
const res = await fetch(`https://app.recommand.eu/api/v1/${company}/send`, {
  method: 'POST',
  headers: { authorization: auth, 'content-type': 'application/json' },
  body: JSON.stringify({ recipient, documentType: 'xml', document: xml }),
})
const body = await res.json().catch(() => ({}))
if (body.success) {
  console.log(`✓ VALID — accepted (id ${body.id ?? body.peppolMessageId ?? '-'})`)
} else {
  console.log(`✗ HTTP ${res.status} — failed assertions:`)
  const errs = body.errors ?? {}
  for (const [loc, msgs] of Object.entries(errs)) {
    for (const m of [].concat(msgs)) console.log(`  [${loc}] ${m}`)
  }
}

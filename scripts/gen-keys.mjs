#!/usr/bin/env node
/*
 * Generates the RSA keypair served by this key service.
 *
 *   public  -> generated/certs            (JWKS JSON, baked into the site / deployed)
 *   private -> generated/private.pem      (NEVER deployed; stays local)
 *
 * Usage:
 *   docker compose run --rm keygen
 *   KID=other-key docker compose run --rm keygen   # override kid
 *   ROTATE=1 docker compose run --rm keygen        # force regenerate (overwrites both files)
 */

import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateKeyPairSync } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const outDir = process.env.OUT_DIR ? join(root, process.env.OUT_DIR) : join(root, 'generated');
const certsPath = join(outDir, 'certs');
const privatePath = join(outDir, 'private.pem');
const kid = process.env.KID || 'druk-key-1';

mkdirSync(outDir, { recursive: true });

if (!process.env.ROTATE && existsSync(certsPath) && existsSync(privatePath)) {
  console.log(`[keygen] keys already exist (kid=${kid}) — set ROTATE=1 to regenerate.`);
  console.log(`[keygen]   public : ${certsPath}`);
  console.log(`[keygen]   private: ${privatePath}`);
  process.exit(0);
}

const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = publicKey.export({ format: 'jwk' });
const jwks = {
  keys: [
    {
      kid,
      kty: jwk.kty,
      alg: 'RS256',
      use: 'sig',
      n: jwk.n,
      e: jwk.e
    }
  ]
};

writeFileSync(certsPath, JSON.stringify(jwks, null, 2) + '\n', { mode: 0o644 });
writeFileSync(privatePath, privateKey.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600 });

console.log('[keygen] generated RSA-2048 keypair');
console.log(`[keygen]   public JWKS -> ${certsPath}`);
console.log(`[keygen]   private PEM -> ${privatePath}  (NEVER deploy; keep out of git)`);
console.log(`[keygen]   kid=${kid}`);

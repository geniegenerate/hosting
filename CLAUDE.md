# CLAUDE.md

Host for the GenieGenerate Apple AASA + Google assetlinks deep-link verification files. **Not** the marketing site.

## Reality check (correct your assumptions before working here)

| Surface | What's serving it | Source |
|---|---|---|
| `https://www.geniegenerate.com/` | **`web/apps/site`** via the prod Cloudflare Tunnel (cut over 2026-07-31; Google Sites retired and unpublished 08-06) | `web/apps/site` — ships in the `web_site` prod image, not this repo. |
| `https://devlink.geniegenerate.com/` | **Cloudflare Pages** project `geniegenerate-wellknown` (since 2026-07-20) | **Auto-deploys from this repo on push.** |
| `https://link.geniegenerate.com/` (prod) | **Cloudflare Pages** `geniegenerate-wellknown` (live since 2026-07-20) | Same project — prod AASA is live and verified through Apple's CDN. |
| `https://staginglink.geniegenerate.com/` | **Cloudflare Pages** `geniegenerate-wellknown` (live since 2026-07-20) | Same project. |

**Deploy targets — parallel run until ~2026-07-27:** Cloudflare Pages (`geniegenerate-wellknown`) is what all three subdomains serve; the Netlify project `stellar-pika-3ff766` remains attached to this repo as the rollback net (re-point a CNAME back to `stellar-pika-3ff766.netlify.app` to roll back) and is retired after a quiet week. Both auto-deploy on push; `_headers`/`_redirects` are honored identically by both. Retirement checklist: `company/operations/deployment/runbooks/CLOUDFLARE_PAGES.md`.

## What this repo serves (and only this)

- `apple-app-site-association` → exposed at `/.well-known/apple-app-site-association` via `_redirects` rewrite. Stored at repo root because Netlify (and Cloudflare Pages) exclude dotfiles/dotdirs from the build artifact.
- `assetlinks.json` → exposed at `/.well-known/assetlinks.json` via `_redirects` rewrite. Same dotfile reason.
- `_headers` → enforces `Content-Type: application/json` for the two files above (Google's assetlinks verifier requires this; Apple tolerates it).
- `netlify.toml` → tells Netlify "no build, publish from repo root".
- `index.html` + `images/` → vestigial landing page predating the marketing-site moves. Harmless; kept so the Pages project's apex doesn't 404 if someone hits it directly.

## ✅ Apple enrollment done — AASA is live with the real Team ID (2026-07-17)

Apple Developer enrollment is complete (Team **`RQ4GFMSFAQ`**, individual). The
`<TEAM_ID>` placeholder has been substituted into all six appID strings (three
`applinks.details` + three `webcredentials.apps`) and the corrected file is live
on both the Netlify origin and Apple's CDN. **iOS passkeys and (for `devlink`)
Universal Links now verify against a real physical device** — proven end-to-end
2026-07-17: passkey register + login with Touch ID succeeded on an iPhone
signed as `RQ4GFMSFAQ.com.geniegenerate.app`.

Historical prerequisites, now all satisfied:
1. ✅ Apple Developer Program membership → Team ID `RQ4GFMSFAQ`.
2. ✅ iOS Xcode project bundle IDs are `com.geniegenerate.app` (all configs),
   `DEVELOPMENT_TEAM=RQ4GFMSFAQ`. The `associated-domains` capability also had to
   move into the code-signed `Runner.entitlements` (mobile-app repo) — iOS
   ignores it in `Info.plist`.
3. ✅ Team ID substituted into `apple-app-site-association` (this repo).

**Prod DNS live (2026-07-20):** `link.` and `staginglink.geniegenerate.com` now
resolve (Cloudflare Pages custom domains) and Apple's CDN serves their AASA with
the real Team ID — verified `200 RQ4GFMSFAQ.com.geniegenerate.app` for all three
subdomains. Go-live steps 4–6 below are **superseded** by the Pages setup; step 7
(verify battery) and step 8 (end-to-end Universal Link test on prod `link.`)
remain the done-gate for any future change.

⚠️ The strict-validator caution still applies to any FUTURE edit: a wrong Team ID
is worse than a placeholder (Apple caches negative results aggressively). The
current `RQ4GFMSFAQ` is verified correct against the signed profile.

## Go-live playbook (when ready to verify in prod)

Execute in order. Each step has a verification command.

### 1. Apple Developer enrollment + Team ID (user action) — ✅ DONE
Enrolled. Team ID **`RQ4GFMSFAQ`** (verify: it's the `ApplicationIdentifierPrefix`/`TeamIdentifier` in any provisioning profile under `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`).

### 2. Update iOS Xcode project (separate scope, mobile-app repo) — ✅ DONE
Bundle IDs are `com.geniegenerate.app` (all configs), `DEVELOPMENT_TEAM=RQ4GFMSFAQ`. Also moved `com.apple.developer.associated-domains` into the code-signed `Runner.entitlements` (mobile-app `783b5875`) — the functional fix for passkeys, since iOS ignores that key in `Info.plist`.

### 3. Substitute Team ID into AASA — ✅ DONE
```bash
sed -i '' 's/<TEAM_ID>/RQ4GFMSFAQ/g' apple-app-site-association   # done in 7e29a44
git diff apple-app-site-association                               # 6 occurrences swapped (3 applinks + 3 webcredentials)
```
**Validate JSON before commit**: `jq . apple-app-site-association`. Confirm live where iOS actually reads it: `curl -s https://app-site-association.cdn-apple.com/a/v1/devlink.geniegenerate.com | jq .`.

### 4. Connect this repo to a Netlify project (user action) — ⚠️ SUPERSEDED 2026-07-20 by Cloudflare Pages (`geniegenerate-wellknown`); steps 4–6 kept for history only
Likely the existing `stellar-pika-3ff766.netlify.app` project (the one `devlink.` already points to) — confirm in Netlify dashboard whether it's still attached to this repo. If yes, just push and it deploys. If the link has drifted: in Netlify UI → Site settings → Build & deploy → Continuous Deployment → reconnect to `github.com/geniegenerate/hosting` branch `main`.

### 5. Add the two missing custom domains in Netlify (user action)
Netlify UI → Site settings → Domain management → add `link.geniegenerate.com` and `staginglink.geniegenerate.com`. (`devlink.` is already there.)

### 6. Add GoDaddy DNS records (user action)
GoDaddy DNS dashboard for `geniegenerate.com`:
- CNAME `link` → `<your-netlify-project>.netlify.app`
- CNAME `staginglink` → `<your-netlify-project>.netlify.app`

(`devlink` CNAME already exists.) Wait for DNS propagation (~5–60 min).

### 7. Verify (this IS the done-gate)
```bash
for sub in link staginglink devlink; do
  echo "=== $sub ==="
  curl -sI "https://$sub.geniegenerate.com/.well-known/apple-app-site-association" | head -3
  curl -s  "https://$sub.geniegenerate.com/.well-known/apple-app-site-association" | jq .
  curl -sI "https://$sub.geniegenerate.com/.well-known/assetlinks.json"             | head -3
  curl -s  "https://$sub.geniegenerate.com/.well-known/assetlinks.json"             | jq .
done
```
Expect: 200, `Content-Type: application/json`, valid JSON, three appIDs each. Then run Apple's [AASA validator](https://branch.io/resources/aasa-validator/) for the strict check.

### 8. End-to-end Universal Link test
On a physical iOS device (simulator won't verify Universal Links): tap a `https://link.geniegenerate.com/verify-email?token=xxx&email=xxx` URL in Notes or Messages — must open the app, not Safari. Same for `/reset-password*` and `/login*`. On Android: tap the same link, must open the app via App Link verification.

## Working in this repo (the autonomous loop, minus what doesn't apply)

- **No `docker compose`, no dev server, no test suite.** The "loop" is: edit → push → wait for Netlify deploy webhook → curl-verify.
- **Lane awareness**: no lane B (no parallel stack needed for static JSON).
- **Done-gate**: verification commands above. Failing to run them post-push is how the AASA stayed broken from `3da1799` (webcredentials) through `4d20845` (Android App Links) through my own `5352b9d`+`cd6ebf8` (the redirect fix) — all four commits shipped without ever verifying the file was live.
- **Public repo**: world-readable. Never commit credentials, internal URLs, or anything not intended for public visitors.

## Git Workflow

Direct-push to `main` (Netlify auto-deploys on push). Conventional commits. **Never** add Claude credit to commit messages.

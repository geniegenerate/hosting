# CLAUDE.md

Host for the GenieGenerate Apple AASA + Google assetlinks deep-link verification files. **Not** the marketing site.

## Reality check (correct your assumptions before working here)

| Surface | What's serving it | Source |
|---|---|---|
| `https://www.geniegenerate.com/` | **Google Sites** (CNAME → `ghs.googlehosted.com`) | Not in any repo. Edit via Google Sites UI. |
| `https://devlink.geniegenerate.com/` | Netlify project `stellar-pika-3ff766.netlify.app` | Presumed deployed from this repo, but the connection has drifted; needs reconnect. |
| `https://link.geniegenerate.com/` (prod) | **Nothing — DNS doesn't resolve** | To be set up. |
| `https://staginglink.geniegenerate.com/` | **Nothing — DNS doesn't resolve** | To be set up. |

The `_redirects` syntax in this repo and the presence of `netlify.toml` mean the deploy target is **Netlify**. Cloudflare Pages is NOT in use here; my earlier claim was wrong.

## What this repo serves (and only this)

- `apple-app-site-association` → exposed at `/.well-known/apple-app-site-association` via `_redirects` rewrite. Stored at repo root because Netlify (and Cloudflare Pages) exclude dotfiles/dotdirs from the build artifact.
- `assetlinks.json` → exposed at `/.well-known/assetlinks.json` via `_redirects` rewrite. Same dotfile reason.
- `_headers` → enforces `Content-Type: application/json` for the two files above (Google's assetlinks verifier requires this; Apple tolerates it).
- `netlify.toml` → tells Netlify "no build, publish from repo root".
- `index.html` + `images/` → vestigial landing page from before the Google Sites migration. Harmless; could be deleted, but kept so the apex of the Netlify deploy doesn't 404 if someone hits it.

## ⚠️ Blocked on Apple Developer enrollment

The AASA file contains `<TEAM_ID>` placeholder in nine appID strings (three appIDs × `applinks.details` + three in `webcredentials.apps`). Apple's AASA validator will reject the file as malformed until the placeholder is replaced with a real 10-character Apple Developer Team ID.

iOS Universal Links cannot verify until **all** of the following exist:
1. Apple Developer Program membership ($99/yr) → unlocks Team ID.
2. iOS Xcode project (`mobile-app/ios/Runner.xcodeproj/`) renamed off the Flutter template default `com.example.mobileApp` to mirror Android: `com.geniegenerate.app{,.staging,.dev}` per buildType. `DEVELOPMENT_TEAM` set to the real Team ID.
3. Team ID substituted into this repo's `apple-app-site-association`.

Until step 1, this repo is in "infrastructure ready, content blocked on Apple" state. Do not edit AASA content speculatively — the strict iOS validator means a wrong Team ID is worse than a placeholder (it caches negative results aggressively).

## Go-live playbook (when ready to verify in prod)

Execute in order. Each step has a verification command.

### 1. Apple Developer enrollment + Team ID (user action)
Enroll at developer.apple.com. Note the 10-char Team ID from membership details. Verify: log into App Store Connect.

### 2. Update iOS Xcode project (separate scope, mobile-app repo)
Rename bundle IDs and set `DEVELOPMENT_TEAM`. See follow-up task. Don't do this from this repo.

### 3. Substitute Team ID into AASA
```bash
sed -i '' 's/<TEAM_ID>/ABCDE12345/g' apple-app-site-association   # use real Team ID
git diff apple-app-site-association                               # verify nine occurrences swapped
```
**Validate JSON before commit**: `jq . apple-app-site-association`.

### 4. Connect this repo to a Netlify project (user action)
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

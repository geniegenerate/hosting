#!/usr/bin/env bash
#
# public-surface-watch.sh — weekly watch over the five public surfaces that fail SILENTLY.
#
# Why this exists: assetlinks.json and the AASA are load-bearing for Android App Links,
# iOS Universal Links and passkey/credential-manager association. If the prod SHA-256
# fingerprint drifts, or a cert lapses, NOTHING in the app errors — deep links quietly
# open in the browser and passkeys quietly stop associating. Nobody finds out.
#
# Exit codes:  0 = all green (say nothing)   1 = WARN   2 = CRITICAL
# Green is deliberately silent: an executor should notify ONLY on non-zero exit.
# A weekly all-clear trains the reader to ignore the alert.
#
# Runs identically on macOS (BSD date) and ubuntu-latest (GNU date). No secrets, no
# credentials, no private hosts: every surface it touches is already public.
#
# Lives under .github/ by convention. NOTE (2026-08-30): Cloudflare Pages does NOT
# exclude dotdirs — this script is itself served at
# https://link.geniegenerate.com/.github/scripts/public_surface_watch.sh. Nothing here is
# secret, and that must stay true (see CLAUDE.md).
#
# Run it by hand any time:  .github/scripts/public_surface_watch.sh ; echo $?

set -uo pipefail   # deliberately NOT -e: run every check, aggregate, report once.

# ---- expected values (ground truth lives in this repo, next to the served files) ----
readonly APEX="geniegenerate.com"
readonly TLS_HOSTS=(geniegenerate.com app.geniegenerate.com link.geniegenerate.com verify.geniegenerate.com)
readonly WELLKNOWN_HOST="link.geniegenerate.com"
readonly PROD_PACKAGE="com.geniegenerate.app"
readonly PROD_FINGERPRINT="E5:14:6C:A1:87:27:13:5F:C1:63:74:87:86:89:7C:CE:4E:0A:4D:9B:D7:B7:EE:75:23:B4:ED:E5:3B:31:E5:65"
readonly TEAM_ID="RQ4GFMSFAQ"

# ---- thresholds (days) ----
readonly CERT_WARN=21   CERT_CRIT=7
readonly DOMAIN_WARN=45 DOMAIN_CRIT=14

worst=0
declare -a FINDINGS=()

note()  { printf '  ok    %s\n' "$*"; }
warn()  { FINDINGS+=("WARN     $*"); printf '  WARN  %s\n' "$*"; (( worst < 1 )) && worst=1; return 0; }
crit()  { FINDINGS+=("CRITICAL $*"); printf '  CRIT  %s\n' "$*"; worst=2; return 0; }

# Portable "date string -> epoch". BSD first, GNU second; empty on failure.
to_epoch() {
    local s=$1 e
    e=$(date -j -f '%b %e %T %Y %Z' "$s" +%s 2>/dev/null) && { printf '%s' "$e"; return 0; }
    e=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "${s%%.*}Z" +%s 2>/dev/null) && { printf '%s' "$e"; return 0; }
    e=$(date -d "$s" +%s 2>/dev/null) && { printf '%s' "$e"; return 0; }
    return 1
}

days_until() { local t; t=$(to_epoch "$1") || return 1; printf '%s' $(( (t - $(date +%s)) / 86400 )); }

echo "== public-surface watch $(date -u '+%Y-%m-%dT%H:%M:%SZ') =="

# ---------------------------------------------------------------- 1. TLS certificates
echo
echo "[1/5] TLS certificates"
for host in "${TLS_HOSTS[@]}"; do
    cert=$(openssl s_client -connect "$host:443" -servername "$host" </dev/null 2>/dev/null \
           | openssl x509 -noout -enddate -issuer 2>/dev/null)
    if [[ -z $cert ]]; then
        crit "$host — TLS handshake failed, could not read certificate"
        continue
    fi

    # ☠️ False-green guard. Behind an egress proxy that re-terminates TLS (e.g. the
    # Claude cloud sandbox) openssl SUCCEEDS and returns the PROXY's cert, so the
    # expiry printed is fiction. Refuse to report a number we cannot trust.
    issuer=${cert#*issuer=}
    if [[ $issuer == *"Egress Gateway"* || $issuer == *"O = Anthropic"* ]]; then
        crit "$host — cert issued by '$issuer': TLS is being re-terminated by a proxy. This runner CANNOT check certs; results would be fake."
        continue
    fi

    enddate=${cert#*notAfter=}; enddate=${enddate%%$'\n'*}
    if ! left=$(days_until "$enddate"); then
        crit "$host — could not parse notAfter '$enddate'"
        continue
    fi
    if   (( left < CERT_CRIT )); then crit "$host — cert expires in ${left}d ($enddate)"
    elif (( left < CERT_WARN )); then warn "$host — cert expires in ${left}d ($enddate)"
    else note "$host — cert ${left}d remaining"
    fi
done

# ------------------------------------------------------- 2. assetlinks.json (Android)
echo
echo "[2/5] assetlinks.json — Play App Signing fingerprint"
al_url="https://$WELLKNOWN_HOST/.well-known/assetlinks.json"
al_body=$(mktemp)
al_code=$(curl -sS -o "$al_body" -w '%{http_code}' --max-time 20 "$al_url" 2>/dev/null)

if [[ $al_code != 200 ]]; then
    crit "assetlinks.json returned HTTP ${al_code:-<none>} (expected 200) at $al_url"
elif ! jq -e . "$al_body" >/dev/null 2>&1; then
    crit "assetlinks.json is not valid JSON — Google's verifier will reject it"
else
    # Positive control: prove the document has content we recognise BEFORE concluding
    # anything is 'absent'. An empty/garbage body must never read as 'fingerprint gone'.
    pkgs=$(jq -r '[.[].target.package_name] | join(", ")' "$al_body")
    if [[ -z ${pkgs//[[:space:]]/} ]]; then
        crit "assetlinks.json parsed but declares NO packages — served file is a shell"
    else
        note "declares packages: $pkgs"
        # Exact match on the parsed structure, never a substring grep.
        got=$(jq -r --arg p "$PROD_PACKAGE" \
              '.[] | select(.target.package_name == $p) | .target.sha256_cert_fingerprints[]' \
              "$al_body")
        if [[ -z $got ]]; then
            crit "assetlinks.json has no entry for $PROD_PACKAGE — App Links + passkeys are BROKEN on every Play install"
        elif ! printf '%s\n' "$got" | grep -qxF "$PROD_FINGERPRINT"; then
            crit "$PROD_PACKAGE fingerprint MISMATCH. expected $PROD_FINGERPRINT / served $(printf '%s' "$got" | tr '\n' ' ')"
        else
            note "$PROD_PACKAGE carries the Play App Signing fingerprint"
        fi
        relations=$(jq -r --arg p "$PROD_PACKAGE" \
                    '.[] | select(.target.package_name == $p) | .relation[]' "$al_body")
        for rel in delegate_permission/common.handle_all_urls delegate_permission/common.get_login_creds; do
            if printf '%s\n' "$relations" | grep -qxF "$rel"; then note "relation $rel present"
            else crit "$PROD_PACKAGE is missing relation $rel"; fi
        done
    fi
fi
rm -f "$al_body"

# ------------------------------------------------------------------- 3. AASA (Apple)
echo
echo "[3/5] apple-app-site-association — Team ID + content type"
aasa_url="https://$WELLKNOWN_HOST/.well-known/apple-app-site-association"
aasa_body=$(mktemp)
aasa_meta=$(curl -sS -o "$aasa_body" -w '%{http_code} %{content_type}' --max-time 20 "$aasa_url" 2>/dev/null)
aasa_code=${aasa_meta%% *}; aasa_ctype=${aasa_meta#* }

if [[ $aasa_code != 200 ]]; then
    crit "AASA returned HTTP ${aasa_code:-<none>} (expected 200) at $aasa_url"
elif ! jq -e . "$aasa_body" >/dev/null 2>&1; then
    crit "AASA is not valid JSON — iOS will refuse the association"
else
    case $aasa_ctype in
        application/json*) note "content-type $aasa_ctype" ;;
        *) crit "AASA content-type is '$aasa_ctype', expected application/json" ;;
    esac
    applinks=$(jq -r '[.applinks.details[].appID] | join(", ")' "$aasa_body")
    webcreds=$(jq -r '[.webcredentials.apps[]]   | join(", ")' "$aasa_body")
    if [[ -z ${applinks//[[:space:]]/} ]]; then
        crit "AASA declares NO applinks.details appIDs"
    else
        note "applinks: $applinks"
        bad=$(jq -r --arg t "$TEAM_ID." '.applinks.details[].appID | select(startswith($t) | not)' "$aasa_body")
        [[ -n $bad ]] && crit "AASA applinks appID(s) not on Team $TEAM_ID: $(printf '%s' "$bad" | tr '\n' ' ')" \
                      || note "all applinks appIDs on Team $TEAM_ID"
    fi
    if [[ -z ${webcreds//[[:space:]]/} ]]; then
        crit "AASA declares NO webcredentials apps — passkeys will not associate"
    else
        note "webcredentials: $webcreds"
        bad=$(jq -r --arg t "$TEAM_ID." '.webcredentials.apps[] | select(startswith($t) | not)' "$aasa_body")
        [[ -n $bad ]] && crit "AASA webcredentials app(s) not on Team $TEAM_ID: $(printf '%s' "$bad" | tr '\n' ' ')" \
                      || note "all webcredentials apps on Team $TEAM_ID"
    fi
fi
rm -f "$aasa_body"

# ------------------------------------------------------------- 4. domain registration
echo
echo "[4/5] domain registration"
# rdap.org has proven unreachable from some networks; the Verisign .com endpoint is
# authoritative for .com and reachable both locally and from GitHub runners.
rdap=$(curl -sS --max-time 20 "https://rdap.verisign.com/com/v1/domain/$APEX" 2>/dev/null)
if ! printf '%s' "$rdap" | jq -e . >/dev/null 2>&1; then
    warn "RDAP lookup for $APEX returned no parseable JSON — could not check expiry"
else
    exp=$(printf '%s' "$rdap" | jq -r '.events[]? | select(.eventAction=="expiration") | .eventDate' | head -1)
    if [[ -z $exp ]]; then
        warn "RDAP for $APEX carries no expiration event"
    elif ! left=$(days_until "$exp"); then
        warn "could not parse RDAP expiry '$exp'"
    elif (( left < DOMAIN_CRIT )); then crit "$APEX registration expires in ${left}d ($exp)"
    elif (( left < DOMAIN_WARN )); then warn "$APEX registration expires in ${left}d ($exp)"
    else note "$APEX registration ${left}d remaining (expires $exp)"
    fi
fi

# ----------------------------------------------------------- 5. security.txt (RFC 9116)
echo
echo "[5/5] security.txt — contact line + expiry"
# ☠️ This host answers 200 with index.html for ANY path, so a status code proves nothing.
# Assert by CONTENT, and prove the assertion can fail: a bogus sibling path must NOT
# carry the Contact line. If it does, the rewrite is a catch-all and the check is void.
readonly ST_CONTACT="Contact: mailto:contact@geniegenerate.com"
readonly ST_WARN=45 ST_CRIT=14
st_url="https://$WELLKNOWN_HOST/.well-known/security.txt"
st_body=$(curl -sS --max-time 20 "$st_url" 2>/dev/null)
ctl_body=$(curl -sS --max-time 20 "https://$WELLKNOWN_HOST/.well-known/security.txt.negative-control" 2>/dev/null)
if printf '%s\n' "$ctl_body" | grep -qxF "$ST_CONTACT"; then
    crit "security.txt negative control FAILED — a bogus path also serves the Contact line; the content check cannot discriminate"
elif ! printf '%s\n' "$st_body" | grep -qxF "$ST_CONTACT"; then
    crit "security.txt at $st_url is missing or lacks '$ST_CONTACT' (researchers will find nobody to tell)"
else
    note "Contact line present; bogus sibling path does not carry it (negative control passed)"
    st_exp=$(printf '%s\n' "$st_body" | grep '^Expires:' | head -1 | awk '{print $2}')
    if [[ -z $st_exp ]]; then
        crit "security.txt has no Expires line — RFC 9116 requires one and tooling treats the file as invalid"
    elif ! left=$(days_until "$st_exp"); then
        crit "security.txt Expires '$st_exp' could not be parsed"
    elif (( left < ST_CRIT )); then crit "security.txt expires in ${left}d ($st_exp) — refresh security.txt in this repo AND web/apps/site/public/.well-known/"
    elif (( left < ST_WARN )); then warn "security.txt expires in ${left}d ($st_exp) — refresh both copies"
    else note "security.txt ${left}d remaining (expires $st_exp)"
    fi
fi

# ------------------------------------------------------------------------- verdict
echo
if (( worst == 0 )); then
    echo "== GREEN — all five surfaces healthy. No action, no notification. =="
else
    echo "== $( ((worst==2)) && echo CRITICAL || echo WARN ) — ${#FINDINGS[@]} finding(s) =="
    printf '%s\n' "${FINDINGS[@]}"
fi
exit "$worst"

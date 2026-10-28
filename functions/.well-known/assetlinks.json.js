// Cloudflare Pages Function — /.well-known/assetlinks.json, answered per host.
//
// One Pages root serves link./staginglink./devlink., and a static file cannot vary by host.
// link. is production's passkey RP ID host, so it must vouch for the Play-signed prod
// package ONLY: listing the .dev/.staging packages there (signed with an unprotected debug
// key) let any debug-signed APK be offered prod saved passwords and passkeys.
// devlink./staginglink. keep the whole file. Any other host (a *.pages.dev preview) gets
// the prod-only answer: the narrow statement is the safe default.
//
// The statements still live in /assetlinks.json at the repo root (one source); this only
// filters them. A Function answers before _redirects and _headers, so it sets its own
// headers. Tested by .github/tests/assetlinks_host.test.mjs; watched by
// .github/scripts/public_surface_watch.sh [2/6].

const PROD_PACKAGE = 'com.geniegenerate.app';
const FULL_FILE_HOSTS = new Set(['devlink.geniegenerate.com', 'staginglink.geniegenerate.com']);

export async function onRequest({ request, env }) {
    const url = new URL(request.url);
    const asset = await env.ASSETS.fetch(new URL('/assetlinks.json', url));
    if (!asset.ok) {
        // Never fall back to an empty list (breaks verification) or the unfiltered file.
        return new Response('assetlinks.json unavailable', { status: 503 });
    }
    const statements = await asset.json();
    const served = FULL_FILE_HOSTS.has(url.hostname.toLowerCase())
        ? statements
        : statements.filter((s) => s.target?.package_name === PROD_PACKAGE);
    return new Response(JSON.stringify(served, null, 4), {
        headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=300',
            'X-Robots-Tag': 'noindex',
        },
    });
}

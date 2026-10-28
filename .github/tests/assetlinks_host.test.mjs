// Unit test for functions/.well-known/assetlinks.json.js — the host-aware assetlinks answer.
// Run: node --test .github/tests/*.test.mjs   (no dependencies; Node 22+)
//
// Why: one Pages root serves link./staginglink./devlink., and a static file cannot vary by
// host. Prod link. is the passkey RP ID host, so it must vouch for the Play-signed prod
// package ONLY — never for the debug-key-signed .dev/.staging builds (mobile-app todos/0015 #22).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { onRequest } from '../../functions/.well-known/assetlinks.json.js';

const servedFile = await readFile(new URL('../../assetlinks.json', import.meta.url), 'utf8');
const PROD_FP = 'E5:14:6C:A1:87:27:13:5F:C1:63:74:87:86:89:7C:CE:4E:0A:4D:9B:D7:B7:EE:75:23:B4:ED:E5:3B:31:E5:65';
const DEBUG_FP_PREFIX = 'BF:BC:60:46';

function context(host, { assetStatus = 200 } = {}) {
    const fetched = [];
    return {
        fetched,
        request: new Request(`https://${host}/.well-known/assetlinks.json`),
        env: {
            ASSETS: {
                fetch: async (input) => {
                    fetched.push(new URL(input instanceof Request ? input.url : input).pathname);
                    return assetStatus === 200
                        ? new Response(servedFile, { headers: { 'Content-Type': 'application/json' } })
                        : new Response('not found', { status: assetStatus });
                },
            },
        },
    };
}

async function answer(host, opts) {
    const ctx = context(host, opts);
    const res = await onRequest(ctx);
    return { res, ctx, body: res.status === 200 ? await res.json() : null };
}

const packages = (body) => body.map((s) => s.target.package_name).sort();

test('link. (prod RP ID host) vouches for the Play-signed prod package only', async () => {
    const { res, ctx, body } = await answer('link.geniegenerate.com');
    assert.equal(res.status, 200);
    assert.deepEqual(ctx.fetched, ['/assetlinks.json']);
    assert.deepEqual(packages(body), ['com.geniegenerate.app']);
    assert.deepEqual(body[0].target.sha256_cert_fingerprints, [PROD_FP]);
    assert.ok(!JSON.stringify(body).includes(DEBUG_FP_PREFIX), 'debug cert must not appear on link.');
    assert.deepEqual(body[0].relation.sort(), [
        'delegate_permission/common.get_login_creds',
        'delegate_permission/common.handle_all_urls',
    ]);
});

for (const host of ['devlink.geniegenerate.com', 'staginglink.geniegenerate.com']) {
    test(`${host} keeps the dev/staging entries`, async () => {
        const { res, body } = await answer(host);
        assert.equal(res.status, 200);
        assert.deepEqual(packages(body), [
            'com.geniegenerate.app',
            'com.geniegenerate.app.dev',
            'com.geniegenerate.app.staging',
        ]);
    });
}

test('an unknown host (e.g. a *.pages.dev preview) gets the prod-only answer — fail safe', async () => {
    const { body } = await answer('geniegenerate-wellknown.pages.dev');
    assert.deepEqual(packages(body), ['com.geniegenerate.app']);
});

test('host match is exact and case-insensitive, not a suffix test', async () => {
    assert.deepEqual(packages((await answer('DEVLINK.geniegenerate.com')).body).length, 3);
    assert.deepEqual(packages((await answer('devlink.geniegenerate.com.evil.example')).body), ['com.geniegenerate.app']);
});

test('headers are the ones Google\'s verifier needs (_headers does not reach a Function)', async () => {
    const { res } = await answer('link.geniegenerate.com');
    assert.match(res.headers.get('content-type'), /^application\/json/);
    assert.equal(res.headers.get('cache-control'), 'public, max-age=300');
    assert.equal(res.headers.get('x-robots-tag'), 'noindex');
});

test('a missing asset is a 503, never an empty list or the unfiltered file', async () => {
    const { res } = await answer('link.geniegenerate.com', { assetStatus: 404 });
    assert.equal(res.status, 503);
});

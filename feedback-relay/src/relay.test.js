import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './index.js';
const env = { GITHUB_PAT: 'fake-test-only', FEEDBACK_LIMIT: { limit: async () => ({ success: true }) } };
const request = (payload) => new Request('https://example.test/feedback', { method: 'POST', headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.1' }, body: JSON.stringify(payload) });
test('fails closed without secret', async () => assert.equal((await worker.fetch(request({}), {})).status, 503));
test('rejects oversized streamed bodies', async () => assert.equal((await worker.fetch(request({ body: 'x'.repeat(33000) }), env)).status, 413));
test('enforces rate limit', async () => assert.equal((await worker.fetch(request({}), { ...env, FEEDBACK_LIMIT: { limit: async () => ({ success: false }) } })).status, 429));
test('rejects malformed fields', async () => assert.equal((await worker.fetch(request({ title: 1, body: 'hello', type: 'bug' }), env)).status, 400));
test('creates issue only in fixed repo, preserving reviewed text', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url, 'https://api.github.com/repos/canberkys/iPScanner/issues');
    assert.equal(JSON.parse(options.body).body, 'Reviewed text\n\n_Submitted via iPScanner._');
    return Response.json({ number: 42 });
  };
  try { const result = await worker.fetch(request({ title: 'Test', body: 'Reviewed text', type: 'bug', repo: 'other/repo' }), env); assert.equal((await result.json()).issueNumber, 42); }
  finally { globalThis.fetch = original; }
});
test('does not expose upstream errors or credentials', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response('sensitive server detail', { status: 401 });
  try { const result = await worker.fetch(request({ title: 'Test', body: 'Text', type: 'feature' }), env); assert.equal(result.status, 502); assert.ok(!(await result.text()).includes('sensitive')); }
  finally { globalThis.fetch = original; }
});

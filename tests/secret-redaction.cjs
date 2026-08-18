#!/usr/bin/env node
// Release-gate regression test: runtime diagnostics must never persist API
// credentials or authorization values. This deliberately reports only
// counts/paths, never matching text.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const home = process.env.HOME || '';
const nexusHome = path.join(home, '.nexus');
const sourceRoot = path.resolve(__dirname, '..');

function collectJsonl(dir) {
  if (!fs.existsSync(dir)) return [];
  const result = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) result.push(...collectJsonl(full));
    else if (entry.isFile() && entry.name.endsWith('.jsonl')) result.push(full);
  }
  return result;
}

const runtimeFiles = [
  path.join(nexusHome, 'logs', 'unified.jsonl'),
  ...collectJsonl(path.join(nexusHome, 'sessions')),
].filter(fs.existsSync);

// Require a provider-shaped, contiguous key body and a non-word boundary.
// Repository paths routinely contain names such as `xai-grok-shell` and
// `task-transaction`; treating those hyphenated identifiers as credentials
// makes the release gate unusable after a normal list_dir call.  DeepSeek and
// xAI keys use a long alphanumeric body, while OpenAI project keys may include
// the literal `proj-` segment.
const credentialLike = /(?:^|[^A-Za-z0-9])(?:sk-(?:proj-)?|xai-)[A-Za-z0-9]{20,}(?![A-Za-z0-9])/i;
const bearerLike = /bearer\s+[A-Za-z0-9._~+\-/=]{8,}/i;

// Regression guards for the detector itself. These are synthetic values and
// never written to runtime files or printed.
assert.equal(credentialLike.test(`sk-${'a'.repeat(32)}`), true);
assert.equal(credentialLike.test(`sk-proj-${'b'.repeat(32)}`), true);
assert.equal(credentialLike.test(`xai-${'c'.repeat(32)}`), true);
assert.equal(credentialLike.test('/crates/xai-grok-shell-session-support/'), false);
assert.equal(credentialLike.test('/tests/task-transaction-harness.swift'), false);
const leaks = [];
for (const file of runtimeFiles) {
  const content = fs.readFileSync(file, 'utf8');
  if (credentialLike.test(content) || bearerLike.test(content)) leaks.push(file);
}
assert.deepEqual(leaks, [], `runtime logs contain credential-shaped data (${leaks.length} files)`);

const sampler = fs.readFileSync(
  path.join(sourceRoot, 'crates/codegen/xai-grok-sampler/src/client.rs'),
  'utf8',
);
assert.equal(sampler.includes('api_key = %api_key'), false, 'sampler logs an API key');
assert.equal(sampler.includes('auth_header_prefix ='), false, 'sampler logs an auth prefix');
assert.equal(sampler.includes('x_api_key_prefix ='), false, 'sampler logs an API-key prefix');

const model = fs.readFileSync(
  path.join(sourceRoot, 'crates/codegen/xai-grok-shell/src/auth/model.rs'),
  'utf8',
);
assert.match(model, /"\[REDACTED\]"/);

console.log(`PASS secret redaction: scanned ${runtimeFiles.length} runtime JSONL files; no credential-shaped values`);

#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.join(__dirname, '..');
const swift = path.join(__dirname, 'browser-verification-harness.swift');
const output = path.join(os.tmpdir(), `ai-dev-one-browser-contract-${process.pid}`);
const sources = [
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/BrowserVerification.swift'),
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/ProjectIntelligence.swift'),
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/GitHubIntegration.swift'),
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/TaskTransaction.swift'),
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/VerificationGate.swift'),
  swift,
];
const compile = spawnSync('swiftc', [
  '-O', '-framework', 'AppKit', '-framework', 'Foundation', '-framework', 'Security', '-framework', 'WebKit',
  '-o', output, ...sources,
], { encoding: 'utf8', timeout: 120000 });
if (compile.status !== 0) {
  console.error(compile.stdout || '', compile.stderr || '');
  process.exit(1);
}
const run = spawnSync(output, { encoding: 'utf8', timeout: 30000 });
if (run.status !== 0) {
  console.error(run.stdout || '', run.stderr || '');
  process.exit(1);
}
console.log(run.stdout.trim());
console.log('PASS browser verification acceptance harness');

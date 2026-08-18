#!/usr/bin/env node
const os = require('os');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.join(__dirname, '..');
const outputDir = path.join(os.tmpdir(), `ai-dev-one-browser-live-${process.pid}`);
fs.mkdirSync(outputDir, { recursive: true });
const output = path.join(outputDir, 'runner');
const sources = [
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/BrowserVerification.swift'),
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/ProjectIntelligence.swift'),
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/GitHubIntegration.swift'),
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/TaskTransaction.swift'),
  path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/VerificationGate.swift'),
  path.join(__dirname, 'browser-verification-live-harness.swift'),
];
const compile = spawnSync('swiftc', [
  '-O', '-framework', 'AppKit', '-framework', 'Foundation', '-framework', 'Security', '-framework', 'WebKit',
  '-o', output, ...sources,
], { encoding: 'utf8', timeout: 180000 });
if (compile.status !== 0) {
  console.error(compile.stdout || '', compile.stderr || '');
  process.exit(1);
}
const run = spawnSync(output, { encoding: 'utf8', timeout: 180000, env: { ...process.env, NSUnbufferedIO: 'YES' } });
if (run.status !== 0) {
  console.error(run.stdout || '', run.stderr || '');
  process.exit(1);
}
process.stdout.write(run.stdout);
const processes = spawnSync('ps', ['-axo', 'command='], { encoding: 'utf8' }).stdout || '';
if (processes.includes('ai-dev-one-browser-fixture')) {
  console.error('managed browser fixture process remained after verification');
  process.exit(1);
}
console.log('PASS browser verification live E2E fixtures');

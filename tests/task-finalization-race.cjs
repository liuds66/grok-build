#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const mainSource = fs.readFileSync(
  path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'),
  'utf8',
);
for (const token of [
  'case .failed(let message, let cancellationSource)',
  'finalization.requestCancel(source: .user)',
  'browserVerification.cancel()',
  'guard finalization.runtimeEndReceived',
  'TaskCancellationSource',
]) {
  if (!mainSource.includes(token)) throw new Error(`desktop finalization contract missing: ${token}`);
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-finalization-'));
const binary = path.join(root, 'task-finalization-race');
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-o', binary,
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/TaskTransaction.swift'),
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/TaskFinalization.swift'),
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/VerificationGate.swift'),
    path.join(__dirname, 'task-finalization-race-harness.swift')], {stdio: 'pipe'});
  const output = cp.execFileSync(binary, [], {encoding: 'utf8'}).trim();
  if (!output.includes('race=A/B/C/D/E/F PASS') || !output.includes('reviewer-gate PASS') || !output.includes('trace-monotonic PASS')) {
    throw new Error(output);
  }
  console.log('PASS task finalization/cancellation race contract: ' + output);
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}

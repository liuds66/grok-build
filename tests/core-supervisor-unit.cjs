#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const main = fs.readFileSync(
  path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'),
  'utf8'
);
const recovery = fs.readFileSync(
  path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/CoreRecovery.swift'),
  'utf8'
);

for (const marker of [
  'final class CoreSupervisor',
  'private var manualShutdown = false',
  'private var generation: UInt64 = 0',
  'private var recoveryWorkItem: DispatchWorkItem?',
  'private(set) var restartAttempt = 0',
  'private static let retryDelays: [TimeInterval] = [1, 2, 5]',
  'func scheduleAutomaticRecovery',
  'func manualRestart',
  'func shutdown()',
  'task.terminationHandler',
  'terminationReason == .uncaughtSignal',
  'CoreSupervisor.logFileURL',
]) {
  assert.ok(main.includes(marker), `missing supervisor marker: ${marker}`);
}

for (const state of ['case stopped', 'case starting', 'case ready', 'case disconnected', 'case restarting', 'case failed']) {
  assert.match(recovery, new RegExp(state), `missing CoreState: ${state}`);
}

// A killed task must be classified as disconnected before stderr/API errors,
// and the old prompt must never be replayed by the recovery callback.
const signalBranch = main.slice(main.indexOf('if !didEnd {'), main.indexOf('if !didEnd {') + 1000);
assert.ok(signalBranch.indexOf('terminationReason == .uncaughtSignal') < signalBranch.indexOf('!errorText.isEmpty'));
assert.doesNotMatch(main, /scheduleAutomaticRecovery[\s\S]{0,800}restartInterruptedTask/);
assert.match(main, /重新启动 Core/);
assert.match(main, /查看日志/);
console.log('core-supervisor-unit: PASS single-owner/backoff/manual-restart contract');

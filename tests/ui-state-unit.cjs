#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
const core = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/CoreRecovery.swift'), 'utf8');

for (const marker of ['enum ModelState', 'enum AgentState', 'enum WorkspaceState']) {
  assert.match(source, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
}
assert.match(core, /enum CoreState/);
assert.match(source, /打开模型设置/);
assert.match(source, /重新连接/);
assert.match(source, /redactSensitive/);
assert.doesNotMatch(source, /Agent Ready/);
console.log('ui-state-unit: PASS');

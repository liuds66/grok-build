#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
const machine = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/TaskTransaction.swift'), 'utf8');
for (const marker of ['Planning', 'Editing', 'Testing', 'Reviewing', 'Waiting', 'Completed', 'Failed']) {
  assert.match(source, new RegExp(marker));
}
assert.match(source, /func setFailure\(\)/);
assert.match(source, /Agent Idle/);
assert.match(machine, /case active/);
assert.match(machine, /case failed/);
console.log('agent-state-unit: PASS');

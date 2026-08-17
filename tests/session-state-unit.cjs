#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
assert.match(source, /guard !runner\.isRunning/);
assert.match(source, /selectedID/);
assert.match(source, /messageID/);
assert.match(source, /session\.messages/);
assert.match(source, /desktop-sessions\.json/);
console.log('session-state-unit: PASS');

#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
assert.match(source, /最近变更/);
assert.match(source, /prefix\(50\)/);
assert.match(source, /byTruncatingMiddle/);
assert.match(source, /项目缺失/);
assert.doesNotMatch(source, /Recent Changes/);
assert.doesNotMatch(source, /Modified/);
console.log('workspace-parser-unit: PASS');

#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
for (const marker of ['401', '429', '502', '503', 'timeout', '网络', '模型配置异常', '模型请求受限', '模型接口离线']) {
  assert.match(source, new RegExp(marker));
}
assert.match(source, /kSecUseAuthenticationContext/);
assert.match(source, /Thread\.isMainThread/);
console.log('model-error-unit: PASS');

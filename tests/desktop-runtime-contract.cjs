#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'),
  'utf8',
);

if (!source.includes('let sandbox = "workspace"')) {
  throw new Error('desktop tasks must keep network access for model requests');
}
if (!source.includes('approval == .readOnly ? "plan" : "bypassPermissions"')) {
  throw new Error('workspace approval/read-only mode contract missing');
}
if (!source.includes('activeToolFailure')) {
  throw new Error('tool failures must block false task completion');
}
if (!source.includes('toolchains/node/bin')) {
  throw new Error('Finder-launched tasks must restore the installer toolchain PATH');
}
if (!source.includes('lateSuccess = value != nil && completionDelivered')) {
  throw new Error('late Keychain success must recover after a bounded timeout');
}
console.log('desktop-runtime-contract: PASS');

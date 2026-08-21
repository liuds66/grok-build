#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const buildScript = fs.readFileSync(path.join(root, 'scripts/build-nexus-desktop'), 'utf8');

const required = [
  'AI_DEV_ONE_CODESIGN_IDENTITY',
  'codesign --force --deep --sign "${signing_identity}"',
  'codesign --force --deep --sign -',
  'signing_mode="AD_HOC"',
  'signing_mode="APPLE_DEVELOPMENT"',
  'echo "SIGNING_MODE=${signing_mode}"',
];
for (const token of required) {
  if (!buildScript.includes(token)) {
    throw new Error(`stable signing contract missing: ${token}`);
  }
}

if (/security\s+.*(?:-w|find-generic-password)/.test(buildScript)) {
  throw new Error('build script must not read or print Keychain secrets');
}
if (/\.p12|private\s*key|login\s*password/i.test(buildScript)) {
  throw new Error('build script must not contain private signing material');
}

console.log('PASS local signing identity/fallback contract');

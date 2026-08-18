#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/BrowserVerification.swift'), 'utf8');
const main = fs.readFileSync(path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
const build = fs.readFileSync(path.join(root, 'scripts/build-nexus-desktop'), 'utf8');

const required = [
  'protocol BrowserDriver',
  'final class WKBrowserDriver',
  'final class DevServerSupervisor',
  'final class BrowserVerificationService',
  'enum BrowserURLPolicy',
  'BrowserVerificationConfiguration.serverStartupTimeout',
  'BrowserVerificationConfiguration.pageLoadTimeout',
  'BrowserVerificationConfiguration.browserLaunchTimeout',
  'BrowserVerificationConfiguration.verificationTimeout',
  'enum BrowserVerificationRedaction',
  'private var launchTimer',
  'BrowserEvidenceStore',
  'console.error',
  'network.failure',
  'horizontalOverflow',
  'invalidImportantElements',
  'WKSnapshotConfiguration',
  'cleanupExpired',
];
for (const token of required) {
  if (!source.includes(token)) throw new Error(`browser verification contract missing: ${token}`);
}
if (!source.includes('host == "localhost" || host == "127.0.0.1"')) throw new Error('URL allowlist must be localhost-only');
if (source.includes('http://google.com') || source.includes('https://github.com')) throw new Error('browser source must not hard-code external domains');
if (!source.includes('removeValue(forKey: "OPENAI_API_KEY")')) throw new Error('browser process environment must not inherit API key');
if (!source.includes('BrowserURLPolicy.sanitizedString')) throw new Error('browser evidence must sanitize URLs');
if (!source.includes('captureScreenshot(fullPage: Bool')) throw new Error('browser driver must support viewport/full-page screenshots');
if (!main.includes('onBrowserVerification') || !main.includes('BrowserVerificationPlanner.shouldRun')) throw new Error('desktop UI/agent integration missing');
if (!build.includes('-framework WebKit')) throw new Error('desktop build must link WebKit');
console.log('PASS browser verification driver/security/layout contract');

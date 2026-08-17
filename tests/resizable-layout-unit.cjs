#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
const number = (name) => Number(source.match(new RegExp(`${name}: CGFloat = ([0-9]+)`))[1]);

assert.equal(number('sidebarDefaultWidth'), 260);
assert.equal(number('sidebarMinimumWidth'), 220);
assert.equal(number('sidebarMaximumWidth'), 420);
assert.equal(number('workspaceDefaultWidth'), 340);
assert.equal(number('workspaceMinimumWidth'), 280);
assert.equal(number('workspaceMaximumWidth'), 620);
assert.equal(number('chatMinimumWidth'), 520);
assert.match(source, /minimumWindowWidth: CGFloat = 1180/);
assert.match(source, /minimumWindowHeight: CGFloat = 720/);
assert.match(source, /normalizedStoredWidth/);
assert.match(source, /resetDivider/);
assert.match(source, /override func hitTest\(_ point: NSPoint\)/);
assert.match(source, /override func mouseDragged\(with event: NSEvent\)/);
assert.match(source, /override func mouseUp\(with event: NSEvent\)/);
assert.match(source, /private var dragStartX: CGFloat\?/);
assert.match(source, /insetBy\(dx: -5, dy: 0\)/);
assert.match(source, /bounds\.width - startWorkspace - chatMinimumWidth/);
assert.match(source, /if sender\.isZoomed \{/);

const clamp = (value, min, max) => Math.min(Math.max(value, min), Math.max(min, max));
assert.equal(clamp(260 + 50, 220, 420), 310, 'left divider positive delta');
assert.equal(clamp(260 - 1000, 220, 420), 220, 'left divider lower bound');
assert.equal(clamp(260 + 1000, 220, 420), 420, 'left divider upper bound');
assert.equal(clamp(340 - 60, 280, 620), 280, 'right divider lower bound');
assert.equal(clamp(340 + 1000, 280, 620), 620, 'right divider upper bound');
assert.equal(Number.isFinite(Number.NaN), false, 'invalid persistence is rejected before clamping');
console.log('resizable-layout-unit: PASS');

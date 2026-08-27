const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const main = fs.readFileSync(path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
const dashboard = fs.readFileSync(path.join(root, 'apps/nexus-desktop/Sources/NexusDesktop/IntelligenceDashboard.swift'), 'utf8');

// The Workspace tab remains an entry point, while the actual center is one
// independent NSPanel instance.  These checks protect the lifecycle boundary
// from accidentally regressing into an embedded, narrow side panel.
assert.match(main, /labels: \["工作区", "文件", "知识库", "工具", "工作监控", "全球情报"\]/);
assert.match(main, /openIntelligenceWindow\(\)/);
assert.match(main, /showIntelligenceFromMenu/);
assert.match(main, /title: "全球情报中心"/);
assert.match(main, /var isIntelligenceWindowVisible: Bool/);
assert.match(main, /view\.window\?\.orderOut\(nil\)/);
assert.match(dashboard, /final class IntelligenceWindowController: NSWindowController, NSWindowDelegate/);
assert.match(dashboard, /AI Dev One · 全球情报中心/);
assert.match(dashboard, /width: 1260, height: 760/);
assert.match(dashboard, /window\.minSize = NSSize\(width: 1050, height: 650\)/);
assert.match(dashboard, /window\.contentMinSize = NSSize\(width: 1050, height: 650\)/);
assert.match(dashboard, /let mainGrid = NSView\(\)/);
assert.match(dashboard, /leftColumn\.widthAnchor\.constraint\(equalTo: mainGrid\.widthAnchor, multiplier: 0\.58, constant: -6\.96\)/);
assert.match(dashboard, /mainGrid\.heightAnchor\.constraint\(equalToConstant: 668\)/);
assert.match(dashboard, /globeCard\.heightAnchor\.constraint\(equalToConstant: 350\)/);
assert.match(dashboard, /feedCard\.heightAnchor\.constraint\(equalToConstant: 308\)/);
assert.match(dashboard, /eventSummaryCard\.heightAnchor\.constraint\(equalToConstant: 148\)/);
assert.match(dashboard, /sourceCard\.heightAnchor\.constraint\(equalToConstant: 145\)/);
assert.match(dashboard, /riskCard\.heightAnchor\.constraint\(equalToConstant: 140\)/);
assert.match(dashboard, /aiCard\.heightAnchor\.constraint\(equalToConstant: 211\)/);
assert.match(dashboard, /eventTotalValue\.font = \.monospacedDigitSystemFont\(ofSize: 40/);
assert.match(dashboard, /row\.heightAnchor\.constraint\(equalToConstant: 52\)/);
assert.match(dashboard, /let baseRadius = min\(rect\.width \* 0\.36, rect\.height \* 0\.50\)/);
assert.match(dashboard, /leftColumn\.widthAnchor\.constraint\(equalTo: mainGrid\.widthAnchor, multiplier: 0\.58, constant: -6\.96\)/);
assert.match(dashboard, /insightBoards\.widthAnchor\.constraint\(equalTo: mainGrid\.widthAnchor, multiplier: 0\.42, constant: -5\.04\)/);
assert.match(dashboard, /insightBoards\.alignment = \.width/);
// Every arranged card is explicitly Auto Layout-driven and tied to its
// column width.  This prevents AppKit from falling back to intrinsic or
// autoresizing widths (the V1.2R1 regression that created narrow floating
// cards despite a correctly sized two-column grid).
assert.match(dashboard, /card\.translatesAutoresizingMaskIntoConstraints = false/);
assert.match(dashboard, /card\.widthAnchor\.constraint\(equalTo: insightBoards\.widthAnchor\)/);
assert.match(dashboard, /globeCard\.widthAnchor\.constraint\(equalTo: leftColumn\.widthAnchor\)/);
assert.match(dashboard, /feedCard\.widthAnchor\.constraint\(equalTo: leftColumn\.widthAnchor\)/);
assert.match(dashboard, /AI_DEV_ONE_INTELLIGENCE_DEBUG_FRAMES/);
assert.match(dashboard, /"globeCard", globeCard/);
assert.match(dashboard, /"realtimeCard", feedCard/);
assert.match(dashboard, /"sourcesCard", sourceCard/);
assert.match(dashboard, /"riskCard", riskCard/);
assert.match(dashboard, /"aiInsightCard", aiCard/);
assert.match(dashboard, /private var rotationOffset: CGFloat = -110/);
assert.match(dashboard, /let center = NSPoint\(x: 52, y: bounds\.midY\)/);
assert.match(dashboard, /bounds\.height \* 0\.48/);
assert.match(dashboard, /Keep hit testing aligned with the framed sphere/);
assert.match(dashboard, /信息来源（Top 6）/);
assert.match(dashboard, /• 亚太航运与能源监测样本/);
assert.match(dashboard, /window\.level = isPinned \? \.floating : \.normal/);
assert.match(dashboard, /ai-dev-one\.intelligence\.pinned/);
assert.match(dashboard, /window\.setFrameAutosaveName/);
assert.match(dashboard, /window\.setFrameUsingName/);
assert.match(dashboard, /window\.isReleasedWhenClosed = false/);
assert.match(dashboard, /onPinToggle/);
assert.match(dashboard, /置顶情报中心/);
assert.match(dashboard, /取消置顶情报中心/);
assert.match(dashboard, /windowWillClose/);

// V1 is explicitly fixture-only.  The legacy OSIRIS controller remains in
// the source for a future provider, but the panel refresh path must never
// start it or issue a URLSession request.
assert.match(dashboard, /enum IntelligenceSourceMode/);
assert.match(dashboard, /case fixture/);
assert.match(dashboard, /struct IntelligenceEvent/);
assert.match(dashboard, /struct GlobalIntelligenceSnapshot/);
assert.match(dashboard, /protocol IntelligenceDataProvider/);
assert.match(dashboard, /final class FixtureIntelligenceDataProvider/);
assert.match(dashboard, /sourceMode: IntelligenceSourceMode = \.fixture/);
assert.match(dashboard, /eventTotal: 3_421/);
assert.match(dashboard, /flightCount: 335/);
assert.match(dashboard, /satelliteCount: 18_841/);
assert.match(dashboard, /earthquakeCount: 47/);
assert.match(dashboard, /IntelligenceRiskSummary\(high: 23, medium: 67, low: 66\)/);
assert.match(dashboard, /case high/);
assert.match(dashboard, /case medium/);
assert.match(dashboard, /case low/);
const refreshStart = dashboard.indexOf('    func refresh() {');
const refreshEnd = dashboard.indexOf('    @objc private func refreshClicked()', refreshStart);
assert.ok(refreshStart >= 0 && refreshEnd > refreshStart, '必须存在可审计的情报刷新入口');
const refreshBlock = dashboard.slice(refreshStart, refreshEnd);
assert.doesNotMatch(refreshBlock, /IntelligenceServiceController/);
assert.doesNotMatch(refreshBlock, /URLSession/);
assert.match(refreshBlock, /fixtureProvider\.snapshot/);
assert.match(dashboard, /V1 仅显示本地固定样本，不连接网络/);
assert.match(dashboard, /本地固定样本/);
assert.match(dashboard, /Timer\(timeInterval: 60, repeats: true\)/);

// Globe interaction and low-cost rendering contract.
assert.match(dashboard, /override func mouseDragged\(with event: NSEvent\)/);
assert.match(dashboard, /override func scrollWheel\(with event: NSEvent\)/);
assert.match(dashboard, /private var zoomScale: CGFloat = 1\.0/);
assert.match(dashboard, /滚轮缩放/);
assert.match(dashboard, /drawLandMasses/);
assert.match(dashboard, /drawDataRoutes/);
assert.match(dashboard, /drawOrbitArcs/);
assert.match(dashboard, /drawTerminator/);
assert.match(dashboard, /oceanHighlight/);
assert.match(dashboard, /sphereShadow/);
assert.match(dashboard, /private var cachedBackground: NSImage\?/);
assert.match(dashboard, /Timer\(timeInterval: 1\.0 \/ 4\.0, repeats: true\)/);
assert.match(dashboard, /accessibilityDisplayShouldReduceMotion/);

// The overview must expose the concept-board information hierarchy and make
// every event row/analysis action keyboard and VoiceOver discoverable.
for (const label of ['事件总数', '信息来源', '风险摘要', 'AI 洞察', '情报详情', '情报动态', '航班', '卫星', '地震', '新闻']) {
  assert.match(dashboard, new RegExp(label));
}
assert.match(dashboard, /row\.setAccessibilityRole\(\.button\)/);
assert.match(dashboard, /row\.setAccessibilityLabel/);
assert.match(dashboard, /modeSelector\.setAccessibilityRole/);
assert.match(dashboard, /autoRefreshButton\.setAccessibilityLabel/);
assert.match(dashboard, /riskRing\.update/);
assert.match(dashboard, /let percentage = Int\(\(Double\(entry\.1\) \/ Double\(total\)/);
assert.match(dashboard, /用 AI Dev One 分析/);
assert.match(dashboard, /onAnalyze: \(\(String\) -> Bool\)\?/);
assert.match(dashboard, /feedScrollView\.hasVerticalScroller = true/);
assert.match(dashboard, /feedHistory\.prefix\(12\)/);
assert.match(dashboard, /intelligenceWrappingLabel/);

console.log('global intelligence center contract: ok');

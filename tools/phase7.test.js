'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const advisorSource = fs.readFileSync(path.join(ROOT, 'TravelAdvisor.lua'), 'utf8');

function assertContains(source, text, message) {
    assert.ok(source.includes(text), message || `Expected source to contain: ${text}`);
}

function getReportCommandBlock() {
    const start = advisorSource.indexOf('elseif msg == "report"');
    assert.ok(start >= 0, 'The /travel report command must exist.');

    const end = advisorSource.indexOf('\n    elseif ', start + 1);
    return advisorSource.slice(start, end >= 0 ? end : advisorSource.length);
}

function getTreeNodeBlock() {
    const start = advisorSource.indexOf('local function CreateTreeNode(');
    assert.ok(start >= 0, 'The zone tree row builder must exist.');

    const end = advisorSource.indexOf('\nlocal function BuildZoneTree', start + 1);
    assert.ok(end >= 0, 'The zone tree builder must follow the row builder.');
    return advisorSource.slice(start, end);
}

function testReportCommandAndHelp() {
    assertContains(advisorSource, 'elseif msg == "report"',
        'The troubleshooting report command must be available as /travel report.');
    assertContains(advisorSource, '/travel report',
        'The command help must document /travel report.');
}

function testPasteReadyReportEnvelope() {
    for (const token of [
        'BuildTroubleshootingReport',
        'PROMPT',
        'DATA',
    ]) {
        assertContains(advisorSource, token,
            `The troubleshooting report must contain a paste-ready ${token} section.`);
    }
}

function testModalCopyInteraction() {
    for (const token of [
        'ShowTroubleshootingReport',
        'SetText("Copy")',
        'HighlightText()',
        'SetFocus()',
    ]) {
        assertContains(advisorSource, token,
            `The troubleshooting modal must provide the copy interaction: ${token}.`);
    }
}

function testReportDoesNotPrintToChat() {
    const reportBlock = getReportCommandBlock();
    assert.ok(!/\bPrint\s*\(|\bprint\s*\(/.test(reportBlock),
        'The /travel report command must not emit report data to chat.');
}

function testUnknownReportTargetsFailClosed() {
    const resolverStart = advisorSource.indexOf('local function ResolveTroubleshootingTarget');
    assert.ok(resolverStart >= 0, 'Troubleshooting target resolver must exist.');
    const resolverEnd = advisorSource.indexOf('\nend', resolverStart);
    const resolver = advisorSource.slice(resolverStart, resolverEnd >= 0 ? resolverEnd : resolverStart + 1200);
    assert.ok(/IsValidMapID\(mapID\)|mapID\s*<=\s*0/.test(resolver),
        'Troubleshooting target lookup must reject unknown or non-positive map IDs.');
    assertContains(resolver, 'lookup-failed',
        'Unknown troubleshooting destinations must return an explicit lookup failure.');
    const reportStart = advisorSource.indexOf('elseif msg == "report"');
    const reportEnd = advisorSource.indexOf('elseif msg == "troubleshoot"', reportStart);
    const reportBlock = advisorSource.slice(reportStart, reportEnd >= 0 ? reportEnd : reportStart + 1800);
    assert.ok(/lookup-failed|unknown destination|Unknown destination/i.test(reportBlock),
        'The report command must surface an unknown destination instead of reporting mapID 0.');
    assert.ok(!/mapID\s*[:=]\s*0/.test(reportBlock),
        'The report command must not construct a report target with mapID 0.');
}

function testEmptyDescriptionsDoNotCreateBlankRegions() {
    const resultsStart = advisorSource.indexOf('function TA:DisplayResults');
    assert.ok(resultsStart >= 0, 'DisplayResults must exist.');
    const results = advisorSource.slice(resultsStart, resultsStart + 12000);
    assert.ok(/local description\s*=\s*SafeString\(route\.description\)/.test(results),
        'Route descriptions must be normalized through the safe display helper.');
    assert.ok(/hasDesc\s*=\s*description\s*~=\s*nil\s*and\s*description\s*~=\s*""/.test(results),
        'Empty descriptions must not create a blank description region.');
}

function testTroubleshootButtonLivesInResultsHeader() {
    const treeNodeBlock = getTreeNodeBlock();
    assert.ok(!/Troubleshoot/.test(treeNodeBlock),
        'Destination tree rows must not contain Troubleshoot controls.');
    assertContains(advisorSource, 'CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")',
        'The results panel must own the Troubleshoot button.');
    assertContains(advisorSource, 'troubleshootButton:SetPoint("TOPRIGHT", rightPanel',
        'The Troubleshoot button must be anchored to the results panel TOPRIGHT.');
    assertContains(advisorSource, 'troubleshootButton:SetText("Troubleshoot")',
        'The results header button must be labeled Troubleshoot.');
    assert.ok(/troubleshootButton:SetScript\("OnClick", function\(\)[\s\S]*?TA\.currentDestMapID[\s\S]*?SlashCmdList\["TRAVELADVISOR"\]\("troubleshoot " \.\. tostring\(TA\.currentDestMapID\)\)/.test(advisorSource),
        'The header Troubleshoot button must invoke the slash handler for the selected destination.');
    assert.ok(/self\.currentDestMapID = destMapID[\s\S]*?if f\.troubleshootButton then[\s\S]*?destMapID and destMapID > 0[\s\S]*?Enable\(\)[\s\S]*?Disable\(\)/.test(advisorSource),
        'DisplayResults must update the header Troubleshoot button enabled state.');
}

function testDestinationFilterUsesCaseInsensitivePlainMatching() {
    assert.ok(/node\.name:lower\(\):find\(filterText,\s*1,\s*true\)/.test(advisorSource),
        'The destination filter must compare names case-insensitively using a plain substring match.');
}

function testDestinationFilterRetainsMatchingAncestors() {
    const treeNodeBlock = getTreeNodeBlock();
    assert.ok(/nodeMatchesFilter\(node,\s*filterText\)/.test(treeNodeBlock),
        'The destination row builder must evaluate whether a node or descendant matches the filter.');
    assert.ok(/for _, child in ipairs\(node\.children\) do[\s\S]*?nodeMatchesFilter\(child,\s*filterText\)/.test(treeNodeBlock),
        'Destination filtering must recurse through children so matching descendants retain their ancestors.');
}

function testDestinationFilterRefreshesOnTextChange() {
    assert.ok(/destinationFilter:SetScript\("OnTextChanged",\s*function\(\)[\s\S]*?TA:RefreshZoneTree\(\)/.test(advisorSource),
        'Typing in the destination filter must refresh the destination tree.');
    assert.ok(/destinationFilter:SetScript\("OnTextChanged",[\s\S]*?C_Timer\.After\(/.test(advisorSource),
        'Destination filtering must debounce refreshes instead of rebuilding on every keystroke.');
    assertContains(advisorSource, '_destinationFilterRefreshScheduled',
        'Destination filter debounce state must coalesce pending refreshes.');
}

function testDestinationFilterResetsWhenEmpty() {
    assert.ok(/if not filterText or filterText == "" then[\s\S]*?return true/.test(advisorSource),
        'An empty destination filter must restore the unfiltered tree path.');
}

testReportCommandAndHelp();
testPasteReadyReportEnvelope();
testModalCopyInteraction();
testReportDoesNotPrintToChat();
testUnknownReportTargetsFailClosed();
testEmptyDescriptionsDoNotCreateBlankRegions();
testTroubleshootButtonLivesInResultsHeader();
testDestinationFilterUsesCaseInsensitivePlainMatching();
testDestinationFilterRetainsMatchingAncestors();
testDestinationFilterRefreshesOnTextChange();
testDestinationFilterResetsWhenEmpty();
console.log('Phase 7 contract tests: PASS');

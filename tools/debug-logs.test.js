'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { runLuaJITHarness } = require('./lua-runtime');

const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const settingsSource = read('TravelAdvisorSettings.lua');
const advisorSource = read('TravelAdvisor.lua');
const checkSource = read('tools/check.js');

function assertContains(source, token, message) {
    assert.ok(source.includes(token), message || `Expected source to contain: ${token}`);
}

function testSettingsHarness() {
    const result = runLuaJITHarness(path.join(__dirname, 'debug-logs-repro.lua'), ROOT);
    if (result.skipped) return;
    assert.strictEqual(result.result.status, 0, result.result.stderr || result.result.stdout);
    assert.match(result.result.stdout, /Debug logs settings regression: PASS/);
}

function testUnboundedVersionedSettingsContract() {
    for (const token of [
        'VERSION = 2',
        'debugLogging = false',
        'local function normalizeDebugLogs(logs)',
        'timestamp = normalizeDebugText(entry.timestamp)',
        'mapID = type(entry.mapID) == "number" and entry.mapID or nil',
        'realZone = normalizeDebugText(entry.realZone)',
        'subZone = normalizeDebugText(entry.subZone)',
        'function Settings:AddDebugLog(entry)',
    ]) assertContains(settingsSource, token);
    assert.ok(!settingsSource.includes('MAX_DEBUG_LOGS'), 'debug log history must not be capped');
    assert.ok(!settingsSource.includes('MAX_DEBUG_TEXT'), 'debug text fields must not be truncated');
}

function testSavedVariableDisclosure() {
    assertContains(advisorSource, 'function TA:ToggleDebugLogging()');
    const toggleStart = advisorSource.indexOf('function TA:ToggleDebugLogging()');
    const toggleEnd = advisorSource.indexOf('\nend', toggleStart);
    const enableNotice = advisorSource.slice(toggleStart, toggleEnd);
    assertContains(enableNotice, 'SavedVariables\\\\TravelAdvisor.lua', 'Enable notice must disclose the SavedVariables file.');
    assertContains(enableNotice, 'logout or reload', 'Enable notice must disclose WoW save timing.');

    const viewerStart = advisorSource.indexOf('local function BuildDebugLogReport()');
    const viewerEnd = advisorSource.indexOf('\nend', viewerStart);
    const viewer = advisorSource.slice(viewerStart, viewerEnd);
    assertContains(advisorSource, 'local savedVariablesPath = "D:\\\\Battle.net', 'A per-character SavedVariables path must be defined.');
    assertContains(viewer, 'Location: " .. savedVariablesPath', 'Logs viewer must disclose the SavedVariables file path.');
    assertContains(viewer, 'TravelAdvisor_Settings.debugLogs', 'Logs viewer must identify the stored table.');
    assertContains(viewer, 'logout or reload', 'Logs viewer must disclose WoW save timing.');
}

function testLocationTransitionCaptureAndControls() {
    for (const token of [
        'function TA:OnLoadingStart()',
        'function TA:OnLoadingEnd()',
        'function TA:OnZoneChanged()',
        'local function GetDebugLocationSnapshot()',
        'C_Map.GetBestMapForUnit, "player"',
        '_G.GetRealZoneText',
        '_G.GetSubZoneText',
        'local function RecordDebugTransition(event, onlyIfChanged)',
        'RecordDebugTransition("PLAYER_LOGIN")',
        'RecordDebugTransition(event)',
        'RecordDebugTransition("POST_DEBOUNCE_LOCATION", true)',
        'event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "PLAYER_ENTERING_WORLD"',
        'eventFrame:RegisterEvent("LOADING_SCREEN_ENABLED")',
        'eventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")',
        'TA:ToggleDebugLogging()',
        'TA:ShowDebugLogs()',
        'elseif msg == "verbose" then',
        'elseif msg == "logs" then',
        'copyButton:SetText("Select All")',
        'explicitCloseButton:SetText("Close")',
        'Prompt: Review these transition records',
        'BEGIN_DATA',
        'END_DATA',
    ]) assertContains(advisorSource, token);
    assertContains(checkSource, "debug-logs.test.js", 'The new focused test must be registered.');
}

testSettingsHarness();
testUnboundedVersionedSettingsContract();
testLocationTransitionCaptureAndControls();
testSavedVariableDisclosure();
console.log('Debug logs contract tests: PASS');

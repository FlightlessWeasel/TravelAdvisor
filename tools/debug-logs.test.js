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

function testBoundedVersionedSettingsContract() {
    for (const token of [
        'VERSION = 2',
        'debugLogging = false',
        'MAX_DEBUG_LOGS = 100',
        'MAX_DEBUG_TEXT = 80',
        'local function normalizeDebugLogs(logs)',
        'timestamp = normalizeDebugText(entry.timestamp, 32)',
        'mapID = type(entry.mapID) == "number" and entry.mapID or nil',
        'realZone = normalizeDebugText(entry.realZone, Settings.MAX_DEBUG_TEXT)',
        'subZone = normalizeDebugText(entry.subZone, Settings.MAX_DEBUG_TEXT)',
        'function Settings:AddDebugLog(entry)',
        'if #logs > self.MAX_DEBUG_LOGS then table.remove(logs, 1) end',
    ]) assertContains(settingsSource, token);
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
        'Prompt: Review these bounded transition records',
        'BEGIN_DATA',
        'END_DATA',
    ]) assertContains(advisorSource, token);
    assertContains(checkSource, "debug-logs.test.js", 'The new focused test must be registered.');
}

testSettingsHarness();
testBoundedVersionedSettingsContract();
testLocationTransitionCaptureAndControls();
console.log('Debug logs contract tests: PASS');

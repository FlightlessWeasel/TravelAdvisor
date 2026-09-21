'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const advisorSource = read('TravelAdvisor.lua');
const graphSource = read('TravelGraph.lua');
const sourcesSource = read('TravelSources.lua');
const settingsSource = read('TravelAdvisorSettings.lua');
const tocSource = read('TravelAdvisor.toc');
const planSource = read('MASTER_PLAN.md');
const validationSource = read('VALIDATION.md');
const checkSource = read('tools/check.js');

function assertContains(source, text, message) {
    assert.ok(source.includes(text), message || `Expected source to contain: ${text}`);
}

function testBestNowAndWaitPolicies() {
    for (const token of [
        'SafeBoolean(result.readyNow) == false',
        'SafeBoolean(result.executableNow) == false',
        'SafeBoolean(result.actionableNow) == false',
        'Graph.Policy.BEST_IF_READY',
        'Graph.Policy.BEST_AFTER_WAIT',
        'route.isInformationalOnly = true',
        'Wait: " .. FormatDuration',
    ]) {
        assertContains(advisorSource + graphSource, token,
            `Phase 6 policy separation is missing ${token}.`);
    }
    assertContains(graphSource, 'readyNow = readyNow and actionableNow');
    assertContains(graphSource, 'executableNow = executableNow');
    assertContains(advisorSource, 'route.explanation.waitTime = route.waitTime');
}

function testCanonicalExplanations() {
    for (const token of [
        'function Sources.BuildExplanation',
        'function Sources.ResolveActionPresentation',
        'sourceType = sourceTypeForExplanation',
        'destinationUncertain',
        'reasonText',
        'charges',
        'interaction',
        'requirements',
        'function Graph:BuildRouteExplanation',
        'sourceStates = routeSources',
        'GetPlayerSourceDiagnostics',
        'edgeDiagnostics',
        'route checks',
    ]) {
        assertContains(sourcesSource + graphSource + advisorSource, token,
            `Canonical explanation contract is missing ${token}.`);
    }
    assertContains(advisorSource, 'local sourceName = SafeText(source.sourceName');
    assertContains(advisorSource, 'local destination = SafeText(explanation.destinationName');
    assertContains(advisorSource, 'SafeText(reason.text)');
}

function testLocalizedNamesAndStableActions() {
    for (const token of [
        'GetSpellName',
        'GetSpellInfo',
        'GetToyInfo',
        'GetItemNameByID',
        'GetItemInfo',
        'GetSpellTexture',
        'GetItemIconByID',
        'effectiveSpellID',
        'actionID = result.action.id',
        'Secure actions use stable IDs',
        'actionConfig.value',
    ]) {
        assertContains(sourcesSource + advisorSource, token,
            `Localized stable-ID presentation is missing ${token}.`);
    }
    assert.ok(!advisorSource.includes('SetAttribute("spell", travel.name)'),
        'Secure action attributes must not use a localized display name.');
}

function testCoalescedCombatSafeRefresh() {
    for (const token of [
        'function TA:QueueRouteRefresh',
        'function TA:ApplyPendingRouteRefresh',
        'self._routeRefreshScheduled',
        'Refresh pending until combat ends',
        'self:ScanAvailableTravel()',
        'self:RefreshZoneTree()',
        'if IsInCombatLockdown() then return end',
        'PLAYER_REGEN_ENABLED',
        'TA:QueueRouteRefresh("manual-refresh")',
    ]) {
        assertContains(advisorSource, token,
            `Safe coalesced refresh is missing ${token}.`);
    }
    assertContains(advisorSource, 'function TA:HideSecureActionButtons');
    assert.ok(!advisorSource.includes('useBtn:SetScript("PreClick"'),
        'Secure action attributes must not be mutated from a click-time Lua handler.');
    assertContains(advisorSource, 'if IsInCombatLockdown() then');
}

function testVersionedSettings() {
    assertContains(tocSource, '## SavedVariablesPerCharacter: TravelAdvisor_Settings');
    assertContains(tocSource, 'TravelAdvisorSettings.lua');
    for (const token of [
        'VERSION = 1',
        'DEFAULTS',
        'function Settings:Load',
        'values.version = self.VERSION',
        'normalizeBoolean',
        'values.showAlternatives = normalizeBoolean',
        'values.showExplanations = normalizeBoolean',
        'function Settings:CyclePolicy',
        '_G.TravelAdvisor_Settings = values',
        'showExplanations',
    ]) {
        assertContains(settingsSource, token, `Versioned settings are missing ${token}.`);
    }
    assertContains(advisorSource, 'settings:CyclePolicy()');
    assertContains(advisorSource, 'settings:Set("showExplanations"');
    assertContains(planSource, 'User-defined sources remain out of scope under D-006');
}

function testPhaseDocumentation() {
    for (const id of ['TA-601', 'TA-602', 'TA-603', 'TA-604', 'TA-605']) {
        assert.ok(planSource.includes(`### [x] ${id}`), `${id} must be marked complete.`);
    }
    assertContains(validationSource, 'Phase 6 implementation checks');
    assertContains(checkSource, 'phase6.test.js');
}

testBestNowAndWaitPolicies();
testCanonicalExplanations();
testLocalizedNamesAndStableActions();
testCoalescedCombatSafeRefresh();
testVersionedSettings();
testPhaseDocumentation();
console.log('Phase 6 contract tests: PASS');

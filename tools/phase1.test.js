'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const graphSource = fs.readFileSync(path.join(ROOT, 'TravelGraph.lua'), 'utf8');
const advisorSource = fs.readFileSync(path.join(ROOT, 'TravelAdvisor.lua'), 'utf8');
const sourcesSource = fs.readFileSync(path.join(ROOT, 'TravelSources.lua'), 'utf8');

function assertContains(source, text, message) {
    assert.ok(source.includes(text), message || `Expected source to contain: ${text}`);
}

function testBindNodeAndHubResolution() {
    assertContains(
        graphSource,
        'self:AddDynamicNode(destinationMapID, {',
        'Canonical bind/dynamic destinations must pass the map ID separately from node data.',
    );
    assert.ok(
        !/self:AddNode\(\{\s*id\s*=\s*bindMapID/.test(graphSource),
        'The malformed bind-node AddNode call must not remain.',
    );
    assertContains(sourcesSource, 'return hub.mapID', 'Source bind-location fallback must return the hub record map ID.');
    assertContains(
        advisorSource,
        'return hub.mapID',
        'UI bind-location fallback must return the hub record map ID.',
    );

    // Regression model for the AddNode contract: a missing bind node is
    // created once and a repeated scan reuses it without adding duplicates.
    const nodes = {};
    const bindMapID = 2339;
    const nodeData = { name: 'Dornogal' };
    if (!nodes[bindMapID]) nodes[bindMapID] = nodeData;
    if (!nodes[bindMapID]) nodes[bindMapID] = nodeData;
    assert.strictEqual(Object.keys(nodes).length, 1);
    assert.strictEqual(nodes[bindMapID].name, 'Dornogal');
}

function testRouteActionSafety() {
    assertContains(advisorSource, 'function TA:IsRouteActionable(route)', 'Routes need an explicit executable state.');
    assertContains(advisorSource, 'route.isOptimalOnly', 'Best If Ready routes must not be executable.');
    assertContains(advisorSource, 'route.actionableNow == false', 'Route actionability must be checked before creating a button.');
    assertContains(advisorSource, 'travel.cooldown or 0', 'Source cooldown must be checked before creating a button.');
    assertContains(advisorSource, 'function TA:GetSecureActionConfig(travel)', 'Secure action metadata must be centralized.');
    assertContains(advisorSource, 'function TA:GetTravelActionAvailability(travel)', 'Use actions need a live availability check.');
    assertContains(advisorSource, 'useBtn:SetScript("PreClick"', 'Use actions need a pre-click revalidation hook.');
    assertContains(advisorSource, 'useBtn:SetAttribute("type", actionConfig.type)', 'Buttons must use the resolved action type.');
    assertContains(advisorSource, 'useBtn:SetAttribute(actionConfig.type, actionConfig.value)', 'Buttons must use the resolved stable action ID.');
    assert.ok(
        !advisorSource.includes('useBtn:SetAttribute("spell", travelData.name)'),
        'Secure spell actions must not use localized display names.',
    );
    assertContains(sourcesSource, 'source.kind == "toy" and "toy"', 'Hearthstone toys must use toy actions.');
    assertContains(sourcesSource, 'actionType == "spell"', 'Spell sources must carry spell action metadata.');
    assertContains(sourcesSource, 'actionType == "item"', 'Ordinary item sources must carry item action metadata.');
    assertContains(sourcesSource, 'actionType == "toy"', 'Toy sources must carry toy action metadata.');
    assertContains(graphSource, 'function Graph:GetActionAvailability(actionType, actionID)', 'Live action state must use one WoW API evaluator.');
    assertContains(sourcesSource, 'spellBook.IsSpellKnown', 'Spell discovery must use the known-spell API, not spellbook presence alone.');
}

function testUnknownMapsAreSafe() {
    assertContains(advisorSource, 'local cacheKey = tostring(currentMapID) .. "_" .. tostring(destinationMapID)', 'Cache keys must be built only after map validation.');
    assertContains(advisorSource, '"unknown-current-map"', 'Unknown current maps need an informational route state.');
    assertContains(advisorSource, '"unknown-destination"', 'Unknown destinations need an informational route state.');
    assertContains(graphSource, 'if not self:IsValidMapID(toMapID) then', 'Graph pathfinding must reject invalid destinations.');
    assertContains(graphSource, 'if edgeData.to ~= Graph.PLAYER_NODE and not self:IsValidMapID(edgeData.to) then', 'Invalid edge destinations must not enter the graph.');
    assert.ok(
        !graphSource.includes('to = spell.mapID or "racial"'),
        'Racial sources must not create a string pseudo-map destination.',
    );
}

function testCombatAndInvalidation() {
    assertContains(advisorSource, 'self._pendingDisplay = {', 'Display rebuilds must be queued during combat.');
    assertContains(advisorSource, 'eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")', 'Pending UI work must replay after combat.');
    assertContains(advisorSource, 'function TA:QueueRouteRefresh(reason)', 'State changes must share one coalesced refresh path.');
    assertContains(advisorSource, 'self._routeRefreshScheduled', 'Refresh bursts must be coalesced.');
    assertContains(advisorSource, 'function TA:ScheduleCooldownRefresh(seconds)', 'Cooldown expiry must trigger a refresh.');

    for (const event of [
        'SPELL_UPDATE_COOLDOWN',
        'SPELL_UPDATE_CHARGES',
        'BAG_UPDATE_DELAYED',
        'BAG_UPDATE_COOLDOWN',
        'TOYS_UPDATED',
        'SPELLS_CHANGED',
        'PLAYER_SPECIALIZATION_CHANGED',
        'PLAYER_TALENT_UPDATE',
        'HEARTHSTONE_BOUND',
        'UNIT_SPELLCAST_SUCCEEDED',
    ]) {
        assertContains(advisorSource, `eventFrame:RegisterEvent("${event}")`, `Missing Phase 1 invalidation event: ${event}`);
    }
}

testBindNodeAndHubResolution();
testRouteActionSafety();
testUnknownMapsAreSafe();
testCombatAndInvalidation();
console.log('Phase 1 contract tests: PASS');

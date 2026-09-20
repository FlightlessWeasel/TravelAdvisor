'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
    REASONS,
    adaptLegacy,
    evaluateFixtures,
    sourceFixtures,
} = require('./phase2-fixtures');

const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const sourcesSource = read('TravelSources.lua');
const graphSource = read('TravelGraph.lua');
const advisorSource = read('TravelAdvisor.lua');
const tocSource = read('TravelAdvisor.toc');

function activeLua(source) {
    return source
        .replace(/--\[\[[\s\S]*?\]\]/g, '')
        .replace(/--[^\r\n]*/g, '');
}

function testCanonicalLoadOrder() {
    const dataIndex = tocSource.indexOf('TravelData.lua');
    const sourcesIndex = tocSource.indexOf('TravelSources.lua');
    const graphIndex = tocSource.indexOf('TravelGraph.lua');
    assert.ok(dataIndex >= 0 && sourcesIndex > dataIndex && graphIndex > sourcesIndex);
}

function testCanonicalModuleSurface() {
    for (const name of [
        'BuildCatalog',
        'CreatePlayerState',
        'ResolveDestination',
        'Evaluate',
        'EvaluateAll',
        'FindByKey',
        'FindByAction',
        'sourceKey',
        'destinationResolved',
        'routeEligible',
        'confidence',
        'cooldownInfo',
        'requirements',
    ]) {
        assert.ok(sourcesSource.includes(name), `TravelSources.lua must expose ${name}`);
    }

    assert.ok(graphSource.includes('dynamicNodes'), 'Graph needs a separate dynamic-node store.');
    assert.ok(graphSource.includes('playerSourceStates'), 'Graph must retain excluded canonical states.');
    assert.ok(graphSource.includes('EvaluateAll'), 'Graph discovery must consume canonical evaluations.');
    assert.ok(graphSource.includes('GetPlayerSourceDiagnostics'), 'Graph must expose excluded-source diagnostics.');
    assert.ok(advisorSource.includes('sourceKey'), 'Legacy adapter must preserve stable source keys.');
    assert.ok(advisorSource.includes('GetSecureActionConfig(availability)'), 'Pre-click actions must use fresh canonical state.');
    assert.ok(sourcesSource.includes('false, true, false, false'), 'Item routing must use bag-only counts.');
    assert.ok(sourcesSource.includes('USABILITY_UNKNOWN'), 'Unknown usability must be non-actionable.');
    assert.ok(sourcesSource.includes('timing.wait') && sourcesSource.includes('timing.interaction')
        && sourcesSource.includes('timing.travel'), 'Timing metadata must be normalized.');
    assert.ok(sourcesSource.includes('resolveDynamic = false'), 'Catalog destinations must not capture player state.');
}

function testDuplicateScannersAreRetired() {
    const activeGraph = activeLua(graphSource);
    const activeAdvisor = activeLua(advisorSource);
    assert.ok(activeGraph.includes('function Graph:ScanCanonicalPlayerSources()'));
    assert.ok(activeGraph.includes('function Graph:ScanPlayerEdges()'));
    assert.ok(!activeGraph.includes('GetSpellAvailability'), 'Graph must not keep a second active spell evaluator.');
    assert.ok(!activeGraph.includes('GetItemAvailability'), 'Graph must not keep a second active item evaluator.');
    assert.ok(!activeAdvisor.includes('C_Spell.IsSpellUsable'), 'UI scanner must not query spell availability directly.');
    assert.ok(!activeAdvisor.includes('C_Item.GetItemCount'), 'UI scanner must not query item ownership directly.');
}

function testEvaluatorReasonsAndRouting() {
    const results = evaluateFixtures();
    const byKey = new Map(results.map((result) => [result.sourceKey, result]));
    const expected = {
        'spell:ready': REASONS.READY,
        'spell:cooldown': REASONS.ON_COOLDOWN,
        'spell:unknown': REASONS.NOT_KNOWN,
        'spell:charges': REASONS.NO_CHARGES,
        'item:missing': REASONS.NOT_OWNED,
        'item:quantity': REASONS.INSUFFICIENT_QUANTITY,
        'toy:missing': REASONS.NOT_COLLECTED,
        'random:dynamic': REASONS.DESTINATION_UNRESOLVED,
        'choice:dynamic': REASONS.DESTINATION_UNRESOLVED,
        'faction:wrong': REASONS.WRONG_FACTION,
        'profession:wrong': REASONS.WRONG_PROFESSION,
        'quest:missing': REASONS.MISSING_QUEST,
        'class:wrong': REASONS.WRONG_CLASS,
        'race:wrong': REASONS.WRONG_RACE,
        'spec:wrong': REASONS.WRONG_SPECIALIZATION,
        'reputation:missing': REASONS.MISSING_REPUTATION,
        'expansion:missing': REASONS.REQUIREMENTS_NOT_MET,
        'unsupported:source': REASONS.UNSUPPORTED_SOURCE,
        'location:wrong': REASONS.UNUSABLE_LOCATION,
        'disabled:source': REASONS.DISABLED,
        'unusable:source': REASONS.UNUSABLE,
        'item:bank-only': REASONS.NOT_OWNED,
        'requirement:unknown': REASONS.REQUIREMENTS_NOT_MET,
        'usability:unknown': REASONS.USABILITY_UNKNOWN,
    };

    for (const [sourceKey, reason] of Object.entries(expected)) {
        assert.strictEqual(byKey.get(sourceKey).reason, reason, sourceKey);
    }
    assert.strictEqual(byKey.get('spell:ready').routeEligible, true);
    assert.strictEqual(byKey.get('spell:cooldown').routeEligible, true);
    assert.strictEqual(byKey.get('spell:cooldown').actionableNow, false);
    assert.strictEqual(byKey.get('random:dynamic').destinationResolved, false);
    assert.strictEqual(byKey.get('random:dynamic').routeEligible, false);
    assert.strictEqual(byKey.get('bind:dynamic').destinationResolved, true);
    assert.strictEqual(byKey.get('bind:dynamic').destination.mapID, 2339);
    assert.strictEqual(byKey.get('bind:dynamic').actionableNow, true);
    assert.strictEqual(byKey.get('item:bank-only').routeEligible, false);
    assert.strictEqual(byKey.get('requirement:unknown').routeEligible, false);
    assert.strictEqual(byKey.get('usability:unknown').routeEligible, false);
}

function testStatePreservationAndLegacyParity() {
    const results = evaluateFixtures();
    assert.strictEqual(results.length, sourceFixtures.length, 'EvaluateAll must retain unavailable sources for diagnostics.');
    for (const result of results) {
        const legacy = adaptLegacy(result);
        assert.strictEqual(legacy.sourceKey, result.sourceKey);
        assert.strictEqual(legacy.reason, result.reason);
        assert.strictEqual(legacy.destinationResolved, result.destinationResolved);
        assert.strictEqual(legacy.routeEligible, result.routeEligible);
        assert.strictEqual(legacy.actionableNow, result.actionableNow);
    }
}

testCanonicalLoadOrder();
testCanonicalModuleSurface();
testDuplicateScannersAreRetired();
testEvaluatorReasonsAndRouting();
testStatePreservationAndLegacyParity();
console.log('Phase 2 contract tests: PASS');

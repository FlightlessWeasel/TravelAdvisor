'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
    buildExplicitGraph,
    findPath,
    choosePolicies,
    topologyNodes,
    topologyConnections,
    routeAlternatives,
    dungeonIdentity,
} = require('./phase4-fixtures');

const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const dataSource = read('TravelData.lua');
const graphSource = read('TravelGraph.lua');
const sourcesSource = read('TravelSources.lua');
const advisorSource = read('TravelAdvisor.lua');
const validatorSource = read('tools/validate.js');
const planSource = read('MASTER_PLAN.md');
const validationSource = read('VALIDATION.md');

function assertContains(source, text, message) {
    assert.ok(source.includes(text), message || `Expected source to contain: ${text}`);
}

function assertNotContains(source, text, message) {
    assert.ok(!source.includes(text), message || `Expected source not to contain: ${text}`);
}

function testExplicitTopologyAndIntermediateHubs() {
    const graph = buildExplicitGraph(topologyNodes, topologyConnections);
    const route = findPath(graph, 14, 2248);
    assert.ok(route, 'An explicit multi-hop topology route should be found.');
    assert.deepStrictEqual(route.path.map((edge) => edge.to), [84, 2339, 2248]);
    assert.deepStrictEqual(route.path.map((edge) => edge.mode), [
        'walking', 'portal-room', 'flightpath',
    ]);
    assert.strictEqual(route.path.some((edge) => edge.from === 14 && edge.to === 2248), false,
        'The route must not invent a direct same-continent edge.');

    const disconnected = findPath(graph, 14, 9999);
    assert.strictEqual(disconnected, null, 'Shared continent membership must not create a route.');
    assertContains(dataSource, 'TA.TravelData.ZoneConnections');
    assertContains(dataSource, 'TA.TravelData.MapIdentity');
    assertContains(graphSource, 'ZoneConnections');
    assertContains(graphSource, 'bidirectional == true');
    assertNotContains(graphSource, 'Add implicit flight edge to DESTINATION only');
    assertNotContains(graphSource, 'GetFlightDistance(currentNode, toMapID)');
}

function testTravelModeAndAccessMetadata() {
    for (const token of [
        'mode = mode',
        'travelMode = mode',
        'requirements = requirements',
        'confidence = edgeData.confidence',
        'accessState = accessState',
        'requiresDiscovery = edgeData.requiresDiscovery',
        'access-unknown',
        'function Graph:CheckRequirements',
        'function Graph:CheckEdgeAccess',
        'function Sources.EvaluateRequirements',
    ]) {
        assertContains(graphSource + sourcesSource + validatorSource, token,
            `Static edge access contract is missing ${token}.`);
    }
    for (const mode of ['walking', 'flightpath', 'portal-room']) {
        assertContains(dataSource + graphSource, mode,
            `Travel data or graph model is missing ${mode} topology.`);
    }
    assertContains(validatorSource, 'INVALID_TRAVEL_MODE');
}

function testPoliciesAndCooldownWait() {
    const policies = choosePolicies(routeAlternatives);
    assert.strictEqual(policies.bestNow.id, 'ready', 'Best Now must exclude cooldown routes.');
    assert.strictEqual(policies.bestIfReady.id, 'cooldown-fast',
        'Best If Ready should rank by travel time without wait.');
    assert.strictEqual(policies.bestAfterWait.id, 'cooldown-fast',
        'Best After Wait must include cooldown wait in elapsed time.');

    const waitAware = routeAlternatives.map((route) => ({
        ...route,
        cooldown: route.id === 'cooldown-fast' ? 100 : route.cooldown,
    }));
    assert.strictEqual(choosePolicies(waitAware).bestAfterWait.id, 'ready',
        'A slower ready route must beat a cooldown route when waiting makes it slower.');
    assertContains(graphSource, 'BEST_AFTER_WAIT');
    assertContains(graphSource, 'includeWait');
    assertContains(graphSource, 'FEWEST_TRANSITIONS');
    assertContains(graphSource, 'FEWEST_INTERACTIONS');
    assertContains(graphSource, 'FindClosestUsefulPath');
    assertContains(graphSource, 'usefulLanding');
    assertContains(advisorSource, 'Best After Wait');
    assertContains(advisorSource, 'BuildRouteCacheKey');
}

function testDungeonIdentitiesAndUnsupportedMaps() {
    assert.ok(dungeonIdentity.landingMapID > 0);
    assert.ok(dungeonIdentity.regionMapID > 0);
    assert.strictEqual(dungeonIdentity.targetKind, 'landing');
    assertContains(dataSource, 'DungeonIdentityPolicy');
    for (const field of ['instanceMapID', 'entranceMapID', 'landingMapID', 'regionMapID']) {
        assertContains(dataSource, field, `Dungeon identity is missing ${field}.`);
        assertContains(graphSource, field, `Graph does not carry ${field}.`);
    }
    assertContains(graphSource, 'unsupported-current-map');
    assertContains(graphSource, 'unsupported-destination');
    assertContains(graphSource, 'GetMapContext');
    assertContains(graphSource, 'ResolveRoutingMap');
    assertContains(validatorSource, 'DungeonIdentityPolicy');
}

function testPhaseDocumentation() {
    for (const id of ['TA-401', 'TA-402', 'TA-403', 'TA-404', 'TA-405', 'TA-406', 'TA-407']) {
        assert.ok(planSource.includes(`### [x] ${id}`), `${id} must be marked complete.`);
    }
    assertContains(validationSource, 'Phase 4 implementation checks');
}

testExplicitTopologyAndIntermediateHubs();
testTravelModeAndAccessMetadata();
testPoliciesAndCooldownWait();
testDungeonIdentitiesAndUnsupportedMaps();
testPhaseDocumentation();
console.log('Phase 4 contract tests: PASS');

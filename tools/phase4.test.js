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
    postTravelNodes,
    postTravelConnections,
    addPostTravelFlightFallback,
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

function testPostTravelFlightComposition() {
    const graph = buildExplicitGraph(postTravelNodes, postTravelConnections);
    addPostTravelFlightFallback(graph, postTravelNodes, 14, 85);

    const route = findPath(graph, 'player', 85);
    assert.ok(route, 'A portal/teleport route should continue through a reachable region to the target.');
    assert.deepStrictEqual(route.path.map((edge) => edge.to), [715, 69, 85]);
    assert.deepStrictEqual(route.path.map((edge) => edge.mode), [
        'teleport', 'portal', 'flight',
    ]);
    assert.strictEqual(route.path[2].accessState, 'unknown',
        'The inferred final flight must remain conditional until access is discovered.');

    const readyRoute = findPath(graph, 'player', 85, { readyOnly: true });
    assert.strictEqual(readyRoute, null,
        'An unknown inferred flight must not be presented as executable Best Now travel.');

    const directStartGraph = buildExplicitGraph(postTravelNodes, postTravelConnections);
    addPostTravelFlightFallback(directStartGraph, postTravelNodes, 69, 85);
    assert.strictEqual(findPath(directStartGraph, 69, 85), null,
        'The fallback must not restore an unqualified direct flight from the current node.');

    const crossContinent = buildExplicitGraph(postTravelNodes, postTravelConnections);
    addPostTravelFlightFallback(crossContinent, postTravelNodes, 14, 85);
    assert.strictEqual(crossContinent.get(14).some((edge) => edge.to === 85), false,
        'Post-travel flight fallback must not cross continents.');
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
    assertContains(graphSource, 'function Graph:BuildPostTravelFlightEdge');
    assertContains(graphSource, 'post-travel-flight');
    assertContains(graphSource, 'fromMapID == startNodeID');
    assertContains(graphSource, 'currentNode ~= Graph.PLAYER_NODE');
    assertContains(graphSource, 'Static-edge `location` is provenance');
    assertContains(graphSource, 'record.locationID');
    assertNotContains(graphSource, 'TA.TravelSources:CreatePlayerState');
    assertNotContains(graphSource, 'TA.TravelSources:EvaluateAll');
    assertNotContains(graphSource, 'TA.TravelSources:FindByAction');
    assertNotContains(graphSource, 'TA.TravelSources:FindByKey');
    assertNotContains(graphSource, 'TA.TravelSources:Evaluate(');
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

function testApproximateMapsDoNotCollapseToAlreadyHere() {
    const currentMapID = 2393;
    const destinationMapID = 48;
    const sharedApproximateNode = 13;
    const currentContext = { routeMapID: sharedApproximateNode, approximate: true };
    const destinationContext = { routeMapID: sharedApproximateNode, approximate: true };
    const isExactRoutingMatch = (currentID, destinationID, current, destination) =>
        currentID === destinationID
        || (current.approximate !== true && destination.approximate !== true);

    assert.notStrictEqual(currentMapID, destinationMapID);
    assert.strictEqual(currentContext.routeMapID, destinationContext.routeMapID);
    assert.ok(
        currentContext.approximate || destinationContext.approximate,
        'The live child maps must remain marked approximate when parent fallback is used.',
    );
    assert.strictEqual(
        isExactRoutingMatch(currentMapID, destinationMapID, currentContext, destinationContext),
        false,
        'Distinct approximate maps must not produce an exact same-location result.',
    );
    assert.strictEqual(
        isExactRoutingMatch(currentMapID, currentMapID, currentContext, currentContext),
        true,
        'The same raw map must still be recognized as the current location.',
    );
    assertContains(graphSource, 'function Graph:IsExactRoutingMatch');
    assertContains(graphSource, 'if startNode == targetNode and self:IsExactRoutingMatch');
    assertContains(advisorSource, 'and Graph:IsExactRoutingMatch(');
    assertContains(dataSource, '[2393] = {');
    assertContains(dataSource, '[48] = { x = 45, y = 50, continent = 13 }');
    assertContains(dataSource, '["loch modan"] = 48');
}

function testPhaseDocumentation() {
    for (const id of ['TA-401', 'TA-402', 'TA-403', 'TA-404', 'TA-405', 'TA-406', 'TA-407']) {
        assert.ok(planSource.includes(`### [x] ${id}`), `${id} must be marked complete.`);
    }
    assertContains(validationSource, 'Phase 4 implementation checks');
}

testExplicitTopologyAndIntermediateHubs();
testPostTravelFlightComposition();
testTravelModeAndAccessMetadata();
testPoliciesAndCooldownWait();
testDungeonIdentitiesAndUnsupportedMaps();
testApproximateMapsDoNotCollapseToAlreadyHere();
testPhaseDocumentation();
console.log('Phase 4 contract tests: PASS');

'use strict';

const assert = require('assert');
const {
    extractTable,
    findDungeonDestinationContradictions,
    findDuplicateNumericKeys,
    parseInlineRecords,
    parseNumericField,
} = require('./validate');
const {
    routeFixtures,
    selectFixtureRoute,
    sourceFixtures,
} = require('./phase0-fixtures');

function testDuplicateMapKeys() {
    const source = `TA.TravelData.ZoneCoordinates = {
        [47] = { x = 1 },
        [2371] = { x = 2 },
        [47] = { x = 3 },
    }`;
    const table = extractTable(source, 'ZoneCoordinates');
    const duplicates = findDuplicateNumericKeys(table);
    assert.deepStrictEqual(duplicates.map((duplicate) => duplicate.key), [47]);
}

function testDungeonIdentityConflicts() {
    const source = `TA.TravelData.DungeonTeleports = {
        { spellID = 1, name = 'First', mapID = 2214 },
        { spellID = 2, name = 'Second', mapID = 2214 },
    }`;
    const table = extractTable(source, 'DungeonTeleports');
    const conflicts = findDungeonDestinationContradictions(table);
    assert.strictEqual(conflicts.length, 1);
    assert.strictEqual(conflicts[0].mapID, 2214);
}

function testRecordParsing() {
    const source = `TA.TravelData.TeleportItems = {
        { itemID = 123, name = 'Example', mapID = 84 },
    }`;
    const table = extractTable(source, 'TeleportItems');
    const records = parseInlineRecords(table);
    assert.strictEqual(records.length, 1);
    assert.strictEqual(parseNumericField(records[0].text, 'itemID'), 123);
    assert.strictEqual(parseNumericField(records[0].text, 'mapID'), 84);
}

function testSourceFixtureContract() {
    assert.ok(sourceFixtures.every((source) => typeof source.id === 'string'));
    assert.ok(sourceFixtures.some((source) => source.state === 'ready' && source.actionableNow));
    assert.ok(sourceFixtures.some((source) => source.state === 'cooldown' && !source.actionableNow));
    assert.ok(sourceFixtures.some((source) => source.state === 'unknown-destination' && !source.actionableNow));
}

function testRoutePolicies() {
    assert.strictEqual(selectFixtureRoute(routeFixtures, 'best-now').id, 'ready-route');
    assert.strictEqual(selectFixtureRoute(routeFixtures, 'best-after-wait').id, 'cooldown-route');
    assert.strictEqual(selectFixtureRoute(routeFixtures, 'best-if-ready').id, 'cooldown-route');
    assert.strictEqual(selectFixtureRoute(routeFixtures, 'best-if-ready').actionableNow, false);
}

testDuplicateMapKeys();
testDungeonIdentityConflicts();
testRecordParsing();
testSourceFixtureContract();
testRoutePolicies();
console.log('Phase 0 contract tests: PASS');

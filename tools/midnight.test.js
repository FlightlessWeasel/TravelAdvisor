'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const dataSource = read('TravelData.lua');
const graphSource = read('TravelGraph.lua');
const advisorSource = read('TravelAdvisor.lua');

function assertContains(source, text, message) {
    assert.ok(source.includes(text), message || `Expected source to contain: ${text}`);
}

const identityStart = dataSource.indexOf('TA.TravelData.MapIdentity = {');
const identityEnd = dataSource.indexOf('\n}\n\n--', identityStart);
assert.ok(identityStart >= 0 && identityEnd > identityStart, 'MapIdentity must be present.');
const identitySource = dataSource.slice(identityStart, identityEnd);

assert.ok(!identitySource.includes('[2393] = {\n        alias = true'),
    'Midnight Silvermoon must not be represented as an alias.');
assert.ok(!identitySource.includes('routeMapID = 110'),
    'Midnight Silvermoon must not route through legacy Silvermoon.');
for (const token of [
    '[2393] = {',
    '[2395] = {',
    '[2437] = {',
    '[2413] = {',
    '[2444] = {',
    '[2393] = { x =',
    '[2395] = { x =',
    '[2437] = { x =',
    '[2413] = { x =',
    '[2444] = { x =',
    '["silvermoon city"] = 2393',
    '["silvermoon city (legacy)"] = 110',
    '["eversong woods"] = 2395',
    '["zul\'aman"] = 2437',
    '["harandar"] = 2413',
    '["voidstorm"] = 2444',
    'name = "Silvermoon City (Midnight)"',
    'name = "Silvermoon City (Legacy)"',
    'name = "Eversong Woods (Midnight)"',
    'name = "Zul\'Aman (Midnight)"',
    'name = "Harandar (Midnight)"',
    'name = "Voidstorm (Midnight)"',
]) {
    assertContains(dataSource, token, `Midnight catalog is missing ${token}.`);
}

assertContains(graphSource, 'function Graph:IsExactRoutingMatch',
    'The exact routing safety check must remain present.');
assertContains(graphSource, 'if currentMapID == destinationMapID then return true end',
    'Exact routing must still require equal raw map IDs.');
assertContains(graphSource, 'currentContext.approximate ~= true',
    'Parent fallback must not become an exact routing match.');
assertContains(dataSource, '[2393] = {\n        { to = 2437, type = "flight", mode = "flight"',
    'Midnight Silvermoon must have an explicit flight connection to Zul\'Aman.');
for (const token of [
    'mapID = 2393', 'mapID = 2413', 'mapID = 2444',
    '{ name = "Harandar", mapID = 2413',
    '{ name = "Voidstorm", mapID = 2444',
    '{ name = "Silvermoon City", mapID = 2393',
]) {
    assertContains(dataSource, token, `Midnight portal topology is missing ${token}.`);
}
assertContains(graphSource, 'if fromID ~= mapID',
    'Zone debug must not count the target zone as flying to itself.');
assertContains(graphSource, 'edge.to == mapID',
    'Zone debug must include explicit flight edges when reporting reachable zones.');
assertContains(advisorSource, 'route.status=calculated-no-route',
    'Troubleshooting reports must distinguish calculated no-route results.');
console.log('Midnight catalog regression: PASS');

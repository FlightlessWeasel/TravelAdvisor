'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
    collectGraphNodeIDs,
    extractTable,
    findDungeonDestinationContradictions,
    findDuplicateNumericKeys,
    parseInlineRecords,
    validate,
    validateDataGovernance,
    validateSourceTables,
    validateStaticEdgeMetadata,
} = require('./validate');

const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const dataSource = read('TravelData.lua');
const graphSource = read('TravelGraph.lua');
const planSource = read('MASTER_PLAN.md');
const validationSource = read('VALIDATION.md');
const checkSource = read('tools/check.js');

function assertContains(source, text, message) {
    assert.ok(source.includes(text), message || `Expected source to contain: ${text}`);
}

function testValidatorPassesCorrectedCatalog() {
    const result = validate();
    assert.deepStrictEqual(result.issues, [], 'The corrected travel catalog must pass validation.');
    assert.strictEqual(result.stats.errorCount, 0);
    assert.ok(result.stats.graphNodeCount > 0);
}

function testValidatorCoversMultilineSourcesAndKnownContracts() {
    const dungeonTable = extractTable(dataSource, 'DungeonTeleports');
    const racialTable = extractTable(dataSource, 'RacialTeleports');
    assert.ok(dungeonTable && parseInlineRecords(dungeonTable).length > 20,
        'The validator must parse multiline dungeon records.');
    assert.ok(racialTable && parseInlineRecords(racialTable).length >= 3,
        'The validator must parse multiline racial source records.');

    const nodeIDs = collectGraphNodeIDs(dataSource);
    assert.deepStrictEqual(validateSourceTables(dataSource, nodeIDs), []);
    assert.deepStrictEqual(validateStaticEdgeMetadata(dataSource), []);
    assert.deepStrictEqual(validateDataGovernance(dataSource), []);
}

function testDuplicateAndIdentityCorrections() {
    const coordinates = extractTable(dataSource, 'ZoneCoordinates');
    assert.ok(coordinates);
    assert.deepStrictEqual(findDuplicateNumericKeys(coordinates), []);
    assertContains(dataSource, 'name = "Boots of the Bay"', 'Boots of the Bay must remain cataloged.');
    assertContains(dataSource, 'name = "Boots of the Bay", destination = "Booty Bay", mapID = 210',
        'Boots of the Bay must target the Booty Bay region node.');
    assertContains(dataSource, 'mapID = 0,\n        zone = "The Ringing Deeps", landingMapID = 2214',
        'Dungeon records must separate landing identity from the legacy instance field.');
    assertContains(dataSource, 'name = "Teleport: Earthen Depths", destination = "Earthen Depths", mapID = 0',
        'Earthen Depths must not route through the Emerald Dream map.');
    assertContains(dataSource, 'destinationResolver = "unverified-landing"',
        'Unverified dungeon landings must remain explicit and non-routable.');
    assertContains(dataSource, 'spellID = 132627, name = "Portal: Vale of Eternal Blossoms (Horde)"',
        'Faction variants must not reuse the Alliance portal stable ID.');
}

function testNegativeIntegrityFixtures() {
    const malformedDungeonSource = [
        'TA.TravelData.DungeonTeleports = {',
        '    { spellID = 1, name = "Dungeon A", mapID = 100, zone = "Zone A" },',
        '    { spellID = 2, name = "Dungeon B", mapID = 100, zone = "Zone B" },',
        '}',
    ].join('\n');
    const malformedDungeon = extractTable(malformedDungeonSource, 'DungeonTeleports');
    assert.strictEqual(findDungeonDestinationContradictions(malformedDungeon).length, 1,
        'Contradictory dungeon identities must remain detectable without the policy declaration.');

    const malformedPortalSource = dataSource.replace(
        '{ name = "Dornogal", mapID = 2339, inst = 0',
        '{ name = "Dornogal", mapID = 0, inst = 0',
    );
    const portalIssues = validateStaticEdgeMetadata(malformedPortalSource);
    assert.ok(portalIssues.some((issue) => issue.code === 'MISSING_NODE_MAP_ID'),
        'Malformed portal destinations must produce a node-map validation finding.');
    for (const token of [
        'location = connection.location',
        'availability = connection.availability',
        'actionability = connection.actionability',
        'provenance = connection.provenance',
        'executable = connection.executable',
    ]) {
        assertContains(graphSource, token, `Static graph edges must preserve ${token}.`);
    }

    const malformedRequirementCatalog = dataSource.replace(
        'quest = "ZoneUnlockQuests"',
        'quest = "NoSuchTable"',
    );
    assert.ok(validateDataGovernance(malformedRequirementCatalog).some(
        (issue) => issue.code === 'UNDEFINED_REQUIREMENT_REFERENCE',
    ), 'Undefined requirement references must be rejected.');
}

function testGovernanceAndStaticAccessMetadata() {
    for (const token of [
        'TA.TravelData.Metadata',
        'TA.TravelData.SourceMetadata',
        'TA.TravelData.DestinationResolvers',
        'TA.TravelData.RequirementCatalog',
        'TA.TravelData.StaticEdgePolicy',
        'TA.TravelData.UserSourcePolicy',
        'applyStaticEdgeMetadata(connection',
        'applyStaticEdgeMetadata(portal',
        'accessState',
        'availability',
        'provenance',
    ]) {
        assertContains(dataSource, token, `Phase 5 data governance is missing ${token}.`);
    }
    assertContains(dataSource, 'status = "informational-only"',
        'Transport coverage must not be presented as universally executable.');
    assertContains(dataSource, 'extensionPoint = "TravelData.UserSources"',
        'The out-of-scope user-source extension point must be documented.');
}

function testDocumentationAndValidationCommand() {
    for (const id of ['TA-501', 'TA-502', 'TA-503', 'TA-504', 'TA-505', 'TA-506']) {
        assert.ok(planSource.includes(`### [x] ${id}`), `${id} must be marked complete.`);
    }
    assertContains(validationSource, 'Phase 5 implementation checks');
    assertContains(validationSource, 'Post-patch');
    assertContains(checkSource, "phase5.test.js");
}

testValidatorPassesCorrectedCatalog();
testValidatorCoversMultilineSourcesAndKnownContracts();
testDuplicateAndIdentityCorrections();
testNegativeIntegrityFixtures();
testGovernanceAndStaticAccessMetadata();
testDocumentationAndValidationCommand();
console.log('Phase 5 contract tests: PASS');

'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
    REASONS,
    evaluate,
    resolveDestination,
    sourceFixtures,
} = require('./phase3-fixtures');

const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const sourcesSource = read('TravelSources.lua');
const dataSource = read('TravelData.lua');
const graphSource = read('TravelGraph.lua');
const advisorSource = read('TravelAdvisor.lua');
const planSource = read('MASTER_PLAN.md');
const validationSource = read('VALIDATION.md');

function assertContains(source, text, message) {
    assert.ok(source.includes(text), message || `Expected source to contain: ${text}`);
}

function assertPattern(source, pattern, message) {
    assert.ok(pattern.test(source), message || `Expected source to match: ${pattern}`);
}

function testSpellDiscoveryAndOverrides() {
    for (const token of [
        'spellBook.IsSpellKnown',
        'spellAPI and type(spellAPI.GetOverrideSpell)',
        'spellAPI and spellAPI.GetSpellCooldown',
        'spellAPI and spellAPI.GetSpellCharges',
        'Sources.Discover',
    ]) {
        assertContains(sourcesSource, token, `Spell discovery is missing ${token}.`);
    }

    const ready = evaluate(sourceFixtures.spellReady, {
        known: true,
        usable: true,
    });
    assert.strictEqual(ready.reason, REASONS.READY);
    assert.strictEqual(ready.actionableNow, true);

    const unusable = evaluate(sourceFixtures.spellUnusable, {
        known: true,
        usable: false,
    });
    assert.strictEqual(unusable.reason, REASONS.UNUSABLE);
    assert.strictEqual(unusable.actionableNow, false);

    const unknown = evaluate(sourceFixtures.spellReady, {
        known: false,
        usable: true,
    });
    assert.strictEqual(unknown.reason, REASONS.NOT_KNOWN);
}

function testItemToyDiscoveryAndActionSeparation() {
    for (const token of [
        'itemAPI and type(itemAPI.GetItemCount)',
        'containerAPI and containerAPI.GetItemCooldown',
        'itemAPI and itemAPI.GetItemCooldown',
        'api.PlayerHasToy',
        'actionType == "toy"',
        'actionType == "item"',
    ]) {
        assertContains(sourcesSource, token, `Item/toy discovery is missing ${token}.`);
    }

    const item = evaluate(sourceFixtures.item, { quantity: 2, usable: true });
    const toy = evaluate(sourceFixtures.toy, { collected: true, usable: true });
    assert.strictEqual(item.reason, REASONS.READY);
    assert.strictEqual(toy.reason, REASONS.READY);
    assert.strictEqual(sourceFixtures.item.actionType, 'item');
    assert.strictEqual(sourceFixtures.toy.actionType, 'toy');
    assert.notStrictEqual(sourceFixtures.item.actionType, sourceFixtures.toy.actionType,
        'Item and toy secure actions must remain distinct.');
    assertContains(advisorSource, 'travel.interaction == "player-choice"');
}

function testProfessionAndEngineeringRequirements() {
    for (const token of [
        'GetProfessions',
        'GetProfessionInfo',
        'professionDetails',
        'INSUFFICIENT_PROFESSION_SKILL',
        'WRONG_PROFESSION',
    ]) {
        assertContains(sourcesSource, token, `Profession discovery is missing ${token}.`);
    }

    const qualified = evaluate(sourceFixtures.profession, {
        professions: ['Engineering'],
        professionSkills: { engineering: 100 },
        quantity: 1,
        usable: true,
    });
    assert.strictEqual(qualified.reason, REASONS.READY);
    assert.strictEqual(qualified.routeEligible, true);

    const lowSkill = evaluate(sourceFixtures.profession, {
        professions: ['Engineering'],
        professionSkills: { engineering: 50 },
        quantity: 1,
        usable: true,
    });
    assert.strictEqual(lowSkill.reason, REASONS.INSUFFICIENT_PROFESSION_SKILL);
    assert.strictEqual(lowSkill.routeEligible, false);

    const wrongProfession = evaluate(sourceFixtures.profession, {
        professions: ['Alchemy'],
        quantity: 1,
        usable: true,
    });
    assert.strictEqual(wrongProfession.reason, REASONS.WRONG_PROFESSION);
}

function testPortalAndChoiceSemantics() {
    assertContains(dataSource, 'SourceSemantics');
    assertContains(dataSource, 'external-player');
    assertContains(dataSource, 'MoleMachineDestinations');
    assertContains(dataSource, 'destinationOptions');
    assertContains(sourcesSource, 'EXTERNAL_INTERACTION');
    assertContains(sourcesSource, 'and result.interaction ~= "player-choice"');
    assertContains(graphSource, 'externalInteraction');
    assertContains(advisorSource, 'travel.externalInteraction == true');

    const portal = evaluate(sourceFixtures.portal, { known: true, usable: true });
    assert.strictEqual(portal.reason, REASONS.EXTERNAL_INTERACTION);
    assert.strictEqual(portal.routeEligible, true);
    assert.strictEqual(portal.actionableNow, false);

    const unresolvedChoice = evaluate(sourceFixtures.moleMachine, {
        known: true,
        usable: true,
    });
    assert.strictEqual(unresolvedChoice.reason, REASONS.DESTINATION_UNRESOLVED);
    assert.strictEqual(unresolvedChoice.routeEligible, false);
    assert.strictEqual(sourceFixtures.moleMachine.destination.options.length, 2);

    const selectedChoice = resolveDestination(sourceFixtures.moleMachine, { choiceMapID: 87 });
    assert.strictEqual(selectedChoice.resolved, true);
    assert.strictEqual(selectedChoice.mapID, 87);
}

function testCanonicalDataRecords() {
    assertPattern(dataSource, /TA\.TravelData\.TeleportItems\s*=\s*\{[\s\S]*?itemID\s*=\s*18984/,
        'Engineering teleport records must be present in the canonical data.');
    assertPattern(dataSource, /itemID\s*=\s*18984[\s\S]*?profession\s*=\s*"Engineering"/,
        'Engineering teleport records must carry their profession requirement.');
    assertPattern(dataSource, /name\s*=\s*"Make Camp"[\s\S]*?routeEligible\s*=\s*false/,
        'Make Camp must remain an explicit setup-only source.');
    assertPattern(dataSource, /name\s*=\s*"Mole Machine"[\s\S]*?destinationOptions\s*=\s*"MoleMachineDestinations"/,
        'Mole Machine must retain its choice table reference.');

    const optionsStart = dataSource.indexOf('TA.TravelData.MoleMachineDestinations');
    const optionsEnd = dataSource.indexOf('TA.TravelData.ZoneConnections', optionsStart);
    const optionsBlock = dataSource.slice(optionsStart, optionsEnd);
    const optionCount = (optionsBlock.match(/mapID\s*=\s*[1-9]\d*/g) || []).length;
    assert.ok(optionCount >= 10, 'Mole Machine must enumerate its supported destinations.');
}

function testDynamicMapZeroSources() {
    const bind = evaluate(sourceFixtures.bind, {
        quantity: 1,
        usable: true,
        bindMapID: 2339,
    });
    assert.strictEqual(bind.destination.resolved, true);
    assert.strictEqual(bind.destination.mapID, 2339);
    assert.strictEqual(bind.routeEligible, true);

    const unresolvedBind = evaluate(sourceFixtures.bind, { quantity: 1, usable: true });
    assert.strictEqual(unresolvedBind.reason, REASONS.DESTINATION_UNRESOLVED);
    assert.strictEqual(unresolvedBind.routeEligible, false);

    const setup = evaluate(sourceFixtures.setup, { known: true, usable: true });
    assert.strictEqual(setup.reason, REASONS.SETUP_ONLY);
    assert.strictEqual(setup.routeEligible, false);
    assertContains(graphSource, 'destination.resolved ~= true');
}

function testCoverageDocumentationAndTests() {
    assertContains(sourcesSource, 'SOURCE_COVERAGE');
    assertContains(sourcesSource, 'boats-zeppelins-ferries-taxis');
    assertContains(sourcesSource, 'informational-only');
    for (const id of ['TA-301', 'TA-302', 'TA-303', 'TA-304', 'TA-305', 'TA-306', 'TA-307']) {
        assert.ok(planSource.includes(`### [x] ${id}`), `${id} must be marked complete.`);
    }
    assertContains(validationSource, 'Phase 3 implementation checks');
}

testSpellDiscoveryAndOverrides();
testItemToyDiscoveryAndActionSeparation();
testProfessionAndEngineeringRequirements();
testPortalAndChoiceSemantics();
testCanonicalDataRecords();
testDynamicMapZeroSources();
testCoverageDocumentationAndTests();
console.log('Phase 3 contract tests: PASS');

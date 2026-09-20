'use strict';

const REASONS = Object.freeze({
    READY: 'ready',
    NOT_KNOWN: 'not-known',
    NOT_OWNED: 'not-owned',
    NOT_COLLECTED: 'not-collected',
    UNUSABLE: 'unusable',
    WRONG_PROFESSION: 'wrong-profession',
    INSUFFICIENT_PROFESSION_SKILL: 'insufficient-profession-skill',
    DESTINATION_UNRESOLVED: 'destination-unresolved',
    EXTERNAL_INTERACTION: 'external-interaction',
    SETUP_ONLY: 'setup-only',
});

function clone(value) {
    return value && typeof value === 'object' ? JSON.parse(JSON.stringify(value)) : value;
}

function professionKey(value) {
    return String(value || '').toLowerCase().replace(/[\s'`-]/g, '');
}

function hasProfession(state, required) {
    const professions = state.professions;
    if (!professions) return null;
    return professions.some((value) => professionKey(value) === professionKey(required));
}

function resolveDestination(source, state) {
    const destination = clone(source.destination) || {};
    if (destination.kind === 'random' || destination.kind === 'unknown') {
        return { ...destination, mapID: undefined, resolved: false };
    }
    if (destination.kind === 'bind') {
        const mapID = state.bindMapID;
        return { ...destination, mapID, resolved: Number.isInteger(mapID) && mapID > 0 };
    }
    if (destination.kind === 'previous') {
        const mapID = state.previousMapID;
        return { ...destination, mapID, resolved: Number.isInteger(mapID) && mapID > 0 };
    }
    if (destination.kind === 'choice') {
        const mapID = state.choiceMapID;
        return {
            ...destination,
            mapID,
            resolved: Number.isInteger(mapID) && mapID > 0,
        };
    }
    return {
        ...destination,
        resolved: Number.isInteger(destination.mapID) && destination.mapID > 0,
    };
}

function evaluate(source, state) {
    const destination = resolveDestination(source, state);
    let reason = source.routeEligible === false ? REASONS.SETUP_ONLY : null;

    if (!reason && source.profession) {
        const hasRequiredProfession = hasProfession(state, source.profession);
        if (hasRequiredProfession == null) reason = REASONS.WRONG_PROFESSION;
        else if (!hasRequiredProfession) reason = REASONS.WRONG_PROFESSION;
        else if (source.professionSkill) {
            const skill = state.professionSkills
                && state.professionSkills[professionKey(source.profession)];
            if (skill == null || skill < source.professionSkill) {
                reason = skill == null
                    ? REASONS.WRONG_PROFESSION
                    : REASONS.INSUFFICIENT_PROFESSION_SKILL;
            }
        }
    }

    if (!reason && source.actionType === 'spell' && state.known !== true) reason = REASONS.NOT_KNOWN;
    if (!reason && source.actionType === 'item' && state.quantity <= 0) reason = REASONS.NOT_OWNED;
    if (!reason && source.actionType === 'toy' && state.collected !== true) reason = REASONS.NOT_COLLECTED;
    if (!reason && state.usable === false) reason = REASONS.UNUSABLE;
    if (!reason && !destination.resolved) reason = REASONS.DESTINATION_UNRESOLVED;
    if (!reason && (source.externalInteraction || source.interaction === 'player-choice')) {
        reason = REASONS.EXTERNAL_INTERACTION;
    }

    const actionableNow = (reason || REASONS.READY) === REASONS.READY
        && destination.resolved
        && source.actionableByPlayer !== false;
    const routeEligible = destination.resolved
        && source.routeEligible !== false
        && [REASONS.READY, REASONS.EXTERNAL_INTERACTION].includes(reason || REASONS.READY);
    return {
        destination,
        reason: reason || REASONS.READY,
        routeEligible,
        actionableNow,
    };
}

const sourceFixtures = {
    spellReady: {
        actionType: 'spell', destination: { kind: 'fixed', mapID: 84 },
    },
    spellUnusable: {
        actionType: 'spell', destination: { kind: 'fixed', mapID: 84 },
    },
    item: {
        actionType: 'item', destination: { kind: 'fixed', mapID: 84 },
    },
    toy: {
        actionType: 'toy', destination: { kind: 'fixed', mapID: 627 },
    },
    profession: {
        actionType: 'item', profession: 'Engineering', professionSkill: 100,
        destination: { kind: 'fixed', mapID: 83 },
    },
    portal: {
        actionType: 'spell', externalInteraction: true, actionableByPlayer: false,
        interaction: 'external-player', destination: { kind: 'fixed', mapID: 84 },
    },
    moleMachine: {
        actionType: 'spell', actionableByPlayer: false, interaction: 'player-choice',
        destination: {
            kind: 'choice',
            options: [
                { name: 'Stormwind', mapID: 84 },
                { name: 'Ironforge', mapID: 87 },
            ],
        },
    },
    bind: {
        actionType: 'item', destination: { kind: 'bind', mapID: 0 },
    },
    setup: {
        actionType: 'spell', routeEligible: false, actionableByPlayer: false,
        destination: { kind: 'unknown', mapID: 0 },
    },
};

module.exports = {
    REASONS,
    evaluate,
    resolveDestination,
    sourceFixtures,
};

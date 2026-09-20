'use strict';

const REASONS = Object.freeze({
    READY: 'ready',
    NOT_KNOWN: 'not-known',
    NOT_OWNED: 'not-owned',
    NOT_COLLECTED: 'not-collected',
    INSUFFICIENT_QUANTITY: 'insufficient-quantity',
    ON_COOLDOWN: 'on-cooldown',
    NO_CHARGES: 'no-charges',
    DISABLED: 'disabled',
    UNUSABLE: 'unusable',
    REQUIREMENTS_NOT_MET: 'requirements-not-met',
    WRONG_CLASS: 'wrong-class',
    WRONG_RACE: 'wrong-race',
    WRONG_SPECIALIZATION: 'wrong-specialization',
    WRONG_FACTION: 'wrong-faction',
    WRONG_PROFESSION: 'wrong-profession',
    MISSING_QUEST: 'missing-quest',
    MISSING_REPUTATION: 'missing-reputation',
    UNUSABLE_LOCATION: 'unusable-location',
    DESTINATION_UNRESOLVED: 'destination-unresolved',
    UNSUPPORTED_SOURCE: 'unsupported-source',
    API_UNAVAILABLE: 'api-unavailable',
    USABILITY_UNKNOWN: 'usability-unknown',
});

function clone(value) {
    return value && typeof value === 'object' ? JSON.parse(JSON.stringify(value)) : value;
}

function resolveDestination(source, state) {
    const destination = clone(source.destination);
    if (destination.kind === 'bind') {
        const mapID = state.bindMapID;
        return {
            ...destination,
            mapID,
            resolved: Number.isInteger(mapID) && mapID > 0,
        };
    }
    if (destination.kind === 'previous') {
        const mapID = state.previousMapID;
        return {
            ...destination,
            mapID,
            resolved: Number.isInteger(mapID) && mapID > 0,
        };
    }
    if (destination.kind === 'choice') {
        const mapID = state.choiceMapID;
        return {
            ...destination,
            mapID,
            resolved: Number.isInteger(mapID) && mapID > 0,
        };
    }
    if (destination.kind === 'random' || destination.kind === 'nearby' || destination.kind === 'unknown') {
        return { ...destination, resolved: false, mapID: undefined };
    }
    return {
        ...destination,
        resolved: Number.isInteger(destination.mapID) && destination.mapID > 0,
    };
}

function requirementReason(source, state) {
    const requirements = source.requirements || {};
    if (requirements.faction) {
        if (state.faction == null) return REASONS.REQUIREMENTS_NOT_MET;
        if (requirements.faction !== 'Both' && requirements.faction !== state.faction) {
            return REASONS.WRONG_FACTION;
        }
    }
    if (requirements.class) {
        if (state.class == null) return REASONS.REQUIREMENTS_NOT_MET;
        if (requirements.class !== state.class) return REASONS.WRONG_CLASS;
    }
    if (requirements.race) {
        if (state.race == null) return REASONS.REQUIREMENTS_NOT_MET;
        if (requirements.race !== state.race) return REASONS.WRONG_RACE;
    }
    if (requirements.specialization) {
        if (state.specialization == null) return REASONS.REQUIREMENTS_NOT_MET;
        if (requirements.specialization !== state.specialization) return REASONS.WRONG_SPECIALIZATION;
    }
    if (requirements.profession) {
        if (state.professions == null) return REASONS.REQUIREMENTS_NOT_MET;
        if (!state.professions.includes(requirements.profession)) return REASONS.WRONG_PROFESSION;
    }
    if (requirements.quest) {
        if (state.completedQuests == null) return REASONS.REQUIREMENTS_NOT_MET;
        if (!state.completedQuests.includes(requirements.quest)) return REASONS.MISSING_QUEST;
    }
    if (requirements.reputation) {
        if (state.reputation == null || state.reputation[requirements.reputation] == null) {
            return REASONS.REQUIREMENTS_NOT_MET;
        }
        if (state.reputation[requirements.reputation] < (requirements.minimum || 0)) {
            return REASONS.MISSING_REPUTATION;
        }
    }
    if (requirements.location) {
        if (state.currentMapID == null) return REASONS.REQUIREMENTS_NOT_MET;
        if (requirements.location !== state.currentMapID) return REASONS.UNUSABLE_LOCATION;
    }
    if (requirements.expansion) {
        if (state.expansions == null) return REASONS.REQUIREMENTS_NOT_MET;
        if (!state.expansions.includes(requirements.expansion)) return REASONS.REQUIREMENTS_NOT_MET;
    }
    return null;
}

function evaluateSource(source, state) {
    const destination = resolveDestination(source, state);
    let reason = source.enabled === false ? REASONS.DISABLED : requirementReason(source, state);
    const result = {
        source,
        sourceKey: source.sourceKey,
        destination,
        destinationResolved: destination.resolved,
        known: state.known,
        owned: state.owned,
        collected: state.collected,
        quantity: state.quantity,
        enabled: source.enabled !== false,
        usable: state.usable !== false,
        usabilityKnown: state.usabilityKnown !== undefined ? state.usabilityKnown : state.usable !== undefined,
        charges: state.charges,
        cooldown: state.cooldown || 0,
        reason: null,
        routeEligible: false,
        actionableNow: false,
    };

    if (!reason && source.actionType === 'spell' && result.known == null) reason = REASONS.API_UNAVAILABLE;
    if (!reason && source.actionType === 'spell' && result.known === false) reason = REASONS.NOT_KNOWN;
    if (!reason && source.actionType === 'item' && result.owned === false) reason = REASONS.NOT_OWNED;
    if (!reason && source.requiredQuantity && (result.quantity || 0) < source.requiredQuantity) {
        reason = REASONS.INSUFFICIENT_QUANTITY;
    }
    if (!reason && source.actionType === 'toy' && result.collected === false) reason = REASONS.NOT_COLLECTED;
    if (!reason && result.charges === 0) reason = REASONS.NO_CHARGES;
    if (!reason && result.cooldown > 0) reason = REASONS.ON_COOLDOWN;
    if (!reason && result.usable === false) reason = REASONS.UNUSABLE;
    if (!reason && !result.usabilityKnown) reason = REASONS.USABILITY_UNKNOWN;
    if (!reason && !result.destinationResolved) reason = REASONS.DESTINATION_UNRESOLVED;

    result.reason = reason || (source.actionType === 'transport' ? REASONS.UNSUPPORTED_SOURCE : REASONS.READY);
    result.actionableNow = result.reason === REASONS.READY
        && result.destinationResolved
        && result.usabilityKnown;
    result.routeEligible = result.destinationResolved
        && [REASONS.READY, REASONS.ON_COOLDOWN, REASONS.NO_CHARGES].includes(result.reason);
    return result;
}

function adaptLegacy(evaluation) {
    return {
        sourceKey: evaluation.sourceKey,
        name: evaluation.source.name,
        type: evaluation.source.edgeType,
        actionType: evaluation.source.actionType,
        actionID: evaluation.source.actionID,
        mapID: evaluation.destination.mapID,
        destinationResolved: evaluation.destinationResolved,
        routeEligible: evaluation.routeEligible,
        actionableNow: evaluation.actionableNow,
        reason: evaluation.reason,
    };
}

const sourceFixtures = [
    {
        sourceKey: 'spell:ready', name: 'Ready spell', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 100, destination: { kind: 'fixed', mapID: 84 },
        state: { known: true, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'spell:cooldown', name: 'Cooldown spell', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 101, destination: { kind: 'fixed', mapID: 85 },
        state: { known: true, cooldown: 30, usable: true },
    },
    {
        sourceKey: 'spell:unknown', name: 'Unknown spell', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 102, destination: { kind: 'fixed', mapID: 87 },
        state: { known: false, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'spell:charges', name: 'Empty charges', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 103, destination: { kind: 'fixed', mapID: 88 },
        state: { known: true, charges: 0, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'item:owned', name: 'Owned item', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 200, destination: { kind: 'fixed', mapID: 84 },
        state: { owned: true, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'item:missing', name: 'Missing item', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 201, destination: { kind: 'fixed', mapID: 84 },
        state: { owned: false, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'item:quantity', name: 'Quantity item', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 202, requiredQuantity: 2, destination: { kind: 'fixed', mapID: 84 },
        state: { owned: true, quantity: 1, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'toy:missing', name: 'Missing toy', kind: 'toy', edgeType: 'toy',
        actionType: 'toy', actionID: 300, destination: { kind: 'fixed', mapID: 84 },
        state: { collected: false, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'bind:dynamic', name: 'Hearthstone', kind: 'hearthstone', edgeType: 'hearthstone',
        actionType: 'item', actionID: 6948, destination: { kind: 'bind', mapID: 0 },
        state: { owned: true, cooldown: 0, usable: true, bindMapID: 2339 },
    },
    {
        sourceKey: 'random:dynamic', name: 'Wormhole', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 400, destination: { kind: 'random', mapID: 2274 },
        state: { owned: true, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'choice:dynamic', name: 'Mole Machine', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 500, destination: { kind: 'choice', mapID: 0 },
        state: { known: true, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'faction:wrong', name: 'Alliance item', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 600, destination: { kind: 'fixed', mapID: 84 },
        requirements: { faction: 'Alliance' }, state: { owned: true, cooldown: 0, usable: true, faction: 'Horde' },
    },
    {
        sourceKey: 'profession:wrong', name: 'Engineering item', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 601, destination: { kind: 'fixed', mapID: 83 },
        requirements: { profession: 'Engineering' }, state: { owned: true, cooldown: 0, usable: true, professions: [] },
    },
    {
        sourceKey: 'quest:missing', name: 'Quest item', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 602, destination: { kind: 'fixed', mapID: 84 },
        requirements: { quest: 9001 }, state: { owned: true, cooldown: 0, usable: true, completedQuests: [] },
    },
    {
        sourceKey: 'location:wrong', name: 'Location spell', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 603, destination: { kind: 'fixed', mapID: 84 },
        requirements: { location: 2339 }, state: { known: true, cooldown: 0, usable: true, currentMapID: 84 },
    },
    {
        sourceKey: 'class:wrong', name: 'Class source', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 606, destination: { kind: 'fixed', mapID: 84 },
        requirements: { class: 'MAGE' }, state: { known: true, cooldown: 0, usable: true, class: 'DRUID' },
    },
    {
        sourceKey: 'race:wrong', name: 'Race source', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 607, destination: { kind: 'fixed', mapID: 84 },
        requirements: { race: 'Vulpera' }, state: { known: true, cooldown: 0, usable: true, race: 'Human' },
    },
    {
        sourceKey: 'spec:wrong', name: 'Spec source', kind: 'teleport', edgeType: 'teleport',
        actionType: 'spell', actionID: 608, destination: { kind: 'fixed', mapID: 84 },
        requirements: { specialization: 'Arcane' }, state: { known: true, cooldown: 0, usable: true, specialization: 'Fire' },
    },
    {
        sourceKey: 'reputation:missing', name: 'Reputation source', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 609, destination: { kind: 'fixed', mapID: 84 },
        requirements: { reputation: 77, minimum: 42000 }, state: { owned: true, cooldown: 0, usable: true, reputation: { 77: 1000 } },
    },
    {
        sourceKey: 'expansion:missing', name: 'Expansion source', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 610, destination: { kind: 'fixed', mapID: 84 },
        requirements: { expansion: 'midnight' }, state: { owned: true, cooldown: 0, usable: true, expansions: [] },
    },
    {
        sourceKey: 'unsupported:source', name: 'Unsupported source', kind: 'unknown', edgeType: 'unknown',
        actionType: 'transport', actionID: 611, destination: { kind: 'fixed', mapID: 84 },
        state: { cooldown: 0, usable: true },
    },
    {
        sourceKey: 'disabled:source', name: 'Disabled source', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 604, enabled: false, destination: { kind: 'fixed', mapID: 84 },
        state: { owned: true, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'unusable:source', name: 'Unusable source', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 605, destination: { kind: 'fixed', mapID: 84 },
        state: { owned: true, cooldown: 0, usable: false },
    },
    {
        sourceKey: 'item:bank-only', name: 'Bank-only item', kind: 'item', edgeType: 'item',
        actionType: 'item', actionID: 612, destination: { kind: 'fixed', mapID: 84 },
        state: { owned: false, quantity: 0, bankQuantity: 3, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'requirement:unknown', name: 'Unknown requirement', kind: 'spell', edgeType: 'teleport',
        actionType: 'spell', actionID: 613, destination: { kind: 'fixed', mapID: 84 },
        requirements: { class: 'MAGE' }, state: { known: true, cooldown: 0, usable: true },
    },
    {
        sourceKey: 'usability:unknown', name: 'Unknown usability', kind: 'spell', edgeType: 'teleport',
        actionType: 'spell', actionID: 614, destination: { kind: 'fixed', mapID: 84 },
        state: { known: true, cooldown: 0 },
    },
];

function evaluateFixtures() {
    return sourceFixtures.map((source) => evaluateSource(source, source.state));
}

module.exports = {
    REASONS,
    adaptLegacy,
    evaluateFixtures,
    evaluateSource,
    resolveDestination,
    sourceFixtures,
};

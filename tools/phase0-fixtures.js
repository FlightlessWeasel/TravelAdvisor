'use strict';

// These fixtures define the Phase 0 contract without pretending to emulate the WoW client.
// Production source evaluation and route calculation will consume this contract in later phases.

const sourceFixtures = [
    { id: 'spell:100', kind: 'spell', state: 'ready', actionableNow: true },
    { id: 'item:200', kind: 'item', state: 'cooldown', actionableNow: false, cooldownSeconds: 30 },
    { id: 'toy:300', kind: 'toy', state: 'unknown-destination', actionableNow: false },
    { id: 'spell:400', kind: 'spell', state: 'not-known', actionableNow: false },
];

const routeFixtures = [
    { id: 'ready-route', actionableNow: true, destinationResolved: true, waitSeconds: 0, travelSeconds: 70 },
    { id: 'cooldown-route', actionableNow: false, destinationResolved: true, waitSeconds: 20, travelSeconds: 20 },
    { id: 'unknown-route', actionableNow: false, destinationResolved: false, waitSeconds: 0, travelSeconds: 10 },
];

function selectFixtureRoute(routes, policy) {
    const candidates = policy === 'best-now'
        ? routes.filter((route) => route.actionableNow && route.destinationResolved)
        : policy === 'best-if-ready'
            ? routes.filter((route) => !route.actionableNow && route.destinationResolved)
            : routes.filter((route) => route.destinationResolved);

    if (candidates.length === 0) return null;

    return candidates.reduce((best, route) => {
        const bestCost = policy === 'best-after-wait'
            ? best.waitSeconds + best.travelSeconds
            : best.travelSeconds;
        const routeCost = policy === 'best-after-wait'
            ? route.waitSeconds + route.travelSeconds
            : route.travelSeconds;
        return routeCost < bestCost ? route : best;
    });
}

module.exports = {
    routeFixtures,
    selectFixtureRoute,
    sourceFixtures,
};

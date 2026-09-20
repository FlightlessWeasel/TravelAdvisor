'use strict';

function clone(value) {
    return value && typeof value === 'object' ? JSON.parse(JSON.stringify(value)) : value;
}

function buildExplicitGraph(nodes, connections) {
    const edges = new Map();
    for (const node of nodes) edges.set(node.id, []);
    for (const connection of connections) {
        if (!edges.has(connection.from) || !edges.has(connection.to)) continue;
        edges.get(connection.from).push(clone(connection));
        if (connection.bidirectional) {
            edges.get(connection.to).push({
                ...clone(connection),
                from: connection.to,
                to: connection.from,
                derived: true,
            });
        }
    }
    return edges;
}

function findPath(edges, from, to, options = {}) {
    const queue = [{ node: from, cost: 0, path: [] }];
    const best = new Map([[from, 0]]);
    while (queue.length > 0) {
        queue.sort((left, right) => left.cost - right.cost);
        const current = queue.shift();
        if (current.node === to) return current;
        for (const edge of edges.get(current.node) || []) {
            if (options.readyOnly && edge.ready === false) continue;
            const wait = options.includeWait && edge.ready === false ? (edge.cooldown || 0) : 0;
            const edgeCost = options.objective === 'transitions'
                ? 1
                : options.objective === 'interactions'
                    ? (edge.interaction ? 1 : 0) + 0.001
                    : (edge.cost || 0) + wait;
            const cost = current.cost + edgeCost;
            if (!best.has(edge.to) || cost < best.get(edge.to)) {
                best.set(edge.to, cost);
                queue.push({ node: edge.to, cost, path: [...current.path, edge] });
            }
        }
    }
    return null;
}

function choosePolicies(routes) {
    const bestNow = routes.filter((route) => route.ready).sort((a, b) => a.cost - b.cost)[0] || null;
    const bestIfReady = [...routes].sort((a, b) => a.cost - b.cost)[0] || null;
    const bestAfterWait = [...routes].sort(
        (a, b) => (a.cost + (a.ready ? 0 : a.cooldown || 0))
            - (b.cost + (b.ready ? 0 : b.cooldown || 0)),
    )[0] || null;
    const fewestTransitions = [...routes].sort((a, b) => a.transitions - b.transitions)[0] || null;
    const fewestInteractions = [...routes].sort((a, b) => a.interactions - b.interactions)[0] || null;
    return { bestNow, bestIfReady, bestAfterWait, fewestTransitions, fewestInteractions };
}

const topologyNodes = [
    { id: 14, continent: 13, kind: 'region' },
    { id: 84, continent: 13, kind: 'hub' },
    { id: 2339, continent: 2274, kind: 'hub' },
    { id: 2248, continent: 2274, kind: 'region' },
    { id: 9999, continent: 13, kind: 'region' },
];

const topologyConnections = [
    { from: 14, to: 84, mode: 'walking', cost: 90, bidirectional: true },
    { from: 84, to: 2339, mode: 'portal-room', cost: 12 },
    { from: 2339, to: 2248, mode: 'flightpath', cost: 180, bidirectional: true },
];

const routeAlternatives = [
    { id: 'ready', ready: true, cost: 120, transitions: 3, interactions: 2 },
    { id: 'cooldown-fast', ready: false, cooldown: 30, cost: 40, transitions: 2, interactions: 1 },
    { id: 'cooldown-slow', ready: false, cooldown: 120, cost: 60, transitions: 1, interactions: 1 },
];

const dungeonIdentity = {
    instanceMapID: 0,
    entranceMapID: 0,
    landingMapID: 2214,
    regionMapID: 2214,
    instanceKey: 'the-stonevault',
    targetKind: 'landing',
    identityConfidence: 'landing-only',
};

module.exports = {
    buildExplicitGraph,
    findPath,
    choosePolicies,
    topologyNodes,
    topologyConnections,
    routeAlternatives,
    dungeonIdentity,
};

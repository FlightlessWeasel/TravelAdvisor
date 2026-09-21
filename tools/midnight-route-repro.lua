local root = arg[1] or "."

local function loadAddonFile(fileName)
    local chunk, err = loadfile(root .. "/" .. fileName)
    assert(chunk, err)
    chunk("TravelAdvisor", TA)
end

TA = {}

local mapInfo = {
    [2393] = { name = "Silvermoon City", parentMapID = 2395, continentID = 13 },
    [110] = { name = "Silvermoon City", parentMapID = 13, continentID = 13 },
}

_G.C_Map = {
    GetMapInfo = function(mapID)
        return mapInfo[mapID]
    end,
}

loadAddonFile("TravelData.lua")
loadAddonFile("TravelGraph.lua")

local TD = TA.TravelData
local Graph = TA.TravelGraph

local function findTreeNode(nodes, wantedMapID)
    for _, node in ipairs(nodes or {}) do
        if node.mapID == wantedMapID then return node end
        local child = findTreeNode(node.children, wantedMapID)
        if child then return child end
    end
    return nil
end

local identity = TD.MapIdentity and TD.MapIdentity[2393]
assert(identity, "Midnight Silvermoon must have a map identity")
assert(identity.alias ~= true, "Midnight Silvermoon must not be an alias")
assert(identity.routeMapID ~= 110, "Midnight Silvermoon must not route through legacy Silvermoon")

local expectedNames = {
    [2393] = "silvermoon city",
    [2395] = "eversong woods",
    [2437] = "zul'aman",
    [2413] = "harandar",
    [2444] = "voidstorm",
}
for mapID, name in pairs(expectedNames) do
    assert(TD.ZoneNameToID and TD.ZoneNameToID[name] == mapID,
        "Missing Midnight name lookup for " .. name)
    assert(findTreeNode(TD.ZoneTree, mapID),
        "Missing Midnight ZoneTree node for map " .. tostring(mapID))
end
assert(TD.ZoneNameToID["silvermoon city (legacy)"] == 110,
    "Legacy Silvermoon must remain separately addressable")

Graph:Initialize()
assert(Graph:HasNode(2393), "Midnight Silvermoon must be a graph node")
assert(Graph:HasNode(110), "Legacy Silvermoon must remain a graph node")
assert(Graph:GetNode(2393) ~= Graph:GetNode(110),
    "Midnight and legacy Silvermoon must be distinct graph nodes")

local currentNode, currentContext = Graph:ResolveRoutingMap(2393)
local legacyNode, legacyContext = Graph:ResolveRoutingMap(110)
assert(currentNode == 2393, "Midnight Silvermoon must resolve to its own node")
assert(legacyNode == 110, "Legacy Silvermoon must resolve to its own node")
assert(currentContext.approximate ~= true, "Midnight Silvermoon must not use parent approximation")
assert(legacyContext.approximate ~= true, "Legacy Silvermoon must not use parent approximation")
assert(currentNode ~= legacyNode,
    "Distinct Silvermoon maps must remain distinct before exact-match evaluation")

local route = Graph:FindPath(2393, 110, {
    currentMapID = 2393,
    checkUnlock = false,
})
assert(not route.found, "Unverified Midnight-to-legacy topology must remain non-routable")
assert(route.reason == "no-route", "2393 -> 110 must not be reported as already here")

local midnightRoute = Graph:FindPath(2393, 2437, {
    currentMapID = 2393,
    checkUnlock = false,
})
assert(midnightRoute.found, "Silvermoon must have an explicit conditional route to Zul'Aman")
assert(midnightRoute.path[1] and midnightRoute.path[1].to == 2437,
    "Silvermoon-to-Zul'Aman must use the explicit flight edge")
local bestNowRoute = Graph:FindPath(2393, 2437, {
    currentMapID = 2393,
    checkUnlock = false,
    onlyReady = true,
})
assert(not bestNowRoute.found,
    "Best Now must not present the unverified Silvermoon-to-Zul'Aman flight")

TD.MapIdentity[9001] = { kind = "instance", landingMapID = 2393 }
TD.MapIdentity[9002] = { kind = "instance", landingMapID = 2393 }
local firstAliasNode, firstAliasContext = Graph:ResolveRoutingMap(9001)
local secondAliasNode, secondAliasContext = Graph:ResolveRoutingMap(9002)
assert(firstAliasNode == 2393 and secondAliasNode == 2393,
    "Synthetic identity maps must resolve through their shared landing map")
assert(firstAliasContext.approximate == true and secondAliasContext.approximate == true,
    "Identity redirects to a different raw map must be approximate")
local aliasRoute = Graph:FindPath(9001, 9002, {
    currentMapID = 9001,
    checkUnlock = false,
})
assert(not (aliasRoute.found and #aliasRoute.path == 0),
    "Distinct identity maps must not produce an empty route")
assert(aliasRoute.reason ~= "already-here",
    "Distinct identity maps sharing a landing map must not collapse to already-here")

local function hasEdge(fromMapID, toMapID, mode)
    for _, edge in ipairs(Graph:GetEdgesFrom(fromMapID) or {}) do
        if edge.to == toMapID and (not mode or edge.mode == mode) then return true end
    end
    return false
end

for _, pair in ipairs({
    { 2393, 2413 }, { 2393, 2444 },
    { 2413, 2393 }, { 2413, 2444 },
    { 2444, 2393 }, { 2444, 2413 },
}) do
    assert(hasEdge(pair[1], pair[2], "portal-room"),
        string.format("Midnight portal topology must include %d -> %d", pair[1], pair[2]))
    local portalRoute = Graph:FindPath(pair[1], pair[2], {
        currentMapID = pair[1],
        checkUnlock = false,
    })
    assert(portalRoute.found,
        string.format("Midnight portal route must exist under the unrestricted policy: %d -> %d", pair[1], pair[2]))
    local portalBestNow = Graph:FindPath(pair[1], pair[2], {
        currentMapID = pair[1],
        checkUnlock = false,
        onlyReady = true,
    })
    assert(not portalBestNow.found,
        string.format("Best Now must reject the unverified Midnight portal route: %d -> %d", pair[1], pair[2]))
end

print("Midnight route regression: PASS")

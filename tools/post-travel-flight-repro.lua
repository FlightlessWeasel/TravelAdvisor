local root = arg[1] or "."

local function loadAddonFile(fileName)
    local chunk, err = loadfile(root .. "/" .. fileName)
    assert(chunk, err)
    chunk("TravelAdvisor", TA)
end

TA = {}
loadAddonFile("TravelData.lua")
loadAddonFile("TravelGraph.lua")

-- Keep the regression small and deterministic while exercising the actual
-- graph implementation loaded from the addon sources.
TA.TravelData = {
    ZoneCoordinates = {
        [100] = { x = 0.10, y = 0.10, continent = 1 },
        [200] = { x = 0.30, y = 0.30, continent = 1 },
        [300] = { x = 0.70, y = 0.70, continent = 1 },
        [400] = { x = 0.80, y = 0.80, continent = 1 },
        [500] = { x = 0.80, y = 0.80, continent = 2 },
    },
    ZoneNameToID = {
        ["start"] = 100,
        ["intermediate hub"] = 200,
        ["same-continent target"] = 300,
        ["portal-only target"] = 400,
        ["other-continent target"] = 500,
    },
    ZoneConnections = {
        [100] = {
            {
                to = 200,
                type = "portal",
                mode = "portal",
                cost = 5,
                accessState = "ready",
                actionableNow = true,
            },
        },
    },
    PortalOnlyZones = { 400 },
    ContinentZones = {
        [1] = { 100, 200, 300, 400 },
        [2] = { 500 },
    },
}

local Graph = TA.TravelGraph
Graph.initialized = false
Graph:Initialize()

local function findEdge(path, sourceType)
    for _, edge in ipairs(path or {}) do
        if edge.sourceType == sourceType then return edge end
    end
    return nil
end

local composed = Graph:FindPath(100, 300, {
    currentMapID = 100,
    checkUnlock = false,
})
assert(composed.found, "intermediate portal route must compose with a post-travel flight")
local fallback = findEdge(composed.path, "post-travel-flight")
assert(fallback and fallback.from == 200 and fallback.to == 300,
    "composed route must contain the real post-travel flight edge")
assert(fallback.accessState == "unknown" and fallback.actionableNow == false,
    "post-travel flight must remain conditional and informational")

assert(Graph:BuildPostTravelFlightEdge(100, 300, 100) == nil,
    "post-travel flight must not be synthesized directly from the starting node")

local portalOnly = Graph:FindPath(100, 400, {
    currentMapID = 100,
    checkUnlock = false,
})
assert(not portalOnly.found, "portal-only destinations must reject post-travel flight")

local crossContinent = Graph:FindPath(100, 500, {
    currentMapID = 100,
    checkUnlock = false,
})
assert(not crossContinent.found, "cross-continent destinations must reject post-travel flight")

local readyOnly = Graph:FindPath(100, 300, {
    currentMapID = 100,
    onlyReady = true,
    checkUnlock = false,
})
assert(not readyOnly.found, "onlyReady must reject unknown fallback access")

print("Post-travel flight regression: PASS")

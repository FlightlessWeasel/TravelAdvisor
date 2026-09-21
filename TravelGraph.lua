-- ═══════════════════════════════════════════════════════════════════════════
-- TravelGraph.lua - Graph-based route planning for TravelAdvisor
-- ═══════════════════════════════════════════════════════════════════════════

local _, TA = ...

local LibZoneNameToMap = LibStub and LibStub("LibZoneNameToMap-1.0", true)

-- Initialize graph structure
TA.TravelGraph = {
    nodes = {},           -- [mapID] = node identity and access metadata
    dynamicNodes = {},    -- Dynamic destinations owned by the current player-state snapshot
    edges = {},           -- Array of typed, access-checked topology transitions
    edgeIndex = {},       -- [fromMapID] = { edges... } for fast lookup
    playerEdges = {},     -- Dynamic edges from player abilities (cleared on rescan)
    playerSourceStates = {}, -- Canonical source evaluations, including excluded sources
    playerState = nil,    -- Snapshot used to produce playerSourceStates/playerEdges
    initialized = false,
}

local Graph = TA.TravelGraph

local function IsSecretValue(value)
    if value == nil then return false end
    local source = TA.TravelSources and TA.TravelSources.IsSecretValue
    if type(source) == "function" then return source(value) end
    local checker = _G.issecretvalue
    if type(checker) ~= "function" then return false end
    local ok, secret = pcall(checker, value)
    return ok and secret == true
end

local function SafeNumber(value, fallback)
    if value == nil or IsSecretValue(value) then return fallback end
    local ok, number = pcall(tonumber, value)
    if not ok or number == nil or IsSecretValue(number) or type(number) ~= "number" then
        return fallback
    end
    return number
end

local function SafeBoolean(value)
    if value == nil or IsSecretValue(value) then return nil end
    return value == true
end

local function SafeString(value, fallback)
    if value == nil or IsSecretValue(value) or type(value) ~= "string" then return fallback end
    return value
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

Graph.EdgeType = {
    WALK = "walk",             -- Walk within a region
    RIDE = "ride",             -- Ride within a region
    TELEPORT = "teleport",       -- Instant spell (mage teleport, hearthstone)
    PORTAL = "portal",           -- Walk to portal in hub
    PORTAL_ROOM = "portal-room", -- Portal-room movement/transition
    FLIGHT = "flight",           -- Explicit flight transition
    FLIGHT_PATH = "flightpath", -- Flight-master/taxi route
    TAXI = "taxi",               -- Taxi route with explicit schedule/access
    BOAT = "boat",               -- Boat transport
    ZEPPELIN = "zeppelin",       -- Zeppelin transport
    FERRY = "ferry",             -- Ferry transport
    DUNGEON = "dungeon",         -- Dungeon teleport (Hero's Path)
    DUNGEON_LANDING = "dungeon-landing", -- Transition into a dungeon landing region
    EXTERNAL = "external-interaction", -- Requires another player/NPC/group
    ITEM = "item",               -- Teleport item
    TOY = "toy",                 -- Teleport toy
    HEARTHSTONE = "hearthstone", -- Hearthstone variants
}

-- Base costs in seconds
Graph.BaseCost = {
    [Graph.EdgeType.WALK] = 30,
    [Graph.EdgeType.RIDE] = 20,
    [Graph.EdgeType.TELEPORT] = 5,      -- Cast time + loading
    [Graph.EdgeType.PORTAL] = 8,        -- Walk to portal + loading
    [Graph.EdgeType.PORTAL_ROOM] = 12,  -- Walk through a portal room
    [Graph.EdgeType.FLIGHT] = 0,        -- Calculated based on distance
    [Graph.EdgeType.FLIGHT_PATH] = 180,
    [Graph.EdgeType.TAXI] = 180,
    [Graph.EdgeType.BOAT] = 180,
    [Graph.EdgeType.ZEPPELIN] = 180,
    [Graph.EdgeType.FERRY] = 120,
    [Graph.EdgeType.DUNGEON] = 5,       -- Cast time + loading
    [Graph.EdgeType.DUNGEON_LANDING] = 15,
    [Graph.EdgeType.EXTERNAL] = 30,
    [Graph.EdgeType.ITEM] = 5,          -- Use time + loading
    [Graph.EdgeType.TOY] = 5,           -- Use time + loading
    [Graph.EdgeType.HEARTHSTONE] = 10,  -- Cast time (10s) + loading
}

-- Route policy names are part of the result contract.  The graph uses
-- explicit edge costs for all known topology and only labels a fallback as
-- approximate; it no longer synthesizes a same-continent direct flight.
Graph.Policy = {
    BEST_NOW = "best-now",
    BEST_IF_READY = "best-if-ready",
    BEST_AFTER_WAIT = "best-after-wait",
    FEWEST_TRANSITIONS = "fewest-transitions",
    FEWEST_INTERACTIONS = "fewest-interactions",
    CLOSEST_USEFUL = "closest-useful-landing",
}

Graph.FLIGHT_SPEED = 6 -- Deprecated compatibility constant; not used for routing.
Graph.DEFAULT_FLIGHT_COST = 180

-- Special node ID for player's current location
Graph.PLAYER_NODE = "player"

-- ═══════════════════════════════════════════════════════════════════════════
-- ZONE ACCESSIBILITY
-- ═══════════════════════════════════════════════════════════════════════════

-- Check if player has unlocked a zone (completed required quest)
function Graph:IsZoneUnlocked(mapID)
    local TD = TA.TravelData
    if not TD or not TD.ZoneUnlockQuests then return true end
    
    local req = TD.ZoneUnlockQuests[mapID]
    if not req then
        -- No unlock requirement, zone is accessible
        return true
    end
    
    -- Check if the unlock quest is completed
    if req.quest and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, value = pcall(C_QuestLog.IsQuestFlaggedCompleted, req.quest)
        local result = ok and SafeBoolean(value)
        if result ~= nil then return result end
    end
    
    -- Fallback: check if player has explored any of the zone
    if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures then
        local ok, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
        if ok and explored and not IsSecretValue(explored) and #explored > 0 then
            return true
        end
    end
    
    return false
end

-- Get unlock status info for a zone (for UI display)
function Graph:GetZoneUnlockInfo(mapID)
    local TD = TA.TravelData
    if not TD or not TD.ZoneUnlockQuests then
        return { unlocked = true }
    end
    
    local req = TD.ZoneUnlockQuests[mapID]
    if not req then
        return { unlocked = true }
    end
    
    local isUnlocked = self:IsZoneUnlocked(mapID)
    return {
        unlocked = isUnlocked,
        questID = req.quest,
        zoneName = req.name,
    }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- NODE MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════

function Graph:AddNode(mapID, data)
    if type(mapID) ~= "number" or mapID <= 0 or type(data) ~= "table" then return end

    local identity = data.identity or {}
    local requirements = data.requirements or identity.requirements or {}
    local kind = data.kind or data.locationKind or identity.kind or "region"
    
    self.nodes[mapID] = {
        id = mapID,
        name = data.name or ("Zone " .. mapID),
        continent = data.continent,
        faction = data.faction or "Both",
        kind = kind,
        targetKind = data.targetKind or kind,
        isHub = data.isHub or false,
        isPortalOnly = data.isPortalOnly or false,
        x = data.x or 50,
        y = data.y or 50,
        regionMapID = data.regionMapID or identity.regionMapID,
        entranceMapID = data.entranceMapID or identity.entranceMapID,
        instanceMapID = data.instanceMapID or identity.instanceMapID,
        landingMapID = data.landingMapID or identity.landingMapID,
        identityKey = data.identityKey or identity.identityKey,
        identityConfidence = data.identityConfidence or identity.identityConfidence,
        requirements = requirements,
        phase = data.phase or identity.phase,
        discovery = data.discovery or identity.discovery,
        services = data.services or identity.services,
    }
    
    -- Ensure edge index exists for this node
    if not self.edgeIndex[mapID] then
        self.edgeIndex[mapID] = {}
    end
end

function Graph:GetNode(mapID)
    return self.nodes[mapID] or self.dynamicNodes[mapID]
end

function Graph:HasNode(mapID)
    return self:GetNode(mapID) ~= nil
end

function Graph:AddDynamicNode(mapID, data)
    if type(mapID) ~= "number" or mapID <= 0 or type(data) ~= "table" then return end
    if self.nodes[mapID] then return self.nodes[mapID] end

    local identity = data.identity or {}
    local requirements = data.requirements or identity.requirements or {}
    local kind = data.kind or data.locationKind or identity.kind or "region"

    self.dynamicNodes[mapID] = {
        id = mapID,
        name = data.name or ("Zone " .. mapID),
        continent = data.continent,
        faction = data.faction or "Both",
        kind = kind,
        targetKind = data.targetKind or kind,
        isHub = data.isHub or false,
        isPortalOnly = data.isPortalOnly or false,
        x = data.x or 50,
        y = data.y or 50,
        regionMapID = data.regionMapID or identity.regionMapID,
        entranceMapID = data.entranceMapID or identity.entranceMapID,
        instanceMapID = data.instanceMapID or identity.instanceMapID,
        landingMapID = data.landingMapID or identity.landingMapID,
        identityKey = data.identityKey or identity.identityKey,
        identityConfidence = data.identityConfidence or identity.identityConfidence,
        requirements = requirements,
        phase = data.phase or identity.phase,
        discovery = data.discovery or identity.discovery,
        services = data.services or identity.services,
    }
    return self.dynamicNodes[mapID]
end

function Graph:ClearDynamicNodes()
    self.dynamicNodes = {}
end

function Graph:IsValidMapID(mapID)
    mapID = SafeNumber(mapID)
    return mapID ~= nil and mapID > 0
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EDGE MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════

function Graph:AddEdge(edgeData)
    if type(edgeData) ~= "table" or IsSecretValue(edgeData)
        or IsSecretValue(edgeData.from) or IsSecretValue(edgeData.to)
        or not edgeData.from or not edgeData.to then return end
    if edgeData.to ~= Graph.PLAYER_NODE and not self:IsValidMapID(edgeData.to) then
        return
    end

    local edgeType = edgeData.type or edgeData.edgeType or Graph.EdgeType.PORTAL
    local mode = edgeData.mode or edgeData.travelMode or edgeData.modeType
    if not mode then
        mode = edgeType
    end
    local externalInteraction = edgeData.externalInteraction == true
        or mode == Graph.EdgeType.EXTERNAL
        or edgeData.interaction == "external-player"
        or edgeData.interaction == "external"
    local accessState = edgeData.accessState or "ready"
    local actionableNow = edgeData.actionableNow ~= false
        and accessState ~= "unknown"
        and not externalInteraction
    local actionability = edgeData.actionability or "derived-from-access"
    if actionability == "informational-only" then actionableNow = false end
    local executable = edgeData.executable
    if executable == nil then executable = edgeData.isPlayerEdge == true and actionableNow end
    local requirements = edgeData.requirements or {}
    if type(requirements) ~= "table" then requirements = {} end
    
    local edge = {
        from = edgeData.from,
        to = edgeData.to,
        type = edgeType,
        mode = mode,
        travelMode = mode,
        cost = edgeData.cost,  -- nil means calculate dynamically (for flight)
        name = edgeData.name or "",
        spellID = edgeData.spellID,
        itemID = edgeData.itemID,
        cooldown = edgeData.cooldown or 0,
        faction = edgeData.faction,
        icon = edgeData.icon,
        isPlayerEdge = edgeData.isPlayerEdge or false,
        state = edgeData.state or "ready",
        reason = edgeData.reason,
        reasonText = edgeData.reasonText,
        actionableNow = actionableNow,
        executable = executable == true and actionableNow,
        destinationResolved = edgeData.destinationResolved ~= false,
        routeEligible = edgeData.routeEligible ~= false,
        actionType = edgeData.actionType,
        actionID = edgeData.actionID,
        sourceKey = edgeData.sourceKey,
        source = edgeData.source,
        sourceState = edgeData.sourceState,
        sourceType = edgeData.sourceType,
        sourceID = edgeData.sourceID,
        destination = edgeData.destination,
        sourceFamily = edgeData.sourceFamily,
        interaction = edgeData.interaction,
        interactionType = edgeData.interactionType,
        externalInteraction = externalInteraction,
        actionableByPlayer = edgeData.actionableByPlayer ~= false,
        destinationOptions = edgeData.destinationOptions,
        charges = edgeData.charges,
        destinationUncertain = edgeData.destinationUncertain == true,
        requirements = requirements,
        access = edgeData.access or (next(requirements) and "restricted" or "unrestricted"),
        accessState = accessState,
        location = edgeData.location,
        availability = edgeData.availability,
        actionability = actionability,
        provenance = edgeData.provenance,
        evidence = edgeData.evidence,
        requiresDiscovery = edgeData.requiresDiscovery == true,
        timing = edgeData.timing,
        estimated = edgeData.estimated ~= false,
        approximate = edgeData.approximate == true or edgeData.confidence == "low",
        confidence = edgeData.confidence or (edgeData.cost and "medium" or "low"),
        targetKind = edgeData.targetKind,
        targetIdentity = edgeData.targetIdentity,
        instanceMapID = edgeData.instanceMapID,
        entranceMapID = edgeData.entranceMapID,
        landingMapID = edgeData.landingMapID,
        regionMapID = edgeData.regionMapID,
        bidirectional = edgeData.bidirectional == true,
        derived = edgeData.derived == true,
        sourceHubMapID = edgeData.sourceHubMapID,
    }
    
    table.insert(self.edges, edge)
    
    -- Index by source node for fast lookup
    local fromKey = edge.from
    if not self.edgeIndex[fromKey] then
        self.edgeIndex[fromKey] = {}
    end
    table.insert(self.edgeIndex[fromKey], edge)
    
    return edge
end

function Graph:AddPlayerEdge(edgeData)
    edgeData.isPlayerEdge = true
    local edge = self:AddEdge(edgeData)
    if edge then
        table.insert(self.playerEdges, edge)
    end
    return edge
end

function Graph:ClearPlayerEdges()
    -- Remove player edges from main edge list and index
    for _, edge in ipairs(self.playerEdges) do
        -- Remove from edges array
        for i = #self.edges, 1, -1 do
            if self.edges[i] == edge then
                table.remove(self.edges, i)
                break
            end
        end
        
        -- Remove from edge index
        local fromKey = edge.from
        if self.edgeIndex[fromKey] then
            for i = #self.edgeIndex[fromKey], 1, -1 do
                if self.edgeIndex[fromKey][i] == edge then
                    table.remove(self.edgeIndex[fromKey], i)
                    break
                end
            end
        end
    end
    
    self.playerEdges = {}
    self.playerSourceStates = {}
    self.playerState = nil
    self:ClearDynamicNodes()
end

-- Single shared empty table so we don't allocate when a node has no edges
local EMPTY_EDGES = {}

function Graph:GetEdgesFrom(nodeID)
    return self.edgeIndex[nodeID] or EMPTY_EDGES
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COST CALCULATION
-- ═══════════════════════════════════════════════════════════════════════════

function Graph:GetFlightDistance(fromMapID, toMapID)
    local fromNode = self:GetNode(fromMapID)
    local toNode = self:GetNode(toMapID)
    
    if not fromNode or not toNode then return nil end
    
    -- Cache for numeric mapID pairs (flight distances are static)
    local cacheKey
    if type(fromMapID) == "number" and type(toMapID) == "number" then
        cacheKey = fromMapID .. "_" .. toMapID
        local cache = self._flightDistanceCache or {}
        self._flightDistanceCache = cache
        if cache[cacheKey] ~= nil then return cache[cacheKey] end
    end
    
    local fromCoords = TA.TravelData.ZoneCoordinates and TA.TravelData.ZoneCoordinates[fromMapID]
    local toCoords = TA.TravelData.ZoneCoordinates and TA.TravelData.ZoneCoordinates[toMapID]
    
    local x1 = fromCoords and fromCoords.x or fromNode.x or 50
    local y1 = fromCoords and fromCoords.y or fromNode.y or 50
    local x2 = toCoords and toCoords.x or toNode.x or 50
    local y2 = toCoords and toCoords.y or toNode.y or 50
    
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    
    if cacheKey then self._flightDistanceCache[cacheKey] = dist end
    return dist
end

local function timingCost(timing)
    if type(timing) ~= "table" then return 0 end
    local total = 0
    for _, field in ipairs({ "cast", "wait", "interaction", "travel" }) do
        local value = SafeNumber(timing[field])
        if value and value > 0 then total = total + value end
    end
    return total
end

function Graph:GetTravelMode(edge)
    return edge and (edge.mode or edge.travelMode or edge.type) or "unknown"
end

function Graph:CalculateEdgeCost(edge, fromMapID, options)
    options = options or {}
    if options.objective == "transitions" then
        return 1
    elseif options.objective == "interactions" then
        local interaction = edge.interaction or edge.interactionType
        local count = interaction and interaction ~= "player" and 1 or 0
        return count + 0.001
    end

    local cost = SafeNumber(edge.cost)
    if cost == nil then
        cost = timingCost(edge.timing)
    end
    if not cost or cost <= 0 then
        local edgeType = edge.type or self.EdgeType.PORTAL
        if edgeType == Graph.EdgeType.FLIGHT or edgeType == Graph.EdgeType.FLIGHT_PATH
            or edgeType == Graph.EdgeType.TAXI then
            -- A missing explicit transport duration is intentionally a coarse
            -- estimate.  Coordinates are retained for map display, not used
            -- to invent a precise direct flight.
            cost = Graph.DEFAULT_FLIGHT_COST
        else
            cost = Graph.BaseCost[edgeType] or 10
        end
    end

    if options.includeWait and SafeBoolean(edge.actionableNow) == false then
        cost = cost + math.max(0, SafeNumber(edge.cooldown, 0))
    end
    return cost
end

local function copyState(state)
    local result = {}
    for key, value in pairs(state or {}) do result[key] = value end
    return result
end

function Graph:GetRequirementState(playerFaction, options)
    local state = copyState(options and options.playerState or self.playerState)
    if options and options.playerFaction then
        state.faction = options.playerFaction
    elseif state.faction == nil then
        state.faction = playerFaction or "Both"
    end
    if state.currentMapID == nil and options and options.currentMapID then
        state.currentMapID = options.currentMapID
    end
    return state
end

function Graph:CheckRequirements(requirements, state)
    if type(requirements) ~= "table" or next(requirements) == nil then
        return true
    end

    if TA.TravelSources and type(TA.TravelSources.EvaluateRequirements) == "function" then
        local reason = TA.TravelSources.EvaluateRequirements(requirements, state)
        if reason then return false, reason end
        return true
    end

    -- The canonical evaluator normally exists because TravelSources.lua is
    -- loaded before this module.  Keep a conservative fallback for embedders
    -- that load the graph in isolation.
    if requirements.faction and state.faction
        and requirements.faction ~= "Both" and requirements.faction ~= state.faction then
        return false, "wrong-faction"
    end
    if requirements.class and state.class == nil then return false, "requirements-not-met" end
    if requirements.race and state.race == nil then return false, "requirements-not-met" end
    if requirements.specialization and state.specialization == nil and state.specID == nil then
        return false, "requirements-not-met"
    end
    return true
end

function Graph:CheckNodeAccess(mapID, options)
    if mapID == Graph.PLAYER_NODE then return true end
    local node = self:GetNode(mapID)
    if not node then return false, "unsupported-map" end

    local state = options and options.playerState or self.playerState or {}
    local faction = state.faction or (options and options.playerFaction) or "Both"
    if node.faction and node.faction ~= "Both" and node.faction ~= faction then
        return false, "wrong-faction"
    end

    local requirements = node.requirements
    if node.phase and (not requirements or requirements.phase == nil) then
        local copy = {}
        for key, value in pairs(requirements or {}) do copy[key] = value end
        requirements = copy
        requirements.phase = node.phase
    end
    if node.discovery and (not requirements or requirements.discovery == nil) then
        local copy = {}
        for key, value in pairs(requirements or {}) do copy[key] = value end
        requirements = copy
        requirements.discovery = node.discovery
    end
    local allowed, reason = self:CheckRequirements(requirements, self:GetRequirementState(faction, options))
    if not allowed then return false, reason end
    return true
end

function Graph:CheckEdgeAccess(edge, playerFaction, onlyReady, checkUnlock, options)
    options = options or {}
    if SafeBoolean(edge.destinationResolved) == false then return false, "destination-unresolved" end
    if SafeBoolean(edge.routeEligible) == false then return false, edge.reason or "unsupported-source" end
    if options.requireExecutable and edge.executable ~= true then
        return false, edge.reason or "informational-only"
    end

    local state = self:GetRequirementState(playerFaction, options)
    if edge.faction and edge.faction ~= "Both" and edge.faction ~= state.faction then
        return false, "wrong-faction"
    end

    if edge.from ~= Graph.PLAYER_NODE then
        local fromAllowed, fromReason = self:CheckNodeAccess(edge.from, options)
        if not fromAllowed then return false, fromReason end
    end
    local toAllowed, toReason = self:CheckNodeAccess(edge.to, options)
    if not toAllowed then return false, toReason end

    local requirementsAllowed, requirementsReason = self:CheckRequirements(edge.requirements, state)
    if not requirementsAllowed then return false, requirementsReason end

    if onlyReady and edge.accessState == "unknown" then
        return false, edge.reason or "access-unknown"
    end

    if onlyReady and SafeBoolean(edge.actionableNow) == false then
        return false, edge.reason or "not-ready"
    end

    if checkUnlock and edge.to and type(edge.to) == "number" then
        local cache = options.unlockedCache
        local unlocked
        if cache then
            unlocked = cache[edge.to]
            if unlocked == nil then
                unlocked = self:IsZoneUnlocked(edge.to)
                cache[edge.to] = unlocked
            end
        else
            unlocked = self:IsZoneUnlocked(edge.to)
        end
        if not unlocked then return false, "zone-not-unlocked" end
    end
    return true
end

function Graph:CanUseEdge(edge, playerFaction, onlyReady, checkUnlock, options)
    local allowed = self:CheckEdgeAccess(edge, playerFaction, onlyReady, checkUnlock, options)
    return allowed
end

function Graph:CanFlyBetween(fromMapID, toMapID)
    local fromNode = self:GetNode(fromMapID)
    local toNode = self:GetNode(toMapID)
    
    if not fromNode or not toNode then return false end
    
    -- Can't fly to/from portal-only zones
    if fromNode.isPortalOnly or toNode.isPortalOnly then
        return false
    end
    
    -- Must be on same continent (and both must have continent set)
    if not fromNode.continent or not toNode.continent then
        return false
    end
    
    if fromNode.continent ~= toNode.continent then
        return false
    end
    
    return true
end

-- Build a conservative final movement leg after the path has already left the
-- player's current routing node.  This keeps teleport and portal sources
-- composable without restoring the old direct-flight shortcut from the
-- player's current location.  The edge is informational until discovered
-- flight access can be verified by the client.
function Graph:BuildPostTravelFlightEdge(fromMapID, toMapID, startNodeID)
    if not self:IsValidMapID(fromMapID) or not self:IsValidMapID(toMapID) then
        return nil
    end
    if fromMapID == toMapID or fromMapID == startNodeID then return nil end
    if not self:CanFlyBetween(fromMapID, toMapID) then return nil end

    local targetNode = self:GetNode(toMapID)
    return {
        from = fromMapID,
        to = toMapID,
        type = Graph.EdgeType.FLIGHT,
        mode = Graph.EdgeType.FLIGHT,
        name = "Fly to " .. self:GetZoneName(toMapID),
        cost = Graph.DEFAULT_FLIGHT_COST,
        estimated = true,
        approximate = true,
        confidence = "low",
        actionableNow = false,
        executable = false,
        routeEligible = true,
        destinationResolved = true,
        access = "conditional",
        accessState = "unknown",
        requiresDiscovery = true,
        reason = "access-unknown",
        interaction = "player",
        sourceType = "post-travel-flight",
        targetKind = targetNode and (targetNode.targetKind or targetNode.kind) or "region",
    }
end

local function safeGraphCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return true, a, b, c end
    return false
end

-- Return the map context without treating an instance or phase map as a
-- normal region.  The route planner may use a known parent/landing region as
-- a conservative fallback, while retaining the requested map in the result.
function Graph:GetMapContext(mapID)
    local TD = TA.TravelData or {}
    local identity = TD.MapIdentity and TD.MapIdentity[mapID]
    local context = {
        mapID = mapID,
        routeMapID = self:HasNode(mapID) and mapID or nil,
        parentMapID = nil,
        continentID = nil,
        mapType = nil,
        isInstance = false,
        isPhased = false,
        approximate = false,
    }
    if not self:IsValidMapID(mapID) then return context end

    if identity then
        context.parentMapID = identity.parentMapID
        context.continentID = identity.continentID
        context.mapType = identity.mapType
        context.isInstance = identity.isInstance == true
        context.isPhased = identity.isPhased == true
        context.approximate = identity.approximate == true
        if not context.routeMapID then
            context.routeMapID = identity.routeMapID
                or identity.landingMapID
                or identity.regionMapID
        end
    end

    local mapAPI = _G.C_Map
    if mapAPI and type(mapAPI.GetMapInfo) == "function" then
        local ok, info = safeGraphCall(mapAPI.GetMapInfo, mapID)
        if ok and type(info) == "table" and not IsSecretValue(info) then
            local parentMapID = SafeNumber(info.parentMapID)
            local continentID = SafeNumber(info.continentID)
            local mapType = SafeNumber(info.mapType)
            context.parentMapID = context.parentMapID or parentMapID
            context.continentID = context.continentID or continentID
            context.mapType = context.mapType or mapType
            context.isInstance = context.isInstance or SafeBoolean(info.isInstance) == true or mapType == 3
            context.isPhased = context.isPhased or SafeBoolean(info.isPhased) == true
        end
    end

    local visited = {}
    local candidate = context.parentMapID
    while not context.routeMapID and self:IsValidMapID(candidate) and not visited[candidate] do
        visited[candidate] = true
        if self:HasNode(candidate) then
            context.routeMapID = candidate
            context.approximate = true
            break
        end
        local parentInfo
        if mapAPI and type(mapAPI.GetMapInfo) == "function" then
            local ok, info = safeGraphCall(mapAPI.GetMapInfo, candidate)
            if ok and type(info) == "table" and not IsSecretValue(info) then parentInfo = info end
        end
        candidate = parentInfo and parentInfo.parentMapID
    end
    return context
end

function Graph:ResolveRoutingMap(mapID)
    local context = self:GetMapContext(mapID)
    if context.isPhased then
        return nil, context
    end
    if context.routeMapID and self:HasNode(context.routeMapID) then
        return context.routeMapID, context
    end
    return nil, context
end

-- A shared routing node is only an exact same-location result when the raw
-- requested maps match or both contexts were resolved without approximation.
-- Parent fallback is useful for routing, but it must never claim two distinct
-- unsupported child maps are the same destination.
function Graph:IsExactRoutingMatch(currentMapID, destinationMapID, currentContext, destinationContext)
    if currentMapID == destinationMapID then return true end
    return currentContext ~= nil
        and destinationContext ~= nil
        and currentContext.approximate ~= true
        and destinationContext.approximate ~= true
end

local function tableFingerprint(value)
    if IsSecretValue(value) then return "<secret>" end
    if type(value) ~= "table" then return tostring(value or "?") end
    local entries = {}
    for key, child in pairs(value) do
        if not IsSecretValue(key) and not IsSecretValue(child)
            and type(child) ~= "table" and type(child) ~= "function" then
            entries[#entries + 1] = tostring(key) .. "=" .. tostring(child)
        end
    end
    table.sort(entries)
    return table.concat(entries, ",")
end

function Graph:GetPlayerStateFingerprint(state)
    state = state or {}
    local parts = {}
    for _, key in ipairs({
        "completedQuests", "reputation", "professions", "professionDetails", "professionSkills",
        "unlocks", "discoveries", "discovered", "phases", "access", "accessState",
        "knownSources", "ownedSources", "sourceRevision", "unlockRevision",
        "discoveryRevision", "professionRevision", "questRevision", "reputationRevision",
    }) do
        if state[key] ~= nil then
            parts[#parts + 1] = key .. "{" .. tableFingerprint(state[key]) .. "}"
        end
    end
    return table.concat(parts, "|")
end

function Graph:GetSourceStateFingerprint()
    local parts = {}
    for _, sourceState in ipairs(self.playerSourceStates or {}) do
        local destination = sourceState.destination or {}
        parts[#parts + 1] = table.concat({
            tostring(sourceState.sourceKey),
            tostring(SafeNumber(sourceState.cooldown, 0)),
            tostring(sourceState.reason),
            tostring(destination.mapID),
            tostring(sourceState.actionableNow),
            tostring(sourceState.routeEligible),
        }, ":")
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

function Graph:BuildRouteCacheKey(currentMapID, destinationMapID, options)
    options = options or {}
    local state = options.playerState or self.playerState or {}
    local fields = {
        currentMapID,
        options.resolvedCurrentMapID,
        destinationMapID,
        options.resolvedDestinationMapID,
        state.faction or options.playerFaction,
        state.class,
        state.race,
        state.specialization or state.specID,
        state.phase or state.phaseID,
        state.instanceMapID,
        state.parentMapID,
        state.bindMapID,
        state.sourceRevision,
        state.unlockRevision,
        state.discoveryRevision,
        self:GetPlayerStateFingerprint(state),
        self:GetSourceStateFingerprint(),
        options.policy,
    }
    local parts = {}
    for index, value in ipairs(fields) do parts[index] = tostring(value or "?") end
    return table.concat(parts, "|")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DIJKSTRA'S ALGORITHM
-- ═══════════════════════════════════════════════════════════════════════════

-- Simple priority queue implementation
local function createPriorityQueue()
    local pq = { items = {} }
    
    function pq:push(item, priority)
        table.insert(self.items, { item = item, priority = priority })
        -- Bubble up
        local i = #self.items
        while i > 1 do
            local parent = math.floor(i / 2)
            if self.items[parent].priority > self.items[i].priority then
                self.items[parent], self.items[i] = self.items[i], self.items[parent]
                i = parent
            else
                break
            end
        end
    end
    
    function pq:pop()
        if #self.items == 0 then return nil end
        
        local result = self.items[1]
        self.items[1] = self.items[#self.items]
        table.remove(self.items)
        
        -- Bubble down
        local i = 1
        while true do
            local smallest = i
            local left = 2 * i
            local right = 2 * i + 1
            
            if left <= #self.items and self.items[left].priority < self.items[smallest].priority then
                smallest = left
            end
            if right <= #self.items and self.items[right].priority < self.items[smallest].priority then
                smallest = right
            end
            
            if smallest ~= i then
                self.items[i], self.items[smallest] = self.items[smallest], self.items[i]
                i = smallest
            else
                break
            end
        end
        
        return result.item, result.priority
    end
    
    function pq:isEmpty()
        return #self.items == 0
    end
    
    function pq:clear()
        for i = #self.items, 1, -1 do
            self.items[i] = nil
        end
    end
    
    return pq
end

-- Reusable priority queue (cleared at start of each FindPath to avoid allocations)
local sharedPQ = createPriorityQueue()

-- Clear a table for reuse (keeps table, removes all entries)
local function wipeTable(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

--[[
    FindPath - Find shortest path from source to destination using Dijkstra's algorithm
    
    @param fromMapID: Starting map ID (or Graph.PLAYER_NODE for current location)
    @param toMapID: Destination map ID
    @param options: {
        playerFaction: "Alliance" or "Horde"
        onlyReady: boolean - only use edges with no cooldown
        currentMapID: number - player's current map ID (used when fromMapID is PLAYER_NODE)
        checkUnlock: boolean - skip routes through/to locked zones (default true)
    }
    
    @return: {
        found: boolean
        path: array of edges taken
        totalCost: number (seconds)
        nodes: array of node IDs in order
    }
]]
function Graph:FindPath(fromMapID, toMapID, options)
    options = options or {}
    local playerFaction = options.playerFaction or "Both"
    local onlyReady = options.onlyReady or false
    local currentMapID = options.currentMapID or fromMapID
    local checkUnlock = options.checkUnlock ~= false

    local function copyExclusions()
        local result = {}
        for index, exclusion in ipairs(self._lastRouteExclusions or {}) do
            result[index] = exclusion
        end
        return result
    end

    local function noPath(reason, context)
        return {
            found = false,
            path = {},
            totalCost = math.huge,
            estimatedSeconds = math.huge,
            nodes = {},
            policy = options.policy,
            reason = reason,
            context = context,
            exclusions = copyExclusions(),
        }
    end

    if not self:IsValidMapID(toMapID) then
        return noPath("unknown-destination")
    end
    if fromMapID == Graph.PLAYER_NODE and not self:IsValidMapID(currentMapID) then
        return noPath("unknown-current-map")
    end
    if fromMapID ~= Graph.PLAYER_NODE and not self:IsValidMapID(fromMapID) then
        return noPath("unknown-current-map")
    end

    local startRequestedMapID = fromMapID == Graph.PLAYER_NODE and currentMapID or fromMapID
    local startNode, startContext = self:ResolveRoutingMap(startRequestedMapID)
    local targetNode, targetContext = self:ResolveRoutingMap(toMapID)
    if not startNode then return noPath("unsupported-current-map", startContext) end
    if not targetNode then return noPath("unsupported-destination", targetContext) end

    if checkUnlock and not self:IsZoneUnlocked(targetNode) then
        return noPath("zone-not-unlocked", targetContext)
    end

    if startNode == targetNode and self:IsExactRoutingMatch(
        startRequestedMapID, toMapID, startContext, targetContext
    ) then
        return {
            found = true,
            path = {},
            totalCost = 0,
            estimatedSeconds = 0,
            movementCost = 0,
            waitTime = 0,
            nodes = { startNode },
            actionableNow = true,
            policy = options.policy,
            approximate = startContext.approximate or targetContext.approximate,
            confidence = (startContext.approximate or targetContext.approximate) and "low" or "high",
            requestedCurrentMapID = startRequestedMapID,
            requestedDestinationMapID = toMapID,
            resolvedCurrentMapID = startNode,
            resolvedDestinationMapID = targetNode,
            currentContext = startContext,
            destinationContext = targetContext,
        }
    end

    if startNode == targetNode then
        return noPath("unsupported-map", {
            current = startContext,
            destination = targetContext,
        })
    end

    local dist = self._dist or {}
    local prev = self._prev or {}
    local visited = self._visited or {}
    self._dist = dist
    self._prev = prev
    self._visited = visited
    wipeTable(dist)
    wipeTable(prev)
    wipeTable(visited)
    options.unlockedCache = options.unlockedCache or {}
    wipeTable(options.unlockedCache)
    self._lastRouteExclusions = {}
    sharedPQ:clear()
    local pq = sharedPQ
    local iterations = 0
    local MAX_ITERATIONS = 5000

    local function noteExclusion(edge, reason)
        if #self._lastRouteExclusions >= 50 then return end
        self._lastRouteExclusions[#self._lastRouteExclusions + 1] = {
            from = edge.from,
            to = edge.to,
            name = edge.name,
            mode = self:GetTravelMode(edge),
            reason = reason,
        }
    end

    -- The virtual player node represents abilities usable at the current
    -- location.  Static topology still starts at the resolved current node.
    dist[Graph.PLAYER_NODE] = 0
    pq:push(Graph.PLAYER_NODE, 0)
    dist[startNode] = 0
    pq:push(startNode, 0)

    while not pq:isEmpty() do
        iterations = iterations + 1
        if iterations > MAX_ITERATIONS then break end

        local currentNode, currentDist = pq:pop()
        if not visited[currentNode] then
            visited[currentNode] = true
            if currentNode == targetNode then break end

            local edges = self:GetEdgesFrom(currentNode)
            for _, edge in ipairs(edges) do
                local allowed, reason = self:CheckEdgeAccess(
                    edge, playerFaction, onlyReady, checkUnlock, options
                )
                if allowed then
                    local edgeCost = self:CalculateEdgeCost(edge, currentNode, options)
                    local newDist = currentDist + edgeCost
                    local nextNode = edge.to
                    if not dist[nextNode] or newDist < dist[nextNode] then
                        dist[nextNode] = newDist
                        prev[nextNode] = { node = currentNode, edge = edge }
                        pq:push(nextNode, newDist)
                    end
                else
                    noteExclusion(edge, reason)
                end
            end

            -- Once a route has reached an intermediate region or hub, allow a
            -- conservative final flight to the requested destination.  This
            -- composes every resolved player/portal source with movement while
            -- keeping the current location itself on explicit topology only.
            if currentNode ~= Graph.PLAYER_NODE then
                local fallback = self:BuildPostTravelFlightEdge(
                    currentNode, targetNode, startNode
                )
                if fallback then
                    local allowed, reason = self:CheckEdgeAccess(
                        fallback, playerFaction, onlyReady, checkUnlock, options
                    )
                    if allowed then
                        local edgeCost = self:CalculateEdgeCost(fallback, currentNode, options)
                        local newDist = currentDist + edgeCost
                        if not dist[targetNode] or newDist < dist[targetNode] then
                            dist[targetNode] = newDist
                            prev[targetNode] = { node = currentNode, edge = fallback }
                            pq:push(targetNode, newDist)
                        end
                    else
                        noteExclusion(fallback, reason)
                    end
                end
            end
        end
    end

    if not dist[targetNode] then
        return noPath("no-route", {
            current = startContext,
            destination = targetContext,
        })
    end

    local path = {}
    local nodes = {}
    local current = targetNode
    while prev[current] do
        path[#path + 1] = prev[current].edge
        nodes[#nodes + 1] = current
        current = prev[current].node
    end
    nodes[#nodes + 1] = current
    local n = #path
    for i = 1, math.floor(n / 2) do
        path[i], path[n - i + 1] = path[n - i + 1], path[i]
    end
    n = #nodes
    for i = 1, math.floor(n / 2) do
        nodes[i], nodes[n - i + 1] = nodes[n - i + 1], nodes[i]
    end

    local filteredNodes = {}
    for _, nodeID in ipairs(nodes) do
        if nodeID ~= Graph.PLAYER_NODE then filteredNodes[#filteredNodes + 1] = nodeID end
    end

    local waitTime = 0
    local movementCost = 0
    local actionableNow = true
    local executableNow = true
    local readyNow = true
    local approximate = startContext.approximate or targetContext.approximate
    local confidence = approximate and "low" or "high"
    local interactionCount = 0
    local maxCooldown = 0
    local routeReason
    local routeReasonText
    local routeCharges
    local routeSources = {}
    for _, edge in ipairs(path) do
        movementCost = movementCost + self:CalculateEdgeCost(edge, edge.from, {
            objective = nil,
            includeWait = false,
        })
        local edgeCooldown = SafeNumber(edge.cooldown, 0)
        if edgeCooldown > 0 then
            maxCooldown = math.max(maxCooldown, edgeCooldown)
            if SafeBoolean(edge.actionableNow) == false then waitTime = waitTime + edgeCooldown end
        end
        if SafeBoolean(edge.actionableNow) == false then
            actionableNow = false
            readyNow = false
            routeReason = routeReason or edge.reason
                or (edge.accessState == "unknown" and "access-unknown")
                or "not-ready"
            routeReasonText = routeReasonText or edge.reasonText
                or (edge.sourceState and edge.sourceState.reasonText)
        end
        if SafeBoolean(edge.routeEligible) == false or SafeBoolean(edge.destinationResolved) == false then
            executableNow = false
            readyNow = false
            routeReason = routeReason or edge.reason or "route-unavailable"
            routeReasonText = routeReasonText or edge.reasonText
                or (edge.sourceState and edge.sourceState.reasonText)
        end
        if SafeBoolean(edge.actionableNow) == false or SafeBoolean(edge.externalInteraction) == true then
            executableNow = false
        end
        if edgeCooldown > 0 then
            readyNow = false
        end
        if edge.charges and not routeCharges then
            routeCharges = edge.charges
        end
        if edge.sourceState then
            routeSources[#routeSources + 1] = edge.sourceState
        end
        if edge.approximate or edge.confidence == "low" then
            approximate = true
            confidence = "low"
        elseif confidence == "high" and edge.confidence == "medium" then
            confidence = "medium"
        end
        if edge.isPlayerEdge or (edge.interaction and edge.interaction ~= "player") then
            interactionCount = interactionCount + 1
        end
    end

    local elapsedCost = movementCost + waitTime
    local totalCost = dist[targetNode]
    if options.objective == "transitions" or options.objective == "interactions" then
        totalCost = dist[targetNode]
    elseif options.includeWait then
        totalCost = elapsedCost
    end

    return {
        found = true,
        path = path,
        totalCost = totalCost,
        estimatedSeconds = elapsedCost,
        movementCost = movementCost,
        waitTime = waitTime,
        cooldown = maxCooldown,
        nodes = filteredNodes,
        actionableNow = actionableNow,
        executableNow = executableNow,
        readyNow = readyNow and actionableNow and waitTime <= 0,
        reason = routeReason,
        reasonText = routeReasonText,
        charges = routeCharges,
        sourceStates = routeSources,
        policy = options.policy,
        objective = options.objective,
        approximate = approximate,
        estimated = true,
        confidence = confidence,
        transitionCount = #path,
        interactionCount = interactionCount,
        requestedCurrentMapID = startRequestedMapID,
        requestedDestinationMapID = toMapID,
        resolvedCurrentMapID = startNode,
        resolvedDestinationMapID = targetNode,
        currentContext = startContext,
        destinationContext = targetContext,
    }
end

local function routePolicyLabel(policy)
    local labels = {
        [Graph.Policy.BEST_NOW] = "Best Now",
        [Graph.Policy.BEST_IF_READY] = "Best If Ready",
        [Graph.Policy.BEST_AFTER_WAIT] = "Best After Wait",
        [Graph.Policy.FEWEST_TRANSITIONS] = "Fewest Transitions",
        [Graph.Policy.FEWEST_INTERACTIONS] = "Fewest Interactions",
        [Graph.Policy.CLOSEST_USEFUL] = "Closest Useful Landing",
    }
    return labels[policy] or policy or "Route"
end

-- Produce structured route explanations from graph edges and canonical source
-- evaluations.  The UI may format this data, but it must not infer readiness
-- or requirements from a localized action label.
function Graph:BuildRouteExplanation(pathResult, destinationName)
    pathResult = pathResult or {}
    local explanation = {
        policy = pathResult.policy,
        policyLabel = routePolicyLabel(pathResult.policy),
            destinationName = SafeString(destinationName)
                or (pathResult.destinationContext and SafeString(pathResult.destinationContext.name)),
        destinationResolved = pathResult.destinationContext == nil
            or pathResult.destinationContext.routeMapID ~= nil,
        waitTime = math.max(0, SafeNumber(pathResult.waitTime, 0)),
        cooldown = math.max(0, SafeNumber(pathResult.cooldown, 0)),
        reasons = {},
        sources = {},
        steps = {},
    }
    local seenSources = {}
    local seenReasons = {}
    for index, edge in ipairs(pathResult.path or {}) do
        local sourceState = edge.sourceState
        local sourceExplanation
        if sourceState and TA.TravelSources
            and type(TA.TravelSources.BuildExplanation) == "function" then
            sourceExplanation = TA.TravelSources.BuildExplanation(sourceState)
        elseif sourceState then
            sourceExplanation = {
                sourceType = edge.sourceType,
                sourceName = SafeString(sourceState.displayName) or SafeString(edge.name),
                sourceKey = sourceState.sourceKey or edge.sourceKey,
                actionType = sourceState.actionType or edge.actionType,
                actionID = sourceState.actionID or edge.actionID,
                destinationName = edge.destination
                    and (SafeString(edge.destination.displayName) or SafeString(edge.destination.name)),
                destinationResolved = SafeBoolean(edge.destinationResolved) == true,
                reason = sourceState.reason or edge.reason,
                reasonText = sourceState.reasonText or edge.reasonText,
                cooldown = edge.cooldown or 0,
                charges = sourceState.charges or edge.charges,
                interaction = sourceState.interactionRequired or sourceState.interaction,
                actionableNow = SafeBoolean(sourceState.actionableNow) == true,
            }
        end
        if sourceExplanation then
            local sourceKey = sourceExplanation.sourceKey
                or (tostring(sourceExplanation.actionType or "unknown") .. ":"
                    .. tostring(sourceExplanation.actionID or "unknown"))
            if not seenSources[sourceKey] then
                seenSources[sourceKey] = true
                explanation.sources[#explanation.sources + 1] = sourceExplanation
            end
        end

        local reason = edge.reason or (sourceState and sourceState.reason)
        local reasonText = edge.reasonText or (sourceState and sourceState.reasonText)
        if reason and not seenReasons[reason] then
            seenReasons[reason] = true
            explanation.reasons[#explanation.reasons + 1] = {
                code = reason,
                text = reasonText
                    or (TA.TravelSources and TA.TravelSources.GetReasonText
                        and TA.TravelSources:GetReasonText(reason))
                    or reason,
            }
        end

        local destination = edge.destination
        explanation.steps[#explanation.steps + 1] = {
            index = index,
            source = sourceExplanation,
            destinationName = destination
                and (SafeString(destination.displayName) or SafeString(destination.name)),
            destinationResolved = SafeBoolean(edge.destinationResolved) == true
                and (not destination or SafeBoolean(destination.resolved) ~= false),
            destinationUncertain = edge.destinationUncertain == true
                or (destination and destination.dynamic == true),
            actionableNow = SafeBoolean(edge.actionableNow) == true,
            reason = reason,
            reasonText = reasonText,
        }
    end

    if pathResult.found == false then
        explanation.rationale = "No route satisfies the selected policy."
    elseif pathResult.policy == Graph.Policy.BEST_NOW then
        explanation.rationale = "Selected the lowest-cost route that is ready and executable now."
    elseif pathResult.policy == Graph.Policy.BEST_IF_READY then
        explanation.rationale = "Selected the lowest movement-cost route, ignoring cooldown wait."
    elseif pathResult.policy == Graph.Policy.BEST_AFTER_WAIT then
        explanation.rationale = "Selected the lowest elapsed-time route, including required waiting."
    elseif pathResult.policy == Graph.Policy.FEWEST_TRANSITIONS then
        explanation.rationale = "Selected the route with the fewest transitions."
    elseif pathResult.policy == Graph.Policy.FEWEST_INTERACTIONS then
        explanation.rationale = "Selected the route with the fewest interactions."
    elseif pathResult.policy == Graph.Policy.CLOSEST_USEFUL then
        explanation.rationale = "Selected the closest explicit landing available."
    else
        explanation.rationale = "Selected by the active route policy."
    end
    return explanation
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ROUTE BUILDING
-- ═══════════════════════════════════════════════════════════════════════════

--[[
    FindRoutes - Evaluate the named route policies for one destination
    
    @param toMapID: Destination map ID
    @param options: {
        playerFaction: "Alliance" or "Horde"
        currentMapID: Player's current map ID
    }
    
    @return: { bestNow, bestIfReady, bestAfterWait, fewestTransitions,
        fewestInteractions, closestUseful, plus legacy available/optimal aliases }
]]
local function routeOptions(base, spec)
    local result = {}
    for key, value in pairs(base or {}) do result[key] = value end
    for key, value in pairs(spec or {}) do result[key] = value end
    return result
end

function Graph:FindClosestUsefulPath(toMapID, options)
    local targetNode = self:ResolveRoutingMap(toMapID)
    if not targetNode then return nil end
    local target = self:GetNode(targetNode)
    if not target then return nil end

    local candidates = {}
    for mapID, node in pairs(self.nodes) do
        if mapID ~= targetNode and (
            node.regionMapID == targetNode
            or node.landingMapID == targetNode
            or (target.regionMapID and node.regionMapID == target.regionMapID)
        ) then
            candidates[#candidates + 1] = mapID
        end
    end

    -- If no explicit landing alias exists, a hub on the target continent is
    -- the only safe useful fallback.  It is informational and approximate;
    -- this does not create a guessed edge to the exact destination.
    if #candidates == 0 then
        for mapID, node in pairs(self.nodes) do
            if mapID ~= targetNode and node.isHub and node.continent == target.continent then
                candidates[#candidates + 1] = mapID
            end
        end
    end

    local best
    for _, candidate in ipairs(candidates) do
        local candidateOptions = routeOptions(options, {
            policy = Graph.Policy.CLOSEST_USEFUL,
            onlyReady = true,
            includeWait = false,
        })
        local route = self:FindPath(Graph.PLAYER_NODE, candidate, candidateOptions)
        if route.found and (not best or route.estimatedSeconds < best.estimatedSeconds) then
            best = route
            best.usefulTargetMapID = candidate
            best.exactDestinationMapID = toMapID
            best.approximate = true
            best.confidence = "low"
            best.usefulLanding = true
        end
    end
    return best
end

function Graph:FindRoutes(toMapID, options)
    options = options or {}
    local base = {
        playerFaction = options.playerFaction,
        currentMapID = options.currentMapID,
        playerState = options.playerState or self.playerState,
        checkUnlock = options.checkUnlock ~= false,
    }

    local policies = {
        bestNow = {
            policy = Graph.Policy.BEST_NOW,
            onlyReady = true,
            includeWait = false,
        },
        bestIfReady = {
            policy = Graph.Policy.BEST_IF_READY,
            onlyReady = false,
            includeWait = false,
        },
        bestAfterWait = {
            policy = Graph.Policy.BEST_AFTER_WAIT,
            onlyReady = false,
            includeWait = true,
        },
        fewestTransitions = {
            policy = Graph.Policy.FEWEST_TRANSITIONS,
            onlyReady = true,
            includeWait = false,
            objective = "transitions",
        },
        fewestInteractions = {
            policy = Graph.Policy.FEWEST_INTERACTIONS,
            onlyReady = true,
            includeWait = false,
            objective = "interactions",
        },
    }

    local result = { policies = {} }
    for name, spec in pairs(policies) do
        result.policies[name] = self:FindPath(
            Graph.PLAYER_NODE,
            toMapID,
            routeOptions(base, spec)
        )
        result[name] = result.policies[name]
    end

    -- Compatibility aliases retained for the existing UI and integrations.
    result.available = result.bestNow
    result.optimal = result.bestIfReady
    result.closestUseful = self:FindClosestUsefulPath(toMapID, routeOptions(base, {
        policy = Graph.Policy.CLOSEST_USEFUL,
    }))
    return result
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PATH FORMATTING
-- ═══════════════════════════════════════════════════════════════════════════

function Graph:FormatPath(pathResult)
    if not pathResult.found then
        return {
            method = "No route found",
            description = "Unable to find a path to this destination",
            steps = 0,
            totalTime = 0,
            edges = {},
            stepDetails = {},
            policy = pathResult.policy,
            reason = pathResult.reason,
            confidence = pathResult.confidence or "low",
        }
    end
    
    if #pathResult.path == 0 then
        return {
            method = "You are already here!",
            description = "You are already at this destination",
            steps = 0,
            totalTime = 0,
            edges = {},
            stepDetails = {},
            policy = pathResult.policy,
            confidence = pathResult.confidence or "high",
        }
    end
    
    local methodParts = {}
    local descParts = {}
    local step = 1
    
    local stepDetails = {}
    local function durationString(seconds)
        local value = math.max(0, math.floor(SafeNumber(seconds, 0)))
        local mins = math.floor(value / 60)
        local secs = value % 60
        if mins > 0 then return string.format("~%dm %ds", mins, secs) end
        return string.format("~%ds", secs)
    end

    local modeLabels = {
        [Graph.EdgeType.WALK] = "Walk",
        [Graph.EdgeType.RIDE] = "Ride",
        [Graph.EdgeType.FLIGHT] = "Fly",
        [Graph.EdgeType.FLIGHT_PATH] = "Take flight path",
        [Graph.EdgeType.TAXI] = "Take taxi",
        [Graph.EdgeType.PORTAL] = "Take portal",
        [Graph.EdgeType.PORTAL_ROOM] = "Move through portal room",
        [Graph.EdgeType.BOAT] = "Take boat",
        [Graph.EdgeType.ZEPPELIN] = "Take zeppelin",
        [Graph.EdgeType.FERRY] = "Take ferry",
        [Graph.EdgeType.DUNGEON_LANDING] = "Enter dungeon landing",
        [Graph.EdgeType.EXTERNAL] = "Arrange external interaction",
    }

    for index, edge in ipairs(pathResult.path) do
        local edgeName = edge.name or edge.type
        local mode = self:GetTravelMode(edge)
        local toNode = self:GetNode(edge.to)
        local toName = toNode and toNode.name or ("Zone " .. edge.to)

        local edgeCost = self:CalculateEdgeCost(edge, edge.from, { includeWait = false })
        local label = modeLabels[mode] or edgeName
        local targetKind = edge.targetKind or (edge.destination and edge.destination.targetKind)
            or (toNode and toNode.targetKind) or "region"
        local confidence = edge.confidence or (edge.approximate and "low" or "medium")
        local qualifier = edge.approximate and " (approximate)" or ""
        methodParts[#methodParts + 1] = label .. " to " .. toName .. " ("
            .. durationString(edgeCost) .. ")"

        local description
        if edge.externalInteraction or mode == Graph.EdgeType.EXTERNAL then
            description = step .. ". Arrange " .. (edge.interaction or "an external interaction")
                .. " to reach " .. toName
        elseif edge.isPlayerEdge then
            description = step .. ". Use " .. edgeName .. " to reach " .. toName
        else
            description = step .. ". " .. label .. " to " .. toName
        end
        descParts[#descParts + 1] = description .. qualifier

        stepDetails[#stepDetails + 1] = {
            index = index,
            from = edge.from,
            to = edge.to,
            mode = mode,
            travelMode = mode,
            name = edgeName,
            destinationName = toName,
            targetKind = targetKind,
            targetIdentity = edge.targetIdentity or edge.destination,
            cost = edgeCost,
            estimated = edge.estimated ~= false,
            approximate = edge.approximate == true,
            confidence = confidence,
            actionableNow = SafeBoolean(edge.actionableNow) == true,
            access = edge.access,
            accessState = edge.accessState,
            requiresDiscovery = edge.requiresDiscovery,
            interaction = edge.interaction,
            requirements = edge.requirements,
            instanceMapID = edge.instanceMapID or (edge.destination and edge.destination.instanceMapID),
            entranceMapID = edge.entranceMapID or (edge.destination and edge.destination.entranceMapID),
            landingMapID = edge.landingMapID or (edge.destination and edge.destination.landingMapID),
            regionMapID = edge.regionMapID or (edge.destination and edge.destination.regionMapID),
        }
    end
    
    -- Format total time
    local totalSeconds = pathResult.estimatedSeconds or pathResult.totalCost or 0
    local totalSecs = math.floor(totalSeconds)
    local mins = math.floor(totalSecs / 60)
    local secs = totalSecs % 60
    local timeStr
    if mins > 0 then
        timeStr = string.format("~%dm %ds", mins, secs)
    else
        timeStr = string.format("~%ds", secs)
    end
    
    return {
        method = table.concat(methodParts, " -> "),
        description = table.concat(descParts, "\n"),
        steps = #pathResult.path,
        totalTime = totalSeconds,
        timeString = timeStr,
        edges = pathResult.path,
        nodes = pathResult.nodes,
        stepDetails = stepDetails,
        policy = pathResult.policy,
        waitTime = pathResult.waitTime or 0,
        movementCost = pathResult.movementCost or totalSeconds,
        estimated = pathResult.estimated ~= false,
        approximate = pathResult.approximate == true,
        confidence = pathResult.confidence or "medium",
        transitionCount = pathResult.transitionCount or #pathResult.path,
        interactionCount = pathResult.interactionCount or 0,
    }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

function Graph:Initialize()
    if self.initialized then return end
    
    -- Clear existing data
    self.nodes = {}
    self.dynamicNodes = {}
    self.edges = {}
    self.edgeIndex = {}
    self.playerEdges = {}
    self.playerSourceStates = {}
    self.playerState = nil
    self.topologyIssues = {}
    self._flightDistanceCache = {}
    self._lastRouteExclusions = {}
    
    -- Build nodes and edges from TravelData
    self:BuildFromTravelData()
    
    self.initialized = true
end

function Graph:BuildFromTravelData()
    local TD = TA.TravelData
    if not TD then return end

    local function listContains(list, wanted)
        if type(list) ~= "table" then return false end
        for _, value in pairs(list) do
            if value == wanted then return true end
        end
        return false
    end

    local function addIssue(code, fromMapID, toMapID, detail)
        self.topologyIssues = self.topologyIssues or {}
        self.topologyIssues[#self.topologyIssues + 1] = {
            code = code,
            from = fromMapID,
            to = toMapID,
            detail = detail,
        }
    end

    local function identityFor(mapID)
        return TD.MapIdentity and TD.MapIdentity[mapID] or {}
    end

    local function requirementsFor(record, fallback)
        local result = {}
        local base = record and record.requirements or fallback and fallback.requirements
        for key, value in pairs(base or {}) do result[key] = value end
        for _, key in ipairs({
            "faction", "class", "race", "specialization", "profession", "quest",
            "reputation", "expansion", "unlock", "discovery", "phase",
        }) do
            if record and record[key] ~= nil then result[key] = record[key] end
            if result[key] == nil and fallback and fallback[key] ~= nil then result[key] = fallback[key] end
        end
        -- Static-edge `location` is provenance such as "hub-map-key" or
        -- "source-map-key", not a player-location requirement.  A real
        -- location restriction must be declared in `requirements.location`
        -- (or explicitly as `locationID`) so metadata cannot make every
        -- portal unusable outside a literal marker string.
        if result.location == nil then
            if record and record.locationID ~= nil then
                result.location = record.locationID
            elseif fallback and fallback.locationID ~= nil then
                result.location = fallback.locationID
            end
        end
        return result
    end

    local function addDataNode(mapID, data)
        if not self:IsValidMapID(mapID) then return false end
        data = data or {}
        local identity = identityFor(mapID)
        data.identity = identity
        data.kind = data.kind or identity.kind or "region"
        data.targetKind = data.targetKind or identity.targetKind or data.kind
        data.regionMapID = data.regionMapID or identity.regionMapID
        data.entranceMapID = data.entranceMapID or identity.entranceMapID
        data.instanceMapID = data.instanceMapID or identity.instanceMapID
        data.landingMapID = data.landingMapID or identity.landingMapID
        data.identityKey = data.identityKey or identity.identityKey
        data.identityConfidence = data.identityConfidence or identity.identityConfidence
        data.requirements = data.requirements or identity.requirements
        if not self.nodes[mapID] then
            self:AddNode(mapID, data)
        end
        return true
    end

    -- Add nodes from authoritative coordinates first.
    if TD.ZoneCoordinates then
        for mapID, coords in pairs(TD.ZoneCoordinates) do
            local identity = identityFor(mapID)
            addDataNode(mapID, {
                name = TD.ZoneNameToID and self:GetZoneName(mapID) or ("Zone " .. mapID),
                continent = coords.continent,
                x = coords.x,
                y = coords.y,
                kind = identity.kind or "region",
                targetKind = identity.targetKind or identity.kind or "region",
                isPortalOnly = listContains(TD.PortalOnlyZones, mapID),
            })
        end
    end

    -- Identity records and localized-name records can define routable maps
    -- even when no coordinate estimate is available.
    if TD.MapIdentity then
        for mapID, identity in pairs(TD.MapIdentity) do
            if not identity.alias then
                addDataNode(mapID, {
                    name = identity.name,
                    continent = identity.continent or identity.continentID,
                    x = identity.x,
                    y = identity.y,
                    kind = identity.kind,
                    targetKind = identity.targetKind,
                    isHub = identity.kind == "hub",
                    isPortalOnly = identity.portalOnly == true,
                })
            end
        end
    end
    if TD.ZoneNameToID then
        for name, mapID in pairs(TD.ZoneNameToID) do
            if self:IsValidMapID(mapID) and not self.nodes[mapID] then
                addDataNode(mapID, { name = name })
            end
        end
    end

    -- Ensure fixed source destinations have nodes without turning mapID 0 or
    -- dynamic choices into graph destinations.
    for _, category in ipairs({
        "MageTeleports", "MagePortals", "ClassTeleports", "DungeonTeleports",
        "TeleportItems", "TeleportToys", "RacialTeleports",
    }) do
        for _, source in ipairs(TD[category] or {}) do
            local mapID = source.landingMapID or source.destinationMapID
                or source.regionMapID or source.mapID
            if self:IsValidMapID(mapID) then
                addDataNode(mapID, {
                    name = source.zone or source.destination or source.name,
                    continent = source.continent,
                    kind = source.targetKind or source.destinationKind or "region",
                    targetKind = source.targetKind or source.destinationKind,
                    instanceMapID = source.instanceMapID,
                    entranceMapID = source.entranceMapID,
                    landingMapID = source.landingMapID,
                    regionMapID = source.regionMapID,
                    identityKey = source.instanceKey,
                    identityConfidence = source.identityConfidence,
                })
            end
        end
    end
    
    -- Add portal hub nodes and their portal edges
    if TD.PortalHubs then
        for _, hub in ipairs(TD.PortalHubs) do
            local hubIdentity = identityFor(hub.mapID)
            local hubRequirements = requirementsFor(hub)
            -- Ensure hub node exists
            if not self.nodes[hub.mapID] then
                addDataNode(hub.mapID, {
                    name = hub.name,
                    faction = hub.faction,
                    isHub = true,
                    kind = hub.kind or "hub",
                    targetKind = hub.targetKind or "hub",
                    isPortalOnly = hub.portalOnly or false,
                    x = hub.x or 50,
                    y = hub.y or 50,
                    identity = hubIdentity,
                    requirements = hubRequirements,
                })
            else
                -- Update existing node to mark as hub
                self.nodes[hub.mapID].isHub = true
                self.nodes[hub.mapID].name = hub.name
                self.nodes[hub.mapID].kind = hub.kind or self.nodes[hub.mapID].kind or "hub"
                self.nodes[hub.mapID].targetKind = hub.targetKind or "hub"
                self.nodes[hub.mapID].requirements = hubRequirements
                if hub.faction then
                    self.nodes[hub.mapID].faction = hub.faction
                end
                if hub.portalOnly then
                    self.nodes[hub.mapID].isPortalOnly = true
                end
            end
            
            -- Add portal edges from this hub
            if hub.portalsTo then
                for _, portal in ipairs(hub.portalsTo) do
                    -- Ensure destination node exists
                    addDataNode(portal.mapID, {
                        name = portal.name,
                        faction = portal.faction,
                        kind = portal.kind or "region",
                        targetKind = portal.targetKind or portal.kind or "region",
                        continent = portal.continent,
                    })
                    
                    -- Add portal edge
                    self:AddEdge({
                        from = hub.mapID,
                        to = portal.mapID,
                        type = Graph.EdgeType.PORTAL,
                        mode = portal.mode or Graph.EdgeType.PORTAL_ROOM,
                        name = portal.name,
                        cost = portal.cost or Graph.BaseCost[Graph.EdgeType.PORTAL_ROOM],
                        timing = portal.timing or { travel = portal.travelTime },
                        faction = portal.faction or hub.faction,
                        requirements = requirementsFor(portal, { requirements = hubRequirements }),
                        confidence = portal.confidence or "medium",
                        approximate = portal.approximate == true,
                        targetKind = portal.targetKind or portal.kind or "region",
                        targetIdentity = portal.identityKey,
                        interaction = portal.interaction or "portal-room",
                        location = portal.location,
                        access = portal.access,
                        accessState = portal.accessState,
                        availability = portal.availability,
                        actionability = portal.actionability,
                        provenance = portal.provenance,
                        evidence = portal.evidence,
                        actionableNow = portal.actionability == "informational-only"
                            and false or portal.actionableNow,
                        executable = portal.executable == true and portal.actionableNow == true,
                        sourceHubMapID = hub.mapID,
                    })
                end
            end
        end
    end
    
    -- Add continent zone associations
    if TD.ContinentZones then
        for continentID, zones in pairs(TD.ContinentZones) do
            for _, zoneID in ipairs(zones) do
                if self.nodes[zoneID] then
                    self.nodes[zoneID].continent = continentID
                end
            end
        end
    end

    -- Consume only explicit topology.  Numeric entries remain supported for
    -- older data, but are normalized to approximate flight-path transitions;
    -- no direct same-continent edge is generated here or during pathfinding.
    if TD.ZoneConnections then
        local function edgeTypeForMode(mode, rawType)
            local value = mode or rawType
            if value == "walking" or value == "walk" then return Graph.EdgeType.WALK end
            if value == "riding" or value == "ride" then return Graph.EdgeType.RIDE end
            if value == "flightpath" then return Graph.EdgeType.FLIGHT_PATH end
            if value == "taxi" then return Graph.EdgeType.TAXI end
            if value == "boat" then return Graph.EdgeType.BOAT end
            if value == "zeppelin" then return Graph.EdgeType.ZEPPELIN end
            if value == "ferry" then return Graph.EdgeType.FERRY end
            if value == "portal-room" then return Graph.EdgeType.PORTAL_ROOM end
            if value == "external-interaction" then return Graph.EdgeType.EXTERNAL end
            if value == "flight" then return Graph.EdgeType.FLIGHT end
            return rawType or Graph.EdgeType.FLIGHT_PATH
        end

        for fromMapID, connections in pairs(TD.ZoneConnections) do
            if not self:HasNode(fromMapID) then
                addIssue("missing-source-node", fromMapID, nil, "ZoneConnections source is not a graph node")
            else
                for _, rawConnection in ipairs(connections or {}) do
                    local connection
                    if type(rawConnection) == "number" then
                        connection = { to = rawConnection, type = Graph.EdgeType.FLIGHT_PATH,
                            mode = "flightpath", confidence = "low", approximate = true }
                    else
                        connection = rawConnection
                    end
                    if type(connection) == "table" then
                        local toMapID = connection.to or connection.mapID or connection.destinationMapID
                        if not self:IsValidMapID(toMapID) or not self:HasNode(toMapID) then
                            addIssue("missing-destination-node", fromMapID, toMapID,
                                "ZoneConnections destination is not a graph node")
                        else
                            local mode = connection.mode or connection.travelMode or connection.type
                            local edgeType = edgeTypeForMode(mode, connection.type)
                            local uncertainAccess = connection.accessState == "unknown"
                                or mode == "flightpath" or mode == "taxi"
                            local accessState = connection.accessState
                                or (uncertainAccess and "unknown" or "ready")
                            local actionableNow = connection.actionableNow
                            if actionableNow == nil then actionableNow = not uncertainAccess end
                            if connection.actionability == "informational-only" then
                                actionableNow = false
                            end
                            local edgeData = {
                                from = fromMapID,
                                to = toMapID,
                                type = edgeType,
                                mode = mode or edgeType,
                                name = connection.name or ("Travel to " .. self:GetZoneName(toMapID)),
                                cost = connection.cost,
                                timing = connection.timing,
                                requirements = requirementsFor(connection),
                                faction = connection.faction,
                                confidence = connection.confidence or "low",
                                approximate = connection.approximate ~= false,
                                estimated = connection.estimated ~= false,
                                actionableNow = actionableNow,
                                executable = connection.executable == true and actionableNow,
                                interaction = connection.interaction or "player",
                                access = connection.access or (uncertainAccess and "conditional" or "unrestricted"),
                                accessState = accessState,
                                location = connection.location,
                                availability = connection.availability,
                                actionability = connection.actionability,
                                provenance = connection.provenance,
                                evidence = connection.evidence,
                                requiresDiscovery = connection.requiresDiscovery == true or uncertainAccess,
                                reason = connection.reason or (uncertainAccess and "access-unknown" or nil),
                                targetKind = connection.targetKind,
                                targetIdentity = connection.identityKey,
                                landingMapID = connection.landingMapID,
                                regionMapID = connection.regionMapID,
                                bidirectional = connection.bidirectional == true,
                            }
                            self:AddEdge(edgeData)
                            if connection.bidirectional == true then
                                local reverse = {}
                                for key, value in pairs(edgeData) do reverse[key] = value end
                                reverse.from = toMapID
                                reverse.to = fromMapID
                                reverse.name = connection.reverseName or ("Travel to " .. self:GetZoneName(fromMapID))
                                reverse.derived = true
                                reverse.bidirectional = false
                                self:AddEdge(reverse)
                            end
                        end
                    end
                end
            end
        end
    end
end

function Graph:GetZoneName(mapID)
    local TD = TA.TravelData
    if TD.ZoneNameToID then
        for name, id in pairs(TD.ZoneNameToID) do
            if id == mapID then
                -- Convert key to display name
                return name:gsub("^%l", string.upper):gsub("_", " ")
            end
        end
    end
    
    -- Try to get from WoW API
    local mapAPI = _G.C_Map
    if mapAPI and type(mapAPI.GetMapInfo) == "function" then
        local ok, mapInfo = safeGraphCall(mapAPI.GetMapInfo, mapID)
        if ok and type(mapInfo) == "table" and not IsSecretValue(mapInfo) then
            return SafeString(mapInfo.name)
        end
    end
    
    return "Zone " .. mapID
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLAYER EDGE SCANNING
-- ═══════════════════════════════════════════════════════════════════════════

-- Convert one canonical source evaluation into a dynamic graph edge.  The
-- source evaluation remains the authority for requirements, actionability,
-- destination resolution, and secure-action metadata.
function Graph:AddPlayerEdgeFromSourceState(sourceState)
    if type(sourceState) ~= "table" or sourceState.routeEligible == false then
        return nil
    end

    local source = sourceState.source
    local destination = sourceState.destination
    if type(source) ~= "table" or type(destination) ~= "table"
        or destination.resolved ~= true or not self:IsValidMapID(destination.mapID) then
        return nil
    end

    local destinationMapID = destination.mapID
    if not self:HasNode(destinationMapID) then
        local mapAPI = _G.C_Map
        local info
        if mapAPI and type(mapAPI.GetMapInfo) == "function" then
            local ok, value = safeGraphCall(mapAPI.GetMapInfo, destinationMapID)
            if ok then info = value end
        end
        local coords = TA.TravelData and TA.TravelData.ZoneCoordinates
            and TA.TravelData.ZoneCoordinates[destinationMapID]
        self:AddDynamicNode(destinationMapID, {
            name = destination.displayName or destination.destinationName or (info and info.name),
            continent = coords and coords.continent,
            x = coords and coords.x,
            y = coords and coords.y,
            kind = destination.targetKind or destination.kind or "region",
            targetKind = destination.targetKind or destination.kind or "region",
            instanceMapID = destination.instanceMapID,
            entranceMapID = destination.entranceMapID,
            landingMapID = destination.landingMapID,
            regionMapID = destination.regionMapID,
            identityKey = destination.identityKey,
            identityConfidence = destination.identityConfidence,
        })
    end

    local actionType = sourceState.actionType
    local actionID = sourceState.actionID
    local edgeType = source.edgeType or source.kind or Graph.EdgeType.TELEPORT
    if not Graph.BaseCost[edgeType] then
        if source.kind == "hearthstone" then
            edgeType = Graph.EdgeType.HEARTHSTONE
        elseif source.kind == "portal" then
            edgeType = Graph.EdgeType.PORTAL
        elseif source.kind == "dungeon" then
            edgeType = Graph.EdgeType.DUNGEON
        elseif source.kind == "item" then
            edgeType = Graph.EdgeType.ITEM
        elseif source.kind == "toy" then
            edgeType = Graph.EdgeType.TOY
        else
            edgeType = Graph.EdgeType.TELEPORT
        end
    end
    local timing = sourceState.timing or source.timing or {}
    local sourceRequirements = source.requirements or {}
    local sourceLocation = sourceRequirements.location
    local edgeFrom = self:IsValidMapID(sourceLocation) and sourceLocation or Graph.PLAYER_NODE
    local mode = sourceState.externalInteraction and Graph.EdgeType.EXTERNAL
        or source.travelMode or source.mode or edgeType
    local edge = self:AddPlayerEdge({
        from = edgeFrom,
        to = destinationMapID,
        type = edgeType,
        mode = mode,
        name = sourceState.displayName or source.displayName or source.name,
        spellID = actionType == "spell" and actionID or source.spellID,
        itemID = (actionType == "item" or actionType == "toy") and actionID
            or source.itemID or source.toyID,
        cooldown = sourceState.cooldown or 0,
        charges = sourceState.charges,
        cost = sourceState.cost or source.cost,
        faction = sourceRequirements.faction,
        requirements = sourceRequirements,
        icon = sourceState.icon or source.icon,
        state = sourceState.state,
        reason = sourceState.reason,
        reasonText = sourceState.reasonText,
        actionableNow = sourceState.actionableNow,
        routeEligible = sourceState.routeEligible,
        destinationResolved = sourceState.destinationResolved,
        actionType = actionType,
        actionID = actionID,
        timing = timing,
        sourceKey = sourceState.sourceKey or source.key,
        source = source,
        sourceState = sourceState,
        sourceType = sourceState.sourceType or source.sourceFamily or source.kind or source.category,
        sourceID = sourceState.actionID or source.actionID or source.spellID or source.itemID,
        destination = destination,
        sourceFamily = sourceState.sourceFamily or source.sourceFamily,
        interaction = sourceState.interaction or source.interaction,
        interactionType = sourceState.interactionType or source.interactionType,
        externalInteraction = sourceState.externalInteraction,
        actionableByPlayer = sourceState.actionableByPlayer,
        destinationOptions = sourceState.destinationOptions,
        destinationUncertain = destination.dynamic == true or destination.resolved ~= true,
        confidence = sourceState.confidence or (destination.dynamic and "medium" or "high"),
        approximate = destination.dynamic == true or sourceState.confidence == "low",
        estimated = true,
        targetKind = sourceState.targetKind or destination.targetKind or destination.kind,
        targetIdentity = destination.identityKey or source.instanceKey,
        instanceMapID = destination.instanceMapID or source.instanceMapID,
        entranceMapID = destination.entranceMapID or source.entranceMapID,
        landingMapID = destination.landingMapID or source.landingMapID,
        regionMapID = destination.regionMapID or source.regionMapID,
    })
    return edge
end

function Graph:ScanCanonicalPlayerSources()
    if not TA.TravelSources then return {} end

    self:ClearPlayerEdges()
    local playerState = TA.TravelSources.CreatePlayerState()
    self.playerState = playerState
    -- EvaluateAll is the canonical discovery boundary; Discover is the
    -- public semantic alias used by integrations that want the same snapshot.
    self.playerSourceStates = TA.TravelSources.EvaluateAll(playerState)

    for _, sourceState in ipairs(self.playerSourceStates) do
        self:AddPlayerEdgeFromSourceState(sourceState)
    end

    return self.playerSourceStates
end

function Graph:GetPlayerSourceDiagnostics(destinationMapID)
    local diagnostics = {}
    for _, sourceState in ipairs(self.playerSourceStates or {}) do
        local destination = sourceState.destination or {}
        local matchesDestination = destinationMapID == nil or destination.mapID == destinationMapID
        if matchesDestination and sourceState.routeEligible == false and sourceState.reason then
            local destination = sourceState.destination or {}
            local explanation = TA.TravelSources
                and TA.TravelSources.BuildExplanation
                and TA.TravelSources.BuildExplanation(sourceState)
            diagnostics[#diagnostics + 1] = {
                sourceKey = sourceState.sourceKey,
                name = sourceState.displayName or (sourceState.source and sourceState.source.name),
                sourceType = sourceState.sourceType
                    or (sourceState.source and (sourceState.source.sourceFamily
                        or sourceState.source.kind or sourceState.source.category)),
                actionType = sourceState.actionType,
                actionID = sourceState.actionID,
                reason = sourceState.reason,
                reasonText = sourceState.reasonText,
                state = sourceState.state,
                cooldown = sourceState.cooldown or 0,
                charges = sourceState.charges,
                interaction = sourceState.interactionRequired or sourceState.interaction,
                requirements = sourceState.requirements
                    or (sourceState.source and sourceState.source.requirements),
                destinationName = destination.displayName or destination.name,
                destinationResolved = sourceState.destinationResolved,
                explanation = explanation,
            }
        end
    end
    table.sort(diagnostics, function(left, right)
        return tostring(left.name or left.sourceKey) < tostring(right.name or right.sourceKey)
    end)
    return diagnostics
end


-- Re-evaluate a rendered action immediately before an out-of-combat click.
-- The route snapshot remains useful for ranking, but secure actions must use
-- current spell/item/toy state when they are about to be configured.
function Graph:GetActionAvailability(actionType, actionID)
    if TA.TravelSources then
        local source = TA.TravelSources.FindByAction(actionType, actionID)
        if source then
            return TA.TravelSources.Evaluate(source, TA.TravelSources.CreatePlayerState())
        end
    end

    return {
        state = "unknown",
        reason = "unsupported-source",
        actionableNow = false,
        routeEligible = false,
    }
end

function Graph:GetSourceAvailability(sourceKey)
    if TA.TravelSources and sourceKey then
        local source = TA.TravelSources.FindByKey(sourceKey)
        if source then
            return TA.TravelSources.Evaluate(source, TA.TravelSources.CreatePlayerState())
        end
    end

    return {
        state = "unknown",
        reason = "unsupported-source",
        actionableNow = false,
        routeEligible = false,
    }
end


--[[
    ScanPlayerEdges - Scan all player-specific travel abilities and add as edges
    
    This should be called:
    - On addon load
    - When player learns new spells
    - When player acquires/loses items
    - Periodically to update cooldowns (before pathfinding)
]]
function Graph:ScanPlayerEdges()
    if TA.TravelSources then
        return self:ScanCanonicalPlayerSources()
    end

    return {}
end


-- Note: We use WoW's built-in tContains() function - don't redefine it!

-- ═══════════════════════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════════════════════

function Graph:DebugPrint()
    print("=== TravelGraph Debug ===")
    print("Nodes: " .. self:CountNodes())
    print("Edges: " .. #self.edges)
    print("Player Edges: " .. #self.playerEdges)
    
    print("\n--- Sample Nodes ---")
    local count = 0
    for mapID, node in pairs(self.nodes) do
        if count < 5 then
            print(string.format("  [%d] %s (continent=%s, hub=%s, portalOnly=%s)",
                mapID, node.name, tostring(node.continent), tostring(node.isHub), tostring(node.isPortalOnly)))
            count = count + 1
        end
    end
    
    print("\n--- Sample Edges ---")
    for i = 1, math.min(5, #self.edges) do
        local edge = self.edges[i]
        print(string.format("  %s -> %s [%s] cost=%s",
            tostring(edge.from), tostring(edge.to), edge.type, tostring(edge.cost)))
    end
end

function Graph:DebugPlayerEdges()
    print("=== Player Edges Debug ===")
    print("Total player edges: " .. #self.playerEdges)
    
    -- Show edges from PLAYER_NODE in the index
    local playerNodeEdges = self.edgeIndex[Graph.PLAYER_NODE]
    print("Edges indexed under PLAYER_NODE: " .. (playerNodeEdges and #playerNodeEdges or 0))
    
    print("\n--- All Player Edges ---")
    for i, edge in ipairs(self.playerEdges) do
        local destNode = self:GetNode(edge.to)
        local destName = destNode and destNode.name or ("Unknown mapID: " .. tostring(edge.to))
        local cdStr = edge.cooldown and edge.cooldown > 0 and string.format(" (CD: %ds)", edge.cooldown) or " (Ready)"
        print(string.format("  %d. [%s] %s -> %s%s", 
            i, edge.type or "?", edge.name or "?", destName, cdStr))
    end
    
    -- Specifically check hearthstones
    print("\n--- Hearthstone Edges ---")
    local hsCount = 0
    for _, edge in ipairs(self.playerEdges) do
        if edge.type == Graph.EdgeType.HEARTHSTONE then
            hsCount = hsCount + 1
            local destNode = self:GetNode(edge.to)
            local destName = destNode and destNode.name or ("Unknown mapID: " .. tostring(edge.to))
            print(string.format("  -> %s to %s (mapID: %s)", edge.name, destName, tostring(edge.to)))
        end
    end
    if hsCount == 0 then
        print("  No hearthstone edges found!")
        print("  Bind location: " .. (GetBindLocation() or "unknown"))
        local bindMapID
        if TA.TravelSources and TA.TravelSources.CreatePlayerState then
            local playerState = TA.TravelSources.CreatePlayerState()
            bindMapID = playerState and playerState.bindMapID
        end
        print("  Bind mapID: " .. tostring(bindMapID))
    end
end

-- Debug helper to check specific zones
function Graph:DebugZone(mapID)
    print("=== Zone Debug: " .. mapID .. " ===")
    local node = self:GetNode(mapID)
    if node then
        print(string.format("  Node: %s", node.name))
        print(string.format("  Continent: %s", tostring(node.continent)))
        print(string.format("  Portal Only: %s", tostring(node.isPortalOnly)))
        print(string.format("  Is Hub: %s", tostring(node.isHub)))
        print(string.format("  Coords: x=%s, y=%s", tostring(node.x), tostring(node.y)))
    else
        print("  Node NOT FOUND!")
    end
    
    -- Check edges from this zone
    local edges = self:GetEdgesFrom(mapID)
    print(string.format("  Edges FROM this zone: %d", #edges))
    for i, edge in ipairs(edges) do
        if i <= 5 then
            print(string.format("    -> %s [%s] cd=%s", tostring(edge.to), edge.type, tostring(edge.cooldown)))
        end
    end
    
    -- Check player edges TO this zone
    local playerEdgesToHere = 0
    for _, edge in ipairs(self.playerEdges) do
        if edge.to == mapID then
            playerEdgesToHere = playerEdgesToHere + 1
            print(string.format("  Player edge TO here: %s [%s] cd=%.0f", edge.name or "?", edge.type, edge.cooldown or 0))
        end
    end
    if playerEdgesToHere == 0 then
        print("  No player edges TO this zone")
    end
    
    -- Check if other zones can fly here
    print("  Zones that can fly to this zone:")
    local canFlyCount = 0
    local function hasExplicitFlightEdge(fromMapID)
        for _, edge in ipairs(self:GetEdgesFrom(fromMapID) or {}) do
            if edge.to == mapID
                and (edge.mode == Graph.EdgeType.FLIGHT or edge.mode == Graph.EdgeType.FLIGHT_PATH) then
                return true
            end
        end
        return false
    end
    for fromID, fromNode in pairs(self.nodes) do
        if fromID ~= mapID
            and (self:CanFlyBetween(fromID, mapID) or hasExplicitFlightEdge(fromID)) then
            canFlyCount = canFlyCount + 1
            if canFlyCount <= 10 then
                print(string.format("    - %s (%d)", fromNode.name or "Unknown", fromID))
            end
        end
    end
    print(string.format("  Total zones that can fly here: %d", canFlyCount))
    
    -- Specifically check key hub nodes
    local hubsToCheck = {
        { id = 1670, name = "Oribos" },
        { id = 715, name = "Emerald Dreamway" },
        { id = 84, name = "Stormwind" },
        { id = 85, name = "Orgrimmar" },
    }
    for _, hub in ipairs(hubsToCheck) do
        if mapID ~= hub.id then
            local hubNode = self:GetNode(hub.id)
            if hubNode then
                local canFly = self:CanFlyBetween(hub.id, mapID)
                local edges = self:GetEdgesFrom(hub.id)
                local hasPortalTo = false
                for _, edge in ipairs(edges) do
                    if edge.to == mapID then
                        hasPortalTo = true
                        break
                    end
                end
                print(string.format("  %s (%d): canFly=%s, hasPortal=%s, edges=%d", 
                    hub.name, hub.id, canFly and "Y" or "N", hasPortalTo and "Y" or "N", #edges))
            end
        end
    end
end

-- Debug route finding
function Graph:DebugRoute(fromMapID, toMapID)
    print(string.format("=== Route Debug: %d -> %d ===", fromMapID, toMapID))
    
    -- Check if both zones exist
    local fromNode = self:GetNode(fromMapID)
    local toNode = self:GetNode(toMapID)
    
    print(string.format("From node exists: %s", fromNode and "YES" or "NO"))
    print(string.format("To node exists: %s", toNode and "YES" or "NO"))
    
    if fromNode and toNode then
        print(string.format("From continent: %s", tostring(fromNode.continent)))
        print(string.format("To continent: %s", tostring(toNode.continent)))
        print(string.format("Can fly between: %s", self:CanFlyBetween(fromMapID, toMapID) and "YES" or "NO"))
        
        local distance = self:GetFlightDistance(fromMapID, toMapID)
        if distance then
            print(string.format("Flight distance: %.1f (cost: %.0fs)", distance, distance * Graph.FLIGHT_SPEED))
        else
            print("Flight distance: CANNOT CALCULATE")
        end
    end
    
    -- Try finding path
    local playerFaction = UnitFactionGroup("player") or "Both"
    
    print("\n--- Finding AVAILABLE route (onlyReady=true) ---")
    local available = self:FindPath(fromMapID, toMapID, { playerFaction = playerFaction, currentMapID = fromMapID, onlyReady = true })
    print(string.format("Found: %s, Cost: %.0f", tostring(available.found), available.totalCost))
    if available.found then
        print("Path nodes: " .. table.concat(available.nodes, " -> "))
    end
    
    print("\n--- Finding OPTIMAL route (onlyReady=false) ---")
    local optimal = self:FindPath(fromMapID, toMapID, { playerFaction = playerFaction, currentMapID = fromMapID, onlyReady = false })
    print(string.format("Found: %s, Cost: %.0f", tostring(optimal.found), optimal.totalCost))
    if optimal.found then
        print("Path nodes: " .. table.concat(optimal.nodes, " -> "))
    end
end

function Graph:CountNodes()
    local count = 0
    for _ in pairs(self.nodes) do
        count = count + 1
    end
    for mapID in pairs(self.dynamicNodes) do
        if not self.nodes[mapID] then count = count + 1 end
    end
    return count
end

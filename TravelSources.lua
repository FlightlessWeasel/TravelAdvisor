-- ═══════════════════════════════════════════════════════════════════════════
-- TravelAdvisor - Canonical travel source model
-- ═══════════════════════════════════════════════════════════════════════════

local _, TA = ...
TA = TA or _G.TravelAdvisor or {}
_G.TravelAdvisor = TA

local Sources = TA.TravelSources or {}
TA.TravelSources = Sources

local unpack = table.unpack or unpack

local C_Spell = _G.C_Spell
local C_SpellBook = _G.C_SpellBook
local C_Item = _G.C_Item
local C_Container = _G.C_Container
local C_Map = _G.C_Map

local CATEGORY_ORDER = {
    "MageTeleports",
    "MagePortals",
    "ClassTeleports",
    "DungeonTeleports",
    "Hearthstones",
    "TeleportItems",
    "TeleportToys",
    "RacialTeleports",
}

local CATEGORY_KIND = {
    MageTeleports = "teleport",
    MagePortals = "portal",
    ClassTeleports = "teleport",
    DungeonTeleports = "dungeon",
    Hearthstones = "hearthstone",
    TeleportItems = "item",
    TeleportToys = "toy",
    RacialTeleports = "teleport",
}

local CATEGORY_FAMILY = {
    MageTeleports = "mage-teleport",
    MagePortals = "mage-portal",
    ClassTeleports = "class-travel",
    DungeonTeleports = "dungeon-scenario",
    Hearthstones = "hearthstone",
    TeleportItems = "teleport-item",
    TeleportToys = "teleport-toy",
    RacialTeleports = "racial-travel",
}

local CATEGORY_INTERACTION = {
    -- A portal spell creates an interaction for another player; it is not a
    -- local teleport action that the secure button can execute for routing.
    MagePortals = "external-player",
}

local SOURCE_COVERAGE = {
    ["teleports"] = {
        status = "supported",
        categories = { "MageTeleports", "ClassTeleports", "DungeonTeleports" },
        discovery = "known-spell-api",
    },
    ["mage-portals"] = {
        status = "supported-informational",
        categories = { "MagePortals" },
        discovery = "known-spell-api",
        interaction = "external-player",
    },
    ["hearthstones"] = {
        status = "supported",
        categories = { "Hearthstones" },
        discovery = "bag-and-toy-api",
    },
    ["items"] = {
        status = "supported",
        categories = { "TeleportItems" },
        discovery = "bag-api",
    },
    ["toys"] = {
        status = "supported",
        categories = { "TeleportToys" },
        discovery = "toy-and-item-api",
    },
    ["class-racial-profession"] = {
        status = "supported",
        categories = { "ClassTeleports", "RacialTeleports", "TeleportItems" },
        discovery = "known-spell-and-profession-api",
    },
    ["portal-hubs"] = {
        status = "supported-static",
        categories = {},
        discovery = "curated-travel-data",
    },
    ["boats-zeppelins-ferries-taxis"] = {
        status = "informational-only",
        categories = {},
        discovery = "no-reliable-player-source-scanner",
        reason = "Transport access and schedules are not inferred without authoritative data.",
    },
}

local REASONS = {
    READY = "ready",
    ON_COOLDOWN = "on-cooldown",
    NO_CHARGES = "no-charges",
    NOT_KNOWN = "not-known",
    NOT_OWNED = "not-owned",
    NOT_COLLECTED = "not-collected",
    INSUFFICIENT_QUANTITY = "insufficient-quantity",
    UNUSABLE = "unusable",
    DISABLED = "disabled",
    REQUIREMENTS_NOT_MET = "requirements-not-met",
    WRONG_CLASS = "wrong-class",
    WRONG_RACE = "wrong-race",
    WRONG_FACTION = "wrong-faction",
    WRONG_PROFESSION = "wrong-profession",
    WRONG_SPECIALIZATION = "wrong-specialization",
    MISSING_QUEST = "missing-quest",
    MISSING_REPUTATION = "missing-reputation",
    UNUSABLE_LOCATION = "unusable-location",
    DESTINATION_UNRESOLVED = "destination-unresolved",
    UNSUPPORTED_SOURCE = "unsupported-source",
    API_UNAVAILABLE = "api-unavailable",
    USABILITY_UNKNOWN = "usability-unknown",
    EXTERNAL_INTERACTION = "external-interaction",
    SETUP_ONLY = "setup-only",
    INSUFFICIENT_PROFESSION_SKILL = "insufficient-profession-skill",
    MISSING_DISCOVERY = "missing-discovery",
    WRONG_PHASE = "wrong-phase",
    INVALID_SOURCE = "invalid-source",
}

local REASON_TEXT = {
    [REASONS.READY] = "Ready",
    [REASONS.ON_COOLDOWN] = "On cooldown",
    [REASONS.NO_CHARGES] = "No charges",
    [REASONS.NOT_KNOWN] = "Spell not known",
    [REASONS.NOT_OWNED] = "Item not owned",
    [REASONS.NOT_COLLECTED] = "Toy not collected",
    [REASONS.INSUFFICIENT_QUANTITY] = "Insufficient quantity",
    [REASONS.UNUSABLE] = "Currently unusable",
    [REASONS.DISABLED] = "Disabled",
    [REASONS.REQUIREMENTS_NOT_MET] = "Requirements not met",
    [REASONS.WRONG_CLASS] = "Wrong class",
    [REASONS.WRONG_RACE] = "Wrong race",
    [REASONS.WRONG_FACTION] = "Wrong faction",
    [REASONS.WRONG_PROFESSION] = "Profession requirement not met",
    [REASONS.WRONG_SPECIALIZATION] = "Specialization requirement not met",
    [REASONS.MISSING_QUEST] = "Required quest not completed",
    [REASONS.MISSING_REPUTATION] = "Required reputation not met",
    [REASONS.UNUSABLE_LOCATION] = "Cannot use in this location",
    [REASONS.DESTINATION_UNRESOLVED] = "Destination unresolved",
    [REASONS.UNSUPPORTED_SOURCE] = "Unsupported travel source",
    [REASONS.API_UNAVAILABLE] = "Game API unavailable",
    [REASONS.USABILITY_UNKNOWN] = "Usability unknown",
    [REASONS.EXTERNAL_INTERACTION] = "Requires another player or external interaction",
    [REASONS.SETUP_ONLY] = "Setup action only",
    [REASONS.INSUFFICIENT_PROFESSION_SKILL] = "Profession skill requirement not met",
    [REASONS.MISSING_DISCOVERY] = "Travel path not discovered",
    [REASONS.WRONG_PHASE] = "Unavailable in the current phase",
    [REASONS.INVALID_SOURCE] = "Invalid travel source",
}

Sources.Reasons = REASONS
Sources.REASON = REASONS
Sources.ReasonText = REASON_TEXT
Sources.REASON_TEXT = REASON_TEXT
Sources.SourceCoverage = SOURCE_COVERAGE
Sources.SOURCE_COVERAGE = SOURCE_COVERAGE

-- Retail can return secret values in restricted content.  Secret values are
-- displayable by Blizzard-owned widgets, but addon code must not inspect,
-- compare, convert, concatenate, or persist them.  Keep all addon-owned
-- state ordinary and let callers treat a secret result as unavailable.
local function isSecretValue(value)
    if value == nil then return false end
    local checker = _G.issecretvalue
    if type(checker) ~= "function" then return false end
    local ok, secret = pcall(checker, value)
    return ok and secret == true
end

local function safeNumber(value)
    if value == nil or isSecretValue(value) then return nil end
    local ok, number = pcall(tonumber, value)
    if not ok or number == nil or isSecretValue(number) or type(number) ~= "number" then
        return nil
    end
    return number
end

local function safeBoolean(value)
    if value == nil or isSecretValue(value) then return nil end
    return value == true
end

local function safeString(value)
    if value == nil or isSecretValue(value) or type(value) ~= "string" then return nil end
    return value ~= "" and value or nil
end

local function safeDisplayValue(value)
    if value == nil or isSecretValue(value) then return nil end
    if type(value) == "string" then
        return value ~= "" and value or nil
    end
    if type(value) == "number" then
        return value > 0 and value or nil
    end
    return nil
end

local function safeKeyPart(value)
    if value == nil or isSecretValue(value) then return nil end
    if type(value) == "string" or type(value) == "number" then
        return tostring(value)
    end
    return nil
end

Sources.IsSecretValue = isSecretValue
Sources.SafeNumber = safeNumber
Sources.SafeBoolean = safeBoolean
Sources.SafeString = safeString

function Sources:GetReasonText(reason)
    return REASON_TEXT[reason] or reason or "Unknown"
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
    if ok then return true, a, b, c, d, e, f, g, h, i end
    return false
end

local function firstNonNil(...)
    local values = { ... }
    for i = 1, select("#", ...) do
        if values[i] ~= nil then return values[i] end
    end
    return nil
end

local function copyValue(value, depth, opaque)
    if isSecretValue(value) then return nil end
    if type(value) ~= "table" then return value end
    if value == _G or (type(opaque) == "table" and value == opaque) then return value end
    depth = depth or 0
    if depth > 8 then return nil end

    local result = {}
    local pairsOK, iterator, state, control = pcall(pairs, value)
    if not pairsOK or type(iterator) ~= "function" then return nil end
    while true do
        local nextOK, key, child = pcall(iterator, state, control)
        if not nextOK or key == nil then break end
        control = key
        if not isSecretValue(key) and not isSecretValue(child)
            and type(key) ~= "function" and type(child) ~= "function" then
            local childOK, copied = pcall(copyValue, child, depth + 1, opaque)
            if childOK and copied ~= nil then result[key] = copied end
        end
    end
    return result
end

local function copyState(state, api)
    api = api or (state and state.api)
    local copied = copyValue(state, 0, api) or {}
    copied.api = api or copied.api or _G
    return copied
end

function Sources:GetCoverage()
    return copyValue(SOURCE_COVERAGE)
end

local function normalizeText(value)
    value = safeString(value)
    if not value then return nil end
    return value:lower():gsub("%s+", ""):gsub("['`%-]", "")
end

local function professionKey(value)
    return normalizeText(value)
end

local function isPositiveMapID(value)
    value = safeNumber(value)
    return value ~= nil and value > 0
end

local function asList(value)
    if value == nil then return nil end
    if type(value) == "table" then return value end
    return { value }
end

local function contains(value, wanted)
    if isSecretValue(value) or isSecretValue(wanted) then return nil end
    if value == nil then return true end
    if type(value) == "string" or type(value) == "number" then
        if type(value) == "string" and type(wanted) == "string" then
            return value == wanted or value:lower() == wanted:lower()
        end
        return value == wanted
    end
    if type(value) ~= "table" then return false end
    for key, item in pairs(value) do
        if contains(item, wanted) or contains(key, wanted) then return true end
    end
    return false
end

local function getData(data)
    if data then return data end
    return TA.TravelData or _G.TravelData or {}
end

local function currentTime(state)
    if state then
        local value = safeNumber(state.now)
        if value ~= nil then return value end
    end
    if type(_G.GetTime) == "function" then
        local ok, value = safeCall(_G.GetTime)
        if ok then
            value = safeNumber(value)
            if value ~= nil then return value end
        end
    end
    return 0
end

local function getUnitClass()
    if type(_G.UnitClass) ~= "function" then return nil end
    local ok, localized, token = safeCall(_G.UnitClass, "player")
    if ok then return safeString(token) or safeString(localized) end
    return nil
end

local function getUnitRace()
    if type(_G.UnitRace) ~= "function" then return nil end
    local ok, localized, token = safeCall(_G.UnitRace, "player")
    if ok then return safeString(token) or safeString(localized) end
    return nil
end

local function getFaction()
    if type(_G.UnitFactionGroup) == "function" then
        local ok, faction = safeCall(_G.UnitFactionGroup, "player")
        if ok then return safeString(faction) end
    end
    return nil
end

local function spellKnown(spellID, state)
    if state then
        for _, knownTable in ipairs({
            state.spells,
            state.knownSpells,
            state.spellbook,
            state.knownSpellIDs,
            state.spellKnowledge,
        }) do
            if knownTable and knownTable[spellID] ~= nil then
                return safeBoolean(knownTable[spellID])
            end
        end
    end

    local api = state and state.api or _G
    local spellBook = api.C_SpellBook or C_SpellBook
    if spellBook and type(spellBook.IsSpellKnown) == "function" then
        local ok, known = safeCall(spellBook.IsSpellKnown, spellID)
        if ok then
            local value = safeBoolean(known)
            if value ~= nil then return value end
        end
    end
    local spellAPI = api.C_Spell or C_Spell
    if spellAPI and type(spellAPI.IsSpellKnown) == "function" then
        local ok, known = safeCall(spellAPI.IsSpellKnown, spellID)
        if ok then
            local value = safeBoolean(known)
            if value ~= nil then return value end
        end
    end
    if type(api.IsSpellKnown) == "function" then
        local ok, known = safeCall(api.IsSpellKnown, spellID)
        if ok then
            local value = safeBoolean(known)
            if value ~= nil then return value end
        end
    end
    if type(api.IsPlayerSpell) == "function" then
        local ok, known = safeCall(api.IsPlayerSpell, spellID)
        if ok then
            local value = safeBoolean(known)
            if value ~= nil then return value end
        end
    end
    return nil
end

local function toyKnown(itemID, state)
    if state and state.toys and state.toys[itemID] ~= nil then
        return safeBoolean(state.toys[itemID])
    end
    if state and state.knownToys and state.knownToys[itemID] ~= nil then
        return safeBoolean(state.knownToys[itemID])
    end

    local api = state and state.api or _G
    if type(api.PlayerHasToy) == "function" then
        local ok, known = safeCall(api.PlayerHasToy, itemID)
        if ok then return safeBoolean(known) end
    end
    return nil
end

local function itemQuantities(itemID, state)
    if state and state.items and state.items[itemID] ~= nil then
        local value = state.items[itemID]
        if isSecretValue(value) then return nil, nil end
        if type(value) == "table" then
            local bagCount = safeNumber(firstNonNil(value.bagCount, value.inventoryCount, value.count))
            if bagCount == nil and value.owned ~= nil then
                local owned = safeBoolean(value.owned)
                if owned ~= nil then bagCount = owned and 1 or 0 end
            end
            return bagCount, safeNumber(firstNonNil(value.bankCount, value.bank))
        end
        return safeNumber(value) or 0, nil
    end

    local api = state and state.api or _G
    local itemAPI = api.C_Item or C_Item
    if itemAPI and type(itemAPI.GetItemCount) == "function" then
        local bagOK, bagCount = safeCall(itemAPI.GetItemCount, itemID, false, true, false, false)
        local totalOK, totalCount = safeCall(itemAPI.GetItemCount, itemID, true, true, false, false)
        bagCount = bagOK and safeNumber(bagCount) or nil
        totalCount = totalOK and safeNumber(totalCount) or nil
        if bagCount ~= nil then
            local bankCount = totalCount and math.max(0, totalCount - bagCount) or nil
            return bagCount, bankCount
        end
    end
    if type(api.GetItemCount) == "function" then
        local bagOK, bagCount = safeCall(api.GetItemCount, itemID, false, true, false, false)
        local totalOK, totalCount = safeCall(api.GetItemCount, itemID, true, true, false, false)
        bagCount = bagOK and safeNumber(bagCount) or nil
        totalCount = totalOK and safeNumber(totalCount) or nil
        if bagCount ~= nil then
            local bankCount = totalCount and math.max(0, totalCount - bagCount) or nil
            return bagCount, bankCount
        end
    end
    return nil, nil
end

local function itemCount(itemID, state)
    local bagCount = itemQuantities(itemID, state)
    return bagCount
end

local function itemBankCount(itemID, state)
    local _, bankCount = itemQuantities(itemID, state)
    return bankCount
end

local function getSpellOverride(spellID, source, state)
    local explicit = firstNonNil(source.overrideSpellID, source.spellOverrideID, source.spellOverride)
    explicit = safeNumber(explicit)
    if explicit and explicit > 0 then return explicit end

    local api = state and state.api or _G
    local spellAPI = api.C_Spell or C_Spell
    if spellAPI and type(spellAPI.GetOverrideSpell) == "function" then
        local ok, override = safeCall(spellAPI.GetOverrideSpell, spellID)
        override = ok and safeNumber(override) or nil
        if override and override > 0 then return override end
    end
    if type(api.GetOverrideSpell) == "function" then
        local ok, override = safeCall(api.GetOverrideSpell, spellID)
        override = ok and safeNumber(override) or nil
        if override and override > 0 then return override end
    end
    return safeNumber(spellID)
end

local function cooldownInfo(value1, value2, value3, value4)
    if type(value1) == "table" then
        if isSecretValue(value1) then return { unavailable = true } end
        local rawStart = firstNonNil(value1.startTime, value1.start, value1[1])
        local rawDuration = firstNonNil(value1.duration, value1[2])
        local rawEnabled = firstNonNil(value1.isEnabled, value1.enabled, value1[3])
        local rawModRate = firstNonNil(value1.modRate, value1.rate, value1[4])
        local start = safeNumber(rawStart)
        local duration = safeNumber(rawDuration)
        local modRate = safeNumber(rawModRate)
        return {
            start = start or 0,
            duration = duration or 0,
            enabled = safeBoolean(rawEnabled),
            modRate = modRate or 1,
            unavailable = (rawStart ~= nil and start == nil)
                or (rawDuration ~= nil and duration == nil)
                or (rawEnabled ~= nil and safeBoolean(rawEnabled) == nil)
                or (rawModRate ~= nil and modRate == nil),
        }
    end
    local start = safeNumber(value1)
    local duration = safeNumber(value2)
    local modRate = safeNumber(value4)
    return {
        start = start or 0,
        duration = duration or 0,
        enabled = safeBoolean(value3),
        modRate = modRate or 1,
        unavailable = (value1 ~= nil and start == nil)
            or (value2 ~= nil and duration == nil)
            or (value3 ~= nil and safeBoolean(value3) == nil)
            or (value4 ~= nil and modRate == nil),
    }
end

local function readSpellCooldown(spellID, state)
    local api = state and state.api or _G
    local spellAPI = api.C_Spell or C_Spell
    local source = spellAPI and spellAPI.GetSpellCooldown or api.GetSpellCooldown
    if type(source) ~= "function" then return nil end
    local ok, a, b, c, d = safeCall(source, spellID)
    if not ok then return nil end
    return cooldownInfo(a, b, c, d)
end

local function readItemCooldown(itemID, state)
    local api = state and state.api or _G
    local containerAPI = api.C_Container or C_Container
    local itemAPI = api.C_Item or C_Item
    -- Retail exposes the numeric-ID form through C_Container.  C_Item's
    -- similarly named API accepts an ItemInfo value, so keep it as a
    -- compatibility fallback for callers that provide that shape.
    local source = containerAPI and containerAPI.GetItemCooldown
        or itemAPI and itemAPI.GetItemCooldown
        or api.GetItemCooldown
    if type(source) ~= "function" then return nil end
    local ok, a, b, c, d = safeCall(source, itemID)
    if not ok then return nil end
    return cooldownInfo(a, b, c, d)
end

local function remaining(info, now)
    if not info or info.unavailable then return 0 end
    if info.enabled == false or info.enabled == 0 then return 0 end
    if info.start <= 0 or info.duration <= 0 then return 0 end
    local modRate = info.modRate > 0 and info.modRate or 1
    now = safeNumber(now) or 0
    return math.max(0, (info.start + info.duration - now) / modRate)
end

local function spellCharges(spellID, state, now)
    local api = state and state.api or _G
    local spellAPI = api.C_Spell or C_Spell
    local source = spellAPI and spellAPI.GetSpellCharges or api.GetSpellCharges
    if type(source) ~= "function" then return nil end
    local ok, a, b, c, d, e = safeCall(source, spellID)
    if not ok then return nil end
    local charges, maxCharges, start, duration, modRate
    if type(a) == "table" then
        if isSecretValue(a) then return nil, true end
        local rawCharges = firstNonNil(a.currentCharges, a.charges, a[1])
        local rawMaxCharges = firstNonNil(a.maxCharges, a.max, a[2])
        local rawStart = firstNonNil(a.cooldownStartTime, a.startTime, a.start, a[3])
        local rawDuration = firstNonNil(a.cooldownDuration, a.duration, a[4])
        local rawModRate = firstNonNil(a.chargeModRate, a.modRate, a.rate, a[5])
        charges = safeNumber(rawCharges)
        maxCharges = safeNumber(rawMaxCharges)
        start = safeNumber(rawStart) or 0
        duration = safeNumber(rawDuration) or 0
        modRate = safeNumber(rawModRate) or 1
        if (rawCharges ~= nil and charges == nil)
            or (rawMaxCharges ~= nil and maxCharges == nil)
            or (rawStart ~= nil and safeNumber(rawStart) == nil)
            or (rawDuration ~= nil and safeNumber(rawDuration) == nil)
            or (rawModRate ~= nil and safeNumber(rawModRate) == nil) then
            return nil, true
        end
    else
        charges = safeNumber(a)
        maxCharges = safeNumber(b)
        start = safeNumber(c) or 0
        duration = safeNumber(d) or 0
        modRate = safeNumber(e) or 1
        if (a ~= nil and charges == nil) or (b ~= nil and maxCharges == nil)
            or (c ~= nil and safeNumber(c) == nil)
            or (d ~= nil and safeNumber(d) == nil)
            or (e ~= nil and safeNumber(e) == nil) then
            return nil, true
        end
    end
    if charges == nil and maxCharges == nil then return nil end
    local recharge = 0
    if start > 0 and duration > 0 then
        recharge = math.max(0, (start + duration - now) / (modRate > 0 and modRate or 1))
    end
    return { current = charges, max = maxCharges, recharge = recharge, modRate = modRate }, false
end

local function resolveFromTables(data, value)
    local wanted = normalizeText(value)
    if not wanted then return nil end

    local maps = { data.ZoneNameToID, TA.ZoneNameToID }
    for _, map in ipairs(maps) do
        if type(map) == "table" then
            for name, mapID in pairs(map) do
                if normalizeText(name) == wanted and isPositiveMapID(mapID) then return mapID end
            end
        end
    end

    local hubs = data.PortalHubs
    if type(hubs) == "table" then
        for key, hub in pairs(hubs) do
            if type(hub) == "table" then
                local name = hub.name or hub.destination or key
                if normalizeText(name) == wanted and isPositiveMapID(hub.mapID) then return hub.mapID end
            end
        end
    end
    return nil
end

local function destinationOptions(source, destination, data)
    local options = firstNonNil(
        destination and destination.options,
        destination and destination.choices,
        source and source.destinationOptions
    )
    if type(options) == "string" and type(data) == "table" and type(data[options]) == "table" then
        options = data[options]
    end
    return copyValue(options)
end

local function destinationShape(destination, source, resolved, mapID, data)
    local kind = firstNonNil(
        destination and destination.kind,
        destination and destination.type,
        source.destinationKind,
        source.destinationType,
        source.targetKind
    )
    if not kind then
        local name = normalizeText(destination and (destination.name or destination.destination))
            or normalizeText(source.destination)
        if source.kind == "hearthstone" or name == "setinnlocation" or name == "hearthstonelocation" then
            kind = "bind"
        elseif name == "previouslocation" or name == "returnlocation" then
            kind = "previous"
        elseif name == "camplocation" or name == "variouslocations" then
            kind = "choice"
        elseif name == "nearestflightmaster" or name == "nearbyflightmaster" then
            kind = "nearby"
        elseif name == "randomlocation" or (name and name:find("random", 1, true)) then
            kind = "random"
        elseif name == "none" then
            kind = "unknown"
        elseif isPositiveMapID(mapID) then
            kind = source.destinationHub and "hub" or "fixed"
        else
            kind = "unknown"
        end
    end
    local dynamicKind = kind == "bind" or kind == "previous" or kind == "choice"
        or kind == "random" or kind == "nearby" or kind == "unknown"
    local actualResolved = resolved == true
    if kind == "random" or kind == "unknown" then
        actualResolved = false
    end
    local options = destinationOptions(source, destination, data)
    local effectiveMapID = isPositiveMapID(mapID) and mapID or nil
    local result = {
        mapID = effectiveMapID,
        kind = kind,
        type = kind,
        targetKind = firstNonNil(
            destination and destination.targetKind,
            source.targetKind,
            source.destinationKind,
            kind
        ),
        name = firstNonNil(destination and destination.name, destination and destination.destination, source.destination, source.name),
        x = destination and destination.x,
        y = destination and destination.y,
        continent = destination and destination.continent,
        dynamic = dynamicKind or not effectiveMapID,
        resolved = actualResolved,
        options = options,
        selectionRequired = kind == "choice" and not actualResolved,
        instanceMapID = source.instanceMapID,
        entranceMapID = source.entranceMapID,
        landingMapID = source.landingMapID or effectiveMapID,
        regionMapID = source.regionMapID or effectiveMapID,
        identityKey = source.instanceKey or source.identityKey,
        identityConfidence = source.identityConfidence,
    }
    result.displayName = result.name
    result.destinationName = result.name
    result.routeEligible = result.resolved and isPositiveMapID(result.mapID)
    return result
end

local function isDynamicDestination(source, destination)
    if source.dynamicDestination or destination.dynamic then return true end
    local name = normalizeText(destination.name or destination.destination or source.destination)
    if not name then return true end
    if name == "setinnlocation" or name == "hearthstonelocation"
        or name == "previouslocation" or name == "camplocation"
        or name == "variouslocations" or name == "randomlocation"
        or name == "randomdraenorlocation" or name == "nearestflightmaster"
        or name == "none" or (name and name:find("random", 1, true))
        or source.kind == "hearthstone" then
        return true
    end
    return not isPositiveMapID(firstNonNil(source.mapID, destination.mapID))
end

local function callResolver(resolver, value, source, state)
    if type(resolver) ~= "function" then return nil end
    local ok, result = safeCall(resolver, value, source, state)
    if not ok then return nil end
    if type(result) == "number" or isSecretValue(result) then
        return safeNumber(result)
    end
    if type(result) == "table" then
        return safeNumber(firstNonNil(result.mapID, result.destinationMapID, result.id)), result
    end
    return nil
end

function Sources.ResolveDestination(source, state, options)
    source = source or {}
    state = state or {}
    options = options or {}

    local raw = source.destination
    if type(raw) ~= "table" then
        raw = { name = raw }
    else
        raw = copyValue(raw)
    end
    local data = getData(options.data)
    if raw.options == nil and raw.choices == nil and source.destinationOptions ~= nil then
        raw.options = destinationOptions(source, raw, data)
    end
    -- Dungeon records route to the landing/region map while retaining their
    -- instance and entrance identities for display and validation.
    local mapID = firstNonNil(
        source.landingMapID,
        source.destinationMapID,
        source.regionMapID,
        source.mapID,
        raw.mapID
    )
    local resolvedDestination

    if not isPositiveMapID(mapID) and options.resolveDynamic ~= false then
        local resolver = firstNonNil(
            source.destinationResolver,
            source.resolveDestination,
            options.resolveDestination,
            state.resolveDestination,
            TA.ResolveDestination
        )
        mapID, resolvedDestination = callResolver(resolver, raw.name or raw.destination or source.destination, source, state)
    end
    if not isPositiveMapID(mapID) then
        mapID = resolveFromTables(data, raw.name or raw.destination or source.destination)
    end

    if not isPositiveMapID(mapID) then
        local dynamic = isDynamicDestination(source, raw)
        if dynamic then
            local name = normalizeText(raw.name or raw.destination or source.destination)
            if name == "camplocation" then
                mapID = firstNonNil(state.campMapID, state.campLocation and state.campLocation.mapID)
            elseif name == "previouslocation" then
                mapID = firstNonNil(state.previousMapID, state.returnMapID)
            elseif name == "nearestflightmaster" or name == "nearbyflightmaster" then
                mapID = firstNonNil(state.nearestFlightMapID, state.flightMasterMapID)
            elseif source.kind == "hearthstone" or name == "setinnlocation" or name == "hearthstonelocation" then
                mapID = firstNonNil(state.bindMapID, state.bindLocation and state.bindLocation.mapID, state.hearthstoneMapID)
            elseif name == "variouslocations" or name == "camplocation" then
                local selection = firstNonNil(
                    state.choiceMapID,
                    state.selectedDestinationMapID,
                    state.moleMachineMapID,
                    state.destinationChoice
                )
                if type(selection) == "table" then
                    mapID = firstNonNil(selection.mapID, selection.destinationMapID, selection.id)
                    resolvedDestination = selection
                else
                    mapID = selection
                end
            elseif raw.kind == "choice" or raw.type == "choice"
                or source.destinationKind == "choice" or source.destinationType == "choice" then
                local selection = firstNonNil(state.choiceMapID, state.selectedDestinationMapID, state.destinationChoice)
                if type(selection) == "table" then
                    mapID = firstNonNil(selection.mapID, selection.destinationMapID, selection.id)
                    resolvedDestination = selection
                else
                    mapID = selection
                end
            elseif state.destinationMapID
                and raw.kind ~= "random"
                and raw.type ~= "random"
                and source.destinationKind ~= "random"
                and source.destinationType ~= "random" then
                mapID = state.destinationMapID
            end
        end
    end

    if type(resolvedDestination) == "table" then
        for key, value in pairs(resolvedDestination) do raw[key] = copyValue(value) end
    end
    local result = destinationShape(raw, source, isPositiveMapID(mapID), mapID, data)
    result.dynamic = result.dynamic or isDynamicDestination(source, raw)
    if result.resolved and state.destinationRouteEligible == false then result.routeEligible = false end
    return result
end

local function makeAction(category, source, kind, actionID)
    local actionType = firstNonNil(source.actionType, source.kind == "toy" and "toy", kind == "toy" and "toy", kind == "item" and "item", source.spellID and "spell")
    if actionType == "portal" or actionType == "teleport" or actionType == "dungeon" then actionType = "spell" end
    if not actionType then actionType = source.itemID and "item" or "spell" end
    return {
        type = actionType,
        id = actionID,
        value = actionType == "item" and ("item:" .. tostring(actionID)) or actionID,
        spellID = actionType == "spell" and actionID or nil,
        itemID = (actionType == "item" or actionType == "toy") and actionID or nil,
        secureType = actionType,
        secureValue = actionType == "item" and ("item:" .. tostring(actionID)) or actionID,
    }
end

local function sourceAction(source)
    if source.action then return source.action end
    local kind = source.kind or source.type or CATEGORY_KIND[source.category] or (source.itemID and "item") or "teleport"
    local actionID = firstNonNil(source.actionID, source.spellID, source.itemID)
    return makeAction(source.category, source, kind, actionID)
end

local function stableKey(category, source, kind)
    local explicit = source.key or source.id
    if explicit then
        return string.lower(category) .. ":" .. tostring(explicit)
    end
    local actionID = source.spellID or source.itemID or source.actionID or "none"
    local name = normalizeText(source.name or source.destination or "source") or "source"
    local destination = normalizeText(source.destinationName or source.destination or "destination") or "destination"
    local requirement = normalizeText(
        source.faction or source.class or source.race or source.profession or source.specialization or "any"
    ) or "any"
    return string.lower(category) .. ":" .. kind .. ":" .. tostring(actionID)
        .. ":" .. name .. ":" .. destination .. ":" .. requirement
end

local function canonicalRecord(category, source, index, options)
    if type(source) ~= "table" then return nil end
    local kind = CATEGORY_KIND[category] or source.type or "teleport"
    local actionID = firstNonNil(source.actionID, source.spellID, source.itemID)
    local data = getData(options and options.data)
    local semantics = data.SourceSemantics and data.SourceSemantics[category] or {}
    local record = copyValue(source)
    record.key = stableKey(category, source, kind)
    record.category = category
    record.index = index
    record.kind = kind
    record.type = kind
    record.name = source.name or source.destination or record.key
    record.destinationResolver = source.destinationResolver or source.resolveDestination
    record.sourceFamily = firstNonNil(source.sourceFamily, semantics.sourceFamily, CATEGORY_FAMILY[category], category)
    record.interaction = firstNonNil(
        source.interaction,
        source.interactionType,
        semantics.interaction,
        CATEGORY_INTERACTION[category],
        "player"
    )
    record.interactionType = record.interaction
    record.externalInteraction = record.interaction == "external-player"
        or record.interaction == "external"
    record.actionableByPlayer = firstNonNil(
        source.actionableByPlayer,
        semantics.actionableByPlayer,
        not record.externalInteraction and record.interaction ~= "player-choice"
    )
    record.discovery = firstNonNil(source.discovery, semantics.discovery)
    record.destinationOptions = copyValue(source.destinationOptions)
    if type(record.destinationOptions) == "string" and type(data[record.destinationOptions]) == "table" then
        record.destinationOptions = copyValue(data[record.destinationOptions])
    end
    -- Catalog records must stay state-independent.  Bind, choice, nearby,
    -- and other dynamic destinations are resolved again by Evaluate.
    local catalogOptions = { data = options and options.data, resolveDynamic = false }
    local catalogSource = copyValue(source) or {}
    catalogSource.destinationResolver = record.destinationResolver
    catalogSource.destinationOptions = record.destinationOptions
    record.destination = Sources.ResolveDestination(catalogSource, nil, catalogOptions)
    record.targetKind = firstNonNil(source.targetKind, source.destinationKind, record.destination.targetKind)
    record.instanceKey = source.instanceKey or source.identityKey
    record.instanceMapID = source.instanceMapID
    record.entranceMapID = source.entranceMapID
    record.landingMapID = source.landingMapID or source.destinationMapID
    record.regionMapID = source.regionMapID
    record.identityConfidence = source.identityConfidence
    record.action = makeAction(category, source, kind, actionID)
    record.actionType = record.action.type
    record.actionID = actionID
    record.spellID = source.spellID
    record.itemID = source.itemID
    record.requirements = copyValue(source.requirements or source.requirement or {})
    if type(record.requirements) ~= "table" then record.requirements = {} end
    record.requirements.class = firstNonNil(record.requirements.class, source.class)
    record.requirements.race = firstNonNil(record.requirements.race, source.race)
    record.requirements.faction = firstNonNil(record.requirements.faction, source.faction)
    record.requirements.profession = firstNonNil(record.requirements.profession, source.profession)
    record.requirements.specialization = firstNonNil(record.requirements.specialization, source.specialization, source.spec)
    record.requirements.quest = firstNonNil(record.requirements.quest, source.quest, source.questID)
    record.requirements.reputation = firstNonNil(record.requirements.reputation, source.reputation, source.reputationID)
    record.requirements.expansion = firstNonNil(record.requirements.expansion, source.expansion, source.expansionID)
    record.requirements.location = firstNonNil(record.requirements.location, source.location, source.locationID)
    record.requirements.unlock = firstNonNil(record.requirements.unlock, source.unlock, source.unlockID)
    record.requirements.discovery = firstNonNil(
        record.requirements.discovery,
        source.discoveryRequirement,
        source.discoveryID
    )
    record.requirements.phase = firstNonNil(
        record.requirements.phase,
        source.phase,
        source.phaseID,
        source.phases
    )
    record.requirements.access = firstNonNil(record.requirements.access, source.access, source.accessState)
    record.requirements.professionSkill = firstNonNil(
        record.requirements.professionSkill,
        record.requirements.minProfessionSkill,
        source.professionSkill,
        source.minProfessionSkill
    )
    if type(source.requirements) == "table" and type(source.requirements.requires) == "function" then
        record.requirements.requires = source.requirements.requires
    end
    record.enabled = source.enabled ~= false and source.disabled ~= true
    record.edgeType = kind
    record.timing = copyValue(source.timing or { cast = tonumber(source.castTime) or 0 })
    if type(record.timing) ~= "table" then record.timing = {} end
    record.timing.cast = tonumber(record.timing.cast) or 0
    record.timing.wait = tonumber(firstNonNil(record.timing.wait, source.waitTime, source.wait)) or 0
    record.timing.interaction = tonumber(firstNonNil(record.timing.interaction, source.interactionTime)) or 0
    record.timing.travel = tonumber(firstNonNil(record.timing.travel, source.travelTime)) or 0
    record.displayName = record.name
    record.sourceKey = record.key
    record.baseCooldown = tonumber(source.cooldown) or 0
    record.timing.cooldown = record.baseCooldown
    record.dynamicDestination = record.destination.dynamic
    record.destinationRouteEligible = record.destination.routeEligible
    -- Preserve an explicit data-level exclusion (for example Make Camp), but
    -- do not turn every unresolved dynamic destination into a setup action.
    record.routeEligible = source.routeEligible
    return record
end

function Sources.BuildCatalog(data, options)
    if type(data) == "table" and data.TravelData then data = data.TravelData end
    data = getData(data)
    options = options or {}
    local catalog = {}
    local byKey = {}
    local byAction = {}

    for _, category in ipairs(CATEGORY_ORDER) do
        local list = data[category]
        if type(list) == "table" then
            for index, source in ipairs(list) do
                local record = canonicalRecord(category, source, index, { data = data })
                if record then
                    local baseKey = record.key
                    local duplicate = 1
                    while byKey[record.key] do
                        duplicate = duplicate + 1
                        record.key = baseKey .. ":" .. duplicate
                        record.sourceKey = record.key
                    end
                    catalog[#catalog + 1] = record
                    byKey[record.key] = record
                    local actionKey = (safeKeyPart(record.action.type) or "unknown")
                        .. ":" .. (safeKeyPart(record.action.id) or "unknown")
                    byAction[actionKey] = byAction[actionKey] or record
                end
            end
        end
    end

    Sources._catalog = catalog
    Sources._byKey = byKey
    Sources._byAction = byAction
    Sources._catalogData = data
    Sources.catalog = catalog
    Sources.byKey = byKey
    Sources.byAction = byAction
    return catalog
end

function Sources.GetAll(options)
    options = options or {}
    local catalog = Sources._catalog
    local data = getData(options.data)
    if not catalog or options.rebuild or Sources._catalogData ~= data then catalog = Sources.BuildCatalog(data, options) end
    if not options.filter and not options.category and not options.kind then return catalog end

    local result = {}
    for _, record in ipairs(catalog) do
        local matches = true
        if options.category and record.category ~= options.category then matches = false end
        if options.kind and record.kind ~= options.kind then matches = false end
        if options.filter and not options.filter(record) then matches = false end
        if matches then result[#result + 1] = record end
    end
    return result
end

function Sources.FindByKey(key, options)
    options = options or {}
    if isSecretValue(key) then return nil end
    if not Sources._catalog or options.rebuild or Sources._catalogData ~= getData(options.data) then Sources.BuildCatalog(options.data, options) end
    return Sources._byKey and Sources._byKey[key]
end

function Sources.FindByAction(actionType, actionID, options)
    options = options or {}
    if type(actionType) == "table" then
        actionID = firstNonNil(actionType.id, actionType.value, actionType.spellID, actionType.itemID)
        actionType = firstNonNil(actionType.type, actionType.actionType)
    elseif actionID == nil and type(actionType) == "string" then
        local record = Sources.FindByKey(actionType, options)
        if record then return record end
    end
    if isSecretValue(actionType) or isSecretValue(actionID) then return nil end
    if type(actionID) == "string" then
        local itemID = actionID:match("^item:(%d+)$")
        if itemID then actionID = tonumber(itemID) end
    end
    if not Sources._catalog or options.rebuild or Sources._catalogData ~= getData(options.data) then Sources.BuildCatalog(options.data, options) end
    local directKey = (safeKeyPart(actionType) or "unknown") .. ":" .. (safeKeyPart(actionID) or "unknown")
    local direct = Sources._byAction and Sources._byAction[directKey]
    if direct then return direct end
    for _, record in ipairs(Sources._catalog or {}) do
        if (record.action.type == actionType or record.kind == "hearthstone")
            and (record.action.id == actionID or record.spellID == actionID or record.itemID == actionID) then
            return record
        end
    end
    return nil
end

local function addProfession(set, value)
    value = safeString(value)
    if not value or value == "" then return end
    set[value] = true
    set[value:lower()] = true
    local key = professionKey(value)
    if key then set[key] = true end
end

local function collectProfessions(api)
    if not api or type(api.GetProfessions) ~= "function" or type(api.GetProfessionInfo) ~= "function" then
        return nil, nil
    end

    local professions = {}
    local details = {}
    local ok, first, second, archaeology, fishing, cooking = safeCall(api.GetProfessions)
    if not ok then return nil, nil end
    for _, professionIndex in ipairs({ first, second, archaeology, fishing, cooking }) do
        if professionIndex then
            local infoOK, name, _, skillLevel, maxSkillLevel, numAbilities, spellOffset, skillLineID = safeCall(
                api.GetProfessionInfo,
                professionIndex
            )
            if not infoOK then return nil, nil end
            addProfession(professions, name)
            local key = professionKey(name)
            if key then
                details[key] = {
                    name = name,
                    skillLevel = safeNumber(skillLevel),
                    maxSkillLevel = safeNumber(maxSkillLevel),
                    numAbilities = safeNumber(numAbilities),
                    spellOffset = safeNumber(spellOffset),
                    skillLineID = safeNumber(skillLineID),
                }
            end
        end
    end
    return professions, details
end

local function getSpecialization(api)
    if not api or type(api.GetSpecialization) ~= "function" or type(api.GetSpecializationInfo) ~= "function" then
        return nil, nil
    end
    local ok, index = safeCall(api.GetSpecialization)
    if not ok or not index then return nil, nil end
    local infoOK, specID, name = safeCall(api.GetSpecializationInfo, index)
    if not infoOK then return nil, nil end
    return safeNumber(specID), safeString(name)
end

local function resolveBindMapID(bindLocation, data)
    if type(bindLocation) == "table" then
        if isSecretValue(bindLocation) then return nil, nil end
        return safeNumber(bindLocation.mapID), safeString(bindLocation.name)
    end
    bindLocation = safeString(bindLocation)
    if not bindLocation or bindLocation == "" then return nil, bindLocation end
    if type(_G.LibStub) == "function" then
        local ok, lib = safeCall(_G.LibStub, "LibZoneNameToMap-1.0", true)
        if ok and lib and type(lib.GetMapIDFromZoneName) == "function" then
            local mapOK, mapID = safeCall(lib.GetMapIDFromZoneName, lib, bindLocation)
            if mapOK and isPositiveMapID(mapID) then return mapID, bindLocation end
        end
    end
    local mapID = resolveFromTables(data, bindLocation)
    if mapID then return mapID, bindLocation end
    local api = _G.C_Map or C_Map
    if api and type(api.GetMapInfo) == "function" and type(api.GetBestMapForUnit) == "function" then
        -- The table lookup above is authoritative for the addon's known zones;
        -- this fallback only handles localized names exposed by the client.
        local ok, current = safeCall(api.GetBestMapForUnit, "player")
        if ok and current then
            local infoOK, info = safeCall(api.GetMapInfo, current)
            if infoOK and info and not isSecretValue(info)
                and safeString(info.name) == bindLocation then
                return safeNumber(current), bindLocation
            end
        end
    end
    return nil, bindLocation
end

function Sources.CreatePlayerState(options)
    options = options or {}
    local api = options.api or _G
    local state = copyState(options, api)
    state.now = currentTime(options)
    state.class = state.class or getUnitClass()
    state.race = state.race or getUnitRace()
    state.faction = state.faction or getFaction()
    local api = state.api or _G
    local data = getData(options.data)
    local mapAPI = api.C_Map or C_Map or _G.C_Map
    if not state.currentMapID and mapAPI and type(mapAPI.GetBestMapForUnit) == "function" then
        local ok, mapID = safeCall(mapAPI.GetBestMapForUnit, "player")
        if ok then state.currentMapID = safeNumber(mapID) end
    end
    if not state.currentZoneName and state.currentMapID and mapAPI and type(mapAPI.GetMapInfo) == "function" then
        local ok, mapInfo = safeCall(mapAPI.GetMapInfo, state.currentMapID)
        if ok and mapInfo and not isSecretValue(mapInfo) then
            state.currentZoneName = safeString(mapInfo.name)
        end
    end
    if not state.bindLocation then
        local ok, bindLocation = safeCall(api.GetBindLocation)
        if ok and not isSecretValue(bindLocation) then
            state.bindLocation = safeString(bindLocation) or copyValue(bindLocation)
        end
    end
    if not state.bindMapID then
        state.bindMapID = resolveBindMapID(state.bindLocation, data)
    end
    if not state.specialization and not state.specID then
        local specID, specialization = getSpecialization(api)
        state.specID = specID
        state.specialization = specialization
    end
    if not state.professions then
        local professions, details = collectProfessions(api)
        state.professions = professions
        state.professionDetails = state.professionDetails or details
    end
    return state
end

local function requirementValue(requirements, source, ...)
    for _, key in ipairs({ ... }) do
        local value = source[key]
        if value == nil then value = requirements[key] end
        if value ~= nil then return value end
    end
    return nil
end

local function questComplete(quest, state)
    if quest == nil then return true end
    if type(quest) == "function" then
        local ok, result = safeCall(quest, state)
        return ok and safeBoolean(result)
    end
    local questID = type(quest) == "table" and firstNonNil(quest.questID, quest.id, quest[1]) or quest
    local required = type(quest) ~= "table" or quest.completed ~= false
    if not required then return true end
    if type(state.completedQuests) == "table" and state.completedQuests[questID] ~= nil then
        return safeBoolean(state.completedQuests[questID])
    end
    local api = state.api or _G
    local questLog = api.C_QuestLog or _G.C_QuestLog
    if questLog and type(questLog.IsQuestFlaggedCompleted) == "function" then
        local ok, complete = safeCall(questLog.IsQuestFlaggedCompleted, questID)
        if ok then return safeBoolean(complete) end
    end
    if type(api.IsQuestFlaggedCompleted) == "function" then
        local ok, complete = safeCall(api.IsQuestFlaggedCompleted, questID)
        if ok then return safeBoolean(complete) end
    end
    return nil
end

local function reputationMet(reputation, state)
    if reputation == nil then return true end
    if type(reputation) == "function" then
        local ok, result = safeCall(reputation, state)
        return ok and safeBoolean(result)
    end
    local factionID, minimum = reputation, 0
    if type(reputation) == "table" then
        factionID = firstNonNil(reputation.factionID, reputation.id, reputation[1])
        minimum = safeNumber(firstNonNil(reputation.min, reputation.minimum, reputation.required, reputation[2])) or 0
    end
    if type(state.reputation) == "table" and state.reputation[factionID] ~= nil then
        local value = state.reputation[factionID]
        if type(value) == "table" then value = firstNonNil(value.standing, value.reputation, value.value) end
        value = safeNumber(value)
        return value ~= nil and value >= minimum
    end
    local api = state.api or _G
    local repAPI = api.C_Reputation or _G.C_Reputation
    if repAPI and type(repAPI.GetFactionDataByID) == "function" then
        local ok, info = safeCall(repAPI.GetFactionDataByID, factionID)
        if ok and type(info) == "table" then
            local value = firstNonNil(info.currentStanding, info.standing, info.barValue)
            value = safeNumber(value)
            if value ~= nil then return value >= minimum end
        end
    end
    return nil
end

local function locationMatches(location, state)
    if location == nil then return true end
    if isSecretValue(location) then return nil end
    if type(location) == "function" then
        local ok, result = safeCall(location, state)
        if not ok then return nil end
        return safeBoolean(result)
    end
    if type(location) == "table" and (location.mapID or location.id or location[1]) then
        location = firstNonNil(location.mapID, location.id, location[1])
    end
    if type(location) == "number" then
        local currentMapID = safeNumber(state.currentMapID)
        if currentMapID == nil then return nil end
        return currentMapID == location
    end
    if type(location) == "string" then
        if state.currentZoneName == nil then return nil end
        return normalizeText(location) == normalizeText(state.currentZoneName)
    end
    return nil
end

local function requirementStatus(required, actual, universal)
    if required == nil then return true end
    if actual == nil then return nil end
    if universal and contains(required, "Both") then return true end
    return contains(required, actual)
end

local function professionRequirement(value, source, requirements)
    local name = value
    local minimum = nil
    if type(value) == "table" then
        name = firstNonNil(value.name, value.profession, value.professionName, value[1])
        minimum = firstNonNil(value.minSkill, value.minimumSkill, value.skill, value.requiredSkill, value[2])
    end
    minimum = firstNonNil(
        minimum,
        source.professionSkill,
        source.minProfessionSkill,
        requirements.professionSkill,
        requirements.minProfessionSkill
    )
    return name, safeNumber(minimum)
end

local function professionDetail(state, name)
    local details = state.professionDetails or state.professionSkills
    if type(details) ~= "table" then return nil end
    local key = professionKey(name)
    local detail = details[name] or details[key]
    if detail == nil and type(name) == "string" then detail = details[name:lower()] end
    if type(detail) == "number" then
        return { skillLevel = safeNumber(detail) }
    end
    if type(detail) == "table" then return detail end
    return nil
end

local function requirementReason(source, state)
    local requirements = source.requirements or {}
    local class = firstNonNil(source.class, requirements.class, requirements.classes)
    local race = firstNonNil(source.race, requirements.race, requirements.races)
    local faction = firstNonNil(source.faction, requirements.faction, requirements.factions)
    local profession = firstNonNil(source.profession, requirements.profession, requirements.professions)
    local specialization = firstNonNil(source.specialization, source.spec, requirements.specialization, requirements.spec)
    local classStatus = requirementStatus(class, state.class)
    if classStatus == nil then return REASONS.REQUIREMENTS_NOT_MET end
    if classStatus == false then return REASONS.WRONG_CLASS end

    local raceStatus = requirementStatus(race, state.race)
    if raceStatus == nil then return REASONS.REQUIREMENTS_NOT_MET end
    if raceStatus == false then return REASONS.WRONG_RACE end

    local factionStatus = requirementStatus(faction, state.faction, true)
    if factionStatus == nil then return REASONS.REQUIREMENTS_NOT_MET end
    if factionStatus == false then return REASONS.WRONG_FACTION end

    if profession ~= nil then
        if state.professions == nil then return REASONS.REQUIREMENTS_NOT_MET end
        local professionName, minimumSkill = professionRequirement(profession, source, requirements)
        if professionName == nil or not contains(state.professions, professionName) then
            return REASONS.WRONG_PROFESSION
        end
        if minimumSkill then
            local detail = professionDetail(state, professionName)
            local skillLevel = detail and safeNumber(firstNonNil(detail.skillLevel, detail.currentSkill, detail.level))
            if skillLevel == nil then return REASONS.REQUIREMENTS_NOT_MET end
            if skillLevel < minimumSkill then return REASONS.INSUFFICIENT_PROFESSION_SKILL end
        end
    end

    if specialization ~= nil then
        if state.specialization == nil and state.specID == nil then
            return REASONS.REQUIREMENTS_NOT_MET
        end
        local matches = (state.specialization ~= nil and contains(specialization, state.specialization))
            or (state.specID ~= nil and contains(specialization, state.specID))
        if not matches then return REASONS.WRONG_SPECIALIZATION end
    end

    local quest = requirementValue(requirements, source, "quest", "questID")
    local questStatus = questComplete(quest, state)
    if questStatus == false then return REASONS.MISSING_QUEST end
    if questStatus == nil then return REASONS.REQUIREMENTS_NOT_MET end

    local reputation = requirementValue(requirements, source, "reputation", "reputationID")
    local reputationStatus = reputationMet(reputation, state)
    if reputationStatus == false then return REASONS.MISSING_REPUTATION end
    if reputationStatus == nil then return REASONS.REQUIREMENTS_NOT_MET end

    local expansion = requirementValue(requirements, source, "expansion", "expansionID")
    if expansion then
        local expansions = firstNonNil(state.expansions, state.expansion, state.expansionID)
        if expansions == nil then return REASONS.REQUIREMENTS_NOT_MET end
        if not contains(expansions, expansion) then return REASONS.REQUIREMENTS_NOT_MET end
    end

    local location = requirementValue(requirements, source, "location", "locationID")
    if location then
        local locationStatus = locationMatches(location, state)
        if locationStatus == nil then return REASONS.REQUIREMENTS_NOT_MET end
        if not locationStatus then return REASONS.UNUSABLE_LOCATION end
    end

    local unlock = requirementValue(requirements, source, "unlock", "unlockID")
    if unlock then
        if state.unlocks == nil then return REASONS.REQUIREMENTS_NOT_MET end
        if not contains(state.unlocks, unlock) then return REASONS.REQUIREMENTS_NOT_MET end
    end

    local discovery = requirementValue(requirements, source, "discovery", "discovered", "discoveryID")
    if discovery ~= nil then
        local discoveries = firstNonNil(state.discoveries, state.discovery, state.discovered)
        if discoveries == nil then return REASONS.REQUIREMENTS_NOT_MET end
        if not contains(discoveries, discovery) then return REASONS.MISSING_DISCOVERY end
    end

    local phase = requirementValue(requirements, source, "phase", "phaseID", "phases")
    if phase ~= nil then
        local phases = firstNonNil(state.phases, state.phase, state.phaseID)
        if phases == nil then return REASONS.REQUIREMENTS_NOT_MET end
        if not contains(phases, phase) then return REASONS.WRONG_PHASE end
    end

    local access = requirementValue(requirements, source, "access", "accessState")
    if access ~= nil then
        local accessState = firstNonNil(state.access, state.accessState)
        if accessState == nil then return REASONS.REQUIREMENTS_NOT_MET end
        if type(access) == "function" then
            local ok, allowed = safeCall(access, accessState, state, source)
            if not ok or allowed ~= true then return REASONS.REQUIREMENTS_NOT_MET end
        elseif not contains(access, accessState) then
            return REASONS.REQUIREMENTS_NOT_MET
        end
    end

    if requirements.requires and type(requirements.requires) == "function" then
        local ok, allowed = safeCall(requirements.requires, state, source)
        if not ok or allowed ~= true then return REASONS.REQUIREMENTS_NOT_MET end
    end
    return nil
end

-- Static graph edges use the same requirement evaluator as dynamic travel
-- sources.  Returning a reason (rather than only a boolean) keeps route
-- diagnostics and UI explanations consistent across both edge families.
function Sources.EvaluateRequirements(requirements, state, source)
    if state then
        state = copyState(state)
    else
        state = Sources.CreatePlayerState()
    end
    local subject = {}
    for key, value in pairs(source or {}) do subject[key] = value end
    if type(requirements) ~= "table" then requirements = {} end
    subject.requirements = requirements or subject.requirements or {}
    return requirementReason(subject, state)
end

local function actionLookupKey(action)
    if not action then return "unknown" end
    return (safeKeyPart(action.type) or "unknown") .. ":" .. (safeKeyPart(action.id) or "unknown")
end

local function usability(action, state)
    local key = actionLookupKey(action)
    if state and state.usable and key and state.usable[key] ~= nil then
        local value = safeBoolean(state.usable[key])
        if value == nil then return true, false end
        return value, true
    end
    local api = state and state.api or _G
    if action.type == "spell" then
        local spellAPI = api.C_Spell or C_Spell
        local source = spellAPI and spellAPI.IsSpellUsable or api.IsUsableSpell
        if type(source) == "function" then
            local ok, usable = safeCall(source, action.id)
            if ok then
                local value = safeBoolean(usable)
                if value ~= nil then return value, true end
                return true, false
            end
        end
    elseif action.type == "item" or action.type == "toy" then
        local itemAPI = api.C_Item or C_Item
        local source = itemAPI and itemAPI.IsUsableItem or api.IsUsableItem
        if type(source) == "function" then
            local ok, usable = safeCall(source, action.id)
            if ok then
                local value = safeBoolean(usable)
                if value ~= nil then return value, true end
                return true, false
            end
        end
    end
    return true, false
end

local function readActionInfo(action, state)
    local api = state and state.api or _G
    local name, icon

    local names = state and (state.actionNames or state.localizedNames)
    local icons = state and (state.actionIcons or state.localizedIcons)
    if type(names) == "table" then name = names[actionLookupKey(action)] end
    if type(icons) == "table" then icon = icons[actionLookupKey(action)] end

    if action.type == "spell" then
        local spellAPI = api.C_Spell or C_Spell
        if not name and spellAPI and type(spellAPI.GetSpellName) == "function" then
            local ok, value = safeCall(spellAPI.GetSpellName, action.id)
            if ok then name = safeString(value) end
        end
        if not icon and spellAPI and type(spellAPI.GetSpellTexture) == "function" then
            local ok, value = safeCall(spellAPI.GetSpellTexture, action.id)
            if ok then icon = safeDisplayValue(value) end
        end
        if (not name or not icon) and spellAPI and type(spellAPI.GetSpellInfo) == "function" then
            local ok, first, _, third = safeCall(spellAPI.GetSpellInfo, action.id)
            if ok and type(first) == "table" and not isSecretValue(first) then
                name = name or safeString(first.name)
                icon = icon or safeDisplayValue(first.iconID) or safeDisplayValue(first.icon)
            elseif ok then
                name = name or safeString(first)
                icon = icon or safeDisplayValue(third)
            end
        end
        if (not name or not icon) and type(api.GetSpellInfo) == "function" then
            local ok, value, _, valueIcon = safeCall(api.GetSpellInfo, action.id)
            if ok then
                name = name or safeString(value)
                icon = icon or safeDisplayValue(valueIcon)
            end
        end
    elseif action.type == "item" or action.type == "toy" then
        local itemAPI = api.C_Item or C_Item
        if action.type == "toy" then
            local toyAPI = api.C_ToyBox or C_ToyBox
            if toyAPI and type(toyAPI.GetToyInfo) == "function" then
                local ok, first, second, third = safeCall(toyAPI.GetToyInfo, action.id)
                if ok and type(first) == "table" and not isSecretValue(first) then
                    name = name or safeString(first.name) or safeString(first.itemName)
                    icon = icon or safeDisplayValue(first.icon) or safeDisplayValue(first.iconID)
                elseif ok then
                    name = name or safeString(first) or safeString(second)
                    icon = icon or safeDisplayValue(second) or safeDisplayValue(third)
                end
            end
        end
        if not name and itemAPI and type(itemAPI.GetItemNameByID) == "function" then
            local ok, value = safeCall(itemAPI.GetItemNameByID, action.id)
            if ok then name = safeString(value) end
        end
        if (not name or not icon) and itemAPI and type(itemAPI.GetItemInfo) == "function" then
            local ok, first, _, _, _, _, _, _, _, valueIcon = safeCall(itemAPI.GetItemInfo, action.id)
            if ok and type(first) == "table" and not isSecretValue(first) then
                name = name or safeString(first.name) or safeString(first.itemName)
                icon = icon or safeDisplayValue(first.icon) or safeDisplayValue(first.iconFileID)
            elseif ok then
                name = name or safeString(first)
                icon = icon or safeDisplayValue(valueIcon)
            end
        end
        if not icon and itemAPI and type(itemAPI.GetItemIconByID) == "function" then
            local ok, value = safeCall(itemAPI.GetItemIconByID, action.id)
            if ok then icon = safeDisplayValue(value) end
        end
        if not icon and itemAPI and type(itemAPI.GetItemInfoInstant) == "function" then
            local ok, _, _, _, _, value = safeCall(itemAPI.GetItemInfoInstant, action.id)
            if ok then icon = safeDisplayValue(value) end
        end
    end

    return name, icon
end

function Sources.ResolveActionPresentation(action, source, state)
    action = action or {}
    source = source or {}
    local name, icon = readActionInfo(action, state)
    return {
        name = name or safeString(source.displayName) or safeString(source.name),
        icon = icon or safeDisplayValue(source.icon),
        actionType = action.type,
        actionID = action.id,
        sourceKey = source.sourceKey or source.key,
    }
end

local function actionForState(source, state)
    local action = sourceAction(source)
    if source.kind ~= "hearthstone" or not source.itemID then return action end

    local count = itemCount(source.itemID, state)
    local collected = toyKnown(source.itemID, state)
    if count and count > 0 then
        return makeAction(source.category, source, "item", source.itemID)
    elseif collected == true then
        return makeAction(source.category, source, "toy", source.itemID)
    elseif source.itemID == 6948 and (count == nil or count == 0) then
        -- The standard hearthstone is granted by the game even when its bag
        -- count is not available during login or loading screens.
        return makeAction(source.category, source, "item", source.itemID)
    end
    return action
end

local function stateForReason(reason)
    if reason == REASONS.READY then return "ready" end
    if reason == REASONS.ON_COOLDOWN then return "cooldown" end
    if reason == REASONS.NOT_KNOWN then return "unknown" end
    if reason == REASONS.NOT_OWNED then return "not-owned" end
    if reason == REASONS.NOT_COLLECTED then return "not-collected" end
    if reason == REASONS.INSUFFICIENT_QUANTITY then return "not-owned" end
    if reason == REASONS.NO_CHARGES then return "no-charges" end
    if reason == REASONS.DISABLED then return "disabled" end
    if reason == REASONS.UNUSABLE then return "unusable" end
    if reason == REASONS.DESTINATION_UNRESOLVED then return "unresolved" end
    if reason == REASONS.UNSUPPORTED_SOURCE then return "unsupported" end
    if reason == REASONS.EXTERNAL_INTERACTION then return "external-interaction" end
    if reason == REASONS.SETUP_ONLY then return "setup-only" end
    if reason == REASONS.API_UNAVAILABLE or reason == REASONS.USABILITY_UNKNOWN then return "unknown" end
    if reason == REASONS.REQUIREMENTS_NOT_MET or reason == REASONS.WRONG_CLASS
        or reason == REASONS.WRONG_RACE or reason == REASONS.WRONG_FACTION
        or reason == REASONS.WRONG_PROFESSION or reason == REASONS.WRONG_SPECIALIZATION
        or reason == REASONS.MISSING_QUEST or reason == REASONS.MISSING_REPUTATION
        or reason == REASONS.UNUSABLE_LOCATION or reason == REASONS.INSUFFICIENT_PROFESSION_SKILL
        or reason == REASONS.MISSING_DISCOVERY or reason == REASONS.WRONG_PHASE then
        return "requirements"
    end
    return "unknown"
end

local function sourceTypeForExplanation(evaluation)
    local source = evaluation and evaluation.source or {}
    return evaluation and (evaluation.sourceFamily or evaluation.sourceType)
        or source.sourceFamily or source.kind or source.category or "travel source"
end

-- Build presentation data from the canonical evaluation.  UI code consumes
-- this shape instead of inferring state from a localized name or an action
-- button.  The raw IDs and reason fields remain available for stable action
-- configuration and diagnostics.
function Sources.BuildExplanation(evaluation)
    evaluation = evaluation or {}
    local source = evaluation.source or {}
    local destination = evaluation.destination or {}
    local resolved = destination.resolved == true or evaluation.destinationResolved == true
    local destinationName = safeString(destination.displayName)
        or safeString(destination.destinationName)
        or safeString(destination.name)
        or safeString(evaluation.destinationName)
        or safeString(source.destinationName)
        or safeString(source.destination)
        or "Unknown destination"
    local sourceName = safeString(evaluation.displayName)
        or safeString(source.displayName)
        or safeString(source.name)
        or "Travel source"
    local reason = evaluation.reason or REASONS.INVALID_SOURCE
    local explanation = {
        sourceType = sourceTypeForExplanation(evaluation),
        sourceName = sourceName,
        sourceKey = evaluation.sourceKey or source.sourceKey or source.key,
        actionType = evaluation.actionType or (evaluation.action and evaluation.action.type),
        actionID = evaluation.actionID or (evaluation.action and evaluation.action.id),
        destinationName = destinationName,
        destinationKind = destination.kind or destination.type,
        destinationResolved = resolved,
        destinationUncertain = not resolved or destination.dynamic == true,
        reason = reason,
        reasonText = evaluation.reasonText or REASON_TEXT[reason] or reason,
        cooldown = math.max(0, safeNumber(evaluation.cooldown) or 0),
        charges = copyValue(evaluation.charges),
        interaction = evaluation.interactionRequired or evaluation.interaction,
        requirements = copyValue(evaluation.requirements or source.requirements),
        actionableNow = evaluation.actionableNow == true,
        routeEligible = evaluation.routeEligible ~= false,
    }
    explanation.details = {}
    if explanation.destinationUncertain then
        explanation.details[#explanation.details + 1] = "Destination is unresolved or dynamic"
    end
    if explanation.cooldown > 0 then
        explanation.details[#explanation.details + 1] = "Cooldown remaining"
    end
    if explanation.charges and explanation.charges.current ~= nil then
        explanation.details[#explanation.details + 1] = string.format(
            "Charges: %s/%s",
            tostring(explanation.charges.current),
            tostring(explanation.charges.max or "?")
        )
    end
    if explanation.interaction and explanation.interaction ~= "player" then
        explanation.details[#explanation.details + 1] = "Requires " .. tostring(explanation.interaction)
    end
    if reason ~= REASONS.READY and explanation.reasonText then
        explanation.details[#explanation.details + 1] = explanation.reasonText
    end
    return explanation
end

function Sources.Evaluate(source, state, options)
    options = options or {}
    if type(source) == "string" then source = Sources.FindByKey(source, options) end
    if not source then
        return {
            state = "invalid",
            reason = REASONS.INVALID_SOURCE,
            reasonText = REASON_TEXT[REASONS.INVALID_SOURCE],
            actionableNow = false,
            routeEligible = false,
        }
    end
    if state then
        state = copyState(state, state.api or options.api)
    else
        state = Sources.CreatePlayerState(options)
    end

    local result = copyValue(source)
    result.destination = Sources.ResolveDestination(source, state, options)
    result.destinationResolved = result.destination.resolved == true
    result.destinationType = result.destination.kind
    result.dynamicDestination = result.destination.dynamic
    result.action = copyValue(actionForState(source, state))
    result.actionConfig = copyValue(result.action)
    result.cooldown = 0
    result.charges = nil
    result.quantity = nil
    result.bankQuantity = nil
    result.requiredQuantity = tonumber(firstNonNil(source.requiredQuantity, source.minQuantity, source.quantity)) or 0
    result.known = nil
    result.owned = nil
    result.collected = nil
    result.usable = true
    result.usabilityKnown = false
    result.enabled = source.enabled ~= false
    result.actionableNow = false
    result.routeEligible = false
    result.state = "unknown"
    result.source = source
    result.sourceKey = source.sourceKey or source.key
    result.displayName = source.displayName or source.name
    result.icon = source.icon
    result.sourceType = source.sourceFamily or source.kind or source.category
    result.sourceID = source.id or source.sourceID
    result.requirements = copyValue(source.requirements)
    result.timing = copyValue(source.timing)
    result.sourceFamily = source.sourceFamily
    result.interaction = source.interaction or source.interactionType or "player"
    result.interactionType = result.interaction
    result.externalInteraction = source.externalInteraction == true
        or result.interaction == "external-player"
        or result.interaction == "external"
    result.actionableByPlayer = source.actionableByPlayer ~= false
        and result.interaction ~= "external-player"
        and result.interaction ~= "external"
        and result.interaction ~= "player-choice"
    result.interactionRequired = result.interaction ~= "player" and result.interaction or nil
    result.destinationOptions = result.destination and result.destination.options

    local reason
    if not result.enabled then
        reason = REASONS.DISABLED
    elseif source.routeEligible == false then
        reason = REASONS.SETUP_ONLY
    else
        reason = requirementReason(source, state)
    end

    local action = result.action
    if action.type == "spell" and action.id then
        local spellID = getSpellOverride(action.id, source, state)
        result.action = makeAction(source.category, source, "teleport", spellID)
        result.actionConfig = copyValue(result.action)
        result.effectiveSpellID = spellID
        local baseKnown = spellKnown(action.id, state)
        local effectiveKnown = spellKnown(spellID, state)
        result.known = baseKnown == true or effectiveKnown == true
        if baseKnown == nil and effectiveKnown == nil then result.known = nil end
        local info = readSpellCooldown(spellID, state)
        result.cooldownInfo = info
        result.cooldown = remaining(info, state.now)
        result.cooldownUnavailable = not info or info.unavailable == true
        if info and info.enabled == false then result.enabled = false end
        local charges, chargesUnavailable = spellCharges(spellID, state, state.now)
        result.charges = charges
        result.chargesUnavailable = chargesUnavailable == true
        if result.charges and result.charges.current ~= nil and result.charges.current <= 0 then
            result.cooldown = math.max(result.cooldown, result.charges.recharge or 0)
        end
        if not reason and result.cooldownUnavailable then
            reason = REASONS.API_UNAVAILABLE
        elseif not reason and result.chargesUnavailable then
            reason = REASONS.API_UNAVAILABLE
        elseif not reason and result.known == nil then
            reason = REASONS.API_UNAVAILABLE
        elseif not reason and result.known == false then
            reason = REASONS.NOT_KNOWN
        elseif not reason and not result.enabled then
            reason = REASONS.DISABLED
        elseif not reason and result.charges and result.charges.current ~= nil and result.charges.current <= 0 then
            reason = REASONS.NO_CHARGES
        end
    elseif (action.type == "item" or action.type == "toy") and action.id then
        local count = itemCount(action.id, state)
        result.bankQuantity = itemBankCount(action.id, state)
        local collected = toyKnown(action.id, state)
        result.quantity = count or (collected == true and 1 or 0)
        result.collected = collected
        result.cooldownInfo = readItemCooldown(action.id, state)
        result.cooldown = remaining(result.cooldownInfo, state.now)
        result.cooldownUnavailable = not result.cooldownInfo or result.cooldownInfo.unavailable == true
        if action.type == "toy" then
            result.owned = collected
            if not reason and collected == nil then
                reason = REASONS.API_UNAVAILABLE
            elseif not reason and collected == false then
                reason = REASONS.NOT_COLLECTED
            end
        elseif source.kind == "hearthstone" and action.id == 6948 and (count == nil or count == 0) then
            result.owned = true
            result.quantity = math.max(result.quantity, 1)
        elseif count == nil then
            result.owned = nil
            if not reason then reason = REASONS.API_UNAVAILABLE end
        else
            result.owned = count > 0
            if not reason and result.requiredQuantity > 0 and count < result.requiredQuantity then
                reason = REASONS.INSUFFICIENT_QUANTITY
            elseif not reason and not result.owned then
                reason = REASONS.NOT_OWNED
            end
        end
    elseif not reason then
        reason = REASONS.UNSUPPORTED_SOURCE
    end

    if result.enabled then
        local usable, usabilityKnown = usability(result.action, state)
        result.usable = usable
        result.usabilityKnown = usabilityKnown
        if not reason and usable == false then reason = REASONS.UNUSABLE end
        if not reason and not usabilityKnown then reason = REASONS.USABILITY_UNKNOWN end
    end
    if result.enabled and not reason and result.cooldownUnavailable then
        reason = REASONS.API_UNAVAILABLE
    elseif result.enabled and not reason and result.cooldown > 0 then
        reason = REASONS.ON_COOLDOWN
    end
    if result.enabled and not reason and not result.destinationResolved then
        reason = REASONS.DESTINATION_UNRESOLVED
    end
    if result.enabled and not reason
        and (result.externalInteraction or result.interaction == "player-choice") then
        reason = REASONS.EXTERNAL_INTERACTION
    end

    result.reason = reason or REASONS.READY
    result.reasonText = REASON_TEXT[result.reason] or result.reason
    result.state = stateForReason(result.reason)
    result.actionableNow = result.reason == REASONS.READY
        and result.destinationResolved
        and result.usable ~= false
        and result.usabilityKnown == true
        and result.actionableByPlayer
    -- A known/owned source on cooldown (or recharging) can still be shown in
    -- the informational "Best If Ready" route.  It is never actionable until
    -- the cooldown/charge state clears.
    result.routeEligible = result.destinationResolved
        and source.routeEligible ~= false
        and (result.reason == REASONS.READY
            or result.reason == REASONS.ON_COOLDOWN
            or result.reason == REASONS.NO_CHARGES
            or result.reason == REASONS.EXTERNAL_INTERACTION)
    result.canUse = result.actionableNow
    result.isReady = result.actionableNow
    result.confidence = result.destinationResolved and (result.dynamicDestination and "medium" or "high") or "low"
    result.reasonCode = result.reason
    result.actionType = result.action.type
    result.actionID = result.action.id
    local presentation = Sources.ResolveActionPresentation(result.action, source, state)
    result.displayName = presentation.name
    result.actionName = presentation.name
    result.icon = presentation.icon or source.icon
    result.explanation = Sources.BuildExplanation(result)
    return result
end

function Sources.EvaluateAll(state, options)
    options = options or {}
    state = state or Sources.CreatePlayerState(options)
    local result = {}
    for _, source in ipairs(Sources.GetAll(options)) do
        result[#result + 1] = Sources.Evaluate(source, state, options)
    end
    return result
end

function Sources.Discover(state, options)
    -- Discovery is intentionally a stateful evaluation of the canonical
    -- catalog.  It retains unavailable records for diagnostics instead of
    -- silently dropping sources that the player may unlock later.
    return Sources.EvaluateAll(state, options)
end

Sources.BuildCatalog()

return Sources

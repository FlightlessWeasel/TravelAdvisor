local root = arg[1] or "."

local TA = {}
_G.TravelAdvisor = TA

local source = {
    name = "Taint-safe test spell",
    spellID = 123,
    mapID = 1,
    destinationMapID = 2,
    routeEligible = true,
}
TA.TravelData = {
    ClassTeleports = { source },
}

local forbidden = {}
local realPairs = pairs
setmetatable(forbidden, {
    __pairs = function()
        error("taint-safety repro: forbidden table was iterated")
    end,
})

local api = {
    forbidden = forbidden,
    C_Spell = {
        IsSpellKnown = function() return true end,
        GetSpellName = function() return "Taint-safe test spell" end,
        GetSpellTexture = function() return 1 end,
        GetSpellCooldown = function()
            return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
        end,
        IsSpellUsable = function() return true end,
    },
    GetBindLocation = function() return "Stormwind City" end,
}

_G.GetTime = function() return 100 end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance" end
_G.GetBindLocation = api.GetBindLocation
_G.C_Spell = api.C_Spell

local chunk, err = loadfile(root .. "/TravelSources.lua")
assert(chunk, err)
chunk("TravelAdvisor", TA)

local sources = TA.TravelSources
local options = {
    api = api,
    now = 100,
    class = "WARRIOR",
    race = "Human",
    faction = "Alliance",
    nested = { safe = "retained", forbidden = forbidden },
}

local oldPairs = _G.pairs
_G.pairs = function(value)
    if value == forbidden then
        error("taint-safety repro: forbidden table was iterated")
    end
    return realPairs(value)
end

local function call(label, callback)
    local ok, value = pcall(callback)
    assert(ok, label .. ": " .. tostring(value))
    return value
end

local state = call("CreatePlayerState", function()
    return sources.CreatePlayerState(options)
end)
assert(state.api == api, "CreatePlayerState must preserve the supplied API reference")
assert(state.nested and state.nested.safe == "retained",
    "safe sibling state must survive an inaccessible nested value")
assert(not state.nested or state.nested.forbidden ~= forbidden,
    "inaccessible nested state must not be retained by reference")

local allFromState = call("EvaluateAll(state)", function()
    return sources.EvaluateAll(state, { api = api })
end)
assert(#allFromState > 0, "EvaluateAll(state) must exercise the canonical source path")

call("Evaluate(state)", function()
    return sources.Evaluate(source, state, { api = api })
end)

call("EvaluateRequirements(state)", function()
    return sources.EvaluateRequirements({}, state, source)
end)

local allFromOptions = call("EvaluateAll(options)", function()
    return sources.EvaluateAll(nil, options)
end)
assert(#allFromOptions > 0, "EvaluateAll(options) must create and evaluate player state")

_G.pairs = oldPairs
print("Taint-safety regression: PASS")

local root = arg[1] or "."

local TA = {}
_G.TravelAdvisor = TA
TA.TravelData = {}

local secretValues = {}
local function secretValue()
    local value = newproxy(true)
    secretValues[value] = true
    return value
end

_G.issecretvalue = function(value)
    return secretValues[value] == true
end

local secretNumber = secretValue()
local secretBoolean = secretValue()
local mode = "cooldown"

_G.GetTime = function() return 100 end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance" end
_G.GetBindLocation = function() return "Stormwind City" end

_G.C_Spell = {
    IsSpellKnown = function() return true end,
    GetSpellName = function() return "Secret-safe test spell" end,
    GetSpellTexture = function() return 1 end,
    GetSpellCooldown = function()
        if mode == "cooldown" then
            return {
                startTime = secretNumber,
                duration = secretNumber,
                isEnabled = true,
                modRate = secretNumber,
            }
        end
        return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
    end,
    GetSpellCharges = function()
        if mode == "cooldown" then
            return {
                currentCharges = secretNumber,
                maxCharges = 1,
                cooldownStartTime = secretNumber,
                cooldownDuration = secretNumber,
                chargeModRate = secretNumber,
            }
        end
        return nil
    end,
    IsSpellUsable = function()
        if mode == "usability" then return secretBoolean end
        return true
    end,
}

local chunk, err = loadfile(root .. "/TravelSources.lua")
assert(chunk, err)
chunk("TravelAdvisor", TA)

local source = {
    category = "ClassTeleports",
    kind = "teleport",
    name = "Secret-safe test spell",
    spellID = 123,
    mapID = 1,
}

local function evaluate()
    local ok, result = pcall(function()
        return TA.TravelSources.Evaluate(source, {
            api = _G,
            now = 100,
            class = "WARRIOR",
            race = "Human",
            faction = "Alliance",
        })
    end)
    assert(ok, tostring(result))
    assert(result.actionableNow == false, "secret state must never create an actionable route")
    return result
end

mode = "cooldown"
local cooldownResult = evaluate()
assert(cooldownResult.reason == "api-unavailable",
    "secret cooldown/charge state must be treated as unavailable")

mode = "usability"
local usabilityResult = evaluate()
assert(usabilityResult.reason == "usability-unknown",
    "secret usability state must be treated as unknown")

print("Secret-value safety regression: PASS")

-- ═══════════════════════════════════════════════════════════════════════════
-- TravelAdvisor - versioned per-character settings
-- ═══════════════════════════════════════════════════════════════════════════

local _, TA = ...

local Settings = {
    VERSION = 2,
    MAX_DEBUG_LOGS = 100,
    MAX_DEBUG_TEXT = 80,
    DEFAULTS = {
        routePolicy = "best-now",
        showAlternatives = true,
        showExplanations = true,
        debugLogging = false,
    },
    POLICY_ORDER = {
        "best-now",
        "best-if-ready",
        "best-after-wait",
    },
    POLICY_LABELS = {
        ["best-now"] = "Best Now",
        ["best-if-ready"] = "Best If Ready",
        ["best-after-wait"] = "Best After Wait",
    },
}

local function copyDefaults()
    local result = {}
    for key, value in pairs(Settings.DEFAULTS) do
        result[key] = value
    end
    return result
end

local function normalizeBoolean(value, defaultValue)
    if value == nil then return defaultValue end
    return value == true
end

local function normalizeDebugText(value, limit)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%c]", " "):sub(1, limit)
    if value == "" then return nil end
    return value
end

local function normalizeDebugLogs(logs)
    local result = {}
    if type(logs) ~= "table" then return result end
    local first = math.max(1, #logs - Settings.MAX_DEBUG_LOGS + 1)
    for index = first, #logs do
        local entry = logs[index]
        if type(entry) == "table" then
            local event = normalizeDebugText(entry.event, 40)
            if event then
                result[#result + 1] = {
                    timestamp = normalizeDebugText(entry.timestamp, 32) or "unknown",
                    event = event,
                    mapID = type(entry.mapID) == "number" and entry.mapID or nil,
                    mapName = normalizeDebugText(entry.mapName, Settings.MAX_DEBUG_TEXT),
                    realZone = normalizeDebugText(entry.realZone, Settings.MAX_DEBUG_TEXT),
                    subZone = normalizeDebugText(entry.subZone, Settings.MAX_DEBUG_TEXT),
                }
            end
        end
    end
    return result
end

function Settings:NormalizePolicy(policy)
    if self.POLICY_LABELS[policy] then return policy end
    return self.DEFAULTS.routePolicy
end

function Settings:Load(saved)
    local values = type(saved) == "table" and saved or {}
    local version = tonumber(values.version) or 0

    -- Version 0 had no documented schema.  Accept the names that early
    -- development builds used so settings never silently select a different
    -- policy after an addon update.
    if version < 1 then
        values.routePolicy = values.routePolicy or values.selectedPolicy or values.policy
        if values.showAlternatives == nil and values.showBestIfReady ~= nil then
            values.showAlternatives = values.showBestIfReady == true
        end
        if values.showExplanations == nil and values.showDetails ~= nil then
            values.showExplanations = values.showDetails == true
        end
    end

    local defaults = copyDefaults()
    for key, defaultValue in pairs(defaults) do
        if values[key] == nil then values[key] = defaultValue end
    end

    values.version = self.VERSION
    values.routePolicy = self:NormalizePolicy(values.routePolicy)
    values.showAlternatives = normalizeBoolean(values.showAlternatives, defaults.showAlternatives)
    values.showExplanations = normalizeBoolean(values.showExplanations, defaults.showExplanations)
    values.debugLogging = normalizeBoolean(values.debugLogging, defaults.debugLogging)
    values.debugLogs = normalizeDebugLogs(values.debugLogs)

    self.values = values
    _G.TravelAdvisor_Settings = values
    return values
end

function Settings:Get(key)
    if not self.values then self:Load(_G.TravelAdvisor_Settings) end
    return self.values[key]
end

function Settings:Set(key, value)
    if not self.values then self:Load(_G.TravelAdvisor_Settings) end
    if key == "routePolicy" then
        value = self:NormalizePolicy(value)
    elseif key == "showAlternatives" or key == "showExplanations" or key == "debugLogging" then
        value = value == true
    elseif key == "debugLogs" then
        value = normalizeDebugLogs(value)
    end
    self.values[key] = value
    _G.TravelAdvisor_Settings = self.values
end

function Settings:AddDebugLog(entry)
    if not self.values then self:Load(_G.TravelAdvisor_Settings) end
    local logs = normalizeDebugLogs(self.values.debugLogs)
    local normalized = normalizeDebugLogs({ entry })
    if #normalized == 0 then return end
    logs[#logs + 1] = normalized[1]
    if #logs > self.MAX_DEBUG_LOGS then table.remove(logs, 1) end
    self.values.debugLogs = logs
    _G.TravelAdvisor_Settings = self.values
end

function Settings:GetPolicyLabel(policy)
    return self.POLICY_LABELS[self:NormalizePolicy(policy)]
end

function Settings:CyclePolicy()
    local current = self:NormalizePolicy(self:Get("routePolicy"))
    for index, policy in ipairs(self.POLICY_ORDER) do
        if policy == current then
            local nextIndex = index % #self.POLICY_ORDER + 1
            self:Set("routePolicy", self.POLICY_ORDER[nextIndex])
            return self.POLICY_ORDER[nextIndex]
        end
    end
    self:Set("routePolicy", self.POLICY_ORDER[1])
    return self.POLICY_ORDER[1]
end

Settings:Load(_G.TravelAdvisor_Settings)
TA.TravelAdvisorSettings = Settings
TA.Settings = Settings

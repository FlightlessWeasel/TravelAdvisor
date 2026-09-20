-- ═══════════════════════════════════════════════════════════════════════════
-- TravelAdvisor - versioned per-character settings
-- ═══════════════════════════════════════════════════════════════════════════

local _, TA = ...

local Settings = {
    VERSION = 1,
    DEFAULTS = {
        routePolicy = "best-now",
        showAlternatives = true,
        showExplanations = true,
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
    elseif key == "showAlternatives" or key == "showExplanations" then
        value = value == true
    end
    self.values[key] = value
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

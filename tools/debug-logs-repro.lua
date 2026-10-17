local root = arg[1] or "."
TA = {}
TravelAdvisor_Settings = {
    version = 1,
    routePolicy = "best-if-ready",
    debugLogging = true,
    debugLogs = {
        { timestamp = "t", event = "ZONE_CHANGED", mapID = 42, mapName = "Zone", realZone = "Real", subZone = "Sub", ignored = "drop" },
        { event = "" },
        "invalid",
    },
}

local chunk, err = loadfile(root .. "/TravelAdvisorSettings.lua")
assert(chunk, err)
chunk("TravelAdvisor", TA)

local settings = TA.Settings
local values = settings:Get("debugLogging") and settings.values
assert(settings.VERSION == 2, "settings schema must be version 2")
assert(values.version == 2, "legacy saved settings must migrate to schema v2")
assert(values.routePolicy == "best-if-ready", "migration must preserve the selected route policy")
assert(values.debugLogging == true, "saved debug preference must survive migration")
assert(#values.debugLogs == 1, "malformed debug entries must be discarded")
local entry = values.debugLogs[1]
assert(entry.timestamp == "t" and entry.event == "ZONE_CHANGED", "valid log fields must be retained")
assert(entry.mapID == 42 and entry.mapName == "Zone", "map identity must be retained")
assert(entry.realZone == "Real" and entry.subZone == "Sub", "zone labels must be retained")
assert(entry.ignored == nil, "unapproved fields must be removed")

settings:Set("debugLogs", {
    { event = "X", timestamp = string.rep("t", 50), mapName = string.rep("m", 100), subZone = "line\nbreak" },
})
entry = settings:Get("debugLogs")[1]
assert(#entry.timestamp == 32, "timestamp text must be capped")
assert(#entry.mapName == 80, "location text must be capped")
assert(entry.subZone == "line break", "control characters must be normalized")

settings:Set("debugLogs", {})
for index = 1, 105 do
    settings:AddDebugLog({ timestamp = "t" .. index, event = "ZONE_CHANGED", mapID = index })
end
local logs = settings:Get("debugLogs")
assert(#logs == 100, "debug logs must be bounded to 100 records")
assert(logs[1].mapID == 6 and logs[100].mapID == 105, "bounded logs must retain the newest records")
assert(TravelAdvisor_Settings == values, "saved-variable global must track normalized settings")

print("Debug logs settings regression: PASS")

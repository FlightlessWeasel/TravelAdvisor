local root = arg[1] or "."
TA = {}
TravelAdvisor_Settings = {
    version = 1,
    routePolicy = "best-if-ready",
    debugLogging = true,
    debugLogs = {
        { timestamp = "t", event = "ZONE_CHANGED", mapID = 42, mapName = "Zone", realZone = "Real", subZone = "Sub", ignored = "drop" },
        { timestamp = string.rep("s", 120), event = string.rep("E", 140), mapName = string.rep("M", 160), realZone = string.rep("R", 180), subZone = string.rep("U", 200) },
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
assert(#values.debugLogs == 2, "valid saved records must remain on load; malformed entries must be discarded")
local entry = values.debugLogs[1]
assert(entry.timestamp == "t" and entry.event == "ZONE_CHANGED", "valid log fields must be retained")
assert(entry.mapID == 42 and entry.mapName == "Zone", "map identity must be retained")
assert(entry.realZone == "Real" and entry.subZone == "Sub", "zone labels must be retained")
assert(entry.ignored == nil, "unapproved fields must be removed")
assert(#values.debugLogs[2].timestamp == 120 and #values.debugLogs[2].event == 140, "long timestamp and event fields must be preserved on load")
assert(#values.debugLogs[2].mapName == 160 and #values.debugLogs[2].realZone == 180 and #values.debugLogs[2].subZone == 200, "long location fields must be preserved on load")

settings:Set("debugLogs", {
    { event = "X", timestamp = string.rep("t", 50), mapName = string.rep("m", 100), subZone = "line\nbreak" },
})
entry = settings:Get("debugLogs")[1]
assert(#entry.timestamp == 50, "timestamp text must be preserved")
assert(#entry.mapName == 100, "location text must be preserved")
assert(entry.subZone == "line break", "control characters must be normalized")

settings:Set("debugLogs", {})
for index = 1, 105 do
    settings:AddDebugLog({ timestamp = "t" .. index, event = "ZONE_CHANGED", mapID = index })
end
settings:AddDebugLog({
    timestamp = string.rep("t", 120),
    event = string.rep("E", 140),
    mapName = string.rep("M", 160),
    realZone = string.rep("R", 180),
    subZone = "line\nbreak",
    ignored = "drop",
})
local logs = settings:Get("debugLogs")
assert(#logs == 106, "all debug records must persist without a history cap")
assert(logs[1].mapID == 1 and logs[105].mapID == 105, "debug logs must retain insertion order")
entry = logs[106]
assert(#entry.timestamp == 120 and #entry.event == 140, "long append timestamp and event fields must be preserved")
assert(#entry.mapName == 160 and #entry.realZone == 180, "long append location fields must be preserved")
assert(entry.subZone == "line break", "control characters must be normalized on append")
assert(entry.ignored == nil, "unapproved fields must be removed on append")
assert(TravelAdvisor_Settings == values, "saved-variable global must track normalized settings")

print("Debug logs settings regression: PASS")

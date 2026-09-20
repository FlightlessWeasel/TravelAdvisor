--[[
    LibZoneNameToMap-1.0
    O(1) zone name -> map ID lookup with normalized (no spaces/punctuation) cache.
    Embeddable via LibStub. Other addons can use this for GetBindLocation() etc.
]]
local LibStub = LibStub
local lib = LibStub and LibStub:NewLibrary("LibZoneNameToMap-1.0", 1)
if not lib then return end

lib._direct = nil   -- [lowercase name] = mapID
lib._normalized = nil  -- [normalized name] = mapID

function lib:RegisterData(zoneNameToID)
    if not zoneNameToID or type(zoneNameToID) ~= "table" then return end
    self._direct = zoneNameToID
    self._normalized = {}
    for name, mapID in pairs(zoneNameToID) do
        local norm = name:gsub("%s+", ""):gsub("'", ""):gsub("-", "")
        if norm ~= "" and self._normalized[norm] == nil then
            self._normalized[norm] = mapID
        end
    end
end

function lib:GetMapIDFromZoneName(zoneName)
    if not zoneName or zoneName == "" or zoneName == "Unknown" then return nil end
    if not self._direct then return nil end
    local lower = zoneName:lower()
    if self._direct[lower] then return self._direct[lower] end
    local norm = lower:gsub("%s+", ""):gsub("'", ""):gsub("-", "")
    return self._normalized[norm]
end

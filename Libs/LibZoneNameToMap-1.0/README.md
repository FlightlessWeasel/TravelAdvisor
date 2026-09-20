# LibZoneNameToMap-1.0

Optional embeddable library for **O(1) zone name → map ID** lookup.

- **RegisterData(zoneNameToID)** – Register a table `[zoneName] = mapID` (keys can be any casing; normalized cache is built automatically).
- **GetMapIDFromZoneName(zoneName)** – Returns `mapID` or `nil`. Handles lowercase and normalized (no spaces/apostrophes/dashes) matching.

Other addons can embed this via LibStub and register their own zone tables (e.g. for bind location, waypoints, or map UI). TravelAdvisor registers `TA.TravelData.ZoneNameToID` on load and uses the lib for the fast path; fallbacks (ZoneCoordinates, PortalHubs) remain in the addon.

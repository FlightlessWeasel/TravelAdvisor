# Libraries

## Embedded

- **LibStub** – Library loader/versioning.
- **LibZoneNameToMap-1.0** – Zone name → map ID lookup (optional). TravelAdvisor registers `ZoneNameToID` on load; other addons can embed and register their own data.
- **CallbackHandler-1.0** – Used by LibDataBroker.
- **LibDataBroker-1.1** – DataBroker (e.g. minimap icon) support.

## Possible future extraction

- **Graph / pathfinding** – `TravelGraph.lua` is a self-contained weighted graph with Dijkstra, priority queue, and edge types. Could be split into a generic **LibGraph** or **LibPathfinder** if you want to reuse it in another addon (e.g. “shortest path” on a custom node/edge set). Remaining code would stay TravelAdvisor-specific (travel data, UI, TomTom).
- **Travel data** – Spell/item/zone tables are addon-specific; sharing them would mean a separate data addon or lib that others depend on, which is only worth it if multiple addons need the same dataset.

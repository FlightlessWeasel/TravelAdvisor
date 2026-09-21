# TravelAdvisor Master Plan

Status: Active  
Last updated: 2026-09-20  
Scope: Make TravelAdvisor a reliable, destination-aware route planner for World of Warcraft travel sources.

Supported client target: Retail/mainline World of Warcraft 12.1.x, beginning with the 12.1.0 client interface `120100`. The target and API assumptions are documented in [VALIDATION.md](VALIDATION.md). Patch-specific travel data and API behavior still require in-game verification on the exact live build.

## How to use this plan

This is the working backlog for the addon. Tackle the items in dependency order unless a documented reason requires a different order.

For every item:

1. Read the scope, dependencies, acceptance criteria, and validation requirements.
2. Make the smallest coherent implementation or data change.
3. Run the listed static or automated validation.
4. Perform the required in-game verification for items marked IN-GAME.
5. Record the completion evidence in the item before changing [ ] to [x].
6. Update this plan when a design decision, API assumption, source type, or supported game version changes.

An item is done only when its acceptance criteria and validation evidence are complete. Do not mark an item done because the code merely loads or because a route appears in one test case.

Use these labels:

- ARCHITECTURE: a design decision must be recorded before implementation.
- IN-GAME: static inspection cannot establish correctness; verify in WoW.
- RELEASE BLOCKER: do not ship with this item incomplete.

If an item is blocked, leave it unchecked and record the blocker, attempted alternatives, and the next action. Do not silently skip it.

Completion record template:

    Date:
    Commit or PR:
    Automated/static validation:
    In-game evidence:
    Notes:

## Product goal

Given a destination region, recommend the fastest valid route using the travel options the current player can actually use, including:

- Known spells and class abilities.
- Owned items and usable toys.
- Hearthstone variants and bind locations.
- Portals, teleports, portal rooms, and hub transitions.
- Flight paths, taxis, boats, zeppelins, ferries, and other transports.
- Profession, faction, quest, reputation, specialization, and location restrictions.
- Travel sources that land in the target region or at a useful nearby region.

The addon must clearly distinguish:

- Ready now.
- Known or owned but on cooldown.
- Known or owned but currently unusable.
- Not known, not owned, or not unlocked.
- Destination unknown or player-selected.

The addon must never offer an unavailable travel source as an executable action.

## Scope boundaries and assumptions

TravelAdvisor cannot safely infer the destination semantics of every arbitrary spell, item, toy, portal, or transport from the WoW API alone. Automatic discovery can find candidates, but reliable destination and restriction data may still require curated metadata or user configuration.

The plan therefore supports both:

- Automatic discovery of candidate spells, items, toys, and abilities.
- Curated source metadata for destination, restrictions, timing, and interaction requirements.

The exact WoW game build and supported expansion range must be recorded before release. API behavior, map IDs, portal availability, and travel data are version-sensitive.

## Current implementation snapshot

The addon currently contains a manually curated travel catalog and a weighted graph. It has partial detection for known spells, bag items, toys, faction checks, and configured unlock quests; static portal hubs; route calculation; and TomTom integration.

It does not yet reliably satisfy the intended behavior because:

- The catalog is not a complete automatic inventory of travel sources.
- The legacy scanner and graph scanner duplicate eligibility logic and can disagree.
- Cooldown, charge, usability, ownership, and enabled-state handling is incomplete.
- Cached routes can outlive cooldown, bag, toy, spellbook, specialization, bind, and zone changes.
- A “Best If Ready” route can create a usable-looking action even when its source is on cooldown.
- Static topology is incomplete; ZoneConnections is defined but not consumed, and intermediate hubs are not generally modeled.
- Dynamic destinations and mapID 0 sources are not resolved safely.
- Travel time estimates are approximate and do not represent all real transport modes.
- The data contains duplicate and contradictory map definitions.
- There is currently no automated test suite or data-validation harness.

## Must-not-regress rules

These rules apply to every future change:

- Never use an array index as a WoW map ID.
- Never add mapID 0 or another unresolved placeholder as a routable destination node.
- Never create or leave an executable Use action for a source that is on cooldown, has no charges, is disabled, is unusable, or has an unknown destination.
- Never use a localized spell name as the primary action identity when a spell ID is available.
- Never configure a hearthstone toy as an ordinary item action if the secure action requires toy semantics.
- Never assume that a static portal, flight path, transport, or hub is available without applying its access requirements.
- Never allow a cached route to conceal a player-state change that can affect availability.
- Never call a route “fastest” without stating whether waiting for cooldowns is included.
- Never conflate an instance map, entrance map, landing map, and surrounding region map.
- Never maintain two independent source-eligibility implementations.
- Never mark an IN-GAME item complete from static inspection alone.

## Phase 0 — Baseline, decisions, and validation infrastructure

### [x] TA-000 — Record the baseline

Priority: RELEASE BLOCKER  
Depends on: None

Scope:

- Record the current addon behavior and limitations in this document.
- Preserve the current source references for known defects.
- Record that the initial review was static and that no Lua runtime or automated tests currently exist.

Acceptance criteria:

- The current implementation snapshot above remains accurate.
- Every known critical or high-risk issue from the review has a corresponding task below.

Validation:

- Static review of TravelAdvisor.lua, TravelGraph.lua, TravelData.lua, and the TOC.

Completion evidence:

    Date: 2026-09-19
    Commit or PR: Working tree baseline; no commit created.
    Automated/static validation: Static review completed for TravelAdvisor.lua, TravelGraph.lua, TravelData.lua, and TravelAdvisor.toc. The WoW MCP Retail/mainline Lua lint and TOC checks were also run; they found no Lua syntax errors but reported moved APIs and combat-protected UI mutations that are tracked by TA-103 through TA-107. No local Lua runtime or automated test suite existed before Phase 0.
    In-game evidence: None; this baseline is explicitly static.
    Notes: High-risk findings are tracked in TA-101 through TA-107 and the later canonical-source, topology, data-integrity, and release-gate tasks.

### [x] TA-001 — Choose the supported WoW API and data target

Priority: ARCHITECTURE  
Depends on: TA-000

Decide and document:

- The supported WoW client/build and expansion range.
- Whether retail-only, classic-only, or multiple client branches are supported.
- Which Blizzard APIs are authoritative for spell cooldowns, charges, toys, item cooldowns, map IDs, and usability.
- How patch-specific travel data is versioned and updated.

Acceptance criteria:

- The target is written in this plan and in the addon documentation.
- API assumptions are linked to the supported client version in [VALIDATION.md](VALIDATION.md) and remain marked for in-game verification where static inspection is insufficient.

Decision for Phase 0: Retail/mainline WoW 12.1.x, starting at interface `120100`; no Classic client branch is supported by this addon.

Completion evidence:

    Date: 2026-09-19
    Commit or PR: Working tree; no commit created.
    Automated/static validation: `TravelAdvisor.toc` targets `120100`; API assumptions and references are recorded in VALIDATION.md.
    In-game evidence: Pending; the verification matrix remains open for exact live-build confirmation.
    Notes: The target is documented, but patch-specific travel data remains subject to the Phase 0 matrix and later data-maintenance tasks.

### [x] TA-002 — Add a test and data-validation harness

Priority: RELEASE BLOCKER  
Depends on: TA-001

Scope:

- Add a repeatable Lua test harness or pure-data validation command that can run outside WoW where practical.
- Add mocks or fixtures for graph nodes, travel sources, player state, cooldowns, charges, and route policies.
- Add validation for duplicate map definitions, missing nodes, invalid edges, invalid source IDs, unresolved destinations, and contradictory metadata.
- Make validation fail with a useful file, source, and field description.

Acceptance criteria:

- A single documented command runs the available checks.
- The validator can detect the currently known duplicate and contradictory data cases.
- Route and source tests can be added without requiring a live WoW client.

Phase 0 implementation: `node tools/check.js` is the single documented command; it runs the dependency-free static validator and the source/destination and route-policy contract fixtures. The validator intentionally reports the known baseline defects until the corresponding Phase 5 data tasks correct them.

Completion evidence:

    Date: 2026-09-19
    Commit or PR: Working tree; no commit created.
    Automated/static validation: `node tools/phase0.test.js` passes. `node tools/validate.js` runs and reports 42 baseline errors, including both duplicate coordinate keys, a duplicate stable source ID, and contradictory dungeon destination identities. `node tools/check.js` runs both checks and exits non-zero because those baseline findings are intentional.
    In-game evidence: Not applicable to the static harness itself.
    Notes: The non-zero validator result is expected until the tracked data-integrity tasks are completed.

### [ ] TA-003 — Define the in-game verification matrix

Priority: IN-GAME  
Depends on: TA-001

Cover at least:

- Each supported faction and representative class.
- Known spells, spell overrides, items, toys, hearthstones, and profession sources.
- Ready, cooldown, disabled, unusable, zero-charge, and missing-source states.
- Bind-location fallback and unknown bind maps.
- Bag updates, toy collection, spellbook changes, specialization changes, talent or unlock changes, and zone changes.
- Combat lockdown while routes are displayed and while the player uses a travel action.
- Fixed, bind, return, choice, random, nearby, portal, flight, dungeon, and transport destinations.

Acceptance criteria:

- Each test has expected behavior, observed behavior, date, character context, and client build.
- The matrix is used by release verification rather than kept as an informal list.

Phase 0 implementation: The required matrix is recorded in [VALIDATION.md](VALIDATION.md). Rows remain pending until executed in the WoW 12.1 client with character and build evidence.

### [ ] TA-004 — Decide route semantics before optimizing

Priority: ARCHITECTURE  
Depends on: TA-001

Decide and document:

- Whether “fastest” means fastest immediately, fastest after waiting for a cooldown, or both.
- Whether “Best If Ready” is informational only or may be selected as an action after its cooldown expires.
- Whether waiting time, number of clicks, number of transitions, estimated movement time, and uncertainty have separate route policies.
- Whether a route to a nearby region is acceptable when no direct route lands in the exact target region.
- How random and player-choice destinations are ranked.
- Whether user-defined travel sources are in scope.

Acceptance criteria:

- The UI labels and route-policy names follow the decisions.
- Tests exist for each selected policy.

Phase 0 decision: `Best Now` contains only routes that are ready and executable immediately. `Best If Ready` is informational only and must never expose an executable action while its first required source is unavailable. `Best After Wait` is the elapsed-time policy and includes cooldown wait time. External interactions and unresolved/random/player-choice destinations remain explicit uncertainty rather than being presented as deterministic local actions. The fixture contract tests cover these policy distinctions; the runtime action-safety implementation is tracked by TA-103 through TA-105.

## Phase 1 — Immediate correctness and action safety

### [ ] TA-101 — Fix the malformed bind fallback AddNode call

Priority: RELEASE BLOCKER  
Depends on: TA-000

Observed issue:

- TravelGraph.lua:106 defines AddNode(mapID, data).
- TravelGraph.lua:1097 calls AddNode with a node table as the first argument and no data.
- If the bind map is missing, data.name can be accessed on nil and route generation can fail.

Required change:

- Pass the bind map ID and node data as separate arguments.
- Add a regression test for a bind map that is not already in the graph.

Acceptance criteria:

- A missing bind node is created without an error.
- An existing bind node is updated or reused without duplicate corruption.

### [ ] TA-102 — Return hub.mapID from bind-location fallback

Priority: RELEASE BLOCKER  
Depends on: TA-000

Observed issue:

- TravelAdvisor.lua:93-103 and TravelGraph.lua:977-985 iterate the PortalHubs array and return the array key instead of hub.mapID.

Required change:

- Return hub.mapID.
- Add a test proving the result is a valid map ID and not the array position.

### [ ] TA-103 — Make cooldown routes non-actionable

Priority: RELEASE BLOCKER  
Depends on: TA-202

Observed issue:

- TravelGraph.lua:615 builds both ready-only and optimal routes.
- TravelAdvisor.lua:2728 creates a secure action button for a route when canUse is true without requiring cooldown == 0 or a ready-only route.

Required change:

- A source on cooldown, disabled, unusable, out of charges, or with an unknown destination may remain visible as information, but must not receive an executable Use action.
- Revalidate readiness immediately before use where the API permits.
- Make the distinction between route visibility and route executability explicit in the route model.

Acceptance criteria:

- A Best If Ready route never attempts to activate an on-cooldown source.
- The UI displays the remaining cooldown and a non-actionable state.
- A source that becomes unavailable after route creation cannot be activated through a stale button.

### [ ] TA-104 — Correct secure action metadata for every source kind

Priority: RELEASE BLOCKER  
Depends on: TA-103

Required change:

- Use spell IDs rather than hardcoded English spell names.
- Use the correct secure action type for spells, ordinary items, toys, and hearthstone toys.
- Ensure icons, tooltips, labels, and action metadata describe the same source.

Acceptance criteria:

- The action works on a non-English client where the source is otherwise usable.
- A collected hearthstone toy is configured as a toy action when required by the WoW secure-action API.
- Every supported source kind has an explicit action-type test and in-game verification.

### [ ] TA-105 — Make secure UI rebuilds combat-safe

Priority: RELEASE BLOCKER  
Depends on: TA-103

Required change:

- Do not create, reconfigure, hide, or otherwise mutate protected action buttons during combat lockdown.
- Queue route-row and secure-button changes until PLAYER_REGEN_ENABLED or the appropriate safe point.
- Keep the display state and action state consistent while a rebuild is deferred.

Acceptance criteria:

- Opening or refreshing the route display in combat does not produce blocked-action errors or taint.
- Pending changes are applied after combat.

### [ ] TA-106 — Handle unknown current and destination maps safely

Priority: RELEASE BLOCKER  
Depends on: TA-000

Required change:

- Handle nil or unknown results from C_Map.GetBestMapForUnit and equivalent APIs.
- Do not concatenate or index nil map IDs in the route-cache key.
- Exclude unresolved destinations from fastest-route calculations or represent them as explicitly unknown and non-actionable.

Acceptance criteria:

- Instances, scenarios, phases, and unsupported maps do not cause an error.
- The UI explains when a route cannot be calculated because the current or destination map is unknown.

### [ ] TA-107 — Invalidate route state when player state changes

Priority: RELEASE BLOCKER  
Depends on: TA-103, TA-202

Observed issue:

- TravelAdvisor.lua:35-37 uses a 15-second route cache.
- TravelAdvisor.lua:2501-2510 checks the cache before scanning player edges.
- TravelAdvisor.lua:2936-2942 registers mainly zone/loading events.

Required change:

- Add a coalesced invalidation and refresh path for cooldown changes, bag changes, toy changes, spellbook changes, specialization/talent changes, entering the world, zone changes, and travel/bind changes.
- Refresh or invalidate after a travel source is used.
- Avoid excessive rescans by coalescing bursts of events.

Acceptance criteria:

- A newly available source appears without waiting for the old cache TTL.
- A newly unavailable source disappears or becomes non-actionable immediately.
- Cooldown expiry updates the route display.

## Phase 2 — Canonical source and player-state model

### [x] TA-201 — Define one canonical travel-source schema

Priority: RELEASE BLOCKER  
Depends on: TA-001, TA-002

Every source record should be able to represent, as applicable:

- Stable source key and source kind.
- Spell ID, item ID, toy ID, or transport identifier.
- Localized display name and icon resolved from the ID.
- Destination resolver and destination type.
- Requirements: faction, class, race, specialization, profession, quest, reputation, expansion, location, and unlock state.
- Ownership or known state.
- Enabled, usable, charge, and cooldown state.
- Failure reason and confidence.
- Correct action type and secure-action configuration.
- Estimated cast, wait, interaction, and travel time.

Acceptance criteria:

- The graph, route converter, UI, tooltips, and action buttons consume this representation.
- No second ad hoc source shape is introduced for a new source category.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: TravelSources.lua normalizes all eight curated source families into stable keys, requirements, destination metadata, action config, timing, and confidence fields. Phase 2 contract tests pass.
    In-game evidence: Pending; exact live-client source and localization behavior remains in the verification matrix.
    Notes: TravelAdvisor.lua and TravelGraph.lua consume canonical evaluations while preserving the legacy adapter fields.

### [x] TA-202 — Implement one canonical availability evaluator

Priority: RELEASE BLOCKER  
Depends on: TA-201

Evaluate separately:

- Known or owned.
- Enabled.
- Requirements satisfied.
- Usable in the current context.
- Has charges or quantity.
- Cooldown remaining.
- Destination resolved.
- Actionable now.

Use the authoritative APIs for the chosen client version. Account for spell overrides, charge cooldowns, modRate, item cooldowns, toy cooldowns, resources, location restrictions, and other source-specific restrictions.

Acceptance criteria:

- The evaluator returns a state and a reason, not only a boolean.
- The same evaluator is used by discovery, graph construction, route ranking, tooltips, and buttons.
- The distinction between unavailable, cooldown, unknown, and ready is test-covered.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: Sources.Evaluate and Sources.EvaluateAll separately retain known/owned, enabled, requirements, usable, charges/quantity, cooldown, destination resolution, actionability, and stable reasons. WoW MCP lint reports 0 errors for TravelSources.lua; Phase 2 contract tests pass.
    In-game evidence: Pending; spell override, charge, modRate, item, toy, and profession behavior still require live-client verification.
    Notes: Unavailable or unresolved sources are retained for diagnostics but are not added as routable player edges; cooldown and recharge sources may remain informationally routable for "Best If Ready" without becoming actionable.

### [x] TA-203 — Retire duplicate scanner behavior

Priority: RELEASE BLOCKER  
Depends on: TA-202

Observed issue:

- TravelAdvisor.lua:405-674 contains a legacy ScanAvailableTravel path.
- TravelGraph.lua:1130 onward contains graph-based ScanPlayerEdges logic.
- They apply different usability and cooldown rules, including different spell-usable checks.

Required change:

- Route all discovery through the canonical evaluator.
- Remove or deprecate the legacy scanner after parity tests pass.
- Document the migration so future source types are not added to both systems.

Acceptance criteria:

- Both old and new route entry points produce the same source state during the migration period.
- The legacy path is deleted or clearly marked as compatibility-only and cannot silently diverge.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: ScanAvailableTravel and ScanPlayerEdges route through TravelSources:EvaluateAll; the former direct scanners are disabled compatibility blocks. Active-source contract checks confirm no duplicate spell/item evaluator remains.
    In-game evidence: Pending; parity across representative characters remains in the verification matrix.
    Notes: Legacy route fallback is no longer used once the graph is initialized.

### [x] TA-204 — Implement destination resolver types

Priority: RELEASE BLOCKER  
Depends on: TA-201

Support explicit resolver modes:

- Fixed destination.
- Current hearthstone bind.
- Return-to-previous-location.
- Player choice.
- Random destination.
- Nearby or closest useful region.
- Hub or portal-room destination.
- Unknown destination.

Acceptance criteria:

- mapID 0 is never treated as a normal destination node.
- A fixed destination resolves to a valid map.
- A dynamic destination is either resolved from current player state or shown as non-actionable informational travel.
- Random and choice semantics follow TA-004.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: ResolveDestination classifies fixed, bind, previous, choice, random, nearby, hub, and unknown destinations; dynamic or unresolved records cannot produce graph edges. Phase 2 fixtures cover bind, choice, and random behavior.
    In-game evidence: Pending; return, nearby, and multi-destination source behavior requires live verification.
    Notes: Positive map IDs are retained as metadata for random/choice anchors but remain non-routable until a concrete destination is resolved.

### [x] TA-205 — Separate static topology from dynamic player state

Priority: ARCHITECTURE  
Depends on: TA-201

Required design:

- Static data describes possible nodes, edges, source metadata, and requirements.
- A player-state snapshot describes current location, known sources, ownership, cooldowns, charges, unlocks, and restrictions.
- Route calculation combines the two without mutating static data with temporary player state.

Acceptance criteria:

- Recalculating after a cooldown or bag change does not rebuild or corrupt static definitions.
- The same static graph can be evaluated for different player fixtures.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: TravelGraph stores dynamicNodes and playerSourceStates separately from static nodes/edges; canonical evaluations use a fresh player-state snapshot and ClearPlayerEdges clears only dynamic state. Phase 2 state-preservation tests pass.
    In-game evidence: Pending; repeated scans across bag, cooldown, bind, and specialization changes remain matrix work.
    Notes: Static catalog records are copied before evaluation, so dynamic bind resolution does not mutate TravelData.

### [x] TA-206 — Give every excluded source a useful reason

Priority: RELEASE BLOCKER  
Depends on: TA-202, TA-204

Provide stable reason categories such as:

- Not known.
- Not owned.
- Not collected.
- On cooldown.
- No charges or quantity.
- Disabled.
- Requirements not met.
- Wrong faction or specialization.
- Wrong profession.
- Unusable in this location.
- Destination unresolved.
- Unsupported source type.

Acceptance criteria:

- The UI and diagnostics can show the reason without duplicating evaluator logic.
- Tests cover at least one source for each reason category.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: Stable reason codes and text are exposed by TravelSources:GetReasonText and consumed by route status/tooltips and no-route source diagnostics. Phase 2 fixtures cover known, owned, collected, cooldown, charges, disabled, usability, unknown API/requirements, faction/class/race/spec/profession, quest, reputation, location, destination, and unsupported-source states.
    In-game evidence: Pending; reason wording and API edge cases require live-client review.
    Notes: Excluded evaluations remain available through Graph.playerSourceStates for diagnostics.

## Phase 3 — Source discovery and coverage

### [x] TA-301 — Discover known spells consistently

Priority: HIGH  
Depends on: TA-202, TA-203

Scope:

- Scan the relevant spellbook and known-spell APIs.
- Resolve spell overrides and current spell IDs.
- Preserve metadata for class, race, faction, specialization, talent, quest, and location requirements.

Acceptance criteria:

- Known and unknown spells produce the expected source state.
- A known but unusable spell is not reported as ready.

### [x] TA-302 — Discover owned items and collected toys

Priority: HIGH  
Depends on: TA-202, TA-203

Scope:

- Scan bags and relevant containers for supported item sources.
- Scan collected toys and resolve toy usability/cooldown.
- Distinguish an item in the bag from a collected toy with the same or equivalent destination.

Acceptance criteria:

- Bag quantity, item cooldown, toy ownership, and toy cooldown are reflected.
- Item and toy actions are not interchangeable in the secure-button configuration.

### [x] TA-303 — Support profession and engineering travel sources

Priority: HIGH  
Depends on: TA-202

Observed issue:

- TravelData.lua:318-338 contains profession entries.
- The graph scanner uses profOk = not item.profession, causing profession sources to be skipped.

Required change:

- Evaluate the player profession and skill requirement.
- Include Engineering and other supported profession sources.
- Record missing profession or skill as a reason.

Acceptance criteria:

- A qualified character can route through the source.
- An unqualified character sees it as unavailable with a clear reason.

### [x] TA-304 — Integrate MagePortals with explicit interaction semantics

Priority: ARCHITECTURE  
Depends on: TA-001, TA-004, TA-201

Decide whether a mage portal is:

- A direct player travel action.
- A portal interaction requiring a mage or another player.
- An informational route step that cannot be executed by the addon.

Then:

- Integrate it into the canonical source and graph model if in scope.
- Ensure the UI labels the required interaction.

Acceptance criteria:

- Mage portal entries are not silently present only in the legacy scanner.
- A route cannot present a required external player interaction as an executable local action.

### [x] TA-305 — Implement Mole Machine and other multi-destination sources

Priority: HIGH  
Depends on: TA-204

Observed issue:

- TravelData.lua:409-423 defines MoleMachineDestinations but no route logic consumes it.

Required change:

- Resolve the destination selection or expose it as a user-choice interaction.
- Add the required profession, location, and availability checks.

Acceptance criteria:

- Every supported Mole Machine destination is represented correctly.
- An unresolved player choice is not ranked as a deterministic fastest route.

### [x] TA-306 — Resolve class, racial, return, and mapID 0 sources

Priority: HIGH  
Depends on: TA-204

Review and implement explicit resolver behavior for the dynamic entries in TravelData.lua:144-163, TravelData.lua:351, and TravelData.lua:385-400, including Astral Recall, return abilities, racial travel, and other sources with mapID 0.

Acceptance criteria:

- Each source has a concrete resolver, an intentional informational-only state, or documented exclusion.
- No unresolved mapID 0 source is used in pathfinding.

### [x] TA-307 — Add discovery for supported source families without overclaiming

Priority: HIGH  
Depends on: TA-301, TA-302, TA-303, TA-304, TA-305, TA-306

Expand the catalog and discovery process for supported:

- Teleports and portals.
- Hearthstone variants.
- Toys.
- Class, racial, and profession travel.
- Dungeon or scenario teleports.
- Portal rooms and hub transitions.
- Boats, zeppelins, ferries, and taxi routes where data is reliable.

Acceptance criteria:

- The supported source families are documented.
- Unsupported or semantically ambiguous sources are reported as such rather than guessed.
- Adding a source requires metadata and tests.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: TravelSources now discovers spell, item, toy, profession, class, racial, dungeon, hearthstone, and mage-portal records through the canonical evaluator. Profession skill metadata, explicit external/player-choice/setup interactions, dynamic mapID 0 resolvers, and source-family coverage metadata are covered by `node tools/phase3.test.js`; Phase 0–2 contract tests remain passing.
    In-game evidence: Pending; exact live-client spell overrides, toy usability, profession skill API behavior, dynamic selections, and secure-action behavior remain in the verification matrix.
    Notes: Mage portals are informational external-player interactions; Mole Machine destinations are represented as explicit choices; boats, zeppelins, ferries, and taxi routes are documented as informational-only until authoritative access data is available.

## Phase 4 — Graph topology and route ranking

### [x] TA-401 — Consume ZoneConnections and add intermediate hubs

Priority: RELEASE BLOCKER  
Depends on: TA-205, TA-307

Observed issue:

- TravelData.lua:429-442 defines ZoneConnections.
- TravelGraph.lua:745-822 builds the graph without consuming those connections.
- Implicit flight is generally added only to the final destination.

Required change:

- Add intermediate flight and transport hubs.
- Allow paths such as current zone to hub to capital to portal room to target region.
- Allow any resolved portal or teleport landing to continue through an eligible
  region and an approximate final flight to the target.
- Ensure each transition has its own access checks and estimated cost.

Acceptance criteria:

- Multi-hop routes are found when no direct edge exists.
- The graph does not invent a direct edge merely because two maps share a continent.

### [x] TA-402 — Model travel modes explicitly

Priority: HIGH  
Depends on: TA-401

Represent, as applicable:

- Walking or riding within a region.
- Flying to a known hub.
- Flight paths or taxis.
- Portals and teleports.
- Portal-room movement.
- Boats, zeppelins, ferries, and similar transports.
- Dungeon or scenario landing transitions.
- External interactions that require a mage, NPC, group, or vehicle.

Acceptance criteria:

- Route steps expose their travel mode.
- Each mode has a documented timing and requirement model.
- The UI does not imply that an external interaction is a local click.

### [x] TA-403 — Apply requirements to every edge

Priority: RELEASE BLOCKER  
Depends on: TA-202, TA-401

Required change:

- Apply faction, class, race, specialization, profession, quest, reputation, expansion, location, discovery, and phase restrictions to explicit and implicit edges.
- Do not rely only on edge-level faction checks if node-level or flight access also matters.

Acceptance criteria:

- A restricted edge is absent or marked unavailable with a reason.
- Faction-specific hubs and flight paths behave consistently.

### [x] TA-404 — Separate region, entrance, instance, and landing map identities

Priority: RELEASE BLOCKER  
Depends on: TA-401

Observed issues:

- Several DungeonTeleports entries use mapID 2214 while describing separate dungeons.
- TravelData.lua:183 uses mapID 2200 for Earthen Depths, which conflicts with the surrounding data.

Required change:

- Add explicit instanceMapID, entranceMapID, landingMapID, and regionMapID fields where needed.
- Route to the map the player actually lands in, while retaining the instance identity for display and validation.

Acceptance criteria:

- Dungeon names and landing regions are not conflated.
- Every route step states whether it targets an instance, entrance, landing location, or region.

### [x] TA-405 — Replace optimistic flight assumptions with an explicit time model

Priority: HIGH  
Depends on: TA-004, TA-402

Observed issue:

- The current graph uses same-continent implicit flight, Euclidean coordinates, and TravelGraph.FLIGHT_SPEED = 6.
- It does not represent actual discovered flight paths, player position within a region, network paths, or flight-skill restrictions.

Required change:

- Decide whether estimates are heuristic or calibrated.
- Use known network paths and discovered access where available.
- Separate movement-to-hub time from transport time.
- Give uncertain estimates a confidence or approximation label.

Acceptance criteria:

- “Fastest” is not presented as exact when based on a heuristic.
- The selected route is reproducible from documented weights.

### [x] TA-406 — Handle current location, instances, phases, and unsupported maps

Priority: HIGH  
Depends on: TA-106, TA-401

Acceptance criteria:

- Current map, parent map, continent, and instance context are handled deliberately.
- Unsupported or phased locations produce a safe no-route or informational result.
- The route cache key is stable for all supported player states.

### [x] TA-407 — Implement explicit route policies

Priority: RELEASE BLOCKER  
Depends on: TA-004, TA-405

At minimum evaluate:

- Best ready now.
- Best after waiting for cooldown.
- Fewest travel transitions.
- Fewest user interactions.
- Closest useful landing region when exact travel is unavailable.

Required change:

- Include cooldown wait time in the policy that claims to optimize elapsed time.
- Do not collapse “Best Now” and “Best If Ready” into one ambiguous result.

Acceptance criteria:

- A slower-ready route beats a faster-cooldown route only under the selected policy.
- Route labels explain the policy used.
- Tests cover a cooldown route versus a ready alternative.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: TravelGraph consumes typed ZoneConnections and portal hubs, carries per-edge mode/access/timing/identity metadata, resolves parent/landing map contexts, and exposes Best Now, Best If Ready, Best After Wait, fewest-transition, fewest-interaction, and closest-useful policies. `node tools/phase0.test.js`, `node tools/phase1.test.js`, `node tools/phase2.test.js`, `node tools/phase3.test.js`, and `node tools/phase4.test.js` pass. The full validator still reports the pre-existing duplicate coordinate, duplicate source, and unresolved dynamic-source findings.
    In-game evidence: Pending; exact flight-path discovery, transport schedules, dungeon instance/entrance IDs, phase state, and live secure-action behavior remain in the verification matrix.
    Notes: Flight and movement estimates are explicit approximations with confidence metadata. Conditional flightpath/taxi edges and target-directed post-travel flight fallbacks are excluded from `Best Now` until discovery/access is known. The fallback is only generated after leaving the current routing node, so the graph does not become an unqualified all-pairs same-continent graph. Unverified dungeon instance and entrance IDs use `0` metadata and never become route destinations; routes target the explicit landing/region map instead.

## Phase 5 — Data integrity, coverage, and maintenance

### [x] TA-501 — Build a travel-data validator

Priority: RELEASE BLOCKER  
Depends on: TA-002

Validate:

- Duplicate map keys and duplicate coordinate keys.
- Missing node names, map IDs, source IDs, icons, or destination resolvers.
- Edges whose endpoints do not exist.
- Sources that refer to undefined requirements or destination records.
- Conflicting instance, entrance, landing, and region identities.
- Static portal or transport entries missing access metadata.

Acceptance criteria:

- The validator reports the current known conflicts and fails in CI or the documented validation command.
- New malformed data cannot be merged without an explicit override or correction.

### [x] TA-502 — Correct duplicate ZoneCoordinates definitions

Priority: RELEASE BLOCKER  
Depends on: TA-501

Observed issues:

- TravelData.lua defines coordinate key 47 more than once; the later definition silently overwrites the earlier one.
- TravelData.lua defines coordinate key 2371 more than once; the later definition silently overwrites the earlier one.

Required change:

- Resolve the intended map IDs and coordinates.
- Add validation preventing duplicate keys from returning.

### [x] TA-503 — Resolve known contradictory data

Priority: RELEASE BLOCKER  
Depends on: TA-501

Review and correct at least:

- Boots of the Bay destination and the region associated with map ID 47.
- The comments and coordinates for map ID 2371.
- Floodgate, Stonevault, and Darkflame Cleft destination identities.
- Earthen Depths map and landing data.

Acceptance criteria:

- Each corrected record has an authoritative source or in-game verification note.
- Route tests use the corrected identity.

### [x] TA-504 — Audit static portals, hubs, and transport assumptions

Priority: HIGH  
Depends on: TA-403, TA-501

For each static edge, document:

- Where the player must be.
- What unlock or requirement applies.
- Whether the edge is always present, phase-specific, seasonal, or patch-specific.
- Whether it is executable by the addon or only informational.

Acceptance criteria:

- No static edge is treated as universally available without evidence.
- Faction and unlock restrictions are represented in data rather than hidden in UI code.

### [x] TA-505 — Add source provenance and patch maintenance

Priority: HIGH  
Depends on: TA-501

Required change:

- Record the source of important map, spell, item, toy, portal, and transport metadata.
- Record the client build or patch in which the entry was verified.
- Add a documented process for updating travel data after patches.

Acceptance criteria:

- A maintainer can identify why an entry exists and when it was last checked.
- Patch changes do not require hunting through unrelated route code.

### [x] TA-506 — Add user-defined source support if selected

Priority: ARCHITECTURE  
Depends on: TA-004, TA-201

If user-defined sources are in scope:

- Define a saved-data schema.
- Validate user entries before adding them to the graph.
- Mark user-provided destinations and restrictions with lower or explicit confidence.
- Provide an import/export or reset path.

If not in scope, document the decision and the supported extension point.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: `node tools/phase5.test.js`, `node tools/validate.js`, and the full `node tools/check.js` command pass. The validator now parses multiline source records and checks duplicate map/source IDs, node names and IDs, icon and destination resolvers, destination-option and requirement references, graph endpoints, dungeon identity metadata, static-edge access policy, source provenance, client/build metadata, maintenance metadata, and user-source scope.
    Data corrections: map 47 is retained as Duskwood, Boots of the Bay targets map 210, map 2371 is retained only for K'aresh, the Horde Vale portal uses spellID 132627, and Floodgate, Stonevault, Darkflame Cleft, Earthen Depths, Gate of the Setting Sun, and Vortex Pinnacle no longer conflate instance IDs with landing regions.
    In-game evidence: Pending; the data records identify the live-client APIs and inspection procedures required for final verification. Unverified access, transport schedules, and dungeon instance/entrance IDs remain informational or non-routable.
    Maintenance: `TravelData.Metadata` records the 12.1.0/120100 target and post-patch process; `SourceMetadata` records the source API and provenance seam for every supported source family; `UserSourcePolicy` documents user-defined sources as out of scope with `TravelData.UserSources` reserved as the validated extension point.

## Phase 6 — UI, explanations, and settings

### [x] TA-601 — Separate Best Now from Best If Ready

Priority: RELEASE BLOCKER  
Depends on: TA-407

Acceptance criteria:

- Best Now contains only executable, ready routes.
- Best If Ready can show cooldown routes without presenting them as ready.
- The UI displays waiting time when it affects the selected policy.

### [x] TA-602 — Explain why sources and routes are unavailable

Priority: HIGH  
Depends on: TA-206

Display, where relevant:

- Source type and name.
- Destination or destination uncertainty.
- Cooldown remaining and charge count.
- Missing profession, faction, quest, reputation, location, or unlock requirement.
- Required external interaction.
- Why a route was selected over another route.

Acceptance criteria:

- Explanations are generated from canonical state and reason fields.
- No tooltip contradicts the actual actionability of the route.

### [x] TA-603 — Use localized names and stable IDs

Priority: HIGH  
Depends on: TA-104, TA-201

Acceptance criteria:

- Spell, item, and toy names are resolved from IDs.
- No route action depends on an English display string.
- Icons and labels match the selected source after overrides.

### [x] TA-604 — Refresh the display safely and efficiently

Priority: HIGH  
Depends on: TA-107, TA-105

Acceptance criteria:

- State changes refresh or invalidate the display through one coalesced path.
- Secure controls are only changed outside combat lockdown.
- The display remains understandable while a protected-button rebuild is pending.

### [x] TA-605 — Implement or remove SavedVariablesPerCharacter

Priority: MEDIUM  
Depends on: TA-004, TA-506

Observed issue:

- TravelAdvisor.toc:7 declares SavedVariablesPerCharacter: TravelAdvisor_Settings, but the code does not currently use it.

Implemented choice:

- Persist the selected route policy and UI settings in the versioned
  per-character schema.
- User-defined sources remain out of scope under D-006 and are not loaded or
  persisted until the validated `TravelData.UserSources` extension point is
  implemented.

Acceptance criteria:

- The TOC and runtime behavior agree.
- Saved data is versioned and migrated if it is implemented.

Completion evidence:

    Date: 2026-09-20
    Commit or PR: Working tree; no commit created.
    Automated/static validation: `node tools/check.js` passes, including the Phase 6 contract test and the strict data validator.
    Runtime/UI changes: Best Now is restricted to ready/executable paths; Best If Ready and Best After Wait are explicitly informational; canonical source, destination, cooldown, charge, interaction, requirement, and policy explanations are rendered from evaluator/graph state; localized action names/icons resolve from effective IDs; refreshes are coalesced and secure controls rebuild only out of combat.
    Persistence: `TravelAdvisorSettings.lua` implements version 1 defaults and migration for `TravelAdvisor_Settings`, including the selected route policy and explanation visibility setting; user-defined sources remain explicitly out of scope under D-006.

## Phase 7 — Tests, in-game verification, and release gate

### [ ] TA-701 — Add source-evaluator tests

Priority: RELEASE BLOCKER  
Depends on: TA-002, TA-202

Cover:

- Known, unknown, owned, unowned, collected, and missing sources.
- Ready, cooldown, disabled, unusable, zero-charge, and resource-limited states.
- Spell overrides and charges.
- Item and toy cooldowns.
- Profession, faction, quest, reputation, specialization, and location restrictions.
- Unknown destinations.

### [ ] TA-702 — Add graph and route-policy tests

Priority: RELEASE BLOCKER  
Depends on: TA-002, TA-401, TA-407

Cover:

- Missing bind node creation.
- Bind hub mapID fallback.
- Multi-hop routes through intermediate hubs.
- Faction-restricted edges.
- Instance versus landing versus region identities.
- Best Now versus Best If Ready.
- Cooldown wait time.
- No route through mapID 0 or unknown destinations.

### [ ] TA-703 — Add action and combat-safety tests

Priority: RELEASE BLOCKER  
Depends on: TA-103, TA-104, TA-105

Cover:

- Correct spell, item, toy, and hearthstone action metadata.
- No action button for cooldown or unusable routes.
- Revalidation of stale route actions.
- Combat lockdown and deferred rebuild behavior.

### [ ] TA-704 — Complete the in-game verification matrix

Priority: RELEASE BLOCKER  
Depends on: TA-003, TA-301, TA-302, TA-303, TA-304, TA-305, TA-306, TA-401, TA-402

Record evidence for:

- Spell and toy APIs.
- Cooldown and charge behavior, including modRate if relevant.
- Bag and toy events.
- Dynamic destinations.
- Profession sources.
- Faction and unlock restrictions.
- Portal, flight, transport, and dungeon landing relationships.
- Secure actions in and out of combat.

### [ ] TA-705 — Perform a regression pass after every data or API update

Priority: HIGH  
Depends on: TA-701, TA-702, TA-703, TA-704

Acceptance criteria:

- The validation command passes.
- The relevant in-game matrix rows are rerun.
- Any changed behavior is recorded here before release.

### [ ] TA-706 — Apply the release gate

Priority: RELEASE BLOCKER  
Depends on: All release-blocker items

Release is allowed only when:

- No critical or high-risk correctness item is unchecked without an explicit documented exception.
- No IN-GAME item is marked complete without evidence.
- Static/data validation passes.
- Source, graph, action, UI, and regression tests pass.
- The supported client/build is documented.
- Known limitations and unsupported travel sources are documented.

## Phase 8 — Cleanup and long-term maintenance

### [ ] TA-801 — Remove obsolete code paths

Priority: MEDIUM  
Depends on: TA-203, TA-705

Remove or isolate:

- The legacy scanner after canonical parity is proven.
- Duplicate cooldown and usability helpers.
- Hardcoded display-name action paths.
- Dead data tables such as unconsumed destination definitions, unless they are intentionally reserved and documented.

### [ ] TA-802 — Document contributor workflow

Priority: MEDIUM  
Depends on: TA-002, TA-505

Document:

- How to add a new spell, item, toy, portal, transport, or destination.
- Required metadata and restrictions.
- Required automated tests and in-game checks.
- How to update patch-specific data.
- How to update this master plan and record completion evidence.

### [ ] TA-803 — Measure and calibrate route estimates

Priority: LOW  
Depends on: TA-405, TA-704

Optional future work:

- Compare estimated and observed travel times.
- Add confidence scores.
- Calibrate weights by travel mode and region.
- Keep user-facing claims proportional to measurement quality.

## Decision log

Record the decision, date, alternatives considered, and affected task IDs here.

### D-001 — Supported client and API version

Decision: Retail/mainline World of Warcraft 12.1.x, beginning with the standard 12.1.0 interface `120100`. Classic branches are out of scope.

Date: 2026-09-19

Affected tasks: TA-001, TA-002, TA-003, TA-201, TA-301, TA-302, TA-401, TA-704

### D-002 — Meaning of fastest

Decision: Keep separate route policies. `Best Now` minimizes estimated travel time among ready/actionable routes. `Best After Wait` minimizes cooldown wait plus estimated travel time. `Best If Ready` is a comparison/information policy and is not an executable route.

Date: 2026-09-19

Affected tasks: TA-004, TA-103, TA-407, TA-601, TA-702

### D-003 — Cooldown route behavior

Decision: A cooldown route may remain visible with its wait time and reason, but it must not receive a Use action or be described as ready. Readiness must be revalidated immediately before activation where the API permits.

Date: 2026-09-19

Affected tasks: TA-103, TA-107, TA-202, TA-601, TA-602

### D-004 — Mage portal and external-player interactions

Decision: A mage portal is an external interaction unless the player can execute the relevant action locally. It may be shown as an informational route step with the required interaction stated, but it is not a local executable action.

Date: 2026-09-19

Affected tasks: TA-304, TA-402, TA-602

### D-005 — Random, choice, return, and nearby destinations

Decision: Fixed destinations may participate in deterministic routing. Return, random, and player-choice sources require an explicit resolver; otherwise they remain informational and non-actionable. A nearby-region fallback must be labeled as such and never presented as an exact destination match.

Date: 2026-09-19

Affected tasks: TA-204, TA-305, TA-306, TA-407, TA-601

### D-006 — User-defined travel sources

Decision: User-defined sources are out of scope for the initial 12.1 implementation. The canonical source schema remains the future extension point; no unvalidated user source is added to the graph.

Date: 2026-09-19

Affected tasks: TA-004, TA-201, TA-506

## Completion log

Use this section for a short chronological record after individual items are completed. The detailed evidence remains beside each item.

| Date | Item | Summary | Validation |
| --- | --- | --- | --- |
| 2026-09-19 | TA-000, TA-001, TA-002 | Recorded the static baseline, selected Retail WoW 12.1.x/interface 120100, and added the dependency-free validation harness and Phase 0 contract fixtures. | `node tools/phase0.test.js` passes; `node tools/validate.js` reports the known baseline defects. |
| 2026-09-20 | TA-101–TA-107 | Implemented Phase 1 bind-node and hub-ID fixes, explicit availability/actionability state, stable spell/item/toy secure-action metadata, out-of-combat pre-click revalidation, combat-deferred UI refreshes, unknown-map handling, and coalesced state invalidation. | `node tools/phase0.test.js` and `node tools/phase1.test.js` pass; WoW MCP Lua lint reports 0 errors; live-client verification and the known 39 data-validator defects remain pending. |
| 2026-09-20 | TA-201–TA-206 | Added the canonical source catalog/evaluator, destination resolution, static/dynamic graph split, canonical scanner adapter, stable exclusion reasons, cooldown-aware informational routes, source diagnostics, and Phase 2 fixtures. | `node tools/phase0.test.js`, `node tools/phase1.test.js`, and `node tools/phase2.test.js` pass; WoW MCP lint reports 0 errors; full data validation still reports the known baseline defects and in-game verification remains pending. |
| 2026-09-20 | TA-301–TA-307 | Added canonical spell/item/toy/profession discovery coverage, profession skill checks, explicit mage-portal and player-choice semantics, dynamic mapID 0 handling, and source-family coverage metadata. | `node tools/phase0.test.js`, `node tools/phase1.test.js`, `node tools/phase2.test.js`, and `node tools/phase3.test.js` pass; live-client verification and the known baseline data-validator defects remain pending. |
| 2026-09-20 | TA-501–TA-506 | Added strict multiline-aware data validation, corrected duplicate and contradictory map/source records, documented conservative static-edge access, added source/build provenance and the post-patch maintenance workflow, and reserved user-defined sources as an explicitly validated future extension point. | `node tools/check.js`, `node tools/phase5.test.js`, and `node tools/validate.js` pass; WoW Lua lint reports 0 errors for Phase 5 data/source files; live-client verification remains pending. |
| 2026-09-20 | TA-601–TA-605 | Separated ready and waiting route policies, added canonical route/source explanations and localized ID-backed presentation, centralized combat-safe display refreshes, and implemented versioned per-character settings. | `node tools/check.js`, `node tools/phase6.test.js`, and `node tools/validate.js` pass; live-client UI/API verification remains pending. |

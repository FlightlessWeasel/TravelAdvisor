# TravelAdvisor validation and WoW 12.1 target

## Supported client target

TravelAdvisor targets the Retail/mainline World of Warcraft 12.1 patch line. The addon TOC uses interface `120100`, the interface number for the standard 12.1 client. The target patch is the 12.1.0 `Curse of Ula'tek` content update; patch-specific travel data must be rechecked when a later 12.1.x build changes maps, spells, toys, transports, or API behavior.

References:

- [Curse of Ula'tek Content Update Notes](https://worldofwarcraft.blizzard.com/en-us/news/24293281/curse-of-ulatek-content-update-notes)
- [Patch 12.1.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes)
- [TOC interface format and interface numbers](https://warcraft.wiki.gg/wiki/TOC_format)

The current repository has no embedded WoW Lua runtime. Static checks establish data and source-shape invariants only; the in-game verification matrix below remains required for API and secure-action claims.

The WoW MCP server is the API source of truth for this project. API lookups and lint below target Retail/mainline (Midnight/12.1), rather than relying on generic web documentation or memory.

## API assumptions to verify in WoW 12.1

| Area | Assumption used by the current addon | Static status |
| --- | --- | --- |
| Current map | `C_Map.GetBestMapForUnit("player")` can return `nil` or an unsupported map and must be handled as unknown. | Not verified in-game |
| Spell knowledge | `C_SpellBook.IsSpellKnown`, `IsPlayerSpell`, and `C_Spell.GetSpellCooldown` are the authoritative 12.1 checks; spellbook presence alone can include temporary overrides. | Not verified in-game |
| Spell icons | `C_Spell.GetSpellTexture` is preferred; localized names are display-only. | Not verified in-game |
| Item state | `C_Item.GetItemCount`, `C_Item.GetItemCooldown`, and `C_Item.GetItemInfoInstant` provide the item state needed by discovery. | Not verified in-game |
| Toys | `PlayerHasToy` identifies collected toys; toy actions are distinct from ordinary item actions. | Not verified in-game |
| Bind location | `GetBindLocation()` returns a localized zone name that requires a safe resolver and may remain unknown. | Not verified in-game |
| Requirements | `C_QuestLog.IsQuestFlaggedCompleted` and profession/faction APIs can be unavailable or context-sensitive and must produce an explicit unavailable reason. | Not verified in-game |
| Secure actions | Protected action buttons and their attributes must only be created or reconfigured outside combat lockdown. | Not verified in-game |

No assumption in this table is evidence that the current implementation is already correct. These are the API seams that the Phase 1 and Phase 2 changes must isolate and verify.

## WoW MCP verification snapshot

The WoW MCP API catalog confirms the following 12.1/mainline details:

- `C_Spell.GetSpellCooldown` returns a `SpellCooldownInfo` table and may return `nil`; it is not the old positional-return API.
- `C_SpellBook.IsSpellInSpellBook` can return true for override spells that are not actually known. Discovery must distinguish known spells from override presence.
- `C_Spell.GetOverrideSpell` is the override resolver used by the Phase 1 availability evaluator; the legacy scanner's `C_SpellBook.FindSpellOverrideByID` call remains a later cleanup item.
- `C_Item.GetItemCooldown`, `C_Item.GetItemCount`, and `C_Item.GetItemInfoInstant` are namespaced APIs with `ItemInfo` arguments.
- `C_Map.GetBestMapForUnit` returns a nullable map ID, and `C_Map.OpenWorldMap` is the namespaced map-opening API.
- Combat lockdown is exposed as `C_RestrictedActions.InCombatLockdown()`.
- `PlayerHasToy` exists as an undocumented legacy global; it is a compatibility seam, not a strongly documented API contract.

The latest WoW MCP Lua lint reports no errors. `TravelGraph.lua` reports 0
warnings, `TravelSources.lua` and `TravelAdvisorSettings.lua` report no
issues, and the remaining `TravelAdvisor.lua` warnings/notes are the known
legacy moved-global and protected-frame mutation findings. The protected
mutations are deferred or guarded at runtime; they are not evidence that the
addon is currently ready to ship.

## Validation commands

From the repository root:

```text
node tools/check.js
```

`check.js` is the single command for all available static checks. It runs the dependency-free Phase 0 through Phase 5 contract tests and the strict data validator. The command must exit zero before a Phase 5 data change is considered complete.

`phase0.test.js` is a dependency-free contract test for the source/destination and route-policy fixtures. It does not emulate the WoW client. Run it directly when only the contract tests are needed.

`phase2.test.js` checks canonical source load order and module surface, verifies that the active graph/UI paths do not retain the duplicate scanner, and exercises fixture states for bag-only ownership, collection, cooldown/recharge route eligibility, charges, unknown requirements/usability, dynamic destinations, diagnostics, and route eligibility.

`validate.js` is intentionally strict and exits non-zero for malformed or under-documented data. Use `node tools/validate.js --json` when another tool needs structured findings.

## Phase 1 implementation checks

The Phase 1 contract test covers the bind-node fallback, bind-hub map IDs, route actionability, stable secure-action IDs, invalid-map handling, combat-deferred UI work, coalesced invalidation, and the cooldown refresh path.

```text
node tools/phase0.test.js
node tools/phase1.test.js
node tools/phase2.test.js
node tools/phase3.test.js
```

All six contract test files pass in the current workspace. The full `node tools/check.js` command passes, including the Phase 5 validator. No local WoW Lua runtime or live-client secure-action test is available in this workspace.

## Phase 2 implementation checks

The Phase 2 implementation adds `TravelSources.lua` between `TravelData.lua` and `TravelGraph.lua` in the TOC. It normalizes the curated source families into stable records, creates a player-state snapshot, resolves dynamic destinations, evaluates action and requirement state, and returns stable reason codes. `TravelGraph.lua` stores static topology separately from dynamic nodes and retains excluded source evaluations for diagnostics. `TravelAdvisor.lua` adapts those evaluations for its legacy display shape without running a second WoW API scanner.

Static checks completed:

- `node tools/phase2.test.js` passes.
- `wow_lua_lint` reports 0 errors and no issues for `TravelSources.lua`.
- `wow_lua_lint` reports 0 errors for `TravelGraph.lua` and `TravelAdvisor.lua`; existing warnings/notes remain documented above.
- `wow_toc_validate` reports 0 errors; its four path-separator warnings predate Phase 2.

Live-client verification remains pending for exact spell overrides, charge/modRate behavior, localized bind names, profession/reputation APIs, dynamic source selection, and secure action activation.

## Phase 3 implementation checks

Phase 3 extends the canonical discovery model without reintroducing the retired
spell/item scanner. `TravelSources.lua` now records source family, interaction
semantics, optional profession skill requirements, dynamic destination options,
and explicit coverage status. Mage portals are informational external-player
interactions, Mole Machine destinations remain player-choice data until a
selection is available, and setup-only sources such as Make Camp never create
route edges.

Static checks:

- `node tools/phase3.test.js` passes.
- `node tools/phase0.test.js`, `node tools/phase1.test.js`, and `node tools/phase2.test.js` remain passing.
- `node tools/check.js` includes the Phase 3 contract test before running the strict validator.

The Phase 3 contract fixtures cover known versus unknown and unusable spells,
item versus toy ownership/action metadata, profession and skill requirements,
external portal semantics, Mole Machine choices, bind resolution, setup-only
and unresolved mapID 0 sources, and documented informational-only transport
coverage. Live-client verification remains required for localized spell and
profession APIs, exact toy usability, dynamic selections, and secure actions.

The validator currently checks:

- the TOC interface target;
- duplicate numeric keys in `ZoneCoordinates`;
- dungeon identity schema and explicit landing-region routing fields;
- positive stable source IDs;
- duplicate stable source IDs that are not modeled as explicit variants;
- unresolved or missing source destinations;
- source destinations without a graph node definition;
- missing endpoints in `ZoneConnections`.
- the explicit dungeon instance/entrance/landing/region identity schema.
- source names, stable IDs, icon resolvers, destination resolvers, and destination-option records;
- undefined requirement fields and destination resolver/table references;
- portal-hub node names and map IDs;
- static-edge access, availability, interaction, actionability, and provenance policy;
- client/build metadata, per-family provenance, maintenance metadata, and user-source scope.

## Phase 4 implementation checks

Phase 4 makes graph topology explicit. `TravelGraph.lua` consumes typed
`TravelData.ZoneConnections` and portal-hub transitions, keeps the player's
current node on explicit topology, and adds a target-directed approximate
flight fallback only after a route has reached an intermediate node. This lets
teleports, portals, and class travel compose with a final movement leg without
inventing an all-pairs same-continent graph. The fallback is conditional and
informational until flight access is discovered. Every route step carries mode,
timing, confidence, requirements, interaction, and region/landing/instance
identity metadata. Static edges use the canonical requirement evaluator where
available; node access and unsupported parent/instance map contexts are checked
separately.

The route policies are explicit and named: `Best Now`, `Best If Ready`, `Best
After Wait`, fewest transitions, fewest interactions, and closest useful
landing. `Best After Wait` includes cooldown wait in elapsed time. `Best If
Ready` remains informational and is never executable through the UI action
button.

Static checks:

- `node tools/phase4.test.js` covers explicit multi-hop topology, no invented
  same-continent edges from the current node, post-travel final-flight
  composition, mode/access metadata, cooldown policy ranking, dungeon identity
  fields, unsupported maps, and cache dimensions.
- `node tools/phase0.test.js`, `node tools/phase1.test.js`,
  `node tools/phase2.test.js`, and `node tools/phase3.test.js` remain passing.
- `node tools/check.js` includes the Phase 4 contract test before running the
  strict validator.

The strict validator now passes the corrected Phase 5 catalog. Exact flight
networks, discovered access, transport schedules, and unverified dungeon
instance/entrance IDs remain pending live or authoritative data verification.
Static flightpath/taxi, portal, and transport edges therefore carry
conditional access and remain non-actionable until discovery/access is known.

## Phase 5 implementation checks

Phase 5 makes travel data auditable and patch-maintainable. `TravelData.lua`
now declares client/build metadata, per-source-family provenance, explicit
destination and requirement catalogs, a conservative static-edge access policy,
and an out-of-scope user-source extension point. Dynamic or unverified
destinations are marked with a resolver or an explicit non-routable state.

The Phase 5 contract test verifies multiline source parsing, duplicate-key and
stable-ID correction, dungeon landing/region identity, source metadata,
static-edge access defaults, transport limitations, and the documented
maintenance process. Run it directly with:

```text
node tools/phase5.test.js
```

Post-patch maintenance process:

1. Recheck affected map, spell, item, toy, portal, and transport records in the
   live client.
2. Update `TravelData.Metadata.client`, the affected `SourceMetadata` entry,
   and any record-level verification note.
3. Rerun `node tools/check.js` and record the client build, character context,
   date, observed behavior, and evidence location in this file.
4. Keep uncertain access informational until discovery, faction, unlock, and
   schedule behavior is verified.

## Phase 6 implementation checks

Phase 6 separates executable and informational route policies at the display
boundary. `Best Now` rejects paths that are not ready, executable, resolved,
and free of required waiting. `Best If Ready` and `Best After Wait` retain
cooldown routes as explicitly informational and expose wait time, charges, and
canonical reason fields.

`TravelSources.lua` now exposes localized action presentation and structured
source explanations. `TravelGraph.lua` carries route rationale, source
evaluations, destination uncertainty, cooldown, charge, interaction, and
requirement metadata into the UI. Secure actions continue to use stable action
IDs rather than display names.

`TravelAdvisor.lua` uses one coalesced refresh path. State changes invalidate
the route cache and defer display/protected-button rebuilds during combat; the
right panel shows a pending-refresh status until `PLAYER_REGEN_ENABLED`.

`TravelAdvisorSettings.lua` owns the versioned per-character settings schema.
The persisted route policy and explanation visibility controls are migrated
from the prior unversioned shape and are declared by the TOC.

Static validation:

- `node tools/phase6.test.js` passes.
- `node tools/check.js` passes, including Phase 0 through Phase 6 contract
  tests and the strict travel-data validator.
- Live-client verification of localized API responses, secure controls, combat
  lockdown, and saved-variable serialization remains required.

## Phase 0 verification matrix

The matrix is a release checklist, not a substitute for automated tests. Each executed row must record the character class/race/faction, client build, date, expected behavior, observed behavior, and evidence location.

| Area | Required cases | Status |
| --- | --- | --- |
| Client/API | Retail 12.1.x live client; current map; spell cooldown; item cooldown; toy collection; bind lookup | Pending in-game verification |
| Source state | Ready; on cooldown; disabled; unusable; zero charge; missing source; unknown destination | Pending in-game verification |
| Player state | Bag update; toy collection; spellbook change; specialization/talent change; quest/unlock change; faction change; zone change; bind change | Pending in-game verification |
| Destinations | Fixed; hearth bind; return; player choice; random; nearby useful region; portal hub; unknown | Pending in-game verification |
| Travel modes | Spell; item; toy; hearthstone toy; portal; flight path; boat/zeppelin/ferry; dungeon landing; external interaction | Pending in-game verification |
| Safety | Combat lockdown while display is open, refreshed, rebuilt, and while an action is attempted | Pending in-game verification |
| Routing | Best Now; Best If Ready; Best After Wait; cooldown wait included; no mapID 0 route | Pending in-game verification |

## Baseline evidence

The initial review was static. No Lua runtime or automated test suite existed before Phase 0. The known high-risk findings are tracked in `MASTER_PLAN.md`, including the malformed bind fallback call, the bind-hub array-key fallback, duplicate coordinate keys, unresolved mapID 0 sources, optimistic cooldown action handling, incomplete cache invalidation, and unconsumed intermediate topology.

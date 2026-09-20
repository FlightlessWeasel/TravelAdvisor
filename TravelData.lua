-- ═══════════════════════════════════════════════════════════════════════════
-- TravelAdvisor - Travel Spell/Item Database
-- ═══════════════════════════════════════════════════════════════════════════
-- This file contains all known travel abilities grouped by destination

local _, TA = ...
TA.TravelData = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- ZONE/CONTINENT IDs (Map IDs from C_Map)
-- ═══════════════════════════════════════════════════════════════════════════
TA.Zones = {
    -- Major Cities
    STORMWIND = 84,
    ORGRIMMAR = 85,
    IRONFORGE = 87,
    THUNDERBLUFF = 88,
    DARNASSUS = 89,
    UNDERCITY = 90,
    EXODAR = 103,
    SILVERMOON = 110,
    SHATTRATH = 111,
    DALARAN_NORTHREND = 125,
    DALARAN_BROKEN_ISLES = 627,
    BORALUS = 1161,
    DAZARALOR = 1165,
    ORIBOS = 1670,
    VALDRAKKEN = 2112,
    DORNOGAL = 2339,

    -- Continents
    EASTERN_KINGDOMS = 13,
    KALIMDOR = 12,
    OUTLAND = 101,
    NORTHREND = 113,
    PANDARIA = 424,
    DRAENOR = 572,
    BROKEN_ISLES = 619,
    ZANDALAR = 875,
    KUL_TIRAS = 876,
    SHADOWLANDS = 1550,
    DRAGON_ISLES = 1978,
    KHAZ_ALGAR = 2274,

    -- Special Locations
    EMERALD_DREAM = 2200,
    PEAK_OF_SERENITY = 569,
    ACHERUS = 118,
    DREADSCAR_RIFT = 717,
    ORDER_HALLS = 0, -- Generic for class halls
    GARRISON = 0, -- Player's garrison
}

-- ═══════════════════════════════════════════════════════════════════════════
-- TRAVEL TYPES
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelType = {
    TELEPORT = "teleport",     -- Instant teleport (mage teleport, hearthstone)
    PORTAL = "portal",         -- Creates portal for group
    FLIGHTPATH = "flightpath", -- Flight master
    ITEM = "item",             -- Usable item
    TOY = "toy",               -- Toy item
    SPELL = "spell",           -- Spell ability
}

-- Travel modes describe the transition itself rather than the source item or
-- spell that may make the transition possible.  Static topology records use
-- these values so the graph never has to infer a mode from a shared
-- continent or a localized name.
TA.TravelData.TravelModes = {
    WALK = "walking",
    RIDE = "riding",
    FLIGHT = "flight",
    FLIGHTPATH = "flightpath",
    TAXI = "taxi",
    PORTAL = "portal",
    PORTAL_ROOM = "portal-room",
    BOAT = "boat",
    ZEPPELIN = "zeppelin",
    FERRY = "ferry",
    DUNGEON_LANDING = "dungeon-landing",
    EXTERNAL = "external-interaction",
}

-- Source semantics are kept in data so a new category cannot silently
-- inherit an executable action model that does not match the in-game action.
TA.TravelData.SourceSemantics = {
    MagePortals = {
        sourceFamily = "mage-portal",
        interaction = "external-player",
        actionableByPlayer = false,
        discovery = "known-spell-api",
        note = "Requires a mage/player interaction; never a local Use action.",
    },
}

-- Data governance is kept beside the catalog so a patch update has one
-- documented place to record what was checked and which API owns each field.
-- `pending-live` is intentional: static validation cannot prove a live-client
-- spell, map, portal, or transport assumption.
TA.TravelData.Metadata = {
    schemaVersion = 1,
    client = {
        flavor = "mainline",
        interface = 120100,
        patch = "12.1.0",
        build = "120100",
        lastChecked = "2026-09-20",
        verification = "pending-live",
    },
    maintenance = {
        owner = "TravelAdvisor maintainers",
        process = "After every client patch, compare changed map, spell, item, toy, portal, and transport records against the live client; update provenance and rerun node tools/check.js before release.",
        liveEvidence = "Record character faction/class/race, client build, date, observed behavior, and an evidence location in VALIDATION.md.",
    },
}

-- These names are metadata contracts used by the validator. Runtime resolvers
-- remain in TravelSources.lua, where they can consume player state safely.
TA.TravelData.DestinationResolvers = {
    ["bind-location"] = { kind = "bind", stateField = "bindMapID" },
    ["previous-location"] = { kind = "previous", stateField = "previousMapID" },
    ["camp-location"] = { kind = "choice", stateField = "campMapID" },
    ["nearest-flight-master"] = { kind = "nearby", stateField = "nearestFlightMapID" },
    ["player-choice"] = { kind = "choice", stateField = "choiceMapID" },
    ["random-location"] = { kind = "random" },
    ["unverified-landing"] = { kind = "unknown", routeEligible = false },
}

TA.TravelData.RequirementCatalog = {
    fields = {
        "class", "race", "faction", "profession", "specialization", "quest",
        "reputation", "expansion", "location", "unlock", "discovery", "phase",
        "access", "professionSkill", "requires",
    },
    references = {
        quest = "ZoneUnlockQuests",
        destinationOptions = "named-data-table",
        resolver = "DestinationResolvers",
    },
}

-- Category-level provenance also supplies the canonical icon and destination
-- resolution seams for records whose values are supplied by WoW APIs at load
-- or evaluation time.
TA.TravelData.SourceMetadata = {
    MageTeleports = {
        stableIDField = "spellID", iconResolver = "C_Spell.GetSpellTexture",
        destinationResolver = "mapID-or-DestinationResolvers", source = "in-game:C_SpellBook/C_Map.GetMapInfo",
        verifiedBuild = "120100", patch = "12.1.0", lastChecked = "2026-09-20",
        verification = "pending-live", evidence = "VALIDATION.md#phase-5-implementation-checks",
    },
    MagePortals = {
        stableIDField = "spellID", iconResolver = "C_Spell.GetSpellTexture",
        destinationResolver = "mapID-or-DestinationResolvers", source = "in-game:C_SpellBook/portal-room inspection",
        verifiedBuild = "120100", patch = "12.1.0", lastChecked = "2026-09-20",
        verification = "pending-live", evidence = "VALIDATION.md#phase-5-implementation-checks",
    },
    ClassTeleports = {
        stableIDField = "spellID", iconResolver = "C_Spell.GetSpellTexture",
        destinationResolver = "mapID-or-DestinationResolvers", source = "in-game:C_SpellBook/C_Map.GetMapInfo",
        verifiedBuild = "120100", patch = "12.1.0", lastChecked = "2026-09-20",
        verification = "pending-live", evidence = "VALIDATION.md#phase-5-implementation-checks",
    },
    DungeonTeleports = {
        stableIDField = "spellID", iconResolver = "C_Spell.GetSpellTexture",
        destinationResolver = "landingMapID-or-DestinationResolvers", source = "in-game:C_SpellBook/dungeon landing inspection",
        verifiedBuild = "120100", patch = "12.1.0", lastChecked = "2026-09-20",
        verification = "pending-live", evidence = "VALIDATION.md#phase-5-implementation-checks",
    },
    Hearthstones = {
        stableIDField = "itemID", iconResolver = "C_Item.GetItemInfoInstant",
        destinationResolver = "bind-location", source = "in-game:C_Item.GetItemInfoInstant/bind inspection",
        verifiedBuild = "120100", patch = "12.1.0", lastChecked = "2026-09-20",
        verification = "pending-live", evidence = "VALIDATION.md#phase-5-implementation-checks",
    },
    TeleportItems = {
        stableIDField = "itemID", iconResolver = "C_Item.GetItemInfoInstant",
        destinationResolver = "mapID-or-DestinationResolvers", source = "in-game:C_Item.GetItemInfoInstant",
        verifiedBuild = "120100", patch = "12.1.0", lastChecked = "2026-09-20",
        verification = "pending-live", evidence = "VALIDATION.md#phase-5-implementation-checks",
    },
    TeleportToys = {
        stableIDField = "itemID", iconResolver = "C_Item.GetItemInfoInstant",
        destinationResolver = "mapID-or-DestinationResolvers", source = "in-game:PlayerHasToy/C_Item.GetItemInfoInstant",
        verifiedBuild = "120100", patch = "12.1.0", lastChecked = "2026-09-20",
        verification = "pending-live", evidence = "VALIDATION.md#phase-5-implementation-checks",
    },
    RacialTeleports = {
        stableIDField = "spellID", iconResolver = "C_Spell.GetSpellTexture",
        destinationResolver = "mapID-or-DestinationResolvers", source = "in-game:C_SpellBook/C_Map.GetMapInfo",
        verifiedBuild = "120100", patch = "12.1.0", lastChecked = "2026-09-20",
        verification = "pending-live", evidence = "VALIDATION.md#phase-5-implementation-checks",
    },
}

-- User-defined sources are intentionally deferred.  This is the extension
-- point future persistence/import work must validate before adding records to
-- the canonical source catalog.
TA.TravelData.UserSourcePolicy = {
    status = "out-of-scope",
    schemaVersion = 1,
    extensionPoint = "TravelData.UserSources",
    requiredFields = { "key", "name", "kind", "destination", "provenance" },
    validation = "Validate IDs, destination/resolver metadata, requirements, and explicit confidence before merging user records into the graph.",
    importExport = "not-implemented",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- MAGE TELEPORT SPELLS
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.MageTeleports = {
    -- Alliance
    { spellID = 3561, name = "Teleport: Stormwind", destination = "Stormwind", faction = "Alliance", mapID = 84 },
    { spellID = 3562, name = "Teleport: Ironforge", destination = "Ironforge", faction = "Alliance", mapID = 87 },
    { spellID = 3565, name = "Teleport: Darnassus", destination = "Darnassus", faction = "Alliance", mapID = 89 },
    { spellID = 32271, name = "Teleport: Exodar", destination = "Exodar", faction = "Alliance", mapID = 103 },
    { spellID = 33690, name = "Teleport: Shattrath (Alliance)", destination = "Shattrath", faction = "Alliance", mapID = 111 },
    { spellID = 49359, name = "Teleport: Theramore", destination = "Theramore", faction = "Alliance", mapID = 12 },
    { spellID = 132621, name = "Teleport: Vale of Eternal Blossoms (Alliance)", destination = "Vale of Eternal Blossoms", faction = "Alliance", mapID = 390 },
    { spellID = 176242, name = "Teleport: Stormshield", destination = "Stormshield", faction = "Alliance", mapID = 622 },
    { spellID = 281403, name = "Teleport: Boralus", destination = "Boralus", faction = "Alliance", mapID = 1161 },

    -- Horde
    { spellID = 3563, name = "Teleport: Undercity", destination = "Undercity", faction = "Horde", mapID = 90 },
    { spellID = 3566, name = "Teleport: Thunder Bluff", destination = "Thunder Bluff", faction = "Horde", mapID = 88 },
    { spellID = 3567, name = "Teleport: Orgrimmar", destination = "Orgrimmar", faction = "Horde", mapID = 85 },
    { spellID = 32272, name = "Teleport: Silvermoon", destination = "Silvermoon", faction = "Horde", mapID = 110 },
    { spellID = 35715, name = "Teleport: Shattrath (Horde)", destination = "Shattrath", faction = "Horde", mapID = 111 },
    { spellID = 49358, name = "Teleport: Stonard", destination = "Stonard", faction = "Horde", mapID = 13 },
    { spellID = 132627, name = "Teleport: Vale of Eternal Blossoms (Horde)", destination = "Vale of Eternal Blossoms", faction = "Horde", mapID = 390 },
    { spellID = 176244, name = "Teleport: Warspear", destination = "Warspear", faction = "Horde", mapID = 624 },
    { spellID = 281404, name = "Teleport: Dazar'alor", destination = "Dazar'alor", faction = "Horde", mapID = 1165 },

    -- Neutral
    { spellID = 53140, name = "Teleport: Dalaran (Northrend)", destination = "Dalaran (Northrend)", faction = "Both", mapID = 125 },
    { spellID = 120145, name = "Teleport: Ancient Dalaran", destination = "Dalaran Crater", faction = "Both", mapID = 13 },
    { spellID = 132620, name = "Teleport: Vale of Eternal Blossoms", destination = "Vale of Eternal Blossoms", faction = "Both", mapID = 390 },
    { spellID = 224869, name = "Teleport: Dalaran (Broken Isles)", destination = "Dalaran (Broken Isles)", faction = "Both", mapID = 627 },
    { spellID = 344587, name = "Teleport: Oribos", destination = "Oribos", faction = "Both", mapID = 1670 },
    { spellID = 395277, name = "Teleport: Valdrakken", destination = "Valdrakken", faction = "Both", mapID = 2112 },
    { spellID = 446540, name = "Teleport: Dornogal", destination = "Dornogal", faction = "Both", mapID = 2339 },
    { spellID = 88342, name = "Teleport: Tol Barad (Alliance)", destination = "Tol Barad", faction = "Alliance", mapID = 245 },
    { spellID = 88344, name = "Teleport: Tol Barad (Horde)", destination = "Tol Barad", faction = "Horde", mapID = 245 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- MAGE PORTAL SPELLS
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.MagePortals = {
    -- Alliance
    { spellID = 10059, name = "Portal: Stormwind", destination = "Stormwind", faction = "Alliance", mapID = 84 },
    { spellID = 11416, name = "Portal: Ironforge", destination = "Ironforge", faction = "Alliance", mapID = 87 },
    { spellID = 11419, name = "Portal: Darnassus", destination = "Darnassus", faction = "Alliance", mapID = 89 },
    { spellID = 32266, name = "Portal: Exodar", destination = "Exodar", faction = "Alliance", mapID = 103 },
    { spellID = 33691, name = "Portal: Shattrath (Alliance)", destination = "Shattrath", faction = "Alliance", mapID = 111 },
    { spellID = 49360, name = "Portal: Theramore", destination = "Theramore", faction = "Alliance", mapID = 12 },
    { spellID = 132626, name = "Portal: Vale of Eternal Blossoms (Alliance)", destination = "Vale of Eternal Blossoms", faction = "Alliance", mapID = 390 },
    { spellID = 176246, name = "Portal: Stormshield", destination = "Stormshield", faction = "Alliance", mapID = 622 },
    { spellID = 281400, name = "Portal: Boralus", destination = "Boralus", faction = "Alliance", mapID = 1161 },

    -- Horde
    { spellID = 11417, name = "Portal: Orgrimmar", destination = "Orgrimmar", faction = "Horde", mapID = 85 },
    { spellID = 11418, name = "Portal: Undercity", destination = "Undercity", faction = "Horde", mapID = 90 },
    { spellID = 11420, name = "Portal: Thunder Bluff", destination = "Thunder Bluff", faction = "Horde", mapID = 88 },
    { spellID = 32267, name = "Portal: Silvermoon", destination = "Silvermoon", faction = "Horde", mapID = 110 },
    { spellID = 35717, name = "Portal: Shattrath (Horde)", destination = "Shattrath", faction = "Horde", mapID = 111 },
    { spellID = 49361, name = "Portal: Stonard", destination = "Stonard", faction = "Horde", mapID = 13 },
    { spellID = 132627, name = "Portal: Vale of Eternal Blossoms (Horde)", destination = "Vale of Eternal Blossoms", faction = "Horde", mapID = 390 },
    { spellID = 176248, name = "Portal: Warspear", destination = "Warspear", faction = "Horde", mapID = 624 },
    { spellID = 281402, name = "Portal: Dazar'alor", destination = "Dazar'alor", faction = "Horde", mapID = 1165 },

    -- Neutral
    { spellID = 53142, name = "Portal: Dalaran (Northrend)", destination = "Dalaran (Northrend)", faction = "Both", mapID = 125 },
    { spellID = 120146, name = "Portal: Ancient Dalaran", destination = "Dalaran Crater", faction = "Both", mapID = 13 },
    { spellID = 224871, name = "Portal: Dalaran (Broken Isles)", destination = "Dalaran (Broken Isles)", faction = "Both", mapID = 627 },
    { spellID = 344597, name = "Portal: Oribos", destination = "Oribos", faction = "Both", mapID = 1670 },
    { spellID = 395289, name = "Portal: Valdrakken", destination = "Valdrakken", faction = "Both", mapID = 2112 },
    { spellID = 446534, name = "Portal: Dornogal", destination = "Dornogal", faction = "Both", mapID = 2339 },
    { spellID = 88345, name = "Portal: Tol Barad (Alliance)", destination = "Tol Barad", faction = "Alliance", mapID = 245 },
    { spellID = 88346, name = "Portal: Tol Barad (Horde)", destination = "Tol Barad", faction = "Horde", mapID = 245 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS-SPECIFIC TELEPORTS
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.ClassTeleports = {
    -- Druid (Dreamwalk replaced Teleport: Moonglade)
    { spellID = 193753, name = "Dreamwalk", class = "DRUID", destination = "Emerald Dreamway", mapID = 715 },

    -- Monk
    { spellID = 126892, name = "Zen Pilgrimage", class = "MONK", destination = "Peak of Serenity", mapID = 569 },
    { spellID = 126895, name = "Zen Pilgrimage: Return", class = "MONK", destination = "Previous Location", mapID = 0,
        destinationKind = "previous", destinationResolver = "previous-location" },

    -- Death Knight
    { spellID = 50977, name = "Death Gate", class = "DEATHKNIGHT", destination = "Acherus", mapID = 118 },

    -- Shaman
    { spellID = 556, name = "Astral Recall", class = "SHAMAN", destination = "Hearthstone Location", mapID = 0,
        destinationKind = "bind", destinationResolver = "bind-location" },

    -- Warlock
    { spellID = 234121, name = "Twisting Corridors", class = "WARLOCK", destination = "Dreadscar Rift", mapID = 717 },

    -- Demon Hunter (Dalaran Order Hall)
    { spellID = 192085, name = "Jump to Fel Hammer", class = "DEMONHUNTER", destination = "Fel Hammer", mapID = 720 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- DUNGEON TELEPORTS (Hero's Path / Mythic+ teleports)
-- These are unlocked by completing dungeons on certain difficulties
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.DungeonTeleports = {
    -- ═══════════════════════════════════════════════════════════════════════
    -- Midnight (Season 3) Dungeons
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 1254559, name = "Teleport: Mechagon City", destination = "Mechagon City", mapID = 2501, zone = "Mechagon City" },
    { spellID = 1254563, name = "Teleport: Nightfall Priory", destination = "Nightfall Priory", mapID = 2556, zone = "Nightfall Priory" },
    { spellID = 1254572, name = "Teleport: The Murkmire", destination = "The Murkmire", mapID = 2511, zone = "The Murkmire" },
    { spellID = 1254400, name = "Teleport: Warrens", destination = "Warrens", mapID = 2494, zone = "Warrens" },
    { spellID = 1254551, name = "Teleport: Seat of the Triumvirate", destination = "Seat of the Triumvirate", mapID = 882, zone = "Mac'Aree" },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- The War Within Season 2 Dungeons
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 1216786, name = "Teleport: The Floodgate", destination = "The Floodgate", mapID = 0,
        zone = "The Ringing Deeps", landingMapID = 2214, regionMapID = 2214,
        destinationKind = "landing", identityConfidence = "landing-only" },
    { spellID = 1237215, name = "Teleport: Earthen Depths", destination = "Earthen Depths", mapID = 0,
        zone = "Unverified landing", landingMapID = 0, regionMapID = 0,
        destinationKind = "unknown", destinationResolver = "unverified-landing",
        identityConfidence = "unknown", routeEligible = false },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- The War Within Season 1 Dungeons
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 445269, name = "Teleport: The Stonevault", destination = "The Stonevault", mapID = 0,
        zone = "The Ringing Deeps", landingMapID = 2214, regionMapID = 2214,
        destinationKind = "landing", identityConfidence = "landing-only" },
    { spellID = 445416, name = "Teleport: City of Threads", destination = "City of Threads", mapID = 2255, zone = "City of Threads" },
    { spellID = 445414, name = "Teleport: The Dawnbreaker", destination = "The Dawnbreaker", mapID = 2215, zone = "Hallowfall" },
    { spellID = 445417, name = "Teleport: Ara-Kara", destination = "Ara-Kara, City of Echoes", mapID = 2216, zone = "Azj-Kahet" },
    { spellID = 445440, name = "Teleport: Cinderbrew Meadery", destination = "Cinderbrew Meadery", mapID = 2248, zone = "Isle of Dorn" },
    { spellID = 445444, name = "Teleport: Priory of the Sacred Flame", destination = "Priory of the Sacred Flame", mapID = 2215, zone = "Hallowfall" },
    { spellID = 445441, name = "Teleport: Darkflame Cleft", destination = "Darkflame Cleft", mapID = 0,
        zone = "The Ringing Deeps", landingMapID = 2214, regionMapID = 2214,
        destinationKind = "landing", identityConfidence = "landing-only" },
    { spellID = 445443, name = "Teleport: The Rookery", destination = "The Rookery", mapID = 2339, zone = "Dornogal" },
    
    -- TWW S1 Returning dungeons
    { spellID = 445424, name = "Teleport: Grim Batol", destination = "Grim Batol", mapID = 241, zone = "Twilight Highlands" },
    { spellID = 445418, name = "Teleport: Siege of Boralus", destination = "Siege of Boralus", mapID = 1161, zone = "Boralus", faction = "Alliance" },
    { spellID = 464256, name = "Teleport: Siege of Boralus", destination = "Siege of Boralus", mapID = 895, zone = "Tiragarde Sound", faction = "Horde" },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- Dragonflight Dungeons
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 424197, name = "Teleport: Dawn of the Infinite", destination = "Dawn of the Infinite", mapID = 2025, zone = "Thaldraszus" },
    { spellID = 393256, name = "Teleport: Ruby Life Pools", destination = "Ruby Life Pools", mapID = 2022, zone = "The Waking Shores" },
    { spellID = 393262, name = "Teleport: The Nokhud Offensive", destination = "The Nokhud Offensive", mapID = 2023, zone = "Ohn'ahran Plains" },
    { spellID = 393267, name = "Teleport: Brackenhide Hollow", destination = "Brackenhide Hollow", mapID = 2024, zone = "The Azure Span" },
    { spellID = 393273, name = "Teleport: Algeth'ar Academy", destination = "Algeth'ar Academy", mapID = 2025, zone = "Thaldraszus" },
    { spellID = 393276, name = "Teleport: Neltharus", destination = "Neltharus", mapID = 2022, zone = "The Waking Shores" },
    { spellID = 393279, name = "Teleport: The Azure Vault", destination = "The Azure Vault", mapID = 2024, zone = "The Azure Span" },
    { spellID = 393283, name = "Teleport: Halls of Infusion", destination = "Halls of Infusion", mapID = 2025, zone = "Thaldraszus" },
    { spellID = 393222, name = "Teleport: Uldaman: Legacy of Tyr", destination = "Uldaman: Legacy of Tyr", mapID = 15, zone = "Badlands" },
    { spellID = 393766, name = "Teleport: Court of Stars", destination = "Court of Stars", mapID = 680, zone = "Suramar" },
    { spellID = 393764, name = "Teleport: Halls of Valor", destination = "Halls of Valor", mapID = 634, zone = "Stormheim" },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- Shadowlands Dungeons
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 354462, name = "Teleport: The Necrotic Wake", destination = "The Necrotic Wake", mapID = 1533, zone = "Bastion" },
    { spellID = 354463, name = "Teleport: Plaguefall", destination = "Plaguefall", mapID = 1536, zone = "Maldraxxus" },
    { spellID = 354464, name = "Teleport: Mists of Tirna Scithe", destination = "Mists of Tirna Scithe", mapID = 1565, zone = "Ardenweald" },
    { spellID = 354465, name = "Teleport: Halls of Atonement", destination = "Halls of Atonement", mapID = 1525, zone = "Revendreth" },
    { spellID = 354466, name = "Teleport: Spires of Ascension", destination = "Spires of Ascension", mapID = 1533, zone = "Bastion" },
    { spellID = 354467, name = "Teleport: Theater of Pain", destination = "Theater of Pain", mapID = 1536, zone = "Maldraxxus" },
    { spellID = 354468, name = "Teleport: De Other Side", destination = "De Other Side", mapID = 1565, zone = "Ardenweald" },
    { spellID = 354469, name = "Teleport: Sanguine Depths", destination = "Sanguine Depths", mapID = 1525, zone = "Revendreth" },
    { spellID = 367416, name = "Teleport: Tazavesh", destination = "Tazavesh, the Veiled Market", mapID = 2472, zone = "Tazavesh" },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- Battle for Azeroth Dungeons
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 410071, name = "Teleport: Freehold", destination = "Freehold", mapID = 895, zone = "Tiragarde Sound" },
    { spellID = 410074, name = "Teleport: The Underrot", destination = "The Underrot", mapID = 863, zone = "Nazmir" },
    { spellID = 373274, name = "Teleport: Operation: Mechagon", destination = "Operation: Mechagon", mapID = 1462, zone = "Mechagon" },
    { spellID = 424167, name = "Teleport: Waycrest Manor", destination = "Waycrest Manor", mapID = 896, zone = "Drustvar" },
    { spellID = 424187, name = "Teleport: Atal'Dazar", destination = "Atal'Dazar", mapID = 862, zone = "Zuldazar" },
    { spellID = 467553, name = "Teleport: The MOTHERLODE!!", destination = "The MOTHERLODE!!", mapID = 862, zone = "Zuldazar", faction = "Alliance" },
    { spellID = 467555, name = "Teleport: The MOTHERLODE!!", destination = "The MOTHERLODE!!", mapID = 862, zone = "Zuldazar", faction = "Horde" },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- Legion Dungeons
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 424153, name = "Teleport: Black Rook Hold", destination = "Black Rook Hold", mapID = 641, zone = "Val'sharah" },
    { spellID = 424163, name = "Teleport: Darkheart Thicket", destination = "Darkheart Thicket", mapID = 641, zone = "Val'sharah" },
    { spellID = 410078, name = "Teleport: Neltharion's Lair", destination = "Neltharion's Lair", mapID = 650, zone = "Highmountain" },
    { spellID = 373262, name = "Teleport: Return to Karazhan", destination = "Return to Karazhan", mapID = 42, zone = "Deadwind Pass" },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- Warlords of Draenor Dungeons (Challenge Mode teleports)
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 159897, name = "Teleport: Auchindoun", destination = "Auchindoun", mapID = 535, zone = "Talador" },
    { spellID = 159895, name = "Teleport: Bloodmaul Slag Mines", destination = "Bloodmaul Slag Mines", mapID = 525, zone = "Frostfire Ridge" },
    { spellID = 159901, name = "Teleport: The Everbloom", destination = "The Everbloom", mapID = 543, zone = "Gorgrond" },
    { spellID = 159900, name = "Teleport: Grimrail Depot", destination = "Grimrail Depot", mapID = 543, zone = "Gorgrond" },
    { spellID = 159896, name = "Teleport: Iron Docks", destination = "Iron Docks", mapID = 543, zone = "Gorgrond" },
    { spellID = 159899, name = "Teleport: Shadowmoon Burial Grounds", destination = "Shadowmoon Burial Grounds", mapID = 539, zone = "Shadowmoon Valley" },
    { spellID = 159898, name = "Teleport: Skyreach", destination = "Skyreach", mapID = 542, zone = "Spires of Arak" },
    { spellID = 159902, name = "Teleport: Upper Blackrock Spire", destination = "Upper Blackrock Spire", mapID = 36, zone = "Burning Steppes" },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- Mists of Pandaria Dungeons (Challenge Mode teleports)
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 131225, name = "Teleport: Gate of the Setting Sun", destination = "Gate of the Setting Sun", mapID = 0,
        zone = "Vale of Eternal Blossoms", landingMapID = 390, regionMapID = 390,
        destinationKind = "landing", identityConfidence = "landing-only" },
    { spellID = 131222, name = "Teleport: Mogu'shan Palace", destination = "Mogu'shan Palace", mapID = 390, zone = "Vale of Eternal Blossoms" },
    { spellID = 131232, name = "Teleport: Scholomance", destination = "Scholomance", mapID = 22, zone = "Western Plaguelands" },
    { spellID = 131231, name = "Teleport: Shado-Pan Monastery", destination = "Shado-Pan Monastery", mapID = 379, zone = "Kun-Lai Summit" },
    { spellID = 131229, name = "Teleport: Scarlet Monastery", destination = "Scarlet Monastery", mapID = 18, zone = "Tirisfal Glades" },
    { spellID = 131228, name = "Teleport: Siege of Niuzao Temple", destination = "Siege of Niuzao Temple", mapID = 388, zone = "Townlong Steppes" },
    { spellID = 131206, name = "Teleport: Scarlet Halls", destination = "Scarlet Halls", mapID = 379, zone = "Kun-Lai Summit" },
    { spellID = 131205, name = "Teleport: Stormstout Brewery", destination = "Stormstout Brewery", mapID = 376, zone = "Valley of the Four Winds" },
    { spellID = 131204, name = "Teleport: Temple of the Jade Serpent", destination = "Temple of the Jade Serpent", mapID = 371, zone = "Jade Forest" },
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- Cataclysm Dungeons (Returning)
    -- ═══════════════════════════════════════════════════════════════════════
    { spellID = 424142, name = "Teleport: Throne of the Tides", destination = "Throne of the Tides", mapID = 203, zone = "Vashj'ir" },
    { spellID = 410080, name = "Teleport: Vortex Pinnacle", destination = "Vortex Pinnacle", mapID = 0,
        zone = "Uldum", landingMapID = 249, regionMapID = 249,
        destinationKind = "landing", identityConfidence = "landing-only" },
}

-- Dungeon teleport records historically mixed an instance identity with the
-- region in which the player lands.  Keep the original source map as
-- unverified instance metadata, and make the routable destination explicit.
-- A zero identity means "not verified by the current data set"; it is never
-- used as a graph node or as a route destination.
local DUNGEON_REGION_MAPS = {
    ["The Ringing Deeps"] = 2214,
    ["City of Threads"] = 2255,
    ["Hallowfall"] = 2215,
    ["Azj-Kahet"] = 2255,
    ["Isle of Dorn"] = 2248,
    ["Dornogal"] = 2339,
    ["Twilight Highlands"] = 241,
    ["Boralus"] = 1161,
    ["Tiragarde Sound"] = 895,
    ["Thaldraszus"] = 2025,
    ["The Waking Shores"] = 2022,
    ["Ohn'ahran Plains"] = 2023,
    ["The Azure Span"] = 2024,
    ["Badlands"] = 17,
    ["Suramar"] = 680,
    ["Stormheim"] = 634,
    ["Bastion"] = 1533,
    ["Maldraxxus"] = 1536,
    ["Ardenweald"] = 1565,
    ["Revendreth"] = 1525,
    ["Tazavesh"] = 2472,
    ["Mac'Aree"] = 882,
    ["Nazmir"] = 863,
    ["Mechagon"] = 1462,
    ["Zuldazar"] = 862,
    ["Val'sharah"] = 641,
    ["Highmountain"] = 650,
    ["Deadwind Pass"] = 42,
    ["Talador"] = 535,
    ["Frostfire Ridge"] = 525,
    ["Gorgrond"] = 543,
    ["Shadowmoon Valley"] = 539,
    ["Spires of Arak"] = 542,
    ["Burning Steppes"] = 36,
    ["Vale of Eternal Blossoms"] = 390,
    ["Western Plaguelands"] = 22,
    ["Kun-Lai Summit"] = 379,
    ["Townlong Steppes"] = 388,
    ["Tirisfal Glades"] = 18,
    ["Valley of the Four Winds"] = 376,
    ["Vashj'ir"] = 203,
    ["Uldum"] = 249,
}

TA.TravelData.DungeonIdentityPolicy = {
    instanceField = "instanceMapID",
    entranceField = "entranceMapID",
    landingField = "landingMapID",
    regionField = "regionMapID",
    legacyMapField = "regionMapID",
    routeTarget = "landingMapID",
    unknownValue = 0,
}

for _, dungeon in ipairs(TA.TravelData.DungeonTeleports) do
    local landingMapID = dungeon.landingMapID or dungeon.destinationMapID or dungeon.mapID
    local regionMapID = dungeon.regionMapID or DUNGEON_REGION_MAPS[dungeon.zone] or landingMapID
    if dungeon.spellID == 1237215 then
        -- The current record's old mapID points at Emerald Dream, not a
        -- verified Earthen Depths landing.  Keep the source informational
        -- until the client supplies an authoritative landing map.
        landingMapID = 0
        regionMapID = 0
    end
    dungeon.instanceKey = dungeon.instanceKey or dungeon.destination or dungeon.name
    dungeon.instanceMapID = dungeon.instanceMapID or 0
    dungeon.entranceMapID = dungeon.entranceMapID or 0
    dungeon.landingMapID = landingMapID
    dungeon.regionMapID = regionMapID
    dungeon.destinationMapID = landingMapID
    dungeon.destinationKind = dungeon.destinationKind or "landing"
    dungeon.identityConfidence = dungeon.identityConfidence or (dungeon.instanceMapID > 0 and "high"
        or (landingMapID > 0 and "landing-only" or "unknown"))
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HEARTHSTONE ITEMS
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.Hearthstones = {
    -- Main Hearthstone (everyone has this)
    { itemID = 6948, name = "Hearthstone", destination = "Set Inn Location", cooldown = 900 },

    -- Special Hearthstones
    { itemID = 64488, name = "The Innkeeper's Daughter", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 93672, name = "Dark Portal", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 142542, name = "Tome of Town Portal", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 162973, name = "Greatfather Winter's Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 163045, name = "Headless Horseman's Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 165669, name = "Lunar Elder's Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 165670, name = "Peddlefeet's Lovely Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 165802, name = "Noble Gardener's Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 166746, name = "Fire Eater's Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 166747, name = "Brewfest Reveler's Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 168907, name = "Holographic Digitalization Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 172179, name = "Eternal Traveler's Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 180290, name = "Night Fae Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 182773, name = "Necrolord Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 183716, name = "Venthyr Sinstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 184353, name = "Kyrian Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 188952, name = "Dominated Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 190237, name = "Broker Translocation Matrix", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 190196, name = "Enlightened Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 200630, name = "Ohn'ir Windsage's Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 206195, name = "Path of the Naaru", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 208704, name = "Deepdweller's Earthen Hearthstone", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 209035, name = "Hearthstone of the Flame", destination = "Set Inn Location", cooldown = 900 },
    { itemID = 212337, name = "Stone of the Hearth", destination = "Set Inn Location", cooldown = 900 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- FIXED DESTINATION ITEMS (Teleport to specific location)
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.TeleportItems = {
    -- Dalaran Items (non-toys)
    { itemID = 132523, name = "Reaves Module: Bling Mode", destination = "Dalaran (Broken Isles)", mapID = 627, cooldown = 14400 },
    { itemID = 139599, name = "Empowered Ring of the Kirin Tor", destination = "Dalaran (Broken Isles)", mapID = 627, cooldown = 1800 },
    { itemID = 118907, name = "Pit Fighter's Punching Ring", destination = "Ashran", mapID = 588, cooldown = 1800 },
    { itemID = 118908, name = "Ironbeard's Fist", destination = "Ashran", mapID = 588, cooldown = 1800 },

    -- Engineering
    { itemID = 18984, name = "Dimensional Ripper - Everlook", destination = "Everlook", mapID = 83, cooldown = 14400, profession = "Engineering" },
    { itemID = 18986, name = "Ultrasafe Transporter: Gadgetzan", destination = "Gadgetzan", mapID = 71, cooldown = 14400, profession = "Engineering" },
    { itemID = 30542, name = "Dimensional Ripper - Area 52", destination = "Area 52", mapID = 102, cooldown = 14400, profession = "Engineering" },
    { itemID = 30544, name = "Ultrasafe Transporter: Toshley's Station", destination = "Toshley's Station", mapID = 105, cooldown = 14400, profession = "Engineering" },
    { itemID = 48933, name = "Wormhole Generator: Northrend", destination = "Northrend (Random)", mapID = 113, cooldown = 14400, profession = "Engineering" },
    { itemID = 87215, name = "Wormhole Generator: Pandaria", destination = "Pandaria (Random)", mapID = 424, cooldown = 14400, profession = "Engineering" },
    { itemID = 112059, name = "Wormhole Centrifuge", destination = "Draenor (Random)", mapID = 572, cooldown = 14400, profession = "Engineering" },
    { itemID = 151652, name = "Wormhole Generator: Argus", destination = "Argus", mapID = 905, cooldown = 14400, profession = "Engineering" },
    { itemID = 168807, name = "Wormhole Generator: Kul Tiras", destination = "Kul Tiras (Random)", mapID = 876, cooldown = 900, profession = "Engineering" },
    { itemID = 168808, name = "Wormhole Generator: Zandalar", destination = "Zandalar (Random)", mapID = 875, cooldown = 900, profession = "Engineering" },
    { itemID = 172924, name = "Wormhole Generator: Shadowlands", destination = "Shadowlands (Random)", mapID = 1550, cooldown = 900, profession = "Engineering" },
    { itemID = 198156, name = "Wyrmhole Generator: Dragon Isles", destination = "Dragon Isles (Random)", mapID = 1978, cooldown = 900, profession = "Engineering" },
    { itemID = 221966, name = "Wormhole Generator: Khaz Algar", destination = "Khaz Algar (Random)", mapID = 2274, cooldown = 900, profession = "Engineering" },

    -- Specific Locations
    { itemID = 52251, name = "Jaina's Locket", destination = "Dalaran (Northrend)", mapID = 125, cooldown = 3600 },
    { itemID = 46874, name = "Argent Crusader's Tabard", destination = "Argent Tournament", mapID = 118, cooldown = 1800 },
    { itemID = 63207, name = "Wrap of Unity (Alliance)", destination = "Stormwind", mapID = 84, cooldown = 14400, faction = "Alliance" },
    { itemID = 63206, name = "Wrap of Unity (Horde)", destination = "Orgrimmar", mapID = 85, cooldown = 14400, faction = "Horde" },
    { itemID = 63352, name = "Shroud of Cooperation (Alliance)", destination = "Stormwind", mapID = 84, cooldown = 14400, faction = "Alliance" },
    { itemID = 63353, name = "Shroud of Cooperation (Horde)", destination = "Orgrimmar", mapID = 85, cooldown = 14400, faction = "Horde" },
    { itemID = 65274, name = "Cloak of Coordination (Alliance)", destination = "Stormwind", mapID = 84, cooldown = 14400, faction = "Alliance" },
    { itemID = 65360, name = "Cloak of Coordination (Horde)", destination = "Orgrimmar", mapID = 85, cooldown = 14400, faction = "Horde" },
    { itemID = 95567, name = "Timeless Isle Trinket", destination = "Timeless Isle", mapID = 554, cooldown = 3600 },
    { itemID = 95568, name = "Timeless Treasure Chest", destination = "Timeless Isle", mapID = 554, cooldown = 3600 },
    { itemID = 141605, name = "Flight Master's Whistle", destination = "Nearest Flight Master", mapID = 0, cooldown = 300,
        destinationKind = "nearby", destinationResolver = "nearest-flight-master" },

    -- Shadowlands
    { itemID = 180817, name = "Cypher of Relocation", destination = "Zereth Mortis", mapID = 1970, cooldown = 3600 },

    -- Dragon Isles
    { itemID = 201420, name = "Antique Bronze Bullion", destination = "Valdrakken", mapID = 2112, cooldown = 3600 },

    -- BfA
    { itemID = 165016, name = "Scroll of Teleport: Dazar'alor", destination = "Dazar'alor", mapID = 1165, cooldown = 1800, faction = "Horde" },
    { itemID = 165017, name = "Scroll of Teleport: Boralus", destination = "Boralus", mapID = 1161, cooldown = 1800, faction = "Alliance" },

    -- Misc
    { itemID = 22632, name = "Tidal Charm", destination = "None", mapID = 0, cooldown = 900,
        destinationKind = "unknown", routeEligible = false, actionableByPlayer = false }, -- summon only
    { itemID = 37863, name = "Direbrew's Remote", destination = "Grim Guzzler", mapID = 35, cooldown = 3600 },
    { itemID = 50287, name = "Boots of the Bay", destination = "Booty Bay", mapID = 210, cooldown = 3600 },
    { itemID = 142469, name = "Violet Seal of the Grand Magus", destination = "Dalaran (Broken Isles)", mapID = 627, cooldown = 7200 },
    { itemID = 132517, name = "Intra-Dalaran Wormhole Generator", destination = "Dalaran", mapID = 627, cooldown = 120 },

    -- Ruby Life Pools
    { itemID = 193753, name = "Ruby Whelp Shell", destination = "Ruby Lifeshrine", mapID = 2023, cooldown = 3600 },

}

-- ═══════════════════════════════════════════════════════════════════════════
-- TOYS THAT TELEPORT
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.TeleportToys = {
    -- Hearthstone Toys
    { itemID = 140192, name = "Dalaran Hearthstone", destination = "Dalaran (Broken Isles)", mapID = 627, cooldown = 1200 },
    { itemID = 110560, name = "Garrison Hearthstone", destination = "Garrison", mapID = 579, cooldown = 1200 },
    { itemID = 228743, name = "Earthen Hearthstone", destination = "Dornogal", mapID = 2339, cooldown = 1200 },
    
    -- Other Toys
    { itemID = 64457, name = "The Last Relic of Argus", destination = "Random Location", mapID = 0, cooldown = 43200,
        destinationKind = "random", destinationResolver = "random-location", routeEligible = false },
    { itemID = 95589, name = "Scroll of Vicious Mage Portal", destination = "Ancient Dalaran (Lethal!)", mapID = 13, cooldown = 3600 },
    { itemID = 93672, name = "Dark Portal", destination = "Set Inn Location", mapID = 0, cooldown = 900,
        destinationKind = "bind", destinationResolver = "bind-location" },
    { itemID = 129276, name = "Beginner's Guide to Dimension Shifting", destination = "Random Draenor Location", mapID = 572, cooldown = 28800,
        destinationKind = "random", destinationResolver = "random-location", routeEligible = false },
    { itemID = 168862, name = "G.E.A.R. Tracking Beacon", destination = "Mechagon", mapID = 1462, cooldown = 14400 },
    { itemID = 168220, name = "Mechagonian Sawblades", destination = "Mechagon", mapID = 1462, cooldown = 14400 },
    { itemID = 180290, name = "Night Fae Hearthstone", destination = "Set Inn Location", mapID = 0, cooldown = 900,
        destinationKind = "bind", destinationResolver = "bind-location" },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- RACIAL ABILITIES
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.RacialTeleports = {
    -- Vulpera
    {
        spellID = 312370,
        name = "Make Camp",
        race = "Vulpera",
        destination = "Camp Location",
        mapID = 0,
        sourceFamily = "racial-camp",
        interaction = "setup-location",
        actionableByPlayer = false,
        routeEligible = false,
        destinationKind = "choice",
        destinationResolver = "camp-location",
    },
    {
        spellID = 312372,
        name = "Return to Camp",
        race = "Vulpera",
        destination = "Camp Location",
        mapID = 0,
        sourceFamily = "racial-return",
        interaction = "dynamic-destination",
        destinationKind = "choice",
        destinationResolver = "camp-location",
    },

    -- Dark Iron Dwarf
    {
        spellID = 265221,
        name = "Mole Machine",
        race = "DarkIronDwarf",
        destination = "Various Locations",
        mapID = 0,
        sourceFamily = "racial-mole-machine",
        interaction = "player-choice",
        actionableByPlayer = false,
        destinationOptions = "MoleMachineDestinations",
        destinationKind = "choice",
        destinationResolver = "player-choice",
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- DARK IRON DWARF MOLE MACHINE DESTINATIONS
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.MoleMachineDestinations = {
    { name = "Shadowforge City", mapID = 35, continent = "Eastern Kingdoms" },
    { name = "Stormwind", mapID = 84, continent = "Eastern Kingdoms" },
    { name = "Ironforge", mapID = 87, continent = "Eastern Kingdoms" },
    { name = "Aerie Peak", mapID = 26, continent = "Eastern Kingdoms" },
    { name = "Thorium Point", mapID = 36, continent = "Eastern Kingdoms" },
    { name = "Nethergarde Keep", mapID = 17, continent = "Eastern Kingdoms" },
    { name = "Fire Plume Ridge", mapID = 78, continent = "Kalimdor" },
    { name = "Ratchet", mapID = 10, continent = "Kalimdor" },
    { name = "Stony Talons", mapID = 65, continent = "Kalimdor" },
    { name = "Honor's Stand", mapID = 63, continent = "Kalimdor" },
    { name = "Dragonmaw Port", mapID = 241, continent = "Eastern Kingdoms" },
    { name = "Anyport", mapID = 862, continent = "Zandalar" },
    { name = "Kaja'mine", mapID = 863, continent = "Zandalar" },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ZONE CONNECTIONS (for route planning)
-- Links between zones that can be traversed without teleporting
-- ═══════════════════════════════════════════════════════════════════════════
--
-- A connection is a real topology edge, not a statement that two maps share a
-- continent.  The graph consumes only these records (and portal-hub records)
-- when it builds static routing edges.  `bidirectional` is explicit because
-- portals and external interactions are intentionally one-way.
--
-- Costs are estimates in seconds.  They are deliberately marked approximate
-- until live flight-path and movement calibration is available.
TA.TravelData.ZoneConnections = {
    -- Eastern Kingdoms: known approaches to the Alliance capital.
    [14] = {
        { to = 84, type = "walk", mode = "walking", cost = 90, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [52] = {
        { to = 84, type = "flight", mode = "flightpath", cost = 150, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [56] = {
        { to = 84, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [47] = {
        { to = 84, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
    },

    -- Kalimdor: known approaches to the Horde capital.
    [11] = {
        { to = 85, type = "walk", mode = "walking", cost = 90, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [10] = {
        { to = 85, type = "flight", mode = "flightpath", cost = 150, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [61] = {
        { to = 85, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
    },

    -- Explicit intermediate flight networks.  These are intentionally sparse
    -- until discovered flight-path data is available; no same-continent
    -- complete graph is generated by the runtime.
    [84] = {
        { to = 52, type = "flight", mode = "flightpath", cost = 150, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 56, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 47, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [85] = {
        { to = 11, type = "flight", mode = "flightpath", cost = 90, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 10, type = "flight", mode = "flightpath", cost = 150, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 61, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
    },

    -- Khaz Algar: Dornogal is an intermediate hub for the open-world zones.
    [2339] = {
        { to = 2248, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 2214, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 2215, type = "flight", mode = "flightpath", cost = 240, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 2255, type = "flight", mode = "flightpath", cost = 270, bidirectional = true,
            confidence = "low", approximate = true },
    },

    -- Dragon Isles, Shadowlands, and older expansion hubs retain explicit
    -- region transitions.  Portal edges still model the cross-expansion hop.
    [2112] = {
        { to = 2022, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 2023, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 2024, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 2025, type = "flight", mode = "flightpath", cost = 120, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [1670] = {
        { to = 1533, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 1536, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 1565, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 1525, type = "flight", mode = "flightpath", cost = 210, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [627] = {
        { to = 630, type = "flight", mode = "flightpath", cost = 150, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 634, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 641, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
    },
    [125] = {
        { to = 114, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 115, type = "flight", mode = "flightpath", cost = 150, bidirectional = true,
            confidence = "low", approximate = true },
        { to = 116, type = "flight", mode = "flightpath", cost = 180, bidirectional = true,
            confidence = "low", approximate = true },
    },
}

-- Static identity metadata is intentionally separate from player-state source
-- records.  It lets instances and landing regions be displayed distinctly
-- without pretending that an unverified instance map is a routable region.
TA.TravelData.MapIdentity = {
    [84] = { kind = "hub", regionMapID = 84, services = { "portal-room", "flightpath" } },
    [85] = { kind = "hub", regionMapID = 85, services = { "portal-room", "flightpath" } },
    [125] = { kind = "hub", regionMapID = 125, services = { "portal-room", "flightpath" } },
    [627] = { kind = "hub", regionMapID = 627, services = { "portal-room", "flightpath" } },
    [1670] = { kind = "hub", regionMapID = 1670, services = { "portal-room", "flightpath" } },
    [2112] = { kind = "hub", regionMapID = 2112, services = { "portal-room", "flightpath" } },
    [2339] = { kind = "hub", regionMapID = 2339, services = { "portal-room", "flightpath" } },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PORTAL ROOMS / HUB CONNECTIONS
-- Major hubs with portals to other locations
-- ═══════════════════════════════════════════════════════════════════════════
-- Portal room waypoint coordinates (mapID, x*100, y*100)
TA.TravelData.PortalHubs = {
    -- ═══════════════════════════════════════════════════════════════════════════
    -- CAPITAL CITIES - Main portal hubs with most connections
    -- World coords (inst, wx, wy) from PortalHelper + fallback x, y map percentages
    -- ═══════════════════════════════════════════════════════════════════════════
    
    -- Stormwind Portal Room (Alliance) /way 49 87
    -- instanceID = 0 for Eastern Kingdoms
    {
        name = "Stormwind Portal Room",
        mapID = 84,
        inst = 0, wx = 900, wy = -9050,
        x = 49.0, y = 87.0,  -- Fallback map percentage
        faction = "Alliance",
        portalsTo = {
            -- The War Within (11.x)
            { name = "Dornogal", mapID = 2339, inst = 0, wx = 886.60, wy = -9060.70, x = 48.8, y = 87.2 },
            -- Dragonflight (10.x)
            { name = "Valdrakken", mapID = 2112, inst = 0, wx = 872.9, wy = -9077.6, x = 48.7, y = 87.3 },
            -- Shadowlands (9.x)
            { name = "Oribos", mapID = 1670, inst = 0, wx = 896.40, wy = -9095.60, x = 49.0, y = 87.5 },
            -- Battle for Azeroth (8.x)
            { name = "Boralus", mapID = 1161, inst = 0, wx = 875.40, wy = -9099.30, x = 48.8, y = 87.6 },
            -- Legion (7.x)
            { name = "Azsuna", mapID = 630, inst = 0, wx = 991.50, wy = -9053.60, x = 49.4, y = 86.9 },
            -- Warlords of Draenor (6.x)
            { name = "Stormshield", mapID = 622, inst = 0, wx = 1004.30, wy = -9036.70, x = 49.5, y = 86.7 },
            -- Mists of Pandaria (5.x)
            { name = "Jade Forest", mapID = 371, inst = 0, wx = 928.60, wy = -9005.20, x = 49.1, y = 86.5 },
            -- Cataclysm (4.x) - Lake Everstill area /way 73 64
            { name = "Deepholm", mapID = 207, inst = 0, wx = 451.60, wy = -8223.60, x = 73.5, y = 64.3 },
            { name = "Hyjal", mapID = 198, inst = 0, wx = 399.00, wy = -8212.30, x = 73.0, y = 63.8 },
            { name = "Vashj'ir", mapID = 203, inst = 0, wx = 449.40, wy = -8191.40, x = 73.5, y = 63.4 },
            { name = "Twilight Highlands", mapID = 241, inst = 0, wx = 413.90, wy = -8186.10, x = 73.2, y = 63.2 },
            { name = "Uldum", mapID = 249, inst = 0, wx = 415.70, wy = -8233.50, x = 73.2, y = 64.8 },
            { name = "Tol Barad", mapID = 245, inst = 0, wx = 450.90, wy = -8208.80, x = 73.6, y = 64.0 },
            -- Wrath of the Lich King (3.x)
            { name = "Dalaran (Northrend)", mapID = 125, inst = 0, wx = 952.00, wy = -9023.40, x = 49.4, y = 86.6 },
            -- Burning Crusade (2.x)
            { name = "Shattrath", mapID = 111, inst = 0, wx = 943.00, wy = -8988.80, x = 49.3, y = 86.3 },
            { name = "Caverns of Time", mapID = 71, inst = 0, wx = 963.00, wy = -8985.00, x = 49.5, y = 86.2 },
            -- Classic cities
            { name = "Exodar", mapID = 103, inst = 0, wx = 965.40, wy = -9006.10, x = 49.6, y = 86.5 },
        }
    },

    -- Orgrimmar Portal Room (Horde) - Pathfinder's Den /way 55 12
    -- instanceID = 1 for Kalimdor
    {
        name = "Orgrimmar Portal Room",
        mapID = 85,
        inst = 1, wx = -4500, wy = 1440,
        x = 55.3, y = 11.8,  -- Fallback map percentage
        faction = "Horde",
        portalsTo = {
            -- The War Within (11.x)
            { name = "Dornogal", mapID = 2339, inst = 1, wx = -4525.20, wy = 1427.00, x = 55.1, y = 11.6 },
            -- Dragonflight (10.x)
            { name = "Valdrakken", mapID = 2112, inst = 1, wx = -4499.9, wy = 1474.7, x = 55.0, y = 12.0 },
            -- Shadowlands (9.x)
            { name = "Oribos", mapID = 1670, inst = 1, wx = -4520.90, wy = 1468.50, x = 55.1, y = 11.9 },
            -- Battle for Azeroth (8.x) - Portal goes to Dazar'alor (city in Zuldazar)
            { name = "Dazar'alor", mapID = 1165, inst = 1, wx = -4513.10, wy = 1445.10, x = 55.0, y = 11.7 },
            -- Legion (7.x)
            { name = "Azsuna", mapID = 630, inst = 1, wx = -4501.70, wy = 1463.30, x = 55.0, y = 11.9 },
            -- Warlords of Draenor (6.x)
            { name = "Warspear", mapID = 624, inst = 1, wx = -4466.40, wy = 1419.00, x = 55.6, y = 11.3 },
            -- Mists of Pandaria (5.x)
            { name = "Jade Forest", mapID = 371, inst = 1, wx = -4505.80, wy = 1417.20, x = 55.0, y = 11.4 },
            -- Cataclysm (4.x) - Earthen Ring portal area /way 50 37
            { name = "Deepholm", mapID = 207, inst = 1, wx = -4389.90, wy = 2064.70, x = 50.7, y = 37.4 },
            { name = "Hyjal", mapID = 198, inst = 1, wx = -4395.30, wy = 2043.00, x = 50.8, y = 37.0 },
            { name = "Vashj'ir", mapID = 203, inst = 1, wx = -4362.50, wy = 2063.60, x = 50.2, y = 37.3 },
            { name = "Twilight Highlands", mapID = 241, inst = 1, wx = -4379.80, wy = 2028.70, x = 50.5, y = 36.8 },
            { name = "Uldum", mapID = 249, inst = 1, wx = -4356.60, wy = 2039.40, x = 50.1, y = 37.0 },
            { name = "Tol Barad", mapID = 245, inst = 1, wx = -4330.80, wy = 2031.10, x = 49.7, y = 36.9 },
            -- Wrath of the Lich King (3.x)
            { name = "Dalaran (Northrend)", mapID = 125, inst = 1, wx = -4484.80, wy = 1422.90, x = 55.4, y = 11.4 },
            -- Burning Crusade (2.x)
            { name = "Shattrath", mapID = 111, inst = 1, wx = -4506.80, wy = 1423.40, x = 55.0, y = 11.4 },
            { name = "Caverns of Time", mapID = 71, inst = 1, wx = -4487.40, wy = 1413.40, x = 55.5, y = 11.2 },
            -- Classic cities (different area)
            { name = "Undercity", mapID = 90, inst = 1, wx = -4388.6, wy = 1842.2, x = 50.8, y = 35.5 },
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- THE WAR WITHIN (11.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Dornogal (Both) - Khaz Algar hub
    -- World coordinates from PortalHelper: inst=2552
    -- x, y are fallback map percentages (0-100 scale)
    {
        name = "Dornogal",
        mapID = 2339,
        inst = 2552, wx = -2400, wy = 2900,
        x = 47.5, y = 61.0,  -- Fallback: center of city
        faction = "Both",
        portalsTo = {
            -- Back to capitals (bidirectional portals)
            { name = "Stormwind", mapID = 84, faction = "Alliance", inst = 2552, wx = -2398.30, wy = 2983.10, x = 47.6, y = 60.8 },
            { name = "Orgrimmar", mapID = 85, faction = "Horde", inst = 2552, wx = -2334.20, wy = 2918.60, x = 47.4, y = 61.2 },
            -- Khaz Algar zone portals (The War Within zones)
            { name = "K'aresh", mapID = 2371, inst = 2552, wx = -2395.00, wy = 2950.00, x = 47.5, y = 61.0 },
            { name = "Azj-Kahet", mapID = 2255, inst = 2552, wx = -2380.00, wy = 2935.00, x = 47.5, y = 61.0 },
            -- Undermine portal - near the harbor
            { name = "Undermine", mapID = 2346, inst = 2552, wx = -2633.00, wy = 2591.00, x = 44.0, y = 56.0 },
        }
    },

    -- Undermine (Both) - 11.1 new zone
    -- World coordinates from PortalHelper: inst=2706
    {
        name = "Undermine",
        mapID = 2346,
        inst = 2706, wx = 847.70, wy = -39.50,
        x = 50.0, y = 50.0,  -- Fallback: center estimate
        faction = "Both",
        portalsTo = {
            -- Back to Dornogal
            { name = "Dornogal", mapID = 2339, inst = 2706, wx = 847.70, wy = -39.50, x = 50.0, y = 50.0 },
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- DRAGONFLIGHT (10.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Valdrakken (Both) - Dragon Isles hub /way 58 35
    -- instanceID = 2444 for Dragon Isles
    {
        name = "Valdrakken",
        mapID = 2112,
        inst = 2444, wx = -1050, wy = 200,
        x = 58.0, y = 35.0,  -- Fallback: Seat of the Aspects portal area
        faction = "Both",
        portalsTo = {
            -- Back to capitals - where you arrive from capitals
            { name = "Stormwind", mapID = 84, faction = "Alliance", inst = 2444, wx = -1069.2, wy = 245.6, x = 57.8, y = 34.8 },
            { name = "Orgrimmar", mapID = 85, faction = "Horde", inst = 2444, wx = -1021.6, wy = 279.2, x = 58.2, y = 35.2 },
            -- Emerald Dream portal - confirmed in PortalHelper
            { name = "Central Encampment", mapID = 2200, inst = 2444, wx = -1110.3, wy = 93.3, x = 57.5, y = 34.5 },
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- SHADOWLANDS (9.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Oribos (Both) - Shadowlands hub /way 50 53
    -- instanceID = 2222 for Shadowlands
    {
        name = "Oribos",
        mapID = 1670,
        inst = 2222, wx = 1350, wy = -1770,
        x = 50.0, y = 53.0,  -- Fallback: Ring of Transference
        faction = "Both",
        portalsTo = {
            -- Back to capitals - where you arrive from capitals
            { name = "Stormwind", mapID = 84, faction = "Alliance", inst = 2222, wx = 1537.70, wy = -1808.40, x = 20.4, y = 57.5 },
            { name = "Orgrimmar", mapID = 85, faction = "Horde", inst = 2222, wx = 1538.10, wy = -1858.50, x = 20.4, y = 42.5 },
            -- Confirmed portals in Ring of Transference
            { name = "Zereth Mortis", mapID = 1970, inst = 2222, wx = 1283.00, wy = -1726.40, x = 45.5, y = 50.5 },
            { name = "Korthia", mapID = 1961, inst = 2222, wx = 1401.90, wy = -1715.20, x = 52.0, y = 49.0 },
            { name = "The Maw", mapID = 1543, inst = 2222, wx = 1299.60, wy = -1816.60, x = 46.0, y = 59.0 },
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- BATTLE FOR AZEROTH (8.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Boralus (Alliance) - Kul Tiras hub /way 70 17
    -- instanceID = 1643 for Kul Tiras
    {
        name = "Boralus",
        mapID = 1161,
        inst = 1643, wx = -520, wy = 1140,
        x = 70.0, y = 17.0,  -- Fallback: Harbormaster's Office
        faction = "Alliance",
        portalsTo = {
            -- Back to capital - where you arrive from Stormwind
            { name = "Stormwind", mapID = 84, inst = 1643, wx = -525.10, wy = 1132.70, x = 70.2, y = 16.8 },
            -- Portal room
            { name = "Ironforge", mapID = 87, inst = 1643, wx = -538.10, wy = 1149.80, x = 69.8, y = 17.2 },
            { name = "Exodar", mapID = 103, inst = 1643, wx = -529.50, wy = 1154.60, x = 70.0, y = 17.4 },
            -- BfA patch zones
            { name = "Silithus", mapID = 81, inst = 1643, wx = -515.80, wy = 1143.00, x = 70.4, y = 17.0 },
            { name = "Nazjatar", mapID = 1355, inst = 1643, wx = -519.80, wy = 1150.20, x = 70.3, y = 17.1 },
        }
    },

    -- Dazar'alor / Zuldazar (Horde) - Zandalar hub, Great Seal /way 50 40
    -- instanceID = 1642 for Zandalar
    {
        name = "Dazar'alor",
        mapID = 1165,
        inst = 1642, wx = 760, wy = -1130,
        x = 50.0, y = 40.0,  -- Fallback: Great Seal portal area
        faction = "Horde",
        portalsTo = {
            -- Back to capital
            { name = "Orgrimmar", mapID = 85, inst = 1642, wx = 758.90, wy = -1124.10, x = 50.0, y = 39.8 },
            -- Portal room (in Great Seal)
            { name = "Thunder Bluff", mapID = 88, inst = 1642, wx = 759.60, wy = -1132.90, x = 50.0, y = 40.2 },
            { name = "Silvermoon", mapID = 110, inst = 1642, wx = 759.20, wy = -1114.40, x = 50.0, y = 39.6 },
            -- BfA patch zones
            { name = "Silithus", mapID = 81, inst = 1642, wx = 759.60, wy = -1142.70, x = 50.0, y = 40.5 },
            { name = "Nazjatar", mapID = 1355, inst = 1642, wx = 779.20, wy = -1142.30, x = 50.5, y = 40.5 },
            { name = "Darkshore", mapID = 62, x = 25, y = 25 },
            { name = "Mechagon Island", mapID = 1462, x = 41, y = 87, faction = "Horde" },
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- LEGION (7.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Dalaran Legion (Both) - Broken Isles hub
    -- World coordinates from PortalHelper: inst=1220
    {
        name = "Dalaran (Legion)",
        mapID = 627,
        inst = 1220,
        wx = 4418.90, wy = -714.60,  -- Center of Dalaran
        x = 39.6, y = 63.3,  -- Fallback map percentage
        faction = "Both",
        portalsTo = {
            -- Back to capitals - Violet Citadel
            { name = "Stormwind", mapID = 84, faction = "Alliance", inst = 1220, wx = 4390.90, wy = -752.40, x = 39.0, y = 63.0 },
            { name = "Orgrimmar", mapID = 85, faction = "Horde", inst = 1220, wx = 4418.90, wy = -714.60, x = 39.5, y = 63.5 },
            -- Chamber of the Guardian (lower level) - confirmed portals
            { name = "Karazhan", mapID = 42, inst = 1220, wx = 4390.00, wy = -780.00, x = 38.8, y = 64.0 },
            { name = "Wyrmrest Temple", mapID = 115, inst = 1220, wx = 4400.00, wy = -770.00, x = 39.0, y = 63.8 },
            -- Vindicaar/Argus portal - exact coords from PortalHelper
            -- Portal goes to Vindicaar, which gives access to all Argus zones
            { name = "Vindicaar", mapID = 832, inst = 1220, wx = 4264.20, wy = -852.00, x = 74.0, y = 49.0 },
            { name = "Argus", mapID = 905, inst = 1220, wx = 4264.20, wy = -852.00, x = 74.0, y = 49.0 },  -- Same portal
            { name = "Krokuun", mapID = 830, inst = 1220, wx = 4264.20, wy = -852.00, x = 74.0, y = 49.0 },  -- Same portal
            { name = "Mac'Aree", mapID = 882, inst = 1220, wx = 4264.20, wy = -852.00, x = 74.0, y = 49.0 },  -- Same portal
            { name = "Antoran Wastes", mapID = 885, inst = 1220, wx = 4264.20, wy = -852.00, x = 74.0, y = 49.0 },  -- Same portal
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- WRATH OF THE LICH KING (3.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Dalaran Northrend (Both) - Violet Citadel portals /way 29.7 48.8
    -- Verified against PortalHelper data
    {
        name = "Dalaran (Northrend)",
        mapID = 125,
        x = 2970, y = 4880,
        faction = "Both",
        portalsTo = {
            -- Violet Citadel portals
            { name = "Stormwind", mapID = 84, faction = "Alliance", x = 2950, y = 4860 },
            { name = "Orgrimmar", mapID = 85, faction = "Horde", x = 2990, y = 4900 },
            -- Note: Other Northrend zones reached by flying/FP from Dalaran
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- BURNING CRUSADE (2.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Shattrath (Both) - Terrace of Light portals /way 57.0 48.0
    -- Verified against PortalHelper data
    {
        name = "Shattrath",
        mapID = 111,
        x = 5700, y = 4800,
        faction = "Both",
        portalsTo = {
            -- Back to capitals (bidirectional from Stormwind/Orgrimmar)
            { name = "Stormwind", mapID = 84, faction = "Alliance", x = 5680, y = 4780 },
            { name = "Orgrimmar", mapID = 85, faction = "Horde", x = 5720, y = 4820 },
            -- Isle of Quel'Danas (Sunwell patch)
            { name = "Isle of Quel'Danas", mapID = 122, x = 5700, y = 4800 },
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- MISTS OF PANDARIA (5.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Vale of Eternal Blossoms - Shrines /way 84.8 62.8
    -- Verified against PortalHelper data
    {
        name = "Vale of Eternal Blossoms",
        mapID = 390,
        x = 8480, y = 6280,
        faction = "Both",
        portalsTo = {
            -- Shrine of Seven Stars (Alliance) portals
            { name = "Stormwind", mapID = 84, faction = "Alliance", x = 8460, y = 6260 },
            -- Shrine of Two Moons (Horde) portals
            { name = "Orgrimmar", mapID = 85, faction = "Horde", x = 8500, y = 6300 },
            -- Note: Other Pandaria zones reached by flying from shrine
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- WARLORDS OF DRAENOR (6.x) HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Stormshield (Alliance) - Ashran hub /way 36.1 68.4
    -- Verified against PortalHelper data
    {
        name = "Stormshield",
        mapID = 622,
        x = 3610, y = 6840,
        faction = "Alliance",
        portalsTo = {
            -- Back to capital (bidirectional from Stormwind)
            { name = "Stormwind", mapID = 84, x = 3600, y = 6830 },
            -- Note: Draenor zones reached by flying
        }
    },

    -- Warspear (Horde) - Ashran hub /way 45.2 33.8
    -- Verified against PortalHelper data
    {
        name = "Warspear",
        mapID = 624,
        x = 4520, y = 3380,
        faction = "Horde",
        portalsTo = {
            -- Back to capital (bidirectional from Orgrimmar)
            { name = "Orgrimmar", mapID = 85, x = 4510, y = 3370 },
            -- Note: Draenor zones reached by flying
        }
    },

    -- Garrison (Both) - Personal Draenor hub
    {
        name = "Garrison",
        mapID = 579,
        faction = "Both",
        portalsTo = {
            -- No fixed portals - depends on garrison level
        }
    },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- CLASS-SPECIFIC HUBS
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Emerald Dreamway (Druid only) - Access via Dreamwalk spell
    -- This is an instanced area with ONLY portals - you cannot fly from here
    -- Verified against PortalHelper data
    {
        name = "Emerald Dreamway",
        mapID = 715,
        inst = 1540,
        wx = 1580, wy = 1650,  -- Center of Dreamway
        faction = "Both",
        class = "DRUID",
        portalOnly = true,  -- Cannot fly from this location, must use portals
        portalsTo = {
            -- Kalimdor
            { name = "Moonglade", mapID = 80, continent = 12, inst = 1540, wx = 1650.70, wy = 1500.80 },
            { name = "Hyjal", mapID = 198, continent = 12, inst = 1540, wx = 1447.30, wy = 1635.40 },
            { name = "Feralas", mapID = 69, continent = 12, inst = 1540, wx = 1669.00, wy = 1703.80 },
            -- Eastern Kingdoms
            { name = "Duskwood", mapID = 47, continent = 13, inst = 1540, wx = 1549.00, wy = 1552.40 },
            { name = "Hinterlands", mapID = 26, continent = 13, inst = 1540, wx = 1467.40, wy = 1570.30 },
            -- Northrend
            { name = "Grizzly Hills", mapID = 116, continent = 113, inst = 1540, wx = 1608.40, wy = 1764.90 },
            -- Broken Isles
            { name = "Dreamgrove", mapID = 747, continent = 619, inst = 1540, wx = 1504.50, wy = 1779.60 },
            -- Dragon Isles
            { name = "Amirdrassil", mapID = 2239, continent = 1978, inst = 1540, wx = 1702.60, wy = 1601.30 },
        }
    },

    -- Peak of Serenity (Monk only) - Access via Zen Pilgrimage
    {
        name = "Peak of Serenity",
        mapID = 569,
        x = 5000, y = 5000,
        faction = "Both",
        class = "MONK",
        portalsTo = {
            -- Can return to previous location via Zen Pilgrimage: Return
        }
    },
}

-- Static edges are estimates until the player has discovered the route or a
-- live-client check proves its access.  Every edge receives this metadata at
-- load time so UI code cannot silently treat a portal, flight path, or
-- transport as universally available.
TA.TravelData.StaticEdgePolicy = {
    schemaVersion = 1,
    requiredFields = {
        "location", "access", "accessState", "availability", "interaction",
        "actionability", "provenance", "executable", "evidence",
    },
    defaults = {
        location = "source-node",
        access = "conditional",
        accessState = "unknown",
        availability = "discovery-or-unlock-dependent",
        interaction = "player-or-external",
        actionability = "derived-from-access",
        provenance = "in-game:static-topology",
        executable = false,
        evidence = "pending-live",
    },
    categories = {
        ZoneConnections = {
            location = "source-map-key",
            availability = "flightpath-discovery-or-local-access",
            access = "conditional", accessState = "unknown",
            interaction = "flightpath-or-local-movement",
            actionability = "derived-from-access", executable = false,
            evidence = "pending-live",
            provenance = "in-game:flight-master-and-zone-transition inspection",
            source = "in-game:flight-master-and-zone-transition inspection",
        },
        PortalHubs = {
            location = "hub-map-key",
            availability = "hub-location-faction-or-unlock-dependent",
            access = "conditional", accessState = "unknown",
            interaction = "portal-room", actionability = "derived-from-access",
            executable = false, evidence = "pending-live",
            provenance = "in-game:portal-room inspection",
            source = "in-game:portal-room inspection",
        },
        Transports = {
            location = "transport-origin-and-destination",
            status = "informational-only",
            availability = "schedule-and-location-dependent",
            access = "conditional", accessState = "unknown",
            interaction = "transport", actionability = "informational-only",
            executable = false, evidence = "pending-live",
            provenance = "not-modeled-until-authoritative-schedule-data-exists",
            source = "not-modeled-until-authoritative-schedule-data-exists",
        },
    },
}

local function applyStaticEdgeMetadata(edge, location, category)
    if type(edge) ~= "table" then return end
    local defaults = TA.TravelData.StaticEdgePolicy.defaults
    local categoryPolicy = TA.TravelData.StaticEdgePolicy.categories[category] or {}
    edge.location = edge.location or location
    edge.access = edge.access or categoryPolicy.access or defaults.access
    edge.accessState = edge.accessState or categoryPolicy.accessState or defaults.accessState
    edge.availability = edge.availability or categoryPolicy.availability or defaults.availability
    edge.interaction = edge.interaction or categoryPolicy.interaction or defaults.interaction
    edge.actionability = edge.actionability or categoryPolicy.actionability or defaults.actionability
    edge.provenance = edge.provenance or categoryPolicy.provenance or categoryPolicy.source or defaults.provenance
    edge.executable = edge.executable == true and categoryPolicy.executable ~= false
    edge.evidence = edge.evidence or categoryPolicy.evidence or defaults.evidence
    edge.requirements = edge.requirements or {}
end

for fromMapID, connections in pairs(TA.TravelData.ZoneConnections or {}) do
    for index, connection in ipairs(connections or {}) do
        applyStaticEdgeMetadata(connection, "map:" .. tostring(fromMapID), "ZoneConnections")
        connection.edgeKey = connection.edgeKey or ("zone:" .. tostring(fromMapID) .. ":" .. tostring(index))
    end
end

for _, hub in ipairs(TA.TravelData.PortalHubs or {}) do
    for index, portal in ipairs(hub.portalsTo or {}) do
        applyStaticEdgeMetadata(portal, "hub:" .. tostring(hub.mapID), "PortalHubs")
        portal.edgeKey = portal.edgeKey or ("portal:" .. tostring(hub.mapID) .. ":" .. tostring(index))
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PORTAL-ONLY ZONES
-- Zones that can only be reached via portal/teleport (no flying allowed)
-- These are ISOLATED instances - not connected to the open world flight network
-- Note: Cross-expansion travel is already blocked by continent checks
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.PortalOnlyZones = {
    -- The War Within (11.x) - Underground zones accessed via Earthen portal network
    2371,   -- K'aresh (portal from Dornogal)
    2346,   -- Undermine (separate island, portal from Dornogal only)
    2472,   -- Tazavesh (dungeon hub)
    
    -- Dragonflight (10.x)
    2200,   -- Emerald Dream / Central Encampment (portal from Valdrakken)
    
    -- Shadowlands (9.x) - isolated sub-zones
    1543,   -- The Maw (portal from Oribos, no flying allowed there anyway)
    1961,   -- Korthia (portal from Oribos)
    1970,   -- Zereth Mortis (portal from Oribos)
    
    -- Battle for Azeroth (8.x) - patch zones not connected to main continents
    1355,   -- Nazjatar (underwater zone, portal from Boralus/Dazar'alor)
    
    -- Mists of Pandaria (5.x)
    504,    -- Isle of Thunder (portal from Townlong Steppes)
    
    -- Legion (7.x) - Argus is completely separate
    905,    -- Argus (continent)
    832,    -- Vindicaar (spaceship)
    830,    -- Krokuun (Argus)
    831,    -- Vindicaar surface
    882,    -- Mac'Aree (Argus)
    885,    -- Antoran Wastes (Argus)
    
    -- Legion Class Halls (instanced, not in open world)
    717,    -- Dreadscar Rift (Warlock)
    720,    -- Fel Hammer (Demon Hunter)
    702,    -- Netherlight Temple (Priest)
    734,    -- Hall of the Guardian (Mage)
    739,    -- Trueshot Lodge (Hunter)
    715,    -- Emerald Dreamway (Druid)
    24,     -- Sanctum of Light (Paladin) - under Light's Hope Chapel
    
    -- Burning Crusade (2.x)
    122,    -- Isle of Quel'Danas (portal from Shattrath)
    
    -- Dungeons/Raids that appear as zones
    2266,   -- Millennia's Threshold (mythic portal hub)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ZONE UNLOCK REQUIREMENTS
-- Zones that require quest completion or other prerequisites to access
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.ZoneUnlockQuests = {
    -- Shadowlands (9.x)
    [1961] = { quest = 63727, name = "Korthia" },          -- Korthia: "Korthia Calls" quest
    [1970] = { quest = 64556, name = "Zereth Mortis" },    -- Zereth Mortis: "Call of the Primus"
    
    -- Dragonflight (10.x)
    [2200] = { quest = 76317, name = "Emerald Dream" },    -- Emerald Dream: "A Gathering of Dreamers"
    [2133] = { quest = 74378, name = "Zaralek Cavern" },   -- Zaralek Cavern: "The Land Beneath"
    [2151] = { quest = 73159, name = "Forbidden Reach" },  -- Forbidden Reach
    
    -- The War Within (11.x)
    [2371] = { quest = 79174, name = "K'aresh" },          -- K'aresh portal unlock
    [2369] = { quest = 83760, name = "Siren Isle" },       -- Siren Isle
    
    -- Legion (7.x) - Argus
    [830] = { quest = 47222, name = "Krokuun" },           -- Argus: "The Hand of Fate"
    [882] = { quest = 47473, name = "Mac'Aree" },          -- Mac'Aree unlock
    [885] = { quest = 47654, name = "Antoran Wastes" },    -- Antoran Wastes unlock
    
    -- BfA (8.x)
    [1355] = { quest = 54972, name = "Nazjatar" },         -- Nazjatar: "The Wolf's Offensive" / "The Warchief's Order"
    [1462] = { quest = 55374, name = "Mechagon" },         -- Mechagon: "The Mechagonian Threat"
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTINENT TO ZONE MAPPINGS
-- Which zones belong to which continent
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.ContinentZones = {
    -- Eastern Kingdoms
    [13] = {
        -- Cities
        84, 87, 90, 110,  -- Stormwind, Ironforge, Undercity, Silvermoon
        -- Zones
        14, 15, 17, 18, 21, 22, 23, 26, 27, 32, 36, 37, 47, 48, 49, 51, 52, 56, 
        -- 14=Arathi, 15=Badlands, 17=Blasted, 18=Tirisfal, 21=Silverpine, 22=WPL, 23=EPL, 26=Hinterlands
        -- 27=Dun Morogh, 32=Searing, 36=Burning, 37=Elwynn, 47=Duskwood, 48=Loch, 49=Redridge, 51=Swamp, 52=Westfall, 56=Wetlands
        210, 241, 245,  -- Stranglethorn, Twilight Highlands, Tol Barad
    },

    -- Kalimdor
    [12] = {
        -- Cities
        85, 88, 89, 103,  -- Orgrimmar, Thunder Bluff, Darnassus, Exodar
        -- Zones
        1, 7, 10, 57, 62, 63, 64, 65, 66, 69, 70, 71, 76, 77, 78, 80, 81, 83,
        -- 1=Durotar, 7=Mulgore, 10=Barrens, 57=Teldrassil, 62=Darkshore, 63=Ashenvale, 64=Thousand Needles
        -- 65=Stonetalon, 66=Desolace, 69=Feralas, 70=Dustwallow, 71=Tanaris, 76=Azshara, 77=Felwood
        -- 78=Un'Goro, 80=Moonglade, 81=Silithus, 83=Winterspring
        198, 249,  -- Hyjal, Uldum (Cata zones in Kalimdor)
    },

    -- Outland
    [101] = {
        100, 102, 104, 105, 107, 108, 109, 111, 122,
        -- 100=Hellfire, 102=Zangarmarsh, 104=Shadowmoon, 105=Blade's Edge, 107=Nagrand
        -- 108=Terokkar, 109=Netherstorm, 111=Shattrath, 122=Isle of Quel'Danas
    },

    -- Northrend
    [113] = {
        114, 115, 116, 117, 118, 119, 120, 121, 123, 125,
        -- 114=Borean, 115=Dragonblight, 116=Grizzly, 117=Howling, 118=Icecrown, 119=Sholazar
        -- 120=Storm Peaks, 121=Zul'Drak, 123=Wintergrasp, 125=Dalaran
    },

    -- Cataclysm zones (special - floating/phased)
    [0] = {
        207, 203,  -- Deepholm, Vashj'ir (these are instanced/phased)
    },

    -- Pandaria
    [424] = {
        371, 376, 379, 388, 390, 391, 393, 422, 504, 554,
        -- 371=Jade Forest, 376=Valley, 379=Kun-Lai, 388=Townlong, 390=Vale, 391=Shrine Horde, 393=Shrine Alli
        -- 422=Dread Wastes, 504=Isle of Thunder, 554=Timeless Isle
    },

    -- Draenor
    [572] = {
        525, 534, 535, 539, 542, 543, 550, 579, 622, 624,
        -- 525=Frostfire, 534=Tanaan, 535=Talador, 539=Shadowmoon, 542=Spires, 543=Gorgrond
        -- 550=Nagrand, 579=Garrison, 622=Stormshield, 624=Warspear
    },

    -- Broken Isles
    [619] = {
        627, 630, 634, 641, 646, 650, 680, 715, 717, 720, 739, 747,
        -- 627=Dalaran, 630=Azsuna, 634=Stormheim, 641=Val'sharah, 646=Broken Shore
        -- 650=Highmountain, 680=Suramar, 715=Dreamway, 717=Dreadscar, 720=Fel Hammer, 739=Trueshot, 747=Dreamgrove
    },

    -- Argus
    [905] = {
        830, 831, 882, 885,  -- Krokuun, Mac'Aree, Antoran Wastes, Seat of the Triumvirate
    },

    -- Zandalar
    [875] = {
        862, 863, 864, 1165,  -- Zuldazar, Nazmir, Vol'dun, Dazar'alor
    },

    -- Kul Tiras
    [876] = {
        895, 896, 942, 1161, 1462,  -- Tiragarde, Drustvar, Stormsong, Boralus, Mechagon
    },

    -- Nazjatar (BfA)
    [1355] = {
        1355,  -- Nazjatar itself
    },

    -- Shadowlands
    [1550] = {
        1525, 1533, 1536, 1543, 1565, 1670, 1961, 1970,
        -- 1525=Revendreth, 1533=Bastion, 1536=Maldraxxus, 1543=The Maw, 1565=Ardenweald
        -- 1670=Oribos, 1961=Korthia, 1970=Zereth Mortis
    },

    -- Dragon Isles
    [1978] = {
        2022, 2023, 2024, 2025, 2112, 2133, 2151, 2200,
        -- 2022=Waking Shores, 2023=Ohn'ahran, 2024=Azure Span, 2025=Thaldraszus
        -- 2112=Valdrakken, 2133=Zaralek, 2151=Forbidden Reach, 2200=Emerald Dream
    },

    -- Khaz Algar (The War Within)
    [2274] = {
        2248, 2214, 2215, 2255, 2216, 2339, 2346, 2371, 2369,
        -- 2248=Isle of Dorn, 2214=Ringing Deeps, 2215=Hallowfall, 2255=Azj-Kahet, 2216=Ara-Kara, 2339=Dornogal, 2346=Undermine, 2371=K'aresh, 2369=Siren Isle
    },

    -- Mechagon (BfA)
    [1462] = {
        1462,
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTINENT ROUTES - Pre-defined routes to reach every continent from capitals
-- Each continent has: hub (main city), hubMapID, portalFromCapital (true if capital has direct portal)
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.ContinentRoutes = {
    -- Eastern Kingdoms
    [13] = {
        hub = "Stormwind",
        hubMapID = 84,
        hubHorde = "Undercity",
        hubMapIDHorde = 90,
        portalFromCapital = true,  -- Capital IS on this continent or has direct teleport
        description = "Your home continent",
    },
    -- Kalimdor
    [12] = {
        hub = "Orgrimmar",
        hubMapID = 85,
        hubAlliance = "Darnassus",
        hubMapIDAlliance = 89,
        portalFromCapital = true,  -- Capital IS on this continent or has direct teleport
        description = "Your home continent",
    },
    -- Outland
    [101] = {
        hub = "Shattrath",
        hubMapID = 111,
        portalFromCapital = true,  -- Portal from SW/Org to Hellfire Peninsula or Shattrath
        capitalPortal = "Hellfire Peninsula",
        capitalPortalMapID = 100,
        description = "Take portal to Hellfire Peninsula or Shattrath",
    },
    -- Northrend
    [113] = {
        hub = "Dalaran (Northrend)",
        hubMapID = 125,
        portalFromCapital = true,  -- Portal from SW/Org to Dalaran
        description = "Take portal to Dalaran (Northrend)",
    },
    -- Pandaria
    [424] = {
        hub = "Vale of Eternal Blossoms",
        hubMapID = 390,
        portalFromCapital = true,  -- Portal to Jade Forest exists
        capitalPortal = "Jade Forest",
        capitalPortalMapID = 371,
        description = "Take portal to Jade Forest, then fly",
    },
    -- Draenor
    [572] = {
        hub = "Warspear",
        hubMapID = 624,
        hubAlliance = "Stormshield",
        hubMapIDAlliance = 622,
        portalFromCapital = true,
        capitalPortal = "Warspear",  -- Horde goes to Warspear
        capitalPortalAlliance = "Stormshield",  -- Alliance goes to Stormshield
        capitalPortalMapID = 624,
        capitalPortalMapIDAlliance = 622,
        description = "Take portal to Stormshield/Warspear",
    },
    -- Broken Isles (Legion)
    [619] = {
        hub = "Dalaran (Legion)",
        hubMapID = 627,
        portalFromCapital = true,
        capitalPortal = "Azsuna",  -- Portal room goes to Azsuna, then fly to Dalaran
        capitalPortalMapID = 630,
        description = "Take portal to Azsuna, then fly/portal to destination",
    },
    -- Argus
    [905] = {
        hub = "Dalaran (Legion)",
        hubMapID = 627,
        portalFromCapital = true,
        requiresQuest = true,  -- Need Argus unlock
        description = "Take portal to Dalaran (Legion), then use Vindicaar",
    },
    -- Zandalar
    [875] = {
        hub = "Dazar'alor",
        hubMapID = 1165,
        hubAlliance = "Boralus",
        hubMapIDAlliance = 1161,
        portalFromCapital = true,
        description = "Take portal to Dazar'alor/Boralus",
    },
    -- Kul Tiras
    [876] = {
        hub = "Boralus",
        hubMapID = 1161,
        hubHorde = "Dazar'alor",
        hubMapIDHorde = 1165,
        portalFromCapital = true,
        description = "Take portal to Boralus/Dazar'alor",
    },
    -- Nazjatar
    [1355] = {
        hub = "Boralus",
        hubMapID = 1161,
        hubHorde = "Dazar'alor",
        hubMapIDHorde = 1165,
        portalFromCapital = true,
        requiresQuest = true,  -- Need Nazjatar unlock
        description = "Take portal to Boralus/Dazar'alor, then Nazjatar portal",
    },
    -- Mechagon
    [1462] = {
        hub = "Boralus",
        hubMapID = 1161,
        hubHorde = "Dazar'alor",
        hubMapIDHorde = 1165,
        portalFromCapital = true,
        description = "Take portal to Boralus/Dazar'alor, then fly to Mechagon",
    },
    -- Shadowlands continent
    [1550] = {
        hub = "Oribos",
        hubMapID = 1670,
        portalFromCapital = true,
        description = "Take portal to Oribos",
    },
    -- Shadowlands portal-only zones
    [1543] = {  -- The Maw
        hub = "Oribos",
        hubMapID = 1670,
        portalFromCapital = true,
        description = "Take portal to Oribos, then portal to The Maw",
    },
    [1961] = {  -- Korthia
        hub = "Oribos",
        hubMapID = 1670,
        portalFromCapital = true,
        description = "Take portal to Oribos, then portal to Korthia",
    },
    [1970] = {  -- Zereth Mortis
        hub = "Oribos",
        hubMapID = 1670,
        portalFromCapital = true,
        description = "Take portal to Oribos, then portal to Zereth Mortis",
    },
    -- Dragon Isles continent
    [1978] = {
        hub = "Valdrakken",
        hubMapID = 2112,
        portalFromCapital = true,
        description = "Take portal to Valdrakken",
    },
    -- Dragon Isles portal-only zones
    [2200] = {  -- Emerald Dream
        hub = "Valdrakken",
        hubMapID = 2112,
        portalFromCapital = true,
        description = "Take portal to Valdrakken, then portal to Emerald Dream",
    },
    -- Khaz Algar (The War Within)
    [2274] = {
        hub = "Dornogal",
        hubMapID = 2339,
        portalFromCapital = true,
        description = "Take portal to Dornogal",
    },
    -- Cataclysm zones (special phased zones)
    [0] = {
        hub = "Stormwind",
        hubMapID = 84,
        hubHorde = "Orgrimmar",
        hubMapIDHorde = 85,
        portalFromCapital = true,
        specialZones = {
            [207] = { name = "Deepholm", portalFrom = "capital" },  -- Deepholm portal in capital
            [203] = { name = "Vashj'ir", description = "Take boat from SW or teleport" },
            [198] = { name = "Hyjal", description = "Portal from capital or fly from Moonglade" },
            [249] = { name = "Uldum", description = "Fly from Tanaris or portal if available" },
            [245] = { name = "Tol Barad", description = "Portal from capital (PvP)" },
            [241] = { name = "Twilight Highlands", description = "Fly from Wetlands/Arathi" },
        },
        description = "Various routes depending on zone",
    },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ZONE COORDINATES - Approximate centers for display and conservative fallback
-- Values are relative positions on continent map (0-100 scale)
-- They are not used to invent direct flight edges or exact flight durations.
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.ZoneCoordinates = {
    -- Eastern Kingdoms (continent 13)
    [84] = { x = 45, y = 65, continent = 13 },   -- Stormwind
    [87] = { x = 45, y = 45, continent = 13 },   -- Ironforge
    [90] = { x = 55, y = 25, continent = 13 },   -- Undercity
    [110] = { x = 65, y = 15, continent = 13 },  -- Silvermoon
    [37] = { x = 30, y = 90, continent = 13 },   -- Northern Stranglethorn
    [210] = { x = 28, y = 95, continent = 13 },  -- Cape of Stranglethorn
    [47] = { x = 45, y = 75, continent = 13 },   -- Duskwood; map 47 is not Booty Bay
    [17] = { x = 45, y = 55, continent = 13 },   -- Badlands
    [51] = { x = 50, y = 70, continent = 13 },   -- Swamp of Sorrows
    [241] = { x = 70, y = 30, continent = 13 },  -- Twilight Highlands
    [36] = { x = 55, y = 40, continent = 13 },   -- Burning Steppes
    [32] = { x = 50, y = 50, continent = 13 },   -- Searing Gorge
    [26] = { x = 45, y = 50, continent = 13 },   -- Loch Modan
    [27] = { x = 50, y = 55, continent = 13 },   -- Dun Morogh
    [49] = { x = 40, y = 40, continent = 13 },   -- Western Plaguelands
    [50] = { x = 50, y = 35, continent = 13 },   -- Eastern Plaguelands
    [23] = { x = 55, y = 20, continent = 13 },   -- Ghostlands
    [21] = { x = 60, y = 10, continent = 13 },   -- Eversong Woods
    [14] = { x = 40, y = 60, continent = 13 },   -- Elwynn Forest
    [52] = { x = 45, y = 75, continent = 13 },   -- Westfall
    [56] = { x = 50, y = 65, continent = 13 },   -- Wetlands
    [25] = { x = 45, y = 35, continent = 13 },   -- Hillsbrad Foothills
    [22] = { x = 50, y = 30, continent = 13 },   -- Silverpine Forest
    
    -- Kalimdor (continent 12)
    [85] = { x = 55, y = 30, continent = 12 },   -- Orgrimmar
    [88] = { x = 40, y = 45, continent = 12 },   -- Thunder Bluff
    [89] = { x = 30, y = 15, continent = 12 },   -- Darnassus
    [80] = { x = 45, y = 20, continent = 12 },   -- Moonglade
    [57] = { x = 35, y = 10, continent = 12 },   -- Teldrassil
    [62] = { x = 25, y = 25, continent = 12 },   -- Darkshore
    [63] = { x = 30, y = 35, continent = 12 },   -- Ashenvale
    [65] = { x = 55, y = 35, continent = 12 },   -- Azshara
    [66] = { x = 40, y = 40, continent = 12 },   -- Stonetalon Mountains
    [69] = { x = 35, y = 45, continent = 12 },   -- Feralas
    [70] = { x = 35, y = 55, continent = 12 },   -- Dustwallow Marsh
    [199] = { x = 45, y = 50, continent = 12 },  -- Southern Barrens
    [10] = { x = 45, y = 40, continent = 12 },   -- Northern Barrens
    [71] = { x = 50, y = 75, continent = 12 },   -- Tanaris
    [249] = { x = 55, y = 85, continent = 12 },  -- Uldum (south of Tanaris)
    [81] = { x = 45, y = 70, continent = 12 },   -- Silithus
    [78] = { x = 40, y = 65, continent = 12 },   -- Un'Goro Crater
    [64] = { x = 55, y = 55, continent = 12 },   -- Thousand Needles
    [61] = { x = 45, y = 45, continent = 12 },   -- Mulgore
    [11] = { x = 50, y = 40, continent = 12 },   -- Durotar
    
    -- Outland (continent 101)
    [111] = { x = 50, y = 50, continent = 101 }, -- Shattrath
    [100] = { x = 40, y = 45, continent = 101 }, -- Hellfire Peninsula
    [102] = { x = 30, y = 50, continent = 101 }, -- Zangarmarsh
    [104] = { x = 55, y = 30, continent = 101 }, -- Shadowmoon Valley
    [105] = { x = 25, y = 30, continent = 101 }, -- Blade's Edge Mountains
    [107] = { x = 50, y = 55, continent = 101 }, -- Nagrand
    [108] = { x = 55, y = 45, continent = 101 }, -- Terokkar Forest
    [109] = { x = 70, y = 25, continent = 101 }, -- Netherstorm
    
    -- Northrend (continent 113)
    [125] = { x = 50, y = 35, continent = 113 }, -- Dalaran
    [114] = { x = 25, y = 60, continent = 113 }, -- Borean Tundra
    [115] = { x = 50, y = 50, continent = 113 }, -- Dragonblight
    [116] = { x = 30, y = 40, continent = 113 }, -- Grizzly Hills
    [117] = { x = 75, y = 60, continent = 113 }, -- Howling Fjord
    [118] = { x = 55, y = 25, continent = 113 }, -- Icecrown
    [119] = { x = 40, y = 35, continent = 113 }, -- Sholazar Basin
    [120] = { x = 60, y = 25, continent = 113 }, -- Storm Peaks
    [121] = { x = 25, y = 35, continent = 113 }, -- Zul'Drak
    [123] = { x = 55, y = 50, continent = 113 }, -- Wintergrasp
    
    -- Pandaria (continent 424)
    [371] = { x = 55, y = 50, continent = 424 }, -- Jade Forest
    [376] = { x = 50, y = 40, continent = 424 }, -- Valley of the Four Winds
    [379] = { x = 45, y = 30, continent = 424 }, -- Kun-Lai Summit
    [388] = { x = 35, y = 25, continent = 424 }, -- Townlong Steppes
    [390] = { x = 55, y = 35, continent = 424 }, -- Vale of Eternal Blossoms
    [422] = { x = 25, y = 30, continent = 424 }, -- Dread Wastes
    [418] = { x = 45, y = 55, continent = 424 }, -- Krasarang Wilds
    
    -- Draenor (continent 572)
    [588] = { x = 50, y = 50, continent = 572 }, -- Ashran
    [525] = { x = 45, y = 55, continent = 572 }, -- Frostfire Ridge
    [535] = { x = 55, y = 50, continent = 572 }, -- Talador
    [539] = { x = 50, y = 35, continent = 572 }, -- Shadowmoon Valley (Draenor)
    [542] = { x = 35, y = 45, continent = 572 }, -- Spires of Arak
    [543] = { x = 35, y = 60, continent = 572 }, -- Gorgrond
    [550] = { x = 60, y = 45, continent = 572 }, -- Nagrand (Draenor)
    [622] = { x = 30, y = 30, continent = 572 }, -- Stormshield
    [624] = { x = 65, y = 50, continent = 572 }, -- Warspear
    
    -- Broken Isles (continent 619)
    [627] = { x = 50, y = 50, continent = 619 }, -- Dalaran (Legion)
    [630] = { x = 45, y = 65, continent = 619 }, -- Azsuna
    [634] = { x = 70, y = 50, continent = 619 }, -- Stormheim
    [641] = { x = 40, y = 45, continent = 619 }, -- Val'sharah
    [650] = { x = 55, y = 35, continent = 619 }, -- Highmountain
    [680] = { x = 35, y = 55, continent = 619 }, -- Suramar
    [646] = { x = 50, y = 75, continent = 619 }, -- Broken Shore
    [747] = { x = 35, y = 40, continent = 619 }, -- Dreamgrove
    
    -- Kul Tiras / Zandalar (BfA)
    [1161] = { x = 70, y = 25, continent = 876 }, -- Boralus
    [895] = { x = 65, y = 40, continent = 876 },  -- Tiragarde Sound
    [896] = { x = 35, y = 50, continent = 876 },  -- Drustvar
    [942] = { x = 50, y = 30, continent = 876 },  -- Stormsong Valley
    [1462] = { x = 75, y = 20, continent = 876 }, -- Mechagon
    [1165] = { x = 45, y = 25, continent = 875 }, -- Dazar'alor
    [862] = { x = 50, y = 35, continent = 875 },  -- Zuldazar
    [863] = { x = 40, y = 55, continent = 875 },  -- Nazmir
    [864] = { x = 65, y = 50, continent = 875 },  -- Vol'dun
    
    -- Shadowlands
    [1670] = { x = 50, y = 50, continent = 1550 }, -- Oribos
    [1533] = { x = 30, y = 25, continent = 1550 }, -- Bastion
    [1536] = { x = 70, y = 35, continent = 1550 }, -- Maldraxxus
    [1565] = { x = 35, y = 65, continent = 1550 }, -- Ardenweald
    [1525] = { x = 65, y = 70, continent = 1550 }, -- Revendreth
    [2472] = { x = 50, y = 15, continent = 1550 }, -- Tazavesh (broker dimension)
    
    -- Dragon Isles
    [2112] = { x = 55, y = 35, continent = 1978 }, -- Valdrakken
    [2022] = { x = 70, y = 70, continent = 1978 }, -- Waking Shores
    [2023] = { x = 50, y = 55, continent = 1978 }, -- Ohn'ahran Plains
    [2024] = { x = 35, y = 45, continent = 1978 }, -- Azure Span
    [2025] = { x = 55, y = 30, continent = 1978 }, -- Thaldraszus
    [2133] = { x = 45, y = 60, continent = 1978 }, -- Zaralek Cavern
    [2200] = { x = 50, y = 50, continent = 2200 }, -- Emerald Dream
    
    -- Khaz Algar (The War Within)
    [2339] = { x = 50, y = 30, continent = 2274 }, -- Dornogal
    [2248] = { x = 45, y = 45, continent = 2274 }, -- Isle of Dorn
    [2214] = { x = 55, y = 55, continent = 2274 }, -- The Ringing Deeps
    [2215] = { x = 40, y = 65, continent = 2274 }, -- Hallowfall
    [2255] = { x = 55, y = 70, continent = 2274 }, -- Azj-Kahet / City of Threads
    [2216] = { x = 60, y = 75, continent = 2274 }, -- Ara-Kara (dungeon area)
    [2371] = { x = 50, y = 50, continent = 2371 }, -- K'aresh (portal only)
    [2346] = { x = 50, y = 50, continent = 2346 }, -- Undermine
    [2369] = { x = 45, y = 40, continent = 2274 }, -- Siren Isle
    
    -- Argus (Legion)
    [882] = { x = 50, y = 50, continent = 905 },   -- Mac'Aree
    [830] = { x = 40, y = 60, continent = 905 },   -- Krokuun
    [885] = { x = 60, y = 40, continent = 905 },   -- Antoran Wastes
    
    -- Midnight (Season 3 zones)
    [2501] = { x = 50, y = 50, continent = 2501 }, -- Mechagon City (Midnight)
    [2556] = { x = 50, y = 50, continent = 2556 }, -- Nightfall Priory
    [2511] = { x = 50, y = 50, continent = 2511 }, -- The Murkmire
    [2494] = { x = 50, y = 50, continent = 2494 }, -- Warrens
    
    -- Cataclysm zones (various, use portal destinations)
    [207] = { x = 50, y = 50, continent = 207 },  -- Deepholm (own instance)
    [198] = { x = 45, y = 20, continent = 12 },   -- Hyjal (Kalimdor, north)
    [203] = { x = 80, y = 50, continent = 13 },   -- Vashj'ir (off EK coast)
    [245] = { x = 75, y = 40, continent = 13 },   -- Tol Barad (island off EK)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ZONE NAME TO MAP ID LOOKUP
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.ZoneNameToID = {
    -- Major Cities
    ["stormwind"] = 84,
    ["stormwind city"] = 84,
    ["orgrimmar"] = 85,
    ["org"] = 85,
    ["ironforge"] = 87,
    ["if"] = 87,
    ["thunder bluff"] = 88,
    ["tb"] = 88,
    ["darnassus"] = 89,
    ["undercity"] = 90,
    ["uc"] = 90,
    ["exodar"] = 103,
    ["silvermoon"] = 110,
    ["silvermoon city"] = 110,
    ["shattrath"] = 111,
    ["dalaran"] = 627,
    ["dalaran northrend"] = 125,
    ["dalaran broken isles"] = 627,
    ["dalaran legion"] = 627,
    ["boralus"] = 1161,
    ["dazar'alor"] = 1165,
    ["dazaralor"] = 1165,
    ["oribos"] = 1670,
    ["valdrakken"] = 2112,
    ["dornogal"] = 2339,
    ["undermine"] = 2346,
    ["undermine city"] = 2346,

    -- Continents
    ["eastern kingdoms"] = 13,
    ["ek"] = 13,
    ["kalimdor"] = 12,
    ["outland"] = 101,
    ["northrend"] = 113,
    ["pandaria"] = 424,
    ["draenor"] = 572,
    ["broken isles"] = 619,
    ["broken shore"] = 646,
    ["zandalar"] = 875,
    ["kul tiras"] = 876,
    ["shadowlands"] = 1550,
    ["dragon isles"] = 1978,
    ["khaz algar"] = 2274,

    -- Popular zones
    ["moonglade"] = 80,
    ["ashran"] = 588,
    ["duskwood"] = 47,
    ["booty bay"] = 210,
    ["tanaris"] = 71,
    ["gadgetzan"] = 71,
    ["winterspring"] = 83,
    ["everlook"] = 83,
    ["timeless isle"] = 554,
    ["argent tournament"] = 118,
    ["icecrown"] = 118,
    ["mechagon"] = 1462,
    ["nazjatar"] = 1355,
    ["zereth mortis"] = 1970,
    ["zaralek cavern"] = 2133,
    ["emerald dream"] = 2200,
    ["forbidden reach"] = 2151,
    
    -- Khaz Algar zones (TWW)
    ["isle of dorn"] = 2248,
    ["ka'resh"] = 2248,
    ["karesh"] = 2371,
    ["k'aresh"] = 2371,
    ["the ringing deeps"] = 2214,
    ["ringing deeps"] = 2214,
    ["hallowfall"] = 2215,
    ["azj-kahet"] = 2255,
    ["city of threads"] = 2255,
    ["azjkahet"] = 2216,
    
    -- Dragon Isles zones
    ["waking shores"] = 2022,
    ["the waking shores"] = 2022,
    ["ohn'ahran plains"] = 2023,
    ["ohnahran plains"] = 2023,
    ["azure span"] = 2024,
    ["the azure span"] = 2024,
    ["thaldraszus"] = 2025,
    
    -- Shadowlands zones
    ["bastion"] = 1533,
    ["maldraxxus"] = 1536,
    ["ardenweald"] = 1565,
    ["revendreth"] = 1525,
    ["the maw"] = 1543,
    ["korthia"] = 1961,
    
    -- BfA zones
    ["tiragarde sound"] = 895,
    ["tiragarde"] = 895,
    ["drustvar"] = 896,
    ["stormsong valley"] = 942,
    ["stormsong"] = 942,
    ["zuldazar"] = 862,
    ["nazmir"] = 863,
    ["vol'dun"] = 864,
    ["voldun"] = 864,
    
    -- Broken Isles zones
    ["azsuna"] = 630,
    ["val'sharah"] = 641,
    ["valsharah"] = 641,
    ["highmountain"] = 650,
    ["stormheim"] = 634,
    ["suramar"] = 680,
    ["broken shore"] = 646,
}

-- Normalized lookup is built by LibZoneNameToMap when RegisterData(ZoneNameToID) is called.

-- ═══════════════════════════════════════════════════════════════════════════
-- HIERARCHICAL ZONE BROWSER (for UI tree view)
-- ═══════════════════════════════════════════════════════════════════════════
TA.TravelData.ZoneTree = {
    {
        name = "The War Within",
        icon = "Interface\\Icons\\Inv_misc_head_nerubian_01",
        children = {
            { name = "Khaz Algar", mapID = 2274, isContinent = true, children = {
                { name = "Dornogal", mapID = 2339, isCity = true },
                { name = "Isle of Dorn", mapID = 2248 },
                { name = "K'aresh", mapID = 2371 },  -- Portal destination from Dornogal
                { name = "The Ringing Deeps", mapID = 2214 },
                { name = "Hallowfall", mapID = 2215 },
                { name = "Azj-Kahet", mapID = 2255 },
            }},
            { name = "Undermine", mapID = 2346, isCity = true, children = {
                { name = "Undermine City", mapID = 2346 },
            }},
        }
    },
    {
        name = "Dragonflight",
        icon = "Interface\\Icons\\Inv_icon_wing06a",
        children = {
            { name = "Dragon Isles", mapID = 1978, isContinent = true, children = {
                { name = "Valdrakken", mapID = 2112, isCity = true },
                { name = "The Waking Shores", mapID = 2022 },
                { name = "Ohn'ahran Plains", mapID = 2023 },
                { name = "The Azure Span", mapID = 2024 },
                { name = "Thaldraszus", mapID = 2025 },
                { name = "Zaralek Cavern", mapID = 2133 },
                { name = "Emerald Dream", mapID = 2200 },
                { name = "The Forbidden Reach", mapID = 2151 },
            }},
        }
    },
    {
        name = "Shadowlands",
        icon = "Interface\\Icons\\Achievement_zone_revendreth_01",
        children = {
            { name = "Shadowlands", mapID = 1550, isContinent = true, children = {
                { name = "Oribos", mapID = 1670, isCity = true },
                { name = "Bastion", mapID = 1533 },
                { name = "Maldraxxus", mapID = 1536 },
                { name = "Ardenweald", mapID = 1565 },
                { name = "Revendreth", mapID = 1525 },
                { name = "The Maw", mapID = 1543 },
                { name = "Korthia", mapID = 1961 },
                { name = "Zereth Mortis", mapID = 1970 },
            }},
        }
    },
    {
        name = "Battle for Azeroth",
        icon = "Interface\\Icons\\Achievement_zone_tiaboreas_01",
        children = {
            { name = "Kul Tiras", mapID = 876, isContinent = true, children = {
                { name = "Boralus", mapID = 1161, isCity = true },
                { name = "Tiragarde Sound", mapID = 895 },
                { name = "Drustvar", mapID = 896 },
                { name = "Stormsong Valley", mapID = 942 },
                { name = "Mechagon", mapID = 1462 },
            }},
            { name = "Zandalar", mapID = 875, isContinent = true, children = {
                { name = "Dazar'alor", mapID = 1165, isCity = true },
                { name = "Zuldazar", mapID = 862 },
                { name = "Nazmir", mapID = 863 },
                { name = "Vol'dun", mapID = 864 },
            }},
            { name = "Nazjatar", mapID = 1355 },
        }
    },
    {
        name = "Legion",
        icon = "Interface\\Icons\\Achievement_zone_brokenshore",
        children = {
            { name = "Broken Isles", mapID = 619, isContinent = true, children = {
                { name = "Dalaran (Legion)", mapID = 627, isCity = true },
                { name = "Azsuna", mapID = 630 },
                { name = "Val'sharah", mapID = 641 },
                { name = "Highmountain", mapID = 650 },
                { name = "Stormheim", mapID = 634 },
                { name = "Suramar", mapID = 680 },
                { name = "Broken Shore", mapID = 646 },
            }},
            { name = "Argus", mapID = 905 },
        }
    },
    {
        name = "Warlords of Draenor",
        icon = "Interface\\Icons\\Achievement_zone_frostfire",
        children = {
            { name = "Draenor", mapID = 572, isContinent = true, children = {
                { name = "Warspear", mapID = 624, isCity = true, faction = "Horde" },
                { name = "Stormshield", mapID = 622, isCity = true, faction = "Alliance" },
                { name = "Frostfire Ridge", mapID = 525 },
                { name = "Gorgrond", mapID = 543 },
                { name = "Talador", mapID = 535 },
                { name = "Spires of Arak", mapID = 542 },
                { name = "Nagrand (Draenor)", mapID = 550 },
                { name = "Shadowmoon Valley (Draenor)", mapID = 539 },
                { name = "Tanaan Jungle", mapID = 534 },
            }},
            { name = "Garrison", mapID = 579 },
        }
    },
    {
        name = "Mists of Pandaria",
        icon = "Interface\\Icons\\Achievement_zone_jadeforest",
        children = {
            { name = "Pandaria", mapID = 424, isContinent = true, children = {
                { name = "Shrine (Alliance)", mapID = 393, isCity = true, faction = "Alliance" },
                { name = "Shrine (Horde)", mapID = 391, isCity = true, faction = "Horde" },
                { name = "Vale of Eternal Blossoms", mapID = 390 },
                { name = "The Jade Forest", mapID = 371 },
                { name = "Valley of the Four Winds", mapID = 376 },
                { name = "Kun-Lai Summit", mapID = 379 },
                { name = "Townlong Steppes", mapID = 388 },
                { name = "Dread Wastes", mapID = 422 },
                { name = "Isle of Thunder", mapID = 504 },
                { name = "Timeless Isle", mapID = 554 },
            }},
        }
    },
    {
        name = "Cataclysm",
        icon = "Interface\\Icons\\Achievement_zone_deepholm",
        children = {
            { name = "Deepholm", mapID = 207 },
            { name = "Mount Hyjal", mapID = 198 },
            { name = "Vashj'ir", mapID = 203 },
            { name = "Uldum", mapID = 249 },
            { name = "Twilight Highlands", mapID = 241 },
            { name = "Tol Barad", mapID = 245 },
        }
    },
    {
        name = "Wrath of the Lich King",
        icon = "Interface\\Icons\\Achievement_zone_icecrown_01",
        children = {
            { name = "Northrend", mapID = 113, isContinent = true, children = {
                { name = "Dalaran (Northrend)", mapID = 125, isCity = true },
                { name = "Borean Tundra", mapID = 114 },
                { name = "Howling Fjord", mapID = 117 },
                { name = "Dragonblight", mapID = 115 },
                { name = "Grizzly Hills", mapID = 116 },
                { name = "Zul'Drak", mapID = 121 },
                { name = "Sholazar Basin", mapID = 119 },
                { name = "The Storm Peaks", mapID = 120 },
                { name = "Icecrown", mapID = 118 },
                { name = "Wintergrasp", mapID = 123 },
            }},
        }
    },
    {
        name = "The Burning Crusade",
        icon = "Interface\\Icons\\Achievement_zone_hellfire_01",
        children = {
            { name = "Outland", mapID = 101, isContinent = true, children = {
                { name = "Shattrath City", mapID = 111, isCity = true },
                { name = "Hellfire Peninsula", mapID = 100 },
                { name = "Zangarmarsh", mapID = 102 },
                { name = "Terokkar Forest", mapID = 108 },
                { name = "Nagrand (Outland)", mapID = 107 },
                { name = "Blade's Edge Mountains", mapID = 105 },
                { name = "Netherstorm", mapID = 109 },
                { name = "Shadowmoon Valley", mapID = 104 },
            }},
        }
    },
    {
        name = "Eastern Kingdoms",
        icon = "Interface\\Icons\\Achievement_zone_easternkingdoms_01",
        isContinent = true,
        mapID = 13,
        children = {
            { name = "Cities", children = {
                { name = "Stormwind", mapID = 84, isCity = true, faction = "Alliance" },
                { name = "Ironforge", mapID = 87, isCity = true, faction = "Alliance" },
                { name = "Undercity", mapID = 90, isCity = true, faction = "Horde" },
                { name = "Silvermoon City", mapID = 110, isCity = true, faction = "Horde" },
            }},
            { name = "Northern EK", children = {
                { name = "Tirisfal Glades", mapID = 18 },
                { name = "Silverpine Forest", mapID = 21 },
                { name = "Western Plaguelands", mapID = 22 },
                { name = "Eastern Plaguelands", mapID = 23 },
                { name = "The Hinterlands", mapID = 26 },
                { name = "Arathi Highlands", mapID = 14 },
                { name = "Wetlands", mapID = 56 },
                { name = "Loch Modan", mapID = 48 },
                { name = "Dun Morogh", mapID = 27 },
            }},
            { name = "Southern EK", children = {
                { name = "Elwynn Forest", mapID = 37 },
                { name = "Westfall", mapID = 52 },
                { name = "Duskwood", mapID = 47 },
                { name = "Redridge Mountains", mapID = 49 },
                { name = "Stranglethorn Vale", mapID = 210 },
                { name = "Swamp of Sorrows", mapID = 51 },
                { name = "Blasted Lands", mapID = 17 },
                { name = "Burning Steppes", mapID = 36 },
                { name = "Searing Gorge", mapID = 32 },
                { name = "Badlands", mapID = 15 },
            }},
        }
    },
    {
        name = "Kalimdor",
        icon = "Interface\\Icons\\Achievement_zone_kalimdor_01",
        isContinent = true,
        mapID = 12,
        children = {
            { name = "Cities", children = {
                { name = "Orgrimmar", mapID = 85, isCity = true, faction = "Horde" },
                { name = "Thunder Bluff", mapID = 88, isCity = true, faction = "Horde" },
                { name = "Darnassus", mapID = 89, isCity = true, faction = "Alliance" },
                { name = "Exodar", mapID = 103, isCity = true, faction = "Alliance" },
            }},
            { name = "Northern Kalimdor", children = {
                { name = "Teldrassil", mapID = 57 },
                { name = "Darkshore", mapID = 62 },
                { name = "Ashenvale", mapID = 63 },
                { name = "Azshara", mapID = 76 },
                { name = "Felwood", mapID = 77 },
                { name = "Winterspring", mapID = 83 },
                { name = "Moonglade", mapID = 80 },
            }},
            { name = "Central Kalimdor", children = {
                { name = "Durotar", mapID = 1 },
                { name = "The Barrens", mapID = 10 },
                { name = "Mulgore", mapID = 7 },
                { name = "Stonetalon Mountains", mapID = 65 },
                { name = "Desolace", mapID = 66 },
                { name = "Dustwallow Marsh", mapID = 70 },
                { name = "Feralas", mapID = 69 },
                { name = "Thousand Needles", mapID = 64 },
            }},
            { name = "Southern Kalimdor", children = {
                { name = "Tanaris", mapID = 71 },
                { name = "Un'Goro Crater", mapID = 78 },
                { name = "Silithus", mapID = 81 },
                { name = "Uldum", mapID = 249 },
            }},
        }
    },
    {
        name = "Class Halls",
        icon = "Interface\\Icons\\Inv_legion_faction_yourclasshall",
        children = {
            { name = "Acherus (Death Knight)", mapID = 118, class = "DEATHKNIGHT" },
            { name = "Fel Hammer (Demon Hunter)", mapID = 720, class = "DEMONHUNTER" },
            { name = "Emerald Dreamway (Druid)", mapID = 715, class = "DRUID" },
            { name = "Trueshot Lodge (Hunter)", mapID = 739, class = "HUNTER" },
            { name = "Hall of the Guardian (Mage)", mapID = 734, class = "MAGE" },
            { name = "Peak of Serenity (Monk)", mapID = 569, class = "MONK" },
            { name = "Sanctum of Light (Paladin)", mapID = 24, class = "PALADIN" },
            { name = "Netherlight Temple (Priest)", mapID = 702, class = "PRIEST" },
            { name = "Hall of Shadows (Rogue)", mapID = 626, class = "ROGUE" },
            { name = "Heart of Azeroth (Shaman)", mapID = 726, class = "SHAMAN" },
            { name = "Dreadscar Rift (Warlock)", mapID = 717, class = "WARLOCK" },
            { name = "Skyhold (Warrior)", mapID = 695, class = "WARRIOR" },
        }
    },
    {
        name = "Special",
        icon = "Interface\\Icons\\Inv_misc_map_01",
        children = {
            { name = "Hearthstone Location", mapID = 0, special = "hearthstone" },
            { name = "Garrison", mapID = 579 },
            { name = "Vulpera Camp", mapID = 0, special = "vulpera", race = "Vulpera" },
        }
    },
}

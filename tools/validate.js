'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DATA_FILE = path.join(ROOT, 'TravelData.lua');
const TOC_FILE = path.join(ROOT, 'TravelAdvisor.toc');

function relativeFile(file) {
    return path.relative(ROOT, file).replace(/\\/g, '/');
}

function lineNumber(source, offset) {
    return source.slice(0, offset).split(/\r?\n/).length;
}

function makeIssue(code, message, file, line, severity = 'error', details) {
    return {
        code,
        message,
        file,
        line,
        severity,
        ...(details ? { details } : {}),
    };
}

function findMatchingBrace(source, openIndex) {
    let depth = 0;
    let state = 'code';

    for (let i = openIndex; i < source.length; i += 1) {
        const char = source[i];
        const next = source[i + 1];

        if (state === 'lineComment') {
            if (char === '\n') state = 'code';
            continue;
        }

        if (state === 'blockComment') {
            if (char === ']' && next === ']') {
                state = 'code';
                i += 1;
            }
            continue;
        }

        if (state === 'singleQuote' || state === 'doubleQuote') {
            if (char === '\\') {
                i += 1;
            } else if ((state === 'singleQuote' && char === "'") ||
                (state === 'doubleQuote' && char === '"')) {
                state = 'code';
            }
            continue;
        }

        if (char === '-' && next === '-') {
            if (source[i + 2] === '[' && source[i + 3] === '[') {
                state = 'blockComment';
                i += 3;
            } else {
                state = 'lineComment';
                i += 1;
            }
            continue;
        }

        if (char === "'") {
            state = 'singleQuote';
        } else if (char === '"') {
            state = 'doubleQuote';
        } else if (char === '{') {
            depth += 1;
        } else if (char === '}') {
            depth -= 1;
            if (depth === 0) return i;
        }
    }

    return -1;
}

function extractTable(source, tableName) {
    const assignment = new RegExp(`TA\\.TravelData\\.${tableName}\\s*=\\s*\\{`);
    const match = assignment.exec(source);
    if (!match) return null;

    const openIndex = source.indexOf('{', match.index);
    const closeIndex = findMatchingBrace(source, openIndex);
    if (closeIndex < 0) {
        throw new Error(`Unterminated table: ${tableName}`);
    }

    return {
        name: tableName,
        source,
        body: source.slice(openIndex + 1, closeIndex),
        bodyStart: openIndex + 1,
        openIndex,
        closeIndex,
    };
}

function findDuplicateNumericKeys(table) {
    const seen = new Map();
    const duplicates = [];
    const keyPattern = /\[\s*(\d+)\s*\]\s*=/g;
    let match;

    while ((match = keyPattern.exec(table.body)) !== null) {
        const key = Number(match[1]);
        const current = {
            key,
            line: lineNumber(table.source, table.bodyStart + match.index),
        };
        const previous = seen.get(key);
        if (previous) {
            duplicates.push({ key, first: previous, duplicate: current });
        } else {
            seen.set(key, current);
        }
    }

    return duplicates;
}

function parseNumericField(text, fieldName) {
    const match = new RegExp(`\\b${fieldName}\\s*=\\s*(-?\\d+)`).exec(text);
    return match ? Number(match[1]) : null;
}

function parseStringField(text, fieldName) {
    const match = new RegExp(`\\b${fieldName}\\s*=\\s*(['\"])(.*?)\\1`).exec(text);
    return match ? match[2] : null;
}

function hasField(text, fieldName) {
    return new RegExp('\\b' + fieldName + '\\s*=').test(text);
}

function parseBooleanField(text, fieldName) {
    const match = new RegExp('\\b' + fieldName + '\\s*=\\s*(true|false)').exec(text);
    return match ? match[1] === 'true' : null;
}

function parseTableRecords(table) {
    const records = [];
    let state = 'code';
    let depth = 0;

    for (let index = table.bodyStart; index < table.closeIndex; index += 1) {
        const char = table.source[index];
        const next = table.source[index + 1];

        if (state === 'lineComment') {
            if (char === '\n') state = 'code';
            continue;
        }
        if (state === 'blockComment') {
            if (char === ']' && next === ']') {
                state = 'code';
                index += 1;
            }
            continue;
        }
        if (state === 'singleQuote' || state === 'doubleQuote') {
            if (char === '\\') index += 1;
            else if ((state === 'singleQuote' && char === "'")
                || (state === 'doubleQuote' && char === '"')) state = 'code';
            continue;
        }

        if (char === '-' && next === '-') {
            if (table.source[index + 2] === '[' && table.source[index + 3] === '[') {
                state = 'blockComment';
                index += 3;
            } else {
                state = 'lineComment';
                index += 1;
            }
            continue;
        }
        if (char === "'") {
            state = 'singleQuote';
        } else if (char === '"') {
            state = 'doubleQuote';
        } else if (char === '{') {
            if (depth === 0) {
                const closeIndex = findMatchingBrace(table.source, index);
                if (closeIndex < 0 || closeIndex > table.closeIndex) break;
                records.push({
                    text: table.source.slice(index, closeIndex + 1),
                    offset: index,
                    line: lineNumber(table.source, index),
                });
                index = closeIndex;
            } else {
                depth += 1;
            }
        } else if (char === '}') {
            depth = Math.max(0, depth - 1);
        }
    }

    return records;
}

function parseInlineRecords(table) {
    return parseTableRecords(table);
}

function extractNamedTable(source, parentTableName, childName) {
    const parent = extractTable(source, parentTableName);
    if (!parent) return null;
    const assignment = new RegExp('\\b' + childName + '\\s*=\\s*\\{').exec(parent.body);
    if (!assignment) return null;
    const openIndex = parent.bodyStart + assignment.index + assignment[0].lastIndexOf('{');
    const closeIndex = findMatchingBrace(source, openIndex);
    if (closeIndex < 0) return null;
    return {
        name: childName,
        source,
        body: source.slice(openIndex + 1, closeIndex),
        bodyStart: openIndex + 1,
        openIndex,
        closeIndex,
    };
}

function parseNestedRecords(source, start, end) {
    const records = [];
    let index = start;
    while (index < end) {
        const openIndex = source.indexOf('{', index);
        if (openIndex < 0 || openIndex >= end) break;
        const closeIndex = findMatchingBrace(source, openIndex);
        if (closeIndex < 0 || closeIndex > end) break;
        records.push({
            text: source.slice(openIndex, closeIndex + 1),
            offset: openIndex,
            line: lineNumber(source, openIndex),
        });
        index = closeIndex + 1;
    }
    return records;
}

function findDungeonDestinationContradictions(table) {
    const byMapID = new Map();
    const contradictions = [];
    const identityPolicy = extractTable(table.source, 'DungeonIdentityPolicy');
    const allowsSharedRegionMapIDs = Boolean(identityPolicy
        && /legacyMapField\s*=\s*["'](?:landingMapID|regionMapID)["']/.test(identityPolicy.body));

    for (const record of parseInlineRecords(table)) {
        const mapID = parseNumericField(record.text, 'mapID');
        const name = parseStringField(record.text, 'name') || parseStringField(record.text, 'destination');
        if (mapID === null || name === null) continue;

        const landingMapID = parseNumericField(record.text, 'landingMapID');
        const regionMapID = parseNumericField(record.text, 'regionMapID');
        const instanceMapID = parseNumericField(record.text, 'instanceMapID');
        const destinationKind = parseStringField(record.text, 'destinationKind');
        const zone = parseStringField(record.text, 'zone');
        const usesLandingIdentity = landingMapID !== null || regionMapID !== null
            || destinationKind === 'landing' || destinationKind === 'unknown';
        const previous = byMapID.get(mapID);
        const conflictingContext = previous && previous.zone && zone && previous.zone !== zone;
        if (previous && previous.name !== name
            && !usesLandingIdentity && !previous.usesLandingIdentity
            && (!allowsSharedRegionMapIDs || conflictingContext)
            && (instanceMapID === null || instanceMapID > 0)) {
            contradictions.push({
                mapID,
                first: previous,
                duplicate: { name, line: record.line, zone },
            });
        } else if (!previous) {
            byMapID.set(mapID, { name, line: record.line, usesLandingIdentity, zone });
        }
    }

    return contradictions;
}

function collectGraphNodeIDs(dataSource) {
    const nodeIDs = new Set();
    const zoneCoordinates = extractTable(dataSource, 'ZoneCoordinates');
    const portalHubs = extractTable(dataSource, 'PortalHubs');
    const zoneNames = extractTable(dataSource, 'ZoneNameToID');

    if (zoneCoordinates) {
        for (const match of zoneCoordinates.body.matchAll(/\[\s*(\d+)\s*\]\s*=/g)) {
            nodeIDs.add(Number(match[1]));
        }
    }

    if (portalHubs) {
        for (const match of portalHubs.body.matchAll(/\bmapID\s*=\s*(\d+)/g)) {
            nodeIDs.add(Number(match[1]));
        }
    }

    if (zoneNames) {
        for (const match of zoneNames.body.matchAll(/=\s*(\d+)/g)) {
            nodeIDs.add(Number(match[1]));
        }
    }

    const mapIdentity = extractTable(dataSource, 'MapIdentity');
    if (mapIdentity) {
        for (const match of mapIdentity.body.matchAll(/\[\s*(\d+)\s*\]\s*=/g)) {
            nodeIDs.add(Number(match[1]));
        }
    }

    const zoneTree = extractTable(dataSource, 'ZoneTree');
    if (zoneTree) {
        for (const match of zoneTree.body.matchAll(/\bmapID\s*=\s*(\d+)/g)) {
            nodeIDs.add(Number(match[1]));
        }
    }

    const continentZones = extractTable(dataSource, 'ContinentZones');
    if (continentZones) {
        for (const match of continentZones.body.matchAll(/(?:^|[=,])\s*(\d+)\s*(?=[,}])/gm)) {
            nodeIDs.add(Number(match[1]));
        }
    }

    const portalOnlyZones = extractTable(dataSource, 'PortalOnlyZones');
    if (portalOnlyZones) {
        for (const match of portalOnlyZones.body.matchAll(/^\s*(\d+)\s*,/gm)) {
            nodeIDs.add(Number(match[1]));
        }
    }

    const destinationOptions = extractTable(dataSource, 'MoleMachineDestinations');
    if (destinationOptions) {
        for (const match of destinationOptions.body.matchAll(/\bmapID\s*=\s*(\d+)/g)) {
            nodeIDs.add(Number(match[1]));
        }
    }

    nodeIDs.delete(0);
    return nodeIDs;
}

function firstNumericField(text, fields) {
    for (const field of fields) {
        const value = parseNumericField(text, field);
        if (value !== null) return { field, value };
    }
    return null;
}

function parseRequirementKeys(text) {
    const match = /\brequirements\s*=\s*\{([\s\S]*?)\}/.exec(text);
    if (!match) return [];
    return [...match[1].matchAll(/\b([A-Za-z][A-Za-z0-9_]*)\s*=/g)].map((entry) => entry[1]);
}

function validateSourceTablesStrict(dataSource, nodeIDs) {
    const issues = [];
    const sourceTables = [
        { name: 'MageTeleports', idField: 'spellID', requiresDestination: true },
        { name: 'MagePortals', idField: 'spellID', requiresDestination: true },
        { name: 'ClassTeleports', idField: 'spellID', requiresDestination: true },
        { name: 'DungeonTeleports', idField: 'spellID', requiresDestination: true },
        { name: 'Hearthstones', idField: 'itemID', requiresDestination: false },
        { name: 'TeleportItems', idField: 'itemID', requiresDestination: true },
        { name: 'TeleportToys', idField: 'itemID', requiresDestination: true },
        { name: 'RacialTeleports', idField: 'spellID', requiresDestination: true },
    ];
    const requirementFields = extractNamedTable(dataSource, 'RequirementCatalog', 'fields');
    const knownRequirements = new Set(requirementFields
        ? [...requirementFields.body.matchAll(/["']([^"']+)["']/g)].map((match) => match[1])
        : []);
    const resolverTable = extractTable(dataSource, 'DestinationResolvers');

    for (const spec of sourceTables) {
        const table = extractTable(dataSource, spec.name);
        if (!table) {
            issues.push(makeIssue(
                'MISSING_SOURCE_TABLE',
                'Expected travel-source table ' + spec.name + ' was not found.',
                relativeFile(DATA_FILE),
                1,
            ));
            continue;
        }

        const metadata = extractNamedTable(dataSource, 'SourceMetadata', spec.name);
        if (!metadata) {
            issues.push(makeIssue(
                'MISSING_SOURCE_METADATA',
                spec.name + ' has no SourceMetadata entry describing IDs, icons, destinations, and provenance.',
                relativeFile(DATA_FILE),
                lineNumber(dataSource, table.openIndex),
            ));
        }
        const iconResolver = metadata && parseStringField(metadata.body, 'iconResolver');
        const categoryResolver = metadata && parseStringField(metadata.body, 'destinationResolver');
        const seenIDs = new Map();

        for (const record of parseInlineRecords(table)) {
            const sourceID = parseNumericField(record.text, spec.idField);
            const sourceName = parseStringField(record.text, 'name');
            if (!sourceName) {
                issues.push(makeIssue(
                    'MISSING_SOURCE_NAME',
                    spec.name + ' record is missing a display name.',
                    relativeFile(DATA_FILE),
                    record.line,
                ));
            }
            const displayName = sourceName || '(unnamed source)';
            if (sourceID === null || sourceID <= 0) {
                issues.push(makeIssue(
                    'INVALID_SOURCE_ID',
                    spec.name + ' record ' + displayName + ' has no positive ' + spec.idField + '.',
                    relativeFile(DATA_FILE),
                    record.line,
                ));
            } else if (seenIDs.has(sourceID)
                && !hasField(record.text, 'variantKey') && !hasField(record.text, 'variantOf')) {
                const previous = seenIDs.get(sourceID);
                issues.push(makeIssue(
                    'DUPLICATE_SOURCE_ID',
                    spec.name + ' repeats stable ' + spec.idField + ' ' + sourceID + ' for '
                        + previous.name + ' and ' + displayName
                        + '; model an explicit variant or keep one canonical record.',
                    relativeFile(DATA_FILE),
                    record.line,
                    'error',
                    { firstLine: previous.line, sourceID },
                ));
            } else if (sourceID !== null && sourceID > 0) {
                seenIDs.set(sourceID, { name: displayName, line: record.line });
            }

            const icon = parseStringField(record.text, 'icon')
                || parseStringField(record.text, 'iconPath')
                || parseStringField(record.text, 'iconResolver');
            if (!icon && !iconResolver) {
                issues.push(makeIssue(
                    'MISSING_SOURCE_ICON',
                    spec.name + ' source ' + displayName + ' has no icon or category icon resolver.',
                    relativeFile(DATA_FILE),
                    record.line,
                ));
            }

            const destination = firstNumericField(record.text, [
                'landingMapID', 'destinationMapID', 'regionMapID', 'mapID',
            ]);
            const resolver = parseStringField(record.text, 'destinationResolver')
                || parseStringField(record.text, 'resolveDestination');
            const destinationKind = parseStringField(record.text, 'destinationKind')
                || parseStringField(record.text, 'destinationType');
            const routeEligible = parseBooleanField(record.text, 'routeEligible');
            const destinationOptions = parseStringField(record.text, 'destinationOptions');
            const hasResolverMetadata = Boolean(
                resolver || destinationKind || destinationOptions || routeEligible === false
                || (!spec.requiresDestination && categoryResolver)
            );

            if (destinationOptions && !extractTable(dataSource, destinationOptions)) {
                issues.push(makeIssue(
                    'UNDEFINED_DESTINATION_RECORD',
                    spec.name + ' source ' + displayName + ' refers to destination record '
                        + destinationOptions + ', which is not defined.',
                    relativeFile(DATA_FILE),
                    record.line,
                ));
            }
            if (resolver && resolverTable
                && !new RegExp("\\[\\s*[\"']" + resolver + "[\"']\\s*\\]").test(resolverTable.body)
                && resolver !== categoryResolver) {
                issues.push(makeIssue(
                    'UNDEFINED_DESTINATION_RESOLVER',
                    spec.name + ' source ' + displayName + ' refers to destination resolver '
                        + resolver + ', which is not defined.',
                    relativeFile(DATA_FILE),
                    record.line,
                ));
            }

            if (spec.requiresDestination && !hasResolverMetadata && !destination) {
                issues.push(makeIssue(
                    'MISSING_DESTINATION_RESOLVER',
                    spec.name + ' source ' + displayName
                        + ' has no map destination, resolver, destination kind, or explicit informational exclusion.',
                    relativeFile(DATA_FILE),
                    record.line,
                ));
            } else if (destination && destination.value > 0 && !nodeIDs.has(destination.value)) {
                issues.push(makeIssue(
                    'MISSING_GRAPH_DESTINATION',
                    spec.name + ' source ' + displayName + ' targets mapID ' + destination.value
                        + ', but no graph node definition was found.',
                    relativeFile(DATA_FILE),
                    record.line,
                ));
            } else if (spec.requiresDestination && destination && destination.value <= 0
                && !hasResolverMetadata) {
                issues.push(makeIssue(
                    'UNRESOLVED_DESTINATION',
                    spec.name + ' source ' + displayName + ' uses '
                        + destination.field + ' ' + destination.value
                        + '; it must declare a resolver or explicit non-routable state.',
                    relativeFile(DATA_FILE),
                    record.line,
                ));
            }

            for (const requirement of parseRequirementKeys(record.text)) {
                if (!knownRequirements.has(requirement)) {
                    issues.push(makeIssue(
                        'UNDEFINED_REQUIREMENT',
                        spec.name + ' source ' + displayName
                            + ' refers to unknown requirement field ' + requirement + '.',
                        relativeFile(DATA_FILE),
                        record.line,
                    ));
                }
            }
        }
    }

    return issues;
}

function validateZoneConnections(dataSource, nodeIDs) {
    const issues = [];
    const table = extractTable(dataSource, 'ZoneConnections');
    if (!table) return issues;

    const allowedModes = new Set([
        'walking', 'riding', 'flight', 'flightpath', 'taxi', 'portal', 'portal-room',
        'boat', 'zeppelin', 'ferry', 'dungeon-landing', 'external-interaction',
        'walk', 'ride', 'flightpath', 'flight', 'taxi', 'boat', 'zeppelin', 'ferry',
    ]);
    const edgePattern = /\[\s*(\d+)\s*\]\s*=\s*\{/g;
    let match;
    while ((match = edgePattern.exec(table.body)) !== null) {
        const from = Number(match[1]);
        const openIndex = table.bodyStart + match.index + match[0].lastIndexOf('{');
        const closeIndex = findMatchingBrace(table.source, openIndex);
        const line = lineNumber(table.source, openIndex);
        if (!nodeIDs.has(from)) {
            issues.push(makeIssue(
                'MISSING_GRAPH_NODE',
                `ZoneConnections references missing source mapID ${from}.`,
                relativeFile(DATA_FILE),
                line,
            ));
        }

        const records = closeIndex >= 0
            ? parseNestedRecords(table.source, openIndex + 1, closeIndex)
            : [];
        const connectionBody = closeIndex >= 0
            ? table.source.slice(openIndex + 1, closeIndex)
            : '';
        const targets = records.length > 0
            ? records.map((record) => ({ record, to: parseNumericField(record.text, 'to')
                || parseNumericField(record.text, 'mapID')
                || parseNumericField(record.text, 'destinationMapID') }))
            : [...connectionBody.matchAll(/\b(\d+)\b/g)].map((target) => ({
                record: { text: target[0], line },
                to: Number(target[1]),
            }));
        for (const target of targets) {
            const to = target.to;
            if (!to) continue;
            if (!nodeIDs.has(to)) {
                issues.push(makeIssue(
                    'MISSING_GRAPH_NODE',
                    `ZoneConnections from ${from} references missing destination mapID ${to}.`,
                    relativeFile(DATA_FILE),
                    line,
                ));
            }

            const mode = parseStringField(target.record.text, 'mode')
                || parseStringField(target.record.text, 'travelMode')
                || parseStringField(target.record.text, 'type');
            if (records.length > 0 && (!mode || !allowedModes.has(mode))) {
                issues.push(makeIssue(
                    'INVALID_TRAVEL_MODE',
                    `ZoneConnections from ${from} to ${to} must declare a supported travel mode.`,
                    relativeFile(DATA_FILE),
                    target.record.line,
                ));
            }
        }

        if (closeIndex >= 0) edgePattern.lastIndex = closeIndex - table.bodyStart + 1;
    }

    return issues;
}

function validateDungeonIdentitySchema(dataSource) {
    const issues = [];
    const requiredFields = ['instanceMapID', 'entranceMapID', 'landingMapID', 'regionMapID'];
    if (!dataSource.includes('DungeonIdentityPolicy')) {
        issues.push(makeIssue(
            'MISSING_DUNGEON_IDENTITY_SCHEMA',
            'Dungeon teleport data must declare an explicit instance/entrance/landing/region identity policy.',
            relativeFile(DATA_FILE),
            1,
        ));
        return issues;
    }
    for (const field of requiredFields) {
        if (!dataSource.includes(`${field} =`)) {
            issues.push(makeIssue(
                'MISSING_DUNGEON_IDENTITY_FIELD',
                `Dungeon identity policy is missing ${field}.`,
                relativeFile(DATA_FILE),
                1,
            ));
        }
    }
    return issues;
}

function validateStaticEdgeMetadata(dataSource) {
    const issues = [];
    const policy = extractTable(dataSource, 'StaticEdgePolicy');
    if (!policy) {
        issues.push(makeIssue(
            'MISSING_STATIC_EDGE_POLICY',
            'Static portal, topology, and transport edges must declare a shared access/availability policy.',
            relativeFile(DATA_FILE),
            1,
        ));
        return issues;
    }

    const requiredFieldsTable = extractNamedTable(dataSource, 'StaticEdgePolicy', 'requiredFields');
    const requiredFields = requiredFieldsTable
        ? [...requiredFieldsTable.body.matchAll(/["']([^"']+)["']/g)].map((match) => match[1])
        : [];
    for (const field of requiredFields) {
        if (!policy.body.includes('"' + field + '"') && !policy.body.includes("'" + field + "'")) {
            issues.push(makeIssue(
                'MISSING_STATIC_EDGE_FIELD',
                'StaticEdgePolicy.requiredFields is missing ' + field + '.',
                relativeFile(DATA_FILE),
                lineNumber(dataSource, policy.openIndex),
            ));
        }
    }

    for (const category of ['ZoneConnections', 'PortalHubs', 'Transports']) {
        if (!policy.body.includes(category)) {
            issues.push(makeIssue(
                'MISSING_STATIC_EDGE_CATEGORY',
                'StaticEdgePolicy does not document ' + category + ' entries.',
                relativeFile(DATA_FILE),
                lineNumber(dataSource, policy.openIndex),
            ));
        }
    }

    if (!/applyStaticEdgeMetadata\(connection,/.test(dataSource)
        || !/applyStaticEdgeMetadata\(portal,/.test(dataSource)) {
        issues.push(makeIssue(
            'STATIC_EDGE_METADATA_NOT_APPLIED',
            'Static edge metadata is documented but not applied to ZoneConnections and PortalHubs.',
            relativeFile(DATA_FILE),
            lineNumber(dataSource, policy.openIndex),
        ));
    }

    const defaults = extractNamedTable(dataSource, 'StaticEdgePolicy', 'defaults');
    for (const field of requiredFields) {
        if (!defaults || !hasField(defaults.body, field)) {
            issues.push(makeIssue(
                'MISSING_STATIC_EDGE_DEFAULT',
                'StaticEdgePolicy.defaults is missing ' + field + '.',
                relativeFile(DATA_FILE),
                lineNumber(dataSource, policy.openIndex),
            ));
        }
    }
    for (const category of ['ZoneConnections', 'PortalHubs', 'Transports']) {
        const categoryPolicy = extractNamedTable(dataSource, 'StaticEdgePolicy', category);
        for (const field of requiredFields) {
            if (!categoryPolicy || !hasField(categoryPolicy.body, field)) {
                issues.push(makeIssue(
                    'MISSING_STATIC_EDGE_CATEGORY_FIELD',
                    'StaticEdgePolicy.' + category + ' is missing ' + field + '.',
                    relativeFile(DATA_FILE),
                    categoryPolicy
                        ? lineNumber(dataSource, categoryPolicy.openIndex)
                        : lineNumber(dataSource, policy.openIndex),
                ));
            }
        }
    }

    const transports = extractNamedTable(dataSource, 'StaticEdgePolicy', 'Transports');
    if (!transports || parseStringField(transports.body, 'status') !== 'informational-only') {
        issues.push(makeIssue(
            'TRANSPORT_ACCESS_UNDOCUMENTED',
            'Transport coverage must remain explicitly informational until schedule and location access are authoritative.',
            relativeFile(DATA_FILE),
            lineNumber(dataSource, policy.openIndex),
        ));
    }

    const hubs = extractTable(dataSource, 'PortalHubs');
    if (hubs) {
        for (const hub of parseInlineRecords(hubs)) {
            const hubName = parseStringField(hub.text, 'name');
            const hubMapID = parseNumericField(hub.text, 'mapID');
            if (!hubName) {
                issues.push(makeIssue(
                    'MISSING_NODE_NAME',
                    'Portal hub is missing a name.',
                    relativeFile(DATA_FILE),
                    hub.line,
                ));
            }
            if (hubMapID === null || hubMapID <= 0) {
                issues.push(makeIssue(
                    'MISSING_NODE_MAP_ID',
                    'Portal hub ' + (hubName || '(unnamed)') + ' is missing a positive mapID.',
                    relativeFile(DATA_FILE),
                    hub.line,
                ));
            }

            const portalsStart = hub.text.search(/\bportalsTo\s*=\s*\{/);
            if (portalsStart < 0) continue;
            const portalsOpen = hub.text.indexOf('{', portalsStart);
            const portalsClose = findMatchingBrace(hub.text, portalsOpen);
            if (portalsClose < 0) continue;
            for (const portal of parseNestedRecords(hub.text, portalsOpen + 1, portalsClose)) {
                const portalName = parseStringField(portal.text, 'name');
                const portalMapID = parseNumericField(portal.text, 'mapID');
                if (!portalName || portalMapID === null || portalMapID <= 0) {
                    issues.push(makeIssue(
                        !portalName ? 'MISSING_NODE_NAME' : 'MISSING_NODE_MAP_ID',
                        'Portal edge in ' + (hubName || '(unnamed hub)')
                            + ' must declare a name and positive mapID.',
                        relativeFile(DATA_FILE),
                        hub.line,
                    ));
                }
            }
        }
    }

    const connections = extractTable(dataSource, 'ZoneConnections');
    if (!connections) {
        issues.push(makeIssue(
            'MISSING_STATIC_TOPOLOGY',
            'ZoneConnections is required so static movement edges are explicit and auditable.',
            relativeFile(DATA_FILE),
            1,
        ));
    }
    return issues;
}

function validateDataGovernance(dataSource) {
    const issues = [];
    const metadata = extractTable(dataSource, 'Metadata');
    const requiredMetadata = ['schemaVersion', 'client', 'patch', 'build', 'lastChecked', 'maintenance', 'process'];
    if (!metadata) {
        issues.push(makeIssue(
            'MISSING_DATA_METADATA',
            'Travel data must declare client, patch, schema, and maintenance metadata.',
            relativeFile(DATA_FILE),
            1,
        ));
    } else {
        for (const field of requiredMetadata) {
            if (!hasField(metadata.body, field) && !metadata.body.includes('patch =') && field === 'patch') {
                issues.push(makeIssue(
                    'MISSING_DATA_METADATA_FIELD',
                    'TravelData.Metadata is missing ' + field + '.',
                    relativeFile(DATA_FILE),
                    lineNumber(dataSource, metadata.openIndex),
                ));
            } else if (field !== 'patch' && !hasField(metadata.body, field)) {
                issues.push(makeIssue(
                    'MISSING_DATA_METADATA_FIELD',
                    'TravelData.Metadata is missing ' + field + '.',
                    relativeFile(DATA_FILE),
                    lineNumber(dataSource, metadata.openIndex),
                ));
            }
        }
    }

    const sourceMetadata = extractTable(dataSource, 'SourceMetadata');
    const sourceCategories = [
        'MageTeleports', 'MagePortals', 'ClassTeleports', 'DungeonTeleports',
        'Hearthstones', 'TeleportItems', 'TeleportToys', 'RacialTeleports',
    ];
    if (!sourceMetadata) {
        issues.push(makeIssue(
            'MISSING_SOURCE_PROVENANCE',
            'SourceMetadata is required for source IDs, icon APIs, destinations, and provenance.',
            relativeFile(DATA_FILE),
            1,
        ));
    } else {
        for (const category of sourceCategories) {
            const entry = extractNamedTable(dataSource, 'SourceMetadata', category);
            for (const field of [
                'stableIDField', 'iconResolver', 'destinationResolver', 'source',
                'verifiedBuild', 'patch', 'lastChecked', 'verification', 'evidence',
            ]) {
                if (!entry || !hasField(entry.body, field)) {
                    issues.push(makeIssue(
                        'INCOMPLETE_SOURCE_PROVENANCE',
                        category + ' provenance is missing ' + field + '.',
                        relativeFile(DATA_FILE),
                        entry ? lineNumber(dataSource, entry.openIndex) : lineNumber(dataSource, sourceMetadata.openIndex),
                    ));
                }
            }
        }
    }

    const requirementCatalog = extractTable(dataSource, 'RequirementCatalog');
    const requirementFields = extractNamedTable(dataSource, 'RequirementCatalog', 'fields');
    if (!requirementFields || !/["'][^"']+["']/.test(requirementFields.body)) {
        issues.push(makeIssue(
            'EMPTY_REQUIREMENT_CATALOG',
            'RequirementCatalog.fields must declare the supported requirement keys.',
            relativeFile(DATA_FILE),
            requirementCatalog ? lineNumber(dataSource, requirementCatalog.openIndex) : 1,
        ));
    }
    const requirementReferences = extractNamedTable(dataSource, 'RequirementCatalog', 'references');
    if (requirementReferences) {
        for (const match of requirementReferences.body.matchAll(
            /\b([A-Za-z][A-Za-z0-9_]*)\s*=\s*[\"']([^\"']+)[\"']/g
        )) {
            const reference = match[2];
            if (reference === 'named-data-table') continue;
            if (!extractTable(dataSource, reference)) {
                issues.push(makeIssue(
                    'UNDEFINED_REQUIREMENT_REFERENCE',
                    'RequirementCatalog reference ' + match[1] + ' points to undefined table ' + reference + '.',
                    relativeFile(DATA_FILE),
                    lineNumber(dataSource, requirementReferences.openIndex),
                ));
            }
        }
    }

    for (const [tableName, issueCode, message] of [
        ['DestinationResolvers', 'MISSING_DESTINATION_RESOLVER_CATALOG', 'DestinationResolvers'],
        ['RequirementCatalog', 'MISSING_REQUIREMENT_CATALOG', 'RequirementCatalog'],
        ['UserSourcePolicy', 'MISSING_USER_SOURCE_POLICY', 'UserSourcePolicy'],
    ]) {
        if (!extractTable(dataSource, tableName)) {
            issues.push(makeIssue(issueCode, message + ' is not defined.', relativeFile(DATA_FILE), 1));
        }
    }

    const userPolicy = extractTable(dataSource, 'UserSourcePolicy');
    if (userPolicy && parseStringField(userPolicy.body, 'status') !== 'out-of-scope') {
        issues.push(makeIssue(
            'USER_SOURCE_SCOPE_UNCLEAR',
            'User-defined sources must be explicitly marked in or out of scope.',
            relativeFile(DATA_FILE),
            lineNumber(dataSource, userPolicy.openIndex),
        ));
    }
    return issues;
}

function validateTarget(tocSource) {
    const issues = [];
    const match = /^##\s*Interface:\s*(.+)$/m.exec(tocSource);
    const values = match ? match[1].split(',').map((value) => value.trim()).filter(Boolean) : [];
    if (!values.includes('120100')) {
        issues.push(makeIssue(
            'TOC_TARGET_MISMATCH',
            `TravelAdvisor.toc must target WoW 12.1 with interface 120100; found ${values.join(', ') || '(none)'}.`,
            relativeFile(TOC_FILE),
            match ? lineNumber(tocSource, match.index) : 1,
        ));
    }
    return issues;
}

function validate() {
    const dataSource = fs.readFileSync(DATA_FILE, 'utf8');
    const tocSource = fs.readFileSync(TOC_FILE, 'utf8');
    const issues = [...validateTarget(tocSource)];

    const zoneCoordinates = extractTable(dataSource, 'ZoneCoordinates');
    if (!zoneCoordinates) {
        issues.push(makeIssue(
            'MISSING_ZONE_COORDINATES',
            'TA.TravelData.ZoneCoordinates was not found.',
            relativeFile(DATA_FILE),
            1,
        ));
    } else {
        for (const duplicate of findDuplicateNumericKeys(zoneCoordinates)) {
            issues.push(makeIssue(
                'DUPLICATE_MAP_KEY',
                `ZoneCoordinates defines mapID ${duplicate.key} more than once (first line ${duplicate.first.line}).`,
                relativeFile(DATA_FILE),
                duplicate.duplicate.line,
                'error',
                { mapID: duplicate.key, firstLine: duplicate.first.line },
            ));
        }
    }

    const dungeonTeleports = extractTable(dataSource, 'DungeonTeleports');
    if (dungeonTeleports) {
        for (const contradiction of findDungeonDestinationContradictions(dungeonTeleports)) {
            issues.push(makeIssue(
                'CONTRADICTORY_DESTINATION_IDENTITY',
                `DungeonTeleports maps ${contradiction.first.name} and ${contradiction.duplicate.name} to the same mapID ${contradiction.mapID}; instance and landing identities must be separated.`,
                relativeFile(DATA_FILE),
                contradiction.duplicate.line,
                'error',
                { mapID: contradiction.mapID, firstLine: contradiction.first.line },
            ));
        }
    }

    const nodeIDs = collectGraphNodeIDs(dataSource);
    issues.push(...validateSourceTablesStrict(dataSource, nodeIDs));
    issues.push(...validateStaticEdgeMetadata(dataSource));
    issues.push(...validateDataGovernance(dataSource));
    issues.push(...validateZoneConnections(dataSource, nodeIDs));
    issues.push(...validateDungeonIdentitySchema(dataSource));

    return {
        issues,
        stats: {
            graphNodeCount: nodeIDs.size,
            errorCount: issues.filter((issue) => issue.severity === 'error').length,
            warningCount: issues.filter((issue) => issue.severity === 'warning').length,
        },
    };
}

function printHuman(result) {
    console.log('TravelAdvisor Phase 0 validator');
    console.log(`Graph node IDs discovered: ${result.stats.graphNodeCount}`);
    if (result.issues.length === 0) {
        console.log('PASS: no validation findings.');
        return;
    }

    for (const issue of result.issues) {
        const location = issue.file ? `${issue.file}:${issue.line}` : '';
        console.log(`- ${issue.severity.toUpperCase()} ${issue.code}${location ? ` ${location}` : ''}: ${issue.message}`);
    }
    console.log(`Summary: ${result.stats.errorCount} error(s), ${result.stats.warningCount} warning(s).`);
}

if (require.main === module) {
    const result = validate();
    if (process.argv.includes('--json')) {
        console.log(JSON.stringify(result, null, 2));
    } else {
        printHuman(result);
    }
    process.exitCode = result.stats.errorCount > 0 ? 1 : 0;
}

module.exports = {
    extractTable,
    extractNamedTable,
    findDuplicateNumericKeys,
    findDungeonDestinationContradictions,
    collectGraphNodeIDs,
    parseTableRecords,
    parseInlineRecords,
    parseNumericField,
    validate,
    validateSourceTables: validateSourceTablesStrict,
    validateStaticEdgeMetadata,
    validateDataGovernance,
    validateDungeonIdentitySchema,
};

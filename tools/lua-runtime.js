'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function candidatePaths() {
    return [
        process.env.LUAJIT,
        process.env.USERPROFILE && path.join(process.env.USERPROFILE, 'bin', 'luajit.exe'),
        'luajit',
    ].filter(Boolean);
}

function findLuaJIT() {
    for (const candidate of candidatePaths()) {
        if (path.isAbsolute(candidate) && !fs.existsSync(candidate)) continue;

        const probe = spawnSync(candidate, ['-v'], {
            stdio: 'ignore',
            windowsHide: true,
        });
        if (!probe.error && probe.status === 0) return candidate;
    }
    return null;
}

function runLuaJITHarness(harness, root) {
    const lua = findLuaJIT();
    if (!lua) {
        console.log(`SKIP: LuaJIT runtime not found; skipped ${path.basename(harness)}.`);
        return { skipped: true, status: 0 };
    }

    const result = spawnSync(lua, [harness, root], {
        cwd: root,
        encoding: 'utf8',
        windowsHide: true,
    });
    if (result.error) throw result.error;
    return { skipped: false, result };
}

module.exports = { findLuaJIT, runLuaJITHarness };

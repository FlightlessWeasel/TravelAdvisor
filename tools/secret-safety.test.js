'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const harness = path.join(__dirname, 'secret-safety-repro.lua');
const candidates = [
    process.env.LUAJIT,
    process.env.USERPROFILE && path.join(process.env.USERPROFILE, 'bin', 'luajit.exe'),
    'luajit',
].filter(Boolean);
const lua = candidates.find((candidate) => !path.isAbsolute(candidate) || fs.existsSync(candidate));
assert.ok(lua, 'LuaJIT is required for the secret-value regression harness.');
const result = spawnSync(lua, [harness, ROOT], {
    cwd: ROOT,
    encoding: 'utf8',
});

if (result.error) {
    throw result.error;
}

assert.strictEqual(result.status, 0, result.stderr || result.stdout);
assert.match(result.stdout, /Secret-value safety regression: PASS/);
console.log('Secret-value safety regression: PASS');

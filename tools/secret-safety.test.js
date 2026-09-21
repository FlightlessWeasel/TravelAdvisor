'use strict';

const assert = require('assert');
const path = require('path');
const { runLuaJITHarness } = require('./lua-runtime');

const ROOT = path.resolve(__dirname, '..');
const harness = path.join(__dirname, 'secret-safety-repro.lua');
const run = runLuaJITHarness(harness, ROOT);
if (run.skipped) process.exit(0);
const { result } = run;
assert.strictEqual(result.status, 0, result.stderr || result.stdout);
assert.match(result.stdout, /Secret-value safety regression: PASS/);
console.log('Secret-value safety regression: PASS');

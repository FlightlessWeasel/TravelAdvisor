'use strict';

const assert = require('assert');
const path = require('path');
const { runLuaJITHarness } = require('./lua-runtime');

const ROOT = path.resolve(__dirname, '..');
const harness = path.join(__dirname, 'taint-safety-repro.lua');
const run = runLuaJITHarness(harness, ROOT);
if (run.skipped) process.exit(0);
const { result } = run;
assert.strictEqual(result.status, 0, result.stderr || result.stdout);
assert.match(result.stdout, /Taint-safety regression: PASS/);
console.log('Taint-safety regression: PASS');

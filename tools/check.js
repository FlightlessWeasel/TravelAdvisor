'use strict';

const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const checks = [
    ['Phase 0 contract tests', path.join(__dirname, 'phase0.test.js')],
    ['Phase 1 contract tests', path.join(__dirname, 'phase1.test.js')],
    ['Phase 2 contract tests', path.join(__dirname, 'phase2.test.js')],
    ['Phase 3 contract tests', path.join(__dirname, 'phase3.test.js')],
    ['Phase 4 contract tests', path.join(__dirname, 'phase4.test.js')],
    ['Phase 5 contract tests', path.join(__dirname, 'phase5.test.js')],
    ['Phase 6 contract tests', path.join(__dirname, 'phase6.test.js')],
    ['Travel-data validator', path.join(__dirname, 'validate.js')],
];

let failed = false;
for (const [label, script] of checks) {
    console.log(`== ${label} ==`);
    const result = spawnSync(process.execPath, [script], {
        cwd: ROOT,
        stdio: 'inherit',
    });
    if (result.error) {
        console.error(result.error.message);
        failed = true;
    } else if (result.status !== 0) {
        failed = true;
    }
}

process.exitCode = failed ? 1 : 0;

// Batch manifests: one line per game, `status=ok label="..." seed=30 arm=on lineup=A log="..."`, written by batch.js (and by
// the hand-written bNN.sh scripts before it). Shared by nf.js, lineup_check.js, bank.js and er.js.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

/** `~/...` and `/c/...` (Git Bash) paths as Node can open them. */
function expandPath(p) {
    if (p.startsWith('~/')) return path.join(os.homedir(), p.slice(2));
    const m = process.platform === 'win32' && p.match(/^\/([a-z])\/(.*)/i);
    return m ? `${m[1].toUpperCase()}:/${m[2]}` : p;
}

/** k=v and k="v" fields of one manifest line. */
function fields(line) {
    const out = {};
    for (const m of line.matchAll(/(\w+)=(?:"([^"]*)"|(\S+))/g)) out[m[1]] = m[2] !== undefined ? m[2] : m[3];
    return out;
}

/** The ok games of a manifest, in order: { label, seed (number), arm, lineup, log (expanded), ...other fields }. */
function readManifest(file) {
    return fs
        .readFileSync(file, 'utf8')
        .split(/\r?\n/)
        .filter(l => /^status=ok /.test(l))
        .map(l => {
            const f = fields(l);
            return { ...f, seed: Number(f.seed), log: expandPath(f.log) };
        });
}

module.exports = { readManifest, fields, expandPath };

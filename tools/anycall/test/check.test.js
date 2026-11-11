const test = require('node:test');
const assert = require('node:assert');
const ts = require('typescript');
const { findAnyCalls } = require('../check.js');

const UNIT = 'interface Unit { GetHealth(): number; extra: any; }\ndeclare const typed: Unit;\ndeclare const loose: any;\n';

function run(body) {
    const name = '/virtual/case.ts';
    const text = UNIT + body;
    const host = ts.createCompilerHost({});
    const read = host.getSourceFile.bind(host);
    host.getSourceFile = (file, target) => (file === name ? ts.createSourceFile(file, text, target, true) : read(file, target));
    const program = ts.createProgram([name], { strict: true, noEmit: true, target: ts.ScriptTarget.ES2020 }, host);
    return findAnyCalls(program, (file) => file === name).map((f) => f.text);
}

test('a unit method called on an any value is flagged', () => {
    assert.deepStrictEqual(run('loose.GetHealth();'), ['loose.GetHealth']);
});

test('a cast to any, an optional call and an index call are all flagged', () => {
    assert.deepStrictEqual(run('(typed as any).GetHealth();\nloose.GetHealth?.();\nloose["GetHealth"]();'), [
        '(typed as any).GetHealth',
        'loose.GetHealth',
        'loose["GetHealth"]',
    ]);
});

test('an any member of a typed value is flagged: it has no method declaration either', () => {
    assert.deepStrictEqual(run('typed.extra();'), ['typed.extra']);
});

test('a declared method, a bare any function and a field read off any are not flagged', () => {
    assert.deepStrictEqual(run('typed.GetHealth();\ndeclare const fn: any;\nfn(1);\nconst d = loose.damage;\nvoid d;'), []);
});

test('the allow comment covers its own line and the next, and nothing further', () => {
    const body = [
        '// any-call-ok: a global function, called without self',
        'loose.InstallDamageCallback(1);',
        'loose.Other(); // any-call-ok: a module function',
        'loose.Third();',
        '// any-call-ok:',
        'loose.Fourth();',
    ].join('\n');
    assert.deepStrictEqual(run(body), ['loose.Third', 'loose.Fourth']);
});

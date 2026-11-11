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

test('a cast on the callee and a Function member are flagged: the compiler drops the cast and finds no signature', () => {
    assert.deepStrictEqual(run('(typed.GetHealth as any)();\ndeclare const holder: { fn: Function };\nholder.fn();'), ['typed.GetHealth', 'holder.fn']);
});

test('only the undeclared call is reported among declared methods, this-void members, bare functions and field reads', () => {
    const body = [
        'typed.GetHealth();',
        'declare const mod: { plain: (this: void, n: number) => number };',
        'mod.plain(1);',
        'declare const fn: any;',
        'fn(1);',
        'const d = loose.damage;',
        'loose.GetMana(d);',
    ].join('\n');
    assert.deepStrictEqual(run(body), ['loose.GetMana']);
});

test('one allow comment does not cover two undeclared calls on a line', () => {
    assert.deepStrictEqual(run('loose.A(loose.B()); // any-call-ok: only one of these was meant'), ['loose.A', 'loose.B']);
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

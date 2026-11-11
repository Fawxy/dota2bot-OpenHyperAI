#!/usr/bin/env node
// Fails the build on a member call with no declared signature (the callee is `any` or `Function`) in our bot code.
//
// The Lua build runs with noImplicitSelf, so `x.Foo()` only passes `x` as the first argument (`x:Foo()`) when the type
// declares Foo as a method. With no declaration (`x` is `any`, or `Foo` is an `any` member) it compiles to `x.Foo()`,
// which type-checks, passes the Lua syntax check, and fails only in a game: a unit method called without its unit.
//
// A call that is meant to be a plain function call (a global looked up on `_G`, a Lua module's function) is allowed by a
// comment on its line or the line above:   // any-call-ok: <why a call without self is right here>
const path = require('path');
const ts = require('typescript');

const ALLOW = /\/\/\s*any-call-ok:\s*\S/;
// The line above counts only when it is a comment of its own, so one call's trailing comment never covers the next call.
const ALLOW_ABOVE = /^\s*\/\/\s*any-call-ok:\s*\S/;

/** Findings for every source file `include(fileName)` accepts: { file, line, col, text }. */
function findAnyCalls(program, include) {
    const checker = program.getTypeChecker();
    const findings = [];
    for (const sourceFile of program.getSourceFiles()) {
        if (sourceFile.isDeclarationFile || !include(sourceFile.fileName)) continue;
        const lines = sourceFile.text.split('\n');
        const byLine = new Map();
        const visit = (node) => {
            if (ts.isCallExpression(node)) {
                // The compiler's own test: it drops casts and parentheses around the callee, then passes self only when
                // the call resolves to a declared signature. `any` and `Function` callees resolve to none.
                const callee = ts.skipOuterExpressions(node.expression);
                const member = ts.isPropertyAccessExpression(callee) || ts.isElementAccessExpression(callee);
                const signature = member ? checker.getResolvedSignature(node) : undefined;
                if (member && (signature === undefined || signature.getDeclaration() === undefined)) {
                    const pos = sourceFile.getLineAndCharacterOfPosition(callee.getStart(sourceFile));
                    const line = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line;
                    const finding = { file: sourceFile.fileName, line: pos.line + 1, col: pos.character + 1, text: callee.getText(sourceFile) };
                    byLine.set(line, [...(byLine.get(line) || []), finding]);
                }
            }
            ts.forEachChild(node, visit);
        };
        visit(sourceFile);
        for (const [line, found] of byLine) {
            // One comment answers for one call: two flagged calls starting on a line are both reported, comment or not.
            const marked = ALLOW.test(lines[line] || '') || (line > 0 && ALLOW_ABOVE.test(lines[line - 1] || ''));
            if (!(marked && found.length === 1)) findings.push(...found);
        }
    }
    return findings.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line || a.col - b.col);
}

function loadProgram(configPath) {
    const config = ts.readConfigFile(configPath, ts.sys.readFile);
    if (config.error) throw new Error(ts.flattenDiagnosticMessageText(config.error.messageText, '\n'));
    const parsed = ts.parseJsonConfigFileContent(config.config, ts.sys, path.dirname(configPath));
    return ts.createProgram(parsed.fileNames, { ...parsed.options, noEmit: true });
}

function main(argv) {
    const root = path.resolve(__dirname, '..', '..');
    const configPath = path.resolve(root, argv[0] || 'tsconfig-tstl.json');
    const scopes = (argv.length > 1 ? argv.slice(1) : ['typescript/bots/FunLib/humaniser']).map((s) => path.resolve(root, s) + path.sep);
    const findings = findAnyCalls(loadProgram(configPath), (file) => scopes.some((s) => path.resolve(file).startsWith(s)));
    for (const f of findings) {
        console.error(`${path.relative(root, f.file)}(${f.line},${f.col}): error ANYCALL: '${f.text}(...)' has no declared signature (it is called through 'any'), so it compiles without a self argument. Declare the method on a typed interface, or mark a plain call with '// any-call-ok: <reason>'.`);
    }
    if (findings.length > 0) {
        console.error(`${findings.length} undeclared member call(s)`);
        process.exit(1);
    }
}

module.exports = { findAnyCalls };
if (require.main === module) main(process.argv.slice(2));

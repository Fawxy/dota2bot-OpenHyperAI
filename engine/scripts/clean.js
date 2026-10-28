// Removes the engine's build outputs: the test bundle (dist/), the bot's bundle and the declarations beside it.
// The hand-written typescript/bots/FunLib/engine/tasks.d.ts stays.
const fs = require('fs');
const path = require('path');

const pkg = path.resolve(__dirname, '..');
for (const p of ['dist', '../bots/FunLib/engine/tasks.lua', '../typescript/bots/FunLib/engine/decl']) {
    fs.rmSync(path.join(pkg, p), { recursive: true, force: true });
}

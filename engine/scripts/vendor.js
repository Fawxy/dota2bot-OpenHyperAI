// Copies the built bundle and declarations into a consuming project:
//   npm run vendor -- --lua <dir> --types <dir>
// Writes <lua>/tasks.lua, <lua>/VERSION, <types>/tasks.d.ts and <types>/decl/*, and records them in
// <lua>/.vendored so the next run can remove files it wrote that are no longer produced.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const pkg = path.resolve(__dirname, '..');
const dist = path.join(pkg, 'dist');
const bundle = path.join(dist, 'tasks.lua');
const declSrc = path.join(dist, 'types');
const MANIFEST = '.vendored';

function die(msg) {
    console.error('vendor: ' + msg);
    process.exit(1);
}

function parseArgs(argv) {
    const out = {};
    for (let i = 0; i < argv.length; i++) {
        const k = argv[i];
        if ((k === '--lua' || k === '--types') && argv[i + 1] !== undefined) out[k.slice(2)] = path.resolve(argv[++i]);
        else die(`unexpected argument '${k}'. usage: npm run vendor -- --lua <dir> --types <dir>`);
    }
    if (!out.lua || !out.types) die('usage: npm run vendor -- --lua <dir> --types <dir>');
    return out;
}

function git(args) {
    return execFileSync('git', args, { cwd: pkg, encoding: 'utf8' }).trim();
}

function listFiles(dir, rel = '') {
    const out = [];
    for (const e of fs.readdirSync(path.join(dir, rel), { withFileTypes: true })) {
        const r = rel === '' ? e.name : rel + '/' + e.name;
        if (e.isDirectory()) out.push(...listFiles(dir, r));
        else if (e.isFile()) out.push(r);
    }
    return out.sort();
}

// Manifest lines are "<root>\t<root dir relative to the lua dir>\t<path relative to root>". Entries whose root dir
// differs from this run's (e.g. a different --types) or that could escape their root are left alone.
function readManifest(file, dirs) {
    if (!fs.existsSync(file)) return [];
    return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map(line => {
        const [root, rootDir, rel] = line.split('\t');
        return { root, rootDir, rel };
    }).filter(e => (e.root === 'lua' || e.root === 'types') && e.rel
        && e.rootDir === rootRel(dirs, e.root)
        && !path.isAbsolute(e.rel) && !e.rel.split('/').includes('..'));
}

function rootRel(dirs, root) {
    return path.relative(dirs.lua, dirs[root]) || '.';
}

function pad(n) {
    return String(n).padStart(2, '0');
}

// dd/mm/yyyy HH:MM:SS in GMT+12, plus the ISO instant.
function buildDate(d) {
    const nz = new Date(d.getTime() + 12 * 3600 * 1000);
    const local = `${pad(nz.getUTCDate())}/${pad(nz.getUTCMonth() + 1)}/${nz.getUTCFullYear()} `
        + `${pad(nz.getUTCHours())}:${pad(nz.getUTCMinutes())}:${pad(nz.getUTCSeconds())} GMT+12`;
    return `${local} (${d.toISOString()})`;
}

const dirs = parseArgs(process.argv.slice(2));
if (!fs.existsSync(bundle)) die(`${path.relative(process.cwd(), bundle)} is missing; run npm run build first.`);
if (!fs.existsSync(path.join(declSrc, 'index.d.ts'))) die(`${path.relative(process.cwd(), declSrc)}/index.d.ts is missing; run npm run build first.`);

const dirty = git(['status', '--porcelain', '--', '.']) !== '';
const sha = git(['rev-parse', 'HEAD']) + (dirty ? '-dirty' : '');

const writes = [
    {
        root: 'lua', rel: 'tasks.lua',
        data: `-- Vendored from dota-bot-sdk packages/lua-tasks @ ${sha}. Do not edit; run npm run vendor.\n`
            + fs.readFileSync(bundle, 'utf8'),
    },
    {
        root: 'lua', rel: 'VERSION',
        data: `commit: ${sha}\nbuilt: ${buildDate(fs.statSync(bundle).mtime)}\n`,
    },
    {
        root: 'types', rel: 'tasks.d.ts',
        data: `// Vendored from dota-bot-sdk packages/lua-tasks @ ${sha}. Do not edit; run npm run vendor.\n`
            + 'export * from "./decl/index";\n',
    },
    ...listFiles(declSrc).map(rel => ({
        root: 'types', rel: 'decl/' + rel, data: fs.readFileSync(path.join(declSrc, rel)),
    })),
];

const manifestFile = path.join(dirs.lua, MANIFEST);
const key = e => e.root + '\t' + rootRel(dirs, e.root) + '\t' + e.rel;
const keep = new Set(writes.map(key));
for (const old of readManifest(manifestFile, dirs)) {
    if (keep.has(key(old))) continue;
    const file = path.join(dirs[old.root], old.rel);
    if (fs.existsSync(file)) {
        fs.unlinkSync(file);
        console.log('removed stale ' + file);
    }
}

for (const w of writes) {
    const file = path.join(dirs[w.root], w.rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, w.data);
}
fs.writeFileSync(manifestFile, writes.map(key).join('\n') + '\n');
console.log(`vendored ${sha}: ${writes.length} files -> ${dirs.lua}, ${dirs.types}`);

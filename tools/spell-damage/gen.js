#!/usr/bin/env node
// Generates typescript/bots/FunLib/humaniser/spell_damage_data.ts: for each hero ability that deals damage, the
// AbilityValues keys of its geometry (SPELL_SHAPE, shapeOf) and the key holding its damage (read live in game with GetSpecialValueFloat, so the level and patch are the
// game's), whether that value is per second, and its damage type. Source: the client's own game files
// (pak01_dir.vpk, scripts/npc/heroes/*.txt). Re-run after a patch:
//   node tools/spell-damage/gen.js [path/to/pak01_dir.vpk]
// The pick is a rule, not a hand table: "AbilityDamage" when non-zero, else a key named "damage", else the largest
// damage-named key; a name saying per second or tick marks it per second. Valve's estimate leaves many spells out (Meat
// Hook, Earth Spike, Shadowraze): only a spell coverage.json measures as counted (coverage.js) is written, so a spell
// never measured stays counted in game, the error on the safe side.
'use strict';
const fs = require('fs');
const path = require('path');

const DEFAULT_VPK = path.join(process.env.HOME, 'Library/Application Support/Steam/steamapps/common/dota 2 beta/game/dota/pak01_dir.vpk');
const OUT = path.join(__dirname, '../../typescript/bots/FunLib/humaniser/spell_damage_data.ts');
const COVERAGE = path.join(__dirname, 'coverage.json');

function readVpk(dirPath, prefix) {
    const base = dirPath.slice(0, -'_dir.vpk'.length);
    const buf = fs.readFileSync(dirPath);
    if (buf.readUInt32LE(0) !== 0x55aa1234) throw new Error('not a VPK');
    const version = buf.readUInt32LE(4);
    const treeSize = buf.readUInt32LE(8);
    const hdr = 12 + (version === 2 ? 16 : 0);
    let p = hdr;
    const cstr = () => {
        const end = buf.indexOf(0, p);
        const s = buf.toString('utf8', p, end);
        p = end + 1;
        return s;
    };
    const files = {};
    for (;;) {
        const ext = cstr();
        if (!ext) break;
        for (;;) {
            const dir = cstr();
            if (!dir) break;
            for (;;) {
                const name = cstr();
                if (!name) break;
                const pre = buf.readUInt16LE(p + 4);
                const arc = buf.readUInt16LE(p + 6);
                const off = buf.readUInt32LE(p + 8);
                const len = buf.readUInt32LE(p + 12);
                p += 18;
                const preload = buf.subarray(p, p + pre);
                p += pre;
                const full = dir === ' ' ? `${name}.${ext}` : `${dir}/${name}.${ext}`;
                if (!full.startsWith(prefix)) continue;
                let data;
                if (arc === 0x7fff) data = buf.subarray(hdr + treeSize + off, hdr + treeSize + off + len);
                else {
                    const fd = fs.openSync(`${base}_${String(arc).padStart(3, '0')}.vpk`, 'r');
                    data = Buffer.alloc(len);
                    fs.readSync(fd, data, 0, len, off);
                    fs.closeSync(fd);
                }
                files[full] = Buffer.concat([preload, data]).toString('utf8');
            }
        }
    }
    return files;
}

// KeyValues: nested objects, a repeated key keeps the last value.
function parseKv(text) {
    const re = /"((?:[^"\\]|\\.)*)"|(\{)|(\})|\/\/[^\n]*|([^\s{}"]+)/g;
    const stack = [{}];
    let key = null;
    let m;
    while ((m = re.exec(text))) {
        if (m[0].startsWith('//')) continue;
        if (m[2]) {
            const o = {};
            stack[stack.length - 1][key] = o;
            stack.push(o);
            key = null;
        } else if (m[3]) {
            stack.pop();
            key = null;
        } else {
            const tok = m[1] !== undefined ? m[1] : m[4];
            if (key === null) key = tok;
            else {
                stack[stack.length - 1][key] = tok;
                key = null;
            }
        }
    }
    return stack[0];
}

const DAMAGE = /damage/i;
// Damage-named keys that are not a hit's damage: modifiers, other units, conditions, timing.
const NOT_A_HIT = /bonus|pct|percent|reduction|amp|resist|block|threshold|radius|interval|duration|tooltip|creep|building|illusion|outgoing|incoming|scepter|shard|heal|return|lifesteal|_as_|armor|crit|mult|factor|chance|range|speed|cleave|count|delay|distance|min_|max_|_type|strength|agility|intel|passthrough|per_beam|per_stack|per_kill|per_charge|stack|buff|_tick_rate|tick_rate|self|talent|limit|cap|absorb|boost|per_mana|per_unit/i;
const PER_SECOND = /per_second|_dps|per_sec|burn_damage|rot_damage|tick_damage|damage_tick|sand_storm_damage/i;
const TYPES = { DAMAGE_TYPE_MAGICAL: 2, DAMAGE_TYPE_PHYSICAL: 1, DAMAGE_TYPE_PURE: 4 };

function valueOf(v) {
    const s = typeof v === 'object' && v !== null ? v.value : v;
    if (typeof s !== 'string') return 0;
    return Math.max(0, ...s.trim().split(/\s+/).map(Number).filter((x) => Number.isFinite(x)));
}

function pick(name, ab) {
    const behavior = ab.AbilityBehavior || '';
    if (behavior.includes('PASSIVE') || name.startsWith('special_bonus')) return undefined;
    const type = TYPES[(ab.AbilityUnitDamageType || '').trim()];
    if (type === undefined) return undefined;
    const vals = ab.AbilityValues || {};
    let key;
    if (valueOf(ab.AbilityDamage) > 0) key = 'AbilityDamage';
    else if (valueOf(vals.damage) > 0) key = 'damage';
    else {
        let best = 0;
        for (const k of Object.keys(vals)) {
            if (!DAMAGE.test(k) || NOT_A_HIT.test(k)) continue;
            const v = valueOf(vals[k]);
            if (v > best) {
                best = v;
                key = k;
            }
        }
    }
    if (key === undefined) return undefined;
    return { key, dot: PER_SECOND.test(key), type };
}

// Geometry (slice oha-spell-aim): where a point or no-target spell lands, as AbilityValues keys read live in game. Valve's AOE
// behaviour flag (a circle drawn at the target point) parts the point spells: with it an area at the point, without it a line
// from the caster (Fissure's and Ice Path's half widths are named radii). A no-target spell with a `<x>_range` beside its
// `<x>_radius` hits a circle that far in front of the caster (Shadowraze); else one around the caster. Unit-target spells get
// no row: the target fixes where they land.
const NOT_GEOMETRY = /vision|sight|aura|bonus|scepter|shard_distance|shard_push|pull|knockback|moved|echo|spine|inner|free_pathing|vector|reticle|application|search|spread|leash|slow|duration|stun|ally|heal|return|max_targets|tree|latch|attack|watch|break|min_|dead_zone|placement|self_|tooltip/i;
// The flag misleads for these: a wave travelling from the caster with an area drawn at its end.
const SHAPE_OVERRIDE = { venomancer_venomous_gale: 'l', shadow_demon_shadow_poison: 'l' };
// The rule picks the wrong key: Whirling Axes' hit radius is each axe's; the axes fly out to max_range around Troll.
const KEY_OVERRIDE = { troll_warlord_whirling_axes_melee: { radius: 'max_range' } };

function geomKey(vals, re, how) {
    let best;
    let bv;
    for (const k of Object.keys(vals)) {
        if (!re.test(k) || NOT_GEOMETRY.test(k) || k === 'AbilityCastRange') continue;
        const v = valueOf(vals[k]);
        if (!(v > 0)) continue;
        if (best === undefined || (how === 'min' ? v < bv : v > bv)) {
            best = k;
            bv = v;
        }
    }
    return best;
}

function shapeOf(name, ab) {
    const b = ab.AbilityBehavior || '';
    if (b.includes('UNIT_TARGET')) return undefined;
    const vals = ab.AbilityValues || {};
    const radius = geomKey(vals, /damage_radius/i) ?? geomKey(vals, /(^|_)(radius|aoe|area_of_effect)$/i, 'max');
    const r = radius === 'start_radius' || radius === 'end_radius' ? undefined : radius;
    const out = {};
    let k;
    if (b.includes('POINT')) {
        k = SHAPE_OVERRIDE[name] ?? (b.includes('_AOE') ? 'a' : 'l');
        if (k === 'a') {
            if (r !== undefined) out.radius = r;
            const spd = geomKey(vals, /^(speed|projectile_speed)$/i, 'max');
            if (spd !== undefined) out.speed = spd;
        } else {
            // The narrower end of a widening line or cone: the creep and the hero must both be inside it.
            const width = geomKey(vals, /width/i, 'min');
            const cone = vals.start_radius !== undefined && vals.end_radius !== undefined ? (valueOf(vals.start_radius) <= valueOf(vals.end_radius) ? 'start_radius' : 'end_radius') : undefined;
            if (width !== undefined) out.width = width;
            else if (cone !== undefined) out.half = cone;
            else if (r !== undefined) out.half = r;
            const spd = geomKey(vals, /speed$/i, 'max');
            if (spd !== undefined && !/move|turn|drag|multiplier|pullback/i.test(spd)) out.speed = spd;
            const len = geomKey(vals, /(^|_)(distance|length|range)$/i, 'max');
            if (len !== undefined && !/cast|stun/i.test(len)) out.length = len;
        }
    } else if (b.includes('NO_TARGET')) {
        const prefix = r !== undefined ? r.replace(/radius$/i, '') : undefined;
        if (prefix && vals[`${prefix}range`] !== undefined && valueOf(vals[`${prefix}range`]) > 0) {
            k = 'r';
            out.offset = `${prefix}range`;
        } else k = 's';
        if (r !== undefined) out.radius = r;
    } else return undefined;
    const delay = geomKey(vals, /delay/i, 'max');
    if (delay !== undefined && !/teleport|path|fade|formation|after/i.test(delay)) out.delay = delay;
    return { k, ...out, ...KEY_OVERRIDE[name] };
}

function main() {
    const vpk = process.argv[2] || DEFAULT_VPK;
    const files = readVpk(vpk, 'scripts/npc/heroes/');
    const cover = JSON.parse(fs.readFileSync(COVERAGE, 'utf8'));
    const rows = [];
    const added = [];
    const shapes = [];
    let damaging = 0;
    for (const [file, text] of Object.entries(files)) {
        if (!file.endsWith('.txt')) continue;
        const heroes = parseKv(text).DOTAHeroes || {};
        for (const hero of Object.values(heroes)) {
            if (typeof hero !== 'object') continue;
            for (const [name, ab] of Object.entries(hero.AbilityDefinitions || {})) {
                if (typeof ab !== 'object') continue;
                const r = pick(name, ab);
                if (r === undefined) continue;
                damaging++;
                const g = shapeOf(name, ab);
                if (g !== undefined) shapes.push([name, g]);
                const verdict = cover[name]?.verdict;
                if (verdict === 'counted') rows.push([name, r]);
                else added.push([name, r, verdict === 'left_out' ? 'left_out' : 'unknown']);
            }
        }
    }
    rows.sort((a, b) => (a[0] < b[0] ? -1 : 1));
    added.sort((a, b) => (a[0] < b[0] ? -1 : 1));
    shapes.sort((a, b) => (a[0] < b[0] ? -1 : 1));
    const steam = fs.readFileSync(path.join(path.dirname(vpk), 'steam.inf'), 'utf8').match(/ClientVersion=(\d+)/);
    const lines = [
        '// Generated by tools/spell-damage/gen.js from the game files (client ' + (steam ? steam[1] : '?') + '); do not edit.',
        '/** Per ability Valve\'s estimate is measured to count: the AbilityValues key of its damage, whether it is per second, and its DamageType. */',
        'export const SPELL_DAMAGE: Record<string, [key: string, perSecond: boolean, damageType: number]> = {',
        ...rows.map(([n, r]) => `    ${n}: [${JSON.stringify(r.key)}, ${r.dot}, ${r.type}],`),
        '};',
        '',
        '/** Per damaging ability Valve\'s estimate is measured to leave out (left_out) or has never been measured (unknown): the same key, per-second flag and DamageType as SPELL_DAMAGE, and the status. A multi-hit or over-time spell whose key is a per-hit or per-tick value is counted once. An unknown spell may be one Valve\'s estimate already counts, so it can be counted twice until coverage.js measures it (of the nukes measured so far the estimate counts about two in three). */',
        'export const SPELL_ADDED: Record<string, [key: string, perSecond: boolean, damageType: number, status: "left_out" | "unknown"]> = {',
        ...added.map(([n, r, st]) => `    ${n}: [${JSON.stringify(r.key)}, ${r.dot}, ${r.type}, ${JSON.stringify(st)}],`),
        '};',
        '',
        '/** Per damaging point or no-target ability, where it lands (gen.js shapeOf): `k` an area at the point (`a`), a line from the caster (`l`), a circle `offset` in front of the caster (`r`) or around it (`s`); each other field the AbilityValues key of that number (`width` a full width, `half` a half width). */',
        'export const SPELL_SHAPE: Record<string, { k: "a" | "l" | "r" | "s"; radius?: string; width?: string; half?: string; length?: string; speed?: string; delay?: string; offset?: string }> = {',
        ...shapes.map(([n, g]) => `    ${n}: { ${Object.entries(g).map(([k, v]) => `${k}: ${JSON.stringify(v)}`).join(', ')} },`),
        '};',
        '',
    ];
    fs.writeFileSync(OUT, lines.join('\n'));
    const missing = Object.keys(cover).filter((n) => cover[n].verdict === 'counted' && !rows.some((r) => r[0] === n));
    // Such a spell (Enchant Totem: a percentage on the next attack) stays counted in game, the safe side.
    if (missing.length) console.log(`counted but no damage key, left in the estimate: ${missing.join(', ')}`);
    console.log(`${rows.length} measured as counted, ${added.length} added (${added.filter((a) => a[2] === 'left_out').length} left_out) of ${damaging} damaging abilities; wrote ${path.relative(process.cwd(), OUT)}`);
}

main();

#!/usr/bin/env node
// Generates typescript/bots/FunLib/humaniser/spell_damage_data.ts: for each hero ability that deals damage, the
// AbilityValues key holding its damage (read live in game with GetSpecialValueFloat, so the level and patch are the
// game's), whether that value is per second, and its damage type. Source: the client's own game files
// (pak01_dir.vpk, scripts/npc/heroes/*.txt). Re-run after a patch:
//   node tools/spell-damage/gen.js [path/to/pak01_dir.vpk]
// The pick is a rule, not a hand table: "AbilityDamage" when non-zero, else a key named "damage", else the largest
// damage-named key; a name saying per second or tick marks it per second. Checked against Valve's own estimate in probe
// game probe_cd1 (17/11/2026).
'use strict';
const fs = require('fs');
const path = require('path');

const DEFAULT_VPK = path.join(process.env.HOME, 'Library/Application Support/Steam/steamapps/common/dota 2 beta/game/dota/pak01_dir.vpk');
const OUT = path.join(__dirname, '../../typescript/bots/FunLib/humaniser/spell_damage_data.ts');

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
const NOT_A_HIT = /bonus|pct|percent|reduction|amp|resist|block|threshold|radius|interval|duration|tooltip|creep|building|illusion|outgoing|incoming|scepter|shard|heal|return|lifesteal|_as_|armor|crit|mult|factor|chance|range|speed|cleave|count|delay|distance|min_|max_|_type|strength|agility|intel|passthrough|per_beam|per_stack|per_kill|per_charge|stack|buff|_tick_rate|tick_rate|self/i;
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

function main() {
    const vpk = process.argv[2] || DEFAULT_VPK;
    const files = readVpk(vpk, 'scripts/npc/heroes/');
    const rows = [];
    let actives = 0;
    for (const [file, text] of Object.entries(files)) {
        if (!file.endsWith('.txt')) continue;
        const heroes = parseKv(text).DOTAHeroes || {};
        for (const hero of Object.values(heroes)) {
            if (typeof hero !== 'object') continue;
            for (const [name, ab] of Object.entries(hero.AbilityDefinitions || {})) {
                if (typeof ab !== 'object') continue;
                if (!(ab.AbilityBehavior || '').includes('PASSIVE')) actives++;
                const r = pick(name, ab);
                if (r) rows.push([name, r]);
            }
        }
    }
    rows.sort((a, b) => (a[0] < b[0] ? -1 : 1));
    const steam = fs.readFileSync(path.join(path.dirname(vpk), 'steam.inf'), 'utf8').match(/ClientVersion=(\d+)/);
    const lines = [
        '// Generated by tools/spell-damage/gen.js from the game files (client ' + (steam ? steam[1] : '?') + '); do not edit.',
        '/** Per ability: the AbilityValues key of its damage, whether it is per second, and its DamageType. */',
        'export const SPELL_DAMAGE: Record<string, [key: string, perSecond: boolean, damageType: number]> = {',
        ...rows.map(([n, r]) => `    ${n}: [${JSON.stringify(r.key)}, ${r.dot}, ${r.type}],`),
        '};',
        '',
    ];
    fs.writeFileSync(OUT, lines.join('\n'));
    console.log(`${rows.length} damaging abilities of ${actives} non-passive; wrote ${path.relative(process.cwd(), OUT)}`);
}

main();

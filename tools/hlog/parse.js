// Parses a Dota console.log into games of humaniser telemetry ([HEV] lines written by telemetry.ts).
'use strict';

const FIELD_RE = /(\w+)=("([^"]*)"|\S+)/g;
const NUMBER_RE = /^-?\d+(\.\d+)?$/;
// Text fields that can look numeric: an all-digit git sha ("0123456") must not lose its leading zero.
const STRING_KEYS = new Set(['build', 'text', 'msg']);
// Lua runtime errors as the Dota console prints them; exact wording varies by build, so match loosely.
const ERROR_RE = /script runtime error|stack traceback|attempt to (index|call|perform arithmetic|compare|concatenate)|\.lua:\d+: /i;
// Dota stops printing a repeated message after 10 copies.
const SQUELCH_RE = /\[VScript\] Message count limit of \d+ hit/;
const CONSOLE_PREFIX = /^\d\d\/\d\d \d\d:\d\d:\d\d (\[VScript\] )?/;
// A new lobby restarts the game clock; interleaved VMs only ever disagree by a frame or two.
const GAME_SPLIT_REGRESSION = 30;
// Events every module instance emits once per team; they repeat when modules are not shared between bots.
const TEAM_WIDE = new Set(['order_post', 'ping', 'cmd', 'mark']);
const TEAM_WIDE_WINDOW = 1.0;

function parseFields(text) {
    const out = {};
    for (const m of text.matchAll(FIELD_RE)) {
        const raw = m[3] !== undefined ? m[3] : m[2];
        out[m[1]] = m[3] === undefined && !STRING_KEYS.has(m[1]) && NUMBER_RE.test(raw) ? Number(raw) : raw;
    }
    return out;
}

/** One console line -> { line: 'event' | 'start' | 'summary' | 'error', ... } or undefined. Events keep their fields in `e`. */
function parseLine(line) {
    const hev = line.indexOf('[HEV] ');
    if (hev >= 0) {
        const f = parseFields(line.slice(hev + 6));
        if (typeof f.t !== 'number' || typeof f.ev !== 'string') return undefined;
        return { line: 'event', e: f };
    }
    const start = line.indexOf('[Humaniser] pid=');
    if (start >= 0) {
        const rest = line.slice(start + 12);
        const f = parseFields(rest);
        const hero = (rest.match(/^pid=\d+ (\S+)/) || [])[1];
        return { line: 'start', pid: f.pid, hero, allyOfHuman: f.allyOfHuman === 'true', skill: f.skill };
    }
    const summary = line.indexOf('[H:intent] summary ');
    if (summary >= 0) return { line: 'summary', ...parseFields(line.slice(summary + 19)) };
    if (ERROR_RE.test(line) && !line.includes('[H:')) return { line: 'error', text: line.replace(CONSOLE_PREFIX, '').trim() };
    if (SQUELCH_RE.test(line)) return { line: 'squelch' };
    return undefined;
}

function sameExceptTime(a, b) {
    const ka = Object.keys(a).filter(k => k !== 't');
    const kb = Object.keys(b).filter(k => k !== 't');
    if (ka.length !== kb.length) return false;
    return ka.every(k => a[k] === b[k]);
}

function newGame(index) {
    return { index, events: [], errors: [], squelched: false, squelches: 0, starts: {}, summaries: [], maxT: -Infinity, minT: Infinity };
}

function dedupe(game) {
    const kept = [];
    const recent = [];
    for (const e of game.events) {
        if (!TEAM_WIDE.has(e.ev)) {
            kept.push(e);
            continue;
        }
        // Each team's VMs see the other team's all-chat too, so marks repeat across teams as well.
        const dup = recent.find(r => {
            if (r.ev !== e.ev || Math.abs(r.t - e.t) > TEAM_WIDE_WINDOW) return false;
            if (e.ev === 'order_post') return r.team === e.team && r.src === e.src;
            if (e.ev === 'mark') return r.by === e.by && r.text === e.text;
            return sameExceptTime(r, e);
        });
        if (dup) continue;
        recent.push(e);
        while (recent.length > 0 && e.t - recent[0].t > TEAM_WIDE_WINDOW) recent.shift();
        kept.push(e);
    }
    game.events = kept;
}

function buildModel(game) {
    dedupe(game);
    const bots = {};
    const ensure = pid => (bots[pid] = bots[pid] || { pid, profiles: [], snaps: [], human: false });
    let markNo = 0;
    game.marks = [];
    for (const e of game.events) {
        if (e.pid !== undefined && (e.ev === 'bot' || e.ev === 'player' || e.ev === 'snap')) {
            const b = ensure(e.pid);
            if (e.ev === 'bot') {
                b.hero = e.hero;
                b.team = e.team;
                b.profiles.push(e);
                if (e.ally !== undefined) b.allyOfHuman = e.ally === 1;
            } else if (e.ev === 'player') {
                b.hero = e.hero;
                b.team = e.team;
                b.human = true;
            } else b.snaps.push(e);
        }
        if (e.ev === 'mark') {
            markNo++;
            game.marks.push({ ...e, n: markNo });
        }
    }
    for (const [pid, s] of Object.entries(game.starts)) {
        const b = ensure(Number(pid));
        if (b.allyOfHuman === undefined) b.allyOfHuman = s.allyOfHuman;
        if (!b.hero) b.hero = (s.hero || '').replace('npc_dota_hero_', '');
    }
    game.bots = bots;
    game.ended = game.events.some(e => e.ev === 'game_end');
    return game;
}

/** Splits console text into games (oldest first), each with deduplicated events and a per-player model. */
function parseLog(text) {
    const games = [];
    let game;
    for (const line of text.split(/\r?\n/)) {
        const p = parseLine(line);
        if (p === undefined) continue;
        if (p.line === 'event') {
            const e = p.e;
            if (game === undefined || e.t < game.maxT - GAME_SPLIT_REGRESSION) {
                game = newGame(games.length + 1);
                games.push(game);
            }
            game.events.push(e);
            game.maxT = Math.max(game.maxT, e.t);
            game.minT = Math.min(game.minT, e.t);
            continue;
        }
        if (game === undefined) {
            game = newGame(games.length + 1);
            games.push(game);
        }
        if (p.line === 'start') {
            // A start line after events means a new lobby whose first [HEV] line has not arrived yet.
            if (game.events.length > 0 && game.starts[p.pid] !== undefined) {
                game = newGame(games.length + 1);
                games.push(game);
            }
            game.starts[p.pid] = p;
        } else if (p.line === 'summary') game.summaries.push(p);
        else if (p.line === 'squelch') {
            game.squelched = true;
            game.squelches++;
        }
        else game.errors.push({ text: p.text, t: game.maxT });
    }
    return games.filter(g => g.events.length > 0 || g.errors.length > 0).map((g, i) => buildModel({ ...g, index: i + 1 }));
}

module.exports = { parseLine, parseFields, parseLog };

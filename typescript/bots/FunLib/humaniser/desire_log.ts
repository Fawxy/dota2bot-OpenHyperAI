/**
 * The desire each gated mode's own GetDesire last returned (Chooser.Gate notes it), for the snapshot's `by` and
 * `competing` fields. Logging only: nothing reads it to decide.
 */
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as HDebug from "bots/FunLib/humaniser/debug";

/** A sample older than this is not this frame's: the mode's desire is then Valve's own, which cannot be read. */
const FRESH = 0.5;

/** The gate's mode name -> the BotMode the active mode reads as; a mode with no BotMode in this build is not sampled. */
const BOT_MODE: Record<string, number | undefined> = {
    laning: BotMode.Laning,
    attack: BotMode.Attack,
    retreat: BotMode.Retreat,
    farm: BotMode.Farm,
    team_roam: BotMode.TeamRoam,
    roam: BotMode.Roam,
    rune: BotMode.Rune,
    ward: BotMode.Ward,
    assemble: BotMode.Assemble,
    defend_tower_top: BotMode.DefendTowerTop,
    defend_tower_mid: BotMode.DefendTowerMid,
    defend_tower_bot: BotMode.DefendTowerBot,
    push_tower_top: BotMode.PushTowerTop,
    push_tower_mid: BotMode.PushTowerMid,
    push_tower_bot: BotMode.PushTowerBot,
    roshan: BotMode.Roshan,
    secret_shop: BotMode.SecretShop,
    side_shop: BotMode.SideShop,
};

interface Sample {
    value: number;
    time: number;
}

const samples: Record<number, Record<number, Sample>> = {};

export function Note(bot: Unit, mode: string, value: any): void {
    const m = BOT_MODE[mode];
    if (m === undefined || type(value) !== "number" || bot.IsIllusion()) return;
    const pid = bot.GetPlayerID();
    let s = samples[pid];
    if (s === undefined) {
        s = {};
        samples[pid] = s;
    }
    const sample = s[m];
    if (sample === undefined) s[m] = { value, time: GameTime() };
    else {
        sample.value = value;
        sample.time = GameTime();
    }
}

/** "<mode> <desire> by raw", or "<mode> (valve)" for a mode whose own code was not asked just now. */
export function Explain(bot: Unit, mode: number): string {
    const sample = samples[bot.GetPlayerID()]?.[mode];
    if (sample === undefined || GameTime() - sample.time > FRESH) return `${HDebug.ModeName(mode)} (valve)`;
    return `${HDebug.ModeName(mode)} ${string.format("%.2f", sample.value)} by raw`;
}

/** The freshest desires, highest first, at most four: "farm=0.62 laning=0.40". */
export function Competing(bot: Unit): string {
    const s = samples[bot.GetPlayerID()];
    if (s === undefined) return "";
    const now = GameTime();
    const fresh: [number, number][] = [];
    for (const [mode, sample] of pairs(s)) {
        if (now - sample.time <= FRESH) fresh.push([mode, sample.value]);
    }
    fresh.sort((a, b) => b[1] - a[1]);
    const parts: string[] = [];
    for (let i = 0; i < fresh.length && i < 4; i++) parts.push(`${HDebug.ModeName(fresh[i][0])}=${string.format("%.2f", fresh[i][1])}`);
    return parts.join(" ");
}

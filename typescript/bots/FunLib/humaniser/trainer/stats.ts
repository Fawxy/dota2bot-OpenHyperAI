import { JudgeEvent, Verdict } from "bots/FunLib/humaniser/trainer/judge";
import { Sec, Signed } from "bots/FunLib/humaniser/trainer/format";

const MIN_TAKEABLE = 10;
const ON_TIME = 0.03;
const SPLIT_MIN_OFFSETS = 3;
const SPLIT_MIN_DIFF = 0.05;
const HARASS_MIN_GROUP = 5;
const HARASS_LINE_GAP = 15;
const HARASS_LEAK_GAP = 20;
const BIAS_MIN_MEAN = 0.06;
const BIAS_MIN_SHARE = 0.2;
const NO_SWING_MIN = 3;
const KIND_SHARE = 0.6;
const DENY_MIN = 5;
const DENY_MAX_RATE = 0.3;
const ADJ_STEP = 0.05;

interface Rule {
    cost: number;
    line: string;
}

function Pct(s: number, t: number): number {
    return t === 0 ? 0 : math.floor((100 * s) / t + 0.5);
}

function IsSuccess(v: Verdict): boolean {
    return v.kind === "PERFECT" || v.kind === "OK";
}

function Mean(xs: number[]): number {
    let sum = 0;
    for (const x of xs) sum += x;
    return sum / xs.length;
}

function Median(xs: number[]): number {
    const sorted = [...xs];
    sorted.sort((a, b) => a - b);
    const n = sorted.length;
    const mid = math.floor(n / 2);
    return n % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function Direction(avg: number): string {
    if (math.abs(avg) < ON_TIME) return "fine";
    return avg < 0 ? "early" : "late";
}

export class Stats {
    private takeable: Verdict[] = [];
    private gotIt: Record<string, boolean> = {};

    Add(e: JudgeEvent): void {
        if (e.type === "outcome") {
            this.gotIt[e.creepId] = e.subjectGotIt;
        } else if (e.v.kind !== "CANCELLED") {
            this.takeable.push(e.v);
        }
    }

    Reset(): void {
        this.takeable = [];
        this.gotIt = {};
    }

    Lines(o: { outcomeOnly: boolean; denies: boolean }): string[] {
        const lines = [this.scoreLine(o.denies), this.timingLine(o.outcomeOnly), this.Leak(o.denies)];
        const harass = this.harassLine();
        if (harass !== undefined) lines.push(harass);
        return lines;
    }

    SelfTestLine(): string {
        const t = this.takeable.length;
        const s = this.takeable.filter((v) => IsSuccess(v)).length;
        return `selftest: ${s}/${t} PERFECT+OK (${Pct(s, t)}%) - easy misses ${this.count((v) => v.kind === "MISSED_EASY")} of ${t} reachable`;
    }

    Leak(denies: boolean): string {
        if (this.takeable.length < MIN_TAKEABLE) return "not enough data yet";

        const rules: Rule[] = [];
        const add = (r: Rule | undefined) => {
            if (r !== undefined) rules.push(r);
        };
        add(this.noSwingRule());
        add(this.lateRule());
        add(this.earlyRule());
        add(this.harassRule());
        if (denies) add(this.denyRule());
        let best: Rule | undefined = undefined;
        for (const r of rules) {
            if (best === undefined || r.cost > best.cost) best = r;
        }
        return best === undefined ? "no clear leak - keep going" : best.line;
    }

    private count(pred: (v: Verdict) => boolean): number {
        return this.takeable.filter((v) => pred(v)).length;
    }

    private scoreLine(denies: boolean): string {
        const lh = this.takeable.filter((v) => !v.isDeny);
        const dn = this.takeable.filter((v) => v.isDeny);
        const lhOk = lh.filter((v) => IsSuccess(v)).length;
        let line = `LH ${lhOk}/${lh.length} (${Pct(lhOk, lh.length)}%)`;
        if (denies) line += ` - denies ${dn.filter((v) => IsSuccess(v)).length}/${dn.length}`;
        return `${line} - easy misses ${this.count((v) => v.kind === "MISSED_EASY")}`;
    }

    /** Offsets of PERFECT, OK, EARLY, LATE and late MISSED_EASY verdicts. */
    private offsets(filter?: (v: Verdict) => boolean): number[] {
        const out: number[] = [];
        for (const v of this.takeable) {
            if (v.offset === undefined || !v.swung) continue;
            if (filter !== undefined && !filter(v)) continue;
            out.push(v.offset);
        }
        return out;
    }

    private isLate(v: Verdict): boolean {
        return v.kind === "LATE" || (v.kind === "MISSED_EASY" && v.swung);
    }

    private timingLine(outcomeOnly: boolean): string {
        if (outcomeOnly) {
            const early = this.count((v) => v.kind === "EARLY");
            return `early ${early} - late ${this.count((v) => this.isLate(v))} (no timing detail)`;
        }

        const offsets = this.offsets();
        if (offsets.length === 0) return "no timing data yet";
        const mean = Mean(offsets);
        const median = `(median ${Signed(Median(offsets))}s)`;
        let line =
            math.abs(mean) < ON_TIME
                ? `you start on time on average ${median}`
                : `you start ${Sec(mean)}s ${mean < 0 ? "early" : "late"} on average ${median}`;

        const ranged = this.offsets((v) => v.creepKind === "ranged");
        const melee = this.offsets((v) => v.creepKind === "melee");
        if (ranged.length >= SPLIT_MIN_OFFSETS && melee.length >= SPLIT_MIN_OFFSETS) {
            const r = Mean(ranged);
            const m = Mean(melee);
            if (math.abs(r - m) > SPLIT_MIN_DIFF) {
                line += `; ${Direction(r)} on ranged (${Signed(r)}s), ${Direction(m)} on melee (${Signed(m)}s)`;
            }
        }
        return line;
    }

    private group(harassed: boolean): { t: number; s: number } {
        const g = this.takeable.filter((v) => v.harassed === harassed);
        return { t: g.length, s: g.filter((v) => IsSuccess(v)).length };
    }

    private harassGap(): { harassed: { t: number; s: number }; free: { t: number; s: number }; gap: number } | undefined {
        const harassed = this.group(true);
        const free = this.group(false);
        if (harassed.t < HARASS_MIN_GROUP || free.t < HARASS_MIN_GROUP) return undefined;
        return { harassed, free, gap: (100 * free.s) / free.t - (100 * harassed.s) / harassed.t };
    }

    private harassLine(): string | undefined {
        const g = this.harassGap();
        if (g === undefined || math.abs(g.gap) < HARASS_LINE_GAP) return undefined;
        return `under harass ${Pct(g.harassed.s, g.harassed.t)}% vs ${Pct(g.free.s, g.free.t)}% free`;
    }

    private noSwingRule(): Rule | undefined {
        const misses = this.takeable.filter((v) => v.kind === "MISSED_EASY" && !v.swung);
        if (misses.length < NO_SWING_MIN) return undefined;

        let suffix = ". Watch every creep near you, not just your target.";
        const kinds: [string, string][] = [
            ["ranged", ", mostly ranged. Watch the backline."],
            ["melee", ", mostly melee. Watch the front line."],
            ["siege", ", mostly siege. Watch the catapult."],
        ];
        for (const [kind, text] of kinds) {
            if (misses.filter((v) => v.creepKind === kind).length >= KIND_SHARE * misses.length) {
                suffix = text;
                break;
            }
        }
        return { cost: misses.length, line: `${misses.length} easy creeps lost with no swing${suffix}` };
    }

    private attempts(): number {
        return this.count((v) => v.swung);
    }

    private adjustment(mean: number): string {
        return Sec(math.max(ADJ_STEP, math.floor(math.abs(mean) / ADJ_STEP + 0.5) * ADJ_STEP));
    }

    private lateRule(): Rule | undefined {
        const offsets = this.offsets();
        if (offsets.length === 0) return undefined;
        const mean = Mean(offsets);
        const late = this.count((v) => this.isLate(v));
        if (mean < BIAS_MIN_MEAN || late < BIAS_MIN_SHARE * this.attempts()) return undefined;
        return { cost: late, line: `you're late: start your swing about ${this.adjustment(mean)}s sooner` };
    }

    private earlyRule(): Rule | undefined {
        const offsets = this.offsets();
        if (offsets.length === 0) return undefined;
        const mean = Mean(offsets);
        const early = this.takeable.filter((v) => v.kind === "EARLY");
        if (mean > -BIAS_MIN_MEAN || early.length < BIAS_MIN_SHARE * this.attempts()) return undefined;
        const lost = early.filter((v) => this.gotIt[v.creepId] === false).length;
        return { cost: lost, line: `you're early: wait about ${this.adjustment(mean)}s longer before swinging` };
    }

    private harassRule(): Rule | undefined {
        const g = this.harassGap();
        if (g === undefined || g.gap < HARASS_LEAK_GAP) return undefined;
        return {
            cost: math.floor((g.gap / 100) * g.harassed.t + 0.5),
            line: "you lose timing when hit: back off or swing earlier under pressure",
        };
    }

    private denyRule(): Rule | undefined {
        const dn = this.takeable.filter((v) => v.isDeny);
        const ok = dn.filter((v) => IsSuccess(v)).length;
        if (dn.length < DENY_MIN || ok >= DENY_MAX_RATE * dn.length) return undefined;
        return { cost: dn.length - ok, line: `denies ${ok}/${dn.length}: check allied creeps under half HP` };
    }
}

/**
 * OHA integration for the vendored lua-tasks runner (bots/FunLib/sdk/tasks, from dota-bot-sdk).
 *
 * The bundle is required lazily under pcall, only once the humaniser and Tasks.Enable are on: a static require
 * would let a bundle that fails to load in Dota's VM break the whole humaniser module, even with Enable = false.
 * Claims go through Intent without `until`, so ClaimTTL applies and a task that stops stepping loses its claim.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as AllyLastHit from "bots/FunLib/humaniser/ally_last_hit";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Utils from "bots/FunLib/utils";

type Bundle = typeof Lib;

let attempted = false;
let lib: Bundle | undefined;

export function Enabled(): boolean {
    return Config.IsEnabled() && Config.Get().Tasks.Enable !== false;
}

const adapter: Lib.Adapter = {
    claim: (bot, c) =>
        Intent.Claim(bot as unknown as Unit, {
            source: c.source,
            tier: c.tier as Intent.Tier,
            mode: c.mode as BotMode,
            floor: c.floor,
            unsticks: c.urgent === true ? true : undefined,
        }),
    release: (bot, source, mode) => Intent.Release(bot as unknown as Unit, source, mode as BotMode),
    hold: (bot, tag) => Intent.Hold(bot as unknown as Unit, tag),
    lastHitFilter: (bot, creep) => {
        const [allowed] = AllyLastHit.MayLastHit(bot as unknown as Unit, creep);
        return allowed;
    },
    // DotaTime, the clock camp-job plans are timed in; the runner and verbs only ever use differences of it.
    now: () => DotaTime(),
    log: (tag, msg) => HDebug.Log(tag, msg),
    event: (name, fields) => Telemetry.Event(name, fields as [string, any][]),
    vector: (x, y, z) => Vector(x, y, z),
    enabled: () => Enabled(),
};

function loadBundle(): Bundle | undefined {
    if (!Enabled()) return undefined;
    if (attempted) return lib;
    attempted = true;
    const [ok, res] = pcall(require, GetScriptDirectory() + "/FunLib/sdk/tasks/tasks");
    const support = `[H:tasks] support coroutine=${type(coroutine)} bundle=`;
    // Always printed (not gated on Debug): the first in-game check is whether the bundle loads at all.
    const rawPrint: ((s: string) => void) | undefined = (Utils as any).RawPrint;
    if (ok && type(res) === "table") {
        lib = res as Bundle;
        lib.init(adapter);
        (rawPrint ?? print)(support + "ok");
    } else {
        (rawPrint ?? print)(`${support}fail ${tostring(res)}`);
    }
    return lib;
}

/** The loaded bundle (loading it on first use), or undefined when tasks are off or it failed to load. */
export function Loaded(): Bundle | undefined {
    return loadBundle();
}

/** True once the bundle has loaded and tasks are enabled. */
export function IsActive(): boolean {
    return lib !== undefined && Enabled();
}

export function Start(bot: Unit, opts: Lib.TaskOptions, body: (this: void) => Lib.TaskBody): boolean {
    const l = loadBundle();
    return l !== undefined && l.Tasks.task(bot as unknown as Lib.TaskUnit, opts, body);
}

/** Call from the host mode's Think(); returns false when no task of this bot runs under `mode`. */
export function Step(bot: Unit, mode: number): boolean {
    const l = loadBundle();
    return l !== undefined && l.Tasks.Step(bot as unknown as Lib.TaskUnit, mode);
}

export function Tick(bot: Unit): void {
    loadBundle()?.Tasks.Tick(bot as unknown as Lib.TaskUnit);
}

/** Never loads the bundle: no task can be running before one was started. */
export function Current(bot: Unit): ReturnType<Bundle["Tasks"]["Current"]> {
    return IsActive() ? lib!.Tasks.Current(bot as unknown as Lib.TaskUnit) : undefined;
}

export function Cancel(bot: Unit, reason: Lib.Reason, message?: string): void {
    if (IsActive()) lib!.Tasks.Cancel(bot as unknown as Lib.TaskUnit, reason, message);
}

export function Urgent(bot: Unit, on: boolean): void {
    lib?.Tasks.Urgent(bot as unknown as Lib.TaskUnit, on);
}

export function Label(bot: Unit, label: string): void {
    lib?.Tasks.Label(bot as unknown as Lib.TaskUnit, label);
}

export function Describe(bot: Unit): string | undefined {
    return loadBundle()?.Tasks.Describe(bot as unknown as Lib.TaskUnit);
}

export function Verbs(): Bundle["Verbs"] | undefined {
    return loadBundle()?.Verbs;
}

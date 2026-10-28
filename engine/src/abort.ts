import { Reason, Result, TaskBody } from "./types";

// Identity of the thrown table, so a host error that happens to carry a `result` field is never mistaken for one.
const TAG = {};

interface Thrown {
    tag: object;
    result: Result;
}

/** Ends the running task with `result` from any generator depth; the runner finishes it as if returned. */
export function abortWith(this: void, result: Result): never {
    const thrown: Thrown = { tag: TAG, result };
    error(thrown as unknown as string, 0);
}

export function abort(this: void, reason: Reason, message?: string): never {
    return abortWith({ success: false, reason, message });
}

/** The carried result if `err` was raised by `abort`/`must`, else undefined. */
export function aborted(this: void, err: unknown): Result | undefined {
    if (type(err) !== "table") return undefined;
    const t = err as Thrown;
    return rawequal(t.tag, TAG) ? t.result : undefined;
}

/**
 * Runs `g` and returns its result if it succeeded; a failure ends the whole task with that result, its message
 * replaced by `message` when given.
 */
export function* must(this: void, g: TaskBody, message?: string): TaskBody {
    const r = yield* g;
    if (r === undefined) return { success: true, reason: "ok" };
    if (!r.success) abortWith(message === undefined ? r : { success: false, reason: r.reason, message });
    return r;
}

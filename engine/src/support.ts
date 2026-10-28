/** True iff the VM exposes a usable `coroutine` library (generators compile to coroutines). */
export function Supported(): boolean {
    const co = rawget(_G, "coroutine") as unknown;
    if (type(co) !== "table") return false;
    const t = co as Record<string, unknown>;
    return (
        type(t.create) === "function" &&
        type(t.resume) === "function" &&
        type(t.status) === "function" &&
        type(t.yield) === "function"
    );
}

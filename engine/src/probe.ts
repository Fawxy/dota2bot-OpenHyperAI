export function* inner(): Generator<void, number, unknown> {
    yield;
    yield;
    return 10;
}

export function* middle(): Generator<void, number, unknown> {
    const v = yield* inner();
    yield;
    return v + 5;
}

/** Three levels deep: 2 (inner) + 1 (middle) + 1 (outer) = 4 yields, returns (10 + 5) * 2 = 30. */
export function* outer(): Generator<void, number, unknown> {
    const v = yield* middle();
    yield;
    return v * 2;
}

/** Yields the running counter each step; returns the final count. */
export function* counter(n: number): Generator<number, number, unknown> {
    let count = 0;
    for (let i = 0; i < n; i++) {
        count += 1;
        yield count;
    }
    return count;
}

/**
 * Yields from inside an explicit `pcall`. Whether this works depends on the runtime
 * (stock Lua 5.1 forbids yielding across pcall; LuaJIT and Lua 5.2+ allow it).
 * Returns pcall's (ok, err) so the caller can report the behaviour.
 */
export function* yieldInPcall(): Generator<void, [boolean, string | undefined], unknown> {
    const [ok, res] = pcall(() => {
        coroutine.yield();
        return "inside";
    });
    return [ok, ok ? undefined : (res as string)];
}

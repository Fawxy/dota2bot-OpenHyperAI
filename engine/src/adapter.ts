import { Adapter } from "./types";

let current: Adapter | undefined;

/** Host integration: the host injects claims, etiquette, time, logging and the kill switch here. */
export function init(a: Adapter): void {
    current = a;
}

export function get(): Adapter | undefined {
    return current;
}

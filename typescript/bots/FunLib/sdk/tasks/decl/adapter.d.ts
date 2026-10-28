/** @noSelfInFile */
import { Adapter } from "./types";
/** Host integration: the host injects claims, etiquette, time, logging and the kill switch here. */
export declare function init(a: Adapter): void;
export declare function get(): Adapter | undefined;

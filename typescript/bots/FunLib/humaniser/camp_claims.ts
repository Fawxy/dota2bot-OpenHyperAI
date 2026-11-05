/**
 * Which hero's job is on which camp, so the two jobs that can meet on a pulled camp see each other without importing one
 * another: a core's trip (`core`, CoreCamp) and the support clearing its own pull (`pullfarm`, PullFarm). The support gives the
 * camp up to a core that comes; a core may price a pulled camp only while the support is on it.
 */
export type Kind = "core" | "pullfarm";

const claims: Record<string, Record<number, number | undefined>> = { core: {}, pullfarm: {} };

export function Set(kind: Kind, pid: number, camp: number | undefined): void {
    claims[kind][pid] = camp;
}

/** The pid of another hero whose `kind` job is on `camp`, if any. */
export function On(kind: Kind, camp: number, exceptPid?: number): number | undefined {
    for (const [pid, c] of pairs(claims[kind])) if (c === camp && pid !== exceptPid) return pid as number;
    return undefined;
}

export function ResetCache(): void {
    for (const k of ["core", "pullfarm"]) for (const [pid] of pairs(claims[k])) delete claims[k][pid as number];
}

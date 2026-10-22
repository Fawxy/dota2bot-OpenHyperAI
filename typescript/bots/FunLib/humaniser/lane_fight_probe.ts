/**
 * Lane fight probe (task 11, spike). `!hfight` dumps the nearest visible enemy's ability handles and installs
 * a cast-callback logger, so one in-game run shows whether cooldowns, levels and enemy/fogged cast events
 * are readable. Debug builds only.
 */
import { DamageType, Team, Unit, UnitType } from "bots/ts_libs/dota";
import * as HDebug from "bots/FunLib/humaniser/debug";

const SLOTS = 6;
const installed: Record<number, boolean> = {};

function nearestVisibleEnemy(bot: Unit): Unit | undefined {
    let best: Unit | undefined;
    let bestDist = math.huge;
    for (const enemy of GetUnitList(UnitType.EnemyHeroes)) {
        if (!enemy.CanBeSeen()) continue;
        const d = GetUnitToUnitDistance(bot, enemy);
        if (d < bestDist) {
            best = enemy;
            bestDist = d;
        }
    }
    return best;
}

export function Run(bot: Unit): string[] {
    const enemy = nearestVisibleEnemy(bot);
    if (enemy === undefined) return ["hfight no visible enemy"];
    const hero = enemy.GetUnitName();
    const lines: string[] = [];
    for (let i = 0; i < SLOTS; i++) {
        const ability = enemy.GetAbilityInSlot(i);
        if (ability === null || ability === undefined) continue;
        lines.push(
            `hfight ${hero} slot=${i} ${ability.GetName()} lvl=${ability.GetLevel()} cd=${ability.GetCooldownTimeRemaining()} ult=${tostring(ability.IsUltimate())} behavior=${ability.GetBehavior()}`
        );
    }
    lines.push(`hfight est=${enemy.GetEstimatedDamageToTarget(true, bot, 5, DamageType.All)}`);
    return lines;
}

export function InstallCastLogger(team: number): void {
    if (!HDebug.IsEnabled() || installed[team] === true) return;
    installed[team] = true;
    const enemyTeam = team === Team.Radiant ? Team.Dire : Team.Radiant;
    for (const pid of GetTeamPlayers(enemyTeam)) {
        InstallCastCallback(pid, (event: any) => {
            let visible = false;
            for (const enemy of GetUnitList(UnitType.EnemyHeroes)) {
                if (enemy.GetPlayerID() === pid && enemy.CanBeSeen()) visible = true;
            }
            const parts: string[] = [];
            if (type(event) === "table") {
                for (const [k, v] of pairs(event)) parts.push(`${tostring(k)}=${tostring(v)}`);
                table.sort(parts);
            } else {
                parts.push(tostring(event));
            }
            HDebug.Log("fight", `hfight cast pid=${pid} visible=${tostring(visible)} ${parts.join(" ")}`);
        });
    }
}

/**
 * Using a consumable on ourselves: finding a castable one in the main slots, what it restores, a tree for a tango, and the
 * order. Shared by camp supply (a tango or clarity before a pull) and the retreat's heal start (slice heal-items).
 */
import { Item, Unit, Vector } from "bots/ts_libs/dota";

/** Bot API methods for item use that ts_libs does not declare yet (its Action_UseAbility* take abilities only). */
interface ItemBot {
    GetNearbyTrees(radius: number): number[];
    Action_UseAbility(item: Item): void;
    Action_UseAbilityOnTree(item: Item, tree: number): void;
    Action_UseAbilityOnEntity(item: Item, target: Unit): void;
}
interface Spec {
    GetSpecialValueFloat(name: string): number;
}
declare function GetTreeLocation(tree: number): Vector;

/** The item by name in slots 0-5 (the backpack cannot be cast), when it can be cast now. */
export function Usable(bot: Unit, name: string): Item | undefined {
    const slot = bot.FindItemSlot(name);
    if (slot === undefined || slot < 0 || slot > 5) return undefined;
    const item = bot.GetItemInSlot(slot);
    return item !== null && item !== undefined && item.IsFullyCastable() ? item : undefined;
}

/** The HP one use gives in full, read from the item: an instant restore (faerie fire) or regen per second times duration. */
export function HpRestore(item: Item): number {
    const spec = item as unknown as Spec;
    const instant = spec.GetSpecialValueFloat("hp_restore");
    if (instant > 0) return instant;
    return spec.GetSpecialValueFloat("health_regen") * spec.GetSpecialValueFloat("buff_duration");
}

/** A visible, passable tree within the radius, for a tango. */
export function TangoTree(bot: Unit, radius: number): number | undefined {
    for (const tree of (bot as unknown as ItemBot).GetNearbyTrees(radius) ?? []) {
        const loc = GetTreeLocation(tree);
        if (IsLocationVisible(loc) && IsLocationPassable(loc)) return tree;
    }
    return undefined;
}

/** An item cast on ourselves (salve, clarity). */
export function UseOnSelf(bot: Unit, item: Item): void {
    (bot as unknown as ItemBot).Action_UseAbilityOnEntity(item, bot);
}

/** A no-target item (faerie fire). */
export function UseNoTarget(bot: Unit, item: Item): void {
    (bot as unknown as ItemBot).Action_UseAbility(item);
}

/** A tango on a tree: the hero walks to within the cast range first, so the caller gives no move order meanwhile. */
export function UseOnTree(bot: Unit, item: Item, tree: number): void {
    (bot as unknown as ItemBot).Action_UseAbilityOnTree(item, tree);
}

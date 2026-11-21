-- Overrides Valve's default watcher mode (active mode id 28, no BOT_MODE_* constant). Since patch 7.42 a hero in it
-- targets npc_dota_lantern at desire 0.43-0.48, above the laning desire, and never completes the activation, so it
-- stands by the watcher for the whole game. Neither team takes watchers until a behaviour of ours owns them.
function GetDesire()
	return BOT_MODE_DESIRE_NONE
end

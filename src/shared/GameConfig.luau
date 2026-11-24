-- Réglages de départ de la manche (docs/design.md) : à ajuster en test.
local GameConfig = {
	MORTALS_PER_MATCH = 4,
	MATCH_DURATION = 8 * 60,
	MAX_ARMED_TRAPS = 4,
	BREATH_CHARGES = 3,
	AGONY_DURATION = 45,
	REAP_DURATION = 4,
	WAITING_ROOM_MAX = 30,
}

-- Cette méthode permet de savoir si une manche peut démarrer lorsque la file a réuni des mortels et une Mort.
function GameConfig.canStartMatch(mortals: number, hasDeath: boolean): boolean
	return hasDeath and mortals == GameConfig.MORTALS_PER_MATCH
end

return GameConfig

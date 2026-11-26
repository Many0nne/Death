-- Réglages de départ de la manche (docs/design.md) : à ajuster en test.
local GameConfig = {
	MORTALS_PER_MATCH = 4,
	MATCH_DURATION = 8 * 60,
	MAX_ARMED_TRAPS = 4,
	BREATH_CHARGES = 3,
	-- Agonie, fauchage, réanimation (#6, docs/design.md) : agonie avant de mourir seul, maintien du fauchage, durée
	-- d'un massage au bon rythme, cadence attendue (battements par minute), mortel ranimé visible par la Mort, et
	-- vitesse de reptation en agonie (studs/s, contre 16 debout). Réglages fins (tolérance, lutte) : Shared.Agony
	AGONY_DURATION = 45,
	REAP_DURATION = 4,
	MASSAGE_DURATION = 8,
	MASSAGE_BPM_MIN = 100,
	MASSAGE_BPM_MAX = 120,
	REVEAL_DURATION = 20,
	CRAWL_SPEED = 4,
	WAITING_ROOM_MAX = 30,
	-- Durée d'affichage du résultat (phase Ended) avant le retour à l'attente, en secondes
	RESULT_DURATION = 10,
	-- Attente avant le démarrage automatique d'une manche quand le serveur est complet, en secondes
	INTERMISSION_DURATION = 10,
	-- Mode test (Studio) : nombre minimal de mortels face à la Mort
	TEST_MIN_MORTALS = 1,
	-- Objectif de fuite (#7) : clés à trouver (une par pièce, hors de la pièce de la sortie ; la carte ne pose aucun
	-- emplacement au garage ni devant la maison, trop près du but), maintien des actions en
	-- secondes, rayon de la sortie en studs (au bout de l'allée, devant le portail de la rue)
	ESCAPE_KEY_COUNT = 3,
	KEY_PICKUP_DURATION = 1,
	CAR_START_DURATION = 8,
	EXIT_RADIUS = 4,
	-- Lampe torche (#8) : piles cachées par manche (sur les emplacements KeySpot laissés libres par les clés, une par
	-- pièce au plus), maintien pour en ramasser une, en secondes
	FLASHLIGHT_BATTERY_COUNT = 3,
	BATTERY_PICKUP_DURATION = 1,
}

-- Cette méthode permet de savoir si une manche peut démarrer lorsque la file a réuni des mortels et une Mort.
function GameConfig.canStartMatch(mortals: number, hasDeath: boolean): boolean
	return hasDeath and mortals == GameConfig.MORTALS_PER_MATCH
end

-- Cette méthode permet de savoir si une manche de test peut démarrer lorsqu'on la lance en Studio avec moins de
-- joueurs : 1 Mort et de TEST_MIN_MORTALS à MORTALS_PER_MATCH mortels.
function GameConfig.canStartTestMatch(mortals: number, hasDeath: boolean): boolean
	return hasDeath and mortals >= GameConfig.TEST_MIN_MORTALS and mortals <= GameConfig.MORTALS_PER_MATCH
end

return GameConfig

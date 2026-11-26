-- Règles pures de la lampe torche des mortels (#8, docs/design.md « Lumière ») : faisceau (cône, portée), batterie,
-- dissipation de la Mort tenue dans le faisceau, choix de l'ombre lointaine où elle se reforme et tirage des piles
-- cachées. Sans service Roblox (testable sous Lune) ; Server.FlashlightService les applique (contrôles serveur, ligne de
-- vue, attributs) et Client.Flashlight ne fait qu'afficher le faisceau et transmettre l'interrupteur et le regard.
local Flashlight = {}

-- Réglages de départ, à ajuster en test
-- Batterie pleine : secondes d'usage (allumée) ; une pile ramassée la remplit entièrement
Flashlight.BATTERY_DURATION = 40
-- Portée du faisceau (studs) : rendu (SpotLight.Range, 60 au plus chez Roblox) et règle
Flashlight.RANGE = 40
-- Demi-angle du cône qui compte (degrés) : la règle (éclairer, dissiper). Le rendu (SpotLight.Angle, angle total) est
-- un peu plus large, 45° soit 22,5° de demi-angle, pour que la tache de lumière déborde du cœur qui agit
Flashlight.HALF_ANGLE = 18
Flashlight.VISUAL_ANGLE = 45
-- Rendu : SpotLight (avec ombres) tenue devant le visage, à droite, dans le repère de la tête ; 1,5 stud devant pour
-- sortir des accessoires de tête (un chapeau de 1,65 stud de profondeur coupait tout le faisceau, mesuré en jeu) ;
-- luminosité : à 8 la tache se devine à peine dans une pièce sombre, à 16 elle se détache (comparé en jeu)
Flashlight.HOLD_OFFSET = CFrame.new(0.4, -0.4, -1.5)
Flashlight.BRIGHTNESS = 16
-- Rayon du corps de la Mort (studs) : elle est touchée dès que le bord de son corps entre dans le cône
Flashlight.BODY_RADIUS = 1.5
-- Dissipation : secondes de faisceau tenu sur la Mort ; coupure tolérée (latence, tremblement) sans perdre le cumul ;
-- répit après une dissipation (rien ne se cumule)
Flashlight.DISPEL_TIME = 3
Flashlight.DISPEL_GAP = 0.3
Flashlight.DISPEL_IMMUNITY = 2
-- Ombre lointaine : distance minimale (studs) entre le point de reformation, la Mort et chaque mortel
Flashlight.RESPAWN_MIN_DISTANCE = 50
-- Batterie publiée par pas d'un centième (Player.FlashlightBattery) : 2,5 mises à jour par seconde au plus
Flashlight.PUBLISH_STEP = 0.01

-- Cette méthode permet de savoir si un point est dans le faisceau lorsque le serveur teste la Mort ou un point à
-- éclairer : à portée, et dans le cône (le bord d'un corps de rayon `radius` suffit). Ne teste pas les murs.
function Flashlight.inBeam(origin: Vector3, direction: Vector3, point: Vector3, radius: number?): boolean
	local offset = point - origin
	local distance = offset.Magnitude
	local r = radius or 0
	if distance - r > Flashlight.RANGE then
		return false
	end
	if distance < 1e-6 then
		return true
	end
	local cos = direction.Unit:Dot(offset / distance)
	-- Jamais à côté ni derrière la lampe, même tout près
	if cos <= 0 then
		return false
	end
	-- Marge du corps plafonnée : tout près de la lampe, le cône s'élargit au plus du double
	local half = math.rad(Flashlight.HALF_ANGLE)
	local slack = math.min(math.asin(math.min(1, r / distance)), half)
	return math.acos(math.clamp(cos, -1, 1)) - slack <= half
end

-- Cette méthode permet de vider la batterie (0 à 1) lorsque la lampe reste allumée `dt` secondes.
function Flashlight.drain(level: number, dt: number): number
	return math.max(0, level - dt / Flashlight.BATTERY_DURATION)
end

-- Cette méthode permet d'arrondir la batterie au pas publié lorsque le serveur décide s'il réécrit l'attribut (une
-- batterie non vide n'est jamais publiée à 0, pour que le HUD ne la montre pas morte trop tôt).
function Flashlight.quantize(level: number): number
	local step = Flashlight.PUBLISH_STEP
	local q = math.floor(level / step + 0.5) * step
	if level > 0 and q <= 0 then
		return step
	end
	return math.clamp(q, 0, 1)
end

export type Dispel = { held: number, gap: number, immunity: number }

-- Cette méthode permet de créer le suivi de dissipation de la Mort lorsqu'elle prend le rôle (rien de cumulé).
function Flashlight.newDispel(): Dispel
	return { held = 0, gap = 0, immunity = 0 }
end

-- Cette méthode permet de cumuler le faisceau tenu sur la Mort à chaque frame lorsque l'on sait s'il la touche ;
-- renvoie (dissipée, progression 0 à 1). Coupure > DISPEL_GAP : cumul effacé ; après dissipation, DISPEL_IMMUNITY.
function Flashlight.updateDispel(state: Dispel, hit: boolean, dt: number): (boolean, number)
	if state.immunity > 0 then
		state.immunity = math.max(0, state.immunity - dt)
		state.held, state.gap = 0, 0
		return false, 0
	end
	if hit then
		state.held += dt
		state.gap = 0
		if state.held >= Flashlight.DISPEL_TIME then
			state.held, state.gap = 0, 0
			state.immunity = Flashlight.DISPEL_IMMUNITY
			return true, 1
		end
	elseif state.held > 0 then
		state.gap += dt
		if state.gap > Flashlight.DISPEL_GAP then
			state.held, state.gap = 0, 0
		end
	end
	return false, state.held / Flashlight.DISPEL_TIME
end

-- Cette méthode permet de choisir où la Mort se reforme lorsqu'elle est dissipée : une ombre à RESPAWN_MIN_DISTANCE
-- d'elle et des mortels, au hasard ; sinon l'ombre la plus éloignée du plus proche ; nil si tout est éclairé.
function Flashlight.chooseRespawn(
	candidates: { Vector3 },
	from: Vector3,
	threats: { Vector3 },
	isLit: (Vector3) -> boolean,
	pick: (number) -> number
): Vector3?
	local far, best, bestScore = {}, nil, -math.huge
	for _, point in candidates do
		if isLit(point) then
			continue
		end
		-- Plus petite distance à un mortel (la Mort compte aussi : on ne la reforme pas sur place)
		local nearest = (point - from).Magnitude
		for _, threat in threats do
			nearest = math.min(nearest, (point - threat).Magnitude)
		end
		if nearest >= Flashlight.RESPAWN_MIN_DISTANCE then
			table.insert(far, point)
		end
		if nearest > bestScore then
			best, bestScore = point, nearest
		end
	end
	if #far > 0 then
		return far[math.clamp(pick(#far), 1, #far)]
	end
	return best
end

export type Spot = { id: string, room: string }

-- Cette méthode permet de tirer les emplacements des piles lorsque la manche démarre : `count` emplacements libres
-- (pas dans `occupied`, ex. ceux des clés), au plus un par pièce ; `pick(n)` renvoie un index de 1 à n. Renvoie moins
-- de `count` emplacements s'il n'y a pas assez de pièces.
function Flashlight.drawBatterySpots(
	spots: { Spot },
	count: number,
	pick: (number) -> number,
	occupied: { [string]: boolean }?
): { string }
	local taken = occupied or {}
	local pool = {}
	for _, spot in spots do
		if not taken[spot.id] then
			table.insert(pool, spot)
		end
	end
	-- Tri par identifiant : le tirage ne dépend que de `pick`, pas de l'ordre de CollectionService
	table.sort(pool, function(a, b)
		return a.id < b.id
	end)
	local chosen, usedRooms = {}, {}
	while #chosen < count and #pool > 0 do
		local spot = table.remove(pool, math.clamp(pick(#pool), 1, #pool))
		if not usedRooms[spot.room] then
			usedRooms[spot.room] = true
			table.insert(chosen, spot.id)
		end
	end
	return chosen
end

return Flashlight

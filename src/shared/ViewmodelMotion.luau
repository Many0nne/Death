-- Mouvement d'un viewmodel (#74), commun à tout objet tenu en première personne (mains et faux de la Mort, lampe
-- torche des mortels #67) : flottement lent, balancement quand la caméra tourne, lissage des poses, courbes de geste,
-- projection à l'écran et composition des repères. Logique pure, testée en Lune ; le montage (pièces locales collées
-- à la caméra) vit dans Client.Viewmodel.
--
-- Repères : une pose est un CFrame dans l'espace de la caméra (X à droite, Y en haut, -Z devant). Un groupe de pièces
-- (une main, la faux) a une ancre (pièce de référence) : la pose dit où va l'ancre, chaque pièce garde son écart à
-- l'ancre relevé sur le modèle au repos.

local ViewmodelMotion = {}

-- Flottement au repos : bob vertical lent, dérive latérale plus lente encore, léger roulis. Périodes non multiples
-- l'une de l'autre : le mouvement ne se répète pas à l'œil. En déplacement, l'amplitude grandit (MOVING_GAIN), la
-- période ne change pas : pas de pas, la Mort glisse.
ViewmodelMotion.FLOAT = table.freeze({
	period = 3.6, -- secondes, bob vertical
	amplitude = 0.03, -- studs, demi-amplitude du bob
	swayPeriod = 5.3, -- secondes, dérive latérale
	sway = 0.015, -- studs
	roll = math.rad(0.8), -- radians, roulis
	movingGain = 0.6, -- part d'amplitude ajoutée à pleine vitesse
})

-- Balancement quand la caméra tourne : les mains restent un peu en arrière du regard, bornées.
ViewmodelMotion.SWAY = table.freeze({
	gain = 0.012, -- studs par radian/seconde de rotation
	max = 0.05, -- studs
})

-- Cette méthode permet de calculer le décalage de flottement d'une main lorsque le viewmodel est rendu : `t` horloge,
-- `phase` décalage propre à la main (deux mains ne bougent pas ensemble), `moving` 0 à 1 (part de la vitesse maximale).
function ViewmodelMotion.float(t: number, phase: number, moving: number): CFrame
	local f = ViewmodelMotion.FLOAT
	local gain = 1 + f.movingGain * math.clamp(moving, 0, 1)
	local bob = math.sin(2 * math.pi * t / f.period + phase) * f.amplitude * gain
	local drift = math.sin(2 * math.pi * t / f.swayPeriod + phase * 1.7) * f.sway * gain
	local roll = math.sin(2 * math.pi * t / f.swayPeriod + phase * 0.6) * f.roll * gain
	return CFrame.new(drift, bob, 0) * CFrame.Angles(0, 0, roll)
end

-- Cette méthode permet de donner le balancement d'une main lorsque la caméra tourne (vitesses de lacet et de tangage
-- en radians/seconde, positives vers la gauche et vers le haut) : la main traîne à l'opposé, bornée à SWAY.max.
function ViewmodelMotion.sway(yawRate: number, pitchRate: number): Vector3
	local s = ViewmodelMotion.SWAY
	local offset = Vector3.new(yawRate * s.gain, -pitchRate * s.gain, 0)
	if offset.Magnitude > s.max then
		offset = offset.Unit * s.max
	end
	return offset
end

-- Cette méthode permet de donner la part d'approche d'un lissage exponentiel lorsque `dt` s'est écoulé (constante de
-- temps `tau`) : indépendante de la cadence d'images, 1 si tau est nul.
function ViewmodelMotion.smoothing(dt: number, tau: number): number
	if tau <= 0 then
		return 1
	end
	return 1 - math.exp(-math.max(dt, 0) / tau)
end

-- Cette méthode permet de lisser une courbe de 0 à 1 lorsqu'un geste passe d'une pose clé à la suivante
-- (départ et arrivée sans à-coup).
function ViewmodelMotion.ease(x: number): number
	local c = math.clamp(x, 0, 1)
	return c * c * (3 - 2 * c)
end

-- Cette méthode permet de donner l'intensité d'un geste bref lorsqu'il a `age` secondes et dure `duration` : monte
-- puis redescend (0 au début et à la fin, 1 au milieu), 0 hors du geste.
function ViewmodelMotion.pulse(age: number?, duration: number): number
	if age == nil or age < 0 or age >= duration then
		return 0
	end
	return math.sin(math.pi * age / duration)
end

-- Cette méthode permet de fondre les poses d'un état vers celles du suivant lorsque l'état change : `from` est la pose
-- affichée au changement, `age` le temps écoulé depuis ; lissé, sans saut au départ ni à l'arrivée. Une pose du
-- nouvel état sans pose de départ est prise telle quelle.
function ViewmodelMotion.crossfade(
	from: { [string]: CFrame },
	to: { [string]: CFrame },
	age: number,
	duration: number
): { [string]: CFrame }
	local w = if duration > 0 then ViewmodelMotion.ease(age / duration) else 1
	local out = {}
	for name, frame in to do
		local start = from[name]
		out[name] = if start and w < 1 then start:Lerp(frame, w) else frame
	end
	return out
end

-- Pose clé : avancée, repère, et une valeur libre interpolée avec lui (rotation d'un objet tenu...)
export type Key = { at: number, frame: CFrame, value: number? }

-- Cette méthode permet de lire une suite de poses clés à l'avancée `p` (0 à 1, clés triées par `at`) lorsqu'un geste
-- long se joue : interpolation lissée entre les deux clés qui encadrent `p`, du repère et de la valeur (0 sans valeur).
function ViewmodelMotion.keyframes(keys: { Key }, p: number): (CFrame, number)
	local first, last = keys[1], keys[#keys]
	if p <= first.at then
		return first.frame, first.value or 0
	end
	for k = 2, #keys do
		local key = keys[k]
		if p <= key.at then
			local prev = keys[k - 1]
			local span = key.at - prev.at
			local x = ViewmodelMotion.ease(if span > 0 then (p - prev.at) / span else 1)
			local a, b = prev.value or 0, key.value or 0
			return prev.frame:Lerp(key.frame, x), a + (b - a) * x
		end
	end
	return last.frame, last.value or 0
end

-- Cette méthode permet de projeter un point de l'espace caméra à l'écran lorsque le cadrage est contrôlé : coordonnées
-- normalisées (-1 à 1, X à droite, Y en haut) pour un champ vertical `fov` (degrés) et un rapport largeur/hauteur
-- `aspect` ; nil derrière la caméra.
function ViewmodelMotion.project(point: Vector3, fov: number, aspect: number): Vector2?
	local depth = -point.Z
	if depth <= 1e-3 then
		return nil
	end
	local half = math.tan(math.rad(fov) / 2)
	return Vector2.new(point.X / (depth * half * aspect), point.Y / (depth * half))
end

-- Cette méthode permet de ramener un point de l'espace caméra à la profondeur `depth` lorsqu'on vise une position à
-- l'écran (coordonnées normalisées) : inverse de `project`.
function ViewmodelMotion.unproject(screen: Vector2, depth: number, fov: number, aspect: number): Vector3
	local half = math.tan(math.rad(fov) / 2)
	return Vector3.new(screen.X * depth * half * aspect, screen.Y * depth * half, -depth)
end

-- Cette méthode permet d'orienter une main vers une direction lorsqu'elle se tend (-Z du repère vers `direction`,
-- haut proche du haut de la caméra). Construit par CFrame.fromMatrix : CFrame.lookAt de Lune 0.9.4 retourne l'axe Z,
-- les tests divergeraient du jeu.
function ViewmodelMotion.aim(position: Vector3, direction: Vector3): CFrame
	local look = direction.Unit
	local side = look:Cross(Vector3.new(0, 1, 0))
	if side.Magnitude < 1e-4 then
		side = Vector3.new(1, 0, 0)
	end
	local right = side.Unit
	return CFrame.fromMatrix(position, right, right:Cross(look), -look)
end

-- Cette méthode permet de donner la plus petite rotation qui amène la direction `from` sur `to` lorsqu'un membre
-- pivote pour suivre un point (vecteurs unitaires ; identité s'ils sont alignés).
function ViewmodelMotion.between(from: Vector3, to: Vector3): CFrame
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(from:Dot(to), -1, 1)))
end

-- Cette méthode permet de placer une pièce lorsque le viewmodel est rendu : la pose du groupe (espace caméra) mène son
-- ancre, la pièce garde son écart à l'ancre relevé au repos (`anchorRest`, `partRest` : repères du modèle d'origine).
function ViewmodelMotion.partFrame(camera: CFrame, pose: CFrame, anchorRest: CFrame, partRest: CFrame): CFrame
	return camera * pose * anchorRest:ToObjectSpace(partRest)
end

return ViewmodelMotion

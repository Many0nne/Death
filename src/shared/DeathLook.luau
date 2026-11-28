-- Rendu de la Mort selon qui la regarde (#80, docs/design.md « La Mort ») : règles pures lues à chaque frame par
-- Client.DeathView, indépendantes du modèle (la faux, `Scythe`, est retrouvée par son nom).
-- - Un mortel : invisible dans l'ombre ; exposée (lumière ambiante), une colonne d'ombre pleine qui avale tout le corps
--   (#98 : presque informe, pointe de capuche en haut, bas qui lèche le sol et traîne derrière elle), sans faux ; tenue
--   dans un faisceau de lampe (attribut public DeathInBeam), la colonne se déchire et laisse voir le vrai corps et la
--   faux, jusqu'à la dissipation (Server.FlashlightService).
-- - La Mort elle-même : son corps et sa faux toujours visibles, voilés dans l'ombre, pleins à la lumière.
local DeathLook = {}

-- Qui regarde : la Mort elle-même ou un autre joueur (mortel, spectateur)
DeathLook.View = table.freeze({ Self = "Self", Mortal = "Mortal" })
-- Ce qu'un mortel voit de la Mort ; Self : le joueur Mort voit son propre corps
DeathLook.Mode = table.freeze({ Hidden = "Hidden", Shadow = "Shadow", Revealed = "Revealed", Self = "Self" })

-- Durées des transitions (secondes) : apparition et disparition (exposée ou non), déchirure de l'ombre dans le
-- faisceau, ombre qui se referme hors du faisceau
DeathLook.FADE_TIME = 0.2
DeathLook.REVEAL_TIME = 0.4
DeathLook.CLOSE_TIME = 0.8
-- Colonne d'ombre vue d'un mortel : transparence du remplissage (quasi opaque), sans contour (#96 : un liseré faisait
-- un objet sélectionné plutôt qu'une ombre)
DeathLook.SHADOW_FILL = 0.04
-- Voile de la Mort sur son propre corps (transparence du remplissage) : dans l'ombre / à la lumière
DeathLook.SELF_VEIL = table.freeze({ shadow = 0.6, light = 0.05 })
-- Déplacement d'une frame à l'autre au-delà duquel la Mort a été téléportée (dissipation, reformation) : elle glisse
-- à 20 studs/s au plus, soit moins de 4 studs même à 5 images par seconde ; JUMP_SPEED couvre une frame plus longue
-- (saccade du client)
DeathLook.JUMP_DISTANCE = 12
DeathLook.JUMP_SPEED = 40
-- Après une téléportation, la Mort reste cachée jusqu'à ce que son exposition retombe (DeathRules.SHADOW_GRACE côté
-- serveur, plus la latence), au plus ce délai (secondes)
DeathLook.JUMP_HOLD = 1
-- La déchirure ne se rejoue que si l'ombre s'était refermée au moins à ce point (révélation sous ce seuil)
DeathLook.TEAR_RESET = 0.3

-- Cette méthode permet de décider ce que voit un joueur de la Mort lorsque son exposition ou le faisceau change : le
-- joueur Mort se voit toujours ; un mortel ne la voit qu'exposée, et son vrai corps seulement dans un faisceau.
function DeathLook.mode(view: string, exposed: boolean, inBeam: boolean): string
	if view == DeathLook.View.Self then
		return DeathLook.Mode.Self
	elseif not exposed then
		return DeathLook.Mode.Hidden
	elseif inBeam then
		return DeathLook.Mode.Revealed
	end
	return DeathLook.Mode.Shadow
end

-- Cette méthode permet de donner les cibles des fondus d'un mode lorsque le client avance d'une frame : visibilité
-- (0 invisible, 1 visible) et révélation (0 ombre, 1 vrai corps et faux) ; pour Self, la visibilité suit l'exposition
-- (voile) et la faux reste visible.
function DeathLook.targets(mode: string, exposed: boolean): (number, number)
	if mode == DeathLook.Mode.Self then
		return if exposed then 1 else 0, 1
	elseif mode == DeathLook.Mode.Hidden then
		return 0, 0
	elseif mode == DeathLook.Mode.Revealed then
		return 1, 1
	end
	return 1, 0
end

-- Cette méthode permet de rapprocher une valeur de sa cible à chaque frame lorsqu'un fondu est en cours : `riseTime`
-- secondes pour aller de 0 à 1, `fallTime` pour redescendre (0 : immédiat).
function DeathLook.approach(current: number, target: number, riseTime: number, fallTime: number, dt: number): number
	local time = if target > current then riseTime else fallTime
	if time <= 0 then
		return target
	end
	local step = dt / time
	return math.clamp(current + math.clamp(target - current, -step, step), 0, 1)
end

export type Layers = {
	-- transparence locale du corps, faux exceptée (1 : invisible), et de la faux ; 0 pour Self (Client.DeathView ne
	-- touche pas au corps du joueur Mort : la caméra à la première personne s'en charge)
	body: number,
	scythe: number,
	-- transparence du remplissage sombre : pour la Mort, le voile de son corps ; pour un mortel, la colonne d'ombre
	-- (1 : aucun)
	fill: number,
	outline: number, -- transparence du contour (1 : aucun)
	scytheFill: number, -- transparence du remplissage sombre de la faux
	smoke: number, -- part (0 à 1) des fumées et braises de la colonne d'ombre
	-- fumées du modèle lui-même (HemSmoke...) : coupées tant qu'un mortel voit l'ombre, rendues avec le vrai corps
	modelSmoke: boolean,
}

-- Cette méthode permet de calculer ce qu'il faut dessiner lorsque visibilité et révélation sont connues : pour un
-- mortel, la colonne d'ombre cache tout le corps (#98), puis cède la place au vrai corps et à la faux dans le faisceau.
function DeathLook.layers(view: string, visibility: number, reveal: number): Layers
	if view == DeathLook.View.Self then
		local veil = DeathLook.SELF_VEIL.shadow + (DeathLook.SELF_VEIL.light - DeathLook.SELF_VEIL.shadow) * visibility
		return {
			body = 0,
			scythe = 0,
			fill = veil,
			outline = 1,
			scytheFill = veil,
			smoke = 0,
			modelSmoke = true,
		}
	end
	local shadow = visibility * (1 - reveal)
	local revealed = 1 - visibility * reveal
	return {
		body = revealed,
		scythe = revealed,
		fill = 1 - shadow * (1 - DeathLook.SHADOW_FILL),
		outline = 1,
		scytheFill = 1,
		smoke = shadow,
		modelSmoke = reveal >= 0.5,
	}
end

-- Cette méthode permet de savoir si la Mort a été téléportée lorsque sa position change d'une frame à l'autre de durée
-- `dt` (nil : position inconnue, pas de saut).
function DeathLook.jumped(previous: Vector3?, current: Vector3?, dt: number): boolean
	if previous == nil or current == nil then
		return false
	end
	return (current - previous).Magnitude > math.max(DeathLook.JUMP_DISTANCE, DeathLook.JUMP_SPEED * dt)
end

-- Cette méthode permet de faire avancer le temps où la Mort reste cachée après une téléportation lorsqu'une frame passe :
-- fini dès que son exposition retombe (reformée dans l'ombre) ou au bout du délai ; renvoie le temps restant.
function DeathLook.holdAfterJump(remaining: number, exposed: boolean, dt: number): number
	if remaining <= 0 or not exposed then
		return 0
	end
	return math.max(0, remaining - dt)
end

-- Cette méthode permet de savoir si l'ombre se déchire à cette frame lorsque la cible de révélation est connue : elle
-- monte, la Mort est visible et l'ombre s'était refermée (un faisceau qui tremble au bord ne rejoue pas la bouffée).
function DeathLook.tears(previousTarget: number, target: number, reveal: number, visibility: number): boolean
	return target > previousTarget and visibility > 0 and reveal < DeathLook.TEAR_RESET
end

export type Box = { cframe: CFrame, size: Vector3 }
export type Bounds = { bottom: number, top: number, radius: number }

-- Cette méthode permet de mesurer le corps dans le repère de sa racine lorsque le modèle apparaît ou change : bas et
-- haut (studs, axe Y de la racine) et rayon horizontal ; nil sans pièce visible.
function DeathLook.bounds(root: CFrame, boxes: { Box }): Bounds?
	local bottom, top, radius = math.huge, -math.huge, 0
	for _, box in boxes do
		local half = box.size / 2
		for _, x in { -half.X, half.X } do
			for _, y in { -half.Y, half.Y } do
				for _, z in { -half.Z, half.Z } do
					local p = root:PointToObjectSpace(box.cframe:PointToWorldSpace(Vector3.new(x, y, z)))
					bottom = math.min(bottom, p.Y)
					top = math.max(top, p.Y)
					radius = math.max(radius, Vector3.new(p.X, 0, p.Z).Magnitude)
				end
			end
		end
	end
	if bottom > top then
		return nil
	end
	return { bottom = bottom, top = top, radius = radius }
end

-- Colonne d'ombre vue d'un mortel (#98) : des ellipsoïdes qui se recouvrent sous un seul remplissage plat, de sorte
-- qu'on ne voit qu'une masse continue. Du sol aux épaules, des couches empilées qui suivent le centre des anneaux d'os
-- de la robe (le bas ondule et traîne avec la cape) ; au-dessus, une pèlerine, la capuche et sa pointe ; au sol, des
-- lobes inégaux qui débordent un peu et traînent derrière la Mort qui glisse ; sur le bord, des bouffées pleines qui
-- se détachent sans cesse, surtout en bas, s'écartent et se résorbent (le bord bouillonne).
-- Demi-largeurs en part de la hauteur sol -> sommet : au bas, au milieu, aux épaules, de la capuche ; profondeur
-- (avant-arrière) en part de la largeur ; hauteur des épaules ; gonflement des couches (part, pulsation rad/s) ;
-- lobes (nombre, éloignement en part de la largeur du bas, longueur, largeur, hauteur visible en studs) ; recul du bas
-- par stud/s de vitesse et au plus (studs) ; bouffées (nombre, rayon en studs pour une Mort de 7,4 studs, durée de vie
-- moyenne en secondes, distance parcourue en studs, part de celles qui naissent au ras du sol).
DeathLook.COLUMN = table.freeze({
	LAYERS = 10,
	BASE = 0.19,
	WAIST = 0.15,
	SHOULDER = 0.165,
	HOOD = 0.095,
	DEPTH = 0.8,
	SHOULDER_AT = 0.74,
	BREATH = 0.02,
	BREATH_WAVE = 1.3,
	LOBES = 9,
	LOBE_REACH = 0.8,
	LOBE_LENGTH = 1.5,
	LOBE_WIDTH = 0.8,
	LOBE_HEIGHT = 0.3,
	TRAIL = 0.12,
	TRAIL_MAX = 1.8,
	PUFFS = 12,
	PUFF_SIZE = 0.42,
	PUFF_PERIOD = 1.3,
	PUFF_DRIFT = 0.9,
	PUFF_LOW = 0.6,
})

export type ColumnInput = {
	root: CFrame, -- racine du corps (position et cap)
	floorY: number, -- hauteur du sol sous la Mort
	top: number, -- hauteur du sommet du corps (capuche)
	hem: Vector3?, -- centre de l'anneau d'os du bas de la robe (monde), s'il y en a
	mid: Vector3?, -- centre de l'anneau d'os du milieu de la robe (monde)
	head: Vector3?, -- centre de la tête (seuls X et Z comptent : la tête penchée)
	velocity: Vector3,
	t: number,
}
export type Ellipsoid = { cframe: CFrame, size: Vector3 }
export type Column = {
	pieces: { Ellipsoid }, -- toujours le même nombre (DeathLook.columnPieces), dans le même ordre
	body: Ellipsoid, -- volume de la colonne, d'où partent les fumées du bord et la déchirure
	floor: Ellipsoid, -- volume au ras du sol, d'où partent la fumée qui lèche le sol et les braises
}

-- Cette méthode permet de donner le nombre de morceaux de la colonne lorsque le rendu les crée : couches, pèlerine,
-- capuche, pointe, lobes, traîne et bouffées.
function DeathLook.columnPieces(): number
	return DeathLook.COLUMN.LAYERS + 3 + DeathLook.COLUMN.LOBES + 1 + DeathLook.COLUMN.PUFFS
end

-- Cette méthode permet de donner une valeur fixe entre 0 et 1 tirée de k lorsque la colonne est posée (lobes et
-- bouffées inégaux, mais stables d'une frame à l'autre).
local function hash(k: number): number
	local x = math.sin(k * 12.9898 + 4.1414) * 43758.5453
	return x - math.floor(x)
end

-- Cette méthode permet d'interpoler la position horizontale du centre de la colonne à la hauteur y lorsque la colonne
-- est posée, entre des points triés du bas vers le haut.
local function spineAt(points: { Vector3 }, y: number): Vector3
	if y <= points[1].Y then
		return Vector3.new(points[1].X, y, points[1].Z)
	end
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		if y <= b.Y then
			local span = b.Y - a.Y
			local f = if span > 1e-6 then (y - a.Y) / span else 1
			local p = a:Lerp(b, f)
			return Vector3.new(p.X, y, p.Z)
		end
	end
	local last = points[#points]
	return Vector3.new(last.X, y, last.Z)
end

-- Cette méthode permet de placer la colonne d'ombre à l'instant t lorsqu'un mortel voit la Mort exposée : ellipsoïdes
-- (repère et taille) et volumes des fumées, en coordonnées monde.
function DeathLook.column(input: ColumnInput): Column
	local C = DeathLook.COLUMN
	local root = input.root
	local up = Vector3.yAxis
	local look = Vector3.new(root.LookVector.X, 0, root.LookVector.Z)
	look = if look.Magnitude > 1e-6 then look.Unit else Vector3.new(0, 0, -1)
	local right = look:Cross(up)
	local heading = CFrame.fromMatrix(Vector3.zero, right, up, -look)
	local floorY = input.floorY
	local height = math.max(input.top - floorY, 2)
	local t = input.t

	local flat = Vector3.new(input.velocity.X, 0, input.velocity.Z)
	local speed = flat.Magnitude
	local moveDir = if speed > 0.05 then flat.Unit else Vector3.zero
	local back = if speed > 0.05 then -moveDir else -look
	local trail = math.min(speed * C.TRAIL, C.TRAIL_MAX)

	local center = root.Position
	local shoulderY = floorY + C.SHOULDER_AT * height
	local shoulder = Vector3.new(center.X, shoulderY, center.Z)
	-- le bas suit l'anneau d'os de l'ourlet (ondulation, traîne de la cape) et recule encore avec la vitesse
	local hem = input.hem or Vector3.new(center.X, floorY + 0.15 * height, center.Z)
	local foot = Vector3.new(hem.X, floorY, hem.Z) + back * trail * 0.6
	local points = { foot }
	if hem.Y > floorY + 0.05 and hem.Y < shoulderY - 0.05 then
		table.insert(points, hem)
	end
	if input.mid and input.mid.Y > hem.Y + 0.05 and input.mid.Y < shoulderY - 0.05 then
		table.insert(points, input.mid)
	end
	table.insert(points, shoulder)

	local pieces = {}
	-- Cette méthode permet d'ajouter un ellipsoïde de demi-largeur w, demi-hauteur h et demi-profondeur d lorsque la
	-- colonne est posée, tourné vers le cap de la Mort (et penché de `tilt` radians vers l'arrière).
	local function add(at: Vector3, w: number, h: number, d: number, tilt: number?)
		local frame = CFrame.new(at) * heading
		if tilt then
			frame *= CFrame.Angles(tilt, 0, 0)
		end
		table.insert(pieces, { cframe = frame, size = Vector3.new(2 * w, 2 * h, 2 * d) })
	end

	-- Cette méthode permet de donner la demi-largeur du corps à la hauteur s (0 au sol, 1 aux épaules) lorsque la
	-- colonne est posée : évasé au bas, régulier ensuite.
	local function widthAt(s: number): number
		local share = if s < 0.35
			then C.BASE + (C.WAIST - C.BASE) * (s / 0.35)
			else C.WAIST + (C.SHOULDER - C.WAIST) * ((s - 0.35) / 0.65)
		return share * height
	end

	-- Corps : couches du sol aux épaules ; écartées de `step`, demi-hauteur 1,7 step : le bord reste presque droit, sans
	-- bourrelets ; la dernière, plus basse, ne déborde pas sur la capuche
	local step = (shoulderY - floorY) / (C.LAYERS - 1)
	for i = 0, C.LAYERS - 1 do
		local s = i / (C.LAYERS - 1)
		local w = widthAt(s) * (1 + C.BREATH * math.sin(C.BREATH_WAVE * t + 2.1 * i))
		local half = if i == C.LAYERS - 1 then step * 1.2 else step * 1.7
		add(spineAt(points, floorY + s * (shoulderY - floorY)), w, half, w * C.DEPTH)
	end

	-- Pèlerine, capuche (penchée comme la tête) et pointe de capuche, un peu en arrière, sous le sommet
	local headFlat = if input.head
		then Vector3.new(input.head.X, 0, input.head.Z)
		else Vector3.new(center.X, 0, center.Z)
	local hoodW = C.HOOD * height
	local headY = input.top - 0.17 * height
	local headAt = Vector3.new(headFlat.X, headY, headFlat.Z)
	add(shoulder:Lerp(headAt, 0.45), (C.SHOULDER * 0.62) * height, (headY - shoulderY) * 0.75, hoodW * 1.15)
	add(headAt, hoodW, 0.11 * height, hoodW * 1.1)
	local tipH = 0.1 * height
	add(Vector3.new(headAt.X, input.top - tipH, headAt.Z) - look * hoodW * 0.25, hoodW * 0.42, tipH, hoodW * 0.5, 0.3)

	-- Lobes au sol : inégaux, posés au ras du sol (la moitié basse passe sous le plancher), ceux de derrière reculent et
	-- s'étirent quand la Mort glisse
	local baseW = C.BASE * height
	for k = 0, C.LOBES - 1 do
		local h = hash(k)
		local th = 2 * math.pi * (k + 0.35 * (h - 0.5)) / C.LOBES
		local dir = look * math.cos(th) + right * math.sin(th)
		local behind = if speed > 0.05 then (1 - dir:Dot(moveDir)) / 2 else (1 - dir:Dot(look)) / 2
		local reach = baseW * C.LOBE_REACH * (0.75 + 0.35 * h) * (1 + 0.12 * math.sin(0.9 * t + 1.7 * k))
		local offset = dir * reach + back * trail * (0.3 + 0.9 * behind)
		local length = C.LOBE_LENGTH * (0.8 + 0.4 * h) + trail * behind
		local along = if offset.Magnitude > 1e-6 then offset.Unit else dir
		local at = Vector3.new(foot.X, floorY, foot.Z) + offset
		table.insert(pieces, {
			cframe = CFrame.lookAt(at, at + along),
			size = Vector3.new(C.LOBE_WIDTH * (0.85 + 0.3 * h), 2 * C.LOBE_HEIGHT, length),
		})
	end
	-- Traîne : une langue d'ombre derrière, d'autant plus longue que la Mort va vite
	local trainLength = C.LOBE_LENGTH + trail * 1.6
	local trainAt = Vector3.new(foot.X, floorY, foot.Z) + back * (baseW * 0.4 + trail * 0.8)
	table.insert(pieces, {
		cframe = CFrame.lookAt(trainAt, trainAt + back),
		size = Vector3.new(baseW * 1.3, 2 * C.LOBE_HEIGHT * 1.2, trainLength),
	})

	-- Bouffées : chacune naît à moitié dans le bord, grandit vite, s'écarte en se résorbant, puis renaît ailleurs (tirage
	-- propre à chaque cycle) ; la plupart au ras du sol, où elles roulent vers l'extérieur et restent en arrière
	local scale = height / 7.4
	for k = 0, C.PUFFS - 1 do
		local period = C.PUFF_PERIOD * (0.8 + 0.4 * hash(k + 0.5))
		local phase = t / period + hash(k + 0.25)
		local cycle = math.floor(phase)
		local f = phase - cycle
		local seed = cycle * 7.31 + k * 1.93
		local low = hash(seed) < C.PUFF_LOW
		local s = if low then 0.1 * hash(seed + 0.1) else 0.1 + 0.9 * hash(seed + 0.1)
		local th = 2 * math.pi * hash(seed + 0.2)
		local dir = look * math.cos(th) + right * math.sin(th)
		if low and speed > 0.05 then
			dir = (dir + back * 0.8).Unit
		end
		local w = widthAt(s)
		-- rayon de l'ellipse du corps dans cette direction (profondeur DEPTH)
		local radial = w * math.sqrt(dir:Dot(right) ^ 2 + (C.DEPTH * dir:Dot(look)) ^ 2)
		local r = C.PUFF_SIZE * scale * (0.7 + 0.6 * hash(seed + 0.3)) * math.min(f / 0.15, 1) * (1 - f) ^ 0.8
		local drift = C.PUFF_DRIFT * scale * f
		local at = spineAt(points, floorY + s * (shoulderY - floorY)) + dir * (radial * 0.85 + drift)
		if low then
			at = Vector3.new(at.X, floorY + r * 0.5, at.Z) + back * trail * f
		else
			at += up * drift * 0.6
		end
		table.insert(pieces, {
			cframe = CFrame.lookAt(at, at + dir),
			size = Vector3.new(2 * r, 1.6 * r, 2.6 * r),
		})
	end

	local bodyW = 2 * C.SHOULDER * height
	local bodyMid = spineAt(points, (floorY + shoulderY) / 2)
	local floorAt = Vector3.new(foot.X, floorY + 0.3, foot.Z) + back * trail * 0.5
	return {
		pieces = pieces,
		body = {
			cframe = CFrame.new(bodyMid) * heading,
			size = Vector3.new(bodyW, shoulderY - floorY, bodyW * C.DEPTH),
		},
		floor = {
			cframe = CFrame.new(floorAt) * heading,
			size = Vector3.new(baseW * 2.4, 0.6, baseW * 2.4 * C.DEPTH + trail),
		},
	}
end

return DeathLook

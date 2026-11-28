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

-- Colonne d'ombre vue d'un mortel (#98) : des ellipsoïdes très recouvrants sous un seul remplissage plat, dont la
-- réunion donne un flanc lisse (revue : pas de pile de boules). Du sol au centre de la capuche, des couches serrées
-- (demi-hauteur OVERLAP fois leur écart) dont la largeur suit un profil lissé : évasé vers le sol, régulier, à peine
-- plus large aux épaules, rétréci vers la capuche ; leur centre suit les anneaux d'os de la robe (le bas ondule et
-- traîne avec la cape) puis la tête penchée ; une onde lente, différente à gauche et à droite, déforme doucement le
-- flanc (revue : pas une chaussette régulière). Au sommet, la pointe de capuche ; au sol, une jupe basse pas plus
-- large que le pied et, en glissant, une langue qui s'effile vers l'arrière (fondues dans la fumée du sol). Le bord
-- bouillonne par la fumée (Client.DeathView), pas par la géométrie.
-- Profil : demi-largeur en part de la hauteur sol -> sommet, à des hauteurs (part du sol au centre de la capuche) ;
-- profondeur (avant-arrière) en part de la largeur (la même partout : une capuche plus creuse que le corps faisait
-- une bosse de profil) ; dôme de la capuche sous le sommet (part de la hauteur) ; centre de la capuche (part de la
-- hauteur) ; onde du flanc (part de la largeur, période à droite et à gauche en secondes ; au plus une demi-onde sur
-- la hauteur) ; pointe (demi-hauteur en part de la hauteur, largeur en part de la capuche, penchée vers l'arrière en
-- radians) ; jupe (demi-largeur en part de la largeur du bas, demi-hauteur visible en studs) ; hauteur sous laquelle
-- les couches ne descendent pas (studs : le pied se perd dans la fumée du sol au lieu de toucher le plancher en ellipse
-- nette) ; langue (demi-longueur
-- par stud de traîne, demi-largeur en part de la largeur du bas, demi-hauteur en studs) ; recul du bas par stud/s de
-- vitesse et au plus (studs) ; flancs de fumée (bandes, en part du sol au centre de la capuche : sous les épaules).
DeathLook.COLUMN = table.freeze({
	LAYERS = 16,
	OVERLAP = 3,
	PROFILE = table.freeze({
		{ 0, 0.205 },
		{ 0.1, 0.176 },
		{ 0.3, 0.152 },
		{ 0.62, 0.158 },
		{ 0.82, 0.138 },
		{ 1, 0.098 },
	}),
	DEPTH = 0.8,
	DOME = 0.08,
	HEAD_AT = 0.83,
	WAVE = 0.035,
	WAVE_RIGHT = 4.1,
	WAVE_LEFT = 3.4,
	TIP = 0.1,
	TIP_WIDTH = 0.42,
	TIP_TILT = 0.3,
	SKIRT = 0.8,
	SKIRT_HEIGHT = 0.15,
	LIFT = 0.3,
	TAIL = 1.2,
	TAIL_WIDTH = 0.55,
	TAIL_HEIGHT = 0.12,
	TRAIL = 0.12,
	TRAIL_MAX = 1.8,
	FLANK_BANDS = table.freeze({ table.freeze({ 0.04, 0.32 }), table.freeze({ 0.32, 0.55 }) }),
})

export type ColumnInput = {
	root: CFrame, -- racine du corps (position et cap)
	floorY: number, -- hauteur du sol sous la Mort
	top: number, -- hauteur du sommet du corps (capuche)
	hem: Vector3?, -- centre de l'anneau d'os du bas de la robe (monde), s'il y en a
	mid: Vector3?, -- centre de l'anneau d'os du milieu de la robe (monde)
	head: Vector3?, -- centre de la tête (seuls X et Z comptent : la tête penchée)
	camera: Vector3?, -- position de la caméra : les fumées du bord partent des flancs tels qu'elle les voit
	velocity: Vector3,
	t: number,
}
export type Ellipsoid = { cframe: CFrame, size: Vector3 }
export type Column = {
	pieces: { Ellipsoid }, -- toujours le même nombre (DeathLook.columnPieces), dans le même ordre
	-- volumes des fumées du bord, vus de la caméra : bas gauche, bas droit, haut gauche, haut droit ; l'axe X de chacun
	-- pointe vers l'extérieur de la silhouette
	flanks: { Ellipsoid },
	body: Ellipsoid, -- volume de la colonne, d'où part la déchirure
	tail: Ellipsoid, -- volume de la langue, d'où part la fumée qui la couvre en glissant
	floor: Ellipsoid, -- volume au ras du sol (la jupe), d'où partent la fumée qui lèche le sol et les braises
}

-- Cette méthode permet de donner le nombre de morceaux de la colonne lorsque le rendu les crée : couches, pointe de
-- capuche, jupe et langue.
function DeathLook.columnPieces(): number
	return DeathLook.COLUMN.LAYERS + 3
end

-- Cette méthode permet de donner la demi-largeur de la colonne (part de la hauteur) à la hauteur u (0 au sol, 1 au
-- centre de la capuche) lorsque la colonne est posée : profil interpolé en douceur entre ses points (sans angle).
function DeathLook.columnWidth(u: number): number
	local profile = DeathLook.COLUMN.PROFILE
	if u <= profile[1][1] then
		return profile[1][2]
	end
	for k = 2, #profile do
		local a, b = profile[k - 1], profile[k]
		if u <= b[1] then
			local f = (u - a[1]) / (b[1] - a[1])
			f = f * f * (3 - 2 * f)
			return a[2] + (b[2] - a[2]) * f
		end
	end
	return profile[#profile][2]
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
	local back = if speed > 0.05 then -flat.Unit else -look
	local trail = math.min(speed * C.TRAIL, C.TRAIL_MAX)

	local center = root.Position
	local headY = floorY + C.HEAD_AT * height
	local headFlat = if input.head then input.head else center
	local head = Vector3.new(headFlat.X, headY, headFlat.Z)
	local shoulderY = floorY + 0.62 * C.HEAD_AT * height
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
	table.insert(points, head)

	local pieces = {}
	-- Couches du sol au centre de la capuche : écartées de `step`, demi-hauteur OVERLAP step (creux entre deux
	-- couches : moins de 1,5 % de la largeur), sans dépasser le dôme de la capuche, sous le sommet (la pointe en sort) ;
	-- onde lente : chaque bord (droite, gauche) avance ou recule de WAVE de la largeur, à son rythme ; la couche se
	-- décale et s'élargit d'autant (bord droit w0 (1 + aR), bord gauche w0 (1 + aL))
	local step = (headY - floorY) / (C.LAYERS - 1)
	for i = 0, C.LAYERS - 1 do
		local u = i / (C.LAYERS - 1)
		local w0 = DeathLook.columnWidth(u) * height
		local aR = C.WAVE * math.sin(2 * math.pi * t / C.WAVE_RIGHT + math.pi * 0.9 * u + 0.4)
		local aL = C.WAVE * math.sin(2 * math.pi * t / C.WAVE_LEFT + math.pi * u + 2.3)
		local w = w0 * (1 + (aR + aL) / 2)
		local depth = w * C.DEPTH
		local at = spineAt(points, floorY + u * (headY - floorY)) + right * w0 * (aR - aL) / 2
		local half = math.min(C.OVERLAP * step, input.top - C.DOME * height - at.Y)
		-- pied relevé : le bas de la couche s'arrête à LIFT du sol, son haut ne bouge pas
		local low = floorY + C.LIFT
		if at.Y - half < low then
			local topY = at.Y + half
			at = Vector3.new(at.X, (low + topY) / 2, at.Z)
			half = (topY - low) / 2
		end
		table.insert(pieces, {
			cframe = CFrame.new(at) * heading,
			size = Vector3.new(2 * w, 2 * half, 2 * depth),
		})
	end

	-- Pointe de capuche, un peu en arrière, son sommet au sommet du corps
	local hoodW = C.PROFILE[#C.PROFILE][2] * height
	local tipH = C.TIP * height
	local tipAt = Vector3.new(head.X, input.top - tipH, head.Z) - look * hoodW * 0.25
	table.insert(pieces, {
		cframe = CFrame.new(tipAt) * heading * CFrame.Angles(C.TIP_TILT, 0, 0),
		size = Vector3.new(2 * hoodW * C.TIP_WIDTH, 2 * tipH, 2 * hoodW * C.TIP_WIDTH * 1.2),
	})

	-- Jupe : basse, pas plus large que le bas, sous la Mort
	local baseW = C.PROFILE[1][2] * height
	local skirtW = baseW * C.SKIRT
	local footAt = Vector3.new(foot.X, floorY, foot.Z)
	table.insert(pieces, {
		cframe = CFrame.lookAt(footAt, footAt + back),
		size = Vector3.new(2 * skirtW, 2 * C.SKIRT_HEIGHT, 2 * skirtW * C.DEPTH),
	})
	-- Langue : en glissant, une ellipse longue et étroite qui part de sous la jupe et s'effile en pointe vers l'arrière ;
	-- immobile, réduite à rien sous le pied
	local grow = math.clamp(trail / 0.5, 0, 1)
	local tailHalf = math.max(trail * C.TAIL, 0.025)
	local tailW = math.max(baseW * C.TAIL_WIDTH * grow, 0.025)
	local tailAt = footAt + back * (tailHalf + skirtW * C.DEPTH * 0.3)
	table.insert(pieces, {
		cframe = CFrame.lookAt(tailAt, tailAt + back),
		size = Vector3.new(2 * tailW, 2 * C.TAIL_HEIGHT, 2 * tailHalf),
	})

	-- Flancs vus de la caméra (sans caméra : côtés de la Mort), en deux bandes sous les épaules (revue : pas de fumée
	-- en cornes autour de la capuche) ; chacun posé juste en deçà du bord de la silhouette, son axe X vers l'extérieur
	local side = right
	if input.camera then
		local view = Vector3.new(center.X - input.camera.X, 0, center.Z - input.camera.Z)
		if view.Magnitude > 1e-3 then
			side = view.Unit:Cross(up)
		end
	end
	-- Cette méthode permet de donner le rayon de la silhouette dans la direction `dir` à la hauteur u lorsque les flancs
	-- sont posés (ellipse de la couche, profondeur comprise).
	local function radius(dir: Vector3, u: number): number
		local w = DeathLook.columnWidth(u) * height
		return w * math.sqrt(dir:Dot(right) ^ 2 + (C.DEPTH * dir:Dot(look)) ^ 2)
	end
	local flanks = {}
	for _, band in C.FLANK_BANDS do
		local u0, u1 = band[1], band[2]
		local uMid = (u0 + u1) / 2
		for _, sign in { -1, 1 } do
			local out = side * sign
			local y = floorY + uMid * (headY - floorY)
			local at = spineAt(points, y) + out * radius(out, uMid) * 0.92
			table.insert(flanks, {
				cframe = CFrame.fromMatrix(at, out, up, out:Cross(up)),
				size = Vector3.new(0.3, (u1 - u0) * (headY - floorY), 0.8),
			})
		end
	end

	local bodyW = 2 * C.PROFILE[4][2] * height
	local bodyMid = spineAt(points, (floorY + shoulderY) / 2)
	return {
		pieces = pieces,
		flanks = flanks,
		body = {
			cframe = CFrame.new(bodyMid) * heading,
			size = Vector3.new(bodyW, shoulderY - floorY, bodyW * C.DEPTH),
		},
		-- disque plus large que le pied, un peu au-dessus du sol : près de la moitié de la fumée qui y naît est hors du
		-- pied, devant compris, et casse son bord (au ras du sol, le plancher en cachait la moitié basse ; posée sur la
		-- colonne, elle disparaît sous son remplissage)
		floor = {
			cframe = CFrame.new(footAt + up * 0.35) * heading,
			size = Vector3.new(2 * baseW * 1.35, 0.2, 2 * baseW * C.DEPTH * 1.35),
		},
		tail = {
			cframe = CFrame.lookAt(tailAt + up * 0.15, tailAt + up * 0.15 + back),
			size = Vector3.new(2 * tailW, 0.3, 2 * tailHalf),
		},
	}
end

return DeathLook

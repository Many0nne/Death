-- Rendu de la Mort selon qui la regarde (#80, docs/design.md « La Mort ») : règles pures lues à chaque frame par
-- Client.DeathView, indépendantes du modèle (seule la faux, `Scythe`, est retrouvée par son nom).
-- - Un mortel : invisible dans l'ombre ; exposée (lumière ambiante), une ombre pleine dont le bas part en fumée, sans
--   faux ; tenue dans un faisceau de lampe (attribut public DeathInBeam), l'ombre se déchire et laisse voir le vrai
--   corps et la faux, jusqu'à la dissipation (Server.FlashlightService).
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
-- Ombre vue d'un mortel : transparence du remplissage (quasi opaque) et du contour léger qui garde la silhouette
-- lisible sur un fond sombre
DeathLook.SHADOW_FILL = 0.04
DeathLook.SHADOW_OUTLINE = 0.7
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
-- Colonne de fumée au bas du corps : part de la hauteur du corps, bornée (studs)
DeathLook.HEM_SHARE = 0.3
DeathLook.HEM_MIN = 1
DeathLook.HEM_MAX = 2.5

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
	fill: number, -- transparence du remplissage sombre du corps (1 : aucun)
	outline: number, -- transparence du contour du corps (1 : aucun)
	scytheFill: number, -- transparence du remplissage sombre de la faux
	smoke: number, -- part (0 à 1) des fumées et braises de l'ombre
}

-- Cette méthode permet de calculer ce qu'il faut dessiner lorsque visibilité et révélation sont connues : pour un
-- mortel, corps et ombre apparaissent ensemble, puis l'ombre (remplissage, contour, fumée) cède la place à la faux.
function DeathLook.layers(view: string, visibility: number, reveal: number): Layers
	if view == DeathLook.View.Self then
		local veil = DeathLook.SELF_VEIL.shadow + (DeathLook.SELF_VEIL.light - DeathLook.SELF_VEIL.shadow) * visibility
		return { body = 0, scythe = 0, fill = veil, outline = 1, scytheFill = veil, smoke = 0 }
	end
	local shadow = visibility * (1 - reveal)
	return {
		body = 1 - visibility,
		scythe = 1 - visibility * reveal,
		fill = 1 - shadow * (1 - DeathLook.SHADOW_FILL),
		outline = 1 - shadow * (1 - DeathLook.SHADOW_OUTLINE),
		scytheFill = 1,
		smoke = shadow,
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

-- Cette méthode permet de placer la colonne de fumée du bas du corps lorsque les mesures sont connues : décalage du
-- centre depuis la racine et taille du volume d'émission (pris dans le corps, plus étroit que les lambeaux).
function DeathLook.hemBox(bounds: Bounds): (Vector3, Vector3)
	local height = math.clamp((bounds.top - bounds.bottom) * DeathLook.HEM_SHARE, DeathLook.HEM_MIN, DeathLook.HEM_MAX)
	local width = math.max(bounds.radius * 1.2, 0.5)
	return Vector3.new(0, bounds.bottom + height / 2, 0), Vector3.new(width, height, width)
end

-- Cette méthode permet de placer le volume des volutes et de la déchirure lorsque les mesures sont connues : tout le
-- corps, un peu rentré pour que la fumée sorte de la silhouette et non de l'air autour.
function DeathLook.bodyBox(bounds: Bounds): (Vector3, Vector3)
	local height = math.max(bounds.top - bounds.bottom, 0.5)
	local width = math.max(bounds.radius * 1.2, 0.5)
	return Vector3.new(0, (bounds.top + bounds.bottom) / 2, 0), Vector3.new(width, height * 0.9, width)
end

return DeathLook

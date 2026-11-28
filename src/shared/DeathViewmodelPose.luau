-- Viewmodel de la Mort (#74) : états des mains et de la faux en première personne, choix de l'état d'après les
-- événements du jeu, pose de chaque groupe (espace caméra, Shared.ViewmodelMotion) et rendu selon la lumière.
-- Logique pure, testée en Lune ; le client (Client.DeathViewmodel) lit les événements et monte le modèle.
--
-- Le maillage `Hands` (deux avant-bras et deux mains d'un seul tenant, pose du modèle : la gauche tendue, la droite
-- serrée sur le manche) ne suit pas ses os dans le viewmodel (constaté dans Studio : Bone.Transform, pièces soudées,
-- AnimationController et Animator, rien ne le déforme). Il est donc cloné deux fois, un clone par main, chacun posé
-- de sorte que son autre main reste hors du champ (derrière la caméra ou loin du cadre) : les deux mains bougent
-- chacune de leur côté. Trois groupes, une même ancre (position de la pièce RightHand du rig, orientation du corps) :
-- - left : clone gauche (on n'en voit que la main gauche) et sa manche d'ombre ;
-- - right : clone droit (on n'en voit que la main droite) et sa manche d'ombre ;
-- - scythe : la faux, dans la main droite, tournée sur l'axe de son manche et glissée le long de celui-ci (la main
--   fermée reste sur le manche) : tenue par le bas au repos, lame vers l'arrière, au-dessus du cadre ; ramenée devant
--   pour faucher et tirer.
-- Cadrage (écran normalisé, -1 à 1) : griffes gauches en bas à gauche, manche dans le tiers droit, penché vers le
-- bord droit en haut ; centre de l'écran et panneau du rôle du HUD (bas droite, Shared.HudLayout) laissés libres.
local GameConfig = require(script.Parent.GameConfig)
local ViewmodelMotion = require(script.Parent.ViewmodelMotion)

local DeathViewmodelPose = {}

DeathViewmodelPose.State = table.freeze({
	Rest = "Rest", -- flottement lent
	Reach = "Reach", -- préparer un piège, saboter une lampe : main tendue vers la cible, maintenue
	Blow = "Blow", -- souffle : poussée courte des mains
	Reap = "Reap", -- fauchage : la faux tourne, se lève puis tranche (GameConfig.REAP_DURATION)
	Pull = "Pull", -- lutte pour l'âme : la faux crochetée tire vers soi
})
local State = DeathViewmodelPose.State

-- Durées (secondes) : geste du souffle, fauchage (celui de l'invite « Faucher »)
DeathViewmodelPose.BLOW_TIME = 0.7
DeathViewmodelPose.REAP_TIME = GameConfig.REAP_DURATION
-- Fondu entre deux états (secondes, Shared.ViewmodelMotion.crossfade) : un changement d'état ne saute jamais
DeathViewmodelPose.BLEND_TIME = 0.35

-- Cadrage du viewmodel : champ de vision de la caméra (CameraRules.FOV_FIRST_PERSON) et rapport largeur / hauteur de
-- référence (capture Studio 1611 x 759) pour les contrôles de cadrage
DeathViewmodelPose.FOV = 80
DeathViewmodelPose.ASPECT = 1611 / 759

-- Points du modèle (repère de la racine, mesurés dans Studio sur ReplicatedStorage.Characters.Death) : ancre (pièce
-- RightHand du rig), bout des griffes de la main gauche (la main qui se tend vers une cible)
DeathViewmodelPose.ANCHOR = Vector3.new(1.27, 0.5, -0.97)
DeathViewmodelPose.CLAW = Vector3.new(-0.8, 1.2, -2.9)

-- Axe du manche de la faux dans le repère de l'ancre (mesuré sur le modèle : du pommeau à la douille, passant par la
-- prise de la main)
DeathViewmodelPose.SCYTHE_AXIS = table.freeze({
	point = Vector3.new(0.17, 0, -0.2),
	direction = Vector3.new(-0.039, 0.998, 0.032).Unit,
})

-- Manches d'ombre : le maillage des mains s'arrête juste derrière le poignet (bout ouvert, que la manche du modèle
-- couvrait ; celle-ci couvrirait la moitié de l'écran, constaté). Une manche effilée par bras (ellipsoïde noir, la
-- couleur de la robe) part du poignet et file vers le coude, hors du champ. Repère de la racine : poignet et direction
-- poignet -> coude (os L_Hand, L_Forearm, R_Hand, R_Forearm mesurés sur le modèle).
DeathViewmodelPose.SLEEVES = table.freeze({
	left = { wrist = Vector3.new(-0.78, 1.2, -2.12), direction = Vector3.new(-0.19, -0.12, 1.32).Unit },
	right = { wrist = Vector3.new(1.14, 0.4, -0.88), direction = Vector3.new(0.09, 0.6, 1.2).Unit },
})
DeathViewmodelPose.SLEEVE = table.freeze({
	length = 3.2, -- studs, de la pointe au bout
	radius = 0.3, -- studs, au plus large
	lead = 0.05, -- studs : la pointe déborde un peu sur la main, la manche couvre le bout ouvert de l'avant-bras
})

-- Zone de l'écran interdite au viewmodel dans tous les états (fraction de l'écran, (0 ; 0) en haut à gauche) : elle
-- couvre le panneau du rôle du HUD (Shared.HudLayout, ombre / lumière, souffle, pièges) avec de la marge
DeathViewmodelPose.HUD_CLEAR = table.freeze({ x = 0.7, y = 0.8 })

-- Pose de repos de chaque clone (ancre, espace caméra), rotation de la faux sur son manche (radians ; π/2 : lame vers
-- l'arrière) et glissement le long du manche (studs, vers la douille : la main tient la faux par le bas, la lame reste
-- au-dessus du cadre). Poses calées par le calcul sur les règles de cadrage des tests : griffes gauches dans le tiers
-- bas à gauche, manche dans le tiers droit, penché d'environ 18 degrés vers la droite en haut, rien sur le panneau du
-- HUD, l'autre main de chaque clone hors du champ.
DeathViewmodelPose.REST = table.freeze({
	left = CFrame.new(-1.0476, -3.1411, -1.3497) * CFrame.fromEulerAnglesYXZ(0.1162, 0.5906, -1.0248),
	right = CFrame.new(2.2688, -0.381, -2.1612) * CFrame.fromEulerAnglesYXZ(0.3156, 1.381, -0.1705),
	twist = math.pi / 2,
	slide = 3.24,
})
local REST = DeathViewmodelPose.REST

-- Main tendue vers la cible : le clone gauche glisse pour amener les griffes le long du regard vers la cible, à une
-- profondeur bornée et dans une zone de l'écran (sous le centre, qui garde l'invite lisible)
DeathViewmodelPose.REACH = table.freeze({
	distance = 1.9,
	minDepth = 1.6,
	maxDepth = 2.4,
	minX = -0.45,
	maxX = 0.05,
	minY = -0.6,
	maxY = -0.2,
	tremble = 0.004, -- studs : la main qui travaille tremble à peine
	forearm = 1.33, -- studs, du poignet au coude (os L_Hand, L_Forearm) : le coude reste en place
})

-- Souffle : poussée de la main gauche vers l'avant et le haut, griffes relevées (rotation autour des griffes) ; la
-- main droite garde la faux immobile (son clone a l'autre main juste au-dessus du cadre : elle y entrerait)
DeathViewmodelPose.BLOW = table.freeze({
	push = Vector3.new(-0.1, 0.15, -0.4),
	lift = 0.25, -- radians
})

-- Fauchage, poses clés du clone droit, rotation de la faux sur son manche (value) et glissement (slide) selon
-- l'avancée (0 à 1 sur REAP_TIME) : la lame tourne et paraît en haut, armée au-dessus du centre, puis taille vers le
-- bas. La main gauche s'efface un peu vers le bas pendant le geste (REAP_DIP).
DeathViewmodelPose.REAP_KEYS = table.freeze({
	{ at = 0, frame = REST.right, value = REST.twist, slide = REST.slide },
	{
		at = 0.3,
		frame = CFrame.new(1.6964, 0.3791, -2.672) * CFrame.fromEulerAnglesYXZ(0.7005, 2.3423, -0.3241),
		value = 1.0065,
		slide = 2.8335,
	},
	{
		at = 0.7,
		frame = CFrame.new(1.5348, 0.1626, -2.2813) * CFrame.fromEulerAnglesYXZ(0.1969, 1.5476, -0.5865),
		value = -1.8276,
		slide = 2.603,
	},
	{
		at = 1,
		frame = CFrame.new(1.6499, 0.3735, -2.75) * CFrame.fromEulerAnglesYXZ(0.3468, 1.1688, -1.0019),
		value = -2.5003,
		slide = 0.0411,
	},
})
DeathViewmodelPose.REAP_DIP = Vector3.new(-0.05, -0.12, 0.05)

-- Lutte pour l'âme : faux crochetée devant, ramenée vers soi et relevée à mesure que l'âme sort (part 0 à 1),
-- tremblement des deux mains
DeathViewmodelPose.PULL = table.freeze({
	from = CFrame.new(1.1068, 0.2989, -3.0536) * CFrame.fromEulerAnglesYXZ(0.7385, 1.7223, -0.6565),
	to = CFrame.new(0.7676, 0.8899, -2.158) * CFrame.fromEulerAnglesYXZ(0.317, 1.5228, -0.2673),
	twist = -3.3769,
	slide = 2.146,
	tremble = 0.012,
})

-- Rendu selon la lumière (part de lumière 0 à 1, fondue en FADE_TIME) : dans l'ombre, mains et faux voilées de noir
-- et à demi transparentes (discrètes) ; à la lumière, pleines, texture visible.
DeathViewmodelPose.LOOK = table.freeze({
	shadow = { transparency = 0.35, fill = 0.15 },
	light = { transparency = 0, fill = 1 },
})
DeathViewmodelPose.FADE_TIME = 0.3

-- Phase du flottement de la main gauche (radians) : les deux mains ne montent pas ensemble
local LEFT_PHASE = 2.1

-- Attribut de debug (Studio seulement), sur le Player : impose un état pour les captures, "Rest", "Reach", "Blow",
-- "Blow:<secondes depuis le souffle>", "Reap:<avancée 0..1>" ou "Pull:<part 0..1>" (sans valeur : geste en boucle) ;
-- nil rend la main aux événements du jeu
DeathViewmodelPose.DEBUG_ATTRIBUTE = "DebugViewmodel"

export type Input = {
	pull: number?, -- lutte en cours : part de l'âme sortie
	reaping: boolean, -- invite « Faucher » tenue
	reaching: boolean, -- autre invite de la Mort tenue (préparer, saboter)
	blowAge: number?, -- secondes depuis le dernier souffle
}

-- Cette méthode permet de choisir l'état du viewmodel lorsque les événements du jeu changent : la lutte passe avant le
-- fauchage, puis le geste du souffle en cours, puis la main tendue ; sinon le repos.
function DeathViewmodelPose.choose(input: Input): string
	if input.pull ~= nil then
		return State.Pull
	end
	if input.reaping then
		return State.Reap
	end
	if input.blowAge ~= nil and input.blowAge >= 0 and input.blowAge < DeathViewmodelPose.BLOW_TIME then
		return State.Blow
	end
	if input.reaching then
		return State.Reach
	end
	return State.Rest
end

-- Cette méthode permet de lire l'attribut de debug lorsqu'il est posé : état imposé et sa valeur (âge du souffle,
-- avancée du fauchage, part de l'âme) ; nil si la valeur n'est pas un état connu.
function DeathViewmodelPose.parseDebug(value: any): (string?, number?)
	if type(value) ~= "string" then
		return nil, nil
	end
	local name, amount = string.match(value, "^(%a+):?([%d%.]*)$")
	if not name or not State[name] then
		return nil, nil
	end
	return State[name], tonumber(amount)
end

-- Cette méthode permet de donner le repère (repère de la racine du modèle) et la taille de la manche d'ombre d'un bras
-- lorsque le viewmodel est construit : ellipsoïde dont l'axe long part du poignet vers le coude.
function DeathViewmodelPose.sleeve(side: string): (CFrame, Vector3)
	local s = DeathViewmodelPose.SLEEVE
	local spec = DeathViewmodelPose.SLEEVES[side]
	local center = spec.wrist + spec.direction * (s.length / 2 - s.lead)
	return ViewmodelMotion.aim(center, spec.direction), Vector3.new(s.radius * 2, s.radius * 2, s.length)
end

-- Cette méthode permet de tourner la faux sur l'axe de son manche lorsque sa pose est calculée : repère à appliquer
-- après celui de l'ancre.
function DeathViewmodelPose.twist(angle: number): CFrame
	local axis = DeathViewmodelPose.SCYTHE_AXIS
	return CFrame.new(axis.point) * CFrame.fromAxisAngle(axis.direction, angle) * CFrame.new(-axis.point)
end

-- Cette méthode permet de poser la faux dans la main droite lorsque la pose du clone droit est connue : tournée de
-- `angle` sur l'axe du manche et glissée de `slide` studs le long de celui-ci (la main fermée reste sur le manche).
function DeathViewmodelPose.scythe(right: CFrame, angle: number, slide: number): CFrame
	return right * DeathViewmodelPose.twist(angle) * CFrame.new(DeathViewmodelPose.SCYTHE_AXIS.direction * slide)
end

-- Cette méthode permet de donner la position des griffes (espace caméra) pour une pose du clone gauche lorsque la
-- main se tend.
function DeathViewmodelPose.claw(left: CFrame): Vector3
	return left * (DeathViewmodelPose.CLAW - DeathViewmodelPose.ANCHOR)
end

-- Cette méthode permet de poser le clone gauche lorsque la Mort tient une invite : les griffes vont le long de la
-- direction de la cible (espace caméra), ramenées dans leur zone de l'écran et leur plage de profondeur ; `rest`
-- (pose de repos du clone, REST.left par défaut) sert au calage.
function DeathViewmodelPose.reachFrame(direction: Vector3?, t: number, rest: CFrame?): CFrame
	local from = rest or REST.left
	local r = DeathViewmodelPose.REACH
	local dir = if direction and direction.Magnitude > 1e-3 then direction.Unit else Vector3.new(0, -0.3, -1).Unit
	if dir.Z > -0.2 then
		-- cible de côté ou derrière : la main va droit devant, sous le regard
		dir = Vector3.new(dir.X * 0.3, -0.3, -1).Unit
	end
	local wanted = dir * r.distance
	local depth = math.clamp(-wanted.Z, r.minDepth, r.maxDepth)
	local screen = ViewmodelMotion.project(
		Vector3.new(wanted.X, wanted.Y, -depth),
		DeathViewmodelPose.FOV,
		DeathViewmodelPose.ASPECT
	) or Vector2.zero
	screen = Vector2.new(math.clamp(screen.X, r.minX, r.maxX), math.clamp(screen.Y, r.minY, r.maxY))
	local claw = ViewmodelMotion.unproject(screen, depth, DeathViewmodelPose.FOV, DeathViewmodelPose.ASPECT)
	local tremble = Vector3.new(math.sin(t * 41), math.sin(t * 53 + 1), 0) * r.tremble
	-- le coude reste en place : l'avant-bras pivote pour suivre la main (sinon sa manche balaierait l'écran)
	local spec = DeathViewmodelPose.SLEEVES.left
	local clawRest = DeathViewmodelPose.claw(from)
	local wrist = from * (spec.wrist - DeathViewmodelPose.ANCHOR)
	local elbow = from * (spec.wrist + spec.direction * r.forearm - DeathViewmodelPose.ANCHOR)
	local turn = ViewmodelMotion.between((elbow - wrist).Unit, (elbow - (wrist + claw - clawRest)).Unit)
	return CFrame.new(claw + tremble) * turn * CFrame.new(-clawRest) * from
end

-- Cette méthode permet de lire le fauchage à l'avancée `p` lorsque l'état Reap est rendu : pose du clone droit,
-- rotation et glissement de la faux, interpolés entre les poses clés.
function DeathViewmodelPose.reap(p: number): (CFrame, number, number)
	local frame, twist = ViewmodelMotion.keyframes(DeathViewmodelPose.REAP_KEYS :: any, p)
	local slides = {}
	for i, key in DeathViewmodelPose.REAP_KEYS do
		slides[i] = { at = key.at, frame = CFrame.identity, value = key.slide }
	end
	local _, slide = ViewmodelMotion.keyframes(slides, p)
	return frame, twist, slide
end

export type Info = {
	t: number, -- horloge (secondes)
	moving: number, -- 0 à 1, part de la vitesse maximale
	target: Vector3?, -- Reach : direction de la cible, espace caméra
	progress: number?, -- Reap : avancée 0 à 1
	pull: number?, -- Pull : part de l'âme sortie 0 à 1
	blowAge: number?, -- Blow : secondes depuis le souffle
}

export type Frames = { left: CFrame, right: CFrame, scythe: CFrame }

-- Cette méthode permet de calculer la pose voulue de chaque groupe (espace caméra) lorsque le viewmodel est rendu
-- dans un état : pose de chaque clone, flottement par-dessus (décalé entre les mains), puis la faux dans la main droite.
function DeathViewmodelPose.frames(state: string, info: Info): Frames
	local left, right, twist, slide = REST.left, REST.right, REST.twist, REST.slide
	if state == State.Reach then
		left = DeathViewmodelPose.reachFrame(info.target, info.t)
	elseif state == State.Blow then
		local k = ViewmodelMotion.pulse(info.blowAge, DeathViewmodelPose.BLOW_TIME)
		local b = DeathViewmodelPose.BLOW
		local claw = DeathViewmodelPose.claw(REST.left)
		left = CFrame.new(b.push * k + claw) * CFrame.Angles(b.lift * k, 0, 0) * CFrame.new(-claw) * REST.left
	elseif state == State.Reap then
		local p = math.clamp(info.progress or 0, 0, 1)
		right, twist, slide = DeathViewmodelPose.reap(p)
		left = CFrame.new(DeathViewmodelPose.REAP_DIP * ViewmodelMotion.pulse(p, 1)) * REST.left
	elseif state == State.Pull then
		local pl = DeathViewmodelPose.PULL
		local v = ViewmodelMotion.ease(math.clamp(info.pull or 0, 0, 1))
		local shake = Vector3.new(math.sin(info.t * 57), math.sin(info.t * 83 + 2), math.sin(info.t * 61 + 4))
			* pl.tremble
		right = CFrame.new(shake) * pl.from:Lerp(pl.to, v)
		left = CFrame.new(shake * 0.6) * REST.left
		twist, slide = pl.twist, pl.slide
	end
	left = ViewmodelMotion.float(info.t, LEFT_PHASE, info.moving) * left
	right = ViewmodelMotion.float(info.t, 0, info.moving) * right
	return { left = left, right = right, scythe = DeathViewmodelPose.scythe(right, twist, slide) }
end

-- Cette méthode permet de donner la transparence des pièces et celle du voile noir lorsque la part de lumière sur la
-- Mort change (0 : ombre, 1 : lumière).
function DeathViewmodelPose.look(light: number): (number, number)
	local k = math.clamp(light, 0, 1)
	local s, l = DeathViewmodelPose.LOOK.shadow, DeathViewmodelPose.LOOK.light
	return s.transparency + (l.transparency - s.transparency) * k, s.fill + (l.fill - s.fill) * k
end

return DeathViewmodelPose

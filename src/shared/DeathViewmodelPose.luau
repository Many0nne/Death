-- Viewmodel de la Mort (#74) : états des mains et de la faux en première personne, choix de l'état d'après les
-- événements du jeu, pose de chaque groupe (espace caméra, Shared.ViewmodelMotion) et rendu selon la lumière.
-- Logique pure, testée en Lune ; le client (Client.DeathViewmodel) lit les événements et monte le modèle.
--
-- Les mains sont un bloc rigide : le maillage `Hands` (deux avant-bras et deux mains, pose du modèle : la gauche
-- tendue, la droite serrée sur le manche) ne suit pas ses os dans le viewmodel (constaté dans Studio : Bone.Transform,
-- pièces soudées, AnimationController et Animator, rien ne le déforme). Deux groupes, une même ancre (position de la
-- pièce RightHand du rig, orientation du corps : une pose sans rotation garde les bras tels que le modèle les tient) :
-- - rig : mains, manches d'ombre et pièces du rig ;
-- - scythe : la faux, tournée sur l'axe de son manche (le manche reste dans la main fermée) : lame vers l'arrière au
--   repos, ramenée devant pour faucher et tirer.
-- Cadrage (écran normalisé, -1 à 1) : griffes de la main gauche en bas à gauche, prise de la faux à droite, manche
-- presque vertical qui sort par le haut et le bas ; centre de l'écran, coin bas droit (indicateur ombre / lumière du
-- HUD) et bas centre (panneau de la lutte) laissés libres au repos.
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

-- Pose de repos (ancre, espace caméra) et rotation de la faux sur son manche (radians ; π/2 : lame vers l'arrière,
-- hors du champ). Le bloc est tourné d'environ 43 degrés vers la gauche et incliné : la main gauche, tendue devant
-- dans le modèle, vient en bas à gauche ; la prise de la faux reste à droite, au-dessus de l'indicateur du HUD.
DeathViewmodelPose.REST = table.freeze({
	rig = CFrame.new(1.5, -0.8, -1.8) * CFrame.Angles(0, 0, 0.3) * CFrame.Angles(0, 0.75, 0) * CFrame.Angles(0.2, 0, 0),
	twist = math.pi / 2,
})
local REST = DeathViewmodelPose.REST

-- Main tendue vers la cible : le bloc glisse pour amener les griffes le long du regard vers la cible, à une
-- profondeur bornée et dans une zone de l'écran (sous le centre, qui garde l'invite lisible), et s'avance un peu
DeathViewmodelPose.REACH = table.freeze({
	distance = 1.9,
	minDepth = 1.6,
	maxDepth = 2.4,
	minX = -0.45,
	maxX = 0.05,
	minY = -0.6,
	maxY = -0.2,
	tremble = 0.004, -- studs : la main qui travaille tremble à peine
})

-- Souffle : poussée du bloc vers l'avant et le haut, griffes relevées
DeathViewmodelPose.BLOW = table.freeze({
	push = Vector3.new(-0.1, 0.15, -0.4),
	lift = 0.25, -- radians
})

-- Fauchage, poses clés du bloc et rotation de la faux selon l'avancée (0 à 1 sur REAP_TIME) : la faux tourne sur son
-- manche et la lame paraît en haut à gauche, armée au-dessus du centre, puis taille vers le bas
DeathViewmodelPose.REAP_KEYS = table.freeze({
	{ at = 0, frame = REST.rig, value = REST.twist },
	{
		at = 0.3,
		frame = CFrame.new(1.4, -0.55, -1.9)
			* CFrame.Angles(0, 0, 0.15)
			* CFrame.Angles(0, 0.75, 0)
			* CFrame.Angles(0.1, 0, 0),
		value = -0.6,
	},
	{
		at = 0.7,
		frame = CFrame.new(1.3, -0.4, -2.1) * CFrame.Angles(0, 0.6, 0) * CFrame.Angles(-0.1, 0, 0),
		value = -1.2,
	},
	{
		at = 1,
		frame = CFrame.new(0.9, -0.95, -2.0)
			* CFrame.Angles(0, 0, 0.6)
			* CFrame.Angles(0, 0.75, 0)
			* CFrame.Angles(-0.4, 0, 0),
		value = -1.5,
	},
})

-- Lutte pour l'âme : faux crochetée devant, ramenée vers soi et relevée à mesure que l'âme sort (part 0 à 1),
-- tremblement
DeathViewmodelPose.PULL = table.freeze({
	from = CFrame.new(1.2, -0.7, -2.3)
		* CFrame.Angles(0, 0, 0.35)
		* CFrame.Angles(0, 0.6, 0)
		* CFrame.Angles(-0.35, 0, 0),
	to = CFrame.new(1.4, -0.85, -1.7) * CFrame.Angles(0, 0, 0.3) * CFrame.Angles(0, 0.7, 0) * CFrame.Angles(0.05, 0, 0),
	twist = -1.4,
	tremble = 0.012,
})

-- Rendu selon la lumière (part de lumière 0 à 1, fondue en FADE_TIME) : dans l'ombre, mains et faux voilées de noir
-- et à demi transparentes (discrètes) ; à la lumière, pleines, texture visible.
DeathViewmodelPose.LOOK = table.freeze({
	shadow = { transparency = 0.35, fill = 0.15 },
	light = { transparency = 0, fill = 1 },
})
DeathViewmodelPose.FADE_TIME = 0.3

-- Phase du flottement (radians)
local PHASE = 0

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

-- Cette méthode permet de donner la position des griffes (espace caméra) pour une pose du bloc lorsque la main se tend.
function DeathViewmodelPose.claw(rig: CFrame): Vector3
	return rig * (DeathViewmodelPose.CLAW - DeathViewmodelPose.ANCHOR)
end

-- Cette méthode permet de poser le bloc lorsque la Mort tient une invite : il glisse pour amener les griffes le long
-- de la direction de la cible (espace caméra), ramenées dans leur zone de l'écran et leur plage de profondeur.
function DeathViewmodelPose.reachFrame(direction: Vector3?, t: number): CFrame
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
	return CFrame.new(claw - DeathViewmodelPose.claw(REST.rig) + tremble) * REST.rig
end

export type Info = {
	t: number, -- horloge (secondes)
	moving: number, -- 0 à 1, part de la vitesse maximale
	target: Vector3?, -- Reach : direction de la cible, espace caméra
	progress: number?, -- Reap : avancée 0 à 1
	pull: number?, -- Pull : part de l'âme sortie 0 à 1
	blowAge: number?, -- Blow : secondes depuis le souffle
}

export type Frames = { rig: CFrame, scythe: CFrame }

-- Cette méthode permet de calculer la pose voulue de chaque groupe (espace caméra) lorsque le viewmodel est rendu
-- dans un état : pose du bloc, flottement par-dessus, puis la faux tournée sur son manche.
function DeathViewmodelPose.frames(state: string, info: Info): Frames
	local rig, twist = REST.rig, REST.twist
	if state == State.Reach then
		rig = DeathViewmodelPose.reachFrame(info.target, info.t)
	elseif state == State.Blow then
		local k = ViewmodelMotion.pulse(info.blowAge, DeathViewmodelPose.BLOW_TIME)
		local b = DeathViewmodelPose.BLOW
		rig = CFrame.new(b.push * k) * REST.rig * CFrame.Angles(b.lift * k, 0, 0)
	elseif state == State.Reap then
		rig, twist =
			ViewmodelMotion.keyframes(DeathViewmodelPose.REAP_KEYS :: any, math.clamp(info.progress or 0, 0, 1))
	elseif state == State.Pull then
		local pl = DeathViewmodelPose.PULL
		local v = math.clamp(info.pull or 0, 0, 1)
		local shake = Vector3.new(math.sin(info.t * 57), math.sin(info.t * 83 + 2), math.sin(info.t * 61 + 4))
			* pl.tremble
		rig = CFrame.new(shake) * pl.from:Lerp(pl.to, ViewmodelMotion.ease(v))
		twist = pl.twist
	end
	rig = ViewmodelMotion.float(info.t, PHASE, info.moving) * rig
	return { rig = rig, scythe = rig * DeathViewmodelPose.twist(twist) }
end

-- Cette méthode permet de donner la transparence des pièces et celle du voile noir lorsque la part de lumière sur la
-- Mort change (0 : ombre, 1 : lumière).
function DeathViewmodelPose.look(light: number): (number, number)
	local k = math.clamp(light, 0, 1)
	local s, l = DeathViewmodelPose.LOOK.shadow, DeathViewmodelPose.LOOK.light
	return s.transparency + (l.transparency - s.transparency) * k, s.fill + (l.fill - s.fill) * k
end

return DeathViewmodelPose

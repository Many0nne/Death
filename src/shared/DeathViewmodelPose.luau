-- Viewmodel de la Mort (#74) : états des mains et de la faux en première personne, choix de l'état d'après les
-- événements du jeu, pose de chaque groupe (espace caméra, Shared.ViewmodelMotion) et rendu selon la lumière.
-- Logique pure, testée en Lune ; le client (Client.DeathViewmodel) lit les événements et monte le modèle.
--
-- Groupes du modèle (pièces du rig R15 de la Mort, os des bras rangés dessous, docs/assets.md). Chaque ancre a la
-- position de sa pièce et l'orientation du corps : une pose sans rotation garde le bras tel que le modèle le tient.
-- - left : bras gauche (LeftUpperArm, LeftLowerArm, LeftHand), ancre LeftHand ;
-- - right : bras droit (RightUpperArm, RightLowerArm, RightHand), ancre RightHand ;
-- - scythe : la faux, même ancre que le bras droit, tournée sur l'axe de son manche (le manche reste dans la main
--   fermée) : lame vers l'arrière au repos, ramenée devant pour faucher ;
-- - core : le maillage des mains (Hands) et UpperTorso, posés entre les deux mains (le maillage suit ses os).
-- Cadrage (écran normalisé, -1 à 1) : main gauche en bas à gauche, faux à droite, manche qui sort par le haut et le bas,
-- coudes hors du champ (le maillage des mains s'arrête au coude) ; centre de l'écran, coin bas droit (indicateur
-- ombre / lumière du HUD) et bas centre (panneau de la lutte) laissés libres au repos.
local GameConfig = require(script.Parent.GameConfig)
local ViewmodelMotion = require(script.Parent.ViewmodelMotion)

local DeathViewmodelPose = {}

DeathViewmodelPose.State = table.freeze({
	Rest = "Rest", -- flottement lent
	Reach = "Reach", -- préparer un piège, saboter une lampe : main tendue vers la cible, maintenue
	Blow = "Blow", -- souffle : geste court de la main gauche
	Reap = "Reap", -- fauchage : la faux se lève puis tranche (GameConfig.REAP_DURATION)
	Pull = "Pull", -- lutte pour l'âme : les deux mains tirent la faux
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

-- Axe du manche de la faux dans le repère de l'ancre droite (mesuré sur le modèle : du pommeau à la douille, passant
-- par la prise de la main)
DeathViewmodelPose.SCYTHE_AXIS = table.freeze({
	point = Vector3.new(0.17, 0, -0.2),
	direction = Vector3.new(-0.039, 0.998, 0.032).Unit,
})

-- Manches d'ombre : le maillage des mains s'arrête juste derrière le poignet (bout ouvert, que la manche du modèle
-- couvrait ; elle-même couvrirait la moitié de l'écran, constaté). Une manche effilée par bras (ellipsoïde noir, la
-- couleur de la robe) part du poignet et file vers le coude, hors du champ. Repère de l'ancre de chaque bras : poignet
-- et direction poignet -> coude (os L_Hand, L_Forearm, R_Hand, R_Forearm mesurés sur le modèle).
DeathViewmodelPose.SLEEVES = table.freeze({
	left = { wrist = Vector3.new(-0.02, 0, 0.2), direction = Vector3.new(-0.19, -0.12, 1.32).Unit },
	right = { wrist = Vector3.new(-0.13, -0.1, 0.09), direction = Vector3.new(0.09, 0.6, 1.2).Unit },
})
DeathViewmodelPose.SLEEVE = table.freeze({
	length = 3.2, -- studs, de la pointe au bout
	radius = 0.3, -- studs, au plus large
	lead = 0.05, -- studs : la pointe déborde un peu sur la main, la manche couvre le bout ouvert de l'avant-bras
})

-- Poses de repos (ancre de chaque groupe, espace caméra) et rotation de la faux sur son manche (radians ; π/2 : lame
-- vers l'arrière). Main gauche : en bas à gauche, griffes un peu relevées et tournées vers le centre. Main droite :
-- à droite, au-dessus de l'indicateur du HUD, manche presque droit, un peu penché en arrière vers l'épaule.
DeathViewmodelPose.REST = table.freeze({
	left = CFrame.new(-1.05, -0.8, -1.7) * CFrame.Angles(0.2, -0.3, 0),
	right = CFrame.new(1.05, -0.8, -2.1) * CFrame.Angles(0, 0, -0.1) * CFrame.Angles(0.25, 0, 0),
	twist = math.pi / 2,
})
local REST = DeathViewmodelPose.REST

-- Main tendue vers la cible : distance visée le long du regard vers la cible, profondeur bornée, et zone de l'écran
-- où elle reste (sous le centre, qui garde l'invite lisible)
DeathViewmodelPose.REACH = table.freeze({
	distance = 1.9,
	minDepth = 1.4,
	maxDepth = 2.2,
	minX = -0.45,
	maxX = 0.2,
	minY = -0.85,
	maxY = -0.25,
	tremble = 0.004, -- studs : la main qui travaille tremble à peine
	shoulder = Vector3.new(-0.8, -1.3, 0.2), -- épaule gauche, espace caméra
	towardTarget = 0.3, -- part de la direction de la cible dans l'orientation des griffes (le reste : épaule -> main)
})

-- Souffle : poussée de la main gauche vers l'avant et le haut, paume tournée vers la cible
DeathViewmodelPose.BLOW = table.freeze({
	push = Vector3.new(0.3, 0.2, -0.45),
	lift = 0.55, -- radians : les griffes se relèvent
})

-- Fauchage, poses clés du bras droit et rotation de la faux selon l'avancée (0 à 1 sur REAP_TIME) : levée (la lame
-- tourne et paraît en haut à droite), armée haute (lame au-dessus, vers la gauche), puis taille vers le bas et la gauche
DeathViewmodelPose.REAP_KEYS = table.freeze({
	{ at = 0, frame = REST.right, value = REST.twist },
	{
		at = 0.3,
		frame = CFrame.new(1.05, -0.45, -2.1) * CFrame.Angles(0, 0, -0.35) * CFrame.Angles(0.1, 0, 0),
		value = 0.9,
	},
	{
		at = 0.7,
		frame = CFrame.new(0.8, -0.25, -2.3) * CFrame.Angles(0, 0, 0.1) * CFrame.Angles(-0.15, 0, 0),
		value = 0.1,
	},
	{
		at = 1,
		frame = CFrame.new(0.35, -0.75, -2.0) * CFrame.Angles(0, 0, 0.55) * CFrame.Angles(-0.55, 0, 0),
		value = -0.1,
	},
})
-- Prise de la main gauche sur le manche, sous la main droite (repère de l'ancre droite), et avancée du fauchage où
-- elle l'a rejoint
DeathViewmodelPose.LEFT_GRIP = CFrame.new(0.15, -1.0, -0.2)
DeathViewmodelPose.GRIP_AT = 0.3

-- Lutte pour l'âme : faux crochetée vers l'avant (lame devant), ramenée vers soi à mesure que l'âme sort (part 0 à 1),
-- tremblement
DeathViewmodelPose.PULL = table.freeze({
	from = CFrame.new(0.6, -0.55, -2.3) * CFrame.Angles(0, 0, 0.25) * CFrame.Angles(-0.45, 0, 0),
	to = CFrame.new(0.75, -0.75, -1.7) * CFrame.Angles(0, 0, 0.35) * CFrame.Angles(-0.1, 0, 0),
	twist = 0,
	tremble = 0.012,
})

-- Rendu selon la lumière (part de lumière 0 à 1, fondue en FADE_TIME) : dans l'ombre, mains et faux voilées de noir
-- et à demi transparentes (discrètes) ; à la lumière, pleines, texture visible.
DeathViewmodelPose.LOOK = table.freeze({
	shadow = { transparency = 0.35, fill = 0.15 },
	light = { transparency = 0, fill = 1 },
})
DeathViewmodelPose.FADE_TIME = 0.3

-- Phases du flottement de chaque main (radians) : elles ne montent pas ensemble
local PHASE = { left = 0, right = 1.9 }

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

-- Cette méthode permet de lire l'attribut de debug lorsqu'il est posé : état imposé et sa valeur (avancée du
-- fauchage, part de l'âme) ; nil si la valeur n'est pas un état connu.
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

-- Cette méthode permet de donner le repère (dans celui de l'ancre du bras) et la taille de la manche d'ombre d'un bras
-- lorsque le viewmodel est construit : ellipsoïde dont l'axe long part du poignet vers le coude.
function DeathViewmodelPose.sleeve(side: string): (CFrame, Vector3)
	local s = DeathViewmodelPose.SLEEVE
	local spec = DeathViewmodelPose.SLEEVES[side]
	local center = spec.wrist + spec.direction * (s.length / 2 - s.lead)
	return ViewmodelMotion.aim(center, spec.direction), Vector3.new(s.radius * 2, s.radius * 2, s.length)
end

-- Cette méthode permet de tourner la faux sur l'axe de son manche lorsque sa pose est calculée : repère à appliquer
-- après celui de l'ancre droite.
function DeathViewmodelPose.twist(angle: number): CFrame
	local axis = DeathViewmodelPose.SCYTHE_AXIS
	return CFrame.new(axis.point) * CFrame.fromAxisAngle(axis.direction, angle) * CFrame.new(-axis.point)
end

-- Cette méthode permet de placer la main tendue lorsque la Mort tient une invite : le long de la direction de la cible
-- (espace caméra), ramenée dans sa zone de l'écran et sa plage de profondeur, griffes vers la cible.
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
	local position = ViewmodelMotion.unproject(screen, depth, DeathViewmodelPose.FOV, DeathViewmodelPose.ASPECT)
	local tremble = Vector3.new(math.sin(t * 41), math.sin(t * 53 + 1), 0) * r.tremble
	-- le bras part de l'épaule, sous la caméra : l'avant-bras sort du champ par le bas au lieu de s'aligner sur le regard
	local aim = ((position - r.shoulder).Unit * (1 - r.towardTarget) + dir * r.towardTarget).Unit
	return ViewmodelMotion.aim(position + tremble, aim)
end

export type Info = {
	t: number, -- horloge (secondes)
	moving: number, -- 0 à 1, part de la vitesse maximale
	target: Vector3?, -- Reach : direction de la cible, espace caméra
	progress: number?, -- Reap : avancée 0 à 1
	pull: number?, -- Pull : part de l'âme sortie 0 à 1
	blowAge: number?, -- Blow : secondes depuis le souffle
}

export type Frames = { left: CFrame, right: CFrame, scythe: CFrame, core: CFrame }

-- Cette méthode permet de calculer la pose voulue de chaque groupe (espace caméra) lorsque le viewmodel est rendu
-- dans un état : pose de l'état, flottement par-dessus, faux tournée sur son manche, puis le maillage des mains entre
-- les deux.
function DeathViewmodelPose.frames(state: string, info: Info): Frames
	local left, right, twist = REST.left, REST.right, REST.twist
	-- part de la prise de la main gauche sur le manche (0 : main libre)
	local grip = 0
	if state == State.Reach then
		left = DeathViewmodelPose.reachFrame(info.target, info.t)
	elseif state == State.Blow then
		local k = ViewmodelMotion.pulse(info.blowAge, DeathViewmodelPose.BLOW_TIME)
		local b = DeathViewmodelPose.BLOW
		left = CFrame.new(b.push * k) * REST.left * CFrame.Angles(b.lift * k, 0, 0)
	elseif state == State.Reap then
		local p = math.clamp(info.progress or 0, 0, 1)
		right, twist = ViewmodelMotion.keyframes(DeathViewmodelPose.REAP_KEYS :: any, p)
		grip = ViewmodelMotion.ease(p / DeathViewmodelPose.GRIP_AT)
	elseif state == State.Pull then
		local pl = DeathViewmodelPose.PULL
		local v = math.clamp(info.pull or 0, 0, 1)
		local shake = Vector3.new(math.sin(info.t * 57), math.sin(info.t * 83 + 2), math.sin(info.t * 61 + 4))
			* pl.tremble
		right = CFrame.new(shake) * pl.from:Lerp(pl.to, ViewmodelMotion.ease(v))
		twist = pl.twist
		grip = 1
	end
	left = ViewmodelMotion.float(info.t, PHASE.left, info.moving) * left
	right = ViewmodelMotion.float(info.t, PHASE.right, info.moving) * right
	if grip > 0 then
		-- la main qui tient le manche suit la main droite, flottement compris : elle ne glisse pas sur le bois
		local held = CFrame.new((right * DeathViewmodelPose.LEFT_GRIP).Position) * REST.left.Rotation
		left = left:Lerp(held, grip)
	end
	local core = CFrame.new(left.Position:Lerp(right.Position, 0.5))
	return { left = left, right = right, scythe = right * DeathViewmodelPose.twist(twist), core = core }
end

-- Cette méthode permet de donner la transparence des pièces et celle du voile noir lorsque la part de lumière sur la
-- Mort change (0 : ombre, 1 : lumière).
function DeathViewmodelPose.look(light: number): (number, number)
	local k = math.clamp(light, 0, 1)
	local s, l = DeathViewmodelPose.LOOK.shadow, DeathViewmodelPose.LOOK.light
	return s.transparency + (l.transparency - s.transparency) * k, s.fill + (l.fill - s.fill) * k
end

return DeathViewmodelPose

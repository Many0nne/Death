-- Règles de caméra (#24) : première personne verrouillée pendant la manche pour la Mort et les mortels encore en jeu,
-- caméra libre ailleurs (attente, résultat, spectateur). Logique pure, lue par le client (CameraController).
local Match = require(script.Parent.Match)

local CameraRules = {}

CameraRules.Mode = table.freeze({ FirstPerson = "FirstPerson", Free = "Free" })

-- Champ de vision en première personne (degrés) : un peu plus large que les 70 par défaut, pour compenser l'absence
-- de recul ; en vue libre, on rend la valeur par défaut de Roblox.
CameraRules.FOV_FIRST_PERSON = 80
CameraRules.FOV_FREE = 70
-- Recul imposé (studs) en quittant la première personne, pour retrouver une caméra à la troisième personne
CameraRules.FREE_ZOOM_DISTANCE = 12
CameraRules.DEFAULT_MIN_ZOOM = 0.5 -- zoom minimal par défaut de Roblox

-- Caméra de la Mort (#91) : Humanoid.CameraOffset (repère de la racine) qui mène le point visé par la caméra du
-- rig R15 sans mise à l'échelle (racine + 2 studs, PlayerModule de Roblox) aux yeux du spectre, mesurés sur le modèle
-- (rendu de profil docs/renders/death/side.png) : 2,68 studs au-dessus de la racine et 0,62 devant, soit 6,3 studs
-- au-dessus du sol (racine à 3,65). Sans ce décalage, la caméra était à 5,78 studs, à hauteur de poitrine.
CameraRules.DEATH_CAMERA_OFFSET = Vector3.new(0, 0.68, -0.62)

-- Invites en première personne : cosinus minimal entre le regard et la direction de la cible (environ 37 degrés),
-- et distance en dessous de laquelle la cible compte comme regardée (grosse pièce collée à soi).
CameraRules.LOOK_MIN_DOT = 0.8
CameraRules.LOOK_NEAR = 3

-- Cette méthode permet de choisir le mode de caméra lorsque la phase, le rôle et l'état du mortel changent : première
-- personne pendant la manche pour la Mort et les mortels vivants ou en agonie, libre sinon (phase autre que Running,
-- hors manche, mortel mort ou sauvé = spectateur).
function CameraRules.modeFor(phase: string?, role: string?, mortalState: string?): string
	if phase ~= Match.Phase.Running then
		return CameraRules.Mode.Free
	end
	if role == Match.Role.Death then
		return CameraRules.Mode.FirstPerson
	end
	if
		role == Match.Role.Mortal
		and (mortalState == Match.MortalState.Alive or mortalState == Match.MortalState.Agony)
	then
		return CameraRules.Mode.FirstPerson
	end
	return CameraRules.Mode.Free
end

-- Cette méthode permet de donner le décalage de caméra d'un personnage lorsqu'il apparaît ou change de corps : aux
-- yeux du spectre pour le corps de la Mort, aucun pour un avatar.
function CameraRules.cameraOffsetFor(isDeathBody: boolean): Vector3
	return if isDeathBody then CameraRules.DEATH_CAMERA_OFFSET else Vector3.zero
end

-- Cette méthode permet de savoir si une cible est regardée lorsque la caméra est à la première personne : dans le
-- cône du regard, ou tout près de la caméra.
function CameraRules.isLookedAt(cameraPos: Vector3, cameraLook: Vector3, targetPos: Vector3, radius: number?): boolean
	local r = radius or 0
	local offset = targetPos - cameraPos
	local distance = offset.Magnitude
	if distance - r <= CameraRules.LOOK_NEAR then
		return true
	end
	-- Une grande cible est regardée dès que son bord entre dans le cône : on retire à l'angle son demi-diamètre apparent
	local angle = math.acos(math.clamp(cameraLook.Unit:Dot(offset / distance), -1, 1))
	local slack = math.asin(math.min(1, r / distance))
	return math.cos(math.max(0, angle - slack)) >= CameraRules.LOOK_MIN_DOT
end

return CameraRules

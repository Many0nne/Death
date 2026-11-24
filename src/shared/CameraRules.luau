-- Règles de caméra (#24) : première personne verrouillée pendant la manche pour la Mort et les mortels encore en jeu,
-- caméra libre ailleurs (attente, résultat, spectateur). Logique pure, lue par le client (CameraController).
local Match = require(script.Parent.Match)

local CameraRules = {}

CameraRules.Mode = table.freeze({ FirstPerson = "FirstPerson", Free = "Free" })

-- Champ de vision en première personne (degrés) : un peu plus large que les 70 par défaut, pour compenser l'absence
-- de recul ; en vue libre, on rend la valeur par défaut de Roblox.
CameraRules.FOV_FIRST_PERSON = 80
CameraRules.FOV_FREE = 70

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

-- Cette méthode permet de savoir si une cible est regardée lorsque la caméra est à la première personne : dans le
-- cône du regard, ou tout près de la caméra.
function CameraRules.isLookedAt(cameraPos: Vector3, cameraLook: Vector3, targetPos: Vector3): boolean
	local offset = targetPos - cameraPos
	local distance = offset.Magnitude
	if distance <= CameraRules.LOOK_NEAR then
		return true
	end
	return cameraLook.Unit:Dot(offset / distance) >= CameraRules.LOOK_MIN_DOT
end

return CameraRules

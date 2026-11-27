-- Mouvement de la cape de la Mort (#76) : règles pures, appliquées aux os de la cape par Client.CloakAnimator.
-- La cape est un maillage à os (assets/rbx/Characters/Death.rbxm, source tools/blender/death_model.py) : CHAINS chaînes de
-- BONES os pendent autour de la robe, la chaîne 0 devant (-Z de la racine), puis dans le sens des X positifs (chaîne
-- CHAINS / 4 à droite). Deux mouvements s'additionnent :
-- - ondulation : même immobile, chaque lambeau ondule (vers l'extérieur et sur le côté), une vague qui descend la
--   chaîne : la Mort n'est jamais figée, comme une ombre ;
-- - traîne : en glissant, la robe part vers l'arrière du mouvement, surtout du côté qui traîne, et ondule plus vite.
-- Les angles sont donnés dans le repère de la racine (HumanoidRootPart), autour du point d'attache de chaque os.
local CloakMotion = {}

CloakMotion.CHAINS = 16
CloakMotion.BONES = 4
-- Vitesse (studs/s) à laquelle la traîne est complète : la Mort dans l'ombre (DeathRules.SPEED_SHADOW)
CloakMotion.FULL_SPEED = 20
-- Ondulation au repos, par os, au bas de la chaîne (radians) ; s'y ajoute FLAP_MOVING à pleine vitesse
CloakMotion.FLAP_IDLE = math.rad(4)
CloakMotion.FLAP_MOVING = math.rad(5)
-- Fréquence de l'ondulation au repos (Hz) ; doublée à pleine vitesse
CloakMotion.FREQUENCY = 0.45
-- Traîne par os à pleine vitesse, côté qui traîne (radians) : 4 os -> 36° au bas de la robe
CloakMotion.TRAIL = math.rad(9)

local DOWN = Vector3.new(0, -1, 0)

-- Cette méthode permet de donner la direction horizontale vers laquelle pend la chaîne `chain` (repère de la racine).
function CloakMotion.outward(chain: number): Vector3
	local th = 2 * math.pi * chain / CloakMotion.CHAINS
	return Vector3.new(math.sin(th), 0, -math.cos(th))
end

-- Cette méthode permet de lire la chaîne et le rang d'un os de la cape d'après son nom (« C07_2 ») ; nil pour l'os
-- racine ou un autre nom.
function CloakMotion.parseBone(name: string): (number?, number?)
	local chain, bone = string.match(name, "^C(%d+)_(%d+)$")
	if not chain then
		return nil, nil
	end
	return tonumber(chain), tonumber(bone)
end

-- Cette méthode permet de calculer la rotation d'un os de la cape à l'instant `t` lorsque la racine se déplace à
-- `velocity` (repère de la racine, studs/s) ; renvoie une rotation pure exprimée dans le repère de la racine.
function CloakMotion.boneRotation(t: number, chain: number, bone: number, velocity: Vector3): CFrame
	local out = CloakMotion.outward(chain)
	local depth = (bone + 1) / CloakMotion.BONES
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontal.Magnitude
	local s = math.clamp(speed / CloakMotion.FULL_SPEED, 0, 1)
	-- ondulation : vague qui descend la chaîne, décalée d'une chaîne à l'autre
	local omega = 2 * math.pi * CloakMotion.FREQUENCY * (1 + s)
	local amplitude = (CloakMotion.FLAP_IDLE + CloakMotion.FLAP_MOVING * s) * depth
	local wave = math.sin(omega * t - 0.9 * bone + 1.7 * chain)
	local side = math.sin(0.7 * omega * t - 0.6 * bone + 2.3 * chain)
	local rotation = CFrame.fromAxisAngle(DOWN:Cross(out), amplitude * wave)
		* CFrame.fromAxisAngle(out, 0.5 * amplitude * side)
	-- traîne : la robe part à l'opposé du mouvement, plus fort du côté qui traîne
	if speed > 1e-3 then
		local back = -horizontal / speed
		local facing = out:Dot(back)
		local trail = CloakMotion.TRAIL * s * (0.55 + 0.45 * facing)
		rotation = CFrame.fromAxisAngle(DOWN:Cross(back), trail) * rotation
	end
	return rotation
end

return CloakMotion

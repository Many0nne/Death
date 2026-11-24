-- Applique l'ambiance de nuit (Shared.NightLighting) au service Lighting au démarrage du serveur ; les clients la
-- reçoivent par réplication.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NightLighting = require(ReplicatedStorage.Shared.NightLighting)

local NightAmbience = {}

-- Cette méthode permet de reprendre l'effet de cette classe déjà présent sous Lighting (place de départ, ou ambiance
-- appliquée deux fois) ou de le créer, lorsqu'un seul exemplaire doit décider du rendu.
local function effect(lighting: Instance, className: string, name: string, properties: { [string]: any }): Instance
	local instance = lighting:FindFirstChildOfClass(className)
	if not instance then
		instance = Instance.new(className)
	end
	instance.Name = name
	for property, value in properties do
		(instance :: any)[property] = value
	end
	instance.Parent = lighting
	return instance
end

-- Cette méthode permet de régler Lighting, le brouillard (Atmosphere) et la palette (ColorCorrection) lorsque le
-- serveur démarre.
function NightAmbience.apply(lighting: Instance)
	for property, value in NightLighting.lighting do
		(lighting :: any)[property] = value
	end
	effect(lighting, "Atmosphere", "NightAtmosphere", NightLighting.atmosphere)
	effect(lighting, "ColorCorrectionEffect", "NightColor", NightLighting.colorCorrection)
end

return NightAmbience

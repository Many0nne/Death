-- Applique l'ambiance de nuit (Shared.NightLighting) au service Lighting au démarrage du serveur ; les clients la
-- reçoivent par réplication.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NightLighting = require(ReplicatedStorage.Shared.NightLighting)

local NightAmbience = {}

-- Cette méthode permet de garder un seul effet de cette classe sous Lighting (le premier présent, sinon un nouveau)
-- lorsque la place de départ en contient déjà : les autres exemplaires sont retirés pour ne pas fausser le rendu.
local function effect(lighting: Instance, className: string, name: string, properties: { [string]: any }): Instance
	local instance = nil
	for _, child in lighting:GetChildren() do
		if child.ClassName == className then
			if instance then
				child:Destroy()
			else
				instance = child
			end
		end
	end
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

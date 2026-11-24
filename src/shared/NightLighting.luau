-- Ambiance de nuit (docs/design.md « Réalisme sobre ») : assez sombre pour que les lampes comptent, assez claire pour se
-- repérer dans un couloir sans lampe. Technology = Future est réglé dans default.project.json (non modifiable par script).
-- Le brouillard passe par Atmosphere : quand elle existe, Roblox ignore FogStart/FogEnd.
local NightLighting = {
	lighting = {
		ClockTime = 0,
		Brightness = 0.4,
		GlobalShadows = true,
		-- Lumière des zones sans lampe : gris bleuté bas. Mesuré en jeu : à (34, 36, 44) la cage d'escalier fermée
		-- était noire ; à (60, 63, 76) on y distingue les marches et la cave reste sombre face aux pièces éclairées
		Ambient = Color3.fromRGB(60, 63, 76),
		OutdoorAmbient = Color3.fromRGB(60, 64, 78),
		EnvironmentDiffuseScale = 0.15,
		EnvironmentSpecularScale = 0.2,
		ExposureCompensation = 0,
	},
	atmosphere = {
		Density = 0.4,
		Offset = 0,
		Color = Color3.fromRGB(84, 90, 102),
		Decay = Color3.fromRGB(38, 42, 50),
		Glare = 0,
		Haze = 2,
	},
	-- Palette désaturée et légèrement froide ; les lampes restent chaudes par contraste
	colorCorrection = {
		Saturation = -0.45,
		Contrast = 0.12,
		Brightness = 0,
		TintColor = Color3.fromRGB(222, 230, 245),
	},
	-- Couleur des lampes d'ambiance (PointLight et bloc néon)
	lampColor = Color3.fromRGB(255, 214, 170),
}

return NightLighting

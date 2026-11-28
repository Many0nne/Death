-- Vue de la Mort dans l'ombre (#69) : réglages et règles pures, appliqués par Client.DeathSight au seul joueur Mort.
-- L'ombre est son milieu : elle y lit la maison nettement, dans une teinte froide propre au rôle (violet de nuit),
-- au-dessus de l'ambiance commune (Shared.NightLighting, inchangée pour les mortels). Les lampes, rougies et
-- renforcées pour elle seule, brûlent : une zone éclairée tranche sur l'ombre violette et se lit comme un danger. Quand
-- la lumière l'expose, la vue « brûle » (teinte chaude, plus claire) le temps de l'exposition. Les mortels encore en
-- jeu gardent une silhouette pâle (âme), cachée derrière les murs : la vue aide à les repérer dans le noir, pas à
-- travers la maison.
local DeathRules = require(script.Parent.DeathRules)
local Match = require(script.Parent.Match)

local DeathSight = {}

-- Propriétés de Lighting posées par le client du joueur Mort, à la place de Shared.NightLighting.lighting (rétablies
-- quand il quitte le rôle). Ambient est la lumière des zones sans lampe : celle des mortels vaut (60, 63, 76).
-- Réglé en jeu (#69) : à (118, 108, 150) et exposition 0,25, les marches de bois sombre et les meubles du grenier
-- restaient noirs ; à (135, 124, 172) et 0,6, le couloir sombre ressemblait au jour et les pièces éclairées ne
-- tranchaient plus.
DeathSight.lighting = table.freeze({
	Ambient = Color3.fromRGB(128, 116, 168),
	OutdoorAmbient = Color3.fromRGB(120, 110, 160),
	ExposureCompensation = 0.45,
})

-- Brouillard (Atmosphere de Lighting) plus léger et violet : la Mort voit loin dans le noir
DeathSight.atmosphere = table.freeze({
	Density = 0.2,
	Color = Color3.fromRGB(70, 62, 96),
	Decay = Color3.fromRGB(30, 24, 46),
	Haze = 0.5,
})

export type Grade = { Saturation: number, Contrast: number, Brightness: number, TintColor: Color3 }

-- Correction colorimétrique de la Mort : dans l'ombre (`shadow`) et exposée (`light`). Elle remplace pour elle seule
-- la correction de la nuit, l'effet REPLACES de Lighting (Server.NightAmbience), désactivé localement. Saturation
-- presque neutre pour que les lampes restent rouges face à l'ombre violette ; contraste faible (à 0,3, les marches
-- de bois sombre retombaient au noir).
DeathSight.REPLACES = "NightColor"
DeathSight.grade = table.freeze({
	shadow = table.freeze({
		Saturation = -0.1,
		Contrast = 0.05,
		Brightness = 0,
		TintColor = Color3.fromRGB(212, 200, 255),
	}) :: Grade,
	light = table.freeze({
		Saturation = -0.05,
		Contrast = 0.1,
		Brightness = 0.04,
		TintColor = Color3.fromRGB(255, 206, 190),
	}) :: Grade,
})

-- Lampes (PointLight « Light » des parts MapTags.Lamp) vues par la Mort : couleur rouge-orangé et éclat multiplié,
-- pour que la lumière ressorte sur une ombre devenue claire. Le serveur ne réécrit ni l'une ni l'autre après la
-- construction (Server.LightService n'allume et n'éteint que Enabled) : valeurs d'origine rétablies en quittant le rôle.
DeathSight.lamp = table.freeze({
	Color = Color3.fromRGB(255, 105, 40),
	brightnessFactor = 1.6,
})

-- Fondu de la brûlure (secondes de 0 à 1 et de 1 à 0) : vive à l'entrée dans la lumière, lente à s'éteindre
DeathSight.BURN_RISE = 0.15
DeathSight.BURN_FALL = 0.6

-- Silhouette d'un mortel (Highlight, DepthMode Occluded : cachée derrière les murs)
DeathSight.silhouette = table.freeze({
	FillColor = Color3.fromRGB(214, 236, 255),
	FillTransparency = 0.82,
	OutlineColor = Color3.fromRGB(226, 242, 255),
	OutlineTransparency = 0.35,
})

-- Cette méthode permet de savoir si le joueur local voit avec les yeux de la Mort lorsque son rôle de lumière change.
function DeathSight.active(lightRole: string?): boolean
	return lightRole == DeathRules.Role.Death
end

-- Cette méthode permet de savoir si un personnage est une proie à montrer à la Mort lorsque la vue parcourt les
-- joueurs : un mortel en jeu (rôle de lumière Mortal) ou en agonie, pas un mort, un sauvé ni la Mort. `deathBody` :
-- le personnage porte le corps de la Mort (attribut DeathBody), cas d'un faux joueur Mort hors manche, rôle Mortal.
function DeathSight.isPrey(lightRole: string?, mortalState: string?, deathBody: boolean?): boolean
	if lightRole == DeathRules.Role.Death or deathBody == true then
		return false
	end
	return lightRole == DeathRules.Role.Mortal or mortalState == Match.MortalState.Agony
end

-- Cette méthode permet de mélanger la correction de l'ombre et celle de l'exposition lorsque la brûlure avance :
-- `burn` de 0 (ombre) à 1 (pleine lumière).
function DeathSight.gradeAt(burn: number): Grade
	local t = math.clamp(burn, 0, 1)
	local a, b = DeathSight.grade.shadow, DeathSight.grade.light
	return {
		Saturation = a.Saturation + (b.Saturation - a.Saturation) * t,
		Contrast = a.Contrast + (b.Contrast - a.Contrast) * t,
		Brightness = a.Brightness + (b.Brightness - a.Brightness) * t,
		TintColor = a.TintColor:Lerp(b.TintColor, t),
	}
end

return table.freeze(DeathSight)

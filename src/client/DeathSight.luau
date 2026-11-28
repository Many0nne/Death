-- Vue de la Mort dans l'ombre (#69), client, réservée au joueur Mort (réglages et règles : Shared.DeathSight) :
-- - Lighting (lumière ambiante, exposition) et brouillard (Atmosphere) réglés localement, valeurs d'origine rétablies
--   quand le joueur quitte le rôle ; rien n'est écrit côté serveur, les mortels gardent Shared.NightLighting ;
-- - correction colorimétrique propre (« DeathSight » sous Lighting, locale) à la place de celle de la nuit,
--   désactivée localement le temps du rôle ; elle « brûle » vers une teinte chaude quand la Mort est exposée ;
-- - lampes de la maison (PointLight) rougies et renforcées localement : la lumière se lit comme un danger ;
-- - silhouette pâle (Highlight caché derrière les murs) sur chaque mortel en jeu, joueurs et, en Studio, faux joueurs
--   (mannequins tagués MatchAttributes.BotTag, attributs sur le mannequin). Un mortel déjà surligné par l'agonie
--   (Client.AgonyClient, « AgonyReveal ») garde ce seul surlignage.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathLook = require(Shared:WaitForChild("DeathLook"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))
local MapTags = require(Shared:WaitForChild("MapTags"))
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))
local Sight = require(Shared:WaitForChild("DeathSight"))

local LA = LightAttributes

local EFFECT_NAME = "DeathSight"
local OUTLINE_NAME = "DeathSightPrey"
-- Surlignage posé par Client.AgonyClient sur un mortel ranimé révélé à la Mort
local REVEAL_NAME = "AgonyReveal"

type Saved = {
	lighting: { [string]: any },
	atmosphere: { instance: Instance, props: { [string]: any } }?,
	colors: { ColorCorrectionEffect },
	lamps: { [Light]: { color: Color3, brightness: number } },
}

local DeathSight = {}

-- Cette méthode permet de rougir et renforcer une lampe pour la Mort lorsque sa vue se pose ou qu'une lampe apparaît
-- pendant le rôle ; ses valeurs d'origine sont mémorisées une seule fois.
local function burnLamp(memo: Saved, part: Instance)
	local light = part:FindFirstChild("Light")
	if not light or not light:IsA("Light") or memo.lamps[light] then
		return
	end
	memo.lamps[light] = { color = light.Color, brightness = light.Brightness }
	light.Color = Sight.lamp.Color
	light.Brightness *= Sight.lamp.brightnessFactor
end

-- Cette méthode permet de lister les proies à montrer à la Mort lorsque la frame commence : personnages des autres
-- joueurs et mannequins des faux joueurs, retenus par Shared.DeathSight.isPrey.
local function preys(localPlayer: Player): { [Model]: boolean }
	local list = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if
			other ~= localPlayer
			and character
			and Sight.isPrey(other:GetAttribute(LA.LightRole), other:GetAttribute(MatchAttributes.MortalState))
		then
			list[character] = true
		end
	end
	for _, mannequin in CollectionService:GetTagged(MatchAttributes.BotTag) do
		if
			mannequin:IsA("Model")
			and Sight.isPrey(mannequin:GetAttribute(LA.LightRole), mannequin:GetAttribute(MatchAttributes.MortalState))
		then
			list[mannequin] = true
		end
	end
	return list
end

-- Cette méthode permet de créer la silhouette d'un mortel lorsque la Mort le voit pour la première fois.
local function newOutline(model: Model): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = OUTLINE_NAME
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	for property, value in Sight.silhouette do
		(highlight :: any)[property] = value
	end
	highlight.Adornee = model
	highlight.Parent = model
	return highlight
end

-- Cette méthode permet de démarrer la vue de la Mort lorsque le client se lance.
function DeathSight.start()
	local player = Players.LocalPlayer
	local saved: Saved? = nil
	local effect: ColorCorrectionEffect? = nil
	local burn = 0
	local outlines: { [Model]: Highlight } = {}

	CollectionService:GetInstanceAddedSignal(MapTags.Lamp):Connect(function(part)
		if saved then
			burnLamp(saved, part)
		end
	end)

	-- Cette méthode permet de poser la vue de la Mort lorsque le joueur prend le rôle : valeurs d'origine mémorisées.
	local function enable()
		local memo: Saved = { lighting = {}, atmosphere = nil, colors = {}, lamps = {} }
		for property, value in Sight.lighting do
			memo.lighting[property] = (Lighting :: any)[property];
			(Lighting :: any)[property] = value
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			local props = {}
			for property, value in Sight.atmosphere do
				props[property] = (atmosphere :: any)[property];
				(atmosphere :: any)[property] = value
			end
			memo.atmosphere = { instance = atmosphere, props = props }
		end
		-- Seule la correction de la nuit est remplacée : les autres (frisson d'un piège, Client.TrapCues) restent
		for _, child in Lighting:GetChildren() do
			if child:IsA("ColorCorrectionEffect") and child.Name == Sight.REPLACES and child.Enabled then
				table.insert(memo.colors, child)
				child.Enabled = false
			end
		end
		for _, part in CollectionService:GetTagged(MapTags.Lamp) do
			burnLamp(memo, part)
		end
		saved = memo
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = EFFECT_NAME
		grade.Parent = Lighting
		effect = grade
		burn = if player:GetAttribute(LA.Exposed) == true then 1 else 0
		for property, value in Sight.gradeAt(burn) do
			(grade :: any)[property] = value
		end
	end

	-- Cette méthode permet de rendre la vue commune lorsque le joueur quitte le rôle de la Mort.
	local function disable()
		local memo = saved
		if memo then
			for property, value in memo.lighting do
				(Lighting :: any)[property] = value
			end
			local atmosphere = memo.atmosphere
			if atmosphere and atmosphere.instance.Parent then
				for property, value in atmosphere.props do
					(atmosphere.instance :: any)[property] = value
				end
			end
			for _, color in memo.colors do
				color.Enabled = true
			end
			for light, original in memo.lamps do
				light.Color = original.color
				light.Brightness = original.brightness
			end
		end
		saved = nil
		if effect then
			effect:Destroy()
			effect = nil
		end
		for model, highlight in outlines do
			highlight:Destroy()
			outlines[model] = nil
		end
	end

	-- Cette méthode permet de suivre les silhouettes des mortels lorsque la frame commence (créées, masquées sous le
	-- surlignage de l'agonie, retirées quand le mortel sort du jeu).
	local function updateOutlines()
		local seen = preys(player)
		for model in seen do
			local highlight = outlines[model]
			if not highlight or not highlight.Parent then
				highlight = newOutline(model)
				outlines[model] = highlight
			end
			highlight.Enabled = model:FindFirstChild(REVEAL_NAME) == nil
		end
		for model, highlight in outlines do
			if not seen[model] then
				highlight:Destroy()
				outlines[model] = nil
			end
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		local active = Sight.active(player:GetAttribute(LA.LightRole))
		if active ~= (saved ~= nil) then
			if active then
				enable()
			else
				disable()
			end
		end
		if not active then
			return
		end
		local target = if player:GetAttribute(LA.Exposed) == true then 1 else 0
		local level = DeathLook.approach(burn, target, Sight.BURN_RISE, Sight.BURN_FALL, dt)
		if level ~= burn and effect then
			burn = level
			for property, value in Sight.gradeAt(burn) do
				(effect :: any)[property] = value
			end
		end
		updateOutlines()
	end)
end

return DeathSight

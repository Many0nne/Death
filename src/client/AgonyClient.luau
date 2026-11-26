-- Agonie côté client (#6), rendu minimal en attendant le HUD (#9) :
-- - masseur : compressions sur Espace, clic gauche, bouton A de la manette ou bouton tactile, envoyées au serveur
--   (Server.AgonyService les note à leur réception) ; un repère pulse à la cadence attendue et un texte dit le rythme
--   (bon, trop vite, trop lent), l'avancée et la lutte pour l'âme ;
-- - agonisant : temps qui reste, et la lutte quand la faux tire son âme ;
-- - Mort : la lutte en cours, et chaque mortel ranimé surligné à travers les murs tant que RevealedUntil n'est pas
--   passé.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Agony = require(Shared:WaitForChild("Agony"))
local AgonyAttributes = require(Shared:WaitForChild("AgonyAttributes"))
local DeathRules = require(Shared:WaitForChild("DeathRules"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))

local AA = AgonyAttributes
local LA = LightAttributes

local ACTION = "AgonyCompression"
local REVEAL_COLOR = Color3.fromRGB(220, 40, 40)
-- Durée d'affichage du verdict d'une compression (secondes)
local VERDICT_TIME = 0.6

local AgonyClient = {}

-- Cette méthode permet de créer le panneau de l'agonie (texte et repère de cadence) lorsque le client démarre.
local function makePanel(player: Player): (TextLabel, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "AgonyPanel"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -72)
	label.Size = UDim2.fromOffset(460, 34)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(235, 225, 225)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.Visible = false
	label.Parent = gui
	local pulse = Instance.new("Frame")
	pulse.Name = "Pulse"
	pulse.AnchorPoint = Vector2.new(0.5, 0.5)
	pulse.Position = UDim2.new(0.5, 0, 1, -140)
	pulse.Size = UDim2.fromOffset(44, 44)
	pulse.BackgroundColor3 = Color3.fromRGB(200, 40, 50)
	pulse.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pulse
	pulse.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return label, pulse
end

-- Cette méthode permet de traduire la qualité d'une compression en verdict lorsque le serveur la renvoie ; l'écart
-- avec la précédente dit si c'était trop vite ou trop lent.
local function verdict(quality: number, interval: number?): string
	if quality >= 0.95 then
		return "bon rythme"
	end
	if interval == nil then
		return "en rythme…"
	end
	-- Écart local dans la cadence mais note du serveur plus basse : la gigue du réseau, pas le joueur
	if interval >= 60 / GameConfig.MASSAGE_BPM_MAX and interval <= 60 / GameConfig.MASSAGE_BPM_MIN then
		return "presque"
	end
	local tooFast = interval < 60 / GameConfig.MASSAGE_BPM_MAX
	if quality <= 0 then
		return if tooFast then "beaucoup trop vite" else "beaucoup trop lent"
	end
	return if tooFast then "trop vite" else "trop lent"
end

-- Cette méthode permet de démarrer l'agonie côté client lorsque le client se lance.
function AgonyClient.start()
	local player = Players.LocalPlayer
	local event = ReplicatedStorage:WaitForChild(AA.Event) :: RemoteEvent
	local label, pulse = makePanel(player)
	local massaging: number? = nil -- UserId de l'agonisant massé
	local beat = { quality = 0, progress = 0, pull = nil :: number?, at = -math.huge, interval = nil :: number? }
	local lastPress: number? = nil
	local metronome = 0
	local highlights: { [Model]: Highlight } = {}

	-- Cette méthode permet d'envoyer une compression lorsque le masseur appuie (seulement à l'appui, pas au relâché).
	local function compress(_, inputState: Enum.UserInputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local now = os.clock()
		beat.interval = if lastPress then now - lastPress else nil
		lastPress = now
		event:FireServer("Press")
		return Enum.ContextActionResult.Sink
	end

	event.OnClientEvent:Connect(function(kind: string, a, b, c)
		if kind == "Massage" then
			massaging = a
			lastPress = nil
			beat.progress, beat.pull, beat.at = 0, nil, -math.huge
			if massaging then
				ContextActionService:BindActionAtPriority(
					ACTION,
					compress,
					true,
					Enum.ContextActionPriority.High.Value,
					Enum.KeyCode.Space,
					Enum.UserInputType.MouseButton1,
					Enum.KeyCode.ButtonA
				)
				ContextActionService:SetTitle(ACTION, "Masser")
			else
				ContextActionService:UnbindAction(ACTION)
			end
		elseif kind == "Beat" then
			beat.quality, beat.progress, beat.pull, beat.at = a, b, c, os.clock()
		end
	end)

	-- Cette méthode permet de surligner pour la Mort chaque mortel ranimé encore révélé lorsque l'image se rafraîchit.
	local function updateReveals(isDeath: boolean)
		local now = workspace:GetServerTimeNow()
		local seen = {}
		if isDeath then
			for _, other in Players:GetPlayers() do
				local untilTime = other:GetAttribute(AA.RevealedUntil)
				local character = other.Character
				if character and type(untilTime) == "number" and now < untilTime then
					seen[character] = true
					if not highlights[character] then
						local highlight = Instance.new("Highlight")
						highlight.Name = "AgonyReveal"
						highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
						highlight.FillColor = REVEAL_COLOR
						highlight.FillTransparency = 0.75
						highlight.OutlineColor = REVEAL_COLOR
						highlight.Adornee = character
						highlight.Parent = character
						highlights[character] = highlight
					end
				end
			end
		end
		for character, highlight in highlights do
			if not seen[character] then
				highlight:Destroy()
				highlights[character] = nil
			end
		end
	end

	-- Cette méthode permet de trouver la lutte pour l'âme en cours lorsque la Mort regarde son panneau (part sortie).
	local function strugglePull(): number?
		for _, other in Players:GetPlayers() do
			local pull = other:GetAttribute(AA.SoulPull)
			if type(pull) == "number" then
				return pull
			end
		end
		return nil
	end

	RunService.RenderStepped:Connect(function(dt)
		local isDeath = player:GetAttribute(LA.LightRole) == DeathRules.Role.Death
		updateReveals(isDeath)
		local text: string? = nil
		if massaging then
			metronome = (metronome + dt * Agony.TARGET_BPM / 60) % 1
			pulse.Visible = true
			local size = 44 + 20 * (1 - metronome) ^ 3
			pulse.Size = UDim2.fromOffset(size, size)
			-- La lutte commence et avance sans compression : lue sur l'agonisant, pas seulement au retour d'un appui
			local target = Players:GetPlayerByUserId(massaging)
			local livePull = target and target:GetAttribute(AA.SoulPull)
			if type(livePull) == "number" then
				beat.pull = livePull
			end
			local recent = os.clock() - beat.at < VERDICT_TIME
			local rhythm = if recent then verdict(beat.quality, beat.interval) else "appuie en rythme (Espace)"
			if beat.pull then
				text = string.format("Lutte pour l'âme : %d %% sortie, %s", math.floor(beat.pull * 100 + 0.5), rhythm)
			else
				text = string.format("Massage : %d %%, %s", math.floor(beat.progress * 100 + 0.5), rhythm)
			end
		else
			pulse.Visible = false
			metronome = 0
			local agonyEnd = player:GetAttribute(AA.AgonyEnd)
			local ownPull = player:GetAttribute(AA.SoulPull)
			if player:GetAttribute(MatchAttributes.MortalState) == "Agony" and type(agonyEnd) == "number" then
				local left = math.max(0, math.ceil(agonyEnd - workspace:GetServerTimeNow()))
				text = if type(ownPull) == "number"
					then string.format("La faux tire ton âme : %d %%", math.floor(ownPull * 100 + 0.5))
					else string.format("Agonie : %d s. Rampe vers les autres", left)
			elseif isDeath then
				local pull = strugglePull()
				if pull then
					text = string.format("Lutte pour l'âme : %d %% sortie", math.floor(pull * 100 + 0.5))
				end
			end
		end
		label.Visible = text ~= nil
		label.Text = text or ""
	end)
end

return AgonyClient

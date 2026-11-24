-- Rendu de la Mort (client), d'après les attributs du serveur (LightRole, DeathExposed) :
-- - pour un mortel : la Mort est invisible dans l'ombre et apparaît en silhouette noire à la lumière (fondu bref) ;
-- - pour la Mort elle-même : son corps reste visible, voilé dans l'ombre, noir plein à la lumière, avec un indicateur
--   « ombre / lumière » à l'écran ;
-- - pour tous : la Mort ne fait aucun bruit de pas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathRules = require(Shared:WaitForChild("DeathRules"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))

local LA = LightAttributes

-- Vitesse du fondu de la silhouette (part de visibilité par seconde) : 0,2 s pour apparaître ou disparaître
local FADE_RATE = 5
-- Voile de la Mort sur son propre corps (transparence du remplissage noir) : dans l'ombre / à la lumière
local SELF_VEIL = { shadow = 0.6, light = 0.05 }
local SILHOUETTE = Color3.fromRGB(0, 0, 0)

local DeathView = {}

-- Cette méthode permet de créer l'indicateur « ombre / lumière » de la Mort lorsque le client démarre (caché tant
-- que le joueur local n'est pas la Mort).
local function makeIndicator(player: Player): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathLightIndicator"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	local label = Instance.new("TextLabel")
	label.Name = "State"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -24)
	label.Size = UDim2.fromOffset(320, 34)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	label.BackgroundTransparency = 0.35
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return label
end

-- Cette méthode permet d'appliquer la transparence locale à tout le corps d'un personnage lorsque la silhouette
-- change (pièces, accessoires, visage) ; invisible, il ne projette plus d'ombre (qui le trahirait sous une lampe).
local function setLocalTransparency(character: Model, value: number)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = value
			d.CastShadow = value < 1
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = value
		end
	end
end

-- Cette méthode permet de démarrer le rendu de la Mort lorsque le client se lance.
function DeathView.start()
	local localPlayer = Players.LocalPlayer
	local indicator = makeIndicator(localPlayer)
	-- Personnage suivi comme Mort -> { highlight, visibility, muted = { Sound -> volume d'origine }, applied, added }
	local tracked: { [Model]: any } = {}

	-- Cette méthode permet de rendre au personnage son apparence et ses sons lorsqu'il n'est plus la Mort.
	local function release(character: Model)
		local state = tracked[character]
		tracked[character] = nil
		state.added:Disconnect()
		state.highlight:Destroy()
		for sound, volume in state.muted do
			if sound.Parent then
				sound.Volume = volume
			end
		end
		if character.Parent then
			setLocalTransparency(character, 0)
		end
	end

	-- Cette méthode permet de couper à chaque frame les sons du personnage (pas, chute, atterrissage) lorsque c'est la
	-- Mort : le script de sons de Roblox réécrit leur volume à chaque mouvement.
	local function mute(character: Model, state)
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		for _, sound in root:GetChildren() do
			if sound:IsA("Sound") then
				if state.muted[sound] == nil then
					state.muted[sound] = sound.Volume
				end
				sound.Volume = 0
			end
		end
	end

	-- Cette méthode permet de mettre à jour l'apparence de la Mort à chaque frame lorsqu'un joueur a ce rôle : fondu
	-- de la silhouette pour les mortels, voile pour la Mort elle-même.
	local function render(player: Player, character: Model, dt: number)
		local state = tracked[character]
		if not state then
			local highlight = Instance.new("Highlight")
			highlight.Name = "DeathSilhouette"
			highlight.FillColor = SILHOUETTE
			highlight.OutlineColor = SILHOUETTE
			highlight.OutlineTransparency = 1
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Adornee = character
			highlight.Parent = character
			-- applied : transparence locale posée sur le corps ; nil = à reposer (pièce ajoutée, accessoire)
			state = { highlight = highlight, visibility = 0, muted = {}, applied = nil :: number? }
			state.added = character.DescendantAdded:Connect(function()
				state.applied = nil
			end)
			tracked[character] = state
		end
		mute(character, state)
		local exposed = player:GetAttribute(LA.Exposed) == true
		local target = if exposed then 1 else 0
		local step = FADE_RATE * dt
		state.visibility = math.clamp(state.visibility + math.clamp(target - state.visibility, -step, step), 0, 1)
		if player == localPlayer then
			-- Première personne verrouillée (#24) : pas de voile sur ses propres bras, l'indicateur suffit
			state.highlight.Enabled = localPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson
			state.highlight.FillTransparency = SELF_VEIL.shadow
				+ (SELF_VEIL.light - SELF_VEIL.shadow) * state.visibility
		else
			local transparency = 1 - state.visibility
			if state.applied ~= transparency then
				state.applied = transparency
				setLocalTransparency(character, transparency)
			end
			state.highlight.Enabled = state.visibility > 0
			state.highlight.FillTransparency = 1 - state.visibility
		end
	end

	-- Cette méthode permet d'afficher l'état « ombre / lumière » lorsque le joueur local est la Mort.
	local function showIndicator()
		local isDeath = localPlayer:GetAttribute(LA.LightRole) == DeathRules.Role.Death
		indicator.Visible = isDeath
		if not isDeath then
			return
		end
		if localPlayer:GetAttribute(LA.Exposed) == true then
			indicator.Text = "À la lumière : visible et ralentie"
			indicator.TextColor3 = Color3.fromRGB(255, 196, 120)
		else
			indicator.Text = "Dans l'ombre : invisible"
			indicator.TextColor3 = Color3.fromRGB(170, 180, 200)
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		local seen = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character and player:GetAttribute(LA.LightRole) == DeathRules.Role.Death then
				seen[character] = true
				render(player, character, dt)
			end
		end
		for character in tracked do
			if not seen[character] then
				release(character)
			end
		end
		showIndicator()
	end)
end

return DeathView

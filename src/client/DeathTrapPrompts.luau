-- Invites de la Mort sur les pièges (#49) : préparer ou désarmer, souffler ou abandonner. Elles n'existent que sur ce
-- client (le serveur ne les crée pas, un client mortel ne peut donc rien y lire) : une paire par point fragile (tag
-- MapTags.TrapCandidate), réglée d'après l'état privé que le serveur publie dans le conteneur privé du joueur
-- (Shared.TrapAttributes : souffle, TrapStates). Elles portent les attributs de LightAttributes, filtrées par
-- Client.LightPrompts comme les autres (rôle, vue, regard). Tenue et déclenchement sont envoyés au serveur par
-- TrapAttributes.ActionEvent, qui revérifie tout (Server.TrapService) : le client n'est qu'un affichage.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathRules = require(Shared:WaitForChild("DeathRules"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))
local MapTags = require(Shared:WaitForChild("MapTags"))
local TrapAttributes = require(Shared:WaitForChild("TrapAttributes"))
local TrapPrompts = require(Shared:WaitForChild("TrapPrompts"))
local Traps = require(Shared:WaitForChild("Traps"))

local LA = LightAttributes
local TA = TrapAttributes
local Action = TrapPrompts.Action
local Phase = TA.ActionPhase

local DeathTrapPrompts = {}

type Entry = { id: string, kind: string, prompts: { [string]: ProximityPrompt } }

-- Cette méthode permet de démarrer les invites de la Mort lorsque le client se lance (sans attendre : conteneur privé
-- et événement sont attendus en tâche de fond).
function DeathTrapPrompts.start()
	local player = Players.LocalPlayer
	local entries: { [Instance]: Entry } = {}
	-- Identifiants déjà pris : comme le serveur, seul le premier objet d'un identifiant en double a ses invites
	local ids: { [string]: Instance } = {}
	-- Invites en cours de maintien : la fin est envoyée au serveur si l'invite disparaît avant (bruit arrêté)
	local holding: { [ProximityPrompt]: boolean } = {}
	local private: Instance? = nil
	local event: RemoteEvent? = nil

	-- Cette méthode permet d'envoyer au serveur une invite tenue, lâchée ou déclenchée lorsque le joueur agit.
	local function send(phase: string, id: string, action: string)
		if event then
			event:FireServer(phase, id, action)
		end
	end

	-- Cette méthode permet de régler les invites d'un point fragile lorsque l'état privé change (texte, maintien,
	-- disponibilité) ; sans état de la Mort publié, elles restent indisponibles.
	local function refresh(entry: Entry)
		local container = private
		local charges = container and container:GetAttribute(TA.BreathCharges)
		local states = container and container:FindFirstChild(TA.TrapStates)
		for action, prompt in entry.prompts do
			local available = false
			if type(charges) == "number" then
				local state = (states and states:GetAttribute(entry.id)) or Traps.State.Idle
				local step = (states and states:GetAttribute(entry.id .. TA.StepSuffix)) or 0
				local view = TrapPrompts.deathView(entry.kind, action, state, step, charges)
				-- Propriétés réécrites seulement au changement : un maintien en cours n'est pas remis à zéro
				if prompt.ActionText ~= view.text then
					prompt.ActionText = view.text
				end
				if prompt.HoldDuration ~= view.hold then
					prompt.HoldDuration = view.hold
				end
				available = view.available
			end
			if prompt:GetAttribute(LA.PromptAvailable) ~= available then
				prompt:SetAttribute(LA.PromptAvailable, available)
			end
		end
	end

	-- Cette méthode permet de régler toutes les invites lorsque le souffle ou l'état d'un piège change.
	local function refreshAll()
		for _, entry in entries do
			refresh(entry)
		end
	end

	-- Cette méthode permet de créer les deux invites de la Mort sur un point fragile lorsqu'il arrive sur le client.
	local function add(part: Instance)
		if entries[part] or not part:IsA("BasePart") then
			return
		end
		local kind = part:GetAttribute(MapTags.Attributes.TrapKind)
		if type(kind) ~= "string" or not Traps.KINDS[kind] then
			return
		end
		local id = TrapPrompts.idOf(part)
		if ids[id] or not TrapPrompts.isValidId(id) then
			return
		end
		ids[id] = part
		local entry: Entry = { id = id, kind = kind, prompts = {} }
		for _, action in { Action.Work, Action.Blow } do
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = TA.DeathPromptName
			prompt.Enabled = false
			prompt.RequiresLineOfSight = false
			for property, value in TrapPrompts.props(kind, action) do
				(prompt :: any)[property] = value
			end
			prompt:SetAttribute(LA.PromptRole, DeathRules.Role.Death)
			prompt:SetAttribute(LA.PromptAvailable, false)
			prompt:SetAttribute(LA.PromptSight, true)
			prompt:AddTag(LA.PromptTag)
			prompt.PromptButtonHoldBegan:Connect(function()
				holding[prompt] = true
				send(Phase.Began, entry.id, action)
			end)
			prompt.PromptButtonHoldEnded:Connect(function()
				holding[prompt] = nil
				send(Phase.Ended, entry.id, action)
			end)
			prompt.Triggered:Connect(function()
				send(Phase.Triggered, entry.id, action)
			end)
			prompt.Parent = part
			entry.prompts[action] = prompt
		end
		entries[part] = entry
		refresh(entry)
	end

	-- Cette méthode permet d'oublier un point fragile lorsqu'il quitte le client (streaming, maison reconstruite).
	local function remove(part: Instance)
		local entry = entries[part]
		entries[part] = nil
		if entry then
			if ids[entry.id] == part then
				ids[entry.id] = nil
			end
			for action, prompt in entry.prompts do
				if holding[prompt] then
					holding[prompt] = nil
					send(Phase.Ended, entry.id, action)
				end
				prompt:Destroy()
			end
		end
	end

	for _, part in CollectionService:GetTagged(MapTags.TrapCandidate) do
		add(part)
	end
	CollectionService:GetInstanceAddedSignal(MapTags.TrapCandidate):Connect(add)
	CollectionService:GetInstanceRemovedSignal(MapTags.TrapCandidate):Connect(remove)

	-- Cette méthode permet de suivre le dossier TrapStates lorsqu'il apparaît dans le conteneur privé.
	local function watchStates(child: Instance)
		if child.Name == TA.TrapStates then
			child.AttributeChanged:Connect(refreshAll)
			refreshAll()
		end
	end

	-- Cette méthode permet de suivre le conteneur privé lorsque le serveur le crée (souffle, états des pièges).
	local function bind(container: Instance)
		if container.Name ~= TA.PrivateName or private == container then
			return
		end
		private = container
		-- Seul le souffle change les invites (pas la dissipation ni la recharge, qui bougent souvent)
		container:GetAttributeChangedSignal(TA.BreathCharges):Connect(refreshAll)
		container.ChildAdded:Connect(watchStates)
		container.ChildRemoved:Connect(refreshAll)
		for _, child in container:GetChildren() do
			watchStates(child)
		end
		refreshAll()
	end

	task.spawn(function()
		event = ReplicatedStorage:WaitForChild(TA.ActionEvent) :: RemoteEvent
	end)
	task.spawn(function()
		local gui = player:WaitForChild("PlayerGui")
		gui.ChildAdded:Connect(bind)
		local existing = gui:FindFirstChild(TA.PrivateName)
		if existing then
			bind(existing)
		end
	end)
end

return DeathTrapPrompts

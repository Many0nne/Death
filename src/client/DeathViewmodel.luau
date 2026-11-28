-- Mains et faux de la Mort en première personne (#74), pour le seul joueur Mort, pendant la manche. Monté par
-- Client.Viewmodel à partir du modèle de la Mort (ReplicatedStorage.Characters.Death : bras du rig R15 et leurs os,
-- maillage des mains, faux), poses et états de Shared.DeathViewmodelPose. Les états suivent les vrais événements :
-- - main tendue : une invite de la Mort tenue (préparer ou désarmer un piège, griller une ampoule, couper le
--   disjoncteur ; ProximityPromptService), vers l'objet de l'invite ;
-- - souffle : une charge de souffle dépensée (conteneur privé, Shared.TrapAttributes.BreathCharges) ;
-- - fauchage : l'invite « Faucher » tenue (avancée = temps tenu / durée de l'invite) ;
-- - traction : une lutte pour l'âme en cours (attribut SoulPull sur l'agonisant, joueur ou faux joueur de debug).
-- Dans l'ombre, mains et faux sont voilées de noir et à demi transparentes ; à la lumière, pleines.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgonyAttributes = require(Shared:WaitForChild("AgonyAttributes"))
local CameraRules = require(Shared:WaitForChild("CameraRules"))
local DeathLook = require(Shared:WaitForChild("DeathLook"))
local DeathRules = require(Shared:WaitForChild("DeathRules"))
local DeathViewmodelPose = require(Shared:WaitForChild("DeathViewmodelPose"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))
local Match = require(Shared:WaitForChild("Match"))
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))
local TrapAttributes = require(Shared:WaitForChild("TrapAttributes"))
local ViewmodelMotion = require(Shared:WaitForChild("ViewmodelMotion"))
local Viewmodel = require(script.Parent:WaitForChild("Viewmodel"))

local State = DeathViewmodelPose.State

-- Pièces du modèle de la Mort gardées (docs/assets.md) : maillage des mains, faux, et les pièces du rig qui portent
-- les os du maillage (invisibles) ; le reste (voile, robe, lanières, manches, torse, jambes, tête) est retiré du clone
local LEFT = { "LeftUpperArm", "LeftLowerArm", "LeftHand" }
local RIGHT = { "RightUpperArm", "RightLowerArm", "RightHand" }
local CORE = { "UpperTorso" }
local SCYTHE_NAME = "Scythe"
local ARM_NAME = "Arm"
local HANDS_NAME = "Hands"
-- Couleur des manches d'ombre : celle de la robe et des manches du modèle (tools/models/death.manifest.json)
local SLEEVE_COLOR = Color3.fromRGB(12, 12, 15)
-- Attribut du modèle du viewmodel qui porte l'état affiché (Shared.DeathViewmodelPose.State)
local STATE_ATTRIBUTE = "State"
-- Constante de temps du balancement quand la caméra tourne (secondes)
local SWAY_TAU = 0.12
-- Période de répétition des gestes imposés par l'attribut de debug (souffle, fauchage), secondes
local DEBUG_LOOP = { [State.Blow] = 1.5, [State.Reap] = DeathViewmodelPose.REAP_TIME + 1 }

local DeathViewmodel = {}

-- Cette méthode permet de construire le viewmodel lorsque le joueur devient la Mort pour la première fois : clone du
-- modèle de la Mort réduit aux bras, aux mains et à la faux ; nil si le modèle manque (place sans les assets).
local function build(): any
	local characters = ReplicatedStorage:FindFirstChild("Characters")
	local template = characters and characters:FindFirstChild("Death")
	if not template or not template:IsA("Model") then
		warn("[Mort] ReplicatedStorage.Characters.Death introuvable : pas de mains en première personne")
		return nil
	end
	local model = template:Clone()
	model.Name = "DeathViewmodel"
	local root = model:FindFirstChild("HumanoidRootPart")
	-- repère de la racine : les mesures du modèle (Shared.DeathViewmodelPose) y sont exprimées, et une pose sans
	-- rotation garde l'orientation naturelle des bras par rapport au corps
	local rootFrame = if root and root:IsA("BasePart") then root.CFrame else CFrame.identity
	local keep = { [SCYTHE_NAME] = true, [ARM_NAME] = true }
	for _, list in { LEFT, RIGHT, CORE } do
		for _, name in list do
			keep[name] = true
		end
	end
	for _, child in model:GetChildren() do
		if not keep[child.Name] then
			child:Destroy()
		end
	end
	local arm = model:FindFirstChild(ARM_NAME)
	local hands = arm and arm:FindFirstChild(HANDS_NAME)
	local scythe = model:FindFirstChild(SCYTHE_NAME)
	if not hands or not hands:IsA("BasePart") then
		warn("[Mort] maillage des mains introuvable dans le modèle de la Mort : pas de mains en première personne")
		model:Destroy()
		return nil
	end
	-- manches du modèle retirées : elles couvriraient la moitié de l'écran (constaté) ; des manches d'ombre les
	-- remplacent (Shared.DeathViewmodelPose.SLEEVES)
	for _, child in arm:GetChildren() do
		if child ~= hands and child:IsA("BasePart") then
			child:Destroy()
		end
	end

	-- Cette méthode permet de relever les pièces nommées d'un groupe lorsque le viewmodel est construit.
	local function collect(names: { string }): { BasePart }
		local parts = {}
		for _, name in names do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				table.insert(parts, part)
			end
		end
		return parts
	end

	-- Cette méthode permet de créer la manche d'ombre d'un bras lorsque le viewmodel est construit, posée au repos dans
	-- le repère de la racine du modèle.
	local function sleeve(side: string): BasePart
		local frame, size = DeathViewmodelPose.sleeve(side)
		local part = Instance.new("Part")
		part.Name = "ShadowSleeve" .. side
		part.Material = Enum.Material.Fabric
		part.Color = SLEEVE_COLOR
		part.Size = size
		part.CFrame = rootFrame * frame
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		part.Parent = model
		return part
	end

	local blade = {}
	if scythe then
		for _, d in scythe:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(blade, d)
			end
		end
	end
	-- Un clone du maillage des mains par main (Shared.DeathViewmodelPose : le maillage est rigide, chaque clone est
	-- posé de sorte que son autre main reste hors du champ), chacun avec sa manche d'ombre. Les pièces du rig
	-- (invisibles, gardées avec les os du maillage) suivent le clone droit.
	local rightHands = hands:Clone()
	rightHands.Name = HANDS_NAME .. "Right"
	rightHands.Parent = arm
	hands.Name = HANDS_NAME .. "Left"
	local left = { hands, sleeve("left") }
	local right = { rightHands, sleeve("right") }
	for _, list in { LEFT, RIGHT, CORE } do
		for _, part in collect(list) do
			table.insert(right, part)
		end
	end
	local rightHand = model:FindFirstChild("RightHand")
	-- ancre : position de la pièce RightHand, orientation du corps (Shared.DeathViewmodelPose.ANCHOR)
	local anchor = rootFrame
		* CFrame.new(
			if rightHand and rightHand:IsA("BasePart")
				then rootFrame:PointToObjectSpace(rightHand.Position)
				else DeathViewmodelPose.ANCHOR
		)
	return Viewmodel.new(model, {
		left = { anchor = anchor, parts = left },
		right = { anchor = anchor, parts = right },
		scythe = { anchor = anchor, parts = blade },
	})
end

-- Cette méthode permet de trouver la position de l'objet d'une invite lorsque la main se tend vers lui (pièce,
-- point d'attache ou modèle parent) ; nil si l'invite n'est plus dans le monde.
local function promptTarget(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent == nil then
		return nil
	end
	if parent:IsA("BasePart") then
		return parent.Position
	end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	if parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

-- Cette méthode permet de trouver la lutte pour l'âme en cours lorsque l'image est rendue : part de l'âme sortie, lue
-- sur les joueurs et les faux joueurs de debug (une seule Mort : toute lutte est la sienne) ; nil sans lutte.
local function soulPull(): number?
	for _, other in Players:GetPlayers() do
		local pull = other:GetAttribute(AgonyAttributes.SoulPull)
		if type(pull) == "number" then
			return pull
		end
	end
	for _, mannequin in CollectionService:GetTagged(MatchAttributes.BotTag) do
		local pull = mannequin:GetAttribute(AgonyAttributes.SoulPull)
		if type(pull) == "number" then
			return pull
		end
	end
	return nil
end

-- Cette méthode permet de démarrer le viewmodel de la Mort lorsque le client se lance.
function DeathViewmodel.start()
	local player = Players.LocalPlayer
	local studio = RunService:IsStudio()
	local viewmodel = nil
	local built = false
	-- invite de la Mort tenue : { prompt, start, reap }
	local holding: { prompt: ProximityPrompt, start: number, reap: boolean }? = nil
	local blowAt: number? = nil
	local state = State.Rest
	local shown: { [string]: CFrame } = {}
	local fadeFrom: { [string]: CFrame } = {}
	local changedAt = -math.huge
	local light = 0
	local sway = Vector3.zero
	local lastLook: Vector3? = nil
	local debugValue: any = nil
	local debugSetAt = 0

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if prompt:GetAttribute(LightAttributes.PromptRole) == DeathRules.Role.Death then
			holding = { prompt = prompt, start = os.clock(), reap = prompt.Name == AgonyAttributes.PromptName }
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		if holding and holding.prompt == prompt then
			holding = nil
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if holding and holding.prompt == prompt then
			holding = nil
		end
	end)

	-- Souffle : la charge dépensée se lit dans le conteneur privé (seul ce joueur le reçoit)
	task.spawn(function()
		local private = player:WaitForChild("PlayerGui"):WaitForChild(TrapAttributes.PrivateName)
		local charges = private:GetAttribute(TrapAttributes.BreathCharges)
		private:GetAttributeChangedSignal(TrapAttributes.BreathCharges):Connect(function()
			local now = private:GetAttribute(TrapAttributes.BreathCharges)
			if type(now) == "number" and type(charges) == "number" and now < charges then
				blowAt = os.clock()
			end
			charges = now
		end)
	end)

	player:GetAttributeChangedSignal(DeathViewmodelPose.DEBUG_ATTRIBUTE):Connect(function()
		debugValue = player:GetAttribute(DeathViewmodelPose.DEBUG_ATTRIBUTE)
		debugSetAt = os.clock()
	end)

	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		local active = camera ~= nil
			and player:GetAttribute(MatchAttributes.Role) == Match.Role.Death
			and CameraRules.modeFor(
					ReplicatedStorage:GetAttribute(MatchAttributes.Phase),
					player:GetAttribute(MatchAttributes.Role),
					player:GetAttribute(MatchAttributes.MortalState)
				)
				== CameraRules.Mode.FirstPerson
		if active and not built then
			built = true
			viewmodel = build()
		end
		if not viewmodel then
			return
		end
		viewmodel:show(active)
		if not active then
			holding, lastLook = nil, nil
			return
		end
		local now = os.clock()
		local cameraCFrame = camera.CFrame

		-- Invite lâchée sans signal (détruite, désactivée, hors de portée) : la main revient
		if holding and (holding.prompt.Parent == nil or not holding.prompt.Enabled) then
			holding = nil
		end
		local pull = soulPull()
		local info = {
			t = now,
			moving = 0,
			target = nil :: Vector3?,
			progress = nil :: number?,
			pull = pull,
			blowAge = if blowAt then now - blowAt else nil,
		}
		local wanted = DeathViewmodelPose.choose({
			pull = pull,
			reaping = holding ~= nil and holding.reap,
			reaching = holding ~= nil and not holding.reap,
			blowAge = info.blowAge,
		})
		if holding then
			local hold = math.max(holding.prompt.HoldDuration, 1e-3)
			info.progress = math.clamp((now - holding.start) / hold, 0, 1)
			local target = promptTarget(holding.prompt)
			if target then
				info.target = cameraCFrame:VectorToObjectSpace(target - cameraCFrame.Position)
			end
		end
		-- Studio : état imposé pour les captures (gestes répétés en boucle)
		local forced, amount = nil, nil
		if studio then
			forced, amount = DeathViewmodelPose.parseDebug(debugValue)
		end
		if forced then
			wanted = forced
			local age = now - debugSetAt
			local loop = DEBUG_LOOP[forced]
			if forced == State.Blow then
				info.blowAge = amount or age % loop
			elseif forced == State.Reap then
				info.progress = amount or math.min((age % loop) / DeathViewmodelPose.REAP_TIME, 1)
			elseif forced == State.Pull then
				info.pull = amount or (0.5 + 0.5 * math.sin(age))
			end
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local v = root.AssemblyLinearVelocity
			info.moving = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / DeathRules.SPEED_SHADOW, 0, 1)
		end

		-- Balancement : la main traîne quand le regard tourne
		local look = cameraCFrame.LookVector
		local target = Vector3.zero
		if lastLook and dt > 0 then
			local local_ = cameraCFrame:VectorToObjectSpace(lastLook)
			-- l'ancien regard vu du nouveau : à droite quand la caméra a tourné vers la gauche
			target = ViewmodelMotion.sway(local_.X / dt, -local_.Y / dt)
		end
		lastLook = look
		sway = sway:Lerp(target, ViewmodelMotion.smoothing(dt, SWAY_TAU))

		if wanted ~= state then
			state = wanted
			fadeFrom = shown
			changedAt = now
			-- lisible depuis Studio (vérification des événements), sans effet sur le jeu
			viewmodel.model:SetAttribute(STATE_ATTRIBUTE, state)
		end
		local poses = ViewmodelMotion.crossfade(
			fadeFrom,
			DeathViewmodelPose.frames(state, info),
			now - changedAt,
			DeathViewmodelPose.BLEND_TIME
		)
		for name, pose in poses do
			poses[name] = CFrame.new(sway) * pose
		end
		shown = poses
		viewmodel:render(cameraCFrame, poses :: any)

		local exposed = player:GetAttribute(LightAttributes.Exposed) == true
		light = DeathLook.approach(
			light,
			if exposed then 1 else 0,
			DeathViewmodelPose.FADE_TIME,
			DeathViewmodelPose.FADE_TIME,
			dt
		)
		viewmodel:setLook(DeathViewmodelPose.look(light))
	end)
end

return DeathViewmodel

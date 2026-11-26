-- Contrôleur de la Mort (serveur) : décide qui agit comme la Mort ou comme mortel sur la lumière (attribut LightRole),
-- règle la vitesse de la Mort selon la lumière et publie son exposition (attribut DeathExposed), que chaque client
-- traduit en silhouette ou en invisibilité (Client.DeathView). Pas d'attaque directe : la Mort n'a ni arme ni
-- collision avec les mortels (groupes de collision), elle ne peut même pas leur barrer le passage.
--
-- API, via `DeathController.get()` : :roleOf(player), :getDeath(), :isExposed(), :setRooted(player, rooted) (la Mort
-- immobile pendant la lutte pour une âme, #6).
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeathRules = require(Shared.DeathRules)
local LightAttributes = require(Shared.LightAttributes)
local MapTags = require(Shared.MapTags)
local Match = require(Shared.Match)

local LA = LightAttributes
local Role = DeathRules.Role

-- Groupes de collision : la Mort traverse les mortels (et inversement), les deux heurtent le décor
local GROUP_DEATH = "Death"
local GROUP_MORTALS = "Mortals"

local DeathController = {}
DeathController.__index = DeathController

-- Cette méthode permet de construire les dépendances réelles lorsque le contrôleur est créé en jeu.
local function defaultDeps()
	local RunService = game:GetService("RunService")
	return {
		players = game:GetService("Players"),
		match = require(script.Parent.MatchService).get(),
		lights = require(script.Parent.LightService).get(),
		heartbeat = RunService.Heartbeat,
		isStudio = RunService:IsStudio(),
		log = function(message)
			print("[Mort] " .. message)
		end,
	}
end

-- Cette méthode permet de créer le contrôleur à l'arrêt lorsqu'on veut l'instance du jeu (`get`) ou un contrôleur
-- isolé.
function DeathController.new(deps)
	return setmetatable({
		deps = deps or defaultDeps(),
		started = false,
		roles = {} :: { [any]: string }, -- Player -> rôle effectif publié
		characters = {} :: { [any]: Model }, -- Player -> personnage auquel le rôle a été appliqué
		-- Player -> exposition, pour chaque joueur Mort (une seule en manche ; plusieurs possibles en bac à sable)
		exposures = {} :: { [any]: DeathRules.Exposure },
		rooted = {} :: { [any]: boolean }, -- Player -> immobilisé (lutte pour une âme)
	}, DeathController)
end

local instance = nil

-- Cette méthode permet de récupérer le contrôleur du serveur lorsqu'un autre module doit savoir qui est la Mort.
function DeathController.get()
	if not instance then
		instance = DeathController.new()
	end
	return instance
end

-- Cette méthode permet de déclarer les groupes de collision et de suivre joueurs et frames lorsque le serveur démarre
-- (une seule fois).
function DeathController:start()
	if self.started then
		return
	end
	self.started = true
	PhysicsService:RegisterCollisionGroup(GROUP_DEATH)
	PhysicsService:RegisterCollisionGroup(GROUP_MORTALS)
	PhysicsService:CollisionGroupSetCollidable(GROUP_DEATH, GROUP_MORTALS, false)
	local players = self.deps.players
	for _, player in players:GetPlayers() do
		self:_watchPlayer(player)
	end
	players.PlayerAdded:Connect(function(player)
		self:_watchPlayer(player)
	end)
	players.PlayerRemoving:Connect(function(player)
		self.roles[player] = nil
		self.characters[player] = nil
		self.exposures[player] = nil
		self.rooted[player] = nil
	end)
	self.deps.heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
end

-- Lecture ------------------------------------------------------------------------------------------------------

-- Cette méthode permet de lire le rôle effectif d'un joueur pour la lumière lorsque disjoncteur ou ampoules le
-- demandent ("Death", "Mortal" ou nil).
function DeathController:roleOf(player): string?
	return self.roles[player]
end

-- Cette méthode permet de trouver le joueur qui joue la Mort lorsqu'un système agit sur elle (nil sinon ; en bac à
-- sable avec plusieurs Morts, la première trouvée).
function DeathController:getDeath(): any
	return next(self.exposures)
end

-- Cette méthode permet de savoir si un joueur Mort est éclairé lorsqu'un système en dépend (silhouette, préparation).
function DeathController:isExposed(player): boolean
	local exposure = self.exposures[player]
	return exposure ~= nil and exposure.exposed
end

-- Cette méthode permet d'immobiliser la Mort ou de lui rendre sa vitesse lorsque sa faux tire une âme (lutte pendant
-- un massage, Server.AgonyService).
function DeathController:setRooted(player, rooted: boolean)
	self.rooted[player] = if rooted then true else nil
end

-- Boucle -------------------------------------------------------------------------------------------------------

-- Cette méthode permet de calculer le rôle effectif d'un joueur lorsque la manche ou le debug change (règle pure
-- DeathRules.lightRole).
function DeathController:_computeRole(player): string?
	local match = self.deps.match
	local running = match:getPhase() == Match.Phase.Running
	return DeathRules.lightRole({
		running = running,
		matchRole = if running then match:getRole(player) else nil,
		alive = running and match:getMortalState(player) == Match.MortalState.Alive,
		isStudio = self.deps.isStudio,
		debugDeath = player:GetAttribute(LA.DebugDeath) == true,
	})
end

-- Cette méthode permet d'avancer d'une frame lorsque le Heartbeat tombe : rôles publiés, puis vitesse et exposition
-- de chaque joueur Mort selon la lumière à sa position.
function DeathController:_step(dt: number)
	for _, player in self.deps.players:GetPlayers() do
		local role = self:_computeRole(player)
		local character = player.Character
		if role ~= self.roles[player] or character ~= self.characters[player] then
			self:_applyRole(player, role, character)
		end
		if role == Role.Death then
			self:_stepDeath(player, dt)
		end
	end
end

-- Cette méthode permet de régler vitesse et exposition d'un joueur Mort lorsqu'une frame passe : silhouette dès
-- qu'il est éclairé, invisible après un court délai d'ombre.
function DeathController:_stepDeath(player, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local exposure = self.exposures[player]
	local lit = self.deps.lights:isLit(root.Position)
	local was = exposure.exposed
	local exposed = DeathRules.updateExposure(exposure, lit, dt)
	if exposed ~= was or player:GetAttribute(LA.Exposed) == nil then
		player:SetAttribute(LA.Exposed, exposed)
	end
	-- Réécrite à chaque frame : un autre script (ou un reset du personnage) ne peut pas la faire dériver
	humanoid.WalkSpeed = if self.rooted[player] then 0 else DeathRules.speed(exposed)
end

-- Cette méthode permet d'appliquer un rôle à un joueur et à son personnage lorsqu'il change ou que le personnage
-- réapparaît : attribut LightRole, groupe de collision, nom masqué et vitesse de la Mort, ou retour à la normale.
function DeathController:_applyRole(player, role: string?, character: Model?)
	local previous = self.roles[player]
	self.roles[player] = role
	self.characters[player] = character
	player:SetAttribute(LA.LightRole, role)
	if role ~= Role.Death then
		self.exposures[player] = nil
		player:SetAttribute(LA.Exposed, nil)
	elseif previous ~= role then
		self.exposures[player] = DeathRules.newExposure()
	end
	if previous ~= role then
		self.deps.log(string.format("%s : rôle lumière %s", player.Name, tostring(role)))
	end
	if not character then
		return
	end
	local isDeath = role == Role.Death
	local group = if isDeath then GROUP_DEATH else GROUP_MORTALS
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Le nom au-dessus de la tête trahirait la Mort cachée dans l'ombre
		humanoid.DisplayDistanceType = if isDeath
			then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
		if not isDeath and previous == Role.Death then
			humanoid.WalkSpeed = DeathRules.MORTAL_SPEED
		end
	end
end

-- Cette méthode permet de suivre un joueur lorsqu'il rejoint le serveur : groupe de collision des pièces ajoutées
-- plus tard (accessoires) et, en Studio, l'attribut DebugDeath.
function DeathController:_watchPlayer(player)
	-- Cette méthode permet de ranger dans le bon groupe chaque pièce ajoutée à un personnage lorsqu'il s'équipe.
	local function watchCharacter(character: Model)
		character.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then
				part.CollisionGroup = if self.roles[player] == Role.Death then GROUP_DEATH else GROUP_MORTALS
			end
		end)
	end
	-- Personnage déjà présent au démarrage : CharacterAdded ne se déclenchera pas pour lui
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	if self.deps.isStudio then
		player.AttributeChanged:Connect(function(name)
			if name == LA.DebugDeath and player:GetAttribute(name) == true then
				self:_toDeathSpawn(player)
			end
		end)
	end
end

-- Cette méthode permet de téléporter un joueur sur une apparition de la Mort (cave) lorsque DebugDeath l'active hors
-- manche, pour tester la Mort seul en Studio.
function DeathController:_toDeathSpawn(player)
	if self.deps.match:getPhase() == Match.Phase.Running then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	for _, spawn in game:GetService("CollectionService"):GetTagged(MapTags.DeathSpawn) do
		if spawn:IsA("BasePart") then
			character:PivotTo(CFrame.new(spawn.Position + Vector3.new(0, 3, 0)))
			return
		end
	end
end

return DeathController

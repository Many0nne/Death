-- Objectif de fuite (#7), abonné aux événements de Server.MatchService (son API n'est pas modifiée) :
-- - MatchStarted : clés posées au hasard sur les ancrages KeySpot (Shared.Escape), une ProximityPrompt par clé ;
-- - toutes les clés trouvées : la voiture du garage propose « Démarrer » (action maintenue) ;
-- - voiture démarrée : la porte du garage s'ouvre, une balise marque la sortie, et un mortel vivant qui l'atteint est
--   sauvé (MatchService:save) ;
-- - fin, annulation ou retour à l'attente : clés retirées, voiture et porte remises en place.
-- État répliqué pour le HUD (#9) sur ReplicatedStorage : MatchAttributes.KeysFound, KeysNeeded, CarStarted.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Escape = require(Shared.Escape)
local GameConfig = require(Shared.GameConfig)
local MapTags = require(Shared.MapTags)
local Match = require(Shared.Match)
local MatchAttributes = require(Shared.MatchAttributes)

local A = MatchAttributes
local EscapeService = {}

-- Intervalle de surveillance de la sortie, en secondes (inutile de tester à chaque frame)
local EXIT_CHECK_INTERVAL = 0.1
-- Hauteur de la zone de sortie au-dessus du sol : la racine d'un personnage debout est à ≈ 3 studs
local EXIT_HEIGHT = 6
local KEY_COLOR = Color3.fromRGB(200, 170, 60)
local EXIT_COLOR = Color3.fromRGB(90, 200, 110)

-- Cette méthode permet de trouver la première pièce taguée sous la maison lorsque le service démarre (sortie,
-- voiture, porte du garage).
local function findTagged(house: Instance, tag: string): Instance?
	for _, d in house:GetDescendants() do
		if d:HasTag(tag) then
			return d
		end
	end
	return nil
end

-- Cette méthode permet de créer une action maintenue (ProximityPrompt) lorsque l'on propose de ramasser une clé ou
-- de démarrer la voiture.
local function makePrompt(parent: Instance, objectText: string, actionText: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 8
	-- Les clés sont posées sur les meubles et la voiture est large : pas de ligne de vue exigée
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

-- Cette méthode permet de brancher l'objectif de fuite sur le service de manche lorsque le serveur démarre ; `house`
-- est le modèle construit par Server.HouseBuilder (KeySpot, EscapeCar, Exit, GarageDoor).
function EscapeService.start(matchService, house: Instance)
	local exit = findTagged(house, MapTags.Exit) :: BasePart
	local car = findTagged(house, MapTags.EscapeCar) :: Model
	local garageDoor = findTagged(house, MapTags.GarageDoor) :: BasePart?
	assert(exit and car and car.PrimaryPart, "maison sans sortie ou sans voiture taguée")
	local exitRoom = exit:GetAttribute(MapTags.Attributes.RoomId)
	local spots: { [string]: BasePart } = {}
	local spotList: { Escape.Spot } = {}
	for _, d in house:GetDescendants() do
		if d:IsA("BasePart") and d:HasTag(MapTags.KeySpot) then
			local id = d:GetAttribute(MapTags.Attributes.AnchorId)
			spots[id] = d
			table.insert(spotList, { id = id, room = d:GetAttribute(MapTags.Attributes.RoomId) })
		end
	end
	local doorState = garageDoor and { transparency = garageDoor.Transparency, canCollide = garageDoor.CanCollide }

	local rng = Random.new()
	local objective = nil -- Escape de la manche en cours
	local keyParts: { [string]: BasePart } = {}
	local carPrompt = makePrompt(car.PrimaryPart, "Voiture", "Démarrer", GameConfig.CAR_START_DURATION)
	carPrompt.Enabled = false
	local beacon: BasePart? = nil
	local exitClock = 0

	-- Cette méthode permet de répliquer l'état de l'objectif lorsqu'il change (nil hors manche).
	local function publish()
		ReplicatedStorage:SetAttribute(A.KeysFound, objective and objective.keysFound)
		ReplicatedStorage:SetAttribute(A.KeysNeeded, objective and objective.keysNeeded)
		ReplicatedStorage:SetAttribute(A.CarStarted, objective and objective.carStarted)
	end

	-- Cette méthode permet de savoir si un joueur peut agir sur l'objectif lorsqu'il déclenche une action.
	local function canAct(player: Player): boolean
		return Escape.canAct(matchService:getRole(player), matchService:getMortalState(player))
	end

	-- Cette méthode permet d'ouvrir la sortie lorsque la voiture démarre : porte du garage ouverte, balise verte au
	-- sol sur la sortie.
	local function openExit()
		if garageDoor then
			garageDoor.Transparency = 1
			garageDoor.CanCollide = false
		end
		local marker = Instance.new("Part")
		marker.Name = "ExitBeacon"
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.CastShadow = false
		marker.Material = Enum.Material.Neon
		marker.Color = EXIT_COLOR
		marker.Transparency = 0.4
		marker.Size = Vector3.new(GameConfig.EXIT_RADIUS * 2, 0.1, GameConfig.EXIT_RADIUS * 2)
		marker.CFrame = CFrame.new(exit.Position.X, exit.Position.Y - exit.Size.Y / 2 + 0.05, exit.Position.Z)
		marker.Parent = exit.Parent
		beacon = marker
	end

	-- Cette méthode permet de ramasser une clé pour le groupe lorsqu'un mortel vivant termine l'action ; la dernière
	-- clé rend la voiture démarrable. Renvoie (true) ou (false, raison).
	local function collect(player: Player, spotId: string): (boolean, string?)
		if not objective then
			return false, "aucune manche en cours"
		end
		if not canAct(player) then
			return false, "seul un mortel vivant peut ramasser une clé"
		end
		local ok, err = objective:collectKey(spotId)
		if not ok then
			return false, err
		end
		local part = keyParts[spotId]
		keyParts[spotId] = nil
		if part then
			part:Destroy()
		end
		carPrompt.Enabled = objective:canStartCar()
		publish()
		print(
			string.format(
				"[Fuite] %s a trouvé une clé (%d/%d)",
				player.Name,
				objective.keysFound,
				objective.keysNeeded
			)
		)
		return true
	end

	-- Cette méthode permet de démarrer la voiture lorsqu'un mortel vivant termine l'action, toutes clés trouvées ;
	-- renvoie (true) ou (false, raison).
	local function startCar(player: Player): (boolean, string?)
		if not objective then
			return false, "aucune manche en cours"
		end
		if not canAct(player) then
			return false, "seul un mortel vivant peut démarrer la voiture"
		end
		local ok, err = objective:startCar()
		if not ok then
			return false, err
		end
		carPrompt.Enabled = false
		openExit()
		publish()
		print(string.format("[Fuite] %s a démarré la voiture : sortie ouverte", player.Name))
		return true
	end

	-- Cette méthode permet de retirer l'objectif lorsque la manche se termine, est annulée ou revient à l'attente
	-- (idempotent) : clés, balise, porte et action de la voiture remises à l'état de départ.
	local function reset()
		objective = nil
		for _, part in keyParts do
			part:Destroy()
		end
		keyParts = {}
		carPrompt.Enabled = false
		if beacon then
			beacon:Destroy()
			beacon = nil
		end
		if garageDoor and doorState then
			garageDoor.Transparency = doorState.transparency
			garageDoor.CanCollide = doorState.canCollide
		end
		publish()
	end

	-- Cette méthode permet de poser une clé sur un emplacement lorsque la manche démarre : petit bloc doré, action
	-- « Ramasser » maintenue.
	local function placeKey(spotId: string)
		local spot = spots[spotId]
		local key = Instance.new("Part")
		key.Name = "Keys"
		key.Anchored = true
		key.CanCollide = false
		key.Material = Enum.Material.Metal
		key.Color = KEY_COLOR
		key.Size = Vector3.new(0.8, 0.3, 0.5)
		key.CFrame = CFrame.new(spot.Position.X, spot.Position.Y - spot.Size.Y / 2 + 0.15, spot.Position.Z)
		key:SetAttribute(MapTags.Attributes.AnchorId, spotId)
		local prompt = makePrompt(key, "Clés", "Ramasser", GameConfig.KEY_PICKUP_DURATION)
		prompt.Triggered:Connect(function(player)
			collect(player, spotId)
		end)
		key.Parent = spot.Parent
		keyParts[spotId] = key
	end

	carPrompt.Triggered:Connect(function(player)
		local ok, err = startCar(player)
		if not ok then
			warn("[Fuite] démarrage refusé pour " .. player.Name .. " : " .. tostring(err))
		end
	end)

	matchService.MatchStarted:Connect(function()
		reset()
		local chosen = Escape.drawKeySpots(spotList, GameConfig.ESCAPE_KEY_COUNT, function(n)
			return rng:NextInteger(1, n)
		end, exitRoom)
		if #chosen < GameConfig.ESCAPE_KEY_COUNT then
			warn(
				string.format("[Fuite] %d emplacement(s) de clés pour %d clés", #chosen, GameConfig.ESCAPE_KEY_COUNT)
			)
		end
		objective = Escape.new(chosen)
		for _, spotId in chosen do
			placeKey(spotId)
		end
		publish()
		print("[Fuite] clés posées : " .. table.concat(chosen, ", "))
	end)
	matchService.MatchEnded:Connect(reset)
	matchService.MatchCancelled:Connect(reset)
	matchService.PhaseChanged:Connect(function(phase)
		if phase ~= Match.Phase.Running then
			reset()
		end
	end)

	-- Surveillance de la sortie : un mortel vivant debout dessus, objectif rempli, est sauvé
	RunService.Heartbeat:Connect(function(dt)
		exitClock += dt
		if exitClock < EXIT_CHECK_INTERVAL then
			return
		end
		exitClock = 0
		if not (objective and objective:isComplete()) then
			return
		end
		local floor = exit.Position - Vector3.new(0, exit.Size.Y / 2, 0)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if
				root
				and root:IsA("BasePart")
				and objective:canEscape(matchService:getRole(player), matchService:getMortalState(player))
				and Escape.isAtExit(root.Position, floor, GameConfig.EXIT_RADIUS, EXIT_HEIGHT)
			then
				local ok, err = matchService:save(player)
				if ok then
					print("[Fuite] " .. player.Name .. " est sauvé")
				else
					warn("[Fuite] sauvetage refusé pour " .. player.Name .. " : " .. tostring(err))
				end
				-- La sauvegarde peut terminer la manche (reset) : on arrête la boucle si l'objectif a disparu
				if not objective then
					return
				end
			end
		end
	end)

	-- Debug (Studio) : DebugEscape = "Key" ou "Car" sur un joueur agit comme si ce joueur avait terminé l'action
	if RunService:IsStudio() then
		-- Cette méthode permet d'exécuter une commande DebugEscape lorsqu'elle est posée sur un joueur.
		local function onDebug(player: Player)
			local value = player:GetAttribute(A.DebugEscape)
			if value == nil then
				return
			end
			player:SetAttribute(A.DebugEscape, nil)
			local ok, err
			if value == "Key" then
				local remaining = next(keyParts)
				if remaining then
					ok, err = collect(player, remaining)
				else
					ok, err = false, "aucune clé restante"
				end
			elseif value == "Car" then
				ok, err = startCar(player)
			else
				ok, err = false, "commande inconnue " .. tostring(value)
			end
			if not ok then
				warn("[Fuite] DebugEscape " .. tostring(value) .. " refusé : " .. tostring(err))
			end
		end
		-- Cette méthode permet d'écouter DebugEscape sur un joueur lorsqu'il rejoint le serveur.
		local function watch(player: Player)
			player:GetAttributeChangedSignal(A.DebugEscape):Connect(function()
				onDebug(player)
			end)
		end
		for _, player in Players:GetPlayers() do
			watch(player)
		end
		Players.PlayerAdded:Connect(watch)
	end

	publish()
end

return EscapeService

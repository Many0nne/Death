-- Apparitions de la manche (#11), abonné aux événements de Server.MatchService (son API n'est pas modifiée) :
-- - MatchStarted : chaque mortel sur son point d'apparition (un par point), la Mort sur l'un des siens (Shared.SpawnPlan) ;
-- - un participant qui réapparaît pendant la manche (personnage rechargé) revient à son point, sauf mortel mort ou sauvé ;
-- - un mortel sauvé quitte la maison aussitôt, et tout le monde la quitte au retour à l'attente (PhaseChanged Waiting) ;
-- - un joueur qui rejoint pendant une manche n'a pas de rôle : il reste dans la zone d'attente (spectateur).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapTags = require(Shared.MapTags)
local Match = require(Shared.Match)
local SpawnPlan = require(Shared.SpawnPlan)
local WaitingZone = require(script.Parent.WaitingZone)

local MatchSpawner = {}

-- Hauteur au-dessus de l'ancrage où poser le personnage : il tombe sur ses pieds au lieu de s'enfoncer dans le sol
local DROP_HEIGHT = 3

-- Cette méthode permet de lister les ancrages d'un tag sous la maison, triés par AnchorId, lorsque le service
-- démarre : l'index tiré par SpawnPlan désigne toujours le même point.
local function sortedAnchors(house: Instance, tag: string): { BasePart }
	local anchors = {}
	for _, d in house:GetDescendants() do
		if d:IsA("BasePart") and d:HasTag(tag) then
			table.insert(anchors, d)
		end
	end
	table.sort(anchors, function(a, b)
		return tostring(a:GetAttribute(MapTags.Attributes.AnchorId))
			< tostring(b:GetAttribute(MapTags.Attributes.AnchorId))
	end)
	return anchors
end

-- Cette méthode permet de lire la racine du personnage d'un joueur lorsqu'on veut le déplacer (nil s'il n'est pas
-- encore chargé).
local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character.Parent and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Cette méthode permet de déplacer le personnage d'un joueur lorsqu'il doit apparaître ailleurs ; renvoie false si
-- le personnage n'est pas chargé (il sera placé à son apparition).
local function moveTo(player: Player, cframe: CFrame): boolean
	if not rootOf(player) then
		return false
	end
	(player.Character :: Model):PivotTo(cframe)
	return true
end

-- Cette méthode permet de brancher les apparitions sur le service de manche lorsque le serveur démarre ; `house` est
-- le modèle construit par Server.HouseBuilder (ancrages MortalSpawn et DeathSpawn).
function MatchSpawner.start(matchService, house: Instance)
	local mortalSpawns = sortedAnchors(house, MapTags.MortalSpawn)
	local deathSpawns = sortedAnchors(house, MapTags.DeathSpawn)
	local rng = Random.new()
	local placements: { [number]: CFrame } = {} -- UserId -> point d'apparition de la manche en cours
	local returned = 0 -- compteur des retours, pour étaler les joueurs dans la zone d'attente

	-- Cette méthode permet de tirer un index de 1 à n lorsque SpawnPlan répartit les points.
	local function pick(n: number): number
		return rng:NextInteger(1, n)
	end

	-- Cette méthode permet de renvoyer le point d'apparition d'un joueur lorsqu'il doit (ré)apparaître dans la maison :
	-- participant de la manche en cours, Mort ou mortel encore en jeu (ni mort ni sauvé) ; nil sinon.
	local function spotOf(player: Player): CFrame?
		if matchService:getPhase() ~= Match.Phase.Running then
			return nil
		end
		local spot = placements[player.UserId]
		if not spot then
			return nil
		end
		if matchService:getRole(player) == Match.Role.Mortal then
			local state = matchService:getMortalState(player)
			if state == nil or Match.isResolved(state) then
				return nil
			end
		end
		return spot
	end

	-- Cette méthode permet de renvoyer un joueur dans la zone d'attente lorsqu'il quitte la maison (fin de manche,
	-- mortel sauvé) ; un joueur déjà dans la zone ne bouge pas.
	local function sendBack(player: Player)
		local root = rootOf(player)
		if root and not WaitingZone.contains(root.Position) then
			returned += 1
			moveTo(player, WaitingZone.spot(returned))
		end
	end

	matchService.MatchStarted:Connect(function(info)
		local plan, err = SpawnPlan.assign(info.deathId, info.mortalIds, #mortalSpawns, #deathSpawns, pick)
		if not plan then
			warn("[Apparitions] " .. tostring(err))
			return
		end
		placements = {}
		for id, placement in plan do
			local anchors = if placement.kind == Match.Role.Death then deathSpawns else mortalSpawns
			placements[id] = anchors[placement.index].CFrame + Vector3.new(0, DROP_HEIGHT, 0)
			local player = Players:GetPlayerByUserId(id)
			if player then
				-- Personnage pas encore chargé : CharacterAdded le placera
				moveTo(player, placements[id])
			end
		end
	end)

	matchService.PhaseChanged:Connect(function(phase)
		if phase == Match.Phase.Waiting then
			placements = {}
			for _, player in Players:GetPlayers() do
				sendBack(player)
			end
		end
	end)

	matchService.MortalStateChanged:Connect(function(change)
		if change.to == Match.MortalState.Saved and change.player then
			sendBack(change.player)
		end
	end)

	-- Cette méthode permet de replacer un participant dans la maison lorsque son personnage réapparaît pendant la
	-- manche (Roblox le pose d'abord sur le SpawnLocation de la zone d'attente).
	local function onCharacter(player: Player, character: Model)
		local spot = spotOf(player)
		if not spot then
			return
		end
		task.spawn(function()
			if not character:WaitForChild("HumanoidRootPart", 5) then
				return
			end
			-- Une frame d'attente : le placement de Roblox sur le SpawnLocation écraserait un déplacement immédiat
			task.wait()
			if player.Character == character and spotOf(player) == spot then
				character:PivotTo(spot)
			end
		end)
	end

	-- Cette méthode permet de suivre les réapparitions d'un joueur lorsqu'il est sur le serveur.
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return MatchSpawner

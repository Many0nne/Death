-- Apparitions de la manche (#11), abonné aux événements de Server.MatchService (son API n'est pas modifiée) :
-- - MatchStarted : chaque mortel sur son point d'apparition (un par point), la Mort sur l'un des siens (Shared.SpawnPlan) ;
-- - un participant qui réapparaît pendant la manche (personnage rechargé) revient à son point, un mortel en agonie
--   là où il est tombé (un reset ne le met pas hors d'atteinte de la Mort), un mortel mort ou sauvé reste dehors ;
-- - garde serveur du reset (#48) : un mortel vivant tué par Roblox pendant la manche (`/reset`, Health = 0, chute dans
--   le vide) subit un accident (MatchService:accident : agonie, ou mort sans agonie s'il a déjà été ranimé) ; un
--   agonisant tué ainsi reste en agonie et réapparaît là où il est mort ;
-- - un mortel sauvé ou mort quitte la maison aussitôt (spectateur ; l'âme errante dans la maison est prévue en v2), et tout le monde la quitte au retour à l'attente (PhaseChanged Waiting) ;
-- - un joueur qui rejoint pendant une manche n'a pas de rôle : il reste dans la zone d'attente (spectateur).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapTags = require(Shared.MapTags)
local Match = require(Shared.Match)
local GameConfig = require(Shared.GameConfig)
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

-- Cette méthode permet de trouver le sol sous un joueur lorsqu'il tombe en agonie : point debout (sans la rotation
-- du corps), DROP_HEIGHT au-dessus du sol ; nil s'il n'y a pas de sol dans les 15 studs (chute dans le vide).
local function groundBelow(player: Player): CFrame?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -15, 0), params)
	return hit and CFrame.new(hit.Position + Vector3.new(0, DROP_HEIGHT, 0))
end

-- Cette méthode permet de brancher les apparitions sur le service de manche lorsque le serveur démarre ; `house` est
-- le modèle construit par Server.HouseBuilder (ancrages MortalSpawn et DeathSpawn).
function MatchSpawner.start(matchService, house: Instance)
	local mortalSpawns = sortedAnchors(house, MapTags.MortalSpawn)
	local deathSpawns = sortedAnchors(house, MapTags.DeathSpawn)
	-- Vérifié au démarrage du serveur : une manche complète ne peut pas échouer faute de points d'apparition
	assert(
		#mortalSpawns >= GameConfig.MORTALS_PER_MATCH and #deathSpawns >= 1,
		string.format("maison avec %d apparition(s) de mortel et %d de la Mort", #mortalSpawns, #deathSpawns)
	)
	local rng = Random.new()
	local placements: { [number]: CFrame } = {} -- UserId -> point d'apparition de la manche en cours
	local fallen: { [number]: CFrame? } = {} -- UserId -> où un mortel est tombé en agonie
	local returned = 0 -- compteur des retours, pour étaler les joueurs dans la zone d'attente

	-- Cette méthode permet de tirer un index de 1 à n lorsque SpawnPlan répartit les points.
	local function pick(n: number): number
		return rng:NextInteger(1, n)
	end

	-- Cette méthode permet de renvoyer le point où (ré)apparaître dans la maison lorsqu'un participant de la manche en
	-- cours recharge son personnage : point d'apparition (Mort, mortel vivant), lieu de la chute (agonie) ; nil sinon.
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
			if state == Match.MortalState.Agony then
				return fallen[player.UserId] or spot
			end
			if state ~= Match.MortalState.Alive then
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
			-- Personne ne pourrait entrer dans la maison : la manche est annulée plutôt que jouée dans le vide
			warn("[Apparitions] manche annulée : " .. tostring(err))
			matchService:stopMatch()
			return
		end
		placements = {}
		fallen = {}
		for id, placement in plan do
			local anchors = if placement.kind == Match.Role.Death then deathSpawns else mortalSpawns
			placements[id] = anchors[placement.index].CFrame + Vector3.new(0, DROP_HEIGHT, 0)
			-- Un faux joueur de debug (#12) est placé par son mannequin
			local player = Players:GetPlayerByUserId(id) or matchService:getBot(id)
			if player then
				-- Personnage pas encore chargé : CharacterAdded le placera
				moveTo(player, placements[id])
			end
		end
	end)

	matchService.PhaseChanged:Connect(function(phase)
		if phase == Match.Phase.Waiting then
			placements = {}
			fallen = {}
			for _, player in Players:GetPlayers() do
				sendBack(player)
			end
			for _, bot in matchService:listBots() do
				sendBack(bot)
			end
		end
	end)

	matchService.MortalStateChanged:Connect(function(change)
		if not change.player then
			return
		end
		if change.to == Match.MortalState.Saved or change.to == Match.MortalState.Dead then
			sendBack(change.player)
		elseif change.to == Match.MortalState.Agony then
			fallen[change.userId] = groundBelow(change.player)
		end
	end)

	-- Cette méthode permet d'appliquer la garde du reset lorsque le personnage d'un mortel meurt par Roblox pendant la
	-- manche : accident pour un mortel vivant, lieu de réapparition mis à jour pour un agonisant.
	local function onDied(player: Player)
		if matchService:getPhase() ~= Match.Phase.Running or matchService:getRole(player) ~= Match.Role.Mortal then
			return
		end
		local state = matchService:getMortalState(player)
		if state == Match.MortalState.Alive then
			local ok, err = matchService:accident(player)
			if ok then
				print(string.format("[Apparitions] %s tué par Roblox pendant la manche : accident", player.Name))
			else
				warn(string.format("[Apparitions] %s : accident refusé (%s)", player.Name, tostring(err)))
			end
		elseif state == Match.MortalState.Agony then
			fallen[player.UserId] = groundBelow(player) or fallen[player.UserId]
		end
	end

	-- Cette méthode permet de suivre la mort Roblox d'un personnage lorsqu'il apparaît (garde du reset, #48).
	local function watchDeath(player: Player, character: Model)
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					if player.Character == character then
						onDied(player)
					end
				end)
			end
		end)
	end

	-- Cette méthode permet de replacer un participant dans la maison lorsque son personnage réapparaît pendant la
	-- manche (Roblox le pose d'abord sur le SpawnLocation de la zone d'attente).
	local function onCharacter(player: Player, character: Model)
		watchDeath(player, character)
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
		if player.Character then
			watchDeath(player, player.Character)
		end
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

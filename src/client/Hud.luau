-- HUD minimal de la manche et écran de fin (#9, docs/parcours-joueur.md « Interface en manche » et « Le Bilan »),
-- sans travail graphique. Il ne fait que lire l'état répliqué (attributs de ReplicatedStorage, des Players et du
-- conteneur privé du joueur, Shared.TrapAttributes) ; textes : Shared.HudFormat.
-- - haut centre : sablier (barre, chiffres sous une minute) ;
-- - haut gauche : rôle du joueur, puis les mortels et leur état (même ordre pour les deux rôles) ;
-- - bas droite : la Mort (ombre / lumière, souffle, pièges armés) ou le mortel (batterie de la lampe) ;
-- - centre : bilan de la manche pendant la phase Ended, retiré au retour en attente ou à la manche suivante.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgonyAttributes = require(Shared:WaitForChild("AgonyAttributes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local HudFormat = require(Shared:WaitForChild("HudFormat"))
local LightAttributes = require(Shared:WaitForChild("LightAttributes"))
local Match = require(Shared:WaitForChild("Match"))
local MatchAttributes = require(Shared:WaitForChild("MatchAttributes"))
local TrapAttributes = require(Shared:WaitForChild("TrapAttributes"))

local MA = MatchAttributes
local LA = LightAttributes
local TA = TrapAttributes

-- Période de rafraîchissement (secondes) : les textes changent au plus à la seconde, sauf la dissipation
local REFRESH = 0.1
local TEXT = Color3.fromRGB(225, 225, 232)
local MUTED = Color3.fromRGB(160, 165, 180)
local ALERT = Color3.fromRGB(255, 196, 120)
local LOCAL_ROW = Color3.fromRGB(255, 236, 170)
local PANEL = Color3.fromRGB(10, 10, 14)
local SAND = Color3.fromRGB(214, 186, 120)

local Hud = {}

-- Cette méthode permet de créer un cadre sombre à coins arrondis lorsque le HUD pose un panneau.
local function makePanel(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

-- Cette méthode permet d'ajouter une ligne de texte à un panneau lorsque le HUD est construit.
local function makeLine(name: string, parent: Instance, order: number, size: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, (size or 16) + 6)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = size or 16
	label.TextColor3 = TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

-- Cette méthode permet de construire le HUD de manche (sablier, mortels, panneau du rôle) lorsque le client démarre ;
-- tout est caché tant que le joueur n'a pas de rôle.
local function makeHud(playerGui: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	-- Sablier : barre qui se vide, chiffres par-dessus sous une minute
	local glass = Instance.new("Frame")
	glass.Name = "Hourglass"
	glass.AnchorPoint = Vector2.new(0.5, 0)
	glass.Position = UDim2.new(0.5, 0, 0, 10)
	glass.Size = UDim2.fromOffset(260, 20)
	glass.BackgroundColor3 = PANEL
	glass.BackgroundTransparency = 0.35
	glass.BorderSizePixel = 0
	local glassCorner = Instance.new("UICorner")
	glassCorner.CornerRadius = UDim.new(0, 6)
	glassCorner.Parent = glass
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = SAND
	fill.BackgroundTransparency = 0.2
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill
	fill.Parent = glass
	local clock = Instance.new("TextLabel")
	clock.Name = "Clock"
	clock.BackgroundTransparency = 1
	clock.Size = UDim2.fromScale(1, 1)
	clock.Font = Enum.Font.GothamBold
	clock.TextSize = 16
	clock.TextColor3 = Color3.new(1, 1, 1)
	clock.TextStrokeTransparency = 0.4
	clock.Parent = glass
	glass.Parent = gui

	-- Haut gauche : rôle, puis une ligne par mortel
	local roster = makePanel("Roster", gui)
	roster.Position = UDim2.fromOffset(12, 10)
	roster.Size = UDim2.fromOffset(250, 0)
	local role = makeLine("Role", roster, 0, 18)
	role.Font = Enum.Font.GothamBold
	local rows = {}
	for i = 1, GameConfig.MORTALS_PER_MATCH do
		rows[i] = makeLine("Mortal" .. i, roster, i)
	end

	-- Bas droite : panneau du rôle
	local side = makePanel("RolePanel", gui)
	side.AnchorPoint = Vector2.new(1, 1)
	side.Position = UDim2.new(1, -12, 1, -12)
	side.Size = UDim2.fromOffset(330, 0)
	local light = makeLine("Light", side, 1, 17)
	local breath = makeLine("Breath", side, 2)
	local traps = makeLine("Traps", side, 3)
	local battery = makeLine("Battery", side, 4)

	gui.Parent = playerGui
	return {
		glass = glass,
		fill = fill,
		clock = clock,
		roster = roster,
		role = role,
		rows = rows,
		side = side,
		light = light,
		breath = breath,
		traps = traps,
		battery = battery,
	}
end

-- Cette méthode permet de construire l'écran de fin (cadre centré, titre, lignes, âmes) lorsque le client démarre ;
-- caché jusqu'à la phase Ended.
local function makeSummary(playerGui: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchSummary"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Enabled = false
	local frame = makePanel("Panel", gui)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.45)
	frame.Size = UDim2.fromOffset(440, 0)
	frame.BackgroundTransparency = 0.15
	local title = makeLine("Title", frame, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Center
	local rows = {}
	for i = 1, GameConfig.MORTALS_PER_MATCH do
		rows[i] = makeLine("Mortal" .. i, frame, i, 17)
	end
	local souls = makeLine("Souls", frame, 100, 18)
	souls.Font = Enum.Font.GothamBold
	souls.TextColor3 = ALERT
	souls.TextXAlignment = Enum.TextXAlignment.Center
	local footer = makeLine("Footer", frame, 101, 14)
	footer.TextColor3 = MUTED
	footer.TextXAlignment = Enum.TextXAlignment.Center
	footer.Text = "Retour en salle d'attente dans quelques secondes"
	gui.Parent = playerGui
	return { gui = gui, title = title, rows = rows, souls = souls }
end

-- Mortel suivi par la liste du HUD : Player, ou mannequin d'un faux joueur de debug (#12, attributs sur le Model)
-- (`state` / `soul` : derniers état et sort d'âme lus, gardés si le mortel quitte la partie)
type RosterEntry = { source: Instance, name: string, bot: boolean, order: number, state: string?, soul: string? }

-- Faux joueurs de debug : Studio seulement, inutile de parcourir le workspace en jeu publié
local IS_STUDIO = RunService:IsStudio()

-- Cette méthode permet de trouver les mortels visibles de la manche (Players et mannequins des faux joueurs qui ont le
-- rôle Mortal) lorsque le HUD complète sa liste.
local function visibleMortals(): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(MA.Role) == Match.Role.Mortal then
			table.insert(list, player)
		end
	end
	if IS_STUDIO then
		for _, child in workspace:GetChildren() do
			if child:IsA("Model") and child:GetAttribute(MA.Role) == Match.Role.Mortal then
				table.insert(list, child)
			end
		end
	end
	return list
end

-- Cette méthode permet de démarrer le HUD et l'écran de fin lorsque le client se lance.
function Hud.start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local hud = makeHud(playerGui)
	local summary = makeSummary(playerGui)
	-- Résultat déjà affiché (texte JSON) : on ne le décode qu'à son changement
	local shownResult: string? = nil
	-- Mortels de la manche en cours, dans l'ordre du bilan (UserId croissant : faux joueurs d'abord, du dernier créé au
	-- premier, puisque leurs UserId négatifs décroissent ; puis joueurs) : un mortel parti garde sa ligne, comme le veut
	-- docs/parcours-joueur.md (« même emplacement, même ordre »)
	local roster: { RosterEntry } = {}
	local known: { [Instance]: boolean } = {}
	-- Dernier temps restant lu en manche : s'il remonte, une nouvelle manche a démarré sans phase visible entre les deux
	local lastTimeLeft: number? = nil

	-- Cette méthode permet d'ajouter à la liste les mortels pas encore suivis lorsque la manche tourne (attributs
	-- répliqués avec un léger retard au démarrage), puis de la trier ; elle retire ceux d'une manche précédente.
	local function updateRoster()
		-- Encore présent mais plus mortel : reste d'une manche relancée dans la même frame (un départ, lui, garde sa ligne)
		for i = #roster, 1, -1 do
			local source = roster[i].source
			if source.Parent ~= nil and source:GetAttribute(MA.Role) ~= Match.Role.Mortal then
				known[source] = nil
				table.remove(roster, i)
			end
		end
		local added = false
		for _, source in visibleMortals() do
			if not known[source] then
				known[source] = true
				added = true
				local bot = not source:IsA("Player")
				table.insert(roster, {
					source = source,
					name = HudFormat.displayName(if bot then nil else (source :: Player).DisplayName, source.Name),
					bot = bot,
					-- Faux joueur : numéro du nom (« Bot Mortel 2 »), qui croît comme son UserId décroît
					order = if bot then -(tonumber(source.Name:match("(%d+)$")) or 0) else (source :: Player).UserId,
				})
			end
		end
		if added then
			table.sort(roster, function(a, b)
				if a.bot ~= b.bot then
					return a.bot
				end
				return a.order < b.order
			end)
		end
	end

	-- Cette méthode permet de remplir l'écran de fin depuis MatchResult lorsque la phase Ended commence (ou que le
	-- résultat change) ; le cache si le résultat est absent ou illisible.
	local function showSummary(raw: string?)
		if raw == shownResult then
			return
		end
		shownResult = raw
		local ok, decoded = pcall(function()
			return if raw then HttpService:JSONDecode(raw) else nil
		end)
		local data = HudFormat.summary(if ok then decoded else nil, localPlayer.UserId)
		-- Bilan réservé aux joueurs de la manche (pas à ceux arrivés pendant la nuit)
		summary.gui.Enabled = data ~= nil and data.involved
		if not data then
			return
		end
		summary.title.Text = data.title
		summary.souls.Text = data.souls
		for i, label in summary.rows do
			local row = data.rows[i]
			label.Visible = row ~= nil
			if row then
				label.Text = string.format("%s — %s", row.name, row.verdict)
				label.TextColor3 = if row.isLocal then LOCAL_ROW else TEXT
			end
		end
	end

	-- Cette méthode permet de mettre à jour le panneau de la Mort (lumière, souffle, pièges) depuis son conteneur privé
	-- lorsque le HUD se rafraîchit.
	local function refreshDeath(now: number)
		local private = playerGui:FindFirstChild(TA.PrivateName)
		-- Cette méthode permet de lire un attribut du conteneur privé lorsqu'il existe déjà (nil sinon).
		local function read(name: string): any
			return if private then private:GetAttribute(name) else nil
		end
		local text, alert = HudFormat.exposure(localPlayer:GetAttribute(LA.Exposed) == true, read(LA.DispelProgress))
		hud.light.Text = text
		hud.light.TextColor3 = if alert then ALERT else MUTED
		local rechargeEnd = read(TA.BreathRechargeEnd)
		local rechargeLeft = if type(rechargeEnd) == "number" then rechargeEnd - now else nil
		hud.breath.Text = HudFormat.breath(read(TA.BreathCharges), GameConfig.BREATH_CHARGES, rechargeLeft)
		hud.traps.Text = HudFormat.traps(read(TA.ArmedTraps), GameConfig.MAX_ARMED_TRAPS)
	end

	-- Cette méthode permet de mettre à jour tout le HUD lorsque la période de rafraîchissement est écoulée : sablier,
	-- rôle et mortels, panneau du rôle, écran de fin.
	local function refresh()
		local phase = ReplicatedStorage:GetAttribute(MA.Phase)
		if phase == Match.Phase.Ended then
			showSummary(ReplicatedStorage:GetAttribute(MA.Result))
		elseif shownResult ~= nil or summary.gui.Enabled then
			shownResult = nil
			summary.gui.Enabled = false
		end

		-- Rôle de manche ; hors manche, seule la Mort de debug (DebugDeath) a un HUD : LightRole vaut Mortal pour tous
		local role = localPlayer:GetAttribute(MA.Role)
		if role == nil and localPlayer:GetAttribute(LA.LightRole) == Match.Role.Death then
			role = Match.Role.Death
		end
		local running = phase == Match.Phase.Running
		local now = workspace:GetServerTimeNow()
		local timeLeft = ReplicatedStorage:GetAttribute(MA.TimeLeft)
		local restarted = running and lastTimeLeft ~= nil and type(timeLeft) == "number" and timeLeft > lastTimeLeft + 1
		if (not running or restarted) and #roster > 0 then
			table.clear(roster)
			table.clear(known)
		end
		lastTimeLeft = if running and type(timeLeft) == "number" then timeLeft else nil
		if running then
			updateRoster()
		end

		local fraction, clockText = HudFormat.hourglass(timeLeft, ReplicatedStorage:GetAttribute(MA.Duration))
		hud.glass.Visible = running and role ~= nil
		hud.fill.Size = UDim2.fromScale(fraction, 1)
		hud.clock.Text = clockText or ""

		local roleText = HudFormat.role(role)
		hud.roster.Visible = roleText ~= nil and phase ~= Match.Phase.Ended
		if hud.roster.Visible then
			hud.role.Text = "Tu es : " .. roleText
			local isDeath = role == Match.Role.Death
			for i, label in hud.rows do
				local entry = roster[i]
				label.Visible = entry ~= nil
				if entry then
					local source = entry.source
					local state
					if source.Parent == nil or source:GetAttribute(MA.Role) ~= Match.Role.Mortal then
						-- Parti pendant la manche : son sort reste affiché s'il était déjà fixé (enfui, mort)
						state = if entry.state and Match.isResolved(entry.state)
							then HudFormat.mortalState(entry.state, entry.soul, nil, isDeath)
							else HudFormat.LEFT
					else
						entry.state = source:GetAttribute(MA.MortalState)
						entry.soul = source:GetAttribute(MA.SoulFate)
						local agonyEnd = source:GetAttribute(AgonyAttributes.AgonyEnd)
						state = HudFormat.mortalState(
							entry.state,
							entry.soul,
							if type(agonyEnd) == "number" then agonyEnd - now else nil,
							isDeath
						)
					end
					label.Text = string.format("%s — %s", entry.name, state)
					label.TextColor3 = if source == localPlayer then LOCAL_ROW else TEXT
				end
			end
		end

		local isDeath = role == Match.Role.Death
		local batteryText = if role == Match.Role.Mortal
			then HudFormat.battery(
				localPlayer:GetAttribute(LA.FlashlightBattery),
				localPlayer:GetAttribute(LA.FlashlightOn)
			)
			else nil
		hud.side.Visible = phase ~= Match.Phase.Ended and (isDeath or batteryText ~= nil)
		hud.light.Visible = isDeath
		hud.breath.Visible = isDeath
		hud.traps.Visible = isDeath
		hud.battery.Visible = batteryText ~= nil
		if isDeath then
			refreshDeath(now)
		end
		if batteryText then
			hud.battery.Text = batteryText
		end
	end

	local elapsed = REFRESH
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= REFRESH then
			elapsed = 0
			refresh()
		end
	end)
end

return Hud

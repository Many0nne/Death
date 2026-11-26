-- Roster (#52) : joueurs + faux joueurs de debug avec l'API de Players, branché sur un vrai MatchService, et vu par les
-- services de jeu (Mort, pièges, lampe torche, lumière, agonie) : un bot est visé comme un joueur. #58 : les tables
-- indexées par joueur sont ordinaires (pas de clés faibles) et vidées au départ d'un joueur ou d'un bot.
return function(T, Loader)
	local physics = {
		RegisterCollisionGroup = function() end,
		CollisionGroupSetCollidable = function() end,
	}
	local loader = Loader.new({ PhysicsService = physics })
	local Signal = loader:require("src/shared/Signal")
	local Match = loader:require("src/shared/Match")
	local A = loader:require("src/shared/MatchAttributes")
	local LA = loader:require("src/shared/LightAttributes")
	local HouseBuilder = loader:require("src/server/HouseBuilder")
	local MatchService = loader:require("src/server/MatchService")
	local DeathController = loader:require("src/server/DeathController")
	local TrapService = loader:require("src/server/TrapService")
	local LightService = loader:require("src/server/LightService")
	local AgonyService = loader:require("src/server/AgonyService")
	local FlashlightService = loader:require("src/server/FlashlightService")
	local PrivateState = loader:require("src/server/PrivateState")
	local S = Match.MortalState

	local house = HouseBuilder.build(Instance.new("Folder"))

	-- Cette méthode permet de créer un objet à attributs (faux joueur, mannequin) lorsqu'un test observe la réplication ;
	-- AttributeChanged est déclenché comme en jeu.
	local function attributeHolder(fields)
		local holder = fields or {}
		holder.attributes = {}
		holder.AttributeChanged = Signal.new()
		-- Cette méthode permet d'écrire un attribut et de prévenir les abonnés comme en jeu.
		function holder.SetAttribute(self, name, value)
			if self.attributes[name] ~= value then
				self.attributes[name] = value
				self.AttributeChanged:Fire(name)
			end
		end
		-- Cette méthode permet de lire un attribut lorsqu'un test ou un service le consulte.
		function holder.GetAttribute(self, name)
			return self.attributes[name]
		end
		return holder
	end

	-- Cette méthode permet de fabriquer un mannequin de bot lorsque DebugAddBot est posé : objet à attributs (Lune ne
	-- déclenche pas AttributeChanged) qui délègue ses enfants à un vrai Model (racine, tête, Humanoid).
	local function mannequin(name)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = model
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = model
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
		local m = attributeHolder({ Name = name, destroyed = false, DescendantAdded = Signal.new() })
		-- Cette méthode permet de trouver un enfant du mannequin lorsqu'un service cherche sa racine ou sa tête.
		function m.FindFirstChild(_, child)
			return model:FindFirstChild(child)
		end
		-- Cette méthode permet de trouver l'Humanoid du mannequin lorsqu'un service règle sa vitesse.
		function m.FindFirstChildOfClass(_, class)
			return model:FindFirstChildOfClass(class)
		end
		-- Cette méthode permet de lister les pièces du mannequin lorsque la Mort règle les groupes de collision.
		function m.GetDescendants()
			return model:GetDescendants()
		end
		-- Cette méthode permet de noter la destruction du mannequin lorsque le bot est retiré.
		function m.Destroy(self)
			self.destroyed = true
		end
		-- Cette méthode permet de déplacer le mannequin lorsque le test le pose quelque part.
		function m.moveTo(_, position)
			root.CFrame = CFrame.new(position)
			head.CFrame = CFrame.new(position + Vector3.new(0, 3.2, 0))
		end
		return m
	end

	-- Cette méthode permet de monter une manche réelle (MatchService) et les services de jeu branchés sur son Roster
	-- lorsqu'un test démarre ; `count` vrais joueurs sans personnage (UserId 1..count).
	local function setup(count)
		local env = { now = 0, list = {}, lit = false, triggers = {}, warnings = {}, mannequins = {} }
		local players = { PlayerAdded = Signal.new(), PlayerRemoving = Signal.new() }
		function players.GetPlayers()
			return table.clone(env.list)
		end
		for id = 1, count do
			local player = attributeHolder({ UserId = id, Name = "Joueur" .. id, CharacterAdded = Signal.new() })
			-- Cette méthode permet de répondre comme un Player sans PlayerGui lorsqu'un service cherche son conteneur privé.
			function player.FindFirstChildOfClass()
				return nil
			end
			table.insert(env.list, player)
		end
		-- Cette méthode permet de noter un avertissement lorsqu'un service en émet.
		local function warn(message)
			table.insert(env.warnings, message)
		end
		-- Cette méthode permet de lire l'horloge simulée lorsqu'un service date un maintien.
		local function clock()
			return env.now
		end
		-- Cette méthode permet de lire le rôle de lumière publié (par DeathController) lorsqu'un service vise un joueur.
		local function roleOf(player)
			return player:GetAttribute(LA.LightRole)
		end
		env.match = MatchService.new({
			players = players,
			replicated = attributeHolder(),
			heartbeat = Signal.new(),
			isStudio = true,
			createMannequin = function(name)
				local m = mannequin(name)
				table.insert(env.mannequins, m)
				return m
			end,
			pick = function()
				return 1
			end,
			encode = function()
				return "json"
			end,
			log = function() end,
			warn = warn,
		})
		local roster = env.match:roster()
		env.heartbeat = Signal.new()
		env.death = DeathController.new({
			players = roster,
			match = env.match,
			lights = {
				isLit = function()
					return env.lit
				end,
			},
			heartbeat = env.heartbeat,
			isStudio = true,
			log = function() end,
		})
		env.traps = TrapService.new({
			house = house,
			match = env.match,
			lights = {
				canPrepareAt = function()
					return true
				end,
				breakLamp = function() end,
			},
			players = roster,
			isStudio = true,
			roleOf = roleOf,
			isExposed = function()
				return false
			end,
			clock = clock,
			serverTime = clock,
			connectPrompt = function(prompt, _, holdBegan)
				env.triggers[prompt] = holdBegan
			end,
			listenActions = function() end,
			privateOf = PrivateState.get,
			delay = function() end,
			animate = function(_, step)
				step(1)
			end,
			lineOfSight = function()
				return true
			end,
			notify = function() end,
			play = function() end,
			stop = function() end,
			random = function()
				return 0.5
			end,
			log = function() end,
			warn = warn,
		})
		env.lights = LightService.new({
			house = house,
			match = env.match,
			players = roster,
			isStudio = true,
			roleOf = roleOf,
			clock = clock,
			connectPrompt = function(prompt, _, holdBegan)
				env.triggers[prompt] = holdBegan
			end,
			delay = function() end,
			lineOfSight = function()
				return true
			end,
			log = function() end,
			warn = warn,
		})
		env.agony = AgonyService.new({
			match = env.match,
			death = env.death,
			players = roster,
			isStudio = true,
			roleOf = roleOf,
			clock = clock,
			serverTime = clock,
			connectPrompt = function(prompt, _, holdBegan)
				env.triggers[prompt] = holdBegan
			end,
			lineOfSight = function()
				return true
			end,
			send = function() end,
			onPress = function() end,
			notify = function() end,
			play = function() end,
			log = function() end,
			warn = warn,
		})
		env.flashlight = FlashlightService.new({
			house = house,
			players = roster,
			isStudio = true,
			roleOf = roleOf,
			clock = clock,
			lineOfSight = function()
				return true
			end,
			teleport = function() end,
			effect = function() end,
			pick = function()
				return 1
			end,
			notify = function() end,
			privateOf = PrivateState.get,
			connectPrompt = function() end,
			log = function() end,
			warn = warn,
		})
		env.death:start()
		env.traps:start()
		env.lights:start()
		env.agony:start()
		env.flashlight:start()
		env.match:start()

		-- Cette méthode permet d'ajouter un bot du rôle voulu lorsque le test le demande (DebugAddBot posé sur le joueur 1) ;
		-- renvoie le bot.
		function env.addBot(role)
			env.list[1]:SetAttribute(A.DebugAddBot, role)
			local bots = env.match:listBots()
			return bots[#bots]
		end

		-- Cette méthode permet de faire partir un vrai joueur comme sous Roblox : PlayerRemoving pendant qu'il est encore
		-- listé, puis retrait de la liste.
		function env.leave(player)
			players.PlayerRemoving:Fire(player)
			table.remove(env.list, table.find(env.list, player))
		end

		-- Cette méthode permet de démarrer une manche de test puis de publier les rôles de lumière lorsqu'un test joue.
		function env.start()
			T.expect(env.match:startMatch({ test = true }))
			env.heartbeat:Fire(0)
		end

		-- Cette méthode permet de donner un point au pied d'un piège lorsque le test y pose un bot.
		function env.near(id, offset)
			return env.traps.entries[id].floor + Vector3.new(0, 3, 0) + (offset or Vector3.zero)
		end
		return env
	end

	-- Cette méthode permet de vérifier qu'une table n'a pas de clés faibles lorsque le test contrôle #58.
	local function expectStrong(map, label)
		local meta = getmetatable(map)
		T.expect(meta == nil or meta.__mode == nil, label .. " : table à clés faibles")
	end

	T.describe("Roster (participants)", function()
		T.it("liste les joueurs puis les bots, et annonce l'arrivée et le départ d'un bot", function()
			local env = setup(1)
			local roster = env.match:roster()
			local added, removing = {}, {}
			local connection = roster.PlayerAdded:Connect(function(p)
				table.insert(added, p.Name)
			end)
			roster.PlayerRemoving:Connect(function(p)
				-- Prévenu avant la destruction du mannequin, comme un joueur encore là pendant PlayerRemoving
				table.insert(removing, p.Name .. if p.Character.destroyed then " détruit" else "")
			end)
			local bot = env.addBot("Mortal")
			T.expectEqual(#roster:GetPlayers(), 2)
			T.expectEqual(roster:GetPlayers()[2], bot)
			connection:Disconnect()
			env.addBot("Mortal")
			T.expectEqual(table.concat(added, ","), "Bot Mortel 1", "Disconnect coupe aussi les bots")
			env.list[1]:SetAttribute(A.DebugClearBots, true)
			T.expectEqual(table.concat(removing, ","), "Bot Mortel 1,Bot Mortel 2")
			T.expectEqual(#roster:GetPlayers(), 1)
		end)
	end)

	T.describe("Roster : un bot est visé comme un joueur (#52)", function()
		T.it("un piège armé touche le faux mortel dans sa zone : accident, agonie", function()
			local env = setup(1)
			local bot = env.addBot("Mortal")
			env.start()
			T.expectEqual(bot:GetAttribute(LA.LightRole), "Mortal", "rôle de lumière publié sur le mannequin")
			T.expectEqual(env.list[1]:GetAttribute(LA.LightRole), "Death")
			bot.Character:moveTo(env.near("WetFloorKitchen", Vector3.new(1, 0, 0)))
			env.traps:prepare("WetFloorKitchen")
			env.traps:step() -- buée : un bot n'a pas de conteneur privé, rien n'est publié
			local ok, _, victims = env.traps:blow("WetFloorKitchen")
			T.expect(ok)
			T.expectEqual(victims[1], bot)
			T.expectEqual(env.match:getMortalState(bot), S.Agony)
			T.expect(env.agony.entries[bot.UserId] ~= nil, "agonie suivie par AgonyService")
			T.expectEqual(#env.warnings, 0, table.concat(env.warnings, "\n"))
		end)

		T.it("le faux mortel porte une lampe : son faisceau éclaire devant lui", function()
			local env = setup(1)
			local bot = env.addBot("Mortal")
			env.start()
			bot.Character:moveTo(Vector3.new(0, 3, 0))
			bot.Character:SetAttribute(LA.DebugFlashlight, "on")
			env.flashlight:step(0.1)
			T.expect(env.flashlight:isOn(bot), "lampe allumée")
			local head = bot.Character:FindFirstChild("Head")
			T.expect(head:FindFirstChild("FlashlightBeam") ~= nil, "faisceau posé sur la tête")
			local ahead = head.CFrame.Position + head.CFrame.LookVector * 10
			T.expect(env.flashlight:isInBeam(ahead), "devant : éclairé")
			T.expect(not env.flashlight:isInBeam(head.CFrame.Position - head.CFrame.LookVector * 10), "derrière")
		end)

		T.it("un faux Mort est exposé par la lumière ambiante", function()
			local env = setup(1)
			local bot = env.addBot("Death")
			env.start()
			T.expectEqual(bot:GetAttribute(LA.LightRole), "Death")
			env.heartbeat:Fire(0.1)
			T.expectEqual(bot:GetAttribute(LA.Exposed), false, "dans l'ombre")
			env.lit = true
			env.heartbeat:Fire(0.1)
			T.expectEqual(bot:GetAttribute(LA.Exposed), true, "éclairé")
			T.expect(env.death:isExposed(bot))
		end)
	end)

	T.describe("Roster : tables par joueur vidées au départ (#58)", function()
		T.it("aucune table à clés faibles indexée par joueur", function()
			local env = setup(1)
			for prompt, holds in env.traps.holds do
				expectStrong(holds, "TrapService.holds")
				expectStrong(env.traps.refused[prompt], "TrapService.refused")
			end
			expectStrong(env.traps.chilled, "TrapService.chilled")
			for _, holds in env.lights.holds do
				expectStrong(holds, "LightService.holds")
			end
			expectStrong(env.lights.holds, "LightService.holds (invites)")
			expectStrong(env.agony.holds, "AgonyService.holds")
			expectStrong(env.agony.saved, "AgonyService.saved")
			expectStrong(env.agony.watched, "AgonyService.watched")
		end)

		T.it("le départ d'un joueur vide maintiens et refus (pièges, lumière, agonie)", function()
			local env = setup(2)
			env.list[1]:SetAttribute(A.DebugRole, "Death")
			local bot = env.addBot("Mortal")
			env.start()
			local mortal = env.list[2]
			-- Le bot tombe en agonie : invites « Faucher » et « Masser » sur son mannequin
			T.expect(env.match:accident(bot))
			local entry = env.agony.entries[bot.UserId]
			env.triggers[entry.prompts.massage](mortal)
			T.expect(env.agony.holds[entry.prompts.massage][mortal] ~= nil, "maintien noté")
			local restore = nil
			for _, item in env.lights.prompts do
				if item.kind == "restore" then
					restore = item.prompt
				end
			end
			env.triggers[restore](mortal)
			T.expect(env.lights.holds[restore][mortal] ~= nil)
			local examine = nil
			for _, item in env.traps.prompts do
				if item.action == "examine" then
					examine = item.prompt
					break
				end
			end
			env.triggers[examine](mortal)
			env.traps.refused[examine][mortal] = true
			env.traps.chilled[mortal] = true
			T.expect(env.traps.holds[examine][mortal] ~= nil)

			env.leave(mortal)
			T.expectEqual(env.agony.holds[entry.prompts.massage][mortal], nil, "agonie")
			T.expectEqual(env.lights.holds[restore][mortal], nil, "lumière")
			T.expectEqual(env.traps.holds[examine][mortal], nil, "pièges : maintien")
			T.expectEqual(env.traps.refused[examine][mortal], nil, "pièges : refus")
			T.expectEqual(env.traps.chilled[mortal], nil, "pièges : buée")
			T.expectEqual(env.match:getPhase(), Match.Phase.Running, "le bot en agonie garde la manche")
		end)

		T.it("DebugClearBots vide aussi les tables du bot retiré", function()
			local env = setup(1)
			local bot = env.addBot("Mortal")
			env.start()
			T.expect(env.agony.watched[bot], "DebugAgony écouté dès l'arrivée du bot")
			T.expect(env.match:accident(bot))
			T.expect(env.agony.saved[bot] ~= nil, "vitesse d'origine gardée pendant la reptation")
			local restore = nil
			for _, item in env.lights.prompts do
				if item.kind == "restore" then
					restore = item.prompt
				end
			end
			env.triggers[restore](bot)
			env.traps.chilled[bot] = true
			env.flashlight:step(0.1)
			env.list[1]:SetAttribute(A.DebugClearBots, true)
			T.expectEqual(env.agony.saved[bot], nil, "agonie : vitesse")
			T.expectEqual(env.agony.watched[bot], nil, "agonie : debug")
			T.expectEqual(env.lights.holds[restore][bot], nil, "lumière")
			T.expectEqual(env.traps.chilled[bot], nil, "pièges")
			T.expectEqual(env.flashlight.holders[bot], nil, "lampe")
			T.expectEqual(env.death:roleOf(bot), nil, "Mort")
			T.expectEqual(#env.warnings, 0, table.concat(env.warnings, "\n"))
		end)
	end)
end

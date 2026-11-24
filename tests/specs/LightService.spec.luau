-- LightService : invites du disjoncteur et des ampoules sur la vraie maison (instances simulées par Lune), contrôles
-- serveur (rôle, distance, vue), état appliqué aux lampes, recharges, remise à zéro par la manche et commandes de debug.
return function(T, Loader)
	local loader = Loader.new()
	local HouseBuilder = loader:require("src/server/HouseBuilder")
	local LightService = loader:require("src/server/LightService")
	local LA = loader:require("src/shared/LightAttributes")
	local MapTags = loader:require("src/shared/MapTags")
	local Match = loader:require("src/shared/Match")
	local Signal = loader:require("src/shared/Signal")

	-- Cette méthode permet de monter un service de lumière isolé sur une maison neuve lorsqu'un test démarre ; renvoie
	-- le service et l'environnement simulé (horloge, délais, vue, invites, joueurs).
	local function setup()
		local env = { now = 0, delays = {}, los = true, triggers = {}, warnings = {}, changed = 0 }
		env.house = HouseBuilder.build(Instance.new("Folder"))
		env.match = { MatchStarted = Signal.new(), PhaseChanged = Signal.new() }
		local service = LightService.new({
			house = env.house,
			match = env.match,
			players = nil,
			isStudio = true,
			roleOf = function(player)
				return player.role
			end,
			clock = function()
				return env.now
			end,
			soundParent = nil,
			connectPrompt = function(prompt, fn, holdBegan)
				env.triggers[prompt] = { fn = fn, hold = holdBegan }
			end,
			delay = function(seconds, fn)
				table.insert(env.delays, { at = env.now + seconds, fn = fn })
			end,
			lineOfSight = function()
				return env.los
			end,
			log = function() end,
			warn = function(message)
				table.insert(env.warnings, message)
			end,
		})
		service.Changed:Connect(function()
			env.changed += 1
		end)
		service:start()

		-- Cette méthode permet d'avancer l'horloge simulée et d'exécuter les délais échus lorsque le test laisse passer
		-- le temps (grésillement, fin de recharge).
		function env.advance(seconds)
			local target = env.now + seconds
			while true do
				-- Délai échu le plus ancien d'abord : un délai programmé par un autre part de son heure d'échéance
				local nextIndex = nil
				for i, d in env.delays do
					if d.at <= target and (nextIndex == nil or d.at < env.delays[nextIndex].at) then
						nextIndex = i
					end
				end
				if not nextIndex then
					break
				end
				local d = table.remove(env.delays, nextIndex)
				env.now = math.max(env.now, d.at)
				d.fn()
			end
			env.now = target
		end

		-- Cette méthode permet de créer un faux joueur avec un personnage posé à une position lorsque le test déclenche
		-- une invite.
		function env.player(role, position)
			local character = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = CFrame.new(position)
			root.Parent = character
			return { Name = "Joueur" .. tostring(role), role = role, Character = character }
		end

		-- Cette méthode permet de retrouver une invite par type (et aile ou pièce) lorsque le test la déclenche.
		function env.prompt(kind, key)
			for _, entry in service.prompts do
				if entry.kind == kind and (key == nil or entry.wing == key or entry.room == key) then
					return entry.prompt
				end
			end
			error("invite introuvable : " .. kind .. " " .. tostring(key))
		end

		-- Cette méthode permet de déclencher une invite comme le ferait le joueur lorsqu'il la maintient.
		function env.trigger(prompt, player)
			env.triggers[prompt].hold(player)
			env.advance(prompt.HoldDuration)
			env.triggers[prompt].fn(player)
		end

		-- Cette méthode permet de déclencher une invite sans la maintenir, comme un client modifié.
		function env.triggerNow(prompt, player)
			env.triggers[prompt].fn(player)
		end

		-- Cette méthode permet de retrouver le bloc d'une lampe lorsque le test lit son état affiché.
		function env.lamp(id)
			for _, d in env.house:GetDescendants() do
				if d:HasTag(MapTags.Lamp) and d:GetAttribute(MapTags.Attributes.LampId) == id then
					return d
				end
			end
			error("lampe introuvable " .. id)
		end

		env.breaker = service.breaker
		env.atBreaker = env.breaker.CFrame.Position + Vector3.new(-3, 0, 0)
		return service, env
	end

	T.describe("LightService : invites", function()
		local service, env = setup()

		T.it("crée une coupure par aile et un rétablissement au disjoncteur, une invite par lampe", function()
			local counts = { cut = 0, restore = 0, burn = 0 }
			for _, entry in service.prompts do
				counts[entry.kind] += 1
				T.expect(entry.prompt:HasTag(LA.PromptTag), "tag des invites")
			end
			T.expectEqual(counts.cut, 3)
			T.expectEqual(counts.restore, 1)
			T.expectEqual(counts.burn, 12)
			T.expectEqual(env.prompt("cut", "Day"):GetAttribute(LA.PromptRole), "Death")
			T.expectEqual(env.prompt("restore"):GetAttribute(LA.PromptRole), "Mortal")
		end)

		T.it("teste la vue depuis le personnage, jamais depuis la caméra", function()
			-- Mesuré en jeu : la vue caméra perd la lampe de plafond sous un linteau de porte
			local burn = env.prompt("burn", "Kitchen")
			T.expectEqual(burn.RequiresLineOfSight, false)
			T.expectEqual(burn:GetAttribute(LA.PromptSight), true)
			T.expectEqual(env.prompt("restore").RequiresLineOfSight, false)
			T.expectEqual(env.prompt("restore"):GetAttribute(LA.PromptSight), true)
		end)

		T.it("publie ce qui est possible au départ : couper et griller oui, rétablir non", function()
			T.expectEqual(env.prompt("cut", "Night"):GetAttribute(LA.PromptAvailable), true)
			T.expectEqual(env.prompt("restore"):GetAttribute(LA.PromptAvailable), false)
			T.expectEqual(env.prompt("burn", "Kitchen"):GetAttribute(LA.PromptAvailable), true)
			T.expectEqual(env.lamp("KitchenLamp"):GetAttribute(LA.LampOn), true)
		end)
	end)

	T.describe("LightService : disjoncteur", function()
		T.it("la Mort coupe une aile : lampes éteintes, disjoncteur marqué, invites à jour", function()
			local _, env = setup()
			env.trigger(env.prompt("cut", "Day"), env.player("Death", env.atBreaker))
			local lamp = env.lamp("LivingChandelier")
			T.expectEqual(lamp:GetAttribute(LA.LampOn), false)
			T.expectEqual(lamp:FindFirstChild("Light").Enabled, false)
			T.expectEqual(env.lamp("StudyLamp"):GetAttribute(LA.LampOn), true, "autre aile")
			T.expectEqual(env.breaker:GetAttribute(LA.CutWing), "Day")
			T.expectEqual(env.prompt("cut", "Night"):GetAttribute(LA.PromptAvailable), false, "une aile à la fois")
			T.expectEqual(env.prompt("restore"):GetAttribute(LA.PromptAvailable), true)
			T.expectEqual(env.prompt("restore").ActionText, "Rétablir : Aile jour")
			T.expectEqual(env.prompt("burn", "Kitchen"):GetAttribute(LA.PromptAvailable), false, "pièce sans courant")
			T.expectEqual(env.changed, 1)
		end)

		T.it("refuse la coupure à un mortel ou à une Mort trop loin", function()
			local service, env = setup()
			env.trigger(env.prompt("cut", "Day"), env.player("Mortal", env.atBreaker))
			T.expectEqual(service.sabotage:cutWing(), nil, "mauvais rôle")
			env.trigger(env.prompt("cut", "Day"), env.player("Death", env.atBreaker + Vector3.new(-20, 0, 0)))
			T.expectEqual(service.sabotage:cutWing(), nil, "trop loin")
			env.los = false
			env.trigger(env.prompt("cut", "Day"), env.player("Death", env.atBreaker))
			T.expectEqual(service.sabotage:cutWing(), nil, "disjoncteur hors de vue")
			env.los = true
			env.triggerNow(env.prompt("cut", "Day"), env.player("Death", env.atBreaker))
			T.expectEqual(service.sabotage:cutWing(), nil, "sans maintien (client modifié)")
			local prompt = env.prompt("cut", "Day")
			local death = env.player("Death", env.atBreaker)
			env.triggers[prompt].hold(death)
			env.advance(prompt.HoldDuration + 5)
			env.triggerNow(prompt, death)
			T.expectEqual(service.sabotage:cutWing(), nil, "maintien périmé (lâché puis rejoué)")
		end)

		T.it("un mortel rétablit, la Mort attend la recharge avant de recouper", function()
			local service, env = setup()
			env.trigger(env.prompt("cut", "Service"), env.player("Death", env.atBreaker))
			env.trigger(env.prompt("restore"), env.player("Death", env.atBreaker))
			T.expectEqual(service.sabotage:cutWing(), "Service", "la Mort ne rétablit pas")
			env.trigger(env.prompt("restore"), env.player("Mortal", env.atBreaker))
			T.expectEqual(service.sabotage:cutWing(), nil)
			T.expectEqual(env.lamp("GarageLampWest"):GetAttribute(LA.LampOn), true)
			T.expectEqual(env.prompt("cut", "Day"):GetAttribute(LA.PromptAvailable), false, "recharge")
			env.advance(service.sabotage.timing.breakerCooldown + 0.1)
			T.expectEqual(env.prompt("cut", "Day"):GetAttribute(LA.PromptAvailable), true, "recharge finie")
		end)
	end)

	T.describe("LightService : ampoules", function()
		T.it("la Mort grille une pièce : grésillement puis noir, recharge ensuite", function()
			local service, env = setup()
			local lamp = env.lamp("KitchenLamp")
			local nearLamp = lamp.CFrame.Position + Vector3.new(0, -8, 6)
			env.trigger(env.prompt("burn", "Kitchen"), env.player("Death", nearLamp))
			T.expectEqual(service:isRoomLit("Kitchen"), false, "règle éteinte tout de suite")
			T.expect(#env.delays > 0, "grésillement programmé")
			-- Le grésillement est visuel : l'attribut répliqué suit la règle sans clignoter
			local seen = {}
			for _ = 1, 6 do
				table.insert(seen, tostring(lamp:GetAttribute(LA.LampOn)))
				env.advance(0.07)
			end
			T.expectEqual(table.concat(seen, ","), "false,false,false,false,false,false")
			env.advance(1)
			T.expectEqual(lamp:GetAttribute(LA.LampOn), false)
			T.expectEqual(lamp.Material.Name, "SmoothPlastic")
			T.expectEqual(env.prompt("burn", "Entry"):GetAttribute(LA.PromptAvailable), false, "recharge")
			env.advance(service.sabotage.timing.burnCooldown)
			T.expectEqual(env.prompt("burn", "Entry"):GetAttribute(LA.PromptAvailable), true)
		end)

		T.it("refuse une lampe hors de vue ou hors de portée", function()
			local service, env = setup()
			local lamp = env.lamp("KitchenLamp")
			env.los = false
			env.trigger(
				env.prompt("burn", "Kitchen"),
				env.player("Death", lamp.CFrame.Position + Vector3.new(0, -8, 0))
			)
			T.expectEqual(service:isRoomLit("Kitchen"), true, "hors de vue")
			env.los = true
			env.trigger(
				env.prompt("burn", "Kitchen"),
				env.player("Death", lamp.CFrame.Position + Vector3.new(0, -8, 25))
			)
			T.expectEqual(service:isRoomLit("Kitchen"), true, "trop loin")
		end)

		T.it("une remise à zéro pendant le grésillement laisse la lampe allumée", function()
			local service, env = setup()
			service:burnRoom("Kitchen")
			service:reset()
			env.advance(1)
			T.expectEqual(env.lamp("KitchenLamp"):GetAttribute(LA.LampOn), true)
		end)

		T.it("un second grésillement de la même lampe remplace le premier et finit éteint", function()
			local service, env = setup()
			local lamp = env.lamp("KitchenLamp")
			service:burnRoom("Kitchen")
			env.advance(0.1)
			service:reset()
			service:burnRoom("Kitchen")
			env.advance(0.2)
			-- Le premier grésillement serait fini ici : la lampe ne doit pas reprendre son état réel en avance
			T.expect(service.flickering.KitchenLamp ~= nil, "second grésillement en cours")
			env.advance(1)
			T.expectEqual(service.flickering.KitchenLamp, nil)
			T.expectEqual(lamp:FindFirstChild("Light").Enabled, false)
		end)
	end)

	T.describe("LightService : manche et API", function()
		T.it("rallume tout au début d'une manche et au retour à l'attente", function()
			local service, env = setup()
			service:cutPower("Night")
			env.match.MatchStarted:Fire({})
			T.expectEqual(service:isRoomLit("Study"), true)
			service:burnRoom("Entry")
			env.match.PhaseChanged:Fire(Match.Phase.Ended)
			T.expectEqual(service:isRoomLit("Entry"), false, "le résultat garde l'état")
			env.match.PhaseChanged:Fire(Match.Phase.Waiting)
			T.expectEqual(service:isRoomLit("Entry"), true)
		end)

		T.it("expose isLit et canPrepareAt pour les pièges et la lampe torche", function()
			local service, env = setup()
			local under = env.lamp("KitchenLamp").CFrame.Position + Vector3.new(0, -8, 0)
			T.expectEqual(service:isLit(under), true)
			T.expectEqual(service:canPrepareAt(under), false)
			T.expectEqual(service:roomAt(under), "Kitchen")
			service:burnRoom("Kitchen")
			T.expectEqual(service:canPrepareAt(under), true)
		end)
	end)

	T.describe("LightService : debug", function()
		-- Cette méthode permet de créer un faux joueur à attributs lorsque le test écrit une commande DebugLight.
		local function debugPlayer()
			local player = { Name = "Testeur", attributes = {} }
			function player.GetAttribute(self, name)
				return self.attributes[name]
			end
			function player.SetAttribute(self, name, value)
				self.attributes[name] = value
			end
			return player
		end

		T.it("exécute cut, restore, burn et reset, puis efface la commande", function()
			local service, env = setup()
			local player = debugPlayer()
			for _, command in { "cut:Day", "burn:Study" } do
				player:SetAttribute(LA.DebugLight, command)
				service:_onDebug(player)
				T.expectEqual(player:GetAttribute(LA.DebugLight), nil, command)
			end
			T.expectEqual(service.sabotage:cutWing(), "Day")
			T.expectEqual(service:isRoomLit("Study"), false)
			player:SetAttribute(LA.DebugLight, "restore")
			service:_onDebug(player)
			T.expectEqual(service.sabotage:cutWing(), nil)
			player:SetAttribute(LA.DebugLight, "reset")
			service:_onDebug(player)
			T.expectEqual(service:isRoomLit("Study"), true)
			player:SetAttribute(LA.DebugLight, "fly")
			service:_onDebug(player)
			T.expect(#env.warnings > 0, "commande inconnue signalée")
		end)
	end)
end

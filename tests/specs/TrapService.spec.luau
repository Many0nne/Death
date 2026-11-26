-- TrapService : points fragiles de la vraie maison (instances simulées par Lune), invites par rôle, contrôles serveur
-- (rôle, lumière, maintien, distance), accidents (agonie, lustre sur plusieurs mortels), souffle publié, buée, remise à
-- zéro et commandes de debug.
return function(T, Loader)
	local loader = Loader.new()
	local HouseBuilder = loader:require("src/server/HouseBuilder")
	local TrapService = loader:require("src/server/TrapService")
	local LA = loader:require("src/shared/LightAttributes")
	local TA = loader:require("src/shared/TrapAttributes")
	local Traps = loader:require("src/shared/Traps")
	local Match = loader:require("src/shared/Match")
	local Signal = loader:require("src/shared/Signal")
	local GameConfig = loader:require("src/shared/GameConfig")

	-- Cette méthode permet de créer un faux joueur (rôle, position, attributs) lorsque le test agit à sa place.
	local function fakePlayer(name, role, position)
		local character = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(position or Vector3.zero)
		root.Parent = character
		local player = { Name = name, role = role, Character = character, attributes = {} }
		-- Cette méthode permet de lire un attribut du faux joueur lorsque le service le consulte.
		function player.GetAttribute(self, key)
			return self.attributes[key]
		end
		-- Cette méthode permet d'écrire un attribut du faux joueur lorsque le service publie un état.
		function player.SetAttribute(self, key, value)
			self.attributes[key] = value
		end
		-- Cette méthode permet de déplacer le personnage lorsque le test le fait marcher.
		function player.moveTo(self, pos)
			self.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
		end
		return player
	end

	-- Cette méthode permet de monter un service des pièges isolé sur une maison neuve lorsqu'un test démarre ; renvoie le
	-- service et l'environnement simulé (horloge, joueurs, manche, sons, messages).
	local function setup()
		local env = {
			now = 0,
			delays = {},
			los = true,
			exposed = false,
			lit = false,
			falls = {},
			deferFalls = false,
			triggers = {},
			notices = {},
			warnings = {},
			playing = {},
			downs = {},
			broken = {},
			list = {},
		}
		env.house = HouseBuilder.build(Instance.new("Folder"))
		env.match = {
			MatchStarted = Signal.new(),
			PhaseChanged = Signal.new(),
			down = function(_, player)
				table.insert(env.downs, player.Name)
				return true
			end,
		}
		env.players = {
			GetPlayers = function()
				return env.list
			end,
		}
		local service = TrapService.new({
			house = env.house,
			match = env.match,
			lights = {
				canPrepareAt = function()
					return not env.lit
				end,
				breakLamp = function(_, id)
					table.insert(env.broken, id)
					return true
				end,
			},
			players = env.players,
			isStudio = false,
			roleOf = function(player)
				return player.role
			end,
			isExposed = function()
				return env.exposed
			end,
			clock = function()
				return env.now
			end,
			serverTime = function()
				return 1000 + env.now
			end,
			connectPrompt = function(prompt, fn, holdBegan, holdEnded)
				env.triggers[prompt] = { fn = fn, hold = holdBegan, ended = holdEnded }
			end,
			delay = function(seconds, fn)
				table.insert(env.delays, { at = env.now + seconds, fn = fn })
			end,
			animate = function(_, step)
				if env.deferFalls then
					table.insert(env.falls, step)
				else
					step(1)
				end
			end,
			lineOfSight = function()
				return env.los
			end,
			notify = function(player, text)
				table.insert(env.notices, player.Name .. " : " .. text)
			end,
			play = function(sound)
				env.playing[sound] = true
			end,
			stop = function(sound)
				env.playing[sound] = nil
			end,
			random = function()
				return 0.5
			end,
			heartbeat = nil,
			log = function() end,
			warn = function(message)
				table.insert(env.warnings, message)
			end,
		})
		service:start()

		-- Cette méthode permet d'avancer l'horloge simulée et d'exécuter les délais échus lorsque le test laisse passer
		-- le temps.
		function env.advance(seconds)
			local target = env.now + seconds
			table.sort(env.delays, function(a, b)
				return a.at < b.at
			end)
			while env.delays[1] and env.delays[1].at <= target do
				local d = table.remove(env.delays, 1)
				env.now = d.at
				d.fn()
			end
			env.now = target
		end

		-- Cette méthode permet de retrouver l'invite d'une action sur un point fragile lorsque le test la déclenche.
		function env.prompt(id, action)
			for _, item in service.prompts do
				if item.entry.id == id and item.action == action then
					return item.prompt
				end
			end
			error("invite introuvable : " .. id .. " " .. action)
		end

		-- Cette méthode permet de maintenir puis déclencher une invite comme le ferait le joueur.
		function env.trigger(prompt, player)
			local t = env.triggers[prompt]
			t.hold(player)
			env.advance(prompt.HoldDuration)
			t.ended(player)
			t.fn(player)
		end

		-- Cette méthode permet de donner une position au pied d'un point fragile lorsque le test y place un joueur.
		function env.near(id, offset)
			local entry = service.entries[id]
			return entry.floor + Vector3.new(0, 3, 0) + (offset or Vector3.zero)
		end

		-- Cette méthode permet d'ajouter un joueur au serveur simulé lorsque le test en a besoin.
		function env.join(name, role, position)
			local player = fakePlayer(name, role, position)
			table.insert(env.list, player)
			return player
		end
		return service, env
	end

	T.describe("TrapService : points fragiles", function()
		local service, env = setup()

		T.it("trouve les trois types de pièges de la maison", function()
			local kinds = {}
			local count = 0
			for _, entry in service.entries do
				kinds[entry.kind] = (kinds[entry.kind] or 0) + 1
				count += 1
			end
			T.expect(count >= 25, count .. " points fragiles")
			T.expect(kinds.WetFloor >= 2 and kinds.Shelf >= 2, "carrelages et étagères")
			T.expectEqual(kinds.Chandelier, 1)
			T.expectEqual(#env.warnings, 0, table.concat(env.warnings, "\n"))
		end)

		T.it("crée quatre invites par objet, réservées à un rôle", function()
			local count = 0
			for _ in service.entries do
				count += 1
			end
			T.expectEqual(#service.prompts, 4 * count)
			T.expectEqual(env.prompt("KitchenShelf", "work"):GetAttribute(LA.PromptRole), "Death")
			T.expectEqual(env.prompt("KitchenShelf", "examine"):GetAttribute(LA.PromptRole), "Mortal")
			T.expect(env.prompt("KitchenShelf", "defuse"):HasTag(LA.PromptTag), "filtrées comme celles de la lumière")
			T.expectEqual(env.prompt("KitchenShelf", "work").ActionText, "Préparer")
			T.expectEqual(env.prompt("KitchenShelf", "work").HoldDuration, Traps.KINDS.Shelf.steps[1])
			T.expectEqual(env.prompt("LivingChandelier", "work").ActionText, "Préparer (1/2)")
			T.expectEqual(env.prompt("KitchenShelf", "blow"):GetAttribute(LA.PromptAvailable), false, "rien d'armé")
			T.expectEqual(env.prompt("KitchenShelf", "examine"):GetAttribute(LA.PromptAvailable), true)
			T.expectEqual(env.prompt("KitchenShelf", "defuse"):GetAttribute(LA.PromptAvailable), true)
		end)

		T.it("place le sol du lustre au plancher du salon et fait tomber l'étagère vers la pièce", function()
			local chandelier = service.entries.LivingChandelier
			T.expect(chandelier.part.CFrame.Position.Y - chandelier.floor.Y > 7, "lustre en hauteur")
			T.expect(#chandelier.moving >= 4, "lustre et son habillage")
			-- KitchenShelf : contre le mur nord de la cuisine (z = 34.75), tombe vers le sud
			T.expectEqual(service.entries.KitchenShelf.front, Vector3.new(0, 0, -1))
		end)

		T.it(
			"fait tomber chaque étagère vers son avant, celui de ses blocs (orientation imposée comprise)",
			function()
				local HouseGeometry = loader:require("src/shared/HouseGeometry")
				local HouseLayout = loader:require("src/shared/HouseLayout")
				local rooms = HouseGeometry.roomsById(HouseLayout)
				local vectors = {
					North = Vector3.new(0, 0, 1),
					South = Vector3.new(0, 0, -1),
					East = Vector3.new(1, 0, 0),
					West = Vector3.new(-1, 0, 0),
				}
				local checked = 0
				for _, prop in HouseLayout.props do
					if prop.trap == "Shelf" then
						local facing = HouseGeometry.propFacing(
							HouseLayout,
							rooms[prop.room],
							prop.x,
							prop.z,
							prop.size[1],
							prop.size[3],
							prop.facing
						)
						T.expectEqual(service.entries[prop.id].front, vectors[facing], prop.id)
						checked += 1
					end
				end
				T.expect(checked >= 20, checked .. " étagères")
				T.expectEqual(service.entries.WineRackMiddle.front, Vector3.new(0, 0, 1), "orientation imposée (nord)")
			end
		)
	end)

	T.describe("TrapService : la Mort", function()
		T.it("prépare en maintenant l'invite : bruit pendant le maintien, piège armé ensuite", function()
			local service, env = setup()
			local death = env.join("Mort", "Death", env.near("KitchenShelf", Vector3.new(0, 0, -3)))
			local prompt = env.prompt("KitchenShelf", "work")
			local noise = service.entries.KitchenShelf.noise
			env.triggers[prompt].hold(death)
			T.expectEqual(env.playing[noise], true, "grincement pendant la préparation")
			env.advance(prompt.HoldDuration)
			env.triggers[prompt].fn(death)
			T.expectEqual(env.playing[noise], nil, "silence ensuite")
			T.expectEqual(service.rules:get("KitchenShelf").state, "Armed")
			T.expectEqual(prompt.ActionText, "Désarmer")
			T.expectEqual(env.prompt("KitchenShelf", "blow"):GetAttribute(LA.PromptAvailable), true)
			T.expectEqual(death:GetAttribute(TA.ArmedTraps), 1)
			T.expectEqual(death:GetAttribute(TA.BreathCharges), GameConfig.BREATH_CHARGES)
			T.expectEqual(env.notices[#env.notices], "Mort : Étagère armé (1/4)")
		end)

		T.it("le bruit s'arrête si la Mort lâche avant la fin", function()
			local service, env = setup()
			local death = env.join("Mort", "Death", env.near("LivingChandelier"))
			local prompt = env.prompt("LivingChandelier", "work")
			env.triggers[prompt].hold(death)
			T.expectEqual(env.playing[service.entries.LivingChandelier.noise], true)
			env.triggers[prompt].ended(death)
			T.expectEqual(env.playing[service.entries.LivingChandelier.noise], nil)
			T.expectEqual(service.rules:get("LivingChandelier").state, "Idle")
		end)

		T.it("le bruit s'arrête si la Mort quitte la partie en plein maintien", function()
			local service, env = setup()
			local death = env.join("Mort", "Death", env.near("LivingChandelier"))
			env.triggers[env.prompt("LivingChandelier", "work")].hold(death)
			local noise = service.entries.LivingChandelier.noise
			service:step()
			T.expectEqual(env.playing[noise], true, "toujours là")
			table.clear(env.list)
			service:step()
			T.expectEqual(env.playing[noise], nil)
		end)

		T.it("le lustre se prépare en deux maintiens de 5 s", function()
			local service, env = setup()
			local death = env.join("Mort", "Death", env.near("LivingChandelier"))
			local prompt = env.prompt("LivingChandelier", "work")
			env.trigger(prompt, death)
			T.expectEqual(service.rules:get("LivingChandelier").state, "Preparing")
			T.expectEqual(prompt.ActionText, "Préparer (2/2)")
			env.trigger(prompt, death)
			T.expectEqual(service.rules:get("LivingChandelier").state, "Armed")
		end)

		T.it("un grand piège commencé puis rallumé s'abandonne pour rendre sa place", function()
			local service, env = setup()
			local death = env.join("Mort", "Death", env.near("LivingChandelier"))
			env.trigger(env.prompt("LivingChandelier", "work"), death)
			env.lit = true
			env.trigger(env.prompt("LivingChandelier", "work"), death)
			T.expectEqual(service.rules:get("LivingChandelier").state, "Preparing", "éclairé : pas de seconde étape")
			local abandon = env.prompt("LivingChandelier", "blow")
			T.expectEqual(abandon.ActionText, "Abandonner")
			T.expectEqual(abandon:GetAttribute(LA.PromptAvailable), true)
			env.trigger(abandon, death)
			T.expectEqual(service.rules:get("LivingChandelier").state, "Idle")
			T.expectEqual(service.rules:activeCount(), 0, "place rendue")
			T.expectEqual(abandon.ActionText, "Souffler")
			T.expectEqual((service:breath()), 3, "aucune charge dépensée")
		end)

		T.it("un maintien refusé au début n'arme jamais le piège, même si la Mort passe dans l'ombre", function()
			local service, env = setup()
			local prompt = env.prompt("KitchenShelf", "work")
			local death = env.join("Mort", "Death", env.near("KitchenShelf", Vector3.new(0, 0, -3)))
			env.exposed = true
			env.triggers[prompt].hold(death)
			env.exposed = false
			env.advance(prompt.HoldDuration)
			env.triggers[prompt].fn(death)
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle", "pas de piège armé en silence")
		end)

		T.it("un refus abandonné au début n'étouffe pas le refus d'un maintien suivant", function()
			local service, env = setup()
			local prompt = env.prompt("KitchenShelf", "work")
			local death = env.join("Mort", "Death", env.near("KitchenShelf", Vector3.new(0, 0, -3)))
			env.exposed = true
			env.triggers[prompt].hold(death)
			env.triggers[prompt].ended(death)
			env.exposed = false
			env.triggers[prompt].hold(death)
			env.exposed = true
			env.advance(prompt.HoldDuration)
			env.triggers[prompt].fn(death)
			T.expectEqual(#env.notices, 2, "refus de la fin du second maintien annoncé")
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle")
		end)

		T.it("refuse dans la lumière, au mauvais rôle, trop loin ou sans maintien", function()
			local service, env = setup()
			local prompt = env.prompt("KitchenShelf", "work")
			local death = env.join("Mort", "Death", env.near("KitchenShelf", Vector3.new(0, 0, -3)))
			env.exposed = true
			env.triggers[prompt].hold(death)
			T.expectEqual(env.playing[service.entries.KitchenShelf.noise], nil, "pas de bruit pour un refus")
			T.expect(string.find(env.notices[1], "lumière", 1, true) ~= nil, "refus annoncé dès le début")
			env.advance(prompt.HoldDuration)
			env.triggers[prompt].fn(death)
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle", "lumière")
			T.expectEqual(#env.notices, 1, "refus annoncé une seule fois")
			env.exposed = false
			env.lit = true
			env.trigger(prompt, death)
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle", "piège éclairé")
			T.expect(string.find(env.notices[#env.notices], "éteindre", 1, true) ~= nil, env.notices[#env.notices])
			env.lit = false
			env.trigger(prompt, env.join("Vivant", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, -3))))
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle", "mortel")
			env.trigger(prompt, env.join("Loin", "Death", env.near("KitchenShelf", Vector3.new(0, 0, -30))))
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle", "trop loin")
			env.triggers[prompt].fn(death)
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle", "sans maintien")
		end)

		T.it("limite à 4 pièges, désarmer pour replacer", function()
			local service, env = setup()
			local ids = { "WetFloorKitchen", "WetFloorLaundry", "WetFloorVeranda", "WetFloorGarage", "WetFloorCave" }
			for _, id in ids do
				local death = env.join("Mort", "Death", env.near(id))
				env.trigger(env.prompt(id, "work"), death)
			end
			T.expectEqual(service.rules:armedCount(), 4)
			T.expectEqual(service.rules:get("WetFloorCave").state, "Idle")
			T.expect(string.find(env.notices[#env.notices], "4 pièges", 1, true) ~= nil, env.notices[#env.notices])
			local death = env.join("Mort", "Death", env.near("WetFloorGarage"))
			env.trigger(env.prompt("WetFloorGarage", "work"), death)
			T.expectEqual(service.rules:get("WetFloorGarage").state, "Idle", "désarmé")
			death:moveTo(env.near("WetFloorCave"))
			env.trigger(env.prompt("WetFloorCave", "work"), death)
			T.expectEqual(service.rules:get("WetFloorCave").state, "Armed", "replacé")
		end)
	end)

	T.describe("TrapService : souffle et accidents", function()
		T.it("le souffle déclenche le carrelage : le mortel dessus tombe en agonie, pas celui d'à côté", function()
			local service, env = setup()
			local death = env.join("Mort", "Death", env.near("WetFloorKitchen", Vector3.new(15, 0, 0)))
			service:prepare("WetFloorKitchen")
			env.join("Dessus", "Mortal", env.near("WetFloorKitchen", Vector3.new(1, 0, 0)))
			env.join("Acote", "Mortal", env.near("WetFloorKitchen", Vector3.new(8, 0, 0)))
			env.trigger(env.prompt("WetFloorKitchen", "blow"), death)
			T.expectEqual(table.concat(env.downs, ","), "Dessus")
			T.expectEqual(service.rules:get("WetFloorKitchen").state, "Spent")
			T.expectEqual(death:GetAttribute(TA.BreathCharges), 2)
			T.expectEqual(death:GetAttribute(TA.BreathRechargeEnd), 1000 + Traps.BREATH_RECHARGE)
			local puddle = service.entries.WetFloorKitchen.part
			T.expect(puddle.Transparency < 1, "flaque visible")
			T.expectEqual(puddle.CanQuery, false, "la flaque ne cache rien")
			T.expectEqual(env.prompt("WetFloorKitchen", "work"):GetAttribute(LA.PromptAvailable), false)
			T.expectEqual(env.prompt("WetFloorKitchen", "examine"):GetAttribute(LA.PromptAvailable), false)
		end)

		T.it("le lustre touche plusieurs mortels, tombe au sol et s'éteint", function()
			local service, env = setup()
			local death = env.join("Mort", "Death", env.near("LivingChandelier", Vector3.new(0, 0, 12)))
			service:prepare("LivingChandelier")
			service:prepare("LivingChandelier")
			env.join("A", "Mortal", env.near("LivingChandelier", Vector3.new(2, 0, 0)))
			env.join("B", "Mortal", env.near("LivingChandelier", Vector3.new(-4, 0, 5)))
			env.join("C", "Mortal", env.near("LivingChandelier", Vector3.new(0, 0, 20)))
			local part = service.entries.LivingChandelier.part
			local top = part.CFrame.Position.Y
			local ok, _, victims = service:blow("LivingChandelier")
			T.expectEqual(ok, true)
			T.expectEqual(#victims, 2)
			T.expectEqual(table.concat(env.downs, ","), "A,B")
			T.expect(part.CFrame.Position.Y < top - 5, "le lustre est tombé")
			T.expectEqual(env.broken[1], "LivingChandelier")
			-- La Mort n'est jamais une victime
			T.expect(table.find(victims, death) == nil, "la Mort")
		end)

		T.it("l'étagère bascule vers la pièce et ne touche que devant elle", function()
			local service, env = setup()
			service:prepare("KitchenShelf")
			env.join("Devant", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, -3)))
			local entry = service.entries.KitchenShelf
			T.expect(#entry.moving > 3, "le meuble et ses blocs visibles")
			local box = entry.part
			local before = box.CFrame
			service:blow("KitchenShelf")
			T.expectEqual(table.concat(env.downs, ","), "Devant")
			local after = box.CFrame
			T.expect(math.abs(after.UpVector.Y) < 0.1, "couché")
			T.expect(after.Position.Z < before.Position.Z - 1, "tombé vers le sud, dans la cuisine")
			T.expect(after.Position.Y < before.Position.Y, "plus bas")
			service:reset()
			T.expect((box.CFrame.Position - before.Position).Magnitude < 1e-3, "relevé à la remise à zéro")
		end)

		T.it("une remise à zéro pendant la chute laisse l'objet relevé", function()
			local service, env = setup()
			env.deferFalls = true
			service:prepare("KitchenShelf")
			local box = service.entries.KitchenShelf.part
			local before = box.CFrame
			service:blow("KitchenShelf")
			env.falls[1](0.5)
			T.expect((box.CFrame.Position - before.Position).Magnitude > 0.1, "en train de tomber")
			service:reset()
			env.falls[1](1)
			T.expect((box.CFrame.Position - before.Position).Magnitude < 1e-3, "l'animation ne le refait pas tomber")
		end)

		T.it("l'étagère touche toute la bande où elle s'abat, pas plus", function()
			local service, env = setup()
			service:prepare("KitchenShelf")
			-- KitchenShelf : 6 de large, 7 de haut, 1,5 de profondeur, tombe vers -Z
			env.join("Loin", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, -7.5)))
			env.join("Bord", "Mortal", env.near("KitchenShelf", Vector3.new(3.5, 0, -4)))
			env.join("Hors", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, -10)))
			env.join("Cote", "Mortal", env.near("KitchenShelf", Vector3.new(5, 0, -3)))
			service:blow("KitchenShelf")
			T.expectEqual(table.concat(env.downs, ","), "Loin,Bord")
		end)

		T.it("refuse le souffle dans la lumière, sans charge ou sur un objet non armé", function()
			local service, env = setup()
			local death = env.join("Mort", "Death", env.near("WetFloorKitchen", Vector3.new(10, 0, 0)))
			env.trigger(env.prompt("WetFloorKitchen", "blow"), death)
			T.expectEqual(service.rules:get("WetFloorKitchen").state, "Idle", "pas armé")
			service:prepare("WetFloorKitchen")
			env.exposed = true
			env.trigger(env.prompt("WetFloorKitchen", "blow"), death)
			T.expectEqual(service.rules:get("WetFloorKitchen").state, "Armed", "lumière")
			env.exposed = false
			for _ = 1, 3 do
				service:removeBreathCharge()
			end
			T.expectEqual(env.prompt("WetFloorKitchen", "blow"):GetAttribute(LA.PromptAvailable), false, "à sec")
			env.trigger(env.prompt("WetFloorKitchen", "blow"), death)
			T.expectEqual(service.rules:get("WetFloorKitchen").state, "Armed", "plus de souffle")
			env.advance(Traps.BREATH_RECHARGE)
			service:step()
			T.expectEqual(env.prompt("WetFloorKitchen", "blow"):GetAttribute(LA.PromptAvailable), true, "rechargé")
			T.expectEqual(death:GetAttribute(TA.BreathCharges), 1)
		end)
	end)

	T.describe("TrapService : mortels et indices", function()
		T.it("examiner dit si l'objet est trafiqué, désamorcer le rend inoffensif", function()
			local service, env = setup()
			local mortal = env.join("Vivant", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, -3)))
			env.trigger(env.prompt("KitchenShelf", "examine"), mortal)
			T.expectEqual(env.notices[#env.notices], "Vivant : Étagère : rien d'anormal")
			service:prepare("KitchenShelf")
			env.trigger(env.prompt("KitchenShelf", "examine"), mortal)
			T.expectEqual(env.notices[#env.notices], "Vivant : Étagère : quelque chose cloche…")
			local defuse = env.prompt("KitchenShelf", "defuse")
			T.expectEqual(defuse.HoldDuration, 6)
			env.trigger(defuse, mortal)
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle")
			T.expectEqual(env.notices[#env.notices], "Vivant : Étagère : piège désamorcé")
		end)

		T.it("buée pour un mortel à environ 3 m d'un piège armé, jamais pour la Mort", function()
			local service, env = setup()
			local near = env.join("Proche", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, -6)))
			local far = env.join("Loin", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, -20)))
			local death = env.join("Mort", "Death", env.near("KitchenShelf", Vector3.new(0, 0, -2)))
			service:step()
			T.expectEqual(near:GetAttribute(TA.Chill), nil, "rien d'armé")
			service:prepare("KitchenShelf")
			service:step()
			T.expectEqual(near:GetAttribute(TA.Chill), true)
			T.expectEqual(far:GetAttribute(TA.Chill), nil)
			T.expectEqual(death:GetAttribute(TA.Chill), nil)
			service:defuse("KitchenShelf")
			service:step()
			T.expectEqual(near:GetAttribute(TA.Chill), nil, "désamorcé")
		end)

		T.it("ni buée ni accident à travers un mur : seulement dans la pièce du piège", function()
			local service, env = setup()
			-- KitchenShelf est adossée au mur nord de la cuisine : 3 studs derrière, c'est la pièce voisine
			local behind = env.join("Derriere", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, 3)))
			local front = env.join("Devant", "Mortal", env.near("KitchenShelf", Vector3.new(0, 0, -6)))
			service:prepare("KitchenShelf")
			service:step()
			T.expectEqual(front:GetAttribute(TA.Chill), true)
			T.expectEqual(behind:GetAttribute(TA.Chill), nil, "derrière le mur")
		end)

		T.it("indice visuel bref toutes les 8 à 10 s tant que le piège est armé", function()
			local service, env = setup()
			local emitter = service.entries.WetFloorKitchen.cue
			service:prepare("WetFloorKitchen")
			local pulses = 0
			for _ = 1, 150 do
				env.advance(0.2)
				service:step()
				if emitter.Enabled then
					pulses += 1
				end
			end
			-- 30 s à 9 s d'intervalle : 3 signes, chacun vu sur 1 ou 2 pas de 0,2 s
			T.expect(pulses >= 3 and pulses <= 6, pulses .. " pas allumés")
			service:defuse("WetFloorKitchen")
			pulses = 0
			for _ = 1, 100 do
				env.advance(0.2)
				service:step()
				if emitter.Enabled then
					pulses += 1
				end
			end
			T.expectEqual(pulses, 0, "plus rien une fois désamorcé")
		end)

		T.it("tout est remis à zéro au début de la manche et au retour à l'attente", function()
			local service, env = setup()
			service:prepare("WetFloorKitchen")
			service:blow("WetFloorKitchen")
			service:prepare("KitchenShelf")
			env.match.MatchStarted:Fire({})
			T.expectEqual(service.rules:get("WetFloorKitchen").state, "Idle")
			local puddle = service.entries.WetFloorKitchen.part
			T.expectEqual(puddle.Transparency, 1)
			T.expectEqual(puddle.CanQuery, true, "ancrage de nouveau détectable")
			T.expectEqual(puddle.Material, service.entries.WetFloorKitchen.look.material)
			T.expectEqual((service:breath()), 3)
			service:prepare("KitchenShelf")
			env.match.PhaseChanged:Fire(Match.Phase.Ended)
			T.expectEqual(service.rules:get("KitchenShelf").state, "Armed", "le résultat garde l'état")
			env.match.PhaseChanged:Fire(Match.Phase.Waiting)
			T.expectEqual(service.rules:get("KitchenShelf").state, "Idle")
		end)
	end)

	T.describe("TrapService : debug", function()
		T.it("exécute arm, blow, drain et reset, puis efface la commande", function()
			local service, env = setup()
			local player = env.join("Testeur", "Mortal", env.near("LivingChandelier"))
			player:SetAttribute(TA.DebugTrap, "arm:LivingChandelier")
			service:_onDebug(player)
			T.expectEqual(player:GetAttribute(TA.DebugTrap), nil)
			T.expectEqual(service.rules:get("LivingChandelier").state, "Armed")
			player:SetAttribute(TA.DebugTrap, "blow:LivingChandelier")
			service:_onDebug(player)
			T.expectEqual(table.concat(env.downs, ","), "Testeur")
			player:SetAttribute(TA.DebugTrap, "drain")
			service:_onDebug(player)
			T.expectEqual((service:breath()), 1)
			player:SetAttribute(TA.DebugTrap, "reset")
			service:_onDebug(player)
			T.expectEqual(service.rules:get("LivingChandelier").state, "Idle")
			player:SetAttribute(TA.DebugTrap, "fly")
			service:_onDebug(player)
			T.expect(#env.warnings > 0, "commande inconnue signalée")
		end)
	end)
end

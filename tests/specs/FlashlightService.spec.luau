-- FlashlightService : interrupteur et batterie contrôlés par le serveur, faisceau qui éclaire (source de lumière),
-- dissipation de la Mort tenue 3 s (reformation loin, charge de souffle perdue), piles posées et ramassées, remise à
-- zéro. Maison réelle (instances simulées par Lune), joueurs, lumière et pièges simulés.
return function(T, Loader)
	local loader = Loader.new()
	local HouseBuilder = loader:require("src/server/HouseBuilder")
	local FlashlightService = loader:require("src/server/FlashlightService")
	local Flashlight = loader:require("src/shared/Flashlight")
	local GameConfig = loader:require("src/shared/GameConfig")
	local LA = loader:require("src/shared/LightAttributes")
	local Match = loader:require("src/shared/Match")
	local Signal = loader:require("src/shared/Signal")

	local house = HouseBuilder.build(Instance.new("Folder"))

	-- Cette méthode permet de monter un service isolé lorsqu'un test démarre ; renvoie le service et l'environnement
	-- simulé (horloge, joueurs, lumière, pièges, vue).
	local function setup()
		local env = {
			now = 0,
			list = {},
			los = true,
			sources = {},
			lit = function(_)
				return false
			end,
			breathRemoved = 0,
			effects = 0,
			notices = {},
			warnings = {},
			phase = Match.Phase.Running,
			prompts = {},
		}
		env.match = {
			MatchStarted = Signal.new(),
			PhaseChanged = Signal.new(),
			getPhase = function()
				return env.phase
			end,
		}
		local service = FlashlightService.new({
			house = house,
			players = {
				GetPlayers = function()
					return env.list
				end,
			},
			match = env.match,
			lights = {
				addLightSource = function(_, test)
					table.insert(env.sources, test)
				end,
				isLit = function(_, position)
					return env.lit(position)
				end,
			},
			traps = {
				removeBreathCharge = function()
					env.breathRemoved += 1
					return true
				end,
			},
			isStudio = false,
			roleOf = function(player)
				return player.role
			end,
			clock = function()
				return env.now
			end,
			lineOfSight = function()
				return env.los
			end,
			teleport = function(player, cframe)
				player.Character.HumanoidRootPart.CFrame = cframe
				player.Character.Head.CFrame = cframe + Vector3.new(0, 1.5, 0)
			end,
			effect = function()
				env.effects += 1
			end,
			pick = function()
				return 1
			end,
			notify = function(player, text)
				table.insert(env.notices, player.Name .. " : " .. text)
			end,
			connectPrompt = function(prompt, fn)
				env.prompts[prompt] = fn
			end,
			remotes = nil,
			heartbeat = nil,
			log = function() end,
			warn = function(message)
				table.insert(env.warnings, message)
			end,
		})
		service:start()

		-- Cette méthode permet de créer un faux joueur avec un personnage (racine et tête) lorsque le test en a besoin.
		function env.player(name, role, position)
			local character = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = CFrame.new(position)
			root.Parent = character
			local head = Instance.new("Part")
			head.Name = "Head"
			head.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
			head.Parent = character
			local attrs = {}
			local player = { Name = name, role = role, Character = character, attrs = attrs }
			function player.GetAttribute(_, key)
				return attrs[key]
			end
			function player.SetAttribute(_, key, value)
				attrs[key] = value
			end
			table.insert(env.list, player)
			return player
		end

		-- Cette méthode permet de faire passer le temps par frames de `dt` lorsque le test attend.
		function env.run(seconds, dt)
			local step = dt or 1 / 30
			local t = 0
			while t < seconds - 1e-9 do
				env.now += step
				t += step
				service:step(step)
			end
		end

		return service, env
	end

	-- Cette méthode permet de pointer la lampe d'un mortel vers un joueur lorsque le test vise la Mort.
	local function aimAt(service, env, mortal, target)
		local from = mortal.Character.Head.CFrame.Position
		env.now += 1
		service:_onAim(mortal, (target.Character.HumanoidRootPart.CFrame.Position - from).Unit)
	end

	T.describe("FlashlightService : interrupteur et batterie", function()
		T.it("un mortel allume sa lampe, pas la Mort", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			local death = env.player("Mort", "Death", Vector3.new(0, 3, -15))
			T.expect(service:toggle(mortal))
			T.expectEqual(mortal.attrs[LA.FlashlightOn], true)
			T.expectEqual(mortal.attrs[LA.FlashlightBattery], 1)
			local ok = service:toggle(death)
			T.expectEqual(ok, false)
		end)

		T.it("la batterie se vide en BATTERY_DURATION s et éteint la lampe, qui ne se rallume plus", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			service:step(0)
			T.expect(service:toggle(mortal))
			env.run(Flashlight.BATTERY_DURATION / 2, 0.1)
			T.expectNear(mortal.attrs[LA.FlashlightBattery], 0.5, 0.011)
			T.expectEqual(service:isOn(mortal), true)
			env.run(Flashlight.BATTERY_DURATION / 2 + 0.2, 0.1)
			T.expectEqual(service:isOn(mortal), false)
			T.expectEqual(mortal.attrs[LA.FlashlightOn], false)
			T.expectEqual(mortal.attrs[LA.FlashlightBattery], 0)
			local ok, err = service:toggle(mortal)
			T.expectEqual(ok, false)
			T.expectEqual(err, "batterie vide")
		end)

		T.it("lampe éteinte : la batterie ne bouge pas", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			env.run(5)
			T.expectEqual(service:batteryOf(mortal), 1)
		end)

		T.it(
			"un mortel qui perd son rôle (agonie) éteint sa lampe et perd ses attributs, batterie gardée",
			function()
				local service, env = setup()
				local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
				service:toggle(mortal)
				env.run(10, 0.1)
				mortal.role = nil
				service:step(0.1)
				T.expectEqual(service:isOn(mortal), false)
				T.expectEqual(mortal.attrs[LA.FlashlightBattery], nil)
				T.expectEqual(mortal.attrs[LA.FlashlightOn], nil)
				mortal.role = "Mortal"
				service:step(0)
				T.expectNear(mortal.attrs[LA.FlashlightBattery], 0.75, 0.011)
			end
		)

		T.it("pose le faisceau sur la tête, allumé selon l'interrupteur", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			service:step(0)
			local attachment = mortal.Character.Head:FindFirstChild("FlashlightBeam")
			T.expect(attachment, "attachment du faisceau")
			local light = attachment:FindFirstChildOfClass("SpotLight")
			T.expectEqual(light.Enabled, false)
			service:toggle(mortal)
			T.expectEqual(light.Enabled, true)
			T.expectEqual(light.Range, Flashlight.RANGE)
		end)

		T.it("refuse un regard invalide", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			service:toggle(mortal)
			service:_onAim(mortal, "nord")
			service:_onAim(mortal, Vector3.new(0, 0, 0))
			service:_onAim(mortal, Vector3.new(0 / 0, 0, 0))
			T.expectEqual(service.holders[mortal].aim, nil)
			env.now += 1
			service:_onAim(mortal, Vector3.new(1, 0, 0))
			T.expectEqual(service.holders[mortal].aim, Vector3.new(1, 0, 0))
		end)
	end)

	T.describe("FlashlightService : faisceau et dissipation", function()
		T.it("éclaire au sens de la règle de lumière : source mobile de LightService", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			local death = env.player("Mort", "Death", Vector3.new(0, 3, -15))
			T.expectEqual(#env.sources, 1)
			local source = env.sources[1]
			local deathPos = death.Character.HumanoidRootPart.CFrame.Position
			service:toggle(mortal)
			aimAt(service, env, mortal, death)
			service:step(1 / 30)
			T.expectEqual(source(deathPos), true)
			T.expectEqual(source(Vector3.new(0, 3, 15)), false, "derrière le mortel")
			env.los = false
			T.expectEqual(source(deathPos), false, "mur entre la lampe et le point")
		end)

		T.it("dissipe la Mort tenue DISPEL_TIME s : reformée loin, une charge de souffle perdue", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			local death = env.player("Mort", "Death", Vector3.new(0, 3, -15))
			local dispelled = nil
			service.Dispelled:Connect(function(info)
				dispelled = info
			end)
			service:toggle(mortal)
			aimAt(service, env, mortal, death)
			env.run(Flashlight.DISPEL_TIME / 2)
			T.expect((death.attrs[LA.DispelProgress] or 0) >= 0.45, "progression publiée")
			T.expectEqual(dispelled, nil, "pas encore")
			env.run(Flashlight.DISPEL_TIME / 2 + 0.05)
			T.expect(dispelled, "dissipée")
			T.expectEqual(env.breathRemoved, 1)
			T.expectEqual(env.effects, 1)
			local now = death.Character.HumanoidRootPart.CFrame.Position
			T.expect(
				(now - mortal.Character.HumanoidRootPart.CFrame.Position).Magnitude >= Flashlight.RESPAWN_MIN_DISTANCE,
				"reformée loin du mortel"
			)
			T.expectEqual(death.attrs[LA.DispelProgress], nil)
		end)

		T.it("ne dissipe pas derrière un mur ni hors du cône", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			local death = env.player("Mort", "Death", Vector3.new(0, 3, -15))
			service:toggle(mortal)
			aimAt(service, env, mortal, death)
			env.los = false
			env.run(Flashlight.DISPEL_TIME + 0.5)
			T.expectEqual(env.breathRemoved, 0, "mur")
			env.los = true
			env.now += 1
			service:_onAim(mortal, Vector3.new(1, 0, 0))
			env.run(Flashlight.DISPEL_TIME + 0.5)
			T.expectEqual(env.breathRemoved, 0, "hors du cône")
		end)

		T.it("lampe éteinte avant 3 s : le cumul repart de zéro", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			local death = env.player("Mort", "Death", Vector3.new(0, 3, -15))
			service:toggle(mortal)
			aimAt(service, env, mortal, death)
			env.run(2)
			env.now += 1
			service:toggle(mortal)
			env.run(1)
			env.now += 1
			service:toggle(mortal)
			env.run(2)
			T.expectEqual(env.breathRemoved, 0)
			env.run(1.1)
			T.expectEqual(env.breathRemoved, 1)
		end)

		T.it("se reforme dans l'ombre : les points éclairés sont écartés", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			local death = env.player("Mort", "Death", Vector3.new(0, 3, -15))
			-- Tout est éclairé sauf la moitié ouest de la maison
			env.lit = function(p)
				return p.X > 30
			end
			service:dispel(death)
			T.expect(death.Character.HumanoidRootPart.CFrame.Position.X <= 30, "point d'ombre")
			T.expect(mortal ~= nil)
		end)
	end)

	T.describe("FlashlightService : piles", function()
		T.it("pose les piles sur des emplacements libres, une par pièce", function()
			local service, _env = setup()
			local chosen = service:placeBatteries()
			T.expectEqual(#chosen, GameConfig.FLASHLIGHT_BATTERY_COUNT)
			local rooms = {}
			for _, id in chosen do
				local part = service.batteries[id]
				T.expect(part and part.Parent, "pile posée " .. id)
				local prompt = part:FindFirstChildOfClass("ProximityPrompt")
				T.expectEqual(prompt.Enabled, false, "le client décide")
				T.expectEqual(prompt:GetAttribute(LA.PromptRole), Match.Role.Mortal)
				local room = service.spots[id]:GetAttribute("RoomId")
				T.expect(not rooms[room], "une par pièce")
				rooms[room] = true
			end
			service:reset()
			for _, id in chosen do
				T.expectEqual(service.batteries[id], nil, "retirée à la remise à zéro")
			end
		end)

		T.it("évite un emplacement déjà occupé (clé)", function()
			local service, _env = setup()
			local first = service.spotList[1]
			for _, spot in service.spotList do
				if spot.id < first.id then
					first = spot
				end
			end
			local key = Instance.new("Part")
			key.Name = "Keys"
			key:SetAttribute("AnchorId", first.id)
			key.Parent = service.spots[first.id].Parent
			local chosen = service:placeBatteries()
			T.expect(not table.find(chosen, first.id), "pas sous la clé")
			key:Destroy()
			service:reset()
		end)

		T.it("une pile remplit la batterie ; refusée lampe pleine ou de trop loin", function()
			local service, env = setup()
			local chosen = service:placeBatteries()
			local id = chosen[1]
			local spot = service.batteries[id].CFrame.Position
			local mortal = env.player("Mortel", "Mortal", spot + Vector3.new(2, 0, 0))
			local ok, err = service:pickBattery(mortal, id)
			T.expectEqual(ok, false)
			T.expectEqual(err, "batterie pleine")
			T.expect(service.batteries[id], "pile laissée en place")
			service:toggle(mortal)
			env.run(20, 0.1)
			local far = env.player("Loin", "Mortal", spot + Vector3.new(40, 0, 0))
			service.holders[far] = nil
			service:_holder(far).battery = 0.2
			T.expectEqual((service:pickBattery(far, id)), false, "trop loin")
			T.expect(service:pickBattery(mortal, id))
			T.expectEqual(service:batteryOf(mortal), 1)
			T.expectEqual(mortal.attrs[LA.FlashlightBattery], 1)
			T.expectEqual(service.batteries[id], nil)
			T.expectEqual((service:pickBattery(mortal, id)), false, "déjà ramassée")
			service:reset()
		end)

		T.it("la manche pose les piles et le retour à l'attente remet tout à zéro", function()
			local service, env = setup()
			local mortal = env.player("Mortel", "Mortal", Vector3.new(0, 3, 0))
			env.match.MatchStarted:Fire({})
			local count = 0
			for _ in service.batteries do
				count += 1
			end
			T.expectEqual(count, GameConfig.FLASHLIGHT_BATTERY_COUNT)
			service:toggle(mortal)
			env.run(10, 0.1)
			env.match.PhaseChanged:Fire(Match.Phase.Waiting)
			T.expectEqual(next(service.batteries), nil)
			T.expectEqual(service:isOn(mortal), false)
			T.expectEqual(service:batteryOf(mortal), 1)
		end)
	end)
end

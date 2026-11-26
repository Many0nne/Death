-- AgonyService : agonie appliquée à une manche simulée (invites sur le personnage, reptation, contrôles serveur du
-- fauchage et du massage, compressions, lutte, révélation du ranimé, nettoyage).
return function(T, Loader)
	local loader = Loader.new()
	local AgonyService = loader:require("src/server/AgonyService")
	local AA = loader:require("src/shared/AgonyAttributes")
	local Agony = loader:require("src/shared/Agony")
	local GameConfig = loader:require("src/shared/GameConfig")
	local LA = loader:require("src/shared/LightAttributes")
	local Signal = loader:require("src/shared/Signal")

	-- Cette méthode permet de créer un faux joueur (rôle, personnage avec racine et Humanoid) lorsque le test agit à sa
	-- place.
	local function fakePlayer(id, name, role, position)
		local character = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(position or Vector3.zero)
		root.Parent = character
		local humanoid = Instance.new("Humanoid")
		humanoid.WalkSpeed = 16
		humanoid.JumpHeight = 7.2
		humanoid.Parent = character
		local player =
			{ UserId = id, Name = name, DisplayName = name, role = role, Character = character, attributes = {} }
		-- Cette méthode permet de lire un attribut du faux joueur lorsque le service le consulte.
		function player.GetAttribute(self, key)
			return self.attributes[key]
		end
		-- Cette méthode permet d'écrire un attribut du faux joueur lorsque le service publie un état.
		function player.SetAttribute(self, key, value)
			self.attributes[key] = value
		end
		-- Cette méthode permet de lire la vitesse de marche du personnage lorsque le test vérifie la reptation.
		function player.speed(self)
			return self.Character:FindFirstChildOfClass("Humanoid").WalkSpeed
		end
		return player
	end

	-- Cette méthode permet de monter un service isolé sur une manche simulée lorsqu'un test démarre ; renvoie le service
	-- et l'environnement (horloge, joueurs, états, messages, Mort immobilisée).
	local function setup()
		local env = { now = 0, los = true, list = {}, states = {}, sent = {}, notices = {}, rooted = {}, beats = 0 }
		local match = {
			MortalStateChanged = Signal.new(),
			PhaseChanged = Signal.new(),
			MatchStarted = Signal.new(),
		}
		-- Cette méthode permet de changer l'état d'un mortel simulé et de prévenir les abonnés comme MatchService.
		local function set(player, to, soul)
			local from = env.states[player.UserId]
			env.states[player.UserId] = to
			match.MortalStateChanged:Fire({ player = player, userId = player.UserId, from = from, to = to, soul = soul })
		end
		-- Cette méthode permet de faire tomber un mortel vivant en agonie lorsque le test simule un accident.
		function match.down(_, player)
			if env.states[player.UserId] ~= "Alive" then
				return false, "pas vivant"
			end
			set(player, "Agony")
			return true
		end
		-- Cette méthode permet de ranimer un agonisant lorsque le service l'ordonne.
		function match.revive(_, player)
			if env.states[player.UserId] ~= "Agony" then
				return false, "pas en agonie"
			end
			set(player, "Alive")
			return true
		end
		-- Cette méthode permet de déclarer un mortel mort lorsque le service l'ordonne (âme fauchée ou échappée).
		function match.kill(_, player, reaped)
			set(player, "Dead", if reaped then "Reaped" else "Escaped")
			return true
		end
		env.match = match
		local service = AgonyService.new({
			match = match,
			death = {
				setRooted = function(_, player, rooted)
					env.rooted[player.Name] = rooted or nil
				end,
			},
			players = {
				GetPlayers = function()
					return env.list
				end,
			},
			isStudio = false,
			roleOf = function(player)
				return if env.states[player.UserId] == nil or env.states[player.UserId] == "Alive"
					then player.role
					else nil
			end,
			clock = function()
				return env.now
			end,
			serverTime = function()
				return 1000 + env.now
			end,
			connectPrompt = function(prompt, fn, holdBegan)
				env[prompt] = { fn = fn, hold = holdBegan }
			end,
			lineOfSight = function()
				return env.los
			end,
			send = function(player, kind, a)
				table.insert(env.sent, string.format("%s:%s:%s", player.Name, kind, tostring(a)))
			end,
			onPress = function() end,
			notify = function(player, text)
				table.insert(env.notices, player.Name .. " : " .. text)
			end,
			play = function()
				env.beats += 1
			end,
			heartbeat = nil,
			log = function() end,
			warn = function() end,
		})
		service:start()

		-- Cette méthode permet d'ajouter un joueur (mortel vivant ou Mort) au serveur simulé.
		function env.join(id, name, role, position)
			local player = fakePlayer(id, name, role, position)
			table.insert(env.list, player)
			if role == "Mortal" then
				env.states[id] = "Alive"
			end
			return player
		end

		-- Cette méthode permet de laisser passer le temps par pas de `dt` lorsque le test attend une issue.
		function env.run(seconds, dt)
			local step = dt or 0.05
			local t = 0
			while t < seconds - 1e-9 do
				env.now += step
				t += step
				service:step(step)
			end
		end

		-- Cette méthode permet de maintenir puis déclencher une invite comme le ferait le joueur.
		function env.trigger(prompt, player, hold)
			local t = env[prompt]
			t.hold(player)
			env.now += hold or prompt.HoldDuration
			t.fn(player)
		end

		-- Cette méthode permet de masser à une cadence fixe jusqu'à une issue (ou `limit` secondes).
		function env.massage(player, bpm, limit)
			local period = 60 / bpm
			local t = 0
			while t < limit and service.massagers[player.UserId] do
				service:press(player)
				env.run(period, period / 4)
				t += period
			end
			return t
		end
		return service, env
	end

	T.describe("AgonyService : agonie", function()
		T.it("le mortel tombé rampe, porte les invites et le cœur, et meurt seul au bout de 45 s", function()
			local service, env = setup()
			local victim = env.join(2, "Victime", "Mortal")
			env.match:down(victim)
			local entry = service.entries[2]
			T.expect(entry and entry.prompts, "invites posées")
			T.expectEqual(entry.prompts.reap.Parent, victim.Character.HumanoidRootPart)
			T.expectEqual(entry.prompts.reap:GetAttribute(LA.PromptRole), "Death")
			T.expectEqual(entry.prompts.massage:GetAttribute(LA.PromptRole), "Mortal")
			T.expectEqual(entry.prompts.reap.HoldDuration, GameConfig.REAP_DURATION)
			T.expectEqual(victim:GetAttribute(AA.AgonyEnd), 1000 + GameConfig.AGONY_DURATION)
			env.run(0.1)
			T.expectEqual(victim:speed(), GameConfig.CRAWL_SPEED)
			T.expect(env.beats >= 1, "le cœur bat")
			env.run(GameConfig.AGONY_DURATION - 1, 0.25)
			T.expectEqual(env.states[2], "Agony")
			env.run(1.5, 0.25)
			T.expectEqual(env.states[2], "Dead")
			T.expectEqual(victim.Character.HumanoidRootPart:FindFirstChild(AA.PromptName), nil, "invites retirées")
			T.expectEqual(victim:GetAttribute(AA.AgonyEnd), nil)
			T.expectEqual(victim:speed(), 16, "vitesse rendue")
			T.expect(env.beats > 20 and env.beats < 60, "battements : " .. env.beats)
		end)
	end)

	T.describe("AgonyService : fauchage", function()
		T.it("la Mort qui tient 4 s récolte l'âme", function()
			local service, env = setup()
			local victim = env.join(2, "Victime", "Mortal")
			local death = env.join(1, "Mort", "Death", Vector3.new(3, 0, 0))
			env.match:down(victim)
			local reaped
			env.match.MortalStateChanged:Connect(function(change)
				reaped = change.soul
			end)
			env.trigger(service.entries[2].prompts.reap, death)
			T.expectEqual(reaped, "Reaped")
			T.expectEqual(service.entries[2], nil)
		end)
		T.it("refuse un maintien trop court, un mortel, une Mort trop loin ou sans vue", function()
			local service, env = setup()
			local victim = env.join(2, "Victime", "Mortal")
			local death = env.join(1, "Mort", "Death", Vector3.new(3, 0, 0))
			local other = env.join(3, "Autre", "Mortal", Vector3.new(2, 0, 0))
			env.match:down(victim)
			local prompt = service.entries[2].prompts.reap
			env.trigger(prompt, death, 1)
			env.trigger(prompt, other)
			env.los = false
			env.trigger(prompt, death)
			env.los = true
			death.Character.HumanoidRootPart.CFrame = CFrame.new(40, 0, 0)
			env.trigger(prompt, death)
			T.expectEqual(env.states[2], "Agony")
		end)
	end)

	T.describe("AgonyService : massage cardiaque", function()
		T.it("au bon rythme, ranime en environ 8 s ; le ranimé est révélé 20 s", function()
			local service, env = setup()
			local victim = env.join(2, "Victime", "Mortal")
			local medic = env.join(3, "Medic", "Mortal", Vector3.new(2, 0, 0))
			env.match:down(victim)
			env.trigger(service.entries[2].prompts.massage, medic)
			T.expectEqual(env.sent[1], "Medic:Massage:2")
			env.run(0.05)
			T.expectEqual(medic:speed(), 0, "masseur sur place")
			T.expectEqual(service.entries[2].prompts.massage:GetAttribute(LA.PromptAvailable), false, "un seul masseur")
			local took = env.massage(medic, 110, 20)
			T.expectEqual(env.states[2], "Alive")
			T.expect(took >= 7.5 and took <= 9.5, string.format("massage %.2f s", took))
			T.expectEqual(env.sent[#env.sent], "Medic:Massage:nil")
			T.expectEqual(medic:speed(), 16, "masseur libéré")
			T.expectEqual(victim:speed(), 16, "ranimé debout")
			T.expectNear(victim:GetAttribute(AA.RevealedUntil), 1000 + env.now + GameConfig.REVEAL_DURATION, 0.6)
			env.run(GameConfig.REVEAL_DURATION - 1, 0.5)
			T.expect(victim:GetAttribute(AA.RevealedUntil) ~= nil, "encore révélé")
			env.run(1.5, 0.5)
			T.expectEqual(victim:GetAttribute(AA.RevealedUntil), nil, "révélation finie")
		end)
		T.it("massage abandonné : masseur libéré, l'agonie continue", function()
			local service, env = setup()
			local victim = env.join(2, "Victime", "Mortal")
			local medic = env.join(3, "Medic", "Mortal", Vector3.new(2, 0, 0))
			env.match:down(victim)
			env.trigger(service.entries[2].prompts.massage, medic)
			env.run(Agony.MASSAGE_IDLE + 0.2)
			T.expectEqual(service.massagers[3], nil)
			T.expectEqual(medic:speed(), 16)
			T.expectEqual(env.states[2], "Agony")
		end)
		T.it("un masseur touché par un accident arrête de masser", function()
			local service, env = setup()
			local victim = env.join(2, "Victime", "Mortal")
			local medic = env.join(3, "Medic", "Mortal", Vector3.new(2, 0, 0))
			env.match:down(victim)
			env.trigger(service.entries[2].prompts.massage, medic)
			env.match:down(medic)
			T.expectEqual(service.massagers[3], nil)
			T.expectEqual(service.rules:get(2).massager, nil)
			T.expect(service.entries[3] ~= nil, "le masseur agonise à son tour")
		end)
	end)

	T.describe("AgonyService : lutte pour l'âme", function()
		-- Cette méthode permet de lancer une lutte (massage en cours, puis fauchage fini) lorsque le test en a besoin.
		local function struggle()
			local service, env = setup()
			local victim = env.join(2, "Victime", "Mortal")
			local medic = env.join(3, "Medic", "Mortal", Vector3.new(2, 0, 0))
			local death = env.join(1, "Mort", "Death", Vector3.new(-3, 0, 0))
			env.match:down(victim)
			env.trigger(service.entries[2].prompts.massage, medic)
			service:press(medic)
			env.trigger(service.entries[2].prompts.reap, death)
			return service, env, medic
		end

		T.it("le fauchage pendant un massage immobilise la Mort et publie la lutte", function()
			local service, env = struggle()
			T.expectEqual(env.rooted.Mort, true)
			T.expectEqual(service.rules:get(2).pull, Agony.STRUGGLE_START)
			env.run(0.05)
			T.expect(env.list[1]:GetAttribute(AA.SoulPull) ~= nil, "lutte publiée")
			T.expectEqual(service.entries[2].prompts.reap:GetAttribute(LA.PromptAvailable), false)
		end)
		T.it("un bon rythme gagne : ranimé, Mort libérée", function()
			local _, env, medic = struggle()
			env.massage(medic, 110, 20)
			T.expectEqual(env.states[2], "Alive")
			T.expectEqual(env.rooted.Mort, nil)
		end)
		T.it("un mauvais rythme perd : âme fauchée, Mort libérée", function()
			local _, env, medic = struggle()
			env.massage(medic, 75, 20)
			T.expectEqual(env.states[2], "Dead")
			T.expectEqual(env.rooted.Mort, nil)
			T.expectEqual(medic:speed(), 16)
		end)
	end)

	T.describe("AgonyService : fin de manche", function()
		T.it("tout est nettoyé quand la manche se termine", function()
			local service, env = setup()
			local victim = env.join(2, "Victime", "Mortal")
			local medic = env.join(3, "Medic", "Mortal", Vector3.new(2, 0, 0))
			env.match:down(victim)
			env.trigger(service.entries[2].prompts.massage, medic)
			env.match.PhaseChanged:Fire("Ended")
			T.expectEqual(next(service.entries), nil)
			T.expectEqual(next(service.massagers), nil)
			T.expectEqual(victim:GetAttribute(AA.AgonyEnd), nil)
			T.expectEqual(medic:speed(), 16)
			T.expectEqual(victim:speed(), 16)
		end)
	end)
end

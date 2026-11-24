-- MatchService : cycle de manche serveur, réplication par attributs, API d'état et attributs de debug, avec des faux
-- joueurs et un faux Heartbeat que le test déclenche lui-même.
return function(T, Loader)
	local loader = Loader.new()
	local Signal = loader:require("src/shared/Signal")
	local Match = loader:require("src/shared/Match")
	local GameConfig = loader:require("src/shared/GameConfig")
	local A = loader:require("src/shared/MatchAttributes")
	local MatchService = loader:require("src/server/MatchService")
	local S = Match.MortalState

	-- Cette méthode permet de créer un objet à attributs (faux Player ou ReplicatedStorage) lorsqu'un test observe
	-- la réplication ; AttributeChanged est déclenché comme en jeu.
	local function attributeHolder(fields)
		local holder = fields or {}
		holder.attributes = {}
		holder.AttributeChanged = Signal.new()
		-- Cette méthode permet d'écrire un attribut lorsqu'il change, et de prévenir les abonnés comme en jeu.
		function holder.SetAttribute(self, name, value)
			if self.attributes[name] ~= value then
				self.attributes[name] = value
				self.AttributeChanged:Fire(name)
			end
		end
		-- Cette méthode permet de lire un attribut lorsqu'un test ou le service le consulte.
		function holder.GetAttribute(self, name)
			return self.attributes[name]
		end
		return holder
	end

	-- Cette méthode permet de monter un service de manche isolé lorsqu'un test démarre, avec `count` joueurs
	-- (UserId 1..count) ; renvoie le service, l'environnement simulé et ses joueurs.
	local function setup(count, options)
		options = options or {}
		local env = {
			list = {},
			replicated = attributeHolder(),
			heartbeat = Signal.new(),
			logs = {},
			warnings = {},
			encoded = nil,
		}
		local players = {
			PlayerAdded = Signal.new(),
			PlayerRemoving = Signal.new(),
		}
		-- Cette méthode permet de lister les faux joueurs présents lorsque le service compte les joueurs.
		function players.GetPlayers()
			return table.clone(env.list)
		end
		-- Cette méthode permet d'ajouter un faux joueur lorsqu'un test simule une arrivée sur le serveur.
		function env.join(id)
			local player = attributeHolder({ UserId = id, Name = "Joueur" .. id })
			table.insert(env.list, player)
			players.PlayerAdded:Fire(player)
			return player
		end
		-- Cette méthode permet de retirer un faux joueur lorsqu'un test simule un départ du serveur.
		function env.leave(player)
			players.PlayerRemoving:Fire(player)
			table.remove(env.list, table.find(env.list, player))
		end
		-- Cette méthode permet d'avancer le faux Heartbeat lorsqu'un test fait passer le temps (pas de 1 s par défaut).
		function env.step(seconds, dt)
			local step = dt or 1
			local elapsed = 0
			while elapsed < seconds do
				env.heartbeat:Fire(step)
				elapsed += step
			end
		end
		for id = 1, count do
			env.join(id)
		end
		local service = MatchService.new({
			players = players,
			replicated = env.replicated,
			heartbeat = env.heartbeat,
			isStudio = options.isStudio ~= false,
			pick = options.pick or function(_n)
				return 1
			end,
			encode = function(value)
				env.encoded = value
				return "json"
			end,
			log = function(message)
				table.insert(env.logs, message)
			end,
			warn = function(message)
				table.insert(env.warnings, message)
			end,
		})
		service:start()
		return service, env, env.list
	end

	T.describe("MatchService (démarrage)", function()
		T.it("attend en phase Waiting au démarrage", function()
			local _, env = setup(2)
			T.expectEqual(env.replicated:GetAttribute(A.Phase), Match.Phase.Waiting)
		end)
		T.it("mode test : 1 Mort + 1 mortel, rôles et sablier répliqués", function()
			local service, env, players = setup(2)
			T.expect(service:startMatch({ test = true }))
			T.expectEqual(env.replicated:GetAttribute(A.Phase), Match.Phase.Running)
			T.expectEqual(env.replicated:GetAttribute(A.TimeLeft), GameConfig.MATCH_DURATION)
			T.expectEqual(env.replicated:GetAttribute(A.Duration), GameConfig.MATCH_DURATION)
			T.expectEqual(players[1]:GetAttribute(A.Role), Match.Role.Death)
			T.expectEqual(players[1]:GetAttribute(A.MortalState), nil)
			T.expectEqual(players[2]:GetAttribute(A.Role), Match.Role.Mortal)
			T.expectEqual(players[2]:GetAttribute(A.MortalState), S.Alive)
		end)
		T.it("hors mode test, il faut 4 mortels", function()
			local service = setup(2)
			local ok, err = service:startMatch()
			T.expectEqual(ok, false)
			T.expect(err ~= nil)
		end)
		T.it("le mode test est refusé hors Studio", function()
			local service = setup(2, { isStudio = false })
			T.expectEqual((service:startMatch({ test = true })), false)
		end)
		T.it("mode test : refusé seul ou à plus de 5", function()
			T.expectEqual((setup(1):startMatch({ test = true })), false)
			T.expectEqual((setup(6):startMatch({ test = true })), false)
		end)
		T.it("serveur complet : démarrage automatique après l'attente", function()
			local service = setup(5)
			service._step(service, GameConfig.INTERMISSION_DURATION - 1)
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
			service._step(service, 1)
			T.expectEqual(service:getPhase(), Match.Phase.Running)
		end)
		T.it("pas de démarrage automatique à moins de 5 joueurs", function()
			local service = setup(3)
			service._step(service, GameConfig.INTERMISSION_DURATION * 2)
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
		end)
	end)

	T.describe("MatchService (API d'état)", function()
		T.it("agonie, fauchage : attributs et événement", function()
			local service, _, players = setup(3)
			service:startMatch({ test = true })
			local events = {}
			service.MortalStateChanged:Connect(function(change)
				table.insert(events, change)
			end)
			T.expect(service:down(players[2]))
			T.expectEqual(players[2]:GetAttribute(A.MortalState), S.Agony)
			T.expect(service:kill(players[2], true))
			T.expectEqual(players[2]:GetAttribute(A.MortalState), S.Dead)
			T.expectEqual(players[2]:GetAttribute(A.SoulFate), Match.SoulFate.Reaped)
			T.expectEqual(#events, 2)
			T.expectEqual(events[2].player, players[2])
			T.expectEqual(events[2].from, S.Agony)
			T.expectEqual(service:getMortalState(players[2]), S.Dead)
		end)
		T.it("refus motivé : fauche debout, Mort, hors manche", function()
			local service, _, players = setup(2)
			T.expectEqual((service:down(players[2])), false)
			service:startMatch({ test = true })
			local ok, err = service:kill(players[2], true)
			T.expectEqual(ok, false)
			T.expect(err ~= nil)
			T.expectEqual((service:down(players[1])), false)
		end)
		T.it("dernier mortel résolu : résultat publié avant la phase Ended", function()
			local service, env, players = setup(3)
			service:startMatch({ test = true })
			local resultAtEnded
			env.replicated.AttributeChanged:Connect(function(name)
				if name == A.Phase and env.replicated:GetAttribute(A.Phase) == Match.Phase.Ended then
					resultAtEnded = env.replicated:GetAttribute(A.Result)
				end
			end)
			local ended
			service.MatchEnded:Connect(function(result)
				ended = result
			end)
			service:save(players[2])
			T.expectEqual(service:getPhase(), Match.Phase.Running)
			service:kill(players[3])
			T.expectEqual(service:getPhase(), Match.Phase.Ended)
			T.expectEqual(resultAtEnded, "json")
			T.expectEqual(env.replicated:GetAttribute(A.EndReason), Match.EndReason.AllResolved)
			T.expectEqual(ended.saved, 1)
			T.expectEqual(ended.escaped, 1)
			T.expectEqual(ended.death.name, "Joueur1")
			T.expectEqual(env.encoded.mortals[1].name, "Joueur2")
			T.expectEqual(env.encoded.mortals[2].soul, Match.SoulFate.Escaped)
		end)
	end)

	T.describe("MatchService (sablier et fin)", function()
		T.it("le temps restant est répliqué en secondes entières", function()
			local service, env = setup(2)
			service:startMatch({ test = true })
			env.step(1.5, 0.5)
			T.expectEqual(env.replicated:GetAttribute(A.TimeLeft), GameConfig.MATCH_DURATION - 1)
			T.expectNear(service:getTimeLeft(), GameConfig.MATCH_DURATION - 1.5)
		end)
		T.it("fin du sablier : mortels restants morts, âme échappée, puis retour à l'attente", function()
			local service, env, players = setup(3)
			service:startMatch({ test = true })
			service:save(players[2])
			env.step(GameConfig.MATCH_DURATION, 10)
			T.expectEqual(service:getPhase(), Match.Phase.Ended)
			T.expectEqual(env.replicated:GetAttribute(A.EndReason), Match.EndReason.TimeUp)
			T.expectEqual(env.replicated:GetAttribute(A.TimeLeft), 0)
			T.expectEqual(players[3]:GetAttribute(A.MortalState), S.Dead)
			T.expectEqual(players[3]:GetAttribute(A.SoulFate), Match.SoulFate.Escaped)
			T.expectEqual(env.encoded.mortals[2].cause, Match.DeathCause.TimeUp)
			env.step(GameConfig.RESULT_DURATION)
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
			T.expectEqual(env.replicated:GetAttribute(A.Phase), Match.Phase.Waiting)
			T.expectEqual(env.replicated:GetAttribute(A.TimeLeft), nil)
			T.expectEqual(env.replicated:GetAttribute(A.Result), "json")
			T.expectEqual(players[2]:GetAttribute(A.Role), nil)
			T.expectEqual(players[3]:GetAttribute(A.MortalState), nil)
			T.expectEqual(players[3]:GetAttribute(A.SoulFate), nil)
		end)
	end)

	T.describe("MatchService (départs)", function()
		T.it("un mortel qui part meurt, âme échappée", function()
			local service, env, players = setup(3)
			service:startMatch({ test = true })
			local leaver, other = players[2], players[3]
			local event
			service.MortalStateChanged:Connect(function(change)
				event = change
			end)
			env.leave(leaver)
			T.expectEqual(event.player, leaver)
			T.expectEqual(service.match:stateOf(2), S.Dead)
			T.expectEqual(service:getPhase(), Match.Phase.Running)
			service:kill(other)
			T.expectEqual(env.encoded.mortals[1].cause, Match.DeathCause.Left)
			T.expectEqual(env.encoded.mortals[1].soul, Match.SoulFate.Escaped)
		end)
		T.it("un mortel déjà mort qui part ne change rien", function()
			local service, env, players = setup(3)
			service:startMatch({ test = true })
			local dead = players[2]
			service:kill(dead)
			env.leave(dead)
			T.expectEqual(service:getPhase(), Match.Phase.Running)
			T.expectEqual(service.match.mortals[2].cause, Match.DeathCause.Accident)
		end)
		T.it("la Mort qui part annule la manche", function()
			local service, env, players = setup(3)
			service:startMatch({ test = true })
			local death, mortal = players[1], players[2]
			local cancelled = false
			service.MatchCancelled:Connect(function()
				cancelled = true
			end)
			env.leave(death)
			T.expect(cancelled, "MatchCancelled attendu")
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
			T.expectEqual(mortal:GetAttribute(A.Role), nil)
		end)
	end)

	T.describe("MatchService (attributs de debug)", function()
		T.it("DebugStartMatch démarre et se remet à nil", function()
			local service, _, players = setup(2)
			players[2]:SetAttribute(A.DebugStart, true)
			T.expectEqual(service:getPhase(), Match.Phase.Running)
			T.expectEqual(players[2]:GetAttribute(A.DebugStart), nil)
		end)
		T.it("DebugRole force la Mort", function()
			local service, _, players = setup(3)
			players[3]:SetAttribute(A.DebugRole, "Death")
			players[1]:SetAttribute(A.DebugStart, true)
			T.expectEqual(service:getRole(players[3]), Match.Role.Death)
			T.expectEqual(players[3]:GetAttribute(A.Role), Match.Role.Death)
		end)
		T.it("DebugSetState change l'état d'un mortel", function()
			local service, _, players = setup(3)
			players[1]:SetAttribute(A.DebugStart, true)
			players[2]:SetAttribute(A.DebugState, "Agony")
			T.expectEqual(players[2]:GetAttribute(A.MortalState), S.Agony)
			players[2]:SetAttribute(A.DebugState, "Reaped")
			T.expectEqual(players[2]:GetAttribute(A.SoulFate), Match.SoulFate.Reaped)
			T.expectEqual(players[2]:GetAttribute(A.DebugState), nil)
			players[3]:SetAttribute(A.DebugState, "Inconnu")
			T.expectEqual(service:getMortalState(players[3]), S.Alive)
		end)
		T.it("DebugTimeScale accélère le sablier", function()
			local service, env, players = setup(2)
			players[1]:SetAttribute(A.DebugStart, true)
			players[1]:SetAttribute(A.DebugTimeScale, 10)
			env.step(1)
			T.expectNear(service:getTimeLeft(), GameConfig.MATCH_DURATION - 10)
			players[1]:SetAttribute(A.DebugTimeScale, nil)
			env.step(1)
			T.expectNear(service:getTimeLeft(), GameConfig.MATCH_DURATION - 11)
		end)
		T.it("le sablier accéléré revient à x1 quand son joueur part", function()
			local service, env, players = setup(3)
			local tester = players[3]
			tester:SetAttribute(A.DebugTimeScale, 10)
			env.leave(tester)
			players[1]:SetAttribute(A.DebugStart, true)
			env.step(1)
			T.expectNear(service:getTimeLeft(), GameConfig.MATCH_DURATION - 1)
		end)
		T.it("DebugRole invalide : signalé et ignoré", function()
			local service, env, players = setup(2)
			players[2]:SetAttribute(A.DebugRole, "death")
			players[1]:SetAttribute(A.DebugStart, true)
			T.expectEqual(service:getRole(players[1]), Match.Role.Death)
			T.expect(#env.warnings == 1, "un avertissement attendu")
		end)
		T.it("relancer depuis le résultat repasse par l'attente", function()
			local service, _, players = setup(2)
			players[1]:SetAttribute(A.DebugStart, true)
			players[1]:SetAttribute(A.DebugTimeLeft, 0)
			local phases = {}
			service.PhaseChanged:Connect(function(phase)
				table.insert(phases, phase)
			end)
			players[1]:SetAttribute(A.DebugStart, true)
			T.expectEqual(table.concat(phases, ","), "Waiting,Running")
		end)
		T.it("un abonné qui annule la manche coupe les changements suivants", function()
			local service, env, players = setup(4)
			players[1]:SetAttribute(A.DebugStart, true)
			local count = 0
			service.MortalStateChanged:Connect(function()
				count += 1
				service:stopMatch()
			end)
			local ended = false
			service.MatchEnded:Connect(function()
				ended = true
			end)
			env.step(GameConfig.MATCH_DURATION, GameConfig.MATCH_DURATION)
			T.expectEqual(count, 1)
			T.expect(not ended, "pas de résultat pour une manche annulée")
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
		end)
		T.it("DebugTimeLeft = 0 termine la manche aussitôt", function()
			local service, _, players = setup(2)
			players[1]:SetAttribute(A.DebugStart, true)
			players[1]:SetAttribute(A.DebugTimeLeft, 0)
			T.expectEqual(service:getPhase(), Match.Phase.Ended)
			T.expectEqual(players[2]:GetAttribute(A.MortalState), S.Dead)
		end)
		T.it("DebugStopMatch annule la manche", function()
			local service, _, players = setup(2)
			players[1]:SetAttribute(A.DebugStart, true)
			players[1]:SetAttribute(A.DebugStop, true)
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
		end)
		T.it("hors Studio, les attributs de debug sont ignorés", function()
			local service, _, players = setup(2, { isStudio = false })
			players[1]:SetAttribute(A.DebugStart, true)
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
		end)
	end)
end

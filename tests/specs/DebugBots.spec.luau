-- DebugBots (#12) : faux joueurs de debug comptés par MatchService, avec faux Players et faux mannequins.
return function(T, Loader)
	local loader = Loader.new()
	local Signal = loader:require("src/shared/Signal")
	local Match = loader:require("src/shared/Match")
	local A = loader:require("src/shared/MatchAttributes")
	local MatchService = loader:require("src/server/MatchService")
	local S = Match.MortalState

	-- Cette méthode permet de créer un objet à attributs (faux joueur, mannequin, ReplicatedStorage) lorsqu'un test
	-- observe la réplication ; AttributeChanged est déclenché comme en jeu.
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
		-- Cette méthode permet de lire un attribut lorsqu'un test ou le service le consulte.
		function holder.GetAttribute(self, name)
			return self.attributes[name]
		end
		return holder
	end

	-- Cette méthode permet de monter un service de manche isolé avec `count` vrais joueurs (UserId 1..count) et un
	-- faux fabricant de mannequins ; renvoie le service, les joueurs, les mannequins créés et les avertissements.
	local function setup(count, isStudio)
		local list, mannequins, warnings = {}, {}, {}
		local players = { PlayerAdded = Signal.new(), PlayerRemoving = Signal.new() }
		function players.GetPlayers()
			return table.clone(list)
		end
		for id = 1, count do
			table.insert(list, attributeHolder({ UserId = id, Name = "Joueur" .. id }))
		end
		local service = MatchService.new({
			players = players,
			replicated = attributeHolder(),
			heartbeat = Signal.new(),
			isStudio = isStudio ~= false,
			createMannequin = function(name)
				local model = attributeHolder({ Name = name, destroyed = false })
				function model.Destroy(self)
					self.destroyed = true
				end
				table.insert(mannequins, model)
				return model
			end,
			pick = function()
				return 1
			end,
			encode = function()
				return "json"
			end,
			log = function() end,
			warn = function(message)
				table.insert(warnings, message)
			end,
		})
		service:start()
		return service, list, mannequins, warnings
	end

	T.describe("DebugBots (ajout)", function()
		T.it("un bot Mortal avec un seul joueur permet une manche de test", function()
			local service, list, mannequins = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Mortal")
			T.expectEqual(#mannequins, 1)
			T.expectEqual(list[1]:GetAttribute(A.DebugAddBot), nil)
			T.expect(service:startMatch({ test = true }))
			T.expectEqual(service:getRole(list[1]), Match.Role.Death)
			local bot = service:getBot(service.bots:list()[1].UserId)
			T.expectEqual(service:getRole(bot), Match.Role.Mortal)
			T.expectEqual(mannequins[1]:GetAttribute(A.MortalState), S.Alive)
		end)
		T.it("un bot Death prend la Mort, le joueur devient mortel", function()
			local service, list = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Death")
			T.expect(service:startMatch({ test = true }))
			T.expectEqual(service:getRole(list[1]), Match.Role.Mortal)
			T.expectEqual(service:getRole(service.bots:list()[1]), Match.Role.Death)
		end)
		T.it("noms numérotés par rôle, et les bots ne lancent pas de manche automatique", function()
			local service, list, mannequins = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Death")
			for _ = 1, 4 do
				list[1]:SetAttribute(A.DebugAddBot, "Mortal")
			end
			T.expectEqual(mannequins[1].Name, "Bot Mort 1")
			T.expectEqual(mannequins[2].Name, "Bot Mortel 1")
			service:_step(1000)
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
		end)
		T.it("sans bot, un seul joueur ne peut pas démarrer", function()
			local service = setup(1)
			T.expectEqual((service:startMatch({ test = true })), false)
		end)
		T.it("valeur inconnue : avertissement, aucun bot", function()
			local service, list, mannequins, warnings = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Zombie")
			T.expectEqual(#mannequins, 0)
			T.expectEqual(#service.bots:list(), 0)
			T.expectEqual(#warnings, 1)
		end)
		T.it("hors Studio, DebugAddBot est ignoré", function()
			local _, list, mannequins = setup(1, false)
			list[1]:SetAttribute(A.DebugAddBot, "Mortal")
			T.expectEqual(#mannequins, 0)
		end)
	end)

	T.describe("DebugBots (état et fin de manche)", function()
		T.it("DebugSetState posé sur le mannequin vise le faux mortel", function()
			local service, list, mannequins = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Mortal")
			service:startMatch({ test = true })
			mannequins[1]:SetAttribute(A.DebugState, "Agony")
			local bot = service.bots:list()[1]
			T.expectEqual(service:getMortalState(bot), S.Agony)
			T.expectEqual(mannequins[1]:GetAttribute(A.MortalState), S.Agony)
			T.expectEqual(mannequins[1]:GetAttribute(A.DebugState), nil)
		end)
		T.it("la manche finit quand le seul faux mortel meurt ou est sauvé", function()
			local service, list, mannequins = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Mortal")
			service:startMatch({ test = true })
			local ended
			service.MatchEnded:Connect(function(result)
				ended = result
			end)
			mannequins[1]:SetAttribute(A.DebugState, "Saved")
			T.expectEqual(service:getPhase(), Match.Phase.Ended)
			T.expectEqual(ended.saved, 1)
			T.expectEqual(ended.mortals[1].name, mannequins[1].Name)
		end)
		T.it("un bot reste disponible pour la manche suivante", function()
			local service, list, mannequins = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Mortal")
			service:startMatch({ test = true })
			mannequins[1]:SetAttribute(A.DebugState, "Dead")
			service:stopMatch()
			T.expect(service:startMatch({ test = true }))
			T.expectEqual(mannequins[1]:GetAttribute(A.MortalState), S.Alive)
		end)
	end)

	T.describe("DebugBots (retrait)", function()
		T.it("DebugClearBots détruit les mannequins hors manche", function()
			local service, list, mannequins = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Mortal")
			list[1]:SetAttribute(A.DebugAddBot, "Death")
			T.expectEqual(#service.bots:list(), 2)
			list[1]:SetAttribute(A.DebugClearBots, true)
			T.expectEqual(#service.bots:list(), 0)
			T.expect(mannequins[1].destroyed and mannequins[2].destroyed)
		end)
		T.it("retirer le faux mortel en manche le fait mourir et termine la manche", function()
			local service, list = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Mortal")
			service:startMatch({ test = true })
			local result
			service.MatchEnded:Connect(function(r)
				result = r
			end)
			list[1]:SetAttribute(A.DebugClearBots, true)
			T.expectEqual(service:getPhase(), Match.Phase.Ended)
			T.expectEqual(result.escaped, 1)
		end)
		T.it("retirer le faux Mort en manche annule la manche", function()
			local service, list = setup(1)
			list[1]:SetAttribute(A.DebugAddBot, "Death")
			service:startMatch({ test = true })
			list[1]:SetAttribute(A.DebugClearBots, true)
			T.expectEqual(service:getPhase(), Match.Phase.Waiting)
		end)
	end)
end

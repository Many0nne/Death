-- Participants du serveur (#52) : vrais joueurs plus faux joueurs de debug (Server.DebugBots, Studio seulement), avec
-- l'API du service Players dont les services de jeu ont besoin : GetPlayers, PlayerAdded, PlayerRemoving. Les pièges,
-- la lumière, la lampe torche, la Mort et l'agonie le reçoivent à la place de Players (`MatchService:roster()`), si
-- bien qu'un bot est visé comme un joueur. En jeu publié, aucun bot n'existe : c'est la liste de Players.
local Roster = {}
Roster.__index = Roster

-- Cette méthode permet de créer la liste des participants lorsque le service de manche démarre ; `players` est le
-- service Players (ou un faux), `bots` le registre DebugBots (signaux Added et Removing).
function Roster.new(players, bots)
	local self = setmetatable({ players = players, bots = bots }, Roster)
	self.PlayerAdded = Roster._merged(players and players.PlayerAdded, bots.Added)
	self.PlayerRemoving = Roster._merged(players and players.PlayerRemoving, bots.Removing)
	return self
end

-- Cette méthode permet de fusionner le signal d'un joueur et celui d'un bot lorsqu'un service s'abonne à une arrivée ou
-- à un départ : Connect branche les deux, la connexion renvoyée les coupe ensemble.
function Roster._merged(playerSignal, botSignal)
	return {
		-- Cette méthode permet de brancher `fn` sur l'arrivée (ou le départ) d'un joueur et d'un bot lorsqu'un service
		-- s'abonne.
		Connect = function(_, fn)
			local connections = { botSignal:Connect(fn) }
			if playerSignal then
				table.insert(connections, playerSignal:Connect(fn))
			end
			local connection = { Connected = true }
			-- Cette méthode permet de couper les deux abonnements lorsque le service n'écoute plus.
			function connection.Disconnect(conn)
				conn.Connected = false
				for _, c in connections do
					c:Disconnect()
				end
			end
			return connection
		end,
	}
end

-- Cette méthode permet de lister vrais joueurs puis bots lorsqu'un service parcourt les participants (comme
-- Players:GetPlayers, nouvelle table à chaque appel).
function Roster:GetPlayers(): { any }
	local list = if self.players then table.clone(self.players:GetPlayers()) else {}
	for _, bot in self.bots:list() do
		table.insert(list, bot)
	end
	return list
end

return Roster

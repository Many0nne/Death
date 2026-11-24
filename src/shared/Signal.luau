-- Signal minimal (Connect / Fire) pour les événements serveur de la manche, sans Instance : testable sous Lune.
-- Les abonnés sont appelés dans l'ordre de connexion ; l'erreur d'un abonné est signalée sans bloquer les autres.
local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (Connection) -> (),
}

-- Cette méthode permet de créer un signal sans abonné lorsqu'un module expose un événement à d'autres modules.
function Signal.new()
	return setmetatable({ _listeners = {} }, Signal)
end

-- Cette méthode permet d'abonner une fonction au signal lorsqu'un module veut réagir à l'événement ;
-- la connexion renvoyée se coupe avec `:Disconnect()`.
function Signal:Connect(fn: (...any) -> ()): Connection
	local listeners = self._listeners
	local connection = { Connected = true, fn = fn }
	-- Cette méthode permet de retirer l'abonné lorsqu'il ne doit plus être appelé (idempotent).
	function connection.Disconnect(conn)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(listeners, conn)
		if index then
			table.remove(listeners, index)
		end
	end
	table.insert(listeners, connection)
	return connection
end

-- Cette méthode permet de prévenir tous les abonnés lorsque l'événement se produit ; un abonné déconnecté pendant
-- l'appel n'est plus appelé, et une erreur d'abonné part en `warn` sans interrompre les suivants.
function Signal:Fire(...: any)
	for _, connection in table.clone(self._listeners) do
		if connection.Connected then
			local ok, err = pcall(connection.fn, ...)
			if not ok then
				warn("Signal : erreur d'un abonné : " .. tostring(err))
			end
		end
	end
end

return Signal

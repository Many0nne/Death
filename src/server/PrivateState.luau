-- Conteneur privé de chaque joueur (#49) : ScreenGui désactivé sous son PlayerGui, que Roblox ne réplique qu'à ce
-- joueur. Les services y écrivent ce qu'un autre client ne doit pas lire (état des pièges et souffle de la Mort,
-- dissipation, buée d'un mortel) ; noms et lecture côté client : Shared.TrapAttributes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrapAttributes = require(ReplicatedStorage:WaitForChild("Shared").TrapAttributes)

local PrivateState = {}

-- Cette méthode permet de trouver (ou créer) le conteneur privé d'un joueur lorsqu'un service publie un état qui lui
-- est propre ; nil tant que le joueur n'a pas de PlayerGui (encore en connexion).
function PrivateState.get(player: Player): Instance?
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return nil
	end
	local container = gui:FindFirstChild(TrapAttributes.PrivateName)
	if not container then
		local screen = Instance.new("ScreenGui")
		screen.Name = TrapAttributes.PrivateName
		-- Données seulement : rien à afficher, et rien à perdre à la réapparition du personnage
		screen.Enabled = false
		screen.ResetOnSpawn = false
		screen.Parent = gui
		container = screen
	end
	return container
end

-- Cette méthode permet d'écrire un attribut privé lorsque sa valeur change seulement (une réplication par changement,
-- pas par appel).
function PrivateState.write(container: Instance, name: string, value: any)
	if container:GetAttribute(name) ~= value then
		container:SetAttribute(name, value)
	end
end

-- Cette méthode permet de trouver (ou créer, si `create`) un dossier enfant du conteneur privé lorsqu'un service y
-- range un groupe d'attributs (état des pièges).
function PrivateState.folder(container: Instance, name: string, create: boolean): Instance?
	local folder = container:FindFirstChild(name)
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = container
	end
	return folder
end

return PrivateState

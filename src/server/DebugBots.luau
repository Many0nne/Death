-- Faux joueurs de debug (#12), Studio seulement : un bot ressemble à un Player pour Server.MatchService (UserId, Name,
-- attributs, AttributeChanged, Character) et compte comme la Mort ou comme un mortel d'une manche de test.
-- Ses attributs vivent sur son mannequin (un Model avec Humanoid) : `DebugSetState` posé sur le mannequin vise ce faux
-- mortel, comme sur un vrai joueur. Les services de jeu les voient par Server.Roster (#52) : arrivée (Added) et départ
-- (Removing, mannequin encore en place) comme PlayerAdded et PlayerRemoving.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.MatchAttributes)
local Signal = require(Shared.Signal)

local DebugBots = {}
DebugBots.__index = DebugBots

local BotMethods = {}
BotMethods.__index = BotMethods

-- Les UserId des bots sont négatifs et loin de ceux des joueurs de test de Studio : aucune collision avec un Player
local ROLE_LABELS = { Death = "Mort", Mortal = "Mortel" }
local FIRST_USER_ID = -1000000

-- Cette méthode permet de lire un attribut du bot lorsqu'un service le traite comme un Player.
function BotMethods:GetAttribute(name: string): any
	return self.Character:GetAttribute(name)
end

-- Cette méthode permet d'écrire un attribut du bot lorsqu'un service le traite comme un Player.
function BotMethods:SetAttribute(name: string, value: any)
	self.Character:SetAttribute(name, value)
end

-- Cette méthode permet de répondre comme un Player sans enfant lorsqu'un service cherche son PlayerGui (conteneur
-- privé, Server.PrivateState) : un bot n'a ni PlayerGui ni client à qui répliquer.
function BotMethods:FindFirstChildOfClass(_className: string): Instance?
	return nil
end

-- Cette méthode permet de construire le mannequin d'un bot lorsqu'il est ajouté en jeu : un Model avec Humanoid et
-- HumanoidRootPart, ancré (il ne tombe pas, PivotTo le déplace), posé dans le workspace.
function DebugBots.createMannequin(name: string): Instance
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 5, 1)
	root.Anchored = true
	root.Color = Color3.fromRGB(150, 150, 160)
	root.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.CFrame = root.CFrame * CFrame.new(0, 3.2, 0)
	head.Color = Color3.fromRGB(150, 150, 160)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = head
	head.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = name
	humanoid.RequiresNeck = false -- pas de Neck : la tête est soudée, le Humanoid ne doit pas mourir
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace
	return model
end

-- Cette méthode permet de créer le registre de bots lorsque le service de manche démarre ; `createModel(name)` fabrique
-- le mannequin (faux objet à attributs dans les tests Lune).
function DebugBots.new(createModel: (string) -> any)
	return setmetatable({
		createModel = createModel,
		bots = {} :: { any },
		counter = 0, -- UserId des bots
		perRole = {} :: { [string]: number }, -- numéro du dernier bot de chaque rôle
		Added = Signal.new(), -- bot ajouté (comme Players.PlayerAdded)
		Removing = Signal.new(), -- bot sur le départ, mannequin encore en place (comme Players.PlayerRemoving)
	}, DebugBots)
end

-- Cette méthode permet d'ajouter un faux participant lorsque DebugAddBot est posé ; `role` vaut "Death" ou "Mortal"
-- (rôle imposé par DebugRole) ; renvoie le bot.
function DebugBots:add(role: string)
	self.counter += 1
	self.perRole[role] = (self.perRole[role] or 0) + 1
	local name = string.format("Bot %s %d", ROLE_LABELS[role] or role, self.perRole[role])
	local model = self.createModel(name)
	local bot = setmetatable({
		UserId = FIRST_USER_ID - self.counter,
		Name = name,
		IsBot = true,
		Character = model,
		AttributeChanged = model.AttributeChanged,
		-- Jamais déclenché : le mannequin ne réapparaît pas (Server.DeathController s'y abonne comme pour un joueur)
		CharacterAdded = Signal.new(),
	}, BotMethods)
	model:SetAttribute(A.DebugRole, role)
	table.insert(self.bots, bot)
	self.Added:Fire(bot)
	return bot
end

-- Cette méthode permet de retirer un bot du registre et de détruire son mannequin lorsqu'il quitte la manche ; les
-- services sont prévenus avant (Removing, bot encore listé), comme au départ d'un joueur.
function DebugBots:remove(bot)
	local index = table.find(self.bots, bot)
	if index then
		self.Removing:Fire(bot)
		table.remove(self.bots, index)
		bot.Character:Destroy()
	end
end

-- Cette méthode permet de lister les bots présents lorsqu'une manche compte ses participants (copie).
function DebugBots:list(): { any }
	return table.clone(self.bots)
end

-- Cette méthode permet de retrouver un bot par son UserId lorsqu'un module de manche (apparitions) doit le placer.
function DebugBots:find(userId: number)
	for _, bot in self.bots do
		if bot.UserId == userId then
			return bot
		end
	end
	return nil
end

return DebugBots

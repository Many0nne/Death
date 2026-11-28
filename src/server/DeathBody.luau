-- Corps de la Mort (#73) : le joueur Mort ne garde pas son avatar Roblox, il revêt le modèle de la Mort
-- (ReplicatedStorage.Characters.Death, versionné dans assets/rbx/Characters, procédure : docs/assets.md) ; il retrouve
-- son avatar dès qu'il n'est plus la Mort. La décision vient de Shared.DeathRules.bodyChange, appelée par
-- Server.DeathController à chaque changement de rôle ou de personnage.
--
-- Revêtir : un clone du modèle remplace le personnage à la même place (Player.Character), avec les scripts du
-- personnage d'origine sauf Animate (Health...) : les modules qui écoutent CharacterAdded le traitent comme une réapparition
-- (Server.MatchSpawner le replace sur son point en manche). Rendre l'avatar : Player:LoadCharacterAsync() (le joueur
-- réapparaît sur le SpawnLocation de la zone d'attente).
-- Un faux joueur Mort de debug ne passe pas par ici : Server.DebugBots le crée directement dans ce modèle (#96).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DeathBody = {}

-- Attribut posé sur un personnage qui porte le corps de la Mort
DeathBody.ATTRIBUTE = "DeathBody"
-- Le corps est posé un peu au-dessus de la racine d'origine : il retombe sur ses pieds au lieu de s'enfoncer
local DROP_HEIGHT = 1
-- Script d'animation par défaut de Roblox, non repris sur le corps de la Mort
DeathBody.SKIPPED_SCRIPT = "Animate"

-- Cette méthode permet de savoir si un personnage porte déjà le corps de la Mort lorsque le rôle est réappliqué.
function DeathBody.isWorn(character: Model?): boolean
	return character ~= nil and character:GetAttribute(DeathBody.ATTRIBUTE) == true
end

-- Cette méthode permet de trouver le modèle de la Mort lorsqu'un joueur doit le revêtir (nil si la place ne l'a pas,
-- par exemple sans synchronisation Rojo des assets).
local function template(): Model?
	local characters = ReplicatedStorage:FindFirstChild("Characters")
	local model = characters and characters:FindFirstChild("Death")
	return if model and model:IsA("Model") then model else nil
end

-- Cette méthode permet de remplacer le personnage d'un joueur par le corps de la Mort lorsqu'il devient la Mort ;
-- renvoie false s'il n'y a rien à remplacer (pas de personnage, déjà revêtu, modèle absent).
function DeathBody.dress(player: Player): boolean
	local old = player.Character
	local oldRoot = old and old:FindFirstChild("HumanoidRootPart")
	local model = template()
	if not old or not oldRoot or not oldRoot:IsA("BasePart") or DeathBody.isWorn(old) or not model then
		if not model then
			warn("[Mort] ReplicatedStorage.Characters.Death introuvable : la Mort garde son avatar")
		end
		return false
	end
	local body = model:Clone()
	body.Name = player.Name
	body:SetAttribute(DeathBody.ATTRIBUTE, true)
	-- Scripts du personnage d'origine (StarterCharacterScripts : Health...), sauf Animate : les bras du spectre sont
	-- skinnés sur le rig R15 (#81), la marche et l'attente par défaut les balanceraient (la main lâcherait la pose de
	-- la faux) ; ses propres animations viendront avec #55
	for _, child in old:GetChildren() do
		if child:IsA("BaseScript") and child.Name ~= DeathBody.SKIPPED_SCRIPT then
			child:Clone().Parent = body
		end
	end
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart
	body:PivotTo(oldRoot.CFrame * root.PivotOffset + Vector3.new(0, DROP_HEIGHT, 0))
	player.Character = body
	body.Parent = workspace
	old:Destroy()
	return true
end

-- Cette méthode permet de rendre son avatar à un joueur lorsqu'il n'est plus la Mort (fin de manche, bac à sable).
function DeathBody.undress(player: Player)
	if player.Parent then
		player:LoadCharacterAsync()
	end
end

return DeathBody

-- Invites des pièges (#5, #49), communes au serveur et au client : identifiant d'un point fragile, réglages de chaque
-- invite (touches, portée, position de la bulle) et ce que permettent les invites de la Mort selon l'état du piège.
-- Les invites des mortels (examiner, désamorcer) sont créées par le serveur (Server.TrapService) ; celles de la Mort
-- (préparer ou désarmer, souffler) par son seul client (Client.DeathTrapPrompts), d'après l'état privé que le serveur
-- lui publie (Shared.TrapAttributes) : un client mortel ne voit jamais ce qu'elles permettent.
local MapTags = require(script.Parent.MapTags)
local Traps = require(script.Parent.Traps)

local State = Traps.State

local TrapPrompts = {}

-- Actions des invites : work = préparer ou désarmer (Mort), blow = souffler ou abandonner (Mort), examine et defuse
-- (mortels)
TrapPrompts.Action = table.freeze({ Work = "work", Blow = "blow", Examine = "examine", Defuse = "defuse" })
local Action = TrapPrompts.Action

-- Actions réservées à la Mort, envoyées au serveur par TrapAttributes.ActionEvent
TrapPrompts.DEATH_ACTIONS = table.freeze({ [Action.Work] = true, [Action.Blow] = true })

-- Touches des invites : préparer/désarmer et désamorcer sur F, souffler sur Q, examiner sur E (celle des invites par
-- défaut, comme rétablir le courant)
TrapPrompts.KEYS = table.freeze({
	[Action.Work] = { key = Enum.KeyCode.F, pad = Enum.KeyCode.ButtonY },
	[Action.Blow] = { key = Enum.KeyCode.Q, pad = Enum.KeyCode.ButtonR1 },
	[Action.Examine] = { key = Enum.KeyCode.E, pad = Enum.KeyCode.ButtonX },
	[Action.Defuse] = { key = Enum.KeyCode.F, pad = Enum.KeyCode.ButtonY },
})
-- Décalage vertical des bulles d'un même objet (pixels)
TrapPrompts.SPACING = 80

-- Cette méthode permet de trouver l'identifiant d'un point fragile lorsque le serveur ou le client lit la maison :
-- AnchorId du carrelage, LampId du lustre, sinon le nom du meuble.
function TrapPrompts.idOf(part: Instance): string
	local id = part:GetAttribute(MapTags.Attributes.AnchorId) or part:GetAttribute(MapTags.Attributes.LampId)
	if type(id) == "string" then
		return id
	end
	local parent = part.Parent
	return if parent and parent:IsA("Model") then parent.Name else part.Name
end

-- Cette méthode permet de savoir si un identifiant de point fragile peut nommer un attribut de l'état privé
-- (TrapAttributes.TrapStates) lorsque le serveur lit la maison : lettres et chiffres seulement, donc jamais confondu
-- avec `<id>` .. StepSuffix, qui contient un « _ ».
function TrapPrompts.isValidId(id: string): boolean
	return string.match(id, "^%a%w*$") ~= nil and #id <= 90
end

-- Cette méthode permet de donner les propriétés de départ d'une invite lorsqu'elle est créée : textes, touches, portée,
-- maintien et place de la bulle (au-dessus pour préparer et examiner, en dessous pour souffler et désamorcer).
function TrapPrompts.props(kind: string, action: string): { [string]: any }
	local spec = Traps.KINDS[kind]
	-- Le lustre porte déjà l'invite « Griller l'ampoule » au centre : bulles des pièges écartées d'une bulle entière
	local gap = if kind == MapTags.TrapKinds.Chandelier then TrapPrompts.SPACING else TrapPrompts.SPACING / 2
	local keys = TrapPrompts.KEYS[action]
	local props: { [string]: any } = {
		ObjectText = spec.label,
		KeyboardKeyCode = keys.key,
		GamepadKeyCode = keys.pad,
		MaxActivationDistance = Traps.INTERACT_DISTANCE,
		UIOffset = Vector2.new(0, if action == Action.Work or action == Action.Examine then -gap else gap),
	}
	if action == Action.Work then
		props.ActionText = "Préparer"
		props.HoldDuration = spec.steps[1]
	elseif action == Action.Blow then
		props.ActionText = "Souffler"
		props.HoldDuration = 0
		props.MaxActivationDistance = Traps.BREATH_DISTANCE
	elseif action == Action.Examine then
		props.ActionText = "Examiner"
		props.HoldDuration = Traps.EXAMINE_HOLD
	else
		props.ActionText = "Désamorcer"
		props.HoldDuration = spec.defuse
	end
	return props
end

export type View = { text: string, hold: number, available: boolean }

-- Cette méthode permet de dire ce que permet une invite de la Mort lorsque l'état du piège (`state`, `step` étapes
-- faites) ou le souffle (`charges`) change : texte, maintien et disponibilité. Le serveur contrôle avec le même calcul.
function TrapPrompts.deathView(kind: string, action: string, state: string, step: number, charges: number): View
	local steps = Traps.KINDS[kind].steps
	if action == Action.Work then
		if state == State.Idle or state == State.Preparing then
			local text = if #steps > 1 then string.format("Préparer (%d/%d)", step + 1, #steps) else "Préparer"
			return { text = text, hold = steps[step + 1] or steps[1], available = true }
		elseif state == State.Armed then
			return { text = "Désarmer", hold = Traps.DISARM_HOLD, available = true }
		end
		return { text = "Préparer", hold = steps[1], available = false }
	end
	-- Grand piège commencé : la touche du souffle sert à l'abandonner (sa place dans la limite est rendue)
	if state == State.Preparing then
		return { text = "Abandonner", hold = Traps.DISARM_HOLD, available = true }
	end
	return { text = "Souffler", hold = 0, available = state == State.Armed and charges > 0 }
end

return TrapPrompts

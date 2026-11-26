-- Règles pures des pièges et du souffle de la Mort (docs/design.md « Pièges », « Indices », « Contre-jeu ») : réglages
-- par taille, états d'un point fragile, limite de pièges en cours, charges de souffle et leur recharge, zones touchées
-- par un accident et rayon de la buée. Sans Instance Roblox (testable sous Lune) ; le temps est passé par l'appelant
-- (`now`, en secondes). Le serveur (Server.TrapService) applique ces règles aux objets de la maison.
local GameConfig = require(script.Parent.GameConfig)

local Traps = {}
Traps.__index = Traps

-- Conversion des mètres du document de conception : 1 stud = 0,28 m (convention Roblox)
Traps.STUDS_PER_METER = 1 / 0.28

-- États d'un point fragile. Preparing : préparation commencée (grand piège : première étape faite) ; Spent : piège
-- déclenché, l'objet est tombé, plus rien à préparer jusqu'à la manche suivante.
Traps.State = table.freeze({ Idle = "Idle", Preparing = "Preparing", Armed = "Armed", Spent = "Spent" })
local State = Traps.State

Traps.Size = table.freeze({ Small = "Small", Medium = "Medium", Large = "Large" })

-- Réglages par type (clés = MapTags.TrapKinds). Préparation : une durée de maintien par étape (grand : 10 s en
-- 2 étapes) ; désamorçage par un mortel : 4 à 8 s selon la taille ; zone touchée : rayon horizontal autour du point
-- au sol du piège (étagère : seulement devant elle, du côté où elle tombe).
Traps.KINDS = table.freeze({
	WetFloor = table.freeze({
		label = "Carrelage",
		size = Traps.Size.Small,
		steps = table.freeze({ 2.5 }),
		defuse = 4,
		hitRadius = 3,
	}),
	Shelf = table.freeze({
		label = "Étagère",
		size = Traps.Size.Medium,
		steps = table.freeze({ 5.5 }),
		defuse = 6,
		hitRadius = 6,
		frontOnly = true,
	}),
	Chandelier = table.freeze({
		label = "Lustre",
		size = Traps.Size.Large,
		steps = table.freeze({ 5, 5 }),
		defuse = 8,
		hitRadius = 8,
	}),
})

-- Réglages de départ, à ajuster en test
Traps.EXAMINE_HOLD = 1
-- La Mort désarme un de ses pièges pour le replacer ailleurs
Traps.DISARM_HOLD = 1
-- Recharge d'une charge de souffle (secondes), une charge à la fois
Traps.BREATH_RECHARGE = 45
-- Portée des invites : préparer, désarmer, examiner, désamorcer (studs, depuis le centre de l'objet) ; souffle
Traps.INTERACT_DISTANCE = 10
Traps.BREATH_DISTANCE = 24
-- Buée et frisson : à environ 3 m d'un piège armé
Traps.CHILL_RADIUS = math.floor(3 * Traps.STUDS_PER_METER + 0.5)
-- Hauteur d'un personnage au-dessus du sol d'un piège pour qu'il compte comme sur le même niveau (zone touchée, buée)
Traps.LEVEL_HEIGHT = 8
-- Indice visuel d'un piège armé : un bref signe toutes les 8 à 10 s
Traps.CUE_MIN = 8
Traps.CUE_MAX = 10

export type Timing = { maxActive: number, breathCharges: number, breathRecharge: number }

export type Trap = { id: string, kind: string, state: string, step: number }

-- Cette méthode permet de créer l'état des pièges d'une maison lorsque le serveur démarre ou qu'un test les isole ;
-- `kinds` associe chaque point fragile à son type, `timing` remplace les réglages de GameConfig et de Traps.
function Traps.new(kinds: { [string]: string }, timing: Timing?)
	local traps = {}
	for id, kind in kinds do
		if not Traps.KINDS[kind] then
			error("Traps : type de piège inconnu " .. tostring(kind) .. " pour " .. id)
		end
		traps[id] = { id = id, kind = kind, state = State.Idle, step = 0 }
	end
	local t = timing
		or {
			maxActive = GameConfig.MAX_ARMED_TRAPS,
			breathCharges = GameConfig.BREATH_CHARGES,
			breathRecharge = Traps.BREATH_RECHARGE,
		}
	return setmetatable({
		traps = traps,
		timing = t,
		charges = t.breathCharges,
		-- Fin de la recharge en cours (nil quand toutes les charges sont là)
		rechargeAt = nil :: number?,
	}, Traps)
end

-- Lecture --------------------------------------------------------------------------------------------------------

-- Cette méthode permet de lire un point fragile lorsque le serveur affiche ses invites ou applique une action.
function Traps:get(id: string): Trap?
	return self.traps[id]
end

-- Cette méthode permet de donner la durée de l'étape de préparation suivante d'un piège lorsque l'invite de la Mort
-- est mise à jour (nil si rien n'est à préparer).
function Traps:nextStepDuration(id: string): number?
	local trap = self.traps[id]
	if not trap or (trap.state ~= State.Idle and trap.state ~= State.Preparing) then
		return nil
	end
	return Traps.KINDS[trap.kind].steps[trap.step + 1]
end

-- Cette méthode permet de compter les pièges en cours (armés ou en préparation) lorsque l'on applique la limite
-- MAX_ARMED_TRAPS : un grand piège à moitié préparé garde sa place.
function Traps:activeCount(): number
	local n = 0
	for _, trap in self.traps do
		if trap.state == State.Armed or trap.state == State.Preparing then
			n += 1
		end
	end
	return n
end

-- Cette méthode permet de compter les pièges armés (prêts à être déclenchés) lorsque le serveur publie l'attribut lu
-- par le HUD.
function Traps:armedCount(): number
	local n = 0
	for _, trap in self.traps do
		if trap.state == State.Armed then
			n += 1
		end
	end
	return n
end

-- Cette méthode permet de lister les pièges armés lorsque le serveur cherche les mortels proches (buée) ou joue les
-- indices visuels.
function Traps:armed(): { string }
	local list = {}
	for id, trap in self.traps do
		if trap.state == State.Armed then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

-- Cette méthode permet de savoir ce qu'un mortel découvre en examinant un objet lorsqu'il le maintient 1 s : vrai si
-- la Mort l'a trafiqué (armé ou préparation commencée).
function Traps:isTampered(id: string): boolean
	local trap = self.traps[id]
	return trap ~= nil and (trap.state == State.Armed or trap.state == State.Preparing)
end

-- Préparation par la Mort ------------------------------------------------------------------------------------------

-- Cette méthode permet de savoir si la Mort peut préparer un point fragile lorsqu'elle commence à maintenir l'invite ;
-- renvoie aussi la raison d'un refus.
function Traps:canPrepare(id: string): (boolean, string?)
	local trap = self.traps[id]
	if not trap then
		return false, "point fragile inconnu " .. tostring(id)
	elseif trap.state == State.Armed then
		return false, "piège déjà armé"
	elseif trap.state == State.Spent then
		return false, "piège déjà déclenché"
	elseif trap.state == State.Idle and self:activeCount() >= self.timing.maxActive then
		return false, string.format("%d pièges déjà en place : désarmes-en un", self.timing.maxActive)
	end
	return true
end

-- Cette méthode permet de faire une étape de préparation lorsque la Mort a maintenu l'invite le temps voulu ; le piège
-- est armé à la dernière étape. Renvoie (true, nil, état) ou (false, raison).
function Traps:prepare(id: string): (boolean, string?, string?)
	local ok, err = self:canPrepare(id)
	if not ok then
		return false, err
	end
	local trap = self.traps[id]
	trap.step += 1
	trap.state = if trap.step >= #Traps.KINDS[trap.kind].steps then State.Armed else State.Preparing
	return true, nil, trap.state
end

-- Cette méthode permet à la Mort de désarmer un de ses pièges (armé ou en préparation) lorsqu'elle veut le replacer
-- ailleurs ; renvoie (true) ou (false, raison).
function Traps:disarm(id: string): (boolean, string?)
	local trap = self.traps[id]
	if not trap or (trap.state ~= State.Armed and trap.state ~= State.Preparing) then
		return false, "rien à désarmer"
	end
	trap.state = State.Idle
	trap.step = 0
	return true
end

-- Cette méthode permet à un mortel de désamorcer un objet lorsqu'il a tenu le temps voulu : un piège trafiqué redevient
-- inoffensif (la Mort récupère sa place). Renvoie (true) si un piège a été désamorcé, (false, raison) sinon.
function Traps:defuse(id: string): (boolean, string?)
	if not self:isTampered(id) then
		return false, "rien à désamorcer"
	end
	return self:disarm(id)
end

-- Souffle -------------------------------------------------------------------------------------------------------

-- Cette méthode permet de faire avancer la recharge du souffle jusqu'à `now` lorsque l'on lit ou dépense les charges :
-- une charge toutes les breathRecharge secondes, jusqu'au maximum.
function Traps:_recharge(now: number)
	while self.rechargeAt and now >= self.rechargeAt do
		self.charges += 1
		if self.charges >= self.timing.breathCharges then
			self.charges = self.timing.breathCharges
			self.rechargeAt = nil
		else
			self.rechargeAt += self.timing.breathRecharge
		end
	end
end

-- Cette méthode permet de lire les charges de souffle à l'instant `now` lorsque le serveur les publie ; renvoie aussi
-- la fin de la recharge en cours (nil si le souffle est plein).
function Traps:breath(now: number): (number, number?)
	self:_recharge(now)
	return self.charges, self.rechargeAt
end

-- Cette méthode permet de retirer une charge de souffle lorsqu'elle est dépensée ou perdue (dissipation par la lampe
-- torche, #8) ; la recharge démarre si elle ne tournait pas. Renvoie (true) ou (false, raison).
function Traps:spendCharge(now: number): (boolean, string?)
	self:_recharge(now)
	if self.charges <= 0 then
		return false, "plus de souffle"
	end
	self.charges -= 1
	if not self.rechargeAt then
		self.rechargeAt = now + self.timing.breathRecharge
	end
	return true
end

-- Cette méthode permet de remplir le souffle lorsque la Mort récolte une âme (docs/design.md « Âmes »).
function Traps:refillBreath()
	self.charges = self.timing.breathCharges
	self.rechargeAt = nil
end

-- Cette méthode permet de savoir si la Mort peut souffler sur un piège lorsqu'elle le vise : il doit être armé et une
-- charge disponible ; renvoie aussi la raison d'un refus.
function Traps:canBlow(id: string, now: number): (boolean, string?)
	local trap = self.traps[id]
	if not trap or trap.state ~= State.Armed then
		return false, "aucun piège armé ici"
	end
	self:_recharge(now)
	if self.charges <= 0 then
		return false, "plus de souffle"
	end
	return true
end

-- Cette méthode permet de déclencher un piège armé par le souffle lorsque la Mort le décide ; renvoie (true) ou
-- (false, raison).
function Traps:blow(id: string, now: number): (boolean, string?)
	local ok, err = self:canBlow(id, now)
	if not ok then
		return false, err
	end
	self:spendCharge(now)
	self.traps[id].state = State.Spent
	return true
end

-- Cette méthode permet de tout remettre à zéro (pièges inoffensifs, souffle plein) lorsqu'une manche commence ou se
-- termine.
function Traps:reset()
	for _, trap in self.traps do
		trap.state = State.Idle
		trap.step = 0
	end
	self:refillBreath()
end

-- Géométrie ------------------------------------------------------------------------------------------------------

-- Cette méthode permet de savoir si un personnage (centre `root`) est sur le même niveau qu'un piège dont le sol est à
-- `floor` lorsque l'on cherche les victimes ou la buée : un étage au-dessus ou la cave en dessous ne comptent pas.
function Traps.sameLevel(floor: Vector3, root: Vector3): boolean
	local dy = root.Y - floor.Y
	return dy >= -1 and dy <= Traps.LEVEL_HEIGHT
end

-- Cette méthode permet de savoir si un accident touche un personnage lorsque le piège se déclenche : rayon au sol, même
-- niveau ; l'étagère (`front` sa chute, `box` sa taille) touche la bande où elle s'abat, un stud de marge autour.
function Traps.hits(kind: string, floor: Vector3, root: Vector3, front: Vector3?, box: Vector3?): boolean
	local spec = Traps.KINDS[kind]
	if not spec or not Traps.sameLevel(floor, root) then
		return false
	end
	local flat = Vector3.new(root.X - floor.X, 0, root.Z - floor.Z)
	if spec.frontOnly and front and box then
		local ahead = Vector3.new(front.X, 0, front.Z).Unit
		local side = Vector3.new(-ahead.Z, 0, ahead.X)
		local depth = if math.abs(ahead.X) > 0.5 then box.X else box.Z
		local width = if math.abs(ahead.X) > 0.5 then box.Z else box.X
		local forward = flat:Dot(ahead)
		return forward >= -1 and forward <= depth / 2 + box.Y + 1 and math.abs(flat:Dot(side)) <= width / 2 + 1
	end
	if flat.Magnitude > spec.hitRadius then
		return false
	end
	if spec.frontOnly and front then
		-- Une marge d'un stud derrière l'avant du meuble : on peut être collé contre son flanc
		return flat:Dot(Vector3.new(front.X, 0, front.Z).Unit) >= -1
	end
	return true
end

-- Cette méthode permet de savoir si un personnage est dans la pièce d'un piège (volume `center`, `size`, marge des seuils
-- comme Shared.Illumination) lorsque l'on cherche victimes ou buée : rien ne passe à travers un mur.
function Traps.inZone(center: Vector3, size: Vector3, root: Vector3): boolean
	local half = size / 2 + Vector3.new(0.5, 0.5, 0.5)
	local d = root - center
	return math.abs(d.X) <= half.X and math.abs(d.Y) <= half.Y and math.abs(d.Z) <= half.Z
end

-- Cette méthode permet de savoir si un mortel sent la présence d'un piège armé (buée, frisson) lorsque le serveur
-- teste les distances : environ 3 m à l'horizontale, même niveau.
function Traps.chills(floor: Vector3, root: Vector3): boolean
	local flat = Vector3.new(root.X - floor.X, 0, root.Z - floor.Z)
	return flat.Magnitude <= Traps.CHILL_RADIUS and Traps.sameLevel(floor, root)
end

return Traps

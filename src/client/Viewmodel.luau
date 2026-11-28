-- Montage d'un viewmodel (#74) : un modèle local collé à la caméra, visible du seul joueur local, découpé en groupes
-- qui suivent chacun une pose (espace caméra, Shared.ViewmodelMotion). Générique : la Mort y monte ses mains et sa
-- faux (Client.DeathViewmodel), la lampe torche des mortels (#67) y montera la sienne.
-- Un groupe mène des pièces (posées une à une, ancrées et inertes : ni collision, ni rayon, ni contact, ni ombre
-- portée) et des os (Bone.Transform, comme l'Animator). Un maillage skinné se pose par ses os : sa pièce et les pièces
-- qui portent ses os restent ensemble dans un même groupe, sinon le maillage se décale (constaté en jeu : la main
-- droite quittait le manche quand la gauche bougeait).
local ViewmodelMotion =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ViewmodelMotion"))

local Viewmodel = {}
Viewmodel.__index = Viewmodel

export type Group = {
	anchor: CFrame, -- repère de l'ancre au repos (modèle d'origine) : la pose du groupe le mène
	parts: { BasePart }?,
	-- os rangés directement sous une pièce d'un groupe (leurs enfants suivent) : leur repère au repos est mené par la
	-- pose du groupe, quel que soit le groupe de leur pièce
	bones: { Bone }?,
}

-- Cette méthode permet de retirer d'un modèle ce qui n'a pas sa place dans un viewmodel lorsqu'il est monté :
-- Humanoid (son Animator remettrait les os à zéro), scripts, soudures et articulations (les pièces sont placées une
-- à une), sons.
local function strip(model: Model)
	for _, d in model:GetDescendants() do
		if
			d:IsA("Humanoid")
			or d:IsA("BaseScript")
			or d:IsA("JointInstance")
			or d:IsA("WeldConstraint")
			or d:IsA("NoCollisionConstraint")
			or d:IsA("Sound")
		then
			d:Destroy()
		end
	end
end

-- Cette méthode permet de monter un viewmodel lorsque son modèle est prêt (un clone dédié, qu'il garde) : pièces et
-- os relevés au repos, pièces rendues inertes, voile (Highlight) posé, rien d'affiché avant `show`.
function Viewmodel.new(model: Model, groups: { [string]: Group })
	strip(model)
	local self = setmetatable({}, Viewmodel)
	self.model = model
	self.parts = {} :: { BasePart }
	self.entries = {} :: { { group: string, anchor: CFrame, rest: CFrame } }
	self.index = {} :: { [BasePart]: number }
	self.bones = {} :: { { bone: Bone, group: string, anchor: CFrame, rest: CFrame, parent: BasePart } }
	-- transparence d'origine des pièces dessinées (les pièces du rig, invisibles, le restent)
	self.base = {} :: { [BasePart]: number }
	for name, group in groups do
		for _, part in group.parts or {} do
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Massless = true
			table.insert(self.parts, part)
			table.insert(self.entries, { group = name, anchor = group.anchor, rest = part.CFrame })
			self.index[part] = #self.parts
			if part.Transparency < 1 then
				self.base[part] = part.Transparency
			end
		end
	end
	for name, group in groups do
		for _, bone in group.bones or {} do
			local parent = bone.Parent
			if parent and parent:IsA("BasePart") and self.index[parent] then
				bone.Transform = CFrame.identity
				table.insert(self.bones, {
					bone = bone,
					group = name,
					anchor = group.anchor,
					rest = parent.CFrame * bone.CFrame,
					parent = parent,
				})
			end
		end
	end
	self.frames = table.create(#self.parts)
	local highlight = Instance.new("Highlight")
	highlight.Name = "ViewmodelVeil"
	highlight.FillColor = Color3.new(0, 0, 0)
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Adornee = model
	highlight.Parent = model
	self.highlight = highlight
	self.shown = false
	return self
end

-- Cette méthode permet d'afficher ou de cacher le viewmodel lorsque le joueur entre dans l'état qui le montre ou en
-- sort (le modèle quitte le monde quand il est caché : rien n'est dessiné ni déplacé).
function Viewmodel:show(visible: boolean)
	if self.shown == visible then
		return
	end
	self.shown = visible
	self.model.Parent = if visible then workspace.CurrentCamera else nil
end

-- Cette méthode permet de placer pièces et os lorsque l'image est rendue : chaque groupe suit sa pose (espace
-- caméra) ; un groupe sans pose garde la dernière.
function Viewmodel:render(camera: CFrame, poses: { [string]: CFrame })
	if not self.shown then
		return
	end
	for k, entry in self.entries do
		local pose = poses[entry.group]
		if pose then
			self.frames[k] = ViewmodelMotion.partFrame(camera, pose, entry.anchor, entry.rest)
		elseif not self.frames[k] then
			self.frames[k] = self.parts[k].CFrame
		end
	end
	workspace:BulkMoveTo(self.parts, self.frames, Enum.BulkMoveMode.FireCFrameChanged)
	for _, b in self.bones do
		local pose = poses[b.group]
		if pose then
			local wanted = ViewmodelMotion.partFrame(camera, pose, b.anchor, b.rest)
			b.bone.Transform = ViewmodelMotion.boneTransform(self.frames[self.index[b.parent]], b.bone.CFrame, wanted)
		end
	end
end

-- Cette méthode permet de régler l'aspect du viewmodel lorsque la lumière change : transparence ajoutée aux pièces
-- dessinées et transparence du voile noir (1 : pas de voile).
function Viewmodel:setLook(transparency: number, fill: number)
	if self.look == transparency * 1000 + fill then
		return
	end
	self.look = transparency * 1000 + fill
	for part, base in self.base do
		part.Transparency = base + (1 - base) * transparency
	end
	self.highlight.Enabled = fill < 1
	self.highlight.FillTransparency = fill
end

-- Cette méthode permet de détruire le viewmodel lorsqu'il ne servira plus (fin de rôle, client arrêté).
function Viewmodel:destroy()
	self.model:Destroy()
end

return Viewmodel

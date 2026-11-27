-- Cape vivante de la Mort (#76) : chaque frame, les os de la cape (Bone « Cxx_y » sous la racine du corps de la Mort,
-- Server.DeathBody) prennent la rotation de Shared.CloakMotion : ondulation au repos, traîne quand la Mort glisse.
-- Purement visuel et local : le serveur ne voit pas ces rotations. Rien n'est calculé pour une Mort lointaine ou
-- invisible pour ce joueur (Client.DeathView pose la transparence locale de son corps).
-- Écrit en PreSimulation : l'Animator du Humanoid remet Bone.Transform à zéro à chaque étape d'animation (mesuré :
-- une rotation posée avant PreAnimation est effacée avant PreSimulation), une écriture plus tôt serait perdue.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CloakMotion = require(Shared:WaitForChild("CloakMotion"))

-- Attribut posé par Server.DeathBody sur le corps de la Mort
local BODY_ATTRIBUTE = "DeathBody"
-- Au-delà de cette distance de la caméra (studs), la cape ne s'anime plus
local MAX_DISTANCE = 150

local CloakAnimator = {}

type BoneState = { bone: Bone, chain: number, index: number, rest: CFrame, restInverse: CFrame }
type CloakState = { root: BasePart, cloak: BasePart, bones: { BoneState } }

-- Cette méthode permet de relever les os de la cape d'un corps et leur orientation de repos (repère de la racine)
-- lorsqu'un corps de la Mort apparaît ; nil tant que la racine, la robe ou tous ses os ne sont pas arrivés (le
-- client réessaie à la frame suivante).
local function collect(character: Model): CloakState?
	local root = character:FindFirstChild("HumanoidRootPart")
	local veil = character:FindFirstChild("Veil")
	local cloak = veil and veil:FindFirstChild("Cloak")
	if not root or not root:IsA("BasePart") or not cloak or not cloak:IsA("BasePart") then
		return nil
	end
	-- deux passes : toutes les rotations à zéro avant de lire les repères de repos (un parent tourné fausserait l'enfant)
	local found = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Bone") then
			d.Transform = CFrame.identity
			local chain, index = CloakMotion.parseBone(d.Name)
			if chain and index then
				table.insert(found, { bone = d, chain = chain, index = index })
			end
		end
	end
	if #found < CloakMotion.CHAINS * CloakMotion.BONES then
		return nil
	end
	local bones = {}
	for _, f in found do
		local rest = root.CFrame:ToObjectSpace(f.bone.WorldCFrame).Rotation
		table.insert(
			bones,
			{ bone = f.bone, chain = f.chain, index = f.index, rest = rest, restInverse = rest:Inverse() }
		)
	end
	return { root = root, cloak = cloak, bones = bones }
end

-- Cette méthode permet de démarrer l'animation des capes lorsque le client se lance.
function CloakAnimator.start()
	local states: { [Model]: CloakState } = {}
	local clock = 0

	RunService.PreSimulation:Connect(function(dt)
		clock += dt
		local camera = workspace.CurrentCamera
		local seen = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character and character:GetAttribute(BODY_ATTRIBUTE) == true then
				seen[character] = true
				local state = states[character] or collect(character)
				states[character] = state
				if state then
					local far = camera and (camera.CFrame.Position - state.root.Position).Magnitude > MAX_DISTANCE
					local hidden = state.cloak.LocalTransparencyModifier >= 1
					if not far and not hidden then
						local velocity = state.root.CFrame:VectorToObjectSpace(state.root.AssemblyLinearVelocity)
						for _, b in state.bones do
							local rotation = CloakMotion.boneRotation(clock, b.chain, b.index, velocity)
							b.bone.Transform = b.restInverse * rotation * b.rest
						end
					end
				end
			end
		end
		for character in states do
			if not seen[character] then
				states[character] = nil
			end
		end
	end)
end

return CloakAnimator

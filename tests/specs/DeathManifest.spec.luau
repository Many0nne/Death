-- Manifeste du modèle de la Mort (#79) : les noms que le code cherche dans le modèle, les os de la cape et les budgets
-- de triangles. La CI n'a pas Blender : on relit le manifeste (tools/models/death.manifest.json) et les mesures que
-- tools/blender/pipeline.py y a écrites (death.measured.json), comparés au code (Client.CloakAnimator,
-- Server.DeathBody, Client.DeathView, Shared.CloakMotion). Le .rbxm versionné est lu directement (Lune >= 0.11, #87).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

return function(T, Loader)
	local loader = Loader.new()
	local CloakMotion = loader:require("src/shared/CloakMotion")
	local manifest = serde.decode("json", fs.readFile("tools/models/death.manifest.json"))
	local measured = serde.decode("json", fs.readFile("tools/models/death.measured.json"))

	-- Cette méthode permet de lister les noms connus du modèle (pièces, groupes, pièces ajoutées dans Studio, noms du
	-- rig et des conteneurs) lorsqu'on vérifie ce que le code y cherche.
	local function knownNames(): { [string]: boolean }
		local names = {}
		for _, name in manifest.codeNames do
			names[name] = true
		end
		for name, part in manifest.parts do
			names[name] = true
			names[part.group] = true
		end
		for name, part in manifest.studio.extraParts do
			names[name] = true
			names[part.group] = true
		end
		for name in manifest.studio.emitters do
			names[name] = true
		end
		return names
	end

	-- Cette méthode permet de relever les noms cherchés par un script (FindFirstChild / WaitForChild avec un littéral
	-- entre guillemets simples ou doubles, second argument éventuel).
	local function lookedUp(path: string): { string }
		local out = {}
		local source = fs.readFile(path)
		for _, method in { "FindFirstChild", "WaitForChild" } do
			for _, quote in { '"', "'" } do
				for name in string.gmatch(source, ":" .. method .. "%(" .. quote .. "([^" .. quote .. "]+)" .. quote) do
					table.insert(out, name)
				end
			end
		end
		return out
	end

	T.describe("Manifeste de la Mort : noms attendus par le code", function()
		T.it("chaque nom cherché par CloakAnimator, DeathBody et DeathView existe dans le manifeste", function()
			local known = knownNames()
			for _, path in { "src/client/CloakAnimator.luau", "src/server/DeathBody.luau", "src/client/DeathView.luau" } do
				for _, name in lookedUp(path) do
					-- les modules partagés (ReplicatedStorage.Shared.X) ne désignent pas le modèle
					local isModule = name == "Shared" or fs.isFile("src/shared/" .. name .. ".luau")
					T.expect(isModule or known[name], path .. " cherche « " .. name .. " », absent du manifeste")
				end
			end
		end)

		T.it("la cape skinnée est la pièce Cloak du groupe Veil (Client.CloakAnimator)", function()
			T.expectEqual(manifest.bones.skin, "Cloak")
			T.expectEqual(manifest.parts.Cloak.group, "Veil")
			T.expect(manifest.parts.Cloak.skinned, "Cloak doit être marquée skinned")
		end)

		T.it("les os de la cape sont ceux que lit Shared.CloakMotion", function()
			T.expectEqual(manifest.bones.chains, CloakMotion.CHAINS)
			T.expectEqual(manifest.bones.perChain, CloakMotion.BONES)
			local bones = measured.bones
			T.expectEqual(#bones, 1 + CloakMotion.CHAINS * CloakMotion.BONES, "nombre d'os mesuré")
			local seen = {}
			for _, name in bones do
				local chain, index = CloakMotion.parseBone(name)
				if chain then
					T.expect(chain < CloakMotion.CHAINS and index < CloakMotion.BONES, "os hors limites : " .. name)
					seen[name] = true
				else
					T.expectEqual(name, manifest.bones.root, "os inattendu")
				end
			end
			for c = 0, CloakMotion.CHAINS - 1 do
				for b = 0, CloakMotion.BONES - 1 do
					local name = string.format("C%02d_%d", c, b)
					T.expect(seen[name], "os manquant : " .. name)
				end
			end
		end)
	end)

	T.describe("Manifeste de la Mort : budgets de triangles (mesurés par pipeline.py)", function()
		T.it("chaque pièce du manifeste est mesurée, sans pièce en trop", function()
			for name in manifest.parts do
				T.expect(measured.parts[name], "pièce non mesurée : " .. name)
			end
			for name in measured.parts do
				T.expect(manifest.parts[name], "pièce mesurée hors manifeste : " .. name)
			end
		end)

		T.it("chaque pièce tient dans son budget, lui-même sous la limite par pièce (12 000)", function()
			T.expect(manifest.budget.partTris <= 12000, "limite par pièce au-dessus de 12 000")
			local total = 0
			for name, part in measured.parts do
				local spec = manifest.parts[name]
				local cap = math.min(spec and spec.maxTris or manifest.budget.partTris, manifest.budget.partTris)
				T.expect(part.tris <= cap, string.format("%s : %d triangles > %d", name, part.tris, cap))
				total += part.tris
			end
			T.expectEqual(total, measured.totalTris, "total mesuré incohérent")
			T.expect(
				total <= manifest.budget.totalTris,
				string.format("total %d > %d", total, manifest.budget.totalTris)
			)
		end)

		T.it(
			"le drapé de la cape garde la grille (sommets attendus d'après la grille trouée, poids recalculés)",
			function()
				T.expect(measured.drape and measured.drape.frames > 0, "cape mesurée sans drapé")
				T.expect(
					measured.cloakGridVertices and measured.cloakGridVertices > 0,
					"grille de la cape non mesurée"
				)
				T.expectEqual(measured.drape.vertices, measured.cloakGridVertices)
			end
		)
	end)

	T.describe("Manifeste de la Mort : bras skinnés sur le rig R15 (#81)", function()
		local body = manifest.bones.body

		T.it("les pièces skinnées sur le corps sont marquées skinned", function()
			for _, name in body.skinned do
				T.expect(manifest.parts[name], "pièce skinnée absente du manifeste : " .. name)
				T.expect(manifest.parts[name].skinned, name .. " doit être marquée skinned")
			end
		end)

		T.it("chaque os rangé sur le rig et chaque articulation existent dans les mesures", function()
			local names = {}
			for _, n in measured.bodyBoneNames do
				names[n] = true
			end
			T.expect(names[body.root], "racine du corps non mesurée : " .. body.root)
			for bone in body.attach do
				T.expect(names[bone], "os rangé non mesuré : " .. bone)
			end
			for _, j in body.joints do
				local bone = measured.bodyBones[j[2]]
				T.expect(bone and #bone.head == 3 and #bone.tail == 3, "articulation " .. j[1] .. " : os " .. j[2])
			end
		end)

		T.it("aucun os du corps ne porte le nom d'un os de la robe", function()
			local cloak = {}
			for _, n in measured.bones do
				cloak[n] = true
			end
			for _, n in measured.bodyBoneNames do
				T.expect(not cloak[n], "os en double entre robe et corps : " .. n)
			end
		end)

		T.it("les noms de morceaux cherchés par DeathView (constantes *_NAME) existent dans le manifeste", function()
			local known = knownNames()
			local source = fs.readFile("src/client/DeathView.luau")
			local count = 0
			for name in string.gmatch(source, 'local %u+_NAME = "([^"]+)"') do
				T.expect(known[name], "DeathView cherche « " .. name .. " », absent du manifeste")
				count += 1
			end
			T.expect(count >= 2, "constantes SCYTHE_NAME / SHROUD_NAME introuvables dans DeathView")
		end)
	end)

	T.describe("Modèle versionné de la Mort (Death.rbxm) contre le manifeste (#87)", function()
		local model = roblox.deserializeModel(fs.readFile("assets/rbx/Characters/Death.rbxm"))[1]
		local weldTo = manifest.studio.weldTo

		-- Cette méthode permet de lister les pièces que le manifeste attend dans le modèle (pièces Blender et pièces
		-- ajoutées dans Studio) lorsqu'on les compare au .rbxm.
		local function expectedParts(): { [string]: { group: string, castShadow: boolean? } }
			local out = {}
			for name, part in manifest.parts do
				out[name] = part
			end
			for name, part in manifest.studio.extraParts do
				out[name] = part
			end
			return out
		end

		-- Cette méthode permet de retrouver une pièce dans son groupe lorsque le groupe porte le même nom qu'elle
		-- (Tatters/Tatters : une recherche récursive sur le nom renverrait le groupe).
		local function findPart(name: string, spec: { group: string }): Instance?
			local group = model:FindFirstChild(spec.group)
			return group and group:FindFirstChild(name)
		end

		T.it("le .rbxm est le modèle de la Mort, avec Humanoid et HumanoidRootPart", function()
			T.expectEqual(model.Name, manifest.model)
			T.expect(model:FindFirstChildOfClass("Humanoid"), "Humanoid manquant")
			T.expect(model:FindFirstChild("HumanoidRootPart"), "HumanoidRootPart manquant")
		end)

		T.it(
			"chaque pièce du manifeste est une pièce de son groupe, sans pièce en trop ni pièce retirée",
			function()
				local parts = expectedParts()
				for name, spec in parts do
					local part = findPart(name, spec)
					T.expect(part and part:IsA("BasePart"), "pièce absente de son groupe dans le .rbxm : " .. name)
				end
				for _, group in model:GetChildren() do
					if group:IsA("Model") then
						for _, part in group:GetChildren() do
							T.expect(
								parts[part.Name],
								"pièce du .rbxm hors manifeste : " .. group.Name .. "." .. part.Name
							)
						end
					end
				end
				for _, name in manifest.studio.remove do
					T.expect(not model:FindFirstChild(name, true), "pièce retirée toujours présente : " .. name)
				end
			end
		)

		T.it("une seule soudure par pièce, vers HumanoidRootPart (ou la main pour le groupe de la faux)", function()
			for name, spec in expectedParts() do
				local part = findPart(name, spec)
				if not part then
					continue -- déjà signalée par le test précédent
				end
				local welds = {}
				for _, child in part:GetChildren() do
					if child:IsA("WeldConstraint") then
						table.insert(welds, child)
					end
				end
				T.expectEqual(#welds, 1, name .. " : nombre de soudures")
				local target = manifest.studio.groupWeld[spec.group] or weldTo
				T.expectEqual(welds[1] and welds[1].Part0 and welds[1].Part0.Name, target, name .. " : Part0")
				T.expect(welds[1] and welds[1].Part1 == part, name .. " : Part1 doit être la pièce")
			end
		end)

		T.it("castShadow du manifeste respecté par chaque pièce (CastShadow)", function()
			for name, spec in expectedParts() do
				local part = findPart(name, spec)
				if part then
					T.expectEqual(part.CastShadow, spec.castShadow == true, name .. " : CastShadow")
				end
			end
		end)

		T.it("les os de la robe sous Root sont ceux mesurés par pipeline.py (65)", function()
			local root = model.HumanoidRootPart:FindFirstChild(manifest.bones.root)
			T.expect(root and root:IsA("Bone"), "os racine absent sous HumanoidRootPart : " .. manifest.bones.root)
			local seen, count = { [root.Name] = true }, 1
			for _, bone in root:GetDescendants() do
				if bone:IsA("Bone") then
					T.expect(not seen[bone.Name], "os en double : " .. bone.Name)
					seen[bone.Name] = true
					count += 1
				end
			end
			T.expectEqual(count, #measured.bones, "nombre d'os sous la racine")
			for _, name in measured.bones do
				T.expect(seen[name], "os mesuré absent du .rbxm : " .. name)
			end
		end)

		T.it("les pièces cuites portent une SurfaceAppearance (les images ne sont pas lisibles par Lune)", function()
			-- Lune ne connaît pas les valeurs par défaut des cartes : les ids restent contrôlés dans le manifeste.
			for name, spec in manifest.parts do
				local part = findPart(name, spec)
				if part and spec.bake then
					T.expect(part:FindFirstChildOfClass("SurfaceAppearance"), name .. " : SurfaceAppearance manquante")
				end
			end
			local cloak = findPart("Cloak", manifest.parts.Cloak)
			T.expect(cloak and cloak:FindFirstChildOfClass("SurfaceAppearance"), "SurfaceAppearance de la cape")
		end)
	end)

	T.describe("Manifeste de la Mort : sculpt et textures (#89)", function()
		T.it("chaque pièce sculptée est une pièce du manifeste, et la source du sculpt est versionnée", function()
			T.expect(measured.sculpt and next(measured.sculpt), "aucun sculpt plaqué dans les mesures")
			T.expect(fs.isFile(measured.sculptFile), "source du sculpt absente : " .. tostring(measured.sculptFile))
			for name, info in measured.sculpt do
				T.expect(manifest.parts[name], "pièce sculptée hors manifeste : " .. name)
				T.expect(type(info.base) == "string" and #info.base > 0, name .. " : empreinte de base manquante")
				T.expect((info.levels or 0) >= 1, name .. " : sculpt sans multirésolution")
			end
		end)

		T.it("les doigts pressent le cuir de la poignée (contact mesuré sur les maillages réels)", function()
			local checks = measured.checks
			T.expect(checks and checks.grip_samples and checks.grip_samples > 0, "contact non mesuré")
			T.expect(checks.grip_gap_max <= 0.005, string.format("doigt décollé : %.4f stud", checks.grip_gap_max))
		end)

		T.it("chaque pièce cuite a toutes ses images dans sa SurfaceAppearance", function()
			for name, part in manifest.parts do
				local bake = part.bake
				if not bake then
					continue
				end
				local surface = part.surface or {}
				local wanted = { "ColorMap", "RoughnessMap" }
				if bake.normal ~= false then
					table.insert(wanted, "NormalMap")
				end
				if bake.metalness ~= nil then
					table.insert(wanted, "MetalnessMap")
				end
				for _, map in wanted do
					local id = surface[map]
					T.expect(
						type(id) == "string" and string.match(id, "^rbxassetid://%d+$") ~= nil,
						name .. " : " .. map .. " manquante (texture cuite non envoyée ?)"
					)
				end
			end
		end)
	end)
end

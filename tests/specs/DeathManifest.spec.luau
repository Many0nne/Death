-- Manifeste du modèle de la Mort (#79) : les noms que le code cherche dans le modèle, les os de la cape et les budgets
-- de triangles. La CI n'a pas Blender : on relit le manifeste (tools/models/death.manifest.json) et les mesures que
-- tools/blender/pipeline.py y a écrites (death.measured.json), comparés au code (Client.CloakAnimator,
-- Server.DeathBody, Client.DeathView, Shared.CloakMotion).
local fs = require("@lune/fs")
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
			"le drapé de la cape garde la grille (même nombre de sommets, poids recalculés d'après la grille)",
			function()
				T.expect(measured.drape and measured.drape.frames > 0, "cape mesurée sans drapé")
				T.expectEqual(measured.drape.vertices, 64 * 30)
			end
		)
	end)
end

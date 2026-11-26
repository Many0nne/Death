-- DeathRules : rôle effectif pour la lumière, vitesse et exposition de la Mort, droit de préparer un piège.
return function(T, Loader)
	local loader = Loader.new()
	local DeathRules = loader:require("src/shared/DeathRules")
	local Illumination = loader:require("src/shared/Illumination")
	local Role = DeathRules.Role

	T.describe("DeathRules.lightRole", function()
		-- Cette méthode permet de construire un contexte de rôle avec des valeurs par défaut lorsque chaque cas ne
		-- précise que ce qui change.
		local function ctx(fields)
			local c = { running = false, matchRole = nil, alive = false, isStudio = false, debugDeath = false }
			for k, v in fields do
				c[k] = v
			end
			return c
		end

		T.it("en manche : la Mort tirée, les mortels vivants", function()
			T.expectEqual(DeathRules.lightRole(ctx({ running = true, matchRole = "Death" })), Role.Death)
			T.expectEqual(
				DeathRules.lightRole(ctx({ running = true, matchRole = "Mortal", alive = true })),
				Role.Mortal
			)
		end)

		T.it("en manche : un mortel à terre, mort ou sauvé n'agit plus, un spectateur non plus", function()
			T.expectEqual(DeathRules.lightRole(ctx({ running = true, matchRole = "Mortal", alive = false })), nil)
			T.expectEqual(DeathRules.lightRole(ctx({ running = true })), nil)
		end)

		T.it("en manche, DebugDeath ne change rien", function()
			local c = ctx({ running = true, matchRole = "Mortal", alive = true, isStudio = true, debugDeath = true })
			T.expectEqual(DeathRules.lightRole(c), Role.Mortal)
		end)

		T.it("hors manche en Studio : bac à sable (DebugDeath = Mort, les autres mortels)", function()
			T.expectEqual(DeathRules.lightRole(ctx({ isStudio = true, debugDeath = true })), Role.Death)
			T.expectEqual(DeathRules.lightRole(ctx({ isStudio = true })), Role.Mortal)
		end)

		T.it("hors manche en jeu publié : personne", function()
			T.expectEqual(DeathRules.lightRole(ctx({ debugDeath = true })), nil)
			T.expectEqual(DeathRules.lightRole(ctx({})), nil)
		end)
	end)

	T.describe("DeathRules : vitesse et exposition", function()
		T.it("ralentit la Mort à la lumière, plus rapide qu'un mortel dans l'ombre", function()
			T.expect(DeathRules.speed(true) < DeathRules.MORTAL_SPEED)
			T.expect(DeathRules.speed(false) > DeathRules.MORTAL_SPEED)
		end)

		T.it("expose dès l'entrée dans la lumière", function()
			local state = DeathRules.newExposure()
			T.expectEqual(DeathRules.updateExposure(state, false, 1 / 60), false)
			T.expectEqual(DeathRules.updateExposure(state, true, 1 / 60), true)
		end)

		T.it("cache après SHADOW_GRACE secondes d'ombre continue, pas avant", function()
			local state = DeathRules.newExposure()
			DeathRules.updateExposure(state, true, 0.1)
			T.expectEqual(DeathRules.updateExposure(state, false, DeathRules.SHADOW_GRACE * 0.6), true)
			-- Un retour bref dans la lumière relance le délai
			DeathRules.updateExposure(state, true, 0.01)
			T.expectEqual(DeathRules.updateExposure(state, false, DeathRules.SHADOW_GRACE * 0.6), true)
			T.expectEqual(DeathRules.updateExposure(state, false, DeathRules.SHADOW_GRACE * 0.6), false)
		end)
	end)

	T.describe("DeathRules.canPrepare", function()
		local m = Illumination.new({
			{ id = "A", wingId = "W", min = Vector3.new(0, 0, 0), max = Vector3.new(30, 10, 10) },
		}, {
			{ id = "L", roomId = "A", wingId = "W", position = Vector3.new(5, 9, 5), reach = 10 },
		})

		T.it("refuse la préparation dans la lumière, l'accepte dans l'ombre", function()
			T.expectEqual(DeathRules.canPrepare(m, Vector3.new(5, 1, 5)), false)
			T.expectEqual(DeathRules.canPrepare(m, Vector3.new(28, 1, 5)), true)
		end)

		T.it("l'accepte sous une lampe éteinte", function()
			m:setWingPowered("W", false)
			T.expectEqual(DeathRules.canPrepare(m, Vector3.new(5, 1, 5)), true)
		end)

		T.it("l'accepte sous une lampe cassée (lustre tombé), jusqu'à la remise à zéro", function()
			m:setWingPowered("W", true)
			T.expectEqual(m:breakLamp("L"), true)
			T.expectEqual(m:breakLamp("L"), false, "déjà cassée")
			T.expectEqual(DeathRules.canPrepare(m, Vector3.new(5, 1, 5)), true)
			m:reset()
			T.expectEqual(DeathRules.canPrepare(m, Vector3.new(5, 1, 5)), false)
		end)
	end)

	T.describe("DeathRules.isHoldValid", function()
		T.it("accepte un maintien tenu jusqu'au bout, latence près", function()
			T.expectEqual(DeathRules.isHoldValid(2, 2), true)
			T.expectEqual(DeathRules.isHoldValid(2 - DeathRules.HOLD_TOLERANCE, 2), true)
			T.expectEqual(DeathRules.isHoldValid(nil, 0), true, "invite sans maintien")
		end)

		T.it("refuse un maintien trop court, inconnu ou périmé", function()
			T.expectEqual(DeathRules.isHoldValid(1, 2), false)
			T.expectEqual(DeathRules.isHoldValid(nil, 2), false)
			T.expectEqual(DeathRules.isHoldValid(2 + DeathRules.HOLD_STALE + 0.1, 2), false)
		end)
	end)
end

-- PromptVisibility : règle pure de visibilité des invites (#18, #19) et du reset du personnage (#17).
return function(T, Loader)
	local PV = Loader.new():require("src/shared/PromptVisibility")
	local Match = Loader.new():require("src/shared/Match")
	local S = Match.MortalState

	T.describe("PromptVisibility.visible", function()
		local escape = { role = "Mortal", state = "Alive", available = true }

		T.it("montre l'invite de fuite à un mortel vivant", function()
			T.expect(PV.visible(escape, "Mortal", S.Alive))
		end)

		T.it("la cache à la Mort", function()
			T.expect(not PV.visible(escape, "Death", nil))
		end)

		T.it("la cache à un mortel en agonie, mort ou sauvé, la rend une fois ranimé", function()
			for _, state in { S.Agony, S.Dead, S.Saved } do
				T.expect(not PV.visible(escape, "Mortal", state), state)
			end
			T.expect(PV.visible(escape, "Mortal", S.Alive))
		end)

		T.it("cache toute invite tant que le rôle est inconnu (chargement)", function()
			T.expect(not PV.visible(escape, nil, nil))
			T.expect(not PV.visible({ role = "Death", available = true }, nil, nil))
		end)

		T.it("cache une invite indisponible", function()
			T.expect(not PV.visible({ role = "Mortal", state = "Alive", available = false }, "Mortal", S.Alive))
		end)

		T.it("sans état exigé, l'état du joueur est ignoré (invites de lumière)", function()
			local light = { role = "Death", available = true }
			T.expect(PV.visible(light, "Death", nil))
			T.expect(not PV.visible(light, "Mortal", S.Alive))
		end)

		T.it("sans rôle exigé, tout rôle connu la voit", function()
			T.expect(PV.visible({ available = true }, "Death", nil))
			T.expect(PV.visible({ available = true }, "Mortal", S.Agony))
		end)
	end)

	T.describe("PromptVisibility.canReset", function()
		T.it("autorise le reset hors manche", function()
			T.expect(PV.canReset(nil, nil))
		end)

		T.it("le bloque pour la Mort et pour un mortel vivant ou en agonie", function()
			T.expect(not PV.canReset("Death", nil))
			T.expect(not PV.canReset("Mortal", S.Alive))
			T.expect(not PV.canReset("Mortal", S.Agony))
		end)

		T.it("l'autorise à un spectateur (mortel mort ou sauvé)", function()
			T.expect(PV.canReset("Mortal", S.Dead))
			T.expect(PV.canReset("Mortal", S.Saved))
		end)

		T.it("le bloque tant que l'état du mortel n'est pas connu", function()
			T.expect(not PV.canReset("Mortal", nil))
		end)
	end)
end

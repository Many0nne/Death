-- GameConfig : règles de démarrage d'une manche (1 Mort contre 4 mortels, jamais moins ; mode test plus souple).
return function(T, Loader)
	local GameConfig = Loader.new():require("src/shared/GameConfig")

	T.describe("GameConfig.canStartMatch", function()
		T.it("démarre avec 1 Mort et 4 mortels", function()
			T.expectEqual(GameConfig.canStartMatch(4, true), true)
		end)
		T.it("ne démarre jamais à moins de 4 mortels", function()
			T.expectEqual(GameConfig.canStartMatch(3, true), false)
		end)
		T.it("ne démarre pas sans Mort", function()
			T.expectEqual(GameConfig.canStartMatch(4, false), false)
		end)
	end)

	T.describe("GameConfig.canStartTestMatch", function()
		T.it("démarre avec 1 Mort et 1 à 4 mortels", function()
			for mortals = 1, 4 do
				T.expectEqual(GameConfig.canStartTestMatch(mortals, true), true, tostring(mortals))
			end
		end)
		T.it("refuse 0 mortel, plus de 4, ou sans Mort", function()
			T.expectEqual(GameConfig.canStartTestMatch(0, true), false)
			T.expectEqual(GameConfig.canStartTestMatch(5, true), false)
			T.expectEqual(GameConfig.canStartTestMatch(2, false), false)
		end)
	end)
end

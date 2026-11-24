-- GameConfig : règles de démarrage d'une manche (1 Mort contre 4 mortels, jamais moins).
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
end

-- TrapPrompts : réglages des invites des pièges et ce que permettent celles de la Mort selon l'état du piège et le
-- souffle (#49, même calcul sur le serveur et sur le client de la Mort).
return function(T, Loader)
	local loader = Loader.new()
	local TrapPrompts = loader:require("src/shared/TrapPrompts")
	local Traps = loader:require("src/shared/Traps")

	local view = TrapPrompts.deathView

	T.describe("TrapPrompts.deathView", function()
		T.it("propose de préparer un objet intact, étape par étape pour le lustre", function()
			local work = view("Chandelier", "work", "Idle", 0, 3)
			T.expectEqual(work.text, "Préparer (1/2)")
			T.expectEqual(work.hold, Traps.KINDS.Chandelier.steps[1])
			T.expectEqual(work.available, true)
			T.expectEqual(view("Shelf", "work", "Idle", 0, 3).text, "Préparer")
			T.expectEqual(view("Chandelier", "work", "Preparing", 1, 3).text, "Préparer (2/2)")
			T.expectEqual(view("Chandelier", "work", "Preparing", 1, 3).hold, Traps.KINDS.Chandelier.steps[2])
		end)

		T.it("désarme un piège armé, souffle seulement avec une charge", function()
			local work = view("Shelf", "work", "Armed", 1, 3)
			T.expectEqual(work.text, "Désarmer")
			T.expectEqual(work.hold, Traps.DISARM_HOLD)
			T.expectEqual(view("Shelf", "blow", "Armed", 1, 3).available, true)
			T.expectEqual(view("Shelf", "blow", "Armed", 1, 0).available, false, "plus de souffle")
			T.expectEqual(view("Shelf", "blow", "Idle", 0, 3).available, false, "rien d'armé")
		end)

		T.it("la touche du souffle abandonne un grand piège commencé, même à sec", function()
			local blow = view("Chandelier", "blow", "Preparing", 1, 0)
			T.expectEqual(blow.text, "Abandonner")
			T.expectEqual(blow.hold, Traps.DISARM_HOLD)
			T.expectEqual(blow.available, true)
		end)

		T.it("ne propose plus rien sur un piège déclenché", function()
			T.expectEqual(view("WetFloor", "work", "Spent", 1, 3).available, false)
			T.expectEqual(view("WetFloor", "blow", "Spent", 1, 3).available, false)
		end)
	end)

	T.describe("TrapPrompts.props", function()
		T.it("souffle de plus loin, bulles de préparation et d'examen au-dessus", function()
			T.expectEqual(TrapPrompts.props("Shelf", "blow").MaxActivationDistance, Traps.BREATH_DISTANCE)
			T.expectEqual(TrapPrompts.props("Shelf", "work").MaxActivationDistance, Traps.INTERACT_DISTANCE)
			T.expect(TrapPrompts.props("Shelf", "work").UIOffset.Y < 0, "préparer au-dessus")
			T.expect(TrapPrompts.props("Shelf", "defuse").UIOffset.Y > 0, "désamorcer en dessous")
			T.expectEqual(TrapPrompts.props("Shelf", "defuse").HoldDuration, Traps.KINDS.Shelf.defuse)
			T.expectEqual(
				TrapPrompts.props("Chandelier", "examine").UIOffset.Y,
				-TrapPrompts.SPACING,
				"lustre écarté"
			)
		end)
	end)
end

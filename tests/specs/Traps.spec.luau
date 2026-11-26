-- Traps : états d'un point fragile, limite de pièges en cours, souffle (charges et recharge), zones touchées et buée.
return function(T, Loader)
	local loader = Loader.new()
	local Traps = loader:require("src/shared/Traps")
	local GameConfig = loader:require("src/shared/GameConfig")
	local State = Traps.State

	-- Cette méthode permet de créer des pièges de test lorsque un cas démarre : 5 carrelages, une étagère, un lustre.
	local function board(timing)
		return Traps.new({
			W1 = "WetFloor",
			W2 = "WetFloor",
			W3 = "WetFloor",
			W4 = "WetFloor",
			W5 = "WetFloor",
			Shelf = "Shelf",
			Lustre = "Chandelier",
		}, timing)
	end

	T.describe("Traps : réglages", function()
		T.it("suit le tableau des tailles (docs/design.md)", function()
			T.expectEqual(Traps.KINDS.WetFloor.size, "Small")
			T.expectEqual(Traps.KINDS.Shelf.size, "Medium")
			T.expectEqual(Traps.KINDS.Chandelier.size, "Large")
			local small = Traps.KINDS.WetFloor.steps
			T.expect(#small == 1 and small[1] >= 2 and small[1] <= 3, "petit : 2 à 3 s")
			local medium = Traps.KINDS.Shelf.steps
			T.expect(#medium == 1 and medium[1] >= 5 and medium[1] <= 6, "moyen : 5 à 6 s")
			local large = Traps.KINDS.Chandelier.steps
			T.expectEqual(#large, 2, "grand : 2 étapes")
			T.expectEqual(large[1] + large[2], 10, "grand : 10 s")
			for kind, spec in Traps.KINDS do
				T.expect(spec.defuse >= 4 and spec.defuse <= 8, kind .. " : désamorcer en 4 à 8 s")
			end
			T.expectEqual(Traps.EXAMINE_HOLD, 1)
			T.expect(Traps.KINDS.Chandelier.hitRadius > Traps.KINDS.WetFloor.hitRadius, "le grand touche plus loin")
		end)

		T.it("la buée se sent à environ 3 m", function()
			T.expectNear(Traps.CHILL_RADIUS / Traps.STUDS_PER_METER, 3, 0.2)
		end)

		T.it("refuse un type inconnu", function()
			local ok = pcall(Traps.new, { X = "Piano" })
			T.expectEqual(ok, false)
		end)
	end)

	T.describe("Traps : préparation", function()
		T.it("arme un petit piège en une étape, un grand en deux", function()
			local b = board()
			T.expectEqual(b:nextStepDuration("W1"), Traps.KINDS.WetFloor.steps[1])
			local ok, _, state = b:prepare("W1")
			T.expect(ok and state == State.Armed, "carrelage armé")
			T.expectEqual(b:nextStepDuration("W1"), nil, "plus rien à préparer")
			ok, _, state = b:prepare("Lustre")
			T.expect(ok and state == State.Preparing, "lustre : première étape")
			T.expectEqual(b:nextStepDuration("Lustre"), 5)
			T.expectEqual(b:armedCount(), 1, "un lustre à moitié n'est pas armé")
			T.expectEqual(b:activeCount(), 2, "mais il garde sa place")
			_, _, state = b:prepare("Lustre")
			T.expectEqual(state, State.Armed)
			local again, err = b:prepare("Lustre")
			T.expect(not again and err == "piège déjà armé", tostring(err))
		end)

		T.it(string.format("refuse un %de piège en cours", GameConfig.MAX_ARMED_TRAPS + 1), function()
			local b = board()
			T.expectEqual(GameConfig.MAX_ARMED_TRAPS, 4)
			for _, id in { "W1", "W2", "W3" } do
				b:prepare(id)
			end
			b:prepare("Lustre") -- à moitié : compte dans la limite
			local ok, err = b:prepare("W4")
			T.expectEqual(ok, false)
			T.expect(string.find(err, "4 pièges", 1, true) ~= nil, tostring(err))
			T.expectEqual(b:prepare("Lustre"), true, "finir un piège commencé reste possible")
		end)

		T.it("désarmer libère une place pour replacer le piège", function()
			local b = board()
			for _, id in { "W1", "W2", "W3", "W4" } do
				b:prepare(id)
			end
			T.expectEqual(b:prepare("W5"), false)
			T.expectEqual(b:disarm("W2"), true)
			T.expectEqual(b:get("W2").state, State.Idle)
			T.expectEqual(b:prepare("W5"), true)
			T.expectEqual(b:disarm("W2"), false, "rien à désarmer")
		end)

		T.it("la limite vient du réglage", function()
			local b = board({ maxActive = 1, breathCharges = 3, breathRecharge = 45 })
			b:prepare("W1")
			T.expectEqual(b:prepare("W2"), false)
		end)
	end)

	T.describe("Traps : souffle", function()
		T.it("3 charges, chacune déclenche un piège armé", function()
			local b = board()
			T.expectEqual(b:breath(0), GameConfig.BREATH_CHARGES)
			T.expectEqual(b:blow("W1", 0), false, "pas armé")
			for _, id in { "W1", "W2", "W3", "W4" } do
				b:prepare(id)
			end
			for i, id in { "W1", "W2", "W3" } do
				T.expectEqual(b:blow(id, 0), true, id)
				T.expectEqual(b:get(id).state, State.Spent)
				T.expectEqual((b:breath(0)), 3 - i)
			end
			local ok, err = b:blow("W4", 0)
			T.expect(not ok and err == "plus de souffle", tostring(err))
			T.expectEqual(b:get("W4").state, State.Armed, "le piège reste armé")
		end)

		T.it("recharge lente : une charge par période, jusqu'au maximum", function()
			local b = board({ maxActive = 4, breathCharges = 3, breathRecharge = 45 })
			b:spendCharge(0)
			b:spendCharge(10)
			local charges, at = b:breath(10)
			T.expectEqual(charges, 1)
			T.expectEqual(at, 45, "la recharge part de la première charge dépensée")
			T.expectEqual((b:breath(44)), 1)
			T.expectEqual((b:breath(45)), 2)
			charges, at = b:breath(89)
			T.expect(charges == 2 and at == 90, "seconde charge à 90 s")
			charges, at = b:breath(500)
			T.expect(charges == 3 and at == nil, "plein")
		end)

		T.it("un piège déclenché ne se prépare plus et libère sa place", function()
			local b = board()
			b:prepare("Shelf")
			b:blow("Shelf", 0)
			local ok, err = b:prepare("Shelf")
			T.expect(not ok and err == "piège déjà déclenché", tostring(err))
			T.expectEqual(b:isTampered("Shelf"), false)
			T.expectEqual(b:activeCount(), 0, "la place est libérée")
		end)

		T.it("perdre une charge (dissipation #8) et remplir le souffle (âme)", function()
			local b = board()
			T.expectEqual(b:spendCharge(0), true)
			T.expectEqual(b:spendCharge(0), true)
			T.expectEqual(b:spendCharge(0), true)
			T.expectEqual(b:spendCharge(0), false, "plus rien à perdre")
			b:refillBreath()
			local charges, at = b:breath(0)
			T.expect(charges == 3 and at == nil, "plein")
		end)
	end)

	T.describe("Traps : contre-jeu", function()
		T.it("examiner révèle un piège armé ou commencé, rien sinon", function()
			local b = board()
			T.expectEqual(b:isTampered("W1"), false)
			b:prepare("W1")
			b:prepare("Lustre")
			T.expectEqual(b:isTampered("W1"), true)
			T.expectEqual(b:isTampered("Lustre"), true, "lustre à moitié préparé")
			T.expectEqual(b:isTampered("Inconnu"), false)
		end)

		T.it("désamorcer rend l'objet inoffensif ; sur un objet sain, rien ne se passe", function()
			local b = board()
			b:prepare("Shelf")
			T.expectEqual(b:defuse("Shelf"), true)
			T.expectEqual(b:get("Shelf").state, State.Idle)
			local ok, err = b:defuse("W1")
			T.expect(not ok and err == "rien à désamorcer", tostring(err))
		end)

		T.it("une remise à zéro relève tout et remplit le souffle", function()
			local b = board()
			b:prepare("W1")
			b:blow("W1", 0)
			b:prepare("Lustre")
			b:reset()
			T.expectEqual(b:get("W1").state, State.Idle)
			T.expectEqual(b:get("Lustre").step, 0)
			T.expectEqual((b:breath(0)), 3)
		end)
	end)

	T.describe("Traps : zones", function()
		local floor = Vector3.new(0, 0, 0)

		T.it("le carrelage touche seulement qui est dessus", function()
			T.expectEqual(Traps.hits("WetFloor", floor, Vector3.new(1, 3, 1)), true)
			T.expectEqual(Traps.hits("WetFloor", floor, Vector3.new(5, 3, 0)), false)
		end)

		T.it("le lustre peut toucher plusieurs mortels, pas l'étage du dessus", function()
			local inside = 0
			for _, pos in { Vector3.new(0, 3, 0), Vector3.new(5, 3, 3), Vector3.new(-4, 3, -5), Vector3.new(12, 3, 0) } do
				if Traps.hits("Chandelier", floor, pos) then
					inside += 1
				end
			end
			T.expectEqual(inside, 3)
			T.expectEqual(Traps.hits("Chandelier", floor, Vector3.new(0, 15, 0)), false, "étage")
			T.expectEqual(Traps.hits("Chandelier", floor, Vector3.new(0, -9, 0)), false, "cave")
		end)

		T.it("l'étagère ne touche que devant elle", function()
			local front = Vector3.new(0, 0, 1)
			T.expectEqual(Traps.hits("Shelf", floor, Vector3.new(0, 3, 4), front), true)
			T.expectEqual(Traps.hits("Shelf", floor, Vector3.new(0, 3, -4), front), false, "derrière")
			T.expectEqual(Traps.hits("Shelf", floor, Vector3.new(0, 3, 9), front), false, "trop loin")
		end)

		T.it("avec sa taille, l'étagère touche la bande où elle s'abat", function()
			-- 8 de large (X), 7 de haut, 1,5 de profondeur (Z), tombe vers +Z : jusqu'à 0,75 + 7 (+ 1) devant
			local front, box = Vector3.new(0, 0, 1), Vector3.new(8, 7, 1.5)
			T.expectEqual(Traps.hits("Shelf", floor, Vector3.new(0, 3, 7.5), front, box), true, "au bout")
			T.expectEqual(Traps.hits("Shelf", floor, Vector3.new(4.5, 3, 3), front, box), true, "au bord")
			T.expectEqual(Traps.hits("Shelf", floor, Vector3.new(0, 3, 9.5), front, box), false, "au-delà")
			T.expectEqual(Traps.hits("Shelf", floor, Vector3.new(6, 3, 3), front, box), false, "à côté")
			T.expectEqual(Traps.hits("Shelf", floor, Vector3.new(0, 3, -3), front, box), false, "derrière")
		end)

		T.it("la buée prévient à environ 3 m, sur le même niveau", function()
			T.expectEqual(Traps.chills(floor, Vector3.new(Traps.CHILL_RADIUS - 0.5, 3, 0)), true)
			T.expectEqual(Traps.chills(floor, Vector3.new(Traps.CHILL_RADIUS + 1, 3, 0)), false)
			T.expectEqual(Traps.chills(floor, Vector3.new(0, 15, 0)), false)
		end)
	end)
end

-- Flashlight : cône du faisceau, batterie, cumul des 3 s de dissipation, ombre de reformation, tirage des piles.
return function(T, Loader)
	local loader = Loader.new()
	local Flashlight = loader:require("src/shared/Flashlight")

	local origin = Vector3.new(0, 5, 0)
	local forward = Vector3.new(0, 0, -1)

	T.describe("Flashlight.inBeam", function()
		T.it("touche un point droit devant, à portée", function()
			T.expect(Flashlight.inBeam(origin, forward, origin + forward * 20))
			T.expect(Flashlight.inBeam(origin, forward, origin + forward * (Flashlight.RANGE - 0.1)))
		end)

		T.it("ne touche pas au-delà de la portée, ni derrière", function()
			T.expect(not Flashlight.inBeam(origin, forward, origin + forward * (Flashlight.RANGE + 0.5)))
			T.expect(not Flashlight.inBeam(origin, forward, origin - forward * 5))
		end)

		T.it("respecte le demi-angle du cône", function()
			local inside = math.rad(Flashlight.HALF_ANGLE - 1)
			local outside = math.rad(Flashlight.HALF_ANGLE + 1)
			local d = 20
			local pointIn = origin + Vector3.new(math.sin(inside), 0, -math.cos(inside)) * d
			local pointOut = origin + Vector3.new(math.sin(outside), 0, -math.cos(outside)) * d
			T.expect(Flashlight.inBeam(origin, forward, pointIn), "juste dedans")
			T.expect(not Flashlight.inBeam(origin, forward, pointOut), "juste dehors")
		end)

		T.it("un corps est touché dès que son bord entre dans le cône", function()
			local outside = math.rad(Flashlight.HALF_ANGLE + 3)
			local point = origin + Vector3.new(math.sin(outside), 0, -math.cos(outside)) * 20
			T.expect(not Flashlight.inBeam(origin, forward, point, 0))
			T.expect(Flashlight.inBeam(origin, forward, point, Flashlight.BODY_RADIUS))
		end)

		T.it("tout près de la lampe, ni à côté ni derrière, et la marge du corps reste bornée", function()
			local side = origin + Vector3.new(1, 0, 0)
			local behind = origin + Vector3.new(0, 0, 1)
			T.expect(not Flashlight.inBeam(origin, forward, side, Flashlight.BODY_RADIUS), "à côté")
			T.expect(not Flashlight.inBeam(origin, forward, behind, Flashlight.BODY_RADIUS), "derrière")
			local wide = math.rad(60)
			local near = origin + Vector3.new(math.sin(wide), 0, -math.cos(wide)) * 2
			T.expect(not Flashlight.inBeam(origin, forward, near, Flashlight.BODY_RADIUS), "60° à 2 studs")
		end)

		T.it("accepte une direction non normalisée", function()
			T.expect(Flashlight.inBeam(origin, forward * 7, origin + forward * 10))
		end)
	end)

	T.describe("Flashlight : batterie", function()
		T.it("se vide en BATTERY_DURATION secondes d'usage, sans passer sous 0", function()
			local level = 1
			for _ = 1, Flashlight.BATTERY_DURATION * 10 - 1 do
				level = Flashlight.drain(level, 0.1)
			end
			T.expect(level > 0, "pas encore vide")
			level = Flashlight.drain(level, 0.1)
			T.expectNear(level, 0, 1e-9)
			T.expectEqual(Flashlight.drain(0, 1), 0)
		end)

		T.it("publie au centième, jamais 0 pour une batterie non vide", function()
			T.expectNear(Flashlight.quantize(0.504), 0.5, 1e-9)
			T.expectNear(Flashlight.quantize(0.001), Flashlight.PUBLISH_STEP, 1e-9)
			T.expectEqual(Flashlight.quantize(0), 0)
			T.expectEqual(Flashlight.quantize(1), 1)
		end)
	end)

	T.describe("Flashlight.updateDispel", function()
		T.it("dissipe au bout de DISPEL_TIME secondes tenues", function()
			local state = Flashlight.newDispel()
			local dt = 1 / 60
			local frames = 0
			local dispelled, progress = false, 0
			while not dispelled and frames < 1000 do
				dispelled, progress = Flashlight.updateDispel(state, true, dt)
				frames += 1
			end
			T.expect(dispelled)
			T.expectNear(frames * dt, Flashlight.DISPEL_TIME, dt + 1e-6)
			T.expectEqual(progress, 1)
		end)

		T.it("une coupure brève garde le cumul, une longue l'efface", function()
			local state = Flashlight.newDispel()
			local _, p1 = Flashlight.updateDispel(state, true, 1.5)
			T.expectNear(p1, 1.5 / Flashlight.DISPEL_TIME)
			Flashlight.updateDispel(state, false, Flashlight.DISPEL_GAP * 0.5)
			local _, p2 = Flashlight.updateDispel(state, true, 0.5)
			T.expectNear(p2, 2 / Flashlight.DISPEL_TIME, 1e-9, "cumul gardé")
			Flashlight.updateDispel(state, false, Flashlight.DISPEL_GAP + 0.05)
			local _, p3 = Flashlight.updateDispel(state, true, 0.1)
			T.expectNear(p3, 0.1 / Flashlight.DISPEL_TIME, 1e-9, "cumul effacé")
		end)

		T.it("aucun cumul pendant le répit qui suit une dissipation", function()
			local state = Flashlight.newDispel()
			T.expect((Flashlight.updateDispel(state, true, Flashlight.DISPEL_TIME)))
			local dispelled, progress = Flashlight.updateDispel(state, true, Flashlight.DISPEL_IMMUNITY - 0.1)
			T.expect(not dispelled)
			T.expectEqual(progress, 0)
			Flashlight.updateDispel(state, true, 0.2)
			local _, after = Flashlight.updateDispel(state, true, 1)
			T.expect(after > 0, "le cumul reprend après le répit")
		end)
	end)

	T.describe("Flashlight.chooseRespawn", function()
		local function never()
			return false
		end
		local function first()
			return 1
		end

		T.it("choisit une ombre loin de la Mort et de chaque mortel", function()
			local candidates = { Vector3.new(0, 0, 0), Vector3.new(100, 0, 0), Vector3.new(10, 0, 0) }
			local point =
				Flashlight.chooseRespawn(candidates, Vector3.new(5, 0, 0), { Vector3.new(0, 0, 5) }, never, first)
			T.expectEqual(point, Vector3.new(100, 0, 0))
		end)

		T.it("écarte les points éclairés", function()
			local candidates = { Vector3.new(100, 0, 0), Vector3.new(-100, 0, 0) }
			local function lit(p)
				return p.X > 0
			end
			local point = Flashlight.chooseRespawn(candidates, Vector3.zero, {}, lit, first)
			T.expectEqual(point, Vector3.new(-100, 0, 0))
		end)

		T.it("à défaut de point assez loin, prend l'ombre la plus éloignée du plus proche", function()
			local candidates = { Vector3.new(10, 0, 0), Vector3.new(30, 0, 0), Vector3.new(20, 0, 0) }
			local point = Flashlight.chooseRespawn(candidates, Vector3.zero, {}, never, first)
			T.expectEqual(point, Vector3.new(30, 0, 0))
		end)

		T.it("rien si tout est éclairé", function()
			local point = Flashlight.chooseRespawn({ Vector3.new(100, 0, 0) }, Vector3.zero, {}, function()
				return true
			end, first)
			T.expectEqual(point, nil)
		end)
	end)

	T.describe("Flashlight.drawBatterySpots", function()
		local spots = {
			{ id = "A1", room = "A" },
			{ id = "A2", room = "A" },
			{ id = "B1", room = "B" },
			{ id = "C1", room = "C" },
		}
		local function first()
			return 1
		end

		T.it("au plus une pile par pièce, jamais sur un emplacement occupé", function()
			local chosen = Flashlight.drawBatterySpots(spots, 3, first, { A1 = true })
			T.expectEqual(#chosen, 3)
			T.expectEqual(table.concat(chosen, ","), "A2,B1,C1")
		end)

		T.it("moins de piles que demandé s'il manque des pièces", function()
			local chosen = Flashlight.drawBatterySpots(spots, 5, first, { C1 = true })
			T.expectEqual(#chosen, 2)
		end)
	end)
end

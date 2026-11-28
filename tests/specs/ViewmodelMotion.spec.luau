-- ViewmodelMotion (#74) : flottement lent et sans à-coup, balancement borné, lissage, gestes, projection et
-- composition des repères d'un viewmodel.
return function(T, Loader)
	local M = Loader.new():require("src/shared/ViewmodelMotion")
	local F = M.FLOAT

	T.describe("ViewmodelMotion.float", function()
		T.it("reste dans son amplitude, à l'arrêt comme à pleine vitesse", function()
			for _, moving in { 0, 1 } do
				local limit = F.amplitude * (1 + F.movingGain * moving) + 1e-9
				local swayLimit = F.sway * (1 + F.movingGain * moving) + 1e-9
				for k = 0, 600 do
					local p = M.float(k * 0.05, 0.7, moving).Position
					T.expect(math.abs(p.Y) <= limit, "bob hors amplitude")
					T.expect(math.abs(p.X) <= swayLimit, "dérive hors amplitude")
					T.expectNear(p.Z, 0, 1e-9)
				end
			end
		end)
		T.it("est lent : période du bob de plusieurs secondes", function()
			T.expect(F.period >= 3, "bob trop rapide")
			T.expectNear(M.float(0, 0, 0).Position.Y, M.float(F.period, 0, 0).Position.Y, 1e-6)
		end)
		T.it("ne fait aucun saut d'une image à l'autre (60 images/s), même en déplacement", function()
			local prev = M.float(0, 0, 1).Position
			local maxStep = 0
			for k = 1, 60 * 12 do
				local p = M.float(k / 60, 0, 1).Position
				maxStep = math.max(maxStep, (p - prev).Magnitude)
				prev = p
			end
			-- vitesse maximale du bob : 2π·A·gain / période ≈ 0,084 stud/s, soit 1,4 millième de stud par image
			T.expect(maxStep < 0.003, string.format("pas de %.4f stud", maxStep))
		end)
		T.it("décale deux mains de phases différentes", function()
			T.expect(math.abs(M.float(1, 0, 0).Position.Y - M.float(1, 1.9, 0).Position.Y) > 1e-3, "mains synchrones")
		end)
	end)

	T.describe("ViewmodelMotion.sway", function()
		T.it("traîne à l'opposé du regard et reste borné", function()
			local s = M.sway(1, 0)
			T.expect(s.X > 0, "lacet : la main doit traîner")
			T.expect(M.sway(0, 1).Y < 0, "tangage vers le haut : la main traîne en bas")
			T.expectNear(M.sway(100, 100).Magnitude, M.SWAY.max, 1e-6)
		end)
	end)

	T.describe("ViewmodelMotion.smoothing / ease / pulse", function()
		T.it("lisse sans dépendre de la cadence", function()
			local a = M.smoothing(0.1, 0.2)
			local b = 1 - (1 - M.smoothing(0.05, 0.2)) ^ 2
			T.expectNear(a, b, 1e-9)
			T.expectNear(M.smoothing(0.1, 0), 1)
			T.expectNear(M.smoothing(0, 0.2), 0)
		end)
		T.it("lisse les bouts d'une courbe", function()
			T.expectNear(M.ease(0), 0)
			T.expectNear(M.ease(1), 1)
			T.expectNear(M.ease(0.5), 0.5)
			T.expectNear(M.ease(-1), 0)
			T.expectNear(M.ease(2), 1)
		end)
		T.it("monte puis redescend pendant un geste, nul hors du geste", function()
			T.expectNear(M.pulse(0, 0.7), 0)
			T.expectNear(M.pulse(0.35, 0.7), 1)
			T.expectNear(M.pulse(0.7, 0.7), 0)
			T.expectNear(M.pulse(nil, 0.7), 0)
			T.expectNear(M.pulse(-0.1, 0.7), 0)
		end)
	end)

	T.describe("ViewmodelMotion.keyframes", function()
		local keys = {
			{ at = 0, frame = CFrame.new(0, 0, 0), value = 1 },
			{ at = 0.5, frame = CFrame.new(1, 0, 0), value = 0 },
			{ at = 1, frame = CFrame.new(1, 2, 0) },
		}
		T.it("rend les clés aux bornes et interpole entre elles", function()
			local f, v = M.keyframes(keys, 0)
			T.expectNear(f.Position.X, 0)
			T.expectNear(v, 1)
			f, v = M.keyframes(keys, 0.5)
			T.expectNear(f.Position.X, 1)
			T.expectNear(v, 0)
			f = M.keyframes(keys, 0.25)
			T.expectNear(f.Position.X, 0.5)
			f, v = M.keyframes(keys, 2)
			T.expectNear(f.Position.Y, 2)
			T.expectNear(v, 0)
		end)
	end)

	T.describe("ViewmodelMotion.crossfade", function()
		T.it("part de la pose affichée et arrive à la nouvelle", function()
			local from = { a = CFrame.new(0, 0, 0) }
			local to = { a = CFrame.new(2, 0, 0), b = CFrame.new(5, 0, 0) }
			T.expectNear(M.crossfade(from, to, 0, 0.35).a.Position.X, 0)
			T.expectNear(M.crossfade(from, to, 0.35, 0.35).a.Position.X, 2)
			T.expectNear(M.crossfade(from, to, 0.175, 0.35).a.Position.X, 1)
			T.expectNear(M.crossfade(from, to, 0, 0.35).b.Position.X, 5, 1e-9, "groupe sans départ")
		end)
	end)

	T.describe("ViewmodelMotion.project / unproject / aim / partFrame", function()
		T.it("projette au centre ce qui est droit devant, rien derrière", function()
			local s = M.project(Vector3.new(0, 0, -3), 80, 2)
			T.expectNear(s.X, 0)
			T.expectNear(s.Y, 0)
			T.expect(M.project(Vector3.new(0, 0, 1), 80, 2) == nil, "derrière la caméra")
		end)
		T.it("place le bord de l'écran au demi-champ", function()
			local half = math.tan(math.rad(40))
			T.expectNear(M.project(Vector3.new(0, half * 2, -2), 80, 2).Y, 1, 1e-9)
			T.expectNear(M.project(Vector3.new(half * 2 * 2, 0, -2), 80, 2).X, 1, 1e-9)
		end)
		T.it("revient au point de départ par unproject", function()
			local p = Vector3.new(0.7, -0.4, -1.8)
			local back = M.unproject(M.project(p, 80, 1611 / 759), 1.8, 80, 1611 / 759)
			T.expectNear((back - p).Magnitude, 0, 1e-9)
		end)
		T.it("oriente -Z vers la direction donnée", function()
			local dir = Vector3.new(0.2, -0.4, -1).Unit
			local c = M.aim(Vector3.new(1, 2, 3), dir)
			local forward = c * Vector3.new(0, 0, -1) - c.Position
			T.expectNear(forward:Dot(dir), 1, 1e-6)
			T.expect((c * Vector3.new(0, 1, 0) - c.Position).Y > 0, "haut du repère vers le haut")
		end)
		T.it("garde l'écart de chaque pièce à son ancre", function()
			local anchor = CFrame.new(1, 1, 1)
			local part = CFrame.new(1, 2, 0)
			local pose = CFrame.new(0, -1, -2)
			local out = M.partFrame(CFrame.identity, pose, anchor, part)
			T.expectNear((out.Position - Vector3.new(0, 0, -3)).Magnitude, 0, 1e-9)
			local cam = CFrame.new(10, 0, 0)
			T.expectNear((M.partFrame(cam, pose, anchor, part).Position - Vector3.new(10, 0, -3)).Magnitude, 0, 1e-9)
		end)
	end)
end

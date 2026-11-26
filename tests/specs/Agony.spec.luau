-- Agony : règles pures de l'agonie (minuterie, qualité du rythme, massage, fauchage, lutte pour l'âme).
return function(T, Loader)
	local loader = Loader.new()
	local Agony = loader:require("src/shared/Agony")
	local GameConfig = loader:require("src/shared/GameConfig")
	local Outcome = Agony.Outcome

	local DYING, MASSAGER, OTHER, DEATH = 1, 2, 3, 9

	-- Cette méthode permet de simuler un masseur qui appuie à une cadence fixe pendant `seconds` secondes, l'agonie
	-- avançant entre deux compressions ; renvoie les issues, l'horloge finale et le nombre de compressions.
	local function massage(rules, bpm: number, seconds: number, start: number?)
		local period = 60 / bpm
		local now = start or 0
		local presses = 0
		local all = {}
		while now <= (start or 0) + seconds do
			rules:press(MASSAGER, now)
			presses += 1
			local resolved = rules:advance(period, now + period)
			for _, r in resolved do
				table.insert(all, r)
			end
			now += period
			if #all > 0 then
				break
			end
		end
		return all, now, presses
	end

	T.describe("Agony.quality", function()
		T.it("vaut 1 dans la cadence 100 à 120 battements par minute", function()
			T.expectEqual(Agony.quality(60 / 100), 1)
			T.expectEqual(Agony.quality(60 / 110), 1)
			T.expectEqual(Agony.quality(60 / 120), 1)
		end)
		T.it("tolère la gigue du réseau au bord de la fenêtre", function()
			T.expectEqual(Agony.quality(0.5 - Agony.RHYTHM_TOLERANCE), 1)
			T.expectEqual(Agony.quality(0.6 + Agony.RHYTHM_TOLERANCE), 1)
		end)
		T.it("baisse puis s'annule hors cadence", function()
			local fast = Agony.quality(0.4)
			local slow = Agony.quality(0.7)
			T.expect(fast > 0 and fast < 1, "un peu trop vite : " .. fast)
			T.expect(slow > 0 and slow < 1, "un peu trop lent : " .. slow)
			T.expectEqual(Agony.quality(0.2), 0, "matraquage")
			T.expectEqual(Agony.quality(1.2), 0, "bien trop lent")
		end)
	end)

	T.describe("Agony : minuterie et cœur", function()
		T.it("meurt seul au bout de l'agonie, pas avant", function()
			local rules = Agony.new()
			rules:start(DYING)
			local resolved = rules:advance(GameConfig.AGONY_DURATION - 0.1, 0)
			T.expectEqual(#resolved, 0)
			resolved = rules:advance(0.2, 0)
			T.expectEqual(#resolved, 1)
			T.expectEqual(resolved[1].outcome, Outcome.Died)
			T.expectEqual(rules:get(DYING), nil, "retiré du suivi")
		end)
		T.it("le cœur ralentit de 90 à 40 battements par minute", function()
			T.expectEqual(Agony.heartRate(GameConfig.AGONY_DURATION), Agony.HEART_BPM_START)
			T.expectEqual(Agony.heartRate(0), Agony.HEART_BPM_END)
			T.expect(Agony.heartRate(20) < Agony.heartRate(40))
		end)
	end)

	T.describe("Agony : massage cardiaque", function()
		T.it("ranime en environ 8 s au bon rythme (110 bpm)", function()
			local rules = Agony.new()
			rules:start(DYING)
			T.expect(rules:beginMassage(DYING, MASSAGER, 0))
			local resolved, now, presses = massage(rules, 110, 30)
			T.expectEqual(#resolved, 1)
			T.expectEqual(resolved[1].outcome, Outcome.Revived)
			T.expectEqual(resolved[1].massager, MASSAGER)
			T.expect(now >= 7.5 and now <= 9, string.format("durée %.2f s", now))
			T.expectEqual(presses, 16)
		end)
		T.it("aux bornes 100 et 120 bpm, toujours autour de 8 s", function()
			for _, bpm in { 100, 120 } do
				local rules = Agony.new()
				rules:start(DYING)
				rules:beginMassage(DYING, MASSAGER, 0)
				local resolved, now = massage(rules, bpm, 30)
				T.expectEqual(resolved[1].outcome, Outcome.Revived)
				T.expect(now >= 7 and now <= 10, string.format("%d bpm : %.2f s", bpm, now))
			end
		end)
		T.it("un mauvais rythme ralentit, beaucoup trop vite n'avance pas", function()
			local rules = Agony.new()
			rules:start(DYING)
			rules:beginMassage(DYING, MASSAGER, 0)
			local resolved, now = massage(rules, 90, 40)
			T.expectEqual(resolved[1] and resolved[1].outcome, Outcome.Revived)
			T.expect(now > 11, string.format("90 bpm : %.2f s", now))

			local spam = Agony.new()
			spam:start(DYING)
			spam:beginMassage(DYING, MASSAGER, 0)
			massage(spam, 300, 10)
			T.expectEqual(spam:get(DYING).progress, 0)
		end)
		T.it("un seul masseur à la fois, jamais un agonisant", function()
			local rules = Agony.new()
			rules:start(DYING)
			rules:start(OTHER)
			T.expect(rules:beginMassage(DYING, MASSAGER, 0))
			T.expect(not rules:beginMassage(DYING, 4, 0), "déjà massé")
			T.expect(not rules:beginMassage(OTHER, MASSAGER, 0), "masseur occupé")
			T.expect(not rules:beginMassage(DYING, OTHER, 0), "agonisant")
			T.expect(not rules:beginMassage(5, 4, 0), "pas en agonie")
		end)
		T.it("abandonné sans compression : avancée perdue, masseur libéré", function()
			local rules = Agony.new()
			rules:start(DYING)
			rules:beginMassage(DYING, MASSAGER, 0)
			massage(rules, 110, 3)
			T.expect(rules:get(DYING).progress > 0)
			local _, idle = rules:advance(0.1, 3 + Agony.MASSAGE_IDLE + 1)
			T.expectEqual(idle[1], MASSAGER)
			T.expectEqual(rules:get(DYING).progress, 0)
			T.expectEqual(rules:targetOf(MASSAGER), nil)
		end)
		T.it("une compression hors massage est ignorée", function()
			local rules = Agony.new()
			T.expectEqual(rules:press(MASSAGER, 0), nil)
		end)
	end)

	T.describe("Agony : fauchage et lutte pour l'âme", function()
		T.it("sans massage, l'âme est récoltée tout de suite", function()
			local rules = Agony.new()
			rules:start(DYING)
			T.expectEqual(rules:reap(DYING, DEATH), Outcome.Reaped)
			T.expectEqual(rules:get(DYING), nil)
			T.expectEqual((rules:reap(DYING, DEATH)), nil, "plus rien à faucher")
		end)
		T.it("pendant un massage, lutte : la faux gagne seule en 4 s", function()
			local rules = Agony.new()
			rules:start(DYING)
			rules:beginMassage(DYING, MASSAGER, 0)
			T.expectEqual(rules:reap(DYING, DEATH), "Struggle")
			T.expectEqual(rules:get(DYING).pull, Agony.STRUGGLE_START)
			T.expectEqual((rules:reap(DYING, DEATH)), nil, "une seule lutte")
			local resolved = {}
			local t = 0
			while #resolved == 0 and t < 10 do
				t += 0.1
				resolved = rules:advance(0.1, 0)
			end
			T.expectEqual(resolved[1].outcome, Outcome.Reaped)
			T.expectNear(t, GameConfig.REAP_DURATION, 0.15)
		end)
		T.it("un bon rythme gagne la lutte, un mauvais la perd", function()
			local good = Agony.new()
			good:start(DYING)
			good:beginMassage(DYING, MASSAGER, 0)
			good:press(MASSAGER, 0)
			good:reap(DYING, DEATH)
			local resolved = massage(good, 110, 20, 60 / 110)
			T.expectEqual(resolved[1].outcome, Outcome.Revived, "110 bpm")

			local bad = Agony.new()
			bad:start(DYING)
			bad:beginMassage(DYING, MASSAGER, 0)
			bad:press(MASSAGER, 0)
			bad:reap(DYING, DEATH)
			resolved = massage(bad, 75, 20, 60 / 75)
			T.expectEqual(resolved[1].outcome, Outcome.Reaped, "75 bpm")
		end)
		T.it("le seuil de qualité de la lutte est autour de la moitié", function()
			T.expect(
				Agony.BREAK_EVEN_QUALITY > 0.4 and Agony.BREAK_EVEN_QUALITY < 0.7,
				tostring(Agony.BREAK_EVEN_QUALITY)
			)
		end)
		T.it("le masseur qui abandonne la lutte laisse l'âme à la faux", function()
			local rules = Agony.new()
			rules:start(DYING)
			rules:beginMassage(DYING, MASSAGER, 0)
			rules:reap(DYING, DEATH)
			rules:endMassage(MASSAGER)
			local resolved = rules:advance(GameConfig.REAP_DURATION, 0)
			T.expectEqual(resolved[1].outcome, Outcome.Reaped)
		end)
	end)
end

-- HudFormat : textes du HUD de manche et de l'écran de fin (#9), calculés depuis les attributs répliqués.
return function(T, Loader)
	local HudFormat = Loader.new():require("src/shared/HudFormat")

	T.describe("HudFormat.clock", function()
		T.it("écrit minutes et secondes, arrondi au-dessus", function()
			T.expectEqual(HudFormat.clock(245), "4:05")
			T.expectEqual(HudFormat.clock(59.2), "1:00")
			T.expectEqual(HudFormat.clock(0), "0:00")
		end)
		T.it("ne descend jamais sous zéro", function()
			T.expectEqual(HudFormat.clock(-3), "0:00")
		end)
	end)

	T.describe("HudFormat.hourglass", function()
		T.it("barre seule au-dessus d'une minute", function()
			local fraction, text = HudFormat.hourglass(240, 480)
			T.expectNear(fraction, 0.5)
			T.expectEqual(text, nil)
		end)
		T.it("chiffres sous une minute (seuil compris)", function()
			local _, atThreshold = HudFormat.hourglass(60, 480)
			T.expectEqual(atThreshold, "1:00")
			local fraction, text = HudFormat.hourglass(42, 480)
			T.expectNear(fraction, 42 / 480)
			T.expectEqual(text, "0:42")
		end)
		T.it("vide hors manche ou durée invalide", function()
			local fraction, text = HudFormat.hourglass(nil, 480)
			T.expectEqual(fraction, 0)
			T.expectEqual(text, nil)
			T.expectEqual((HudFormat.hourglass(10, 0)), 0)
		end)
		T.it("borne la part restante à [0, 1]", function()
			T.expectEqual((HudFormat.hourglass(600, 480)), 1)
		end)
	end)

	T.describe("HudFormat.role", function()
		T.it("nomme les deux rôles, nil hors rôle", function()
			T.expectEqual(HudFormat.role("Death"), "La Mort")
			T.expectEqual(HudFormat.role("Mortal"), "Mortel")
			T.expectEqual(HudFormat.role(nil), nil)
		end)
	end)

	T.describe("HudFormat.mortalState", function()
		T.it("vivant, enfui, fauché", function()
			T.expectEqual(HudFormat.mortalState("Alive"), "Vivant")
			T.expectEqual(HudFormat.mortalState("Saved"), "Enfui")
			T.expectEqual(HudFormat.mortalState("Dead", "Reaped"), "Fauché")
		end)
		T.it("agonie avec le temps restant arrondi au-dessus", function()
			T.expectEqual(HudFormat.mortalState("Agony", nil, 31.2), "Agonie · 32 s")
			T.expectEqual(HudFormat.mortalState("Agony"), "Agonie")
		end)
		T.it("âme échappée précisée pour la Mort seulement", function()
			T.expectEqual(HudFormat.mortalState("Dead", "Escaped", nil, false), "Mort")
			T.expectEqual(HudFormat.mortalState("Dead", "Escaped", nil, true), "Mort · âme échappée")
		end)
		T.it("tiret hors manche", function()
			T.expectEqual(HudFormat.mortalState(nil), "—")
		end)
	end)

	T.describe("HudFormat : panneau de la Mort", function()
		T.it("souffle plein sans recharge", function()
			T.expectEqual(HudFormat.breath(3, 3, nil), "Souffle 3/3")
		end)
		T.it("souffle entamé avec la recharge en secondes", function()
			T.expectEqual(HudFormat.breath(1, 3, 11.3), "Souffle 1/3 · recharge 12 s")
		end)
		T.it("souffle inconnu compté à zéro", function()
			T.expectEqual(HudFormat.breath(nil, 3, nil), "Souffle 0/3")
		end)
		T.it("pièges armés sur la limite", function()
			T.expectEqual(HudFormat.traps(2, 4), "Pièges armés 2/4")
			T.expectEqual(HudFormat.traps(nil, 4), "Pièges armés 0/4")
		end)
		T.it("ombre, lumière, puis dissipation prioritaire", function()
			local shadow, alertShadow = HudFormat.exposure(false, nil)
			T.expectEqual(shadow, "Dans l'ombre : invisible")
			T.expectEqual(alertShadow, false)
			local light, alertLight = HudFormat.exposure(true, nil)
			T.expectEqual(light, "À la lumière : visible et ralentie")
			T.expectEqual(alertLight, true)
			local beam, alertBeam = HudFormat.exposure(true, 0.4)
			T.expectEqual(beam, "Dans le faisceau : dissipation 40 %")
			T.expectEqual(alertBeam, true)
		end)
	end)

	T.describe("HudFormat.battery", function()
		T.it("pourcentage arrondi et état de la lampe", function()
			T.expectEqual(HudFormat.battery(0.734, true), "Lampe 73 % · allumée")
			T.expectEqual(HudFormat.battery(1, false), "Lampe 100 % · éteinte")
			T.expectEqual(HudFormat.battery(0, true), "Lampe 0 % · vide")
		end)
		T.it("nil sans lampe", function()
			T.expectEqual(HudFormat.battery(nil, nil), nil)
		end)
	end)

	T.describe("HudFormat.verdict", function()
		T.it("enfui, fauché, morts avec cause", function()
			T.expectEqual(HudFormat.verdict("Saved"), "Enfui")
			T.expectEqual(HudFormat.verdict("Dead", "Reaped", "Reaped"), "Fauché")
			T.expectEqual(HudFormat.verdict("Dead", "Escaped", "Accident"), "Mort sur le coup · âme échappée")
			T.expectEqual(HudFormat.verdict("Dead", "Escaped", "Agony"), "Mort en agonie · âme échappée")
			T.expectEqual(HudFormat.verdict("Dead", "Escaped", "TimeUp"), "Encore là à l'aube · âme échappée")
			T.expectEqual(HudFormat.verdict("Dead", "Escaped", "Left"), "Parti · âme échappée")
		end)
		T.it("mort sans cause connue", function()
			T.expectEqual(HudFormat.verdict("Dead", "Escaped", nil), "Mort · âme échappée")
		end)
	end)

	T.describe("HudFormat.summary", function()
		local result = {
			reason = "TimeUp",
			death = { userId = 1, name = "Faucheuse" },
			mortals = {
				{ userId = 2, name = "Ana", state = "Saved" },
				{ userId = 3, name = "Bob", state = "Dead", soul = "Reaped", cause = "Reaped" },
				{ userId = 4, name = "Cy", state = "Dead", soul = "Escaped", cause = "TimeUp" },
			},
			saved = 1,
			reaped = 1,
			escaped = 1,
		}

		T.it("titre, une ligne par mortel dans l'ordre, âmes de la Mort", function()
			local summary = HudFormat.summary(result, 3)
			T.expectEqual(summary.title, "La nuit s'achève")
			T.expectEqual(#summary.rows, 3)
			T.expectEqual(summary.rows[1].name, "Ana")
			T.expectEqual(summary.rows[1].verdict, "Enfui")
			T.expectEqual(summary.rows[2].verdict, "Fauché")
			T.expectEqual(summary.rows[3].verdict, "Encore là à l'aube · âme échappée")
			T.expectEqual(summary.souls, "Faucheuse a récolté 1 âme sur 3")
		end)
		T.it("repère le joueur local et la Mort", function()
			local mortal = HudFormat.summary(result, 3)
			T.expectEqual(mortal.rows[2].isLocal, true)
			T.expectEqual(mortal.rows[1].isLocal, false)
			T.expectEqual(mortal.isDeath, false)
			T.expectEqual(HudFormat.summary(result, 1).isDeath, true)
		end)
		T.it("pluriel des âmes et titre de fin anticipée", function()
			local all = {
				reason = "AllResolved",
				death = { userId = 1, name = "Faucheuse" },
				mortals = {
					{ userId = 2, name = "Ana", state = "Dead", soul = "Reaped", cause = "Reaped" },
					{ userId = 3, name = "Bob", state = "Dead", soul = "Reaped", cause = "Reaped" },
				},
				reaped = 2,
			}
			local summary = HudFormat.summary(all, nil)
			T.expectEqual(summary.title, "Tous les mortels ont connu leur sort")
			T.expectEqual(summary.souls, "Faucheuse a récolté 2 âmes sur 2")
		end)
		T.it("compte les âmes des lignes sans décompte du serveur", function()
			local partial = {
				reason = "TimeUp",
				death = { userId = 1 },
				mortals = { { userId = 2, state = "Dead", soul = "Reaped" } },
			}
			local summary = HudFormat.summary(partial, nil)
			T.expectEqual(summary.souls, "La Mort a récolté 1 âme sur 1")
			T.expectEqual(summary.rows[1].name, "2")
		end)
		T.it("nil pour un résultat absent ou illisible", function()
			T.expectEqual(HudFormat.summary(nil, 1), nil)
			T.expectEqual(HudFormat.summary("x", 1), nil)
			T.expectEqual(HudFormat.summary({ reason = "TimeUp" }, 1), nil)
		end)
	end)
end

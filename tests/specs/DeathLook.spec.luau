-- DeathLook : ce que voit un joueur de la Mort (#80) : invisible dans l'ombre, ombre pleine sans faux à la lumière,
-- vrai corps et faux dans le faisceau ; la Mort se voit toujours avec sa faux.
return function(T, Loader)
	local loader = Loader.new()
	local DeathLook = loader:require("src/shared/DeathLook")

	local View, Mode = DeathLook.View, DeathLook.Mode

	-- Cette méthode permet de faire avancer un fondu de `seconds` par frames de 1/60 s lorsque le test mesure sa durée ;
	-- renvoie la valeur atteinte et le temps mis pour atteindre la cible.
	local function run(current, target, rise, fall, seconds)
		local dt, t, reached = 1 / 60, 0, nil
		while t < seconds - 1e-9 do
			current = DeathLook.approach(current, target, rise, fall, dt)
			t += dt
			if reached == nil and current == target then
				reached = t
			end
		end
		return current, reached
	end

	T.describe("DeathLook.mode", function()
		T.it("mortel : invisible dans l'ombre, même tenu par un faisceau", function()
			T.expectEqual(DeathLook.mode(View.Mortal, false, false), Mode.Hidden)
			T.expectEqual(DeathLook.mode(View.Mortal, false, true), Mode.Hidden)
		end)

		T.it("mortel : ombre à la lumière, vrai corps dans le faisceau", function()
			T.expectEqual(DeathLook.mode(View.Mortal, true, false), Mode.Shadow)
			T.expectEqual(DeathLook.mode(View.Mortal, true, true), Mode.Revealed)
		end)

		T.it("la Mort se voit toujours", function()
			T.expectEqual(DeathLook.mode(View.Self, false, false), Mode.Self)
			T.expectEqual(DeathLook.mode(View.Self, true, true), Mode.Self)
		end)
	end)

	T.describe("DeathLook.targets et layers", function()
		-- Cette méthode permet de donner les couches d'un mode, fondus terminés, lorsque le test compare les modes.
		local function settled(view, exposed, inBeam)
			local mode = DeathLook.mode(view, exposed, inBeam)
			local visibility, reveal = DeathLook.targets(mode, exposed)
			return DeathLook.layers(view, visibility, reveal)
		end

		T.it("cachée : rien de dessiné, ni corps, ni faux, ni ombre, ni fumée", function()
			local l = settled(View.Mortal, false, false)
			T.expectEqual(l.body, 1)
			T.expectEqual(l.scythe, 1)
			T.expectEqual(l.fill, 1)
			T.expectEqual(l.outline, 1)
			T.expectEqual(l.smoke, 0)
		end)

		T.it("ombre : corps couvert d'un remplissage presque opaque, sans contour, fumée, pas de faux", function()
			local l = settled(View.Mortal, true, false)
			T.expectEqual(l.body, 0)
			T.expectEqual(l.scythe, 1, "faux cachée")
			T.expectNear(l.fill, DeathLook.SHADOW_FILL)
			T.expect(l.fill < 0.1, "pleine, pas transparente")
			T.expectEqual(l.outline, 1, "aucun liseré (#96)")
			T.expectEqual(l.smoke, 1)
		end)

		T.it("révélée : vrai corps et faux, ombre et fumée retirées", function()
			local l = settled(View.Mortal, true, true)
			T.expectEqual(l.body, 0)
			T.expectEqual(l.scythe, 0)
			T.expectEqual(l.fill, 1)
			T.expectEqual(l.outline, 1)
			T.expectEqual(l.smoke, 0)
		end)

		T.it("la Mort : faux toujours visible, voile de l'ombre à la lumière, aucune fumée", function()
			local dark = settled(View.Self, false, false)
			local lit = settled(View.Self, true, false)
			T.expectEqual(dark.scythe, 0)
			T.expectEqual(dark.body, 0)
			T.expectNear(dark.fill, DeathLook.SELF_VEIL.shadow)
			T.expectNear(lit.fill, DeathLook.SELF_VEIL.light)
			T.expectEqual(lit.scytheFill, lit.fill, "la faux sous le même voile")
			T.expectEqual(dark.smoke, 0)
		end)

		T.it(
			"lanières (#81) : cachées avec le corps, à demi effacées dans l'ombre, pleines révélées et pour la Mort",
			function()
				T.expectEqual(settled(View.Mortal, false, false).tatters, 1)
				T.expectNear(settled(View.Mortal, true, false).tatters, DeathLook.TATTER_FADE)
				T.expect(DeathLook.TATTER_FADE > 0 and DeathLook.TATTER_FADE < 1, "ni pleines ni invisibles")
				T.expectEqual(settled(View.Mortal, true, true).tatters, 0)
				T.expectEqual(settled(View.Self, false, false).tatters, 0)
				T.expectEqual(settled(View.Self, true, false).tatters, 0)
			end
		)

		T.it("à mi-déchirure : la faux apparaît pendant que l'ombre se retire", function()
			local l = DeathLook.layers(View.Mortal, 1, 0.5)
			T.expectNear(l.scythe, 0.5)
			T.expectNear(l.smoke, 0.5)
			T.expect(l.fill > DeathLook.SHADOW_FILL and l.fill < 1)
		end)
	end)

	T.describe("DeathLook.approach", function()
		T.it("déchirure en REVEAL_TIME, ombre refermée en CLOSE_TIME", function()
			local opened, openTime = run(0, 1, DeathLook.REVEAL_TIME, DeathLook.CLOSE_TIME, 2)
			T.expectEqual(opened, 1)
			T.expectNear(openTime, DeathLook.REVEAL_TIME, 1 / 60 + 1e-6)
			local closed, closeTime = run(1, 0, DeathLook.REVEAL_TIME, DeathLook.CLOSE_TIME, 2)
			T.expectEqual(closed, 0)
			T.expectNear(closeTime, DeathLook.CLOSE_TIME, 1 / 60 + 1e-6)
		end)

		T.it("durée nulle : immédiat", function()
			T.expectEqual(DeathLook.approach(0, 1, 0, 0, 1 / 60), 1)
		end)
	end)

	T.describe("DeathLook : téléportation et déchirure", function()
		T.it("une glissade n'est pas un saut, même après une saccade ; une reformation lointaine l'est", function()
			local a = Vector3.new(0, 3, 0)
			T.expect(not DeathLook.jumped(a, a + Vector3.new(4, 0, 0), 0.2), "20 studs/s à 5 images/s")
			T.expect(not DeathLook.jumped(a, a + Vector3.new(16, 0, 0), 0.8), "20 studs/s, frame de 0,8 s")
			T.expect(DeathLook.jumped(a, a + Vector3.new(50, 0, 0), 1 / 60), "reformée à 50 studs")
			T.expect(not DeathLook.jumped(nil, a, 1 / 60), "position inconnue")
			T.expect(not DeathLook.jumped(a, nil, 1 / 60))
		end)

		T.it("cachée après un saut tant qu'elle reste exposée, au plus JUMP_HOLD", function()
			local dt = 1 / 60
			T.expect(DeathLook.holdAfterJump(DeathLook.JUMP_HOLD, true, dt) > 0, "encore exposée (délai d'ombre)")
			T.expectEqual(DeathLook.holdAfterJump(DeathLook.JUMP_HOLD, false, dt), 0, "exposition retombée")
			local remaining, t = DeathLook.JUMP_HOLD, 0
			while remaining > 0 and t < 10 do
				remaining = DeathLook.holdAfterJump(remaining, true, dt)
				t += dt
			end
			T.expectNear(t, DeathLook.JUMP_HOLD, dt + 1e-6, "pas de blocage si elle reste éclairée")
		end)

		T.it("déchirure à l'entrée dans le faisceau, pas quand le faisceau tremble au bord", function()
			T.expect(DeathLook.tears(0, 1, 0, 1), "ombre refermée")
			T.expect(not DeathLook.tears(0, 1, 0.8, 1), "ombre encore ouverte")
			T.expect(not DeathLook.tears(0, 1, 0, 0), "invisible")
			T.expect(not DeathLook.tears(1, 1, 0, 1), "déjà dans le faisceau")
		end)
	end)

	T.describe("DeathLook.bounds", function()
		T.it("mesure bas, haut et rayon dans le repère de la racine, même tournée", function()
			local root = CFrame.new(10, 5, 0) * CFrame.Angles(0, math.rad(90), 0)
			local boxes = {
				{ cframe = root * CFrame.new(0, -1, 0), size = Vector3.new(2, 6, 2) }, -- robe, de -4 à 2
				{ cframe = root * CFrame.new(0, 2.5, 0), size = Vector3.new(1, 1, 1) }, -- capuche, jusqu'à 3
			}
			local b = DeathLook.bounds(root, boxes)
			T.expect(b ~= nil)
			assert(b)
			T.expectNear(b.bottom, -4, 1e-4)
			T.expectNear(b.top, 3, 1e-4)
			T.expectNear(b.radius, math.sqrt(2), 1e-4)
		end)

		T.it("aucune pièce : nil", function()
			T.expectEqual(DeathLook.bounds(CFrame.new(), {}), nil)
		end)

		T.it("braises au bas du corps, volume borné ; fumerolles sur tout le corps", function()
			local bounds = { bottom = -4, top = 3, radius = 1.5 }
			local hemOffset, hemSize = DeathLook.hemBox(bounds)
			T.expectNear(hemSize.Y, 7 * DeathLook.HEM_SHARE, 1e-6)
			T.expectNear(hemOffset.Y - hemSize.Y / 2, -4, 1e-6, "part du bas du corps")
			local _, tall = DeathLook.hemBox({ bottom = -20, top = 20, radius = 1 })
			T.expectEqual(tall.Y, DeathLook.HEM_MAX)
			local bodyOffset, bodySize = DeathLook.bodyBox(bounds)
			T.expectNear(bodyOffset.Y, -0.5, 1e-6)
			T.expect(bodySize.Y < 7, "rentré dans la silhouette")
		end)
	end)

	T.describe("DeathLook : ombre sans nuage, volutes du bas (#90)", function()
		-- Cette méthode permet de donner les couches d'un mode, fondus terminés, lorsque le test vérifie les fumées.
		local function settled(view, exposed, inBeam)
			local mode = DeathLook.mode(view, exposed, inBeam)
			local visibility, reveal = DeathLook.targets(mode, exposed)
			return DeathLook.layers(view, visibility, reveal)
		end

		T.it("les fumées du modèle sont coupées dans l'ombre, rendues avec le vrai corps et pour la Mort", function()
			T.expectEqual(settled(View.Mortal, true, false).modelSmoke, false, "pas de nuage rond autour du bas")
			T.expectEqual(settled(View.Mortal, true, true).modelSmoke, true)
			T.expectEqual(settled(View.Self, true, false).modelSmoke, true)
		end)

		local start = Vector3.new(0, 1, 0)
		local out = Vector3.new(0, 0, 1)
		local floorY = -2

		T.it("immobile : la volute tombe sous son départ, s'écarte un peu de la robe, au-dessus du sol", function()
			local tendril = DeathLook.tendril(start, out, Vector3.zero, 0, 0, 2, floorY)
			T.expect(tendril.finish.Y < start.Y - 1, "elle tombe")
			T.expect(tendril.finish.Y >= floorY + DeathLook.TENDRIL.FLOOR_GAP - 1e-6, "au-dessus du sol")
			T.expect((tendril.finish - start).Magnitude <= 2 + DeathLook.TENDRIL.SWAY + 1e-6, "longueur bornée")
			T.expect(tendril.startCurve > 0, "elle part vers le bas")
		end)

		T.it("en mouvement : elle se couche derrière, d'autant plus que la Mort va vite", function()
			local still = DeathLook.tendril(start, out, Vector3.zero, 0, 0, 2, floorY)
			local slow = DeathLook.tendril(start, out, Vector3.new(5, 0, 0), 0, 0, 2, floorY)
			local fast = DeathLook.tendril(start, out, Vector3.new(16, 0, 0), 0, 0, 2, floorY)
			T.expect(slow.finish.X < still.finish.X, "derrière la Mort qui avance en +X")
			T.expect(fast.finish.X < slow.finish.X, "plus loin derrière à pleine vitesse")
			T.expect(fast.finish.Y > still.finish.Y, "moins tombante : elle traîne")
		end)

		T.it("elle ondule avec le temps, sans dépasser l'amplitude", function()
			local a = DeathLook.tendril(start, out, Vector3.zero, 0, 0, 2, floorY)
			local b = DeathLook.tendril(start, out, Vector3.zero, 1, 0, 2, floorY)
			T.expect((a.finish - b.finish).Magnitude > 0.05, "elle bouge")
			for k = 0, 20 do
				local c = DeathLook.tendril(start, out, Vector3.zero, k * 0.37, 1.1, 2, floorY)
				T.expect(math.abs(c.endCurve) <= DeathLook.TENDRIL.SWAY + 1e-6)
			end
		end)

		T.it("au ras du sol, elle glisse en gardant sa longueur au lieu de s'y enfoncer", function()
			local from = Vector3.new(0, -1.8, 0)
			local low = DeathLook.tendril(from, out, Vector3.zero, 0, 0, 2, floorY)
			T.expectNear(low.finish.Y, floorY + DeathLook.TENDRIL.FLOOR_GAP, 1e-6)
			local flat = Vector3.new(low.finish.X - from.X, 0, low.finish.Z - from.Z)
			T.expect(flat.Magnitude > 1.5, "elle s'étire le long du sol")
		end)

		T.it("les volutes de derrière sont les plus longues", function()
			T.expect(DeathLook.tendrilLength(1) > DeathLook.tendrilLength(0))
			T.expectNear(DeathLook.tendrilLength(0), DeathLook.TENDRIL.FRONT_LENGTH, 1e-6)
			T.expectNear(DeathLook.tendrilLength(2), DeathLook.TENDRIL.BACK_LENGTH, 1e-6, "bornée")
		end)
	end)
end

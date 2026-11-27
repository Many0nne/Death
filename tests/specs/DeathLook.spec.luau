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

		T.it("ombre : corps couvert d'un remplissage presque opaque, contour léger, fumée, pas de faux", function()
			local l = settled(View.Mortal, true, false)
			T.expectEqual(l.body, 0)
			T.expectEqual(l.scythe, 1, "faux cachée")
			T.expectNear(l.fill, DeathLook.SHADOW_FILL)
			T.expect(l.fill < 0.1, "pleine, pas transparente")
			T.expectNear(l.outline, DeathLook.SHADOW_OUTLINE)
			T.expect(l.outline > 0 and l.outline < 1, "contour léger")
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

		T.it("colonne de fumée au bas du corps, bornée ; volutes sur tout le corps", function()
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
end

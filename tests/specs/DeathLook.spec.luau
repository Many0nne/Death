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

		T.it("ombre : vrai corps caché sous une colonne presque opaque, sans contour, fumée, pas de faux", function()
			local l = settled(View.Mortal, true, false)
			T.expectEqual(l.body, 1, "le vrai corps est caché par la colonne (#98)")
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

		T.it("à mi-déchirure : corps et faux apparaissent pendant que la colonne se retire", function()
			local l = DeathLook.layers(View.Mortal, 1, 0.5)
			T.expectNear(l.scythe, 0.5)
			T.expectNear(l.body, 0.5)
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
	end)

	T.describe("DeathLook.column : colonne d'ombre (#98)", function()
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

		-- La Mort de docs/assets.md : racine à 3,65 studs du sol, sommet à 7,4 ; tournée vers -Z
		local floorY = 0
		local root = CFrame.new(0, 3.65, 0)
		-- Cette méthode permet de poser une colonne de test lorsque seuls la vitesse, l'instant et l'ourlet changent.
		local function column(velocity: Vector3?, t: number?, hem: Vector3?)
			return DeathLook.column({
				root = root,
				floorY = floorY,
				top = 7.4,
				hem = hem,
				velocity = velocity or Vector3.zero,
				t = t or 0,
			})
		end
		-- Cette méthode permet de donner les points extrêmes d'un ellipsoïde (sommet, bas, et écart horizontal au centre
		-- de la racine) lorsque le test mesure la silhouette.
		local function extent(piece)
			local half = piece.size / 2
			local top, bottom, reach = -math.huge, math.huge, 0
			for _, axis in { Vector3.xAxis * half.X, Vector3.yAxis * half.Y, Vector3.zAxis * half.Z } do
				for _, sign in { -1, 1 } do
					local p = piece.cframe:PointToWorldSpace(axis * sign)
					top = math.max(top, p.Y)
					bottom = math.min(bottom, p.Y)
					reach = math.max(reach, Vector3.new(p.X, 0, p.Z).Magnitude)
				end
			end
			return top, bottom, reach
		end
		-- Cette méthode permet de mesurer le recul moyen des lobes au sol (vers +Z, derrière une Mort tournée vers -Z)
		-- lorsque le test compare des vitesses.
		local function lobesBack(c)
			local sum, n = 0, 0
			for k = DeathLook.COLUMN.LAYERS + 4, DeathLook.COLUMN.LAYERS + 3 + DeathLook.COLUMN.LOBES do
				sum += c.pieces[k].cframe.Position.Z
				n += 1
			end
			return sum / n
		end

		T.it("toujours le même nombre de morceaux, dans le même ordre", function()
			T.expectEqual(#column().pieces, DeathLook.columnPieces())
			T.expectEqual(#column(Vector3.new(0, 0, -16), 3.7).pieces, DeathLook.columnPieces())
		end)

		T.it("une colonne continue du sol au sommet, chaque morceau recouvre le précédent", function()
			local c = column()
			local L = DeathLook.COLUMN.LAYERS
			local _, bottom = extent(c.pieces[1])
			T.expect(bottom <= floorY, "elle part du sol")
			for k = 2, L + 3 do
				local _, low = extent(c.pieces[k])
				local high = extent(c.pieces[k - 1])
				T.expect(low < high - 0.3, "le morceau " .. k .. " chevauche le précédent")
			end
			local tipTop = extent(c.pieces[L + 3])
			T.expectNear(tipTop, 7.4, 0.15, "pointe de capuche au sommet du corps")
		end)

		T.it("presque informe : largeur à peu près régulière, sans bras qui dépasse", function()
			local c = column()
			local widths = {}
			for k = 2, DeathLook.COLUMN.LAYERS do
				table.insert(widths, c.pieces[k].size.X)
			end
			local lo, hi = math.min(table.unpack(widths)), math.max(table.unpack(widths))
			T.expect(hi / lo < 1.35, "pas de bosse d'épaule ou de bras")
			T.expect(lo > 0.25 * 7.4, "assez large pour avaler le corps")
			local headW = c.pieces[DeathLook.COLUMN.LAYERS + 2].size.X
			T.expect(headW < lo, "la capuche plus étroite que le corps")
			T.expect(c.pieces[DeathLook.COLUMN.LAYERS + 3].size.X < headW * 0.6, "une pointe, pas une boule")
		end)

		T.it("au sol : les lobes débordent un peu, sans flaque ronde", function()
			local c = column()
			local reaches = {}
			for k = DeathLook.COLUMN.LAYERS + 4, DeathLook.COLUMN.LAYERS + 3 + DeathLook.COLUMN.LOBES do
				local piece = c.pieces[k]
				T.expectNear(piece.cframe.Position.Y, floorY, 1e-6, "posé au ras du sol")
				local _, _, reach = extent(piece)
				table.insert(reaches, reach)
			end
			local baseHalf = c.pieces[1].size.X / 2
			local lo, hi = math.min(table.unpack(reaches)), math.max(table.unpack(reaches))
			T.expect(hi > baseHalf, "déborde autour du bas")
			T.expect(hi < baseHalf + 2, "un peu seulement")
			T.expect(hi - lo > 0.2, "lobes inégaux, pas un disque")
		end)

		T.it("en glissant, le bas recule et traîne derrière, d'autant plus qu'elle va vite", function()
			local still = lobesBack(column())
			local slow = lobesBack(column(Vector3.new(0, 0, -5)))
			local fast = lobesBack(column(Vector3.new(0, 0, -16)))
			T.expect(slow > still, "derrière la Mort qui avance vers -Z")
			T.expect(fast > slow + 0.5, "plus loin à pleine vitesse")
			local trainAt = DeathLook.COLUMN.LAYERS + 4 + DeathLook.COLUMN.LOBES
			local train = column(Vector3.new(0, 0, -16)).pieces[trainAt]
			T.expect(train.size.Z > column().pieces[trainAt].size.Z + 1, "la traîne s'allonge")
			local _, _, reach = extent(train)
			T.expect(reach < 6, "traîne bornée")
		end)

		T.it("le bas suit l'ourlet de la cape (os de la robe), les épaules restent sur la racine", function()
			local base = column().pieces[1].cframe.Position
			local swayed = column(nil, nil, Vector3.new(0.6, 1, 0.4))
			local foot = swayed.pieces[1].cframe.Position
			T.expectNear(foot.X - base.X, 0.6, 1e-6)
			T.expectNear(foot.Z - base.Z, 0.4, 1e-6)
			T.expectNear(swayed.pieces[DeathLook.COLUMN.LAYERS].cframe.Position.X, 0, 1e-6)
		end)

		T.it("elle respire avec le temps, sans changer de forme générale", function()
			local a, b = column(nil, 0), column(nil, 1.1)
			T.expect(math.abs(a.pieces[3].size.X - b.pieces[3].size.X) > 0.01, "elle bouge")
			for k = 1, DeathLook.COLUMN.LAYERS do
				T.expectNear(a.pieces[k].size.X, b.pieces[k].size.X, 0.2 * a.pieces[k].size.X)
			end
		end)

		T.it(
			"le bord bouillonne : des bouffées naissent au bord, surtout en bas, s'écartent et se résorbent",
			function()
				local first = DeathLook.columnPieces() - DeathLook.COLUMN.PUFFS + 1
				local low, total, moved = 0, 0, 0
				for step = 0, 40 do
					local t = step * 0.37
					local a, b = column(nil, t), column(nil, t + 0.1)
					for k = first, DeathLook.columnPieces() do
						local piece = a.pieces[k]
						local top, _, reach = extent(piece)
						T.expect(reach < 0.19 * 7.4 + 0.9 + 1.2, "près du bord, pas loin dans la pièce")
						T.expect(top < 7.4, "sous le sommet")
						T.expect(piece.size.X <= 2 * DeathLook.COLUMN.PUFF_SIZE * 1.3 + 1e-6, "petites")
						total += 1
						if piece.cframe.Position.Y < 1 then
							low += 1
						end
						if (b.pieces[k].cframe.Position - piece.cframe.Position).Magnitude > 0.01 then
							moved += 1
						end
					end
				end
				T.expect(low / total > 0.4, "surtout en bas")
				T.expect(moved / total > 0.9, "elles bougent sans cesse")
			end
		)

		T.it("les volumes des fumées couvrent le corps et le ras du sol", function()
			local c = column()
			T.expect(c.body.size.Y > 4, "le bord de toute la colonne")
			T.expect(c.floor.cframe.Position.Y < 1, "au ras du sol")
			T.expect(c.floor.size.X > c.pieces[1].size.X, "plus large que le bas")
		end)
	end)
end

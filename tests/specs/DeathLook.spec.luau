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

		-- La Mort de docs/assets.md : racine à 3,65 studs du sol, sommet à 7,4 ; tournée vers -Z (droite : +X)
		local floorY = 0
		local top = 7.4
		local C = DeathLook.COLUMN
		local headY = floorY + C.HEAD_AT * (top - floorY)
		local root = CFrame.new(0, 3.65, 0)
		-- Cette méthode permet de poser une colonne de test lorsque seuls la vitesse, l'instant, l'ourlet et la caméra
		-- changent.
		local function column(velocity: Vector3?, t: number?, hem: Vector3?, camera: Vector3?)
			return DeathLook.column({
				root = root,
				floorY = floorY,
				top = top,
				hem = hem,
				camera = camera,
				velocity = velocity or Vector3.zero,
				t = t or 0,
			})
		end
		-- Cette méthode permet de donner le bord de la silhouette à la hauteur y lorsque le test mesure le flanc : le plus
		-- loin, le long de `axis` (X : vue de face, Z : de profil), que va la réunion des couches.
		local function edge(c, y: number, axis: Vector3): number
			local best = -math.huge
			for k = 1, C.LAYERS do
				local piece = c.pieces[k]
				local p = piece.cframe.Position
				local half = piece.size / 2
				local dy = (y - p.Y) / half.Y
				if math.abs(dy) < 1 then
					local reach = if axis.X ~= 0 then half.X else half.Z
					best = math.max(best, p:Dot(axis) + reach * math.sqrt(1 - dy * dy))
				end
			end
			return best
		end
		-- Cette méthode permet de mesurer la plus grosse bosse du flanc lorsque le test vérifie qu'il est lisse : à chaque
		-- creux du bord (du pied à la capuche), sa profondeur sous les bords voisins à ±0,8 stud ; une courbe régulière
		-- (évasement, capuche) n'a pas de creux.
		local function bumpiness(c, axis: Vector3): number
			local es = {}
			local y = floorY + 0.3
			while y <= headY - 0.2 do
				table.insert(es, edge(c, y, axis))
				y += 0.05
			end
			local worst = 0
			for i = 2, #es - 1 do
				if es[i] < es[i - 1] and es[i] <= es[i + 1] then
					local left, right = es[i], es[i]
					for j = math.max(1, i - 16), i do
						left = math.max(left, es[j])
					end
					for j = i, math.min(#es, i + 16) do
						right = math.max(right, es[j])
					end
					worst = math.max(worst, math.min(left, right) - es[i])
				end
			end
			return worst
		end

		T.it("toujours le même nombre de morceaux, dans le même ordre", function()
			T.expectEqual(#column().pieces, DeathLook.columnPieces())
			T.expectEqual(#column(Vector3.new(0, 0, -16), 3.7).pieces, DeathLook.columnPieces())
		end)

		T.it(
			"flanc lisse : aucune bosse de plus de 0,05 stud, de face comme de profil, immobile ou penchée",
			function()
				for _, c in
					{ column(), column(nil, 1.7), column(Vector3.new(0, 0, -9), 0.6, Vector3.new(0.3, 1.1, 0.5)) }
				do
					T.expect(bumpiness(c, Vector3.xAxis) < 0.05, "de face : " .. bumpiness(c, Vector3.xAxis))
					T.expect(bumpiness(c, Vector3.zAxis) < 0.05, "de dos : " .. bumpiness(c, Vector3.zAxis))
					T.expect(bumpiness(c, -Vector3.zAxis) < 0.05, "de face (profil) : " .. bumpiness(c, -Vector3.zAxis))
				end
			end
		)

		T.it("profil : évasé progressivement vers le sol, régulier ensuite, rétréci vers la capuche", function()
			local c = column()
			local foot = edge(c, floorY + 0.75, Vector3.xAxis)
			local waist = edge(c, floorY + 0.3 * (headY - floorY), Vector3.xAxis)
			T.expect(foot > waist + 0.2, "le pied s'évase")
			T.expect(edge(c, floorY + C.LIFT - 0.05, Vector3.xAxis) == -math.huge, "pas de contact net avec le sol")
			local previous = math.huge
			local y = floorY + 0.75
			while y <= floorY + 0.3 * (headY - floorY) do
				local e = edge(c, y, Vector3.xAxis)
				T.expect(e <= previous + 0.005, "évasement sans escalier")
				previous = e
				y += 0.05
			end
			local widths = {}
			for u = 0.3, 0.7, 0.05 do
				table.insert(widths, edge(c, floorY + u * (headY - floorY), Vector3.xAxis))
			end
			T.expect(math.max(table.unpack(widths)) - math.min(table.unpack(widths)) < 0.15, "colonne régulière")
			T.expect(waist > 0.25 * 7.4 / 2, "assez large pour avaler le corps")
			T.expect(edge(c, headY, Vector3.xAxis) < waist * 0.75, "la capuche plus étroite que le corps")
		end)

		T.it("pointe de capuche au sommet du corps, plus étroite que la capuche", function()
			local c = column()
			local tip = c.pieces[C.LAYERS + 1]
			local apex = tip.cframe:PointToWorldSpace(Vector3.new(0, tip.size.Y / 2, 0))
			T.expectNear(apex.Y, top, 0.15)
			T.expect(tip.size.X < c.pieces[C.LAYERS].size.X * 0.6, "une pointe, pas une boule")
		end)

		T.it("jupe au ras du sol, pas plus large que le pied + 10 %, sans langue à l'arrêt", function()
			local c = column()
			local skirt = c.pieces[C.LAYERS + 2]
			T.expectNear(skirt.cframe.Position.Y, floorY, 1e-6)
			T.expect(skirt.size.Y <= 0.4, "basse")
			local foot = edge(c, floorY + 0.75, Vector3.xAxis)
			T.expect(skirt.size.X / 2 <= foot * 1.1, "pas plus large que le pied + 10 %")
			local tail = c.pieces[C.LAYERS + 3]
			T.expect(tail.size.X < 0.1 and tail.size.Z < 0.1, "immobile : pas de langue")
		end)

		T.it(
			"en glissant, une langue étroite qui part de sous le pied et s'effile en pointe vers l'arrière",
			function()
				local c = column(Vector3.new(0, 0, -9))
				local tail = c.pieces[C.LAYERS + 3]
				local skirt = c.pieces[C.LAYERS + 2]
				T.expect(tail.size.Z > 2, "longue")
				T.expect(tail.size.X < skirt.size.X, "plus étroite que la jupe")
				local ends = {
					tail.cframe:PointToWorldSpace(Vector3.new(0, 0, -tail.size.Z / 2)),
					tail.cframe:PointToWorldSpace(Vector3.new(0, 0, tail.size.Z / 2)),
				}
				local rear = math.max(ends[1].Z, ends[2].Z)
				T.expect(
					rear > 2.5 and rear < 4.5,
					"pointe 2,5 à 4,5 studs derrière la Mort qui avance vers -Z : " .. rear
				)
				T.expect(
					math.min(ends[1].Z, ends[2].Z) < skirt.cframe.Position.Z + skirt.size.Z / 2,
					"part de sous le pied"
				)
				T.expectNear(tail.cframe.Position.Y, floorY, 1e-6, "au ras du sol")
			end
		)

		T.it("le bas suit l'ourlet de la cape (os de la robe), la capuche reste sur la tête", function()
			local base = column()
			local swayed = column(nil, nil, Vector3.new(0.6, 1, 0.4))
			local foot = swayed.pieces[1].cframe.Position - base.pieces[1].cframe.Position
			T.expectNear(foot.X, 0.6, 1e-6)
			T.expectNear(foot.Z, 0.4, 1e-6)
			local hood = swayed.pieces[C.LAYERS].cframe.Position - base.pieces[C.LAYERS].cframe.Position
			T.expectNear(hood.X, 0, 1e-6)
		end)

		T.it(
			"onde lente : chaque bord bouge à son rythme (3 à 5 s), de 3 à 4 % de la largeur, sans bosse",
			function()
				local y = floorY + 0.45 * (headY - floorY)
				local rights, lefts = {}, {}
				for k = 0, 200 do
					local c = column(nil, k * 0.05)
					table.insert(rights, edge(c, y, Vector3.xAxis))
					table.insert(lefts, edge(c, y, -Vector3.xAxis))
					T.expect(bumpiness(c, Vector3.xAxis) < 0.05, "pas de bosse")
					T.expect(bumpiness(c, -Vector3.xAxis) < 0.05, "pas de bosse à gauche")
				end
				local width = edge(column(), y, Vector3.xAxis)
				local function swing(list)
					return (math.max(table.unpack(list)) - math.min(table.unpack(list))) / 2 / width
				end
				T.expect(swing(rights) > 0.025 and swing(rights) < 0.045, "amplitude à droite : " .. swing(rights))
				T.expect(swing(lefts) > 0.025 and swing(lefts) < 0.045, "amplitude à gauche : " .. swing(lefts))
				-- période : écart moyen entre deux passages par la moyenne, montants
				local function period(list)
					local mean = 0
					for _, v in list do
						mean += v / #list
					end
					local ups = {}
					for k = 2, #list do
						if list[k - 1] < mean and list[k] >= mean then
							table.insert(ups, k * 0.05)
						end
					end
					return (ups[#ups] - ups[1]) / (#ups - 1)
				end
				T.expect(period(rights) > 3 and period(rights) < 5, "période à droite : " .. period(rights))
				T.expect(period(lefts) > 3 and period(lefts) < 5, "période à gauche : " .. period(lefts))
				T.expect(math.abs(period(rights) - period(lefts)) > 0.3, "asymétrique")
				for k = 1, C.LAYERS do
					T.expectNear(column(nil, 0).pieces[k].size.X, column(nil, 1.7).pieces[k].size.X, 0.05 * width * 2)
				end
			end
		)

		T.it(
			"fumées du bord : sur les flancs vus de la caméra, tournées vers l'extérieur, sous les épaules",
			function()
				local camera = Vector3.new(10, 4, 0)
				local c = column(nil, nil, nil, camera)
				T.expectEqual(#c.flanks, 4)
				for k, flank in c.flanks do
					local out = flank.cframe.RightVector
					T.expectNear(out.X, 0, 1e-6, "perpendiculaire au regard")
					local p = flank.cframe.Position
					T.expect(p:Dot(out) > 0.6, "sur le bord, pas dans le cœur (" .. k .. ")")
					T.expect(p:Dot(out) < 1.4, "sur le bord, pas loin dans la pièce (" .. k .. ")")
				end
				T.expect(
					c.flanks[1].cframe.RightVector:Dot(c.flanks[2].cframe.RightVector) < -0.99,
					"un de chaque côté"
				)
				local low, high = c.flanks[1], c.flanks[3]
				local shoulderY = floorY + 0.62 * (headY - floorY)
				T.expect(low.cframe.Position.Y - low.size.Y / 2 < 0.5, "jusqu'au pied")
				T.expect(high.cframe.Position.Y + high.size.Y / 2 < shoulderY, "rien au-dessus des épaules")
			end
		)

		T.it(
			"volumes : déchirure sur le corps, fumée du sol au bord du pied, fumée de la langue derrière",
			function()
				local c = column()
				T.expect(c.body.size.Y > 3, "le corps")
				T.expect(c.floor.cframe.Position.Y < 0.5, "au ras du sol")
				local foot = edge(c, floorY + 0.75, Vector3.xAxis)
				T.expect(
					c.floor.size.X / 2 > foot * 1.2 and c.floor.size.X / 2 < foot * 1.5,
					"plus large que le pied, sans aller loin"
				)
				local moving = column(Vector3.new(0, 0, -9))
				local tail = moving.pieces[C.LAYERS + 3]
				T.expectNear(moving.tail.size.Z, tail.size.Z, 1e-6, "la fumée couvre toute la langue")
				T.expect(moving.tail.cframe.Position.Z > 0, "derrière la Mort qui avance vers -Z")
			end
		)
	end)
end

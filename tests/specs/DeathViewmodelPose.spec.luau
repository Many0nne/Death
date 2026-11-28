-- DeathViewmodelPose (#74) : choix de l'état d'après les événements, poses et cadrage des mains et de la faux de la
-- Mort en première personne (un clone du maillage des mains par main, faux tournée et glissée sur son manche), rendu
-- selon la lumière. Cadrage en fraction de l'écran ((0 ; 0) en haut à gauche) sur une capture de 1611 x 759.
return function(T, Loader)
	local P = Loader.new():require("src/shared/DeathViewmodelPose")
	local M = Loader.new():require("src/shared/ViewmodelMotion")
	local GameConfig = Loader.new():require("src/shared/GameConfig")
	local HudLayout = Loader.new():require("src/shared/HudLayout")
	local State = P.State
	local VIEWPORT = Vector2.new(1611, 759)

	-- Cette méthode permet de relever une boîte de points (repère de la racine du modèle) lorsqu'une main est cadrée :
	-- coins, milieux des arêtes et centre.
	local function box(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, n: number): { Vector3 }
		local points = {}
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				for k = 0, n - 1 do
					local u, v, w = i / (n - 1), j / (n - 1), k / (n - 1)
					table.insert(points, Vector3.new(x0 + (x1 - x0) * u, y0 + (y1 - y0) * v, z0 + (z1 - z0) * w))
				end
			end
		end
		return points
	end

	-- Boîtes englobantes de chaque main du maillage `Hands` (avant-bras court compris, mesurées sur le modèle) :
	-- grossières pour une main vue, fines pour une main qui doit rester cachée
	local LEFT_BOX = { -0.95, -0.6, 0.85, 1.3, -2.95, -1.85 }
	local RIGHT_BOX = { 1.05, 1.65, 0.3, 0.8, -1.45, -0.2 }
	local LEFT_HAND = box(LEFT_BOX[1], LEFT_BOX[2], LEFT_BOX[3], LEFT_BOX[4], LEFT_BOX[5], LEFT_BOX[6], 3)
	local RIGHT_HAND = box(RIGHT_BOX[1], RIGHT_BOX[2], RIGHT_BOX[3], RIGHT_BOX[4], RIGHT_BOX[5], RIGHT_BOX[6], 3)
	local LEFT_HIDDEN = box(LEFT_BOX[1], LEFT_BOX[2], LEFT_BOX[3], LEFT_BOX[4], LEFT_BOX[5], LEFT_BOX[6], 6)
	local RIGHT_HIDDEN = box(RIGHT_BOX[1], RIGHT_BOX[2], RIGHT_BOX[3], RIGHT_BOX[4], RIGHT_BOX[5], RIGHT_BOX[6], 6)
	-- Faux (repère de la racine, mesurée sur le modèle) : pommeau, douille, prise, lame (grille sur son plan)
	local POMMEL = Vector3.new(1.63, -3.52, -1.28)
	local HEAD = Vector3.new(1.37, 3.95, -1.07)
	local GRIP = Vector3.new(1.5, 0.5, -1.2)
	local BLADE_TIP = Vector3.new(-2.0, 2.4, -1.06)
	local BLADE = {}
	for _, x in { -2.0, -1.2, -0.4, 0.4, 1.2 } do
		for _, y in { 1.34, 2.5, 3.64 } do
			table.insert(BLADE, Vector3.new(x, y, -1.06))
		end
	end
	local SHAFT = {}
	for i = 0, 40 do
		table.insert(SHAFT, POMMEL:Lerp(HEAD, i / 40))
	end
	-- Largeur du manche (studs), prise sur ses parties les plus larges, bagues et poignée de cuir (boîtes du modèle,
	-- tools/models/death.measured.json, moins l'inclinaison du manche ; rendu docs/renders/death/v81/textured/hand_close)
	local SHAFT_WIDTH = 0.34
	-- Flottement à t = 0 (les deux mains ont des phases différentes) : écart toléré sur une position imposée à l'écran
	local FLOAT_SLACK = 0.03
	-- Plan proche de la caméra de Roblox (studs) : ce qui est plus près n'est pas dessiné
	local NEAR_PLANE = 0.1

	-- Cette méthode permet de relever la surface d'une manche d'ombre (repère de la racine) lorsqu'elle est cadrée.
	local function sleevePoints(side: string): { Vector3 }
		local frame, size = P.sleeve(side)
		local points = {}
		for i = 0, 16 do
			local u = -1 + 2 * i / 16
			local r = math.sqrt(math.max(0, 1 - u * u))
			for k = 0, 7 do
				local a = k * math.pi / 4
				table.insert(
					points,
					frame * Vector3.new(math.cos(a) * r * size.X / 2, math.sin(a) * r * size.Y / 2, u * size.Z / 2)
				)
			end
		end
		return points
	end
	local SLEEVE = { left = sleevePoints("left"), right = sleevePoints("right") }

	-- Cette méthode permet de passer un point du modèle dans l'espace caméra lorsqu'un groupe est posé.
	local function camera(frame: CFrame, point: Vector3): Vector3
		return frame * (point - P.ANCHOR)
	end

	-- Cette méthode permet de projeter un point de l'espace caméra en fraction de l'écran lorsque le cadrage est
	-- contrôlé ; nil derrière la caméra.
	local function fraction(point: Vector3): Vector2?
		local s = M.project(point, P.FOV, P.ASPECT)
		return s and Vector2.new((s.X + 1) / 2, (1 - s.Y) / 2)
	end

	-- Cette méthode permet de savoir si un point projeté est dans le cadre lorsque le cadrage est contrôlé.
	local function onScreen(f: Vector2?): boolean
		return f ~= nil and f.X >= 0 and f.X <= 1 and f.Y >= 0 and f.Y <= 1
	end

	-- Cette méthode permet de relever les points visibles d'une pose lorsque le cadrage est contrôlé : main et manche
	-- de chaque clone, manche et lame de la faux, en espace caméra, étiquetés.
	local function visible(frames): { { name: string, point: Vector3 } }
		local out = {}
		local function add(name: string, frame: CFrame, points: { Vector3 })
			for _, p in points do
				table.insert(out, { name = name, point = camera(frame, p) })
			end
		end
		add("main gauche", frames.left, LEFT_HAND)
		add("manche gauche", frames.left, SLEEVE.left)
		add("main droite", frames.right, RIGHT_HAND)
		add("manche droite", frames.right, SLEEVE.right)
		add("manche de la faux", frames.scythe, SHAFT)
		add("lame", frames.scythe, BLADE)
		return out
	end

	-- Cette méthode permet de savoir si une main cachée d'un clone reste hors du champ lorsque le cadrage est contrôlé :
	-- toute la boîte de la main (échantillonnée finement) devant la caméra, sans la traverser, et hors du cadre avec
	-- une marge.
	local function hidden(frame: CFrame, points: { Vector3 }): boolean
		for _, p in points do
			local c = camera(frame, p)
			if c.Z > -0.12 then
				return false
			end
			local f = fraction(c) :: Vector2
			if f.X > -0.04 and f.X < 1.04 and f.Y > -0.04 and f.Y < 1.04 then
				return false
			end
		end
		return true
	end

	-- Cette méthode permet de vérifier les règles communes à toutes les poses lorsque le cadrage d'un état est contrôlé :
	-- rien sur le panneau du HUD, l'autre main de chaque clone hors du champ.
	local function checkCommon(frames, label: string)
		for _, e in visible(frames) do
			-- en deçà du plan proche de la caméra (NEAR_PLANE), rien n'est dessiné
			local f = if -e.point.Z >= NEAR_PLANE then fraction(e.point) else nil
			if f then
				T.expect(
					not (f.X > P.HUD_CLEAR.x and f.Y > P.HUD_CLEAR.y),
					string.format("%s : %s sur le panneau du HUD (%.2f ; %.2f)", label, e.name, f.X, f.Y)
				)
			end
		end
		T.expect(hidden(frames.left, RIGHT_HIDDEN), label .. " : main droite du clone gauche dans le champ")
		T.expect(hidden(frames.right, LEFT_HIDDEN), label .. " : main gauche du clone droit dans le champ")
	end

	-- Poses à contrôler : chaque état, échantillonné sur son avancée
	local base = { t = 0, moving = 0 }
	local SAMPLES = { { "repos", P.frames(State.Rest, base) } }
	for _, dir in
		{ Vector3.new(0, 0, -1), Vector3.new(0.6, -0.4, -1), Vector3.new(-1, 0.5, -0.5), Vector3.new(0, -1, -0.3) }
	do
		table.insert(
			SAMPLES,
			{ "main tendue " .. tostring(dir), P.frames(State.Reach, { t = 0, moving = 0, target = dir }) }
		)
	end
	for i = 0, 20 do
		local k = i / 20
		table.insert(
			SAMPLES,
			{ "souffle " .. k, P.frames(State.Blow, { t = 0, moving = 0, blowAge = k * P.BLOW_TIME }) }
		)
		table.insert(SAMPLES, { "fauchage " .. k, P.frames(State.Reap, { t = 0, moving = 0, progress = k }) })
		table.insert(SAMPLES, { "traction " .. k, P.frames(State.Pull, { t = 0, moving = 0, pull = k }) })
	end
	for i = 0, 8 do
		table.insert(SAMPLES, { "flottement " .. i, P.frames(State.Rest, { t = i * 0.6, moving = 1 }) })
	end

	T.describe("DeathViewmodelPose.choose", function()
		T.it("donne le repos sans événement", function()
			T.expectEqual(P.choose({ reaping = false, reaching = false }), State.Rest)
		end)
		T.it("tend la main pendant une invite tenue", function()
			T.expectEqual(P.choose({ reaping = false, reaching = true }), State.Reach)
		end)
		T.it("joue le souffle pendant BLOW_TIME, même main tendue", function()
			T.expectEqual(P.choose({ reaping = false, reaching = true, blowAge = 0.1 }), State.Blow)
			T.expectEqual(P.choose({ reaping = false, reaching = false, blowAge = P.BLOW_TIME }), State.Rest)
		end)
		T.it("fait passer le fauchage avant le souffle, et la lutte avant tout", function()
			T.expectEqual(P.choose({ reaping = true, reaching = false, blowAge = 0.1 }), State.Reap)
			T.expectEqual(P.choose({ pull = 0.5, reaping = true, reaching = true, blowAge = 0.1 }), State.Pull)
		end)
		T.it("fauche le temps de l'invite « Faucher »", function()
			T.expectEqual(P.REAP_TIME, GameConfig.REAP_DURATION)
			T.expectEqual(P.REAP_TIME, 4)
		end)
	end)

	T.describe("DeathViewmodelPose.parseDebug", function()
		T.it("lit un état et sa valeur", function()
			local s, v = P.parseDebug("Reap:0.6")
			T.expectEqual(s, State.Reap)
			T.expectNear(v, 0.6)
			s, v = P.parseDebug("Rest")
			T.expectEqual(s, State.Rest)
			T.expectEqual(v, nil)
		end)
		T.it("refuse une valeur inconnue", function()
			T.expectEqual(P.parseDebug("Dance"), nil)
			T.expectEqual(P.parseDebug(nil), nil)
			T.expectEqual(P.parseDebug(3), nil)
		end)
	end)

	T.describe("DeathViewmodelPose : cadrage dans tous les états", function()
		T.it("laisse dégagé le panneau du rôle du HUD, lu dans HudLayout", function()
			local corner, far = HudLayout.rolePanel(VIEWPORT, HudLayout.DEATH_LINES)
			-- la zone interdite couvre le panneau, avec de la marge
			T.expect(corner.X > P.HUD_CLEAR.x and corner.Y > P.HUD_CLEAR.y, "panneau hors de la zone interdite")
			T.expect(far.X <= 1 and far.Y <= 1, "panneau hors de l'écran")
		end)
		T.it("ne pose aucune pièce sur le panneau et garde l'autre main de chaque clone hors du champ", function()
			for _, sample in SAMPLES do
				checkCommon(sample[2], sample[1])
			end
		end)
	end)

	T.describe("DeathViewmodelPose : cadrage au repos", function()
		local f = P.frames(State.Rest, base)
		T.it("pose les griffes gauches dans le tiers bas à gauche, la main sous y 0,62", function()
			local claw = fraction(P.claw(f.left)) :: Vector2
			T.expect(claw.X > 0.15 and claw.X < 0.4 and claw.Y > 0.62 and claw.Y < 0.9, "griffes mal placées")
			for _, p in LEFT_HAND do
				local s = fraction(camera(f.left, p))
				T.expect(onScreen(s) and s.Y > 0.62, "main gauche au-dessus de y 0,62 ou hors du cadre")
			end
		end)
		T.it("fait entrer chaque manche d'ombre par le bord du cadre (bas ou bas gauche pour la gauche)", function()
			for _, side in { "left", "right" } do
				local spec = P.SLEEVES[side]
				local frame = if side == "left" then f.left else f.right
				local exit: Vector2? = nil
				for i = 0, 60 do
					local s = fraction(camera(frame, spec.wrist + spec.direction * (i / 60 * 3.1)))
					if not onScreen(s) then
						exit = s or Vector2.new(0.5, 2)
						break
					end
				end
				T.expect(exit ~= nil, side .. " : manche qui finit dans le cadre")
				if side == "left" then
					T.expect(
						exit.Y > 0.99 or (exit.X < 0.01 and exit.Y > 0.6),
						string.format("manche gauche sortie en (%.2f ; %.2f)", exit.X, exit.Y)
					)
				end
			end
		end)
		T.it("couvre le bout ouvert de chaque avant-bras par sa manche d'ombre", function()
			for _, side in { "left", "right" } do
				local frame, size = P.sleeve(side)
				local spec = P.SLEEVES[side]
				-- bout ouvert de l'avant-bras : 0,25 stud derrière le poignet, rayon 0,1 environ
				local stump = frame:PointToObjectSpace(spec.wrist + spec.direction * 0.25)
				local r = size / 2
				local q = (stump.X / r.X) ^ 2 + (stump.Y / r.Y) ^ 2 + (stump.Z / r.Z) ^ 2
				T.expect(q < 1, side .. " : bout de l'avant-bras hors de la manche")
				local across = r.X * math.sqrt(1 - (stump.Z / r.Z) ^ 2)
				T.expect(across > 0.12, string.format("%s : manche de %.2f stud au bout de l'avant-bras", side, across))
			end
		end)
		T.it("laisse le centre de l'écran libre", function()
			for _, e in visible(f) do
				local s = fraction(e.point)
				T.expect(not (s and math.abs(s.X - 0.5) < 0.14 and math.abs(s.Y - 0.5) < 0.17), e.name .. " au centre")
			end
		end)
		T.it("garde la lame hors du cadre", function()
			for _, p in BLADE do
				T.expect(not onScreen(fraction(camera(f.scythe, p))), "lame visible au repos")
			end
		end)
		T.it("garde le manche dans le tiers droit, penché de 15 à 25 degrés vers la droite en haut, fin", function()
			local seen = 0
			local half = math.tan(math.rad(P.FOV) / 2)
			for _, p in SHAFT do
				local c = camera(f.scythe, p)
				local s = fraction(c)
				if onScreen(s) then
					seen += 1
					T.expect(s.X > 0.68, string.format("manche à x %.2f", s.X))
					-- largeur à l'écran : SHAFT_WIDTH, celle des bagues et de la poignée (les plus larges)
					local px = SHAFT_WIDTH * VIEWPORT.Y / (2 * half * -c.Z)
					T.expect(px <= 70, string.format("manche de %.0f px", px))
				end
			end
			T.expect(seen >= 6, "manche peu visible")
			-- inclinaison à l'écran (en pixels) de l'axe du manche, autour de la prise
			local axis = P.SCYTHE_AXIS
			local a = fraction(f.right * axis.point) :: Vector2
			local b = fraction(f.right * (axis.point + axis.direction)) :: Vector2
			local tilt = math.deg(math.atan2((b.X - a.X) * VIEWPORT.X, (a.Y - b.Y) * VIEWPORT.Y))
			T.expect(tilt >= 15 and tilt <= 25, string.format("manche penché de %.1f degrés", tilt))
		end)
		T.it("fait du groupe faux le clone droit tourné et glissé sur l'axe du manche", function()
			local onAxis = P.SCYTHE_AXIS.point + P.SCYTHE_AXIS.direction * 1.5
			local shifted = P.SCYTHE_AXIS.direction * P.REST.slide
			T.expectNear(((f.right * (onAxis + shifted)) - (f.scythe * onAxis)).Magnitude, 0, 1e-5)
			T.expect((P.twist(P.REST.twist) * Vector3.new(-1, 0, 0)).Z > 0.9, "lame vers l'arrière au repos")
		end)
	end)

	T.describe("DeathViewmodelPose.frames : états", function()
		T.it("amène les griffes vers une cible au centre, sous le centre", function()
			local f = P.frames(State.Reach, { t = 0, moving = 0, target = Vector3.new(0, 0, -1) })
			local claw = M.project(P.claw(f.left), P.FOV, P.ASPECT)
			T.expect(claw ~= nil and claw.Y <= P.REACH.maxY + FLOAT_SLACK, "griffes au-dessus de leur zone")
			local rest = M.project(P.claw(P.frames(State.Rest, base).left), P.FOV, P.ASPECT)
			T.expect(claw.X > rest.X + 0.2, "main pas tendue")
		end)
		T.it("garde les griffes dans leur zone même vers une cible de côté ou derrière", function()
			for _, dir in { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 1, -0.1), Vector3.zero } do
				local f = P.frames(State.Reach, { t = 0, moving = 0, target = dir })
				local s = M.project(P.claw(f.left), P.FOV, P.ASPECT)
				local r = P.REACH
				T.expect(
					s ~= nil
						and s.X >= r.minX - FLOAT_SLACK
						and s.X <= r.maxX + FLOAT_SLACK
						and s.Y >= r.minY - FLOAT_SLACK
						and s.Y <= r.maxY + FLOAT_SLACK,
					"hors zone"
				)
			end
		end)
		T.it("ne bouge que la main gauche pour se tendre", function()
			local f = P.frames(State.Reach, { t = 0, moving = 0, target = Vector3.new(0, 0, -1) })
			local rest = P.frames(State.Rest, base)
			T.expectNear((f.right.Position - rest.right.Position).Magnitude, 0, 1e-6)
			T.expect((f.left.Position - rest.left.Position).Magnitude > 0.2, "main gauche immobile")
		end)
		T.it("pousse les mains au milieu du souffle et les ramène à la fin", function()
			local mid = P.frames(State.Blow, { t = 0, moving = 0, blowAge = P.BLOW_TIME / 2 })
			local done = P.frames(State.Blow, { t = 0, moving = 0, blowAge = P.BLOW_TIME })
			local rest = P.frames(State.Rest, base)
			T.expect((P.claw(mid.left) - P.claw(rest.left)).Magnitude > 0.35, "geste trop faible")
			T.expectNear((done.left.Position - rest.left.Position).Magnitude, 0, 1e-6)
			T.expectNear((done.right.Position - rest.right.Position).Magnitude, 0, 1e-6)
		end)
		T.it("fait paraître la lame en haut puis la fait descendre pendant le fauchage", function()
			local start = P.frames(State.Reap, { t = 0, moving = 0, progress = 0 })
			local rest = P.frames(State.Rest, base)
			T.expectNear((start.scythe.Position - rest.scythe.Position).Magnitude, 0, 1e-6)
			local armed = P.frames(State.Reap, { t = 0, moving = 0, progress = 0.7 })
			local tipArmed = fraction(camera(armed.scythe, BLADE_TIP))
			T.expect(onScreen(tipArmed) and tipArmed.Y < 0.4, "lame pas armée en haut")
			local cut = P.frames(State.Reap, { t = 0, moving = 0, progress = 1 })
			local tipCut = fraction(camera(cut.scythe, BLADE_TIP))
			T.expect(tipCut ~= nil and tipCut.Y > tipArmed.Y + 0.25, "la lame ne descend pas")
		end)
		T.it("crochète la lame devant pendant la lutte et ramène la faux vers soi", function()
			local a = P.frames(State.Pull, { t = 0, moving = 0, pull = 0 })
			local b = P.frames(State.Pull, { t = 0, moving = 0, pull = 1 })
			T.expect(onScreen(fraction(camera(a.scythe, BLADE_TIP))), "lame invisible pendant la lutte")
			T.expect(b.right.Position.Z > a.right.Position.Z + 0.4, "pas de traction")
		end)
		T.it("tremble pendant la lutte, peu", function()
			local a = P.frames(State.Pull, { t = 0.1, moving = 0, pull = 0.5 })
			local b = P.frames(State.Pull, { t = 0.13, moving = 0, pull = 0.5 })
			local d = (a.right.Position - b.right.Position).Magnitude
			T.expect(d > 0.001 and d < 0.08, string.format("tremblement de %.3f", d))
		end)
	end)

	T.describe("DeathViewmodelPose.look", function()
		T.it("voile et allège dans l'ombre, rend tout à la lumière", function()
			local t0, f0 = P.look(0)
			local t1, f1 = P.look(1)
			T.expect(t0 > 0 and f0 < 1, "ombre : discrète")
			T.expectNear(t1, 0)
			T.expectNear(f1, 1)
			local tm = P.look(0.5)
			T.expect(tm > t1 and tm < t0, "fondu")
		end)
	end)
end

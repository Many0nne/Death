-- DeathViewmodelPose (#74) : choix de l'état d'après les événements, poses et cadrage des mains et de la faux de la
-- Mort en première personne, rendu selon la lumière.
return function(T, Loader)
	local P = Loader.new():require("src/shared/DeathViewmodelPose")
	local M = Loader.new():require("src/shared/ViewmodelMotion")
	local GameConfig = Loader.new():require("src/shared/GameConfig")
	local State = P.State

	-- Points du modèle de la Mort (repère de la racine, mesurés dans Studio sur ReplicatedStorage.Characters.Death) :
	-- ancres (pièces LeftHand, RightHand du rig) et points à cadrer
	local ANCHOR = {
		left = Vector3.new(-0.76, 1.2, -2.32),
		right = Vector3.new(1.27, 0.5, -0.97),
		scythe = Vector3.new(1.27, 0.5, -0.97),
	}
	local POINTS = {
		leftHand = { "left", Vector3.new(-0.76, 1.2, -2.32) },
		leftClaw = { "left", Vector3.new(-0.8, 1.2, -2.9) },
		leftElbow = { "left", Vector3.new(-0.87, 1.14, -1.1) },
		grip = { "right", Vector3.new(1.5, 0.5, -1.2) },
		rightElbow = { "right", Vector3.new(1.19, 0.7, -0.1) },
		head = { "scythe", Vector3.new(1.37, 3.95, -1.07) },
		pommel = { "scythe", Vector3.new(1.63, -3.52, -1.28) },
		bladeTip = { "scythe", Vector3.new(-2.0, 2.4, -1.06) },
	}

	-- Cette méthode permet de projeter un point du modèle à l'écran lorsque le cadrage d'un état est contrôlé.
	local function screen(frames, name: string): Vector2?
		local spec = POINTS[name]
		local cam = frames[spec[1]] * (spec[2] - ANCHOR[spec[1]])
		return M.project(cam, P.FOV, P.ASPECT)
	end

	-- Cette méthode permet de savoir si un point projeté est dans un rectangle de l'écran lorsque le cadrage est
	-- contrôlé (nil, derrière la caméra, n'y est jamais).
	local function inside(s: Vector2?, x0: number, x1: number, y0: number, y1: number): boolean
		return s ~= nil and s.X >= x0 and s.X <= x1 and s.Y >= y0 and s.Y <= y1
	end

	local function offscreen(s: Vector2?): boolean
		return s == nil or math.abs(s.X) > 1 or math.abs(s.Y) > 1
	end

	local base = { t = 0, moving = 0 }

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

	T.describe("DeathViewmodelPose.frames : cadrage au repos", function()
		local f = P.frames(State.Rest, base)
		T.it("pose la main gauche en bas à gauche et la prise de la faux à droite", function()
			T.expect(inside(screen(f, "leftHand"), -0.7, -0.15, -0.8, -0.3), "main gauche")
			T.expect(inside(screen(f, "grip"), 0.2, 0.6, -0.8, -0.3), "main droite")
		end)
		T.it("laisse le centre de l'écran libre", function()
			for name in POINTS do
				T.expect(not inside(screen(f, name), -0.25, 0.25, -0.3, 0.3), name .. " au centre")
			end
		end)
		T.it("n'empiète pas sur l'indicateur ombre / lumière (coin bas droit)", function()
			for name in POINTS do
				T.expect(not inside(screen(f, name), 0.47, 1, -1, -0.66), name .. " sous l'indicateur")
			end
		end)
		T.it("couvre le bout ouvert de chaque avant-bras par sa manche d'ombre, qui sort du champ", function()
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
				-- l'autre bout de la manche est hors de l'écran
				local far = spec.wrist + spec.direction * (P.SLEEVE.length - P.SLEEVE.lead)
				local cam = f[side] * far
				T.expect(offscreen(M.project(cam, P.FOV, P.ASPECT)), side .. " : bout de la manche dans le champ")
			end
		end)
		T.it("garde la lame hors du champ, derrière la tête, et le haut du manche au-dessus de l'écran", function()
			T.expect(offscreen(screen(f, "bladeTip")), "pointe de la lame visible")
			T.expect(offscreen(screen(f, "head")), "douille visible")
		end)
		T.it("fait du groupe faux la pose du bras droit tournée sur le manche", function()
			local turned = f.right * P.twist(P.REST.twist)
			T.expectNear((turned.Position - f.scythe.Position).Magnitude, 0, 1e-9)
			-- un point de l'axe du manche ne bouge pas
			local onAxis = P.SCYTHE_AXIS.point + P.SCYTHE_AXIS.direction * 1.5
			T.expectNear(((f.right * onAxis) - (f.scythe * onAxis)).Magnitude, 0, 1e-6)
		end)
		T.it("tourne la lame vers l'arrière au repos", function()
			local blade = P.twist(P.REST.twist) * Vector3.new(-1, 0, 0)
			T.expect(blade.Z > 0.9, "lame vers l'arrière")
		end)
	end)

	T.describe("DeathViewmodelPose.frames : états", function()
		T.it("tend la main vers une cible au centre, sous le centre", function()
			local f = P.frames(State.Reach, { t = 0, moving = 0, target = Vector3.new(0, 0, -1) })
			local hand = screen(f, "leftHand")
			T.expect(hand ~= nil and hand.Y <= P.REACH.maxY + 0.01, "main au-dessus de sa zone")
			T.expect(hand ~= nil and hand.X > screen(P.frames(State.Rest, base), "leftHand").X, "main pas tendue")
		end)
		T.it("garde la main tendue dans sa zone même vers une cible de côté ou derrière", function()
			for _, dir in { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 1, -0.1), Vector3.zero } do
				local s = screen(P.frames(State.Reach, { t = 0, moving = 0, target = dir }), "leftHand")
				T.expect(
					inside(s, P.REACH.minX - 0.01, P.REACH.maxX + 0.01, P.REACH.minY - 0.01, P.REACH.maxY + 0.01),
					"hors zone"
				)
			end
		end)
		T.it("pousse la main gauche au milieu du souffle et la ramène à la fin", function()
			local mid = P.frames(State.Blow, { t = 0, moving = 0, blowAge = P.BLOW_TIME / 2 })
			local done = P.frames(State.Blow, { t = 0, moving = 0, blowAge = P.BLOW_TIME })
			local rest = P.frames(State.Rest, base)
			T.expect((mid.left.Position - rest.left.Position).Magnitude > 0.4, "geste trop faible")
			T.expectNear((done.left.Position - rest.left.Position).Magnitude, 0, 1e-6)
		end)
		T.it("fait passer la lame devant pendant le fauchage, du repos à la taille", function()
			local start = P.frames(State.Reap, { t = 0, moving = 0, progress = 0 })
			local rest = P.frames(State.Rest, base)
			T.expectNear((start.scythe.Position - rest.scythe.Position).Magnitude, 0, 1e-6)
			local armed = P.frames(State.Reap, { t = 0, moving = 0, progress = 0.7 })
			T.expect(not offscreen(screen(armed, "bladeTip")), "lame invisible au fauchage")
			local cut = P.frames(State.Reap, { t = 0, moving = 0, progress = 1 })
			T.expect(screen(cut, "bladeTip").Y < screen(armed, "bladeTip").Y, "la lame ne descend pas")
		end)
		T.it("amène la main gauche sur le manche pendant le fauchage et la lutte", function()
			for _, frames in
				{
					P.frames(State.Reap, { t = 0, moving = 0, progress = 1 }),
					P.frames(State.Pull, { t = 0, moving = 0, pull = 0.5 }),
				}
			do
				local grip = frames.right * P.LEFT_GRIP
				T.expectNear((frames.left.Position - grip.Position).Magnitude, 0, 1e-6)
			end
		end)
		T.it("ramène la faux vers soi à mesure que l'âme sort", function()
			local a = P.frames(State.Pull, { t = 0, moving = 0, pull = 0 })
			local b = P.frames(State.Pull, { t = 0, moving = 0, pull = 1 })
			T.expect(b.right.Position.Z > a.right.Position.Z + 0.4, "pas de traction")
		end)
		T.it("tremble pendant la lutte, peu", function()
			local a = P.frames(State.Pull, { t = 0.1, moving = 0, pull = 0.5 })
			local b = P.frames(State.Pull, { t = 0.13, moving = 0, pull = 0.5 })
			local d = (a.right.Position - b.right.Position).Magnitude
			T.expect(d > 0.001 and d < 0.08, string.format("tremblement de %.3f", d))
		end)
		T.it("pose le maillage des mains entre les deux mains", function()
			local f = P.frames(State.Rest, base)
			T.expectNear((f.core.Position - f.left.Position:Lerp(f.right.Position, 0.5)).Magnitude, 0, 1e-9)
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

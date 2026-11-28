-- DeathViewmodelPose (#74) : choix de l'état d'après les événements, poses et cadrage des mains et de la faux de la
-- Mort en première personne (bloc rigide et faux tournée sur son manche), rendu selon la lumière.
return function(T, Loader)
	local P = Loader.new():require("src/shared/DeathViewmodelPose")
	local M = Loader.new():require("src/shared/ViewmodelMotion")
	local GameConfig = Loader.new():require("src/shared/GameConfig")
	local State = P.State

	-- Points du modèle de la Mort à cadrer (repère de la racine, mesurés dans Studio sur ReplicatedStorage.Characters.Death)
	local POINTS = {
		claw = { "rig", P.CLAW },
		leftWrist = { "rig", Vector3.new(-0.78, 1.2, -2.12) },
		grip = { "rig", Vector3.new(1.5, 0.5, -1.2) },
		head = { "scythe", Vector3.new(1.37, 3.95, -1.07) },
		pommel = { "scythe", Vector3.new(1.63, -3.52, -1.28) },
		bladeTip = { "scythe", Vector3.new(-2.0, 2.4, -1.06) },
	}

	-- Cette méthode permet de projeter un point du modèle à l'écran lorsque le cadrage d'un état est contrôlé.
	local function screen(frames, name: string): Vector2?
		local spec = POINTS[name]
		return M.project(frames[spec[1]] * (spec[2] - P.ANCHOR), P.FOV, P.ASPECT)
	end

	-- Cette méthode permet de savoir si un point projeté est dans un rectangle de l'écran lorsque le cadrage est
	-- contrôlé (nil, derrière la caméra, n'y est jamais).
	local function inside(s: Vector2?, x0: number, x1: number, y0: number, y1: number): boolean
		return s ~= nil and s.X >= x0 and s.X <= x1 and s.Y >= y0 and s.Y <= y1
	end

	-- Cette méthode permet de savoir si un point projeté est hors de l'écran lorsque le cadrage est contrôlé.
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
		T.it("pose les griffes gauches en bas à gauche et la prise de la faux à droite", function()
			T.expect(inside(screen(f, "claw"), -0.7, -0.25, -0.7, -0.2), "griffes")
			T.expect(inside(screen(f, "grip"), 0.25, 0.47, -0.6, -0.3), "prise de la faux")
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
		T.it("garde la lame et le haut du manche hors du champ, le manche presque vertical à droite", function()
			T.expect(offscreen(screen(f, "bladeTip")), "pointe de la lame visible")
			T.expect(offscreen(screen(f, "head")), "douille visible")
			-- le manche traverse l'écran à droite du centre, en haut comme en bas
			local grip, head, pommel = screen(f, "grip"), screen(f, "head"), screen(f, "pommel")
			T.expect(head ~= nil and head.X > 0.2 and pommel ~= nil and pommel.X > 0.2, "manche vers le centre")
			T.expect(math.abs(head.X - grip.X) < 0.15 and math.abs(pommel.X - grip.X) < 0.15, "manche trop penché")
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
				T.expect(
					offscreen(M.project(f.rig * (far - P.ANCHOR), P.FOV, P.ASPECT)),
					side .. " : bout dans le champ"
				)
			end
		end)
		T.it("fait du groupe faux le bloc tourné sur l'axe du manche", function()
			local onAxis = P.SCYTHE_AXIS.point + P.SCYTHE_AXIS.direction * 1.5
			T.expectNear(((f.rig * onAxis) - (f.scythe * onAxis)).Magnitude, 0, 1e-6)
			T.expect((P.twist(P.REST.twist) * Vector3.new(-1, 0, 0)).Z > 0.9, "lame vers l'arrière au repos")
		end)
	end)

	T.describe("DeathViewmodelPose.frames : états", function()
		T.it("amène les griffes vers une cible au centre, sous le centre", function()
			local f = P.frames(State.Reach, { t = 0, moving = 0, target = Vector3.new(0, 0, -1) })
			local claw = screen(f, "claw")
			T.expect(claw ~= nil and claw.Y <= P.REACH.maxY + 0.01, "griffes au-dessus de leur zone")
			T.expect(claw.X > screen(P.frames(State.Rest, base), "claw").X + 0.2, "main pas tendue")
		end)
		T.it("garde les griffes dans leur zone même vers une cible de côté ou derrière", function()
			for _, dir in { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 1, -0.1), Vector3.zero } do
				local s = screen(P.frames(State.Reach, { t = 0, moving = 0, target = dir }), "claw")
				local r = P.REACH
				T.expect(inside(s, r.minX - 0.01, r.maxX + 0.01, r.minY - 0.01, r.maxY + 0.01), "hors zone")
			end
		end)
		T.it("pousse les mains au milieu du souffle et les ramène à la fin", function()
			local mid = P.frames(State.Blow, { t = 0, moving = 0, blowAge = P.BLOW_TIME / 2 })
			local done = P.frames(State.Blow, { t = 0, moving = 0, blowAge = P.BLOW_TIME })
			local rest = P.frames(State.Rest, base)
			T.expect((mid.rig.Position - rest.rig.Position).Magnitude > 0.35, "geste trop faible")
			T.expectNear((done.rig.Position - rest.rig.Position).Magnitude, 0, 1e-6)
		end)
		T.it("fait paraître la lame puis la fait descendre pendant le fauchage", function()
			local start = P.frames(State.Reap, { t = 0, moving = 0, progress = 0 })
			local rest = P.frames(State.Rest, base)
			T.expectNear((start.scythe.Position - rest.scythe.Position).Magnitude, 0, 1e-6)
			T.expect(offscreen(screen(start, "bladeTip")), "lame visible au départ")
			local armed = P.frames(State.Reap, { t = 0, moving = 0, progress = 0.7 })
			local tipArmed = screen(armed, "bladeTip")
			T.expect(not offscreen(tipArmed) and tipArmed.Y > 0.2, "lame pas armée en haut")
			local cut = P.frames(State.Reap, { t = 0, moving = 0, progress = 1 })
			T.expect(screen(cut, "bladeTip").Y < tipArmed.Y - 0.5, "la lame ne descend pas")
		end)
		T.it("crochète la lame devant pendant la lutte et ramène la faux vers soi", function()
			local a = P.frames(State.Pull, { t = 0, moving = 0, pull = 0 })
			local b = P.frames(State.Pull, { t = 0, moving = 0, pull = 1 })
			T.expect(not offscreen(screen(a, "bladeTip")), "lame invisible pendant la lutte")
			T.expect(b.rig.Position.Z > a.rig.Position.Z + 0.4, "pas de traction")
		end)
		T.it("tremble pendant la lutte, peu", function()
			local a = P.frames(State.Pull, { t = 0.1, moving = 0, pull = 0.5 })
			local b = P.frames(State.Pull, { t = 0.13, moving = 0, pull = 0.5 })
			local d = (a.rig.Position - b.rig.Position).Magnitude
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

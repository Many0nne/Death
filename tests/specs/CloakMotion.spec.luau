-- CloakMotion : la cape de la Mort ondule au repos et traîne derrière elle quand elle glisse.
return function(T, Loader)
	local loader = Loader.new()
	local CloakMotion = loader:require("src/shared/CloakMotion")

	-- Cette méthode permet de mesurer où pend le bas d'un os après rotation lorsqu'on compare deux situations.
	local function tip(t, chain, bone, velocity)
		return CloakMotion.boneRotation(t, chain, bone, velocity):VectorToWorldSpace(Vector3.new(0, -1, 0))
	end

	-- Cette méthode permet de donner l'angle (radians) entre la verticale et un os tourné.
	local function tilt(t, chain, bone, velocity)
		return math.acos(math.clamp(-tip(t, chain, bone, velocity).Y, -1, 1))
	end

	T.describe("CloakMotion.parseBone", function()
		T.it("lit la chaîne et le rang d'un os de lambeau", function()
			local chain, bone = CloakMotion.parseBone("C07_2")
			T.expectEqual(chain, 7)
			T.expectEqual(bone, 2)
		end)

		T.it("ignore l'os racine et les autres noms", function()
			T.expectEqual(CloakMotion.parseBone("Root"), nil)
			T.expectEqual(CloakMotion.parseBone("C7"), nil)
		end)
	end)

	T.describe("CloakMotion.outward", function()
		T.it("chaîne 0 devant (-Z), chaîne CHAINS/4 à droite (+X)", function()
			T.expect(CloakMotion.outward(0):FuzzyEq(Vector3.new(0, 0, -1), 1e-6))
			T.expect(CloakMotion.outward(CloakMotion.CHAINS / 4):FuzzyEq(Vector3.new(1, 0, 0), 1e-6))
		end)
	end)

	T.describe("CloakMotion.boneRotation", function()
		local still = Vector3.zero

		T.it("au repos, la cape ondule encore (jamais figée) mais reste près de la verticale", function()
			local seen = 0
			for k = 0, 40 do
				local a = tilt(k * 0.1, 3, CloakMotion.BONES - 1, still)
				seen = math.max(seen, a)
				T.expect(a <= CloakMotion.FLAP_IDLE * 1.2 + 1e-6, "ondulation bornée")
			end
			T.expect(seen > CloakMotion.FLAP_IDLE * 0.5, "elle bouge")
		end)

		T.it("le haut de la chaîne bouge moins que le bas", function()
			local top, bottom = 0, 0
			for k = 0, 40 do
				top = math.max(top, tilt(k * 0.1, 5, 0, still))
				bottom = math.max(bottom, tilt(k * 0.1, 5, CloakMotion.BONES - 1, still))
			end
			T.expect(top < bottom)
		end)

		T.it("en glissant vers l'avant, le bas de la robe part vers l'arrière (+Z)", function()
			local forward = Vector3.new(0, 0, -CloakMotion.FULL_SPEED)
			local back = CloakMotion.CHAINS / 2
			local sum = 0
			for k = 0, 20 do
				sum += tip(k * 0.1, back, 2, forward).Z
			end
			T.expect(sum / 21 > 0.1, "moyenne vers l'arrière")
		end)

		T.it("le côté qui traîne se soulève plus que le côté qui fend l'air", function()
			local forward = Vector3.new(0, 0, -CloakMotion.FULL_SPEED)
			local backChain, frontChain = CloakMotion.CHAINS / 2, 0
			local backTilt, frontTilt = 0, 0
			for k = 0, 20 do
				backTilt += tilt(k * 0.1, backChain, 1, forward)
				frontTilt += tilt(k * 0.1, frontChain, 1, forward)
			end
			T.expect(backTilt > frontTilt)
		end)

		T.it("la traîne grandit avec la vitesse et plafonne à FULL_SPEED", function()
			local back = CloakMotion.CHAINS / 2
			-- Cette méthode permet de moyenner l'inclinaison sur une période pour effacer l'ondulation.
			local function mean(speed)
				local sum = 0
				for k = 0, 40 do
					sum += tilt(k * 0.05, back, 1, Vector3.new(0, 0, -speed))
				end
				return sum / 41
			end
			T.expect(mean(5) < mean(15))
			T.expect(math.abs(mean(CloakMotion.FULL_SPEED) - mean(CloakMotion.FULL_SPEED * 3)) < 1e-6)
		end)

		T.it("ignore la vitesse verticale (chute, saut)", function()
			local a = CloakMotion.boneRotation(1.3, 4, 2, Vector3.new(0, -30, 0))
			local b = CloakMotion.boneRotation(1.3, 4, 2, still)
			T.expect(a.LookVector:FuzzyEq(b.LookVector, 1e-6))
		end)
	end)
end

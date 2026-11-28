-- DeathSight : vue de la Mort dans l'ombre (#69) : réservée au rôle Mort, plus claire que la nuit des mortels, lampes
-- reconnaissables, mortels en jeu repérés, brûlure à l'exposition.
return function(T, Loader)
	local loader = Loader.new()
	local Sight = loader:require("src/shared/DeathSight")
	local Night = loader:require("src/shared/NightLighting")
	local Match = loader:require("src/shared/Match")

	local S = Match.MortalState

	-- Cette méthode permet de mesurer la luminance relative (0 à 1) d'une couleur lorsque le test compare deux teintes.
	local function luminance(c: Color3): number
		return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	end

	T.describe("DeathSight.active", function()
		T.it("seul le rôle Mort voit dans l'ombre", function()
			T.expect(Sight.active("Death"))
			T.expect(not Sight.active("Mortal"))
			T.expect(not Sight.active(nil))
		end)
	end)

	T.describe("DeathSight.isPrey", function()
		T.it("montre un mortel en jeu et un agonisant", function()
			T.expect(Sight.isPrey("Mortal", S.Alive))
			T.expect(Sight.isPrey("Mortal", nil)) -- bac à sable de Studio, hors manche
			T.expect(Sight.isPrey(nil, S.Agony))
		end)

		T.it("ne montre ni la Mort, ni un mort, ni un sauvé, ni un joueur hors rôle", function()
			T.expect(not Sight.isPrey("Death", nil))
			T.expect(not Sight.isPrey(nil, S.Dead))
			T.expect(not Sight.isPrey(nil, S.Saved))
			T.expect(not Sight.isPrey(nil, nil))
		end)
	end)

	T.describe("DeathSight.lighting", function()
		T.it("l'ombre de la Mort est nettement plus claire que celle des mortels", function()
			local ratio = luminance(Sight.lighting.Ambient) / luminance(Night.lighting.Ambient)
			T.expect(ratio >= 1.6, string.format("rapport de lumière ambiante %.2f", ratio))
			T.expect(Sight.atmosphere.Density < Night.atmosphere.Density)
		end)

		T.it("teinte propre au rôle : ombre violette (bleu au-dessus du vert)", function()
			local a = Sight.lighting.Ambient
			T.expect(a.B > a.G and a.R > a.G)
		end)

		T.it(
			"ne règle que des propriétés que la nuit commune règle aussi (rétablies en quittant le rôle)",
			function()
				for property in Sight.lighting do
					T.expect(Night.lighting[property] ~= nil, property)
				end
				for property in Sight.atmosphere do
					T.expect(Night.atmosphere[property] ~= nil, property)
				end
			end
		)
	end)

	T.describe("DeathSight.gradeAt", function()
		T.it("dans l'ombre, la correction de l'ombre ; exposée, celle de la lumière", function()
			local shadow, light = Sight.gradeAt(0), Sight.gradeAt(1)
			T.expectNear(shadow.Saturation, Sight.grade.shadow.Saturation)
			T.expectNear(light.Brightness, Sight.grade.light.Brightness)
			T.expect(shadow.TintColor == Sight.grade.shadow.TintColor)
			T.expect(light.TintColor == Sight.grade.light.TintColor)
		end)

		T.it("borne la brûlure entre 0 et 1 et mélange à mi-chemin", function()
			T.expectNear(Sight.gradeAt(-1).Contrast, Sight.grade.shadow.Contrast)
			T.expectNear(Sight.gradeAt(2).Contrast, Sight.grade.light.Contrast)
			local half = Sight.gradeAt(0.5)
			T.expectNear(half.Saturation, (Sight.grade.shadow.Saturation + Sight.grade.light.Saturation) / 2)
		end)

		T.it("ombre froide, lumière chaude : l'exposition se lit comme un danger", function()
			local cold, warm = Sight.grade.shadow.TintColor, Sight.grade.light.TintColor
			T.expect(cold.B > cold.R, "ombre froide")
			T.expect(warm.R > warm.B, "lumière chaude")
		end)

		T.it("les lampes de la Mort brûlent : rouges à travers la teinte de l'ombre, plus fortes", function()
			local lamp = Sight.lamp.Color
			local tint = Sight.grade.shadow.TintColor
			T.expect(lamp.R * tint.R > 2 * lamp.B * tint.B, "lampe filtrée nettement plus rouge que bleue")
			local night = Night.lampColor
			T.expect(lamp.R / lamp.B > night.R / night.B, "plus rouge que la lampe des mortels")
			T.expect(Sight.lamp.brightnessFactor > 1)
		end)
	end)

	T.describe("DeathSight.silhouette", function()
		T.it("silhouette pâle, voilée au remplissage, nette au contour", function()
			T.expect(Sight.silhouette.FillTransparency > Sight.silhouette.OutlineTransparency)
			T.expect(luminance(Sight.silhouette.OutlineColor) > 0.8)
		end)
	end)
end

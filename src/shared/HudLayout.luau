-- Disposition du panneau du rôle du HUD (bas droite : ombre / lumière, souffle, pièges armés de la Mort ; batterie du
-- mortel), en points d'interface. Partagée par Client.Hud, qui le construit, et par les contrôles de cadrage du
-- viewmodel (Shared.DeathViewmodelPose, tests Lune), qui doivent le laisser dégagé.
local HudLayout = {}

HudLayout.ROLE_PANEL = table.freeze({
	margin = 12, -- écart aux bords droit et bas de l'écran
	width = 330,
	padding = 6, -- marge intérieure haute et basse (10 à gauche et à droite)
	spacing = 2, -- écart entre deux lignes
	lineExtra = 6, -- hauteur d'une ligne : taille du texte + lineExtra
})

-- Tailles de texte des lignes du panneau de la Mort, dans l'ordre (lumière, souffle, pièges armés)
HudLayout.DEATH_LINES = table.freeze({ 17, 16, 16 })

-- Cette méthode permet de donner le rectangle du panneau du rôle en fraction de l'écran ((0 ; 0) en haut à gauche)
-- lorsque le cadrage d'un viewmodel est contrôlé, pour un écran de `viewport` points et les tailles de texte `lines`.
function HudLayout.rolePanel(viewport: Vector2, lines: { number }): (Vector2, Vector2)
	local p = HudLayout.ROLE_PANEL
	local height = 2 * p.padding + p.spacing * math.max(#lines - 1, 0)
	for _, size in lines do
		height += size + p.lineExtra
	end
	local right, bottom = viewport.X - p.margin, viewport.Y - p.margin
	return Vector2.new((right - p.width) / viewport.X, (bottom - height) / viewport.Y),
		Vector2.new(right / viewport.X, bottom / viewport.Y)
end

return HudLayout

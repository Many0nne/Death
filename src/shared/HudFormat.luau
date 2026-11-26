-- Présentation du HUD de manche et de l'écran de fin (#9, docs/parcours-joueur.md « Interface en manche » et « Le
-- Bilan ») : textes et valeurs affichés, calculés depuis les attributs répliqués. Sans Instance Roblox (testable sous
-- Lune) ; Client.Hud lit les attributs et pose ces textes, sans rien décider.
local Match = require(script.Parent.Match)

local HudFormat = {}

-- Sous ce temps restant (secondes), le sablier affiche aussi des chiffres ; au-dessus, la barre seule
HudFormat.CLOCK_THRESHOLD = 60
-- État d'un mortel parti pendant la manche (sa ligne reste à sa place dans la liste)
HudFormat.LEFT = "Parti"

local State = Match.MortalState
local Cause = Match.DeathCause

local ROLE_LABELS = { [Match.Role.Death] = "La Mort", [Match.Role.Mortal] = "Mortel" }
-- Cause d'une âme échappée, dans le bilan (la cause Reaped s'affiche « Fauché »)
local CAUSE_LABELS = {
	[Cause.Accident] = "Mort sur le coup",
	[Cause.Agony] = "Mort en agonie",
	[Cause.TimeUp] = "Encore là à l'aube",
	[Cause.Left] = "Parti",
}
local REASON_LABELS = {
	[Match.EndReason.TimeUp] = "La nuit s'achève",
	[Match.EndReason.AllResolved] = "Tous les mortels ont connu leur sort",
}

export type SummaryRow = { name: string, verdict: string, isLocal: boolean }
export type Summary = { title: string, rows: { SummaryRow }, souls: string, isDeath: boolean }

-- Cette méthode permet d'écrire une durée en minutes et secondes (« 4:05 ») lorsque le HUD affiche un temps restant ;
-- arrondie à la seconde au-dessus, jamais négative.
function HudFormat.clock(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Cette méthode permet de calculer le sablier (part restante de 0 à 1, et chiffres sous une minute seulement) lorsque
-- le HUD lit MatchTimeLeft et MatchDuration ; renvoie 0 et nil hors manche.
function HudFormat.hourglass(timeLeft: number?, duration: number?): (number, string?)
	if timeLeft == nil or duration == nil or duration <= 0 then
		return 0, nil
	end
	local fraction = math.clamp(timeLeft / duration, 0, 1)
	local text = if timeLeft <= HudFormat.CLOCK_THRESHOLD then HudFormat.clock(timeLeft) else nil
	return fraction, text
end

-- Cette méthode permet de nommer un rôle (Match.Role) lorsque le HUD l'affiche ; nil hors rôle.
function HudFormat.role(role: string?): string?
	return if role then ROLE_LABELS[role] else nil
end

-- Cette méthode permet de nommer l'état d'un mortel en manche lorsque le HUD liste les mortels : `agonyLeft` (secondes)
-- complète l'agonie ; le sort de l'âme (fauchée ou échappée) n'est dit qu'à la Mort (`forDeath`), qui suit ses âmes.
function HudFormat.mortalState(state: string?, soul: string?, agonyLeft: number?, forDeath: boolean?): string
	if state == State.Alive then
		return "Vivant"
	elseif state == State.Agony then
		return if agonyLeft then string.format("Agonie · %d s", math.max(0, math.ceil(agonyLeft))) else "Agonie"
	elseif state == State.Saved then
		return "Enfui"
	elseif state == State.Dead then
		if not forDeath then
			return "Mort"
		end
		return if soul == Match.SoulFate.Reaped then "Fauché" else "Mort · âme échappée"
	end
	return "—"
end

-- Cette méthode permet d'écrire les charges de souffle de la Mort et la recharge en cours lorsque son HUD se met à
-- jour ; `rechargeLeft` (secondes) est nil quand le souffle est plein.
function HudFormat.breath(charges: number?, max: number, rechargeLeft: number?): string
	local text = string.format("Souffle %d/%d", charges or 0, max)
	if rechargeLeft and rechargeLeft > 0 and (charges or 0) < max then
		text ..= string.format(" · recharge %d s", math.ceil(rechargeLeft))
	end
	return text
end

-- Cette méthode permet d'écrire le nombre de pièges armés de la Mort sur la limite lorsque son HUD se met à jour.
function HudFormat.traps(armed: number?, max: number): string
	return string.format("Pièges armés %d/%d", armed or 0, max)
end

-- Cette méthode permet d'écrire la batterie de la lampe torche d'un mortel (de 0 à 1) et son état lorsque son HUD se
-- met à jour ; nil sans lampe (hors rôle).
function HudFormat.battery(level: number?, on: boolean?): string?
	if level == nil then
		return nil
	end
	local percent = math.clamp(math.floor(level * 100 + 0.5), 0, 100)
	local stateText = if percent == 0 then "vide" elseif on then "allumée" else "éteinte"
	return string.format("Lampe %d %% · %s", percent, stateText)
end

-- Cette méthode permet de dire à la Mort si elle est exposée (et la dissipation en cours, de 0 à 1) lorsque son HUD se
-- met à jour ; le booléen renvoyé dit s'il faut l'alerte (lumière ou faisceau).
function HudFormat.exposure(exposed: boolean?, dispel: number?): (string, boolean)
	if dispel and dispel > 0 then
		return string.format("Dans le faisceau : dissipation %d %%", math.floor(dispel * 100 + 0.5)), true
	end
	if exposed then
		return "À la lumière : visible et ralentie", true
	end
	return "Dans l'ombre : invisible", false
end

-- Cette méthode permet de donner le sort d'un mortel dans le bilan lorsque l'écran de fin le liste : enfui, fauché,
-- ou mort avec sa cause (âme échappée).
function HudFormat.verdict(state: string?, soul: string?, cause: string?): string
	if state == State.Saved then
		return "Enfui"
	end
	if state == State.Dead then
		if soul == Match.SoulFate.Reaped or cause == Cause.Reaped then
			return "Fauché"
		end
		local label = cause and CAUSE_LABELS[cause]
		return (label or "Mort") .. " · âme échappée"
	end
	return "—"
end

-- Cette méthode permet de construire l'écran de fin (titre, une ligne par mortel, âmes de la Mort, joueur local repéré)
-- lorsque la manche passe en phase Ended, depuis MatchAttributes.Result décodé ; nil si le résultat est illisible.
function HudFormat.summary(result: any, localUserId: number?): Summary?
	if type(result) ~= "table" or type(result.mortals) ~= "table" then
		return nil
	end
	local rows = {}
	local reaped = 0
	for _, mortal in result.mortals do
		if type(mortal) == "table" then
			local verdict = HudFormat.verdict(mortal.state, mortal.soul, mortal.cause)
			if verdict == "Fauché" then
				reaped += 1
			end
			table.insert(rows, {
				name = tostring(mortal.name or mortal.userId or "?"),
				verdict = verdict,
				isLocal = localUserId ~= nil and mortal.userId == localUserId,
			})
		end
	end
	-- Le décompte du serveur fait foi ; à défaut, celui des lignes
	if type(result.reaped) == "number" then
		reaped = result.reaped
	end
	local death = if type(result.death) == "table" then result.death else {}
	local isDeath = localUserId ~= nil and death.userId == localUserId
	-- La Mort lit sa propre moisson ; les mortels, celle de la Mort nommée
	local who = if isDeath then "Tu as" else tostring(death.name or "La Mort") .. " a"
	local souls = string.format("%s récolté %d âme%s sur %d", who, reaped, if reaped > 1 then "s" else "", #rows)
	return {
		title = REASON_LABELS[result.reason] or "Fin de la manche",
		rows = rows,
		souls = souls,
		isDeath = isDeath,
	}
end

return HudFormat

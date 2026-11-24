-- Règles pures de la Mort face à la lumière (docs/design.md « La Mort », « Lumière ») : vitesse, exposition, droit de
-- préparer un piège, rôle effectif pour les actions de lumière, et réglages du disjoncteur et des ampoules.
-- « D'ombre en ombre » : la Mort marche librement ; dans l'ombre elle est invisible pour les mortels, rapide et
-- silencieuse ; à la lumière elle apparaît en silhouette et ralentit. La lumière révèle, elle ne bloque pas.
-- Bac à sable (Studio, hors manche) : le joueur DebugDeath joue la Mort, les autres des mortels ; jeu publié hors
-- manche : personne n'agit sur la lumière.
local DeathRules = {}

-- Réglages de départ, à ajuster en test (les mortels marchent à 16, vitesse par défaut de Roblox)
DeathRules.SPEED_SHADOW = 20
DeathRules.SPEED_LIGHT = 9
DeathRules.MORTAL_SPEED = 16
-- Temps dans l'ombre avant de redevenir invisible : évite le clignotement au bord d'une zone éclairée
DeathRules.SHADOW_GRACE = 0.3

-- Disjoncteur (cave) : une seule aile coupée à la fois, recharge après chaque rétablissement
DeathRules.BREAKER_COOLDOWN = 20
DeathRules.CUT_HOLD = 1
DeathRules.RESTORE_HOLD = 3
DeathRules.BREAKER_DISTANCE = 8
-- Ampoules : toute la pièce grille d'un coup, recharge entre deux pièces
DeathRules.BURN_COOLDOWN = 20
DeathRules.BURN_HOLD = 1.5
DeathRules.LAMP_DISTANCE = 16
-- Marge de latence acceptée par le serveur sur la distance d'une action déclenchée par le client
DeathRules.DISTANCE_TOLERANCE = 4

-- Rôle effectif pour la lumière (attribut LightRole du joueur)
DeathRules.Role = table.freeze({ Death = "Death", Mortal = "Mortal" })

export type RoleContext = {
	running: boolean, -- une manche est en cours
	matchRole: string?, -- Match.Role du joueur dans la manche
	alive: boolean, -- mortel vivant (pas en agonie, mort ni sauvé)
	isStudio: boolean,
	debugDeath: boolean, -- attribut DebugDeath : jouer la Mort sans manche (Studio)
}

-- Cette méthode permet de décider qui agit comme la Mort ou comme mortel sur la lumière lorsque la manche change :
-- en manche, selon le rôle tiré (un mortel doit être vivant), sinon selon le bac à sable ci-dessus.
function DeathRules.lightRole(ctx: RoleContext): string?
	if ctx.running then
		if ctx.matchRole == DeathRules.Role.Death then
			return DeathRules.Role.Death
		elseif ctx.matchRole == DeathRules.Role.Mortal and ctx.alive then
			return DeathRules.Role.Mortal
		end
		return nil
	end
	if ctx.isStudio then
		return if ctx.debugDeath then DeathRules.Role.Death else DeathRules.Role.Mortal
	end
	return nil
end

-- Cette méthode permet de donner la vitesse de marche de la Mort lorsqu'elle entre dans la lumière ou en sort.
function DeathRules.speed(exposed: boolean): number
	return if exposed then DeathRules.SPEED_LIGHT else DeathRules.SPEED_SHADOW
end

-- Cette méthode permet de savoir si la Mort peut préparer un piège à un endroit lorsque #5 lance une préparation :
-- jamais dans la lumière ambiante.
function DeathRules.canPrepare(illumination, position: Vector3): boolean
	return not illumination:isLit(position)
end

export type Exposure = { exposed: boolean, shadowTime: number }

-- Cette méthode permet de créer le suivi d'exposition de la Mort lorsqu'elle prend le rôle (dans l'ombre au départ).
function DeathRules.newExposure(): Exposure
	return { exposed = false, shadowTime = 0 }
end

-- Cette méthode permet de mettre à jour l'exposition à chaque frame lorsque l'on sait si la Mort est éclairée :
-- exposée dès qu'elle entre dans la lumière, cachée après SHADOW_GRACE secondes d'ombre continue.
function DeathRules.updateExposure(state: Exposure, lit: boolean, dt: number): boolean
	if lit then
		state.exposed = true
		state.shadowTime = 0
	elseif state.exposed then
		state.shadowTime += dt
		if state.shadowTime >= DeathRules.SHADOW_GRACE then
			state.exposed = false
			state.shadowTime = 0
		end
	end
	return state.exposed
end

return DeathRules

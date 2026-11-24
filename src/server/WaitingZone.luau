-- Zone d'attente (#11) : plateforme en blocs gris au sud de la maison, avec le seul SpawnLocation de la place. Les
-- joueurs y apparaissent en rejoignant le serveur (retardataires compris, spectateurs sans rôle) et y reviennent à la
-- fin de la manche (Server.MatchSpawner). Séparée de la maison par le vide : on ne peut pas y entrer à pied.
local WaitingZone = {}

WaitingZone.MODEL_NAME = "WaitingZone"
-- Plateforme : sol à y = 0 comme le rez-de-chaussée, centre à 30 studs au sud de la façade (z = 0)
WaitingZone.CENTER = Vector3.new(40, 0, -30)
WaitingZone.SIZE = 32 -- côté de la plateforme carrée
local WALL_HEIGHT = 8 -- plus haut qu'un saut (≈ 6,4 studs)
local THICKNESS = 1
local COLOR = Color3.fromRGB(110, 110, 114)

-- Cette méthode permet de poser un bloc gris ancré de la zone lorsque l'on construit le sol ou un muret.
local function block(parent: Instance, name: string, center: Vector3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = CFrame.new(center)
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = COLOR
	part.Parent = parent
	return part
end

-- Cette méthode permet de construire la zone d'attente sous parent (Workspace en jeu) lorsque le serveur démarre ;
-- une zone déjà présente est remplacée. Renvoie le modèle « WaitingZone ».
function WaitingZone.build(parent: Instance): Model
	local old = parent:FindFirstChild(WaitingZone.MODEL_NAME)
	if old then
		old:Destroy()
	end
	local zone = Instance.new("Model")
	zone.Name = WaitingZone.MODEL_NAME
	local c, s = WaitingZone.CENTER, WaitingZone.SIZE
	block(zone, "Floor", c - Vector3.new(0, THICKNESS / 2, 0), Vector3.new(s, THICKNESS, s))
	local h = WALL_HEIGHT / 2
	local half = (s - THICKNESS) / 2
	block(zone, "WallSouth", c + Vector3.new(0, h, -half), Vector3.new(s, WALL_HEIGHT, THICKNESS))
	block(zone, "WallNorth", c + Vector3.new(0, h, half), Vector3.new(s, WALL_HEIGHT, THICKNESS))
	block(zone, "WallWest", c + Vector3.new(-half, h, 0), Vector3.new(THICKNESS, WALL_HEIGHT, s - 2 * THICKNESS))
	block(zone, "WallEast", c + Vector3.new(half, h, 0), Vector3.new(THICKNESS, WALL_HEIGHT, s - 2 * THICKNESS))

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(c + Vector3.new(0, 0.1, 0))
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = COLOR
	spawn.Parent = zone

	zone.Parent = parent
	return zone
end

-- Cette méthode permet de renvoyer le point où renvoyer le `n`-ième joueur lorsqu'il revient de la maison : cercle
-- de 8 studs autour du centre, 3 studs au-dessus du sol (le personnage tombe sur ses pieds).
function WaitingZone.spot(n: number): CFrame
	local angle = (n - 1) * (2 * math.pi / 8)
	local offset = Vector3.new(math.cos(angle) * 8, 3, math.sin(angle) * 8)
	return CFrame.new(WaitingZone.CENTER + offset)
end

-- Cette méthode permet de savoir si une position est sur la plateforme lorsque l'on décide de renvoyer un joueur
-- (les spectateurs déjà dans la zone ne bougent pas).
function WaitingZone.contains(position: Vector3): boolean
	local d = position - WaitingZone.CENTER
	local half = WaitingZone.SIZE / 2
	return math.abs(d.X) <= half and math.abs(d.Z) <= half and d.Y > -2 and d.Y < 20
end

return WaitingZone

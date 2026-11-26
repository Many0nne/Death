-- Captures versionnées de la carte (docs/captures/), prises dans Studio via le MCP depuis des points de vue fixes :
-- vues d'ensemble et coupes par niveau (VIEWS), plus une vue par pièce intérieure calculée depuis Shared.HouseLayout.
-- Procédure complète : docs/captures/README.md. Sous-commandes (lune run tools/captures -- <commande>) :
--   install                       code Luau qui installe _G.DeathCapture (une fois par Play, execute_luau Server)
--   list                          par vue : appel de mise en scène, camera_position, look_at_position
--   save <vue> <image> [...]      copie des captures (jpg du MCP) vers docs/captures/ ; plusieurs paires possibles
--   stamp                         empreinte des sources de la carte et galerie des pièces du README : captures à jour
--   --check                       échoue si une source de la carte a changé depuis `stamp` ou si une vue n'a pas
--                                 d'image (tools/check.sh)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/lib/Loader")

local HouseLayout = Loader.new():require("src/shared/HouseLayout")

local OUT_DIR = "docs/captures"
local STAMP_PATH = OUT_DIR .. "/sources.sha256"
local README_PATH = OUT_DIR .. "/README.md"
local SCENE_PATH = "tools/captures.scene.luau"
local ROOMS_BEGIN = "<!-- pieces:debut (généré par lune run tools/captures -- stamp) -->"
local ROOMS_END = "<!-- pieces:fin -->"

-- Sources dont dépend le rendu de la carte : en changer une demande de reprendre les captures.
-- Les .luau sont extraits en CRLF partout (.gitattributes) : l'empreinte est la même sous Windows et en CI.
local SOURCES = {
	"src/shared/HouseLayout.luau",
	"src/shared/HouseGeometry.luau",
	"src/shared/HouseStyle.luau",
	"src/shared/NightLighting.luau",
	"src/server/HouseBuilder.luau",
	"src/server/NightAmbience.luau",
}

type View = {
	name: string,
	file: string,
	label: string,
	light: string,
	cut: number?,
	camera: { number },
	lookAt: { number },
}

-- Points de vue fixes. Terrain : x -12..104, z -16..90 (HouseLayout.bounds), rue côté z bas. Sols des niveaux en
-- y = -12, 0, 12 (LEVEL_HEIGHT 12) : une coupe à sol + 10 garde les murs et retire plafond et niveaux supérieurs.
-- Vue de dessus : le décalage de 1 en z évite une caméra exactement verticale (haut de l'image = côté rue).
local VIEWS: { View } = {
	{
		name = "ensemble-rue",
		label = "Ensemble côté rue (jour)",
		light = "jour",
		camera = { -25, 72, -35 },
		lookAt = { 46, 0, 37 },
	},
	{
		name = "ensemble-jardin",
		label = "Ensemble côté jardin (jour)",
		light = "jour",
		camera = { 117, 72, 109 },
		lookAt = { 46, 0, 37 },
	},
	{
		-- Cadrée sur l'emprise de la cave (x 38..92), plus petite que la maison
		name = "niveau-cave",
		label = "Cave en coupe (jour)",
		light = "jour",
		cut = -2,
		camera = { 65, 52, 26 },
		lookAt = { 65, -12, 25 },
	},
	{
		name = "niveau-rdc",
		label = "Rez-de-chaussée en coupe (jour)",
		light = "jour",
		cut = 10,
		camera = { 46, 95, 38 },
		lookAt = { 46, 0, 37 },
	},
	{
		name = "niveau-etage",
		label = "Étage en coupe (jour)",
		light = "jour",
		cut = 22,
		camera = { 46, 107, 38 },
		lookAt = { 46, 12, 37 },
	},
	{
		name = "nuit-rue",
		label = "Façade depuis la rue, éclairage du jeu (nuit)",
		light = "nuit",
		camera = { 10, 14, -50 },
		lookAt = { 50, 6, 10 },
	},
} :: any
for _, v in VIEWS do
	v.file = v.name .. ".jpg"
end

-- Vue d'une pièce : plongée d'au moins 65° depuis le côté rue (z bas), recul selon la profondeur et la largeur de la pièce
-- (image 16:9, champ vertical 70°), coupe au-dessus de son niveau le plus haut (cages d'escalier : palier du haut,
-- la volée du bas reste visible). Les pièces voisines restent visibles autour, pour situer la pièce.
local PITCH = math.rad(65)
local VIEW_HEIGHT = 10 -- coupe à sol + 10 : murs gardés, plafond retiré
local EYE = 1 -- point visé un peu au-dessus du sol

-- Cette méthode permet de calculer la vue d'une pièce intérieure lorsque l'on construit la liste des vues.
local function roomView(room): View
	local floorY = (room.level + (room.levels or 1) - 1) * HouseLayout.LEVEL_HEIGHT
	local cx, cz = (room.x0 + room.x1) / 2, (room.z0 + room.z1) / 2
	local w, d = room.x1 - room.x0, room.z1 - room.z0
	local dist = math.max(d, w * 0.55) + 6
	local function round(n: number): number
		return math.floor(n * 10 + 0.5) / 10
	end
	-- Caméra au-dessus de la pièce, jamais derrière son mur proche (il masquerait le bas de l'image)
	local back = math.min(dist * math.cos(PITCH), d / 2 - 1)
	local id = string.lower(room.id)
	return {
		name = "piece-" .. id,
		file = "pieces/" .. id .. ".jpg",
		label = room.name,
		light = "jour",
		cut = floorY + VIEW_HEIGHT,
		camera = { round(cx), round(floorY + EYE + dist * math.sin(PITCH)), round(cz - back) },
		lookAt = { round(cx), floorY + EYE, round(cz) },
	}
end

-- Vues des pièces groupées par coupe (une seule mise en scène par groupe), dans l'ordre de HouseLayout.rooms
local ROOM_VIEWS: { View } = {}
local order: { [View]: number } = {}
for _, room in HouseLayout.rooms do
	if not room.outdoor then
		local v = roomView(room)
		table.insert(ROOM_VIEWS, v)
		order[v] = #ROOM_VIEWS
	end
end
table.sort(ROOM_VIEWS, function(a, b)
	if a.cut ~= b.cut then
		return (a.cut :: number) < (b.cut :: number)
	end
	return order[a] < order[b]
end)
local ALL: { View } = table.clone(VIEWS)
for _, v in ROOM_VIEWS do
	table.insert(ALL, v)
end

-- Cette méthode permet de retrouver une vue par son nom lorsqu'une sous-commande le reçoit, ou d'arrêter avec la
-- liste des noms connus.
local function findView(name: string?): View
	for _, v in ALL do
		if v.name == name then
			return v
		end
	end
	print("vue inconnue : " .. tostring(name) .. " (lune run tools/captures -- list)")
	process.exit(1)
	error("inaccessible")
end

-- Cette méthode permet de calculer l'empreinte des sources de la carte lorsque l'on enregistre ou vérifie la fraîcheur
-- des captures (une ligne « sha256  chemin » par source).
local function stamp(): string
	local lines = {}
	for _, path in SOURCES do
		table.insert(lines, serde.hash("sha256", fs.readFile(path)) .. "  " .. path)
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Cette méthode permet d'écrire la galerie des pièces du README lorsque l'on enregistre les captures (une ligne par
-- pièce, par niveau).
local function roomsGallery(): string
	local lines = { ROOMS_BEGIN, "", "| Pièce | Niveau | Capture |", "|---|---|---|" }
	for _, room in HouseLayout.rooms do
		if not room.outdoor then
			local id = string.lower(room.id)
			table.insert(
				lines,
				string.format("| %s | %s | ![](pieces/%s.jpg) |", room.name, HouseLayout.levels[room.level], id)
			)
		end
	end
	table.insert(lines, "")
	table.insert(lines, ROOMS_END)
	return table.concat(lines, "\n")
end

-- Cette méthode permet d'écrire un vecteur au format attendu par screen_capture lorsque l'on liste les vues.
local function vec(v: { number }): string
	return "[" .. table.concat(v, ", ") .. "]"
end

-- Cette méthode permet d'écrire l'appel de mise en scène d'une vue lorsque l'on liste les vues.
local function sceneCall(v: View): string
	return string.format(
		'return _G.DeathCapture({ light = "%s", cut = %s })',
		v.light,
		if v.cut then tostring(v.cut) else "nil"
	)
end

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
local command = args[1]

if table.find(args, "--check") then
	local problems = {}
	local current = if fs.isFile(STAMP_PATH) then string.gsub(fs.readFile(STAMP_PATH), "\r", "") else ""
	if current ~= stamp() then
		table.insert(problems, "les sources de la carte ont changé depuis docs/captures/sources.sha256")
	end
	for _, v in ALL do
		if not fs.isFile(OUT_DIR .. "/" .. v.file) then
			table.insert(problems, "capture manquante : docs/captures/" .. v.file .. " (vue " .. v.name .. ")")
		end
	end
	if #problems == 0 then
		print("ok")
		return
	end
	print("captures de la carte à reprendre :")
	for _, p in problems do
		print("  " .. p)
	end
	print("procédure : docs/captures/README.md (Studio, puis lune run tools/captures -- stamp)")
	process.exit(1)
elseif command == "install" then
	print((string.gsub(fs.readFile(SCENE_PATH), "\r", "")))
elseif command == "list" then
	-- Une ligne de scène seulement quand elle change : les vues qui la partagent se capturent à la suite
	local last = nil
	for _, v in ALL do
		local call = sceneCall(v)
		if call ~= last then
			print("scène : " .. call)
			last = call
		end
		print(string.format("  %-22s camera_position %s  look_at_position %s", v.name, vec(v.camera), vec(v.lookAt)))
	end
elseif command == "save" then
	if #args < 3 or #args % 2 ~= 1 then
		print("usage : save <vue> <image> [<vue> <image> ...]")
		process.exit(1)
	end
	for i = 2, #args, 2 do
		local v = findView(args[i])
		local src = args[i + 1]
		if not fs.isFile(src) then
			print("image introuvable : " .. src)
			process.exit(1)
		end
		local dest = OUT_DIR .. "/" .. v.file
		fs.writeDir((string.match(dest, "^(.*)/[^/]+$")) :: string)
		fs.copy(src, dest, true)
		print("écrit " .. dest)
	end
elseif command == "stamp" then
	fs.writeDir(OUT_DIR)
	fs.writeFile(STAMP_PATH, stamp())
	local readme = string.gsub(fs.readFile(README_PATH), "\r", "")
	local b, e = string.find(readme, ROOMS_BEGIN, 1, true), select(2, string.find(readme, ROOMS_END, 1, true))
	if not b or not e then
		print("marqueurs de la galerie des pièces absents de " .. README_PATH)
		process.exit(1)
	end
	fs.writeFile(README_PATH, string.sub(readme, 1, b - 1) .. roomsGallery() .. string.sub(readme, e + 1))
	print("écrit " .. STAMP_PATH .. " et la galerie des pièces de " .. README_PATH)
else
	print("usage : lune run tools/captures -- install | list | save <vue> <image> [...] | stamp | --check")
	process.exit(1)
end

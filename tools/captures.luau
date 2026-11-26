-- Captures versionnées de la carte (docs/captures/), prises dans Studio via le MCP depuis des points de vue fixes.
-- Procédure complète : docs/captures/README.md. Sous-commandes (lune run tools/captures -- <commande>) :
--   list                 points de vue : nom, lumière, coupe, caméra
--   scene <vue>          code Luau à exécuter en Play, contexte Server (execute_luau), avant screen_capture
--   save <vue> <image>   copie la capture (jpg du MCP) vers docs/captures/<vue>.jpg
--   stamp                enregistre l'empreinte des sources de la carte : les captures sont à jour
--   --check              échoue si les sources de la carte ont changé depuis le dernier `stamp` (tools/check.sh)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local OUT_DIR = "docs/captures"
local STAMP_PATH = OUT_DIR .. "/sources.sha256"
local SCENE_PATH = "tools/captures.scene.luau"

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

-- Points de vue fixes. Terrain : x -12..104, z -16..90 (HouseLayout.bounds), rue côté z bas. Sols des niveaux en
-- y = -12, 0, 12 (LEVEL_HEIGHT 12) : une coupe à sol + 10 garde les murs et retire plafond et niveaux supérieurs.
-- Vue de dessus : le décalage de 1 en z évite une caméra exactement verticale (haut de l'image = côté rue).
local VIEWS = {
	{
		name = "ensemble-rue",
		label = "Vue d'ensemble côté rue (jour)",
		light = "jour",
		camera = { -25, 72, -35 },
		lookAt = { 46, 0, 37 },
	},
	{
		name = "ensemble-jardin",
		label = "Vue d'ensemble côté jardin (jour)",
		light = "jour",
		camera = { 117, 72, 109 },
		lookAt = { 46, 0, 37 },
	},
	{
		-- Cadrée sur l'emprise de la cave (x 38..92), plus petite que la maison
		name = "niveau-cave",
		label = "Cave en coupe, vue de dessus (jour)",
		light = "jour",
		cut = -2,
		camera = { 65, 52, 26 },
		lookAt = { 65, -12, 25 },
	},
	{
		name = "niveau-rdc",
		label = "Rez-de-chaussée en coupe, vue de dessus (jour)",
		light = "jour",
		cut = 10,
		camera = { 46, 95, 38 },
		lookAt = { 46, 0, 37 },
	},
	{
		name = "niveau-etage",
		label = "Étage en coupe, vue de dessus (jour)",
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
}

-- Cette méthode permet de retrouver un point de vue par son nom lorsqu'une sous-commande le reçoit, ou d'arrêter avec
-- la liste des noms connus.
local function findView(name: string?)
	for _, v in VIEWS do
		if v.name == name then
			return v
		end
	end
	local names = {}
	for _, v in VIEWS do
		table.insert(names, v.name)
	end
	print("vue inconnue : " .. tostring(name) .. " (vues : " .. table.concat(names, ", ") .. ")")
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

-- Cette méthode permet d'écrire un vecteur au format attendu par screen_capture lorsque l'on liste les vues.
local function vec(v: { number }): string
	return "[" .. table.concat(v, ", ") .. "]"
end

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
local command = args[1]

if table.find(args, "--check") then
	local current = if fs.isFile(STAMP_PATH) then string.gsub(fs.readFile(STAMP_PATH), "\r", "") else ""
	if current == stamp() then
		print("ok")
		return
	end
	print("captures de la carte à reprendre : les sources de la carte ont changé depuis docs/captures/sources.sha256")
	print("procédure : docs/captures/README.md (Studio, puis lune run tools/captures -- stamp)")
	process.exit(1)
elseif command == "list" then
	for _, v in VIEWS do
		print(
			string.format(
				"%-16s %-5s coupe %-5s camera_position %s  look_at_position %s",
				v.name,
				v.light,
				if v.cut then tostring(v.cut) else "-",
				vec(v.camera),
				vec(v.lookAt)
			)
		)
	end
elseif command == "scene" then
	local v = findView(args[2])
	local header = string.format(
		"local VIEW = { light = %q, cut = %s }\n",
		v.light,
		if v.cut then tostring(v.cut) else "nil"
	)
	local body = string.gsub(fs.readFile(SCENE_PATH), "\r", "")
	body = string.gsub(body, "local VIEW = VIEW :: [^\n]*\n", "")
	print(header .. body)
elseif command == "save" then
	local v = findView(args[2])
	local src = args[3]
	if not src or not fs.isFile(src) then
		print("image introuvable : " .. tostring(src))
		process.exit(1)
	end
	fs.writeDir(OUT_DIR)
	fs.copy(src, OUT_DIR .. "/" .. v.name .. ".jpg", true)
	print("écrit " .. OUT_DIR .. "/" .. v.name .. ".jpg")
elseif command == "stamp" then
	fs.writeDir(OUT_DIR)
	fs.writeFile(STAMP_PATH, stamp())
	print("écrit " .. STAMP_PATH)
else
	print("usage : lune run tools/captures -- list | scene <vue> | save <vue> <image> | stamp | --check")
	process.exit(1)
end

-- Plan de la carte sans ouvrir Studio (lune run tools/house-map) : écrit docs/plan/plan.svg (plan 2D des trois niveaux)
-- et docs/plan/maison-3d.html (vue 3D Three.js) depuis Shared.HouseLayout et les blocs de Shared.HouseGeometry, ceux
-- que Server.HouseBuilder construit. `--check` ne réécrit rien et échoue si les fichiers ne sont plus à jour
-- (tools/check.sh). Ne remplace pas la vérification en jeu (traversées, collisions, éclairage réel).
local fs = require("@lune/fs")
local process = require("@lune/process")
local Loader = require("../tests/lib/Loader")

local loader = Loader.new()
local HouseLayout = loader:require("src/shared/HouseLayout")
local HouseGeometry = loader:require("src/shared/HouseGeometry")
local HouseStyle = loader:require("src/shared/HouseStyle")

local OUT_DIR = "docs/plan"
local SVG_PATH = OUT_DIR .. "/plan.svg"
local HTML_PATH = OUT_DIR .. "/maison-3d.html"
local TEMPLATE_PATH = "tools/house-map.viewer.html"

local layout = HouseLayout
local byId = HouseGeometry.roomsById(layout)
local built = HouseGeometry.build(layout)
local B = layout.bounds

-- Cette méthode permet d'écrire un nombre de façon stable et courte lorsque l'on produit le SVG ou le JSON (une sortie
-- identique d'une exécution à l'autre, pour la vérification de fraîcheur).
local function num(n: number): string
	local s = string.format("%.2f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "-0" then
		return "0"
	end
	return s
end

-- Cette méthode permet d'échapper un texte lorsqu'il entre dans un attribut ou un nœud SVG.
local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

---------------------------------------------------------------------------------------------------------------------
-- Plan 2D
---------------------------------------------------------------------------------------------------------------------
local SCALE = 7 -- pixels par stud
local PAD = 3 -- studs de marge autour du terrain
local PANEL_W = (B.x1 - B.x0 + 2 * PAD) * SCALE
local PANEL_H = (B.z1 - B.z0 + 2 * PAD) * SCALE
local TITLE_H = 40
local GAP = 24
local LEGEND_H = 120
local LEVELS = { -1, 0, 1 }
local WIDTH = #LEVELS * PANEL_W + (#LEVELS + 1) * GAP
local HEIGHT = TITLE_H + PANEL_H + LEGEND_H + GAP

local COLORS = {
	lit = "#e9dcc0",
	dark = "#5b6170",
	outdoorLit = "#a9c49a",
	outdoorDark = "#5f7558",
	shed = "#7d6a55",
	wall = "#1d1f24",
	fence = "#2f5a2a",
	leaf = "#d23b2f",
	step = "#c7c9d1",
	partition = "#3a3d45",
	prop = "#8b8f99",
	trap = "#e8892b",
	key = "#2f7de1",
	lamp = "#ffd54a",
	mortal = "#2bb673",
	death = "#8e2bd2",
	wet = "#3fc4e0",
	exit = "#ff2e63",
	car = "#3b4a63",
	breaker = "#ffef5a",
	text = "#1d1f24",
	textDark = "#f2f2f2",
	bg = "#f4f2ee",
}

local svg = {}
-- Cette méthode permet d'ajouter une ligne au SVG lorsque l'on dessine un élément.
local function out(s: string)
	table.insert(svg, s)
end

-- Cette méthode permet de convertir un rectangle du monde (x, z) en rectangle SVG d'un panneau lorsque l'on dessine
-- une pièce, un mur ou un meuble ; le nord est en haut.
local function rect(ox: number, x0: number, x1: number, z0: number, z1: number, attrs: string)
	local px = ox + (x0 - B.x0 + PAD) * SCALE
	local py = TITLE_H + (B.z1 - z1 + PAD) * SCALE
	out(
		string.format(
			'<rect x="%s" y="%s" width="%s" height="%s" %s/>',
			num(px),
			num(py),
			num((x1 - x0) * SCALE),
			num((z1 - z0) * SCALE),
			attrs
		)
	)
end

-- Cette méthode permet de convertir un point du monde en coordonnées SVG d'un panneau.
local function point(ox: number, x: number, z: number): (number, number)
	return ox + (x - B.x0 + PAD) * SCALE, TITLE_H + (B.z1 - z + PAD) * SCALE
end

-- Cette méthode permet de couper un nom en lignes lorsqu'il est plus large que la place disponible (largeur de
-- caractère estimée à 0,58 fois la taille de police).
local function wrap(text: string, size: number, maxWidth: number): { string }
	local lines, current = {}, ""
	for word in string.gmatch(text, "%S+") do
		local candidate = if current == "" then word else current .. " " .. word
		if current ~= "" and utf8.len(candidate) * size * 0.58 > maxWidth then
			table.insert(lines, current)
			current = word
		else
			current = candidate
		end
	end
	table.insert(lines, current)
	return lines
end

-- Cette méthode permet de dessiner un texte centré (sur plusieurs lignes si maxWidth est donné) lorsque l'on nomme une
-- pièce ou un repère ; un contour de la couleur opposée le garde lisible sur les halos et les meubles.
local function label(
	ox: number,
	x: number,
	z: number,
	text: string,
	size: number,
	color: string,
	weight: string?,
	maxWidth: number?
)
	local px, py = point(ox, x, z)
	local lines = if maxWidth then wrap(text, size, maxWidth) else { text }
	local halo = if color == COLORS.textDark or color == "white" then "#000000" else "#ffffff"
	local lineH = size * 1.15
	local y0 = py - (#lines - 1) * lineH / 2
	for i, line in lines do
		out(
			string.format(
				'<text x="%s" y="%s" font-size="%d" fill="%s" stroke="%s" stroke-width="2.5" stroke-opacity="0.55" paint-order="stroke" text-anchor="middle" dominant-baseline="middle"%s>%s</text>',
				num(px),
				num(y0 + (i - 1) * lineH),
				size,
				color,
				halo,
				if weight then string.format(' font-weight="%s"', weight) else "",
				esc(line)
			)
		)
	end
end

-- Cette méthode permet de dessiner un disque lorsque l'on place une lampe ou un ancrage.
local function circle(ox: number, x: number, z: number, radius: number, attrs: string)
	local px, py = point(ox, x, z)
	out(string.format('<circle cx="%s" cy="%s" r="%s" %s/>', num(px), num(py), num(radius), attrs))
end

-- Cette méthode permet de donner le rectangle au sol (x0, x1, z0, z1) et la plage de hauteur d'un bloc calculé.
local function bounds(p)
	local a, b = HouseGeometry.extent(p)
	return a.X, b.X, a.Z, b.Z, a.Y, b.Y
end

-- Cette méthode permet de choisir le fond d'une pièce selon qu'elle est dehors, éclairée ou sombre.
local function roomFill(room): string
	if room.outdoor then
		return if room.lit then COLORS.outdoorLit else COLORS.outdoorDark
	end
	if room.id == "Shed" then
		return COLORS.shed
	end
	return if room.lit then COLORS.lit else COLORS.dark
end

-- Cette méthode permet de dessiner un niveau complet (pièces, escaliers, meubles, murs, portes, lampes, ancrages,
-- noms) dans son panneau lorsque l'on produit le plan.
local function drawLevel(index: number, level: number)
	local ox = GAP + (index - 1) * (PANEL_W + GAP)
	local floorY = HouseGeometry.floorY(layout, level)
	-- Coupe à hauteur de hanche : les murs percés d'une porte s'y interrompent
	local cut = floorY + 1.5
	out(string.format('<g id="level%d">', level))
	out(
		string.format(
			'<text x="%s" y="26" font-size="20" font-weight="bold" fill="%s">%s (niveau %d)</text>',
			num(ox),
			COLORS.text,
			esc(layout.levels[level]),
			level
		)
	)
	-- Tout le dessin du panneau est découpé à son cadre (les halos des lampes n'en débordent pas)
	out(
		string.format(
			'<clipPath id="clip%d"><rect x="%s" y="%s" width="%s" height="%s"/></clipPath><g clip-path="url(#clip%d)">',
			index,
			num(ox),
			num(TITLE_H),
			num(PANEL_W),
			num(PANEL_H),
			index
		)
	)
	rect(ox, B.x0 - PAD, B.x1 + PAD, B.z0 - PAD, B.z1 + PAD, 'fill="#e4e1da"')
	if level == 0 then
		-- Décor hors de la carte, coupé au bord du panneau
		for _, s in layout.scenery or {} do
			local x0, x1 = math.max(s.x0, B.x0 - PAD), math.min(s.x1, B.x1 + PAD)
			local z0, z1 = math.max(s.z0, B.z0 - PAD), math.min(s.z1, B.z1 + PAD)
			if x0 < x1 and z0 < z1 then
				rect(ox, x0, x1, z0, z1, if s.kind == "Street" then 'fill="#55565c"' else 'fill="#8d9a86"')
			end
		end
	else
		-- Emprise de la maison au rez, en pointillés, pour se repérer
		for _, room in layout.rooms do
			if not room.outdoor and HouseGeometry.spansLevel(room, 0) and room.id ~= "Shed" then
				rect(ox, room.x0, room.x1, room.z0, room.z1, 'fill="none" stroke="#b9b5ab" stroke-dasharray="4 3"')
			end
		end
	end
	-- Sols
	for _, room in layout.rooms do
		if HouseGeometry.spansLevel(room, level) then
			rect(ox, room.x0, room.x1, room.z0, room.z1, string.format('fill="%s"', roomFill(room)))
		end
	end
	-- Escaliers : marches, paliers et cloison ; la teinte s'assombrit avec la hauteur
	for _, p in built.pieces do
		local room = p.room and byId[p.room]
		if not (room and room.stairs and HouseGeometry.spansLevel(room, level)) then
			continue
		end
		if p.kind == "Step" or p.kind == "Landing" or p.kind == "Partition" then
			local x0, x1, z0, z1, _, y1 = bounds(p)
			local fill = COLORS.partition
			if p.kind ~= "Partition" then
				local t = math.clamp((y1 - HouseGeometry.floorY(layout, room.level)) / (2 * layout.LEVEL_HEIGHT), 0, 1)
				local g = math.floor(225 - t * 120)
				fill = string.format("#%02x%02x%02x", g, g, g + 8)
			end
			rect(ox, x0, x1, z0, z1, string.format('fill="%s" stroke="#666" stroke-width="0.5"', fill))
		end
	end
	-- Meubles
	for _, prop in layout.props do
		local room = byId[prop.room]
		if room.level ~= level then
			continue
		end
		local sx, sz = prop.size[1], prop.size[3]
		local fill = if prop.tag == "Breaker" then COLORS.breaker elseif prop.trap then COLORS.trap else COLORS.prop
		local stroke = if prop.keySpot then COLORS.key else "#444"
		local width = if prop.keySpot then 2.5 else 0.8
		rect(
			ox,
			prop.x - sx / 2,
			prop.x + sx / 2,
			prop.z - sz / 2,
			prop.z + sz / 2,
			string.format('fill="%s" stroke="%s" stroke-width="%s"', fill, stroke, num(width))
		)
		if prop.keySpot then
			circle(ox, prop.x, prop.z, 3.5, string.format('fill="%s" stroke="white" stroke-width="1"', COLORS.key))
		end
	end
	-- Voiture
	if byId[layout.car.room].level == level then
		for _, p in built.pieces do
			if p.kind == "Car" and string.match(p.name, "^Body") then
				local x0, x1, z0, z1 = bounds(p)
				rect(ox, x0, x1, z0, z1, string.format('fill="%s" stroke="#111" rx="6"', COLORS.car))
				label(ox, p.center.X, p.center.Z, "Voiture", 11, COLORS.textDark, "bold")
			end
		end
	end
	-- Murs, clôtures et battants coupés à hauteur de hanche (les ouvertures apparaissent d'elles-mêmes)
	for _, p in built.pieces do
		if p.kind ~= "Wall" and p.kind ~= "Fence" and p.kind ~= "DoorLeaf" then
			continue
		end
		local x0, x1, z0, z1, y0, y1 = bounds(p)
		if y0 <= cut and cut < y1 then
			local fill = if p.kind == "Fence"
				then COLORS.fence
				elseif p.kind == "DoorLeaf" then COLORS.leaf
				else COLORS.wall
			-- Un battant fait l'épaisseur du mur : on l'élargit un peu pour le voir
			if p.kind == "DoorLeaf" then
				if x1 - x0 < z1 - z0 then
					x0, x1 = x0 - 0.4, x1 + 0.4
				else
					z0, z1 = z0 - 0.4, z1 + 0.4
				end
			end
			rect(ox, x0, x1, z0, z1, string.format('fill="%s"', fill))
		end
	end
	-- Lampes : halo de portée puis ampoule
	for _, lamp in layout.lamps do
		local room = byId[lamp.room]
		if room.level == level then
			local style = HouseGeometry.LAMP_STYLES[lamp.kind or "Ceiling"]
			circle(ox, lamp.x, lamp.z, style.range * SCALE, 'fill="#ffd54a" fill-opacity="0.10" stroke="none"')
		end
	end
	for _, lamp in layout.lamps do
		local room = byId[lamp.room]
		if room.level == level then
			local r = if lamp.kind == "Chandelier" then 7 else 5
			local stroke = if lamp.kind == "Chandelier" then COLORS.trap else "#7a5c00"
			circle(ox, lamp.x, lamp.z, r, string.format('fill="%s" stroke="%s" stroke-width="2"', COLORS.lamp, stroke))
		end
	end
	-- Ancrages
	for _, a in layout.anchors do
		local room = byId[a.room]
		if room.level ~= level then
			continue
		end
		if a.kind == "WetFloor" then
			rect(
				ox,
				a.x - 2,
				a.x + 2,
				a.z - 2,
				a.z + 2,
				string.format('fill="%s" fill-opacity="0.75" stroke="#1a7d92" rx="5"', COLORS.wet)
			)
		elseif a.kind == "MortalSpawn" then
			circle(ox, a.x, a.z, 6, string.format('fill="%s" stroke="white" stroke-width="1.5"', COLORS.mortal))
		elseif a.kind == "DeathSpawn" then
			circle(ox, a.x, a.z, 7, string.format('fill="%s" stroke="white" stroke-width="1.5"', COLORS.death))
			label(ox, a.x, a.z, "M", 9, "white", "bold")
		elseif a.kind == "Exit" then
			circle(ox, a.x, a.z, 9, string.format('fill="%s" stroke="white" stroke-width="2"', COLORS.exit))
			label(ox, a.x, a.z + 3.2, "SORTIE", 12, COLORS.exit, "bold")
		end
	end
	-- Noms des pièces
	for _, room in layout.rooms do
		if HouseGeometry.spansLevel(room, level) then
			local color = if room.lit and room.id ~= "Shed" then COLORS.text else COLORS.textDark
			local cx, cz = (room.x0 + room.x1) / 2, (room.z0 + room.z1) / 2
			local name = room.name
			if room.stairs then
				name ..= string.format(" (%d↔%d)", room.level, room.level + 1)
			end
			label(ox, cx, cz, name, 12, color, "bold", (room.x1 - room.x0) * SCALE - 8)
		end
	end
	if level == 0 then
		-- Limite invisible du terrain
		rect(ox, B.x0, B.x1, B.z0, B.z1, 'fill="none" stroke="#c0392b" stroke-width="1.5" stroke-dasharray="6 4"')
	end
	out("</g>")
	-- Boussole
	local nx, ny = ox + PANEL_W - 22, TITLE_H + 26
	out(
		string.format(
			'<path d="M %s %s l -7 16 l 7 -5 l 7 5 z" fill="%s"/><text x="%s" y="%s" font-size="12" text-anchor="middle" fill="%s" font-weight="bold">N</text>',
			num(nx),
			num(ny - 12),
			COLORS.text,
			num(nx),
			num(ny - 16),
			COLORS.text
		)
	)
	out("</g>")
end

-- Cette méthode permet de dessiner la légende sous les trois panneaux.
local function drawLegend()
	local y = TITLE_H + PANEL_H + GAP + 6
	local items = {
		{ "rect", COLORS.lit, "Pièce éclairée" },
		{ "rect", COLORS.dark, "Pièce sombre" },
		{ "rect", COLORS.outdoorLit, "Dehors éclairé" },
		{ "rect", COLORS.outdoorDark, "Dehors sombre" },
		{ "rect", COLORS.wall, "Mur (ouverture = porte)" },
		{ "rect", COLORS.fence, "Clôture" },
		{ "rect", COLORS.leaf, "Battant fermé (porte d'entrée, garage, portail)" },
		{ "rect", COLORS.trap, "Meuble piège (étagère)" },
		{ "rect", COLORS.prop, "Meuble" },
		{ "circle", COLORS.key, "Emplacement de clés" },
		{ "circle", COLORS.lamp, "Lampe (halo = portée) ; cerclée orange = lustre piège" },
		{ "rect", COLORS.wet, "Sol mouillé (piège)" },
		{ "circle", COLORS.mortal, "Apparition mortel" },
		{ "circle", COLORS.death, "Apparition de la Mort" },
		{ "rect", COLORS.breaker, "Disjoncteur" },
		{ "circle", COLORS.exit, "Sortie" },
		{ "dash", "#c0392b", "Limite du terrain" },
	}
	local perRow = 6
	local colW = (WIDTH - 2 * GAP) / perRow
	for i, item in items do
		local col, row = (i - 1) % perRow, (i - 1) // perRow
		local x, yy = GAP + col * colW, y + row * 30
		if item[1] == "rect" then
			out(
				string.format(
					'<rect x="%s" y="%s" width="18" height="14" fill="%s" stroke="#444" stroke-width="0.5"/>',
					num(x),
					num(yy),
					item[2]
				)
			)
		elseif item[1] == "circle" then
			out(
				string.format(
					'<circle cx="%s" cy="%s" r="7" fill="%s" stroke="#444" stroke-width="0.5"/>',
					num(x + 9),
					num(yy + 7),
					item[2]
				)
			)
		else
			out(
				string.format(
					'<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>',
					num(x),
					num(yy + 7),
					num(x + 18),
					num(yy + 7),
					item[2]
				)
			)
		end
		out(
			string.format(
				'<text x="%s" y="%s" font-size="13" fill="%s">%s</text>',
				num(x + 26),
				num(yy + 12),
				COLORS.text,
				esc(item[3])
			)
		)
	end
	out(
		string.format(
			'<text x="%s" y="%s" font-size="12" fill="#666">Généré par lune run tools/house-map depuis Shared.HouseLayout. 1 case de grille = 10 studs. Murs coupés à 1,5 stud du sol.</text>',
			num(GAP),
			num(HEIGHT - 10)
		)
	)
end

-- Cette méthode permet de dessiner une grille de 10 studs dans chaque panneau pour lire les distances.
local function grid(ox: number)
	local parts = {}
	for x = math.ceil(B.x0 / 10) * 10, B.x1, 10 do
		local px, py0 = point(ox, x, B.z1 + PAD)
		local _, py1 = point(ox, x, B.z0 - PAD)
		table.insert(parts, string.format("M%s %sV%s", num(px), num(py0), num(py1)))
	end
	for z = math.ceil(B.z0 / 10) * 10, B.z1, 10 do
		local px0, py = point(ox, B.x0 - PAD, z)
		local px1 = point(ox, B.x1 + PAD, z)
		table.insert(parts, string.format("M%s %sH%s", num(px0), num(py), num(px1)))
	end
	out(
		string.format(
			'<path d="%s" stroke="#000" stroke-opacity="0.08" stroke-width="1" fill="none"/>',
			table.concat(parts)
		)
	)
end

out(
	string.format(
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="Segoe UI, Helvetica, Arial, sans-serif">',
		WIDTH,
		HEIGHT,
		WIDTH,
		HEIGHT
	)
)
out(string.format('<rect width="100%%" height="100%%" fill="%s"/>', COLORS.bg))
for i, level in LEVELS do
	drawLevel(i, level)
	grid(GAP + (i - 1) * (PANEL_W + GAP))
end
drawLegend()
out("</svg>")
local svgText = table.concat(svg, "\n") .. "\n"

---------------------------------------------------------------------------------------------------------------------
-- Vue 3D : blocs calculés, injectés dans le gabarit Three.js
---------------------------------------------------------------------------------------------------------------------
local HIDDEN = { Zone = true, Boundary = true }

-- Cette méthode permet d'écrire un composant d'axe avec trois décimales lorsque l'on exporte l'orientation d'un bloc
-- (les quarts de tour restent exacts : 0, 1, -1).
local function num3(n: number): string
	local s = string.format("%.3f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "-0" then
		return "0"
	end
	return s
end

-- Cette méthode permet de produire les champs JSON de forme et d'orientation d'un bloc rond ou tourné lorsque l'on
-- exporte la vue 3D ; les axes sont donnés en repère du jeu, la vue fait la conversion vers Three.js.
local function orientedFields(p): string
	local s = p.size
	local fields = string.format(',"s":[%s,%s,%s]', num(s.X), num(s.Y), num(s.Z))
	if p.basis then
		local m = {}
		for _, axis in p.basis do
			table.insert(m, num3(axis.X))
			table.insert(m, num3(axis.Y))
			table.insert(m, num3(axis.Z))
		end
		fields ..= string.format(',"m":[%s]', table.concat(m, ","))
	end
	if p.shape then
		fields ..= string.format(',"f":%d', if p.shape == "Ball" then 1 else 2)
	end
	return fields
end

local boxes = {}
for _, p in built.pieces do
	if HIDDEN[p.kind] then
		continue
	end
	local room = p.room and byId[p.room]
	local kind = p.kind
	local extra = ""
	if kind == "Prop" and p.attributes.TrapKind then
		kind = "Trap"
	elseif kind == "Lamp" and p.attributes.TrapKind then
		kind = "Chandelier"
	elseif kind == "Anchor" then
		local tag = p.tags[1]
		if tag == "TrapCandidate" then
			kind = "WetFloor"
		else
			kind = tag
		end
	elseif kind == "Prop" and table.find(p.tags, "Breaker") then
		kind = "Breaker"
	end
	if kind == "Floor" and room then
		extra = if room.lit then ',"lit":1' else ',"lit":0'
	end
	-- Mode « Rendu » de la vue : couleur de l'habillage (HouseStyle) ; un volume de meuble habillé y est masqué au
	-- profit de ses blocs, que le mode « Plan » masque
	if p.surface then
		local surface = HouseStyle.surfaces[p.surface]
		local c = surface.color
		extra ..= string.format(',"c":"#%02x%02x%02x"', c[1], c[2], c[3])
		if surface.transparency and surface.transparency >= 0.5 then
			extra ..= ',"t":1'
		end
	end
	if p.hitbox then
		extra ..= ',"h":1'
	end
	-- Bloc rond ou tourné : taille dans ses axes (s), axes dans le monde (m) et forme (f : 1 boule, 2 cylindre) ;
	-- b reste sa boîte englobante, dont le centre est celui du bloc
	if p.basis or p.shape then
		extra ..= orientedFields(p)
	end
	local x0, x1, z0, z1, y0, y1 = bounds(p)
	table.insert(
		boxes,
		string.format(
			'{"k":"%s","n":"%s","r":"%s","b":[%s,%s,%s,%s,%s,%s]%s}',
			kind,
			p.name,
			if room then esc(room.name) else "",
			num(x0),
			num(y0),
			num(z0),
			num(x1),
			num(y1),
			num(z1),
			extra
		)
	)
end
local labels = {}
for _, room in layout.rooms do
	table.insert(
		labels,
		string.format(
			'{"n":"%s","x":%s,"y":%s,"z":%s,"lvl":%d}',
			esc(room.name),
			num((room.x0 + room.x1) / 2),
			num(HouseGeometry.floorY(layout, room.level) + 0.2),
			num((room.z0 + room.z1) / 2),
			room.level
		)
	)
end
local data = string.format(
	'{"levelHeight":%d,"bounds":[%s,%s,%s,%s],"boxes":[\n%s\n],"labels":[\n%s\n]}',
	layout.LEVEL_HEIGHT,
	num(B.x0),
	num(B.z0),
	num(B.x1),
	num(B.z1),
	table.concat(boxes, ",\n"),
	table.concat(labels, ",\n")
)
-- Gabarit en LF, comme la sortie comparée par --check (extraction CRLF sous Windows avec core.autocrlf, #36)
local template = string.gsub(fs.readFile(TEMPLATE_PATH), "\r\n", "\n")
local start, finish = string.find(template, "/*DATA*/null", 1, true)
assert(start, TEMPLATE_PATH .. " : marqueur /*DATA*/null introuvable")
local htmlText = string.sub(template, 1, start - 1) .. data .. string.sub(template, finish + 1)

---------------------------------------------------------------------------------------------------------------------
-- Écriture ou vérification
---------------------------------------------------------------------------------------------------------------------
local outputs = { { SVG_PATH, svgText }, { HTML_PATH, htmlText } }
if table.find(process.args, "--check") then
	local stale = {}
	for _, o in outputs do
		local current = if fs.isFile(o[1]) then fs.readFile(o[1]) else nil
		-- Fins de ligne CRLF possibles à l'extraction sous Windows
		if current then
			current = string.gsub(current, "\r\n", "\n")
		end
		if current ~= o[2] then
			table.insert(stale, o[1])
		end
	end
	if #stale > 0 then
		print("plan pas à jour : " .. table.concat(stale, ", ") .. " (lune run tools/house-map)")
		process.exit(1)
	end
	print("ok")
else
	if not fs.isDir(OUT_DIR) then
		fs.writeDir(OUT_DIR)
	end
	for _, o in outputs do
		fs.writeFile(o[1], o[2])
		print("écrit " .. o[1])
	end
end

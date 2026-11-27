-- build-remount.luau (#79) : prépare le script de remontage à exécuter dans Studio.
-- Usage (racine du dépôt ou du worktree) : lune run tools/rbxm/build-remount.luau -- <modèle> <import> <sortie.luau>
--   <modèle> : nom du manifeste (tools/models/<modèle>.manifest.json et <modèle>.measured.json), par ex. death
--   <import> : nom du modèle importé (GLB) dans workspace ou ReplicatedStorage, ou "" pour seulement réappliquer
--   <sortie> : fichier écrit (hors dépôt, par ex. %TEMP%), à passer tel quel à `execute_luau` (mode Edit)
-- Injecte manifeste, mesures et nom de l'import dans tools/rbxm/remount.luau.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local args = table.clone(process.args)
if args[1] == "--" then
	table.remove(args, 1)
end
assert(#args == 3, "usage : lune run tools/rbxm/build-remount.luau -- <modèle> <import> <sortie.luau>")
local name, import, out = args[1], args[2], args[3]
assert(string.match(name, "^[%w_]+$"), "nom de modèle invalide : " .. name)
assert(import == "" or string.match(import, "^[%w_%-]+$"), "nom d'import invalide : " .. import)

-- Cette méthode permet de relire un JSON et de le réécrire compact (valide, sans `]==]` qui fermerait la chaîne).
local function compact(path: string): string
	local text = serde.encode("json", serde.decode("json", fs.readFile(path)))
	assert(not string.find(text, "]==]", 1, true), path .. " contient « ]==] »")
	return text
end

local template = fs.readFile("tools/rbxm/remount.luau")
-- remplacements littéraux (gsub interpréterait les % du JSON)
local function replace(text: string, marker: string, value: string): string
	local a, b = string.find(text, marker, 1, true)
	assert(a, "marqueur absent : " .. marker)
	return string.sub(text, 1, a - 1) .. value .. string.sub(text, b + 1)
end
local script = template
script = replace(script, "@MANIFEST@", compact("tools/models/" .. name .. ".manifest.json"))
script = replace(script, "@MEASURED@", compact("tools/models/" .. name .. ".measured.json"))
script = replace(script, "@IMPORT@", import)
fs.writeFile(out, script)
print(string.format("%s (%d octets)", out, #script))

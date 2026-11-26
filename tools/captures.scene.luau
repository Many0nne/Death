-- Mise en scène d'une capture de la carte, exécutée en Play dans le contexte Server via le MCP Studio (execute_luau).
-- Ne pas lancer tel quel : `lune run tools/captures -- scene <vue>` l'imprime précédé de la ligne `local VIEW = {...}`.
-- Idempotent et réversible : chaque appel annule d'abord la mise en scène précédente (lumière, blocs masqués).
-- VIEW.light = "jour" (lecture du décor) ou "nuit" (éclairage du jeu) ; VIEW.cut = hauteur au-dessus de laquelle les
-- blocs sont masqués (coupe d'un niveau), nil pour la maison entière.
local VIEW = VIEW :: { light: string, cut: number? }

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local STASH = "CaptureStash"
local LIGHT_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation" }

-- Cette méthode permet de remettre la lumière et les blocs du jeu lorsqu'une mise en scène précédente les a changés.
local function restore()
	local stash = ServerStorage:FindFirstChild(STASH)
	if stash then
		for _, prop in LIGHT_PROPS do
			local v = stash:GetAttribute(prop)
			if v ~= nil then
				(Lighting :: any)[prop] = v
			end
		end
		for _, effect in stash:GetChildren() do
			effect.Parent = Lighting
		end
		stash:Destroy()
	end
	for _, p in workspace:GetDescendants() do
		local t = p:GetAttribute("CaptureTransparency")
		if t ~= nil then
			(p :: BasePart).Transparency = t
			p:SetAttribute("CaptureTransparency", nil)
		end
	end
end

-- Cette méthode permet de passer en plein jour, sans brume ni étalonnage de nuit, lorsque la vue sert à lire le décor.
local function daylight()
	local stash = Instance.new("Folder")
	stash.Name = STASH
	for _, prop in LIGHT_PROPS do
		stash:SetAttribute(prop, (Lighting :: any)[prop])
	end
	for _, effect in Lighting:GetChildren() do
		if effect:IsA("PostEffect") or effect:IsA("Atmosphere") then
			effect.Parent = stash
		end
	end
	stash.Parent = ServerStorage
	Lighting.ClockTime = 13
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = Color3.fromRGB(140, 140, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 160, 160)
end

-- Cette méthode permet de masquer ce qui est au-dessus d'un niveau (plafonds, étages, toits) lorsque la vue est une
-- coupe : un bloc qui commence au-dessus de la coupe, ou un haut mur qui la dépasse largement, disparaît.
local function cut(height: number): number
	local hidden = 0
	for _, p in workspace:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local bottom = p.Position.Y - p.Size.Y / 2
			if bottom >= height - 0.01 or (p.Position.Y > height + 1 and p.Size.Y > 4) then
				p:SetAttribute("CaptureTransparency", p.Transparency)
				p.Transparency = 1
				hidden += 1
			end
		end
	end
	return hidden
end

restore()
if VIEW.light == "jour" then
	daylight()
end
local hidden = if VIEW.cut then cut(VIEW.cut) else 0
return string.format("scène prête : lumière %s, %d blocs masqués", VIEW.light, hidden)

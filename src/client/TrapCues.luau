-- Indices des pièges côté client (#5), sans marqueur à l'écran :
-- - buée de respiration et léger frisson quand le serveur signale un piège armé à environ 3 m (attribut TrapChill) ;
-- - message bref pour le joueur local (résultat d'un examen, refus d'une préparation : événement TrapNotice).
-- Les bruits de préparation, l'indice visuel intermittent et les chutes sont joués par le serveur (Server.TrapService).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrapAttributes = require(Shared:WaitForChild("TrapAttributes"))

local TA = TrapAttributes

-- Buée : une bouffée toutes les BREATH_PERIOD secondes devant le visage
local BREATH_PERIOD = 1.8
local BREATH_PUFF = 0.35
-- Frisson : petit tremblement de la caméra (studs) et teinte froide, en fondu
local SHIVER_AMPLITUDE = 0.035
local FADE_RATE = 2.5
-- Durée d'affichage d'un message (secondes)
local NOTICE_TIME = 2.5

local TrapCues = {}

-- Cette méthode permet de créer l'émetteur de buée (attaché au terrain, replacé devant la caméra à chaque image)
-- lorsque le client démarre.
local function makeBreath(): (Attachment, ParticleEmitter)
	local attachment = Instance.new("Attachment")
	attachment.Name = "TrapBreath"
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Breath"
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(Color3.fromRGB(235, 240, 245))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.2)
	emitter.Speed = NumberRange.new(0.6, 1)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Rate = 40
	emitter.Drag = 2
	emitter.LockedToPart = false
	emitter.Parent = attachment
	attachment.Parent = workspace.Terrain
	return attachment, emitter
end

-- Cette méthode permet de créer le bandeau des messages lorsque le client démarre.
local function makeNotice(player: Player): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "TrapNotice"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 72)
	label.Size = UDim2.fromOffset(420, 34)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(230, 230, 235)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.Visible = false
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return label
end

-- Cette méthode permet de démarrer les indices lorsque le client se lance.
function TrapCues.start()
	local player = Players.LocalPlayer
	local attachment, emitter = makeBreath()
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "TrapChill"
	tint.Enabled = false
	tint.Parent = Lighting
	local strength = 0 -- 0 : aucun frisson, 1 : frisson plein
	local breathClock = 0
	local shaking = false

	RunService.RenderStepped:Connect(function(dt)
		local chilled = player:GetAttribute(TA.Chill) == true
		strength = math.clamp(strength + (if chilled then dt else -dt) * FADE_RATE, 0, 1)
		local camera = workspace.CurrentCamera
		if camera then
			attachment.WorldPosition = (camera.CFrame * CFrame.new(0, -0.5, -1.4)).Position
			emitter.Acceleration = camera.CFrame.LookVector * 1.5 + Vector3.new(0, 0.6, 0)
		end
		breathClock += dt
		if chilled and breathClock >= BREATH_PERIOD then
			breathClock = 0
		end
		emitter.Enabled = chilled and breathClock < BREATH_PUFF
		tint.Enabled = strength > 0
		tint.Saturation = -0.25 * strength
		tint.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(205, 222, 255), strength)
		-- CameraOffset touché seulement pendant le frisson (et remis à zéro une fois à la fin) : il reste libre sinon
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and strength > 0 then
			shaking = true
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 2 * SHIVER_AMPLITUDE * strength,
				(math.random() - 0.5) * 2 * SHIVER_AMPLITUDE * strength,
				0
			)
		elseif humanoid and shaking then
			shaking = false
			humanoid.CameraOffset = Vector3.zero
		end
	end)

	task.spawn(function()
		local label = makeNotice(player)
		local token = 0
		local event = ReplicatedStorage:WaitForChild(TA.NoticeEvent) :: RemoteEvent
		event.OnClientEvent:Connect(function(text: string)
			token += 1
			local mine = token
			label.Text = text
			label.Visible = true
			task.delay(NOTICE_TIME, function()
				if token == mine then
					label.Visible = false
				end
			end)
		end)
	end)
end

return TrapCues

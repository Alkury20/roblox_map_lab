-- EffectController.luau
-- Handles cosmetic effects: trails, auras, pets, dark world flashlight, night vision

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local Logger     = require(ReplicatedStorage.Shared.Logger)

local TAG = "EffectController"
local localPlayer = Players.LocalPlayer
local EffectController = {}

local currentData = nil

-- Built-in Roblox particle textures (nothing to download)
local AURA_PRESETS = {
	aura_fire = {
		texture = "rbxasset://textures/particles/fire_main.dds",
		rate = 40,
		lifetime = NumberRange.new(0.35, 0.7),
		speed = NumberRange.new(1, 3),
		spread = Vector2.new(180, 180),
		acceleration = Vector3.new(0, 4, 0),
		size = NumberSequence.new(0.6, 0),
		lightBrightness = 1.8,
		lightRange = 10,
		fillTransparency = 0.82,
		outlineTransparency = 0.35,
	},
	aura_ice = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		rate = 28,
		lifetime = NumberRange.new(0.5, 1.1),
		speed = NumberRange.new(0.5, 2),
		spread = Vector2.new(360, 360),
		acceleration = Vector3.new(0, -1, 0),
		size = NumberSequence.new(0.35, 0),
		lightBrightness = 1.2,
		lightRange = 8,
		fillTransparency = 0.88,
		outlineTransparency = 0.25,
	},
	aura_dark = {
		texture = "rbxasset://textures/particles/smoke_main.dds",
		rate = 22,
		lifetime = NumberRange.new(0.8, 1.4),
		speed = NumberRange.new(0.3, 1.2),
		spread = Vector2.new(360, 360),
		acceleration = Vector3.new(0, 1.5, 0),
		size = NumberSequence.new(0.8, 0),
		lightBrightness = 0.6,
		lightRange = 7,
		fillTransparency = 0.78,
		outlineTransparency = 0.2,
	},
}

local function findShopItem(itemId: string)
	for _, item in ipairs(Constants.SHOP_ITEMS) do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

local function getAttachPart(char: Model): BasePart?
	return char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("HumanoidRootPart")
end

local function clearTrail(char: Model)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	for _, name in ipairs({ "_MazeTrail", "TrailA0", "TrailA1" }) do
		local inst = hrp:FindFirstChild(name)
		if inst then inst:Destroy() end
	end
end

local function clearAura(char: Model)
	local folder = char:FindFirstChild("_MazeAura")
	if folder then folder:Destroy() end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local light = hrp:FindFirstChild("_MazeAuraLight")
		if light then light:Destroy() end
		local attach = hrp:FindFirstChild("_MazeAuraAttach")
		if attach then attach:Destroy() end
	end
end

-- ─── Trail ────────────────────────────────────────────────────────────────────
local function applyTrail(char: Model, trailId: string)
	clearTrail(char)
	if trailId == "none" then
		Logger.info(TAG, "Trail cleared")
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		Logger.warn(TAG, "Trail skipped — no HumanoidRootPart", trailId)
		return
	end

	local item = findShopItem(trailId)
	local trailColor = item and item.color or Color3.fromRGB(255, 255, 255)

	local colorSeq
	if trailId == "trail_rainbow" then
		colorSeq = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 0,   0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 165, 0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(75, 0, 130)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(148, 0, 211)),
		})
	else
		colorSeq = ColorSequence.new(trailColor)
	end

	local attach0 = Instance.new("Attachment")
	attach0.Name = "TrailA0"
	attach0.Position = Vector3.new(0, 1, 0)
	attach0.Parent = hrp

	local attach1 = Instance.new("Attachment")
	attach1.Name = "TrailA1"
	attach1.Position = Vector3.new(0, -1, 0)
	attach1.Parent = hrp

	local trail = Instance.new("Trail")
	trail.Name = "_MazeTrail"
	trail.Attachment0 = attach0
	trail.Attachment1 = attach1
	trail.Color = colorSeq
	trail.LightEmission = 0.5
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Lifetime = 0.5
	trail.MinLength = 0
	trail.Parent = hrp

	Logger.info(TAG, "Trail applied", trailId, item and item.name or "?")
end

-- ─── Aura (Highlight + ParticleEmitter + PointLight — native Roblox) ─────────
local function applyAura(char: Model, auraId: string)
	clearAura(char)
	if auraId == "none" then
		Logger.info(TAG, "Aura cleared")
		return
	end

	local item = findShopItem(auraId)
	local auraColor = item and item.color or Color3.fromRGB(255, 255, 255)
	local preset = AURA_PRESETS[auraId] or AURA_PRESETS.aura_fire

	local attachPart = getAttachPart(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not attachPart or not hrp then
		Logger.warn(TAG, "Aura skipped — character parts missing", auraId)
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "_MazeAura"
	folder.Parent = char

	local highlight = Instance.new("Highlight")
	highlight.Name = "AuraHighlight"
	highlight.Adornee = char
	highlight.FillColor = auraColor
	highlight.OutlineColor = auraColor
	highlight.FillTransparency = preset.fillTransparency
	highlight.OutlineTransparency = preset.outlineTransparency
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = folder

	local attach = Instance.new("Attachment")
	attach.Name = "_MazeAuraAttach"
	attach.Position = Vector3.new(0, 0, 0)
	attach.Parent = attachPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraParticles"
	emitter.Texture = preset.texture
	emitter.Rate = preset.rate
	emitter.Lifetime = preset.lifetime
	emitter.Speed = preset.speed
	emitter.SpreadAngle = preset.spread
	emitter.Acceleration = preset.acceleration
	emitter.Size = preset.size
	emitter.Color = ColorSequence.new(auraColor)
	emitter.LightEmission = 0.6
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = attach

	local light = Instance.new("PointLight")
	light.Name = "_MazeAuraLight"
	light.Color = auraColor
	light.Brightness = preset.lightBrightness
	light.Range = preset.lightRange
	light.Parent = hrp

	Logger.info(TAG, "Aura applied", auraId, item and item.name or "?", "preset=" .. auraId)
end

-- ─── Night Vision (Dark world + NightVision gamepass) ─────────────────────────
local function applyNightVision(enabled: boolean)
	local Lighting = game:GetService("Lighting")
	if enabled then
		Lighting.Brightness = 3
		Lighting.Ambient = Color3.fromRGB(100, 150, 100)
	end
end

-- ─── Dark world flashlight ────────────────────────────────────────────────────
local function applyDarknessLight(char: Model)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local existing = hrp:FindFirstChild("_MazeFlashlight")
	if existing then existing:Destroy() end

	local light = Instance.new("SpotLight")
	light.Name = "_MazeFlashlight"
	light.Brightness = 5
	light.Angle = 70
	light.Range = 30
	light.Color = Color3.fromRGB(255, 245, 200)
	light.Face = Enum.NormalId.Front
	light.Parent = hrp
end

-- ─── Apply all cosmetics from data ────────────────────────────────────────────
local function applyCosmetics(data, char: Model)
	if not data or not char then return end

	local equipped = data.EquippedItems or {}
	Logger.debug(TAG, "Applying cosmetics",
		"trail=" .. tostring(equipped.Trail),
		"aura=" .. tostring(equipped.Aura),
		"effect=" .. tostring(equipped.Effect),
		"pet=" .. tostring(equipped.Pet))

	applyTrail(char, equipped.Trail or "none")
	applyAura(char, equipped.Aura or "none")

	if data.Gamepasses and data.Gamepasses.NightVision then
		applyNightVision(true)
	end
end

-- ─── Handle effect events from server ─────────────────────────────────────────
function EffectController.onEffect(effectData)
	if effectData.type ~= "equip" then return end
	if effectData.userId ~= localPlayer.UserId then return end

	Logger.info(TAG, "Equip event received",
		"slot=" .. tostring(effectData.slot),
		"itemId=" .. tostring(effectData.itemId))

	local char = localPlayer.Character
	if not char then
		Logger.warn(TAG, "Equip event — no character yet")
		return
	end

	if effectData.slot == "trail" then
		applyTrail(char, effectData.itemId)
	elseif effectData.slot == "aura" then
		applyAura(char, effectData.itemId)
	elseif effectData.slot == "effect" or effectData.slot == "pet" then
		Logger.info(TAG, "Slot not implemented yet", effectData.slot, effectData.itemId)
	else
		Logger.warn(TAG, "Unknown equip slot", tostring(effectData.slot))
	end
end

function EffectController.onDataUpdated(data)
	currentData = data
	local char = localPlayer.Character
	if char then
		applyCosmetics(data, char)
	else
		Logger.debug(TAG, "Data updated — waiting for character to apply cosmetics")
	end
end

-- ─── Darkness world effect ────────────────────────────────────────────────────
local RemoteDefsRef = require(ReplicatedStorage.Shared.RemoteDefinitions)

function EffectController.init(initialData)
	currentData = initialData

	localPlayer.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		applyCosmetics(currentData, char)

		ReplicatedStorage:WaitForChild("Remotes")
			:WaitForChild(RemoteDefsRef.MazeLoaded).OnClientEvent:Connect(function(info)
			if table.find(info.mechanics or {}, "darkness") then
				if currentData and currentData.Gamepasses and currentData.Gamepasses.NightVision then
					applyNightVision(true)
				else
					applyDarknessLight(char)
				end
			else
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local fl = hrp:FindFirstChild("_MazeFlashlight")
					if fl then fl:Destroy() end
				end
			end
		end)
	end)

	if localPlayer.Character then
		task.wait(0.5)
		applyCosmetics(currentData, localPlayer.Character)
	end

	Logger.info(TAG, "Initialized")
end

return EffectController

-- EffectController.luau
-- Handles cosmetic effects: trails, auras, pets, dark world flashlight, night vision

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Constants  = require(ReplicatedStorage.Shared.Constants)

local localPlayer = Players.LocalPlayer
local EffectController = {}

local currentData = nil
local attachedEffects: { Instance } = {}

-- ─── Trail ────────────────────────────────────────────────────────────────────
local function applyTrail(char: Model, trailId: string)
	-- Remove existing trail
	local existing = char:FindFirstChild("_MazeTrail")
	if existing then existing:Destroy() end
	if trailId == "none" then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Find color for trail
	local trailColor = Color3.fromRGB(255, 255, 255)
	for _, item in ipairs(Constants.SHOP_ITEMS) do
		if item.id == trailId and item.color then
			trailColor = item.color
			break
		end
	end

	-- Rainbow trail = color sequence
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

	table.insert(attachedEffects, attach0)
	table.insert(attachedEffects, attach1)
	table.insert(attachedEffects, trail)
end

-- ─── Aura ─────────────────────────────────────────────────────────────────────
local function applyAura(char: Model, auraId: string)
	local existing = char:FindFirstChild("_MazeAura")
	if existing then existing:Destroy() end
	if auraId == "none" then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local auraColor = Color3.fromRGB(255, 255, 255)
	for _, item in ipairs(Constants.SHOP_ITEMS) do
		if item.id == auraId and item.color then
			auraColor = item.color
			break
		end
	end

	local aura = Instance.new("Part")
	aura.Name = "_MazeAura"
	aura.Size = Vector3.new(5, 5, 5)
	aura.Transparency = 0.85
	aura.CanCollide = false
	aura.Anchored = false
	aura.Material = Enum.Material.Neon
	aura.Color = auraColor
	aura.Shape = Enum.PartType.Ball
	aura.Parent = hrp

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = aura
	weld.Parent = aura

	-- Pulse
	task.spawn(function()
		while aura.Parent do
			TweenService:Create(aura, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Size = Vector3.new(6, 6, 6) }):Play()
			task.wait(1)
			TweenService:Create(aura, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Size = Vector3.new(4.5, 4.5, 4.5) }):Play()
			task.wait(1)
		end
	end)
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
	local existing = char:FindFirstChild("_MazeFlashlight")
	if existing then existing:Destroy() end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

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

	applyTrail(char, equipped.Trail or "none")
	applyAura(char, equipped.Aura or "none")

	-- NightVision
	if data.Gamepasses and data.Gamepasses.NightVision then
		applyNightVision(true)
	end
end

-- ─── Handle effect events from server ─────────────────────────────────────────
function EffectController.onEffect(effectData)
	if effectData.type == "equip" and effectData.userId == localPlayer.UserId then
		local char = localPlayer.Character
		if char and currentData then
			if effectData.slot == "trail" then
				applyTrail(char, effectData.itemId)
			elseif effectData.slot == "aura" then
				applyAura(char, effectData.itemId)
			end
		end
	end
end

function EffectController.onDataUpdated(data)
	currentData = data
	local char = localPlayer.Character
	if char then applyCosmetics(data, char) end
end

-- ─── Darkness world effect ────────────────────────────────────────────────────
local ReplicatedStorageRef = ReplicatedStorage
local RemoteDefsRef = require(ReplicatedStorage.Shared.RemoteDefinitions)

function EffectController.init(initialData)
	currentData = initialData

	localPlayer.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		applyCosmetics(currentData, char)

		-- Check if in dark world
		ReplicatedStorage:WaitForChild("Remotes")
			:WaitForChild(RemoteDefsRef.MazeLoaded).OnClientEvent:Connect(function(info)
			if table.find(info.mechanics or {}, "darkness") then
				-- Check night vision gamepass first
				if currentData and currentData.Gamepasses and currentData.Gamepasses.NightVision then
					applyNightVision(true)
				else
					applyDarknessLight(char)
				end
			else
				-- Remove flashlight if not dark world
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
end

return EffectController

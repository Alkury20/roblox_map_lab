-- MazeController.luau
-- Handles client-side maze interactions: coins, checkpoints, exit, lava, secrets

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)

local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local localPlayer = Players.LocalPlayer

local MazeController = {}

local currentMazeInfo = nil
local hintArrows: { BasePart } = {}
local isSlippery = false
local collectedCoins: { [string]: boolean } = {}
local activatedCheckpoints: { [number]: boolean } = {}
local foundSecrets: { [number]: boolean } = {}
local lavaConnections: { RBXScriptConnection } = {}

-- ─── Arrow hint display ───────────────────────────────────────────────────────
local function clearHintArrows()
	for _, a in ipairs(hintArrows) do
		a:Destroy()
	end
	hintArrows = {}
end

local function showPathHint(waypoints)
	clearHintArrows()
	for i, wp in ipairs(waypoints) do
		local arrow = Instance.new("Part")
		arrow.Name = "HintArrow"
		arrow.Size = Vector3.new(0.5, 0.5, 2)
		arrow.CFrame = CFrame.new(wp.x, 1.5, wp.z)
		arrow.Anchored = true
		arrow.CanCollide = false
		arrow.Material = Enum.Material.Neon
		arrow.Color = Color3.fromRGB(0, 255, 150)
		arrow.Parent = Workspace

		-- Point toward next waypoint
		if waypoints[i + 1] then
			local nextWP = waypoints[i + 1]
			arrow.CFrame = CFrame.lookAt(
				Vector3.new(wp.x, 1.5, wp.z),
				Vector3.new(nextWP.x, 1.5, nextWP.z)
			)
		end

		table.insert(hintArrows, arrow)

		-- Fade out after 5 seconds
		task.delay(5, function()
			if arrow.Parent then
				TweenService:Create(arrow, TweenInfo.new(1), { Transparency = 1 }):Play()
				task.wait(1)
				arrow:Destroy()
			end
		end)
	end
end

-- ─── Slippery physics ─────────────────────────────────────────────────────────
local function applySlippery()
	local char = localPlayer.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	if hum then
		-- Simulate reduced friction via extra force application
		-- We rely on Roblox's physics; ice material already reduces traction
	end
end

-- ─── Lava damage ──────────────────────────────────────────────────────────────
local function setupLavaCheck(mazeFolder: Folder)
	for _, conn in ipairs(lavaConnections) do conn:Disconnect() end
	lavaConnections = {}

	local conn = RunService.Heartbeat:Connect(function()
		local char = localPlayer.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChild("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then return end

		for _, obj in ipairs(mazeFolder:GetDescendants()) do
			if obj:IsA("BasePart") and obj:FindFirstChild("LavaTag") then
				local dist = (obj.Position - hrp.Position).Magnitude
				if dist < Constants.CELL_SIZE * 0.6 then
					hum:TakeDamage(Constants.LAVA_DAMAGE_PER_SECOND / 30) -- per frame ~30fps
				end
			end
		end
	end)
	table.insert(lavaConnections, conn)
end

-- ─── Main proximity loop ──────────────────────────────────────────────────────
local proximityConn: RBXScriptConnection?

local function startProximityLoop()
	if proximityConn then proximityConn:Disconnect() end

	proximityConn = RunService.Heartbeat:Connect(function()
		local char = localPlayer.Character
		if not char or not currentMazeInfo then return end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChild("Humanoid")
		if not hrp or not hum then return end

		local mazeFolder = Workspace:FindFirstChild("Mazes")
			and Workspace.Mazes:FindFirstChild("Maze_" .. localPlayer.UserId)
		if not mazeFolder then return end

		local pos = hrp.Position

		-- Coin collection
		for _, obj in ipairs(mazeFolder:GetDescendants()) do
			if obj:IsA("BasePart") and obj:FindFirstChild("CoinTag") then
				local tag = obj:FindFirstChild("CoinTag").Value
				if not collectedCoins[tag] then
					local dist = (obj.Position - pos).Magnitude
					if dist < Constants.COIN_PICKUP_RADIUS then
						collectedCoins[tag] = true
						Remotes:WaitForChild(RemoteDefs.CollectCoin):FireServer(tag)
					end
				end
			end
		end

		-- Checkpoint activation
		for _, obj in ipairs(mazeFolder:GetDescendants()) do
			if obj:IsA("BasePart") and obj:FindFirstChild("CheckpointIndex") then
				local idx = tonumber(obj:FindFirstChild("CheckpointIndex").Value)
				if idx and not activatedCheckpoints[idx] then
					local dist = (obj.Position - pos).Magnitude
					if dist < Constants.CHECKPOINT_ACTIVATE_RADIUS then
						activatedCheckpoints[idx] = true
						Remotes:WaitForChild(RemoteDefs.ActivateCheckpoint):FireServer(idx)
						-- Visual feedback
						obj.Color = Color3.fromRGB(50, 255, 100)
					end
				end
			end
		end

		-- Exit detection
		local exitPortal = mazeFolder:FindFirstChild("ExitPortal")
		if exitPortal then
			local dist = (exitPortal.Position - pos).Magnitude
			if dist < Constants.CELL_SIZE then
				Remotes:WaitForChild(RemoteDefs.PlayerReachedExit):FireServer()
				proximityConn:Disconnect()
				proximityConn = nil
				clearHintArrows()
			end
		end

		-- Secret rooms
		for _, obj in ipairs(mazeFolder:GetDescendants()) do
			if obj:IsA("BasePart") and obj:FindFirstChild("SecretRoomIndex") then
				local idx = tonumber(obj:FindFirstChild("SecretRoomIndex").Value)
				if idx and not foundSecrets[idx] then
					local dist = (obj.Position - pos).Magnitude
					if dist < Constants.CELL_SIZE then
						foundSecrets[idx] = true
						Remotes:WaitForChild(RemoteDefs.EnterSecretRoom):FireServer(idx)
					end
				end
			end
		end

		-- Darkness: if dark world, apply local spotlight on character
		if currentMazeInfo and table.find(currentMazeInfo.mechanics or {}, "darkness") then
			-- Done in EffectController (point light attached to character)
		end
	end)
end

-- ─── Humanoid death handler ───────────────────────────────────────────────────
local function onCharacterAdded(char: Model)
	collectedCoins = {}
	activatedCheckpoints = {}
	foundSecrets = {}

	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		Remotes:WaitForChild(RemoteDefs.PlayerDied):FireServer()
	end)

	startProximityLoop()

	-- Setup lava check if applicable
	if currentMazeInfo and table.find(currentMazeInfo.mechanics or {}, "lava") then
		local mazeFolder = Workspace:WaitForChild("Mazes"):FindFirstChild("Maze_" .. localPlayer.UserId)
		if mazeFolder then
			setupLavaCheck(mazeFolder)
		end
	end
end

-- ─── Path hint input ──────────────────────────────────────────────────────────
local function requestHint()
	local waypoints = Remotes:WaitForChild(RemoteDefs.RequestPathHint):InvokeServer()
	if waypoints then
		showPathHint(waypoints)
	end
end

-- ─── Lighting / atmosphere (client-side = per-player, multiplayer-safe) ────────
local function getAtmosphere(): Atmosphere
	local Lighting = game:GetService("Lighting")
	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmos then
		atmos = Instance.new("Atmosphere")
		atmos.Parent = Lighting
	end
	return atmos
end

local function getSky(): Sky
	local Lighting = game:GetService("Lighting")
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	return sky
end

local function hasMechanic(mechanics: { string }?, name: string): boolean
	return mechanics ~= nil and table.find(mechanics, name) ~= nil
end

local HUB_DEFAULTS = {
	ambient    = Color3.fromRGB(120, 130, 160),
	fogEnd     = 1000,
	fogColor   = Color3.fromRGB(180, 195, 220),
}

local function applyHubLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.Ambient        = HUB_DEFAULTS.ambient
	Lighting.OutdoorAmbient = HUB_DEFAULTS.ambient
	Lighting.FogEnd         = HUB_DEFAULTS.fogEnd
	Lighting.FogStart       = HUB_DEFAULTS.fogEnd * 0.6
	Lighting.FogColor       = HUB_DEFAULTS.fogColor
	Lighting.ClockTime      = 14
	Lighting.ColorShift_Top    = Color3.fromRGB(180, 200, 255)
	Lighting.ColorShift_Bottom = Color3.fromRGB(140, 150, 180)
	local atmos = getAtmosphere()
	atmos.Density = 0.3
	atmos.Haze    = 0.5
	atmos.Color   = HUB_DEFAULTS.fogColor
	local sky = getSky()
	sky.CelestialBodiesShown = true
	sky.StarCount = 0
end

local function applyMazeLighting(mazeInfo)
	local Lighting = game:GetService("Lighting")
	local mechanics = mazeInfo.mechanics or {}
	local bg = mazeInfo.bg or {}
	local ambient = mazeInfo.ambient or Color3.fromRGB(150, 150, 150)
	local hasFog = hasMechanic(mechanics, "fog")
	local hasDark = hasMechanic(mechanics, "darkness")

	Lighting.Ambient        = ambient
	Lighting.OutdoorAmbient = ambient
	Lighting.ClockTime      = bg.clockTime or 14
	Lighting.ColorShift_Top    = bg.skyTop or ambient
	Lighting.ColorShift_Bottom = bg.skyBottom or ambient

	local fogEnd = mazeInfo.fogEnd or 500
	if hasFog then
		fogEnd = math.min(fogEnd, 70)
	end
	Lighting.FogEnd   = fogEnd
	Lighting.FogStart = hasFog and 5 or fogEnd * 0.45
	Lighting.FogColor = bg.skyBottom or ambient

	local atmos = getAtmosphere()
	atmos.Color = bg.skyBottom or ambient
	atmos.Decay = bg.skyTop or ambient
	if hasFog then
		atmos.Density = 0.88
		atmos.Haze    = 3.2
		atmos.Glare   = 0.05
	elseif hasDark then
		atmos.Density = 0.65
		atmos.Haze    = 1.8
		atmos.Glare   = 0
	else
		atmos.Density = 0.35
		atmos.Haze    = 1.0
		atmos.Glare   = 0.15
	end

	local sky = getSky()
	sky.CelestialBodiesShown = not hasDark
	sky.StarCount = hasDark and 4500 or 0
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function MazeController.onMazeLoaded(mazeInfo)
	currentMazeInfo = mazeInfo
	collectedCoins = {}
	activatedCheckpoints = {}
	foundSecrets = {}
	clearHintArrows()

	applyMazeLighting(mazeInfo)

	startProximityLoop()
end

function MazeController.onHubEntered()
	currentMazeInfo = nil
	collectedCoins = {}
	activatedCheckpoints = {}
	foundSecrets = {}
	clearHintArrows()
	if proximityConn then
		proximityConn:Disconnect()
		proximityConn = nil
	end
	applyHubLighting()
end

function MazeController.requestHint()
	requestHint()
end

function MazeController.init()
	applyHubLighting()
	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
end

return MazeController

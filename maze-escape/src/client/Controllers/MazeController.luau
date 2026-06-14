-- MazeController.luau
-- Handles client-side maze interactions: coins, checkpoints, exit, lava, secrets

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)
local Logger     = require(ReplicatedStorage.Shared.Logger)

local TAG = "MazeController"

local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local localPlayer = Players.LocalPlayer

local MazeController = {}

local currentMazeInfo = nil
local playerZone: "hub" | "maze" = "hub"
local zoneConn: RBXScriptConnection? = nil
local mazeWatchConn: RBXScriptConnection? = nil
local savedCameraMode: Enum.CameraMode? = nil
local savedCameraMinZoom: number? = nil
local savedCameraMaxZoom: number? = nil
local hintArrows: { BasePart } = {}
local isSlippery = false
local slipperyConn: RBXScriptConnection? = nil
local slideVelocity = Vector3.zero
local collectedCoins: { [string]: boolean } = {}
local activatedCheckpoints: { [number]: boolean } = {}
local foundSecrets: { [number]: boolean } = {}
local lavaConnections: { RBXScriptConnection } = {}
local lastLavaDamageTime = 0

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
local function clearSlippery()
	isSlippery = false
	slideVelocity = Vector3.zero
	if slipperyConn then
		slipperyConn:Disconnect()
		slipperyConn = nil
	end
end

local function hasSlipperyMechanic(): boolean
	if not currentMazeInfo then return false end
	return table.find(currentMazeInfo.mechanics or {}, "slippery") ~= nil
end

local function setupSlippery()
	clearSlippery()
	if not hasSlipperyMechanic() then return end

	isSlippery = true
	slipperyConn = RunService.Heartbeat:Connect(function(dt)
		if not isSlippery or playerZone ~= "maze" then return end

		local char = localPlayer.Character
		if not char then return end
		local hrp  = char:FindFirstChild("HumanoidRootPart")
		local hum  = char:FindFirstChild("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then return end

		local state = hum:GetState()
		local grounded = state == Enum.HumanoidStateType.Running
			or state == Enum.HumanoidStateType.RunningNoPhysics
			or state == Enum.HumanoidStateType.Landed
			or state == Enum.HumanoidStateType.Physics

		-- В воздухе — простое затухание, игрок не управляет
		if not grounded then
			slideVelocity = slideVelocity * (Constants.SLIPPERY_FRICTION ^ (dt * 60))
			local vel = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(slideVelocity.X, vel.Y, slideVelocity.Z)
			return
		end

		local moveDir = hum.MoveDirection
		local walkSpeed = hum.WalkSpeed
		local maxSpeed  = walkSpeed * Constants.SLIPPERY_MAX_SPEED_MULT

		-- ── Разложение скорости на продольную и боковую компоненты ──────────
		-- «Продольная» — вдоль текущего движения, «боковая» — поперёк (занос)
		local speed = slideVelocity.Magnitude
		local fwdAxis  -- направление текущего движения
		if speed > 0.5 then
			fwdAxis = slideVelocity.Unit
		else
			fwdAxis = Vector3.new(moveDir.X, 0, moveDir.Z)
			if fwdAxis.Magnitude < 0.05 then fwdAxis = Vector3.new(0, 0, 1) end
			fwdAxis = fwdAxis.Unit
		end

		local rightAxis = Vector3.new(-fwdAxis.Z, 0, fwdAxis.X)

		-- Проекции текущей скорости
		local vFwd  = slideVelocity:Dot(fwdAxis)
		local vSide = slideVelocity:Dot(rightAxis)

		-- ── Ускорение от ввода (только продольное — поперёк не «рулим» напрямую)
		if moveDir.Magnitude > 0.05 then
			local inputDir = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

			-- Проекция ввода на ось движения (ускорение вперёд/назад)
			local accelFwd = inputDir:Dot(fwdAxis) * Constants.SLIPPERY_ACCEL * dt * maxSpeed

			-- Слабый «руль» — очень маленькое боковое ускорение → занос сохраняется
			local accelSide = inputDir:Dot(rightAxis) * Constants.SLIPPERY_STEER * dt * maxSpeed

			vFwd  = vFwd  + accelFwd
			vSide = vSide + accelSide
		end

		-- ── Затухание: боковая компонента тормозит сильнее (занос гасится медленно)
		local decayFwd  = Constants.SLIPPERY_FRICTION ^ (dt * 60)
		local decaySide = Constants.SLIPPERY_SIDE_FRICTION ^ (dt * 60)

		vFwd  = vFwd  * decayFwd
		vSide = vSide * decaySide

		-- ── Сборка вектора и ограничение скорости
		slideVelocity = fwdAxis * vFwd + rightAxis * vSide

		local hSpeed = slideVelocity.Magnitude
		if hSpeed > maxSpeed * 1.35 then
			slideVelocity = slideVelocity.Unit * maxSpeed * 1.35
		end

		if hSpeed < 0.06 and moveDir.Magnitude < 0.05 then
			slideVelocity = Vector3.zero
		end

		local vel = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(slideVelocity.X, vel.Y, slideVelocity.Z)
	end)
end

-- ─── Lava damage (gradual — one tick at a time, not per-frame stack) ───────────
local function setupLavaCheck(mazeFolder: Folder)
	for _, conn in ipairs(lavaConnections) do conn:Disconnect() end
	lavaConnections = {}
	lastLavaDamageTime = 0

	local conn = RunService.Heartbeat:Connect(function()
		local char = localPlayer.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChild("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then return end

		local now = os.clock()
		if now - lastLavaDamageTime < Constants.LAVA_DAMAGE_INTERVAL then
			return
		end

		local onLava = false
		local hrpFlat = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
		for _, obj in ipairs(mazeFolder:GetDescendants()) do
			if obj:IsA("BasePart") and obj:FindFirstChild("LavaTag") then
				local lavaFlat = Vector3.new(obj.Position.X, 0, obj.Position.Z)
				if (lavaFlat - hrpFlat).Magnitude <= Constants.LAVA_TOUCH_RADIUS then
					onLava = true
					break
				end
			end
		end

		if onLava then
			lastLavaDamageTime = now
			hum:TakeDamage(Constants.LAVA_DAMAGE_PER_TICK)
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

		-- Checkpoint activation (dangerous worlds only)
		if currentMazeInfo.useCheckpoints then
			for _, obj in ipairs(mazeFolder:GetDescendants()) do
				if obj:IsA("BasePart") and obj:FindFirstChild("CheckpointIndex") then
					local idx = tonumber(obj:FindFirstChild("CheckpointIndex").Value)
					if idx and not activatedCheckpoints[idx] then
						local dist = (obj.Position - pos).Magnitude
						if dist < Constants.CHECKPOINT_ACTIVATE_RADIUS then
							activatedCheckpoints[idx] = true
							Remotes:WaitForChild(RemoteDefs.ActivateCheckpoint):FireServer(idx)
							obj.Color = Color3.fromRGB(50, 255, 100)
						end
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
	setupSlippery()

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

-- ─── Zone: hub vs maze (multiplayer-safe lighting & visibility) ───────────────

local function getOwnMazeName(): string
	return "Maze_" .. localPlayer.UserId
end

local function setInstanceHiddenLocally(inst: Instance, hidden: boolean)
	if inst:IsA("BasePart") then
		-- LocalTransparencyModifier is a property on BasePart (client-only), not an Instance
		inst.LocalTransparencyModifier = hidden and 1 or 0
	elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
		inst.Enabled = not hidden
	elseif inst:IsA("Light") then
		inst.Enabled = not hidden
	elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
		inst.Enabled = not hidden
	end
end

local function setMazeFolderHidden(folder: Instance, hidden: boolean)
	for _, desc in folder:GetDescendants() do
		setInstanceHiddenLocally(desc, hidden)
	end
	setInstanceHiddenLocally(folder, hidden)
end

local function updateMazeVisibility()
	local mazes = Workspace:FindFirstChild("Mazes")
	if not mazes then return end

	local inMazeZone = playerZone == "maze"
	local ownName = getOwnMazeName()

	for _, child in mazes:GetChildren() do
		local isOwn = child.Name == ownName
		local hide = not inMazeZone or not isOwn
		setMazeFolderHidden(child, hide)
	end
end

local applyHubLighting
local applyMazeLighting

local function applyMazeCamera()
	if savedCameraMode == nil then
		savedCameraMode = localPlayer.CameraMode
		savedCameraMinZoom = localPlayer.CameraMinZoomDistance
		savedCameraMaxZoom = localPlayer.CameraMaxZoomDistance
	end

	if Constants.MAZE_CAMERA_LOCK_FIRST_PERSON then
		localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		localPlayer.CameraMinZoomDistance = 0.5
		localPlayer.CameraMaxZoomDistance = 0.5
	else
		localPlayer.CameraMinZoomDistance = Constants.MAZE_CAMERA_MIN_ZOOM
		localPlayer.CameraMaxZoomDistance = Constants.MAZE_CAMERA_MAX_ZOOM
	end
end

local function applyHubCamera()
	if savedCameraMode ~= nil then
		localPlayer.CameraMode = savedCameraMode
		localPlayer.CameraMinZoomDistance = savedCameraMinZoom or 0.5
		localPlayer.CameraMaxZoomDistance = savedCameraMaxZoom or 128
		savedCameraMode = nil
		savedCameraMinZoom = nil
		savedCameraMaxZoom = nil
	end
end

local function applyZoneLighting()
	if playerZone == "hub" or not currentMazeInfo then
		applyHubLighting()
		Logger.debug(TAG, "Zone lighting → hub")
	else
		applyMazeLighting(currentMazeInfo)
		Logger.debug(TAG, "Zone lighting → maze", currentMazeInfo.worldName or "?")
	end
end

local function setPlayerZone(zone: "hub" | "maze", reason: string?)
	if playerZone == zone then
		updateMazeVisibility()
		return
	end
	playerZone = zone
	Logger.info(TAG, "Zone changed", zone, reason or "")
	if zone == "maze" then
		applyMazeCamera()
		setupSlippery()
	else
		applyHubCamera()
		clearSlippery()
	end
	applyZoneLighting()
	updateMazeVisibility()
end

local function updateZoneFromPosition()
	local char = localPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local newZone: "hub" | "maze" = hrp.Position.Y >= Constants.MAZE_ZONE_MIN_Y and "maze" or "hub"
	if newZone ~= playerZone then
		setPlayerZone(newZone, "position Y=" .. math.floor(hrp.Position.Y))
	end
end

local function watchMazeFolder()
	local mazes = Workspace:WaitForChild("Mazes")
	updateMazeVisibility()
	if mazeWatchConn then
		mazeWatchConn:Disconnect()
	end
	mazeWatchConn = mazes.ChildAdded:Connect(function()
		task.defer(updateMazeVisibility)
	end)
end

local function startZoneTracking()
	if zoneConn then
		zoneConn:Disconnect()
	end
	zoneConn = RunService.Heartbeat:Connect(updateZoneFromPosition)
	watchMazeFolder()
end

-- ─── Lighting / atmosphere (per-zone on this client only) ─────────────────────
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

applyHubLighting = function()
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

applyMazeLighting = function(mazeInfo)
	local Lighting = game:GetService("Lighting")
	local mechanics = mazeInfo.mechanics or {}
	local bg = mazeInfo.bg or {}
	local ambient = mazeInfo.ambient or Color3.fromRGB(150, 150, 150)
	local hasFog = hasMechanic(mechanics, "fog")
	local hasDark = hasMechanic(mechanics, "darkness")
	local isIce = mazeInfo.theme == "ice"

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
	elseif isIce then
		atmos.Density = 0.52
		atmos.Haze    = 1.7
		atmos.Glare   = 0
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

	-- Lighting follows zone — stay on hub look while physically in hub
	if playerZone == "maze" then
		applyMazeLighting(mazeInfo)
	else
		applyHubLighting()
	end
	updateMazeVisibility()

	startProximityLoop()
	setupSlippery()
end

function MazeController.onHubEntered()
	currentMazeInfo = nil
	collectedCoins = {}
	activatedCheckpoints = {}
	foundSecrets = {}
	clearHintArrows()
	clearSlippery()
	if proximityConn then
		proximityConn:Disconnect()
		proximityConn = nil
	end

	setPlayerZone("hub", "HubEntered")
end

function MazeController.requestHint()
	requestHint()
end

function MazeController.init()
	setPlayerZone("hub", "init")
	startZoneTracking()
	localPlayer.CharacterAdded:Connect(function(char)
		onCharacterAdded(char)
		if playerZone == "maze" then
			task.defer(applyMazeCamera)
		end
	end)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
end

return MazeController

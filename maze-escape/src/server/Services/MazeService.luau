-- MazeService.luau
-- Builds maze geometry in Workspace, handles player maze state.
-- Each player's maze is generated in its OWN isolated region high above the hub,
-- so the game is fully multiplayer-safe (no two mazes overlap).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local MazeGenerator  = require(ReplicatedStorage.Shared.MazeGenerator)
local RemoteDefs     = require(ReplicatedStorage.Shared.RemoteDefinitions)
local Logger         = require(ReplicatedStorage.Shared.Logger)

local TAG = "MazeService"

local PlayerDataService -- loaded in init to avoid circular dependency
local HubService        -- loaded in init
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local MazeService = {}

-- Per-player session state
local sessions: { [number]: any } = {}

-- Slot management for multiplayer placement
local usedSlots: { [number]: boolean } = {}

local mazeFolder: Folder

local CELL           = Constants.CELL_SIZE
local WALL_HEIGHT    = Constants.WALL_HEIGHT
local WALL_THICKNESS = Constants.WALL_THICKNESS

-- ─── Slot helpers ─────────────────────────────────────────────────────────────
local function acquireSlot(): number
	for i = 0, Constants.MAZE_MAX_SLOTS - 1 do
		if not usedSlots[i] then
			usedSlots[i] = true
			return i
		end
	end
	-- Fallback: reuse slot 0
	return 0
end

local function releaseSlot(slot: number)
	usedSlots[slot] = nil
end

local function getOrigin(slot: number): Vector3
	return Vector3.new(slot * Constants.MAZE_SLOT_SPACING, Constants.MAZE_BASE_Y, 0)
end

-- World-space center of a cell
local function cellWorld(origin: Vector3, x: number, y: number, height: number?): Vector3
	return Vector3.new(
		origin.X + (x - 1) * CELL + CELL / 2,
		origin.Y + (height or 0),
		origin.Z + (y - 1) * CELL + CELL / 2
	)
end

-- ─── Theme Materials & Colors ────────────────────────────────────────────────
local THEME_CONFIGS = {
	classic = {
		floor    = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(200, 185, 165) },
		wall     = { material = Enum.Material.Brick,         color = Color3.fromRGB(160, 145, 120) },
		ceiling  = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(180, 165, 145) },
	},
	forest = {
		floor    = { material = Enum.Material.Grass,         color = Color3.fromRGB(60, 120, 40)   },
		wall     = { material = Enum.Material.Wood,          color = Color3.fromRGB(80, 50, 20)    },
		ceiling  = { material = Enum.Material.LeafyGrass,    color = Color3.fromRGB(40, 100, 30)   },
	},
	ice = {
		floor    = { material = Enum.Material.Glacier,       color = Color3.fromRGB(180, 230, 255)  },
		wall     = { material = Enum.Material.Ice,           color = Color3.fromRGB(140, 210, 255)  },
		ceiling  = { material = Enum.Material.Ice,           color = Color3.fromRGB(160, 220, 255)  },
	},
	lava = {
		floor    = { material = Enum.Material.Rock,          color = Color3.fromRGB(60, 40, 30)    },
		wall     = { material = Enum.Material.Basalt,        color = Color3.fromRGB(80, 50, 30)    },
		ceiling  = { material = Enum.Material.Basalt,        color = Color3.fromRGB(50, 30, 20)    },
	},
	dark = {
		floor    = { material = Enum.Material.Concrete,      color = Color3.fromRGB(30, 25, 40)    },
		wall     = { material = Enum.Material.Slate,         color = Color3.fromRGB(20, 15, 30)    },
		ceiling  = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(15, 10, 25)    },
	},
	tech = {
		floor    = { material = Enum.Material.Metal,         color = Color3.fromRGB(40, 50, 70)    },
		wall     = { material = Enum.Material.DiamondPlate,  color = Color3.fromRGB(50, 60, 90)    },
		ceiling  = { material = Enum.Material.Metal,         color = Color3.fromRGB(30, 40, 60)    },
	},
	chaos = {
		floor    = { material = Enum.Material.Neon,          color = Color3.fromRGB(60, 0, 80)     },
		wall     = { material = Enum.Material.Basalt,        color = Color3.fromRGB(40, 0, 60)     },
		ceiling  = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(20, 0, 40)     },
	},
}

-- ─── Geometry helpers ─────────────────────────────────────────────────────────
local function makePart(parent: Instance, name: string, size: Vector3, pos: Vector3, theme: string, surface: string): BasePart
	local cfg = THEME_CONFIGS[theme] and THEME_CONFIGS[theme][surface] or THEME_CONFIGS.classic.floor
	local p = Instance.new("Part")
	p.Name     = name
	p.Size     = size
	p.CFrame   = CFrame.new(pos)
	p.Anchored = true
	p.Material = cfg.material
	p.Color    = cfg.color
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	p.Parent   = parent
	return p
end

local function addPointLight(part: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color      = color
	light.Brightness = brightness
	light.Range      = range
	light.Parent     = part
end

-- ─── Per-world background (each maze gets its own surrounding backdrop) ────────
local function buildBackground(worldConfig, origin: Vector3, folder: Folder, W: number, H: number)
	local bg = worldConfig.bg or { skyTop = Color3.fromRGB(120,120,140), skyBottom = Color3.fromRGB(180,180,200) }
	local centerX = origin.X + (W * CELL) / 2
	local centerZ = origin.Z + (H * CELL) / 2
	local span    = math.max(W, H) * CELL
	local margin  = span * 0.9
	local domeY   = origin.Y + WALL_HEIGHT
	local height  = 400

	local bgFolder = Instance.new("Folder")
	bgFolder.Name = "Background"
	bgFolder.Parent = folder

	local function bgPanel(name, size, pos, color, material, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(pos)
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Material = material or Enum.Material.SmoothPlastic
		p.Color = color
		if transparency then p.Transparency = transparency end
		p.Parent = bgFolder
		return p
	end

	local half = span / 2 + margin

	-- 4 backdrop walls (gradient: darker at bottom, lighter toward top)
	local wallBaseY = domeY + height / 2 - 60
	bgPanel("BG_N", Vector3.new(span + margin * 2, height, 4),
		Vector3.new(centerX, wallBaseY, centerZ - half), bg.skyBottom)
	bgPanel("BG_S", Vector3.new(span + margin * 2, height, 4),
		Vector3.new(centerX, wallBaseY, centerZ + half), bg.skyBottom)
	bgPanel("BG_E", Vector3.new(4, height, span + margin * 2),
		Vector3.new(centerX + half, wallBaseY, centerZ), bg.skyBottom)
	bgPanel("BG_W", Vector3.new(4, height, span + margin * 2),
		Vector3.new(centerX - half, wallBaseY, centerZ), bg.skyBottom)

	-- Sky ceiling
	bgPanel("BG_Top", Vector3.new(span + margin * 2, 4, span + margin * 2),
		Vector3.new(centerX, domeY + height - 60, centerZ), bg.skyTop, Enum.Material.Neon, 0.15)

	-- Layered sky dome for atmospheric gradient
	local skyWidth = span + margin * 2
	for layer = 1, 5 do
		local t = layer / 5
		local layerColor = bg.skyBottom:Lerp(bg.skyTop, t)
		local layerY = domeY + 40 + layer * 55
		local layerSize = skyWidth * (0.85 + layer * 0.06)
		bgPanel("SkyLayer_" .. layer,
			Vector3.new(layerSize, 6, layerSize),
			Vector3.new(centerX, layerY, centerZ),
			layerColor,
			Enum.Material.SmoothPlastic,
			0.12 + layer * 0.1)
	end

	-- Soft sky glow above the maze
	local glow = bgPanel("SkyGlow",
		Vector3.new(skyWidth * 1.1, skyWidth * 0.55, skyWidth * 1.1),
		Vector3.new(centerX, domeY + height - 80, centerZ),
		bg.skyTop,
		Enum.Material.Neon,
		0.88)
	glow.Shape = Enum.PartType.Ball
end

-- ─── Per-world ambient particle effects ───────────────────────────────────────
local function buildEffects(worldConfig, origin: Vector3, folder: Folder, W: number, H: number)
	local effect = worldConfig.bg and worldConfig.bg.effect or "none"
	if effect == "none" then return end

	local centerX = origin.X + (W * CELL) / 2
	local centerZ = origin.Z + (H * CELL) / 2
	local span    = math.max(W, H) * CELL

	local emitterPart = Instance.new("Part")
	emitterPart.Name = "EffectEmitter"
	emitterPart.Size = Vector3.new(span, 1, span)
	emitterPart.CFrame = CFrame.new(centerX, origin.Y + WALL_HEIGHT + 30, centerZ)
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.Transparency = 1
	emitterPart.Parent = folder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 60
	emitter.Lifetime = NumberRange.new(4, 7)
	emitter.Speed = NumberRange.new(2, 6)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.4

	if effect == "snow" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		emitter.Size = NumberSequence.new(0.4)
		emitter.Acceleration = Vector3.new(0, -8, 0)
		emitter.Rate = 120
	elseif effect == "embers" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 120, 0))
		emitter.Size = NumberSequence.new(0.5)
		emitter.Acceleration = Vector3.new(0, 6, 0)
		emitter.LightEmission = 1
		emitter.Rate = 100
	elseif effect == "leaves" then
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 180, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 140, 40)),
		})
		emitter.Size = NumberSequence.new(0.7)
		emitter.Acceleration = Vector3.new(2, -6, 0)
		emitter.Rate = 50
	elseif effect == "stars" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 255))
		emitter.Size = NumberSequence.new(0.3)
		emitter.Speed = NumberRange.new(0, 1)
		emitter.LightEmission = 1
		emitter.Rate = 40
	elseif effect == "sparks" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(0, 220, 255))
		emitter.Size = NumberSequence.new(0.35)
		emitter.LightEmission = 1
		emitter.Acceleration = Vector3.new(0, -4, 0)
		emitter.Rate = 70
	elseif effect == "chaos" then
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(1,   Color3.fromRGB(0, 0, 255)),
		})
		emitter.Size = NumberSequence.new(0.5)
		emitter.LightEmission = 1
		emitter.Rate = 120
	end

	emitter.Parent = emitterPart
end

-- ─── Maze Builder ─────────────────────────────────────────────────────────────
local function buildMaze(worldConfig, mazeData, folder: Folder, origin: Vector3)
	local theme = worldConfig.theme
	local cells = mazeData.cells
	local W, H  = mazeData.width, mazeData.height

	local bx, bz = origin.X, origin.Z
	local floorY = origin.Y

	-- Floor slab
	makePart(folder, "MazeFloor",
		Vector3.new(W * CELL + WALL_THICKNESS, 2, H * CELL + WALL_THICKNESS),
		Vector3.new(bx + W * CELL / 2, floorY - 1, bz + H * CELL / 2),
		theme, "floor")

	-- Ceiling
	local ceilPart = makePart(folder, "MazeCeiling",
		Vector3.new(W * CELL + WALL_THICKNESS, 1, H * CELL + WALL_THICKNESS),
		Vector3.new(bx + W * CELL / 2, floorY + WALL_HEIGHT + 0.5, bz + H * CELL / 2),
		theme, "ceiling")
	ceilPart.Transparency = 0.9
	ceilPart.CanCollide = false

	-- Walls per cell
	for y = 1, H do
		for x = 1, W do
			local cell = cells[y][x]
			local cx = bx + (x - 1) * CELL
			local cz = bz + (y - 1) * CELL
			local midY = floorY + WALL_HEIGHT / 2

			if cell.walls.north then
				makePart(folder, "W_N_"..x.."_"..y,
					Vector3.new(CELL + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS),
					Vector3.new(cx + CELL/2, midY, cz),
					theme, "wall")
			end
			if cell.walls.west then
				makePart(folder, "W_W_"..x.."_"..y,
					Vector3.new(WALL_THICKNESS, WALL_HEIGHT, CELL + WALL_THICKNESS),
					Vector3.new(cx, midY, cz + CELL/2),
					theme, "wall")
			end
			if y == H and cell.walls.south then
				makePart(folder, "W_S_"..x.."_"..y,
					Vector3.new(CELL + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS),
					Vector3.new(cx + CELL/2, midY, cz + CELL),
					theme, "wall")
			end
			if x == W and cell.walls.east then
				makePart(folder, "W_E_"..x.."_"..y,
					Vector3.new(WALL_THICKNESS, WALL_HEIGHT, CELL + WALL_THICKNESS),
					Vector3.new(cx + CELL, midY, cz + CELL/2),
					theme, "wall")
			end
		end
	end

	-- Ambient lights along ceiling
	local lightSpacing = 4
	for y = 1, H, lightSpacing do
		for x = 1, W, lightSpacing do
			local lightPart = Instance.new("Part")
			lightPart.Name = "Light_"..x.."_"..y
			lightPart.Size = Vector3.new(0.5, 0.5, 0.5)
			lightPart.CFrame = CFrame.new(bx + (x-1)*CELL + CELL/2, floorY + WALL_HEIGHT - 1, bz + (y-1)*CELL + CELL/2)
			lightPart.Anchored = true
			lightPart.CanCollide = false
			lightPart.Transparency = 1
			lightPart.Parent = folder
			addPointLight(lightPart, worldConfig.ambientColor, 1.5, CELL * 3)
		end
	end
end

local function placeSpecials(worldConfig, mazeData, folder: Folder, origin: Vector3)
	local floorY = origin.Y

	-- Exit portal
	local exitPos = cellWorld(origin, mazeData.exitPos.x, mazeData.exitPos.y, 0.25 + floorY - origin.Y)
	local exitPart = Instance.new("Part")
	exitPart.Name = "ExitPortal"
	exitPart.Size = Vector3.new(CELL - 2, 0.5, CELL - 2)
	exitPart.CFrame = CFrame.new(Vector3.new(exitPos.X, floorY + 0.25, exitPos.Z))
	exitPart.Anchored = true
	exitPart.CanCollide = false
	exitPart.Material = Enum.Material.Neon
	exitPart.Color = Color3.fromRGB(0, 255, 150)
	exitPart.Parent = folder
	addPointLight(exitPart, Color3.fromRGB(0, 255, 150), 3, 24)

	task.spawn(function()
		while exitPart.Parent do
			local tween = TweenService:Create(exitPart,
				TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Color = Color3.fromRGB(0, 200, 255) })
			tween:Play()
			task.wait(2)
			tween:Cancel()
		end
	end)

	-- Coins
	for _, pos in ipairs(mazeData.coinPositions) do
		local w = cellWorld(origin, pos.x, pos.y)
		local coin = Instance.new("Part")
		coin.Name = "Coin_"..pos.x.."_"..pos.y
		coin.Size = Vector3.new(2, 0.3, 2)
		coin.CFrame = CFrame.new(Vector3.new(w.X, floorY + 2.5, w.Z))
		coin.Anchored = true
		coin.CanCollide = false
		coin.Material = Enum.Material.Neon
		coin.Color = Color3.fromRGB(255, 200, 30)
		coin.Shape = Enum.PartType.Cylinder

		local tag = Instance.new("StringValue")
		tag.Name = "CoinTag"
		tag.Value = pos.x .. "_" .. pos.y
		tag.Parent = coin
		coin.Parent = folder

		task.spawn(function()
			local angle = 0
			while coin.Parent do
				angle += 0.05
				coin.CFrame = CFrame.new(w.X, floorY + 2.5 + math.sin(angle) * 0.3, w.Z)
					* CFrame.Angles(0, angle, math.pi / 2)
				task.wait(0.03)
			end
		end)
	end

	-- Checkpoints
	for i, pos in ipairs(mazeData.checkpoints) do
		local w = cellWorld(origin, pos.x, pos.y)
		local cp = Instance.new("Part")
		cp.Name = "Checkpoint_" .. i
		cp.Size = Vector3.new(CELL - 2, 0.3, CELL - 2)
		cp.CFrame = CFrame.new(Vector3.new(w.X, floorY + 0.15, w.Z))
		cp.Anchored = true
		cp.CanCollide = false
		cp.Material = Enum.Material.Neon
		cp.Color = Color3.fromRGB(100, 100, 255)
		cp.Parent = folder

		local cpTag = Instance.new("StringValue")
		cpTag.Name = "CheckpointIndex"
		cpTag.Value = tostring(i)
		cpTag.Parent = cp

		local cpPos = Instance.new("Vector3Value")
		cpPos.Name = "CellPos"
		cpPos.Value = Vector3.new(pos.x, 0, pos.y)
		cpPos.Parent = cp

		addPointLight(cp, Color3.fromRGB(100, 100, 255), 2, 18)
	end

	-- Secret rooms
	for i, pos in ipairs(mazeData.secretRooms) do
		local w = cellWorld(origin, pos.x, pos.y)
		local secretFloor = Instance.new("Part")
		secretFloor.Name = "SecretRoom_" .. i
		secretFloor.Size = Vector3.new(CELL, 0.4, CELL)
		secretFloor.CFrame = CFrame.new(Vector3.new(w.X, floorY + 0.2, w.Z))
		secretFloor.Anchored = true
		secretFloor.CanCollide = false
		secretFloor.Material = Enum.Material.Neon
		secretFloor.Color = Color3.fromRGB(180, 0, 255)
		secretFloor.Parent = folder
		addPointLight(secretFloor, Color3.fromRGB(180, 0, 255), 2, 14)

		local tag = Instance.new("StringValue")
		tag.Name = "SecretRoomIndex"
		tag.Value = tostring(i)
		tag.Parent = secretFloor
	end

	-- Lava patches
	if table.find(worldConfig.mechanics, "lava") then
		local W, H = mazeData.width, mazeData.height
		for y = 2, H - 1 do
			for x = 2, W - 1 do
				if math.random() < 0.08 then
					local w = cellWorld(origin, x, y)
					local lava = Instance.new("Part")
					lava.Name = "Lava_"..x.."_"..y
					lava.Size = Vector3.new(CELL - 1, 0.3, CELL - 1)
					lava.CFrame = CFrame.new(Vector3.new(w.X, floorY + 0.15, w.Z))
					lava.Anchored = true
					lava.CanCollide = false
					lava.Material = Enum.Material.Neon
					lava.Color = Color3.fromRGB(255, 80, 0)
					lava.Parent = folder

					local lavaTg = Instance.new("StringValue")
					lavaTg.Name = "LavaTag"
					lavaTg.Parent = lava

					addPointLight(lava, Color3.fromRGB(255, 80, 0), 2, 12)
				end
			end
		end
	end

	if table.find(worldConfig.mechanics, "slippery") then
		local tag = Instance.new("StringValue")
		tag.Name = "SlipperyFloor"
		tag.Parent = folder
	end
end

-- ─── Session Management ───────────────────────────────────────────────────────
local function clearMaze(player: Player)
	local existing = mazeFolder:FindFirstChild("Maze_" .. player.UserId)
	if existing then existing:Destroy() end
end

local function spawnPlayerAtMaze(player: Player, session)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local origin = session.origin
	local w = cellWorld(origin, session.mazeData.startPos.x, session.mazeData.startPos.y)
	hrp.CFrame = CFrame.new(Vector3.new(w.X, origin.Y + 4, w.Z))
end

function MazeService.endSession(player: Player)
	local session = sessions[player.UserId]
	if session then
		releaseSlot(session.slot)
	end
	sessions[player.UserId] = nil
	clearMaze(player)
end

function MazeService.startMaze(player: Player, worldId: number)
	local worldConfig = Constants.WORLDS[worldId]
	if not worldConfig then
		Logger.warn(TAG, "Unknown world", player.Name, "worldId=" .. tostring(worldId))
		return
	end

	-- Reuse existing slot if player already has a session, else acquire a new one
	local existing = sessions[player.UserId]
	local slot = existing and existing.slot or acquireSlot()
	local origin = getOrigin(slot)

	Logger.info(TAG, "Starting maze", player.Name, worldConfig.name,
		worldConfig.mazeSize.width .. "x" .. worldConfig.mazeSize.height, "slot=" .. slot)

	clearMaze(player)

	local seed = os.time() + player.UserId + math.random(1, 99999)
	local mazeData = MazeGenerator.generate(
		worldConfig.mazeSize.width,
		worldConfig.mazeSize.height,
		seed
	)

	local folder = Instance.new("Folder")
	folder.Name = "Maze_" .. player.UserId
	folder.Parent = mazeFolder

	buildMaze(worldConfig, mazeData, folder, origin)
	placeSpecials(worldConfig, mazeData, folder, origin)

	local bgOk, bgErr = pcall(buildBackground, worldConfig, origin, folder, mazeData.width, mazeData.height)
	if not bgOk then
		Logger.warn(TAG, "Background build failed (maze still playable)", tostring(bgErr))
	end

	local fxOk, fxErr = pcall(buildEffects, worldConfig, origin, folder, mazeData.width, mazeData.height)
	if not fxOk then
		Logger.warn(TAG, "Effects build failed", tostring(fxErr))
	end

	Logger.info(TAG, "Maze built",
		"coins=" .. #mazeData.coinPositions,
		"checkpoints=" .. #mazeData.checkpoints,
		"secrets=" .. #mazeData.secretRooms)

	sessions[player.UserId] = {
		worldId          = worldId,
		slot             = slot,
		origin           = origin,
		mazeData         = mazeData,
		startTime        = os.time(),
		activeCheckpoint = nil,
		coinsCollected   = 0,
		usedCheckpoint   = false,
		hintUsed         = false,
	}

	Remotes:WaitForChild(RemoteDefs.MazeLoaded):FireClient(player, {
		worldId   = worldId,
		worldName = worldConfig.name,
		theme     = worldConfig.theme,
		mechanics = worldConfig.mechanics,
		width     = mazeData.width,
		height    = mazeData.height,
		fogEnd    = worldConfig.fogEnd,
		ambient   = worldConfig.ambientColor,
		bg        = worldConfig.bg,
	})

	task.delay(0.4, function()
		local s = sessions[player.UserId]
		if s then
			spawnPlayerAtMaze(player, s)
			Logger.info(TAG, "Player teleported to maze start", player.Name)
		end
	end)
end

-- ─── Remote Handlers ─────────────────────────────────────────────────────────
local function setupRemotes()
	Remotes:WaitForChild(RemoteDefs.PlayerReachedExit).OnServerEvent:Connect(function(player)
		local session = sessions[player.UserId]
		if not session then
			Logger.warn(TAG, "Exit reached but no session", player.Name)
			return
		end

		local elapsed = os.time() - session.startTime
		Logger.info(TAG, "Maze completed", player.Name, "time=" .. elapsed .. "s", "world=" .. session.worldId)
		local worldId = session.worldId
		local data    = PlayerDataService.get(player)
		if not data then return end

		if not data.BestTimes[worldId] or elapsed < data.BestTimes[worldId] then
			data.BestTimes[worldId] = elapsed
		end

		data.CompletedWorlds[worldId] = true
		data.TotalMazesCompleted = (data.TotalMazesCompleted or 0) + 1

		PlayerDataService.addCoins(player, Constants.COIN_PER_MAZE)
		PlayerDataService.addXP(player, Constants.XP_MAZE_COMPLETE)

		if elapsed < 60 then
			PlayerDataService.unlockAchievement(player, "speed_run")
		end
		if not session.usedCheckpoint then
			PlayerDataService.unlockAchievement(player, "no_checkpoint")
		end
		PlayerDataService.checkAchievements(player)

		-- Quest progress
		data.QuestProgress["complete_maze"]   = (data.QuestProgress["complete_maze"]   or 0) + 1
		data.QuestProgress["complete_3_maze"] = (data.QuestProgress["complete_3_maze"] or 0) + 1
		data.QuestProgress["weekly_mazes"]    = (data.QuestProgress["weekly_mazes"]    or 0) + 1
		if worldId == 2 then
			data.QuestProgress["complete_world2"] = (data.QuestProgress["complete_world2"] or 0) + 1
		end

		local nextWorldId = worldId + 1
		if Constants.WORLDS[nextWorldId] then
			data.CurrentWorld = nextWorldId
		end

		Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
			title = "Maze Complete!",
			text  = "Time: " .. math.floor(elapsed / 60) .. "m " .. (elapsed % 60) .. "s — returning to hub",
			icon  = "🏆",
			color = "gold",
		})

		Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)

		-- Return to hub after a short delay
		task.delay(2.5, function()
			if player.Parent then
				MazeService.endSession(player)
				HubService.teleportToHub(player)
			end
		end)
	end)

	Remotes:WaitForChild(RemoteDefs.ActivateCheckpoint).OnServerEvent:Connect(function(player, cpIndex: number)
		local session = sessions[player.UserId]
		if not session then return end

		local maze = mazeFolder:FindFirstChild("Maze_"..player.UserId)
		if not maze then return end

		local cpPart = maze:FindFirstChild("Checkpoint_" .. cpIndex)
		if not cpPart then return end

		cpPart.Color = Color3.fromRGB(50, 255, 100)

		local posVal = cpPart:FindFirstChild("CellPos")
		if posVal then
			session.activeCheckpoint = { x = posVal.Value.X, y = posVal.Value.Z }
		end
		session.usedCheckpoint = true
	end)

	Remotes:WaitForChild(RemoteDefs.CollectCoin).OnServerEvent:Connect(function(player, coinTag: string)
		local session = sessions[player.UserId]
		if not session then return end

		local folder = mazeFolder:FindFirstChild("Maze_" .. player.UserId)
		if not folder then return end

		local coin = folder:FindFirstChild("Coin_" .. coinTag)
		if not coin then return end

		coin:Destroy()
		session.coinsCollected += 1
		PlayerDataService.addCoins(player, Constants.COIN_VALUE)

		local data = PlayerDataService.get(player)
		if data then
			data.QuestProgress["collect_coins_50"] = (data.QuestProgress["collect_coins_50"] or 0) + 1
			data.QuestProgress["weekly_coins"]     = (data.QuestProgress["weekly_coins"]     or 0) + 1
		end
	end)

	Remotes:WaitForChild(RemoteDefs.EnterSecretRoom).OnServerEvent:Connect(function(player, roomIndex: number)
		local data = PlayerDataService.get(player)
		if not data then return end

		local session = sessions[player.UserId]
		local sessionWorldId = session and session.worldId or 0
		local key = "secret_found_" .. sessionWorldId .. "_" .. roomIndex
		if data.Achievements[key] then return end
		data.Achievements[key] = true

		data.SecretRoomsFound = (data.SecretRoomsFound or 0) + 1
		data.QuestProgress["find_secret"]    = (data.QuestProgress["find_secret"]    or 0) + 1
		data.QuestProgress["weekly_secrets"] = (data.QuestProgress["weekly_secrets"] or 0) + 1

		PlayerDataService.addCoins(player, 15)
		PlayerDataService.addXP(player, Constants.XP_SECRET_FOUND)
		PlayerDataService.checkAchievements(player)

		Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
			title = "Secret Found!",
			text  = "You discovered a secret room! +15 coins",
			icon  = "🔮",
			color = "purple",
		})
	end)

	Remotes:WaitForChild(RemoteDefs.PlayerDied).OnServerEvent:Connect(function(player)
		local session = sessions[player.UserId]
		if not session then return end

		task.delay(0.5, function()
			local s = sessions[player.UserId]
			if not s or not player.Character then return end
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end

			if s.activeCheckpoint then
				local w = cellWorld(s.origin, s.activeCheckpoint.x, s.activeCheckpoint.y)
				hrp.CFrame = CFrame.new(Vector3.new(w.X, s.origin.Y + 4, w.Z))
			else
				spawnPlayerAtMaze(player, s)
			end
		end)
	end)

	Remotes:WaitForChild(RemoteDefs.RequestPathHint).OnServerInvoke = function(player)
		local session = sessions[player.UserId]
		if not session then return nil end

		local char = player.Character
		if not char then return nil end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return nil end

		local origin = session.origin
		local pos = hrp.Position
		local cellX = math.clamp(math.round((pos.X - origin.X) / CELL) + 1, 1, session.mazeData.width)
		local cellY = math.clamp(math.round((pos.Z - origin.Z) / CELL) + 1, 1, session.mazeData.height)

		local path = MazeGenerator.findPath(session.mazeData, cellX, cellY)
		session.hintUsed = true

		if path and #path > 1 then
			local waypoints = {}
			for i = 1, math.min(6, #path) do
				local p = path[i]
				local w = cellWorld(origin, p.x, p.y)
				table.insert(waypoints, { x = w.X, y = origin.Y + 1.5, z = w.Z })
			end
			return waypoints
		end
		return nil
	end

	Remotes:WaitForChild(RemoteDefs.SkipLevel).OnServerInvoke = function(player)
		local session = sessions[player.UserId]
		local data = PlayerDataService.get(player)
		if not data then return false end

		local worldId = session and session.worldId or data.CurrentWorld
		data.CompletedWorlds[worldId] = true
		data.TotalMazesCompleted = (data.TotalMazesCompleted or 0) + 1

		local nextWorldId = worldId + 1
		if Constants.WORLDS[nextWorldId] then
			data.CurrentWorld = nextWorldId
		end

		MazeService.endSession(player)
		Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
		HubService.teleportToHub(player)
		return true
	end
end

function MazeService.init()
	PlayerDataService = require(script.Parent.PlayerDataService)
	HubService        = require(script.Parent.HubService)

	mazeFolder = Workspace:FindFirstChild("Mazes") or Instance.new("Folder")
	mazeFolder.Name = "Mazes"
	mazeFolder.Parent = Workspace

	setupRemotes()

	-- On spawn, send the player to the hub (they pick a world there)
	local function setupPlayer(player: Player)
		Logger.info(TAG, "Setting up player", player.Name, "UserId=" .. player.UserId)

		local function sendToHub()
			-- Wait briefly for player data (now instant in Studio)
			for _ = 1, 20 do
				if PlayerDataService.get(player) then break end
				task.wait(0.05)
			end
			HubService.teleportToHub(player)
		end

		player.CharacterAdded:Connect(sendToHub)
		if player.Character then
			task.spawn(sendToHub)
		end
	end

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		MazeService.endSession(player)
	end)

	-- MarketplaceService product processing
	local MarketplaceService = game:GetService("MarketplaceService")
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

		local productId = receiptInfo.ProductId

		if productId == Constants.PRODUCT_IDS.SkipLevel
			or productId == Constants.PRODUCT_IDS.UnlockWorld then
			HubService.handleProductPurchase(player, productId)
		elseif productId == Constants.PRODUCT_IDS.PathHint then
			Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
				title = "Path Hint",
				text  = "Hint activated! Press H or the map button.",
				icon  = "🗺️",
				color = "blue",
			})
		elseif productId == Constants.PRODUCT_IDS.TeleportCheckpoint then
			local session = sessions[player.UserId]
			if session and session.activeCheckpoint and player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local w = cellWorld(session.origin, session.activeCheckpoint.x, session.activeCheckpoint.y)
					hrp.CFrame = CFrame.new(Vector3.new(w.X, session.origin.Y + 4, w.Z))
				end
			end
		elseif productId == Constants.PRODUCT_IDS.Revive then
			local session = sessions[player.UserId]
			if session and player.Character then
				local hum = player.Character:FindFirstChild("Humanoid")
				if hum then hum.Health = hum.MaxHealth end
				spawnPlayerAtMaze(player, session)
			end
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	Logger.info(TAG, "Initialized", "mazeFolder=" .. mazeFolder:GetFullName())
end

return MazeService

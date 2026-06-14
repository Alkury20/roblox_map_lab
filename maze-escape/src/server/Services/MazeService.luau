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
local BonusShapes    = require(ReplicatedStorage.Shared.BonusShapes)
local PolarMaze      = require(ReplicatedStorage.Shared.PolarMaze)
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
		floor    = { material = Enum.Material.Glacier,       color = Color3.fromRGB(125, 142, 162) },
		wall     = { material = Enum.Material.Ice,           color = Color3.fromRGB(98, 118, 138)  },
		ceiling  = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(82, 96, 112)   },
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
local function applyIceFloorPhysics(part: BasePart, theme: string)
	if theme == "ice" then
		part.CustomPhysicalProperties = PhysicalProperties.new(
			0.7,
			Constants.SLIPPERY_FLOOR_FRICTION,
			0.05,
			1,
			1
		)
	end
end

local function getAmbientLightParams(theme: string): (number, number)
	if theme == "ice" then
		return 0.6, Constants.CELL_SIZE * 2.5
	end
	return 1.5, Constants.CELL_SIZE * 3
end

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
	if surface == "floor" then
		applyIceFloorPhysics(p, theme)
	end
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
	local isIce = worldConfig.theme == "ice"
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
		Vector3.new(centerX, domeY + height - 60, centerZ), bg.skyTop,
		isIce and Enum.Material.SmoothPlastic or Enum.Material.Neon,
		isIce and 0.4 or 0.15)

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
		isIce and Enum.Material.SmoothPlastic or Enum.Material.Neon,
		isIce and 0.95 or 0.88)
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
		emitter.Color = ColorSequence.new(Color3.fromRGB(185, 195, 210))
		emitter.Size = NumberSequence.new(0.35)
		emitter.Acceleration = Vector3.new(0, -6, 0)
		emitter.Rate = 55
		emitter.LightEmission = 0
		emitter.Transparency = NumberSequence.new(0.15)
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
local function buildMaze(worldConfig, mazeData, folder: Folder, origin: Vector3, isShaped: boolean?)
	local theme = worldConfig.theme
	local cells = mazeData.cells
	local W, H  = mazeData.width, mazeData.height

	local bx, bz = origin.X, origin.Z
	local floorY = origin.Y

	local function isBlockedOrEdge(nx: number, ny: number): boolean
		if nx < 1 or nx > W or ny < 1 or ny > H then return true end
		return cells[ny][nx].blocked == true
	end

	if not isShaped then
		-- Rectangular floor slab
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
	end

	-- Walls per cell. For shaped mazes, also seal any side facing a blocked
	-- cell or the grid edge so the maze stays fully enclosed.
	for y = 1, H do
		for x = 1, W do
			local cell = cells[y][x]
			if cell.blocked then
				continue
			end
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
			if cell.walls.south and (y == H or isBlockedOrEdge(x, y + 1)) then
				makePart(folder, "W_S_"..x.."_"..y,
					Vector3.new(CELL + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS),
					Vector3.new(cx + CELL/2, midY, cz + CELL),
					theme, "wall")
			end
			if cell.walls.east and (x == W or isBlockedOrEdge(x + 1, y)) then
				makePart(folder, "W_E_"..x.."_"..y,
					Vector3.new(WALL_THICKNESS, WALL_HEIGHT, CELL + WALL_THICKNESS),
					Vector3.new(cx + CELL, midY, cz + CELL/2),
					theme, "wall")
			end
		end
	end

	-- Ambient lights along ceiling (skip blocked cells)
	local lightBright, lightRange = getAmbientLightParams(theme)
	local lightSpacing = 4
	for y = 1, H, lightSpacing do
		for x = 1, W, lightSpacing do
			if cells[y][x].blocked then continue end
			local lightPart = Instance.new("Part")
			lightPart.Name = "Light_"..x.."_"..y
			lightPart.Size = Vector3.new(0.5, 0.5, 0.5)
			lightPart.CFrame = CFrame.new(bx + (x-1)*CELL + CELL/2, floorY + WALL_HEIGHT - 1, bz + (y-1)*CELL + CELL/2)
			lightPart.Anchored = true
			lightPart.CanCollide = false
			lightPart.Transparency = 1
			lightPart.Parent = folder
			addPointLight(lightPart, worldConfig.ambientColor, lightBright, lightRange)
		end
	end
end

-- Continuous cell coords (px, py may be fractional) → world position at origin Y
local function outlineWorld(origin: Vector3, px: number, py: number): Vector3
	return Vector3.new(
		origin.X + (px - 1) * CELL + CELL / 2,
		origin.Y,
		origin.Z + (py - 1) * CELL + CELL / 2
	)
end

-- Draw a flat triangle (two wedge parts) — used to fill shaped floors smoothly.
local FLOOR_THICK = 2
local function floorTriangle(folder: Folder, a: Vector3, b: Vector3, c: Vector3, material: Enum.Material, color: Color3)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b

	local right = ac:Cross(ab)
	if right.Magnitude < 1e-4 then return end
	right = right.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local function wedge(size: Vector3, cf: CFrame)
		local w = Instance.new("WedgePart")
		w.Name = "BonusFloor"
		w.Anchored = true
		w.CanCollide = true
		w.Size = size
		w.CFrame = cf
		w.Material = material
		w.Color = color
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Parent = folder
	end

	wedge(Vector3.new(FLOOR_THICK, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + b) / 2, right, up, back))
	wedge(Vector3.new(FLOOR_THICK, height, math.abs(ac:Dot(back))),
		CFrame.fromMatrix((a + c) / 2, -right, up, -back))
end

-- Build the smooth shaped floor + perimeter wall that follow the TRUE outline
-- of the bonus shape (circle / star / pentagon / overgrown) — no square blocks.
local function buildBonusShell(worldConfig, mazeData, folder: Folder, origin: Vector3)
	local shape = mazeData.shape
	if not shape then return end

	local W, H = mazeData.width, mazeData.height
	local floorY = origin.Y
	local theme = worldConfig.theme
	local floorCfg = THEME_CONFIGS[theme] and THEME_CONFIGS[theme].floor or THEME_CONFIGS.classic.floor
	local wallCfg  = THEME_CONFIGS[theme] and THEME_CONFIGS[theme].wall  or THEME_CONFIGS.classic.wall
	local isHedge = shape == "overgrown"

	local outline = BonusShapes.getOutline(shape, W, H, mazeData.wobbleSeed)
	local n = #outline
	if n < 3 then return end

	-- Center point of the shaped floor fan
	local center = outlineWorld(origin, (W + 1) / 2, (H + 1) / 2)
	center = Vector3.new(center.X, floorY - FLOOR_THICK / 2, center.Z)

	-- Floor: triangle fan from center to each outline edge
	for i = 1, n do
		local p1 = outline[i]
		local p2 = outline[(i % n) + 1]
		local w1 = outlineWorld(origin, p1.x, p1.y)
		local w2 = outlineWorld(origin, p2.x, p2.y)
		w1 = Vector3.new(w1.X, floorY - FLOOR_THICK / 2, w1.Z)
		w2 = Vector3.new(w2.X, floorY - FLOOR_THICK / 2, w2.Z)
		floorTriangle(folder, center, w1, w2, floorCfg.material, floorCfg.color)
	end

	-- Perimeter wall: a thin segment along each outline edge
	for i = 1, n do
		local p1 = outline[i]
		local p2 = outline[(i % n) + 1]
		local w1 = outlineWorld(origin, p1.x, p1.y)
		local w2 = outlineWorld(origin, p2.x, p2.y)
		local dx = w2.X - w1.X
		local dz = w2.Z - w1.Z
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 0.05 then continue end

		local mid = Vector3.new((w1.X + w2.X) / 2, floorY + WALL_HEIGHT / 2, (w1.Z + w2.Z) / 2)
		local theta = math.atan2(-dz, dx)

		local wall = Instance.new("Part")
		wall.Name = "BonusWall"
		wall.Anchored = true
		wall.Size = Vector3.new(len + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS * 2.5)
		wall.CFrame = CFrame.new(mid) * CFrame.Angles(0, theta, 0)
		wall.Material = isHedge and Enum.Material.LeafyGrass or wallCfg.material
		wall.Color = isHedge and Color3.fromRGB(40, 100, 35) or wallCfg.color
		wall.TopSurface = Enum.SurfaceType.Smooth
		wall.BottomSurface = Enum.SurfaceType.Smooth
		wall.Parent = folder

		if isHedge then
			local bush = Instance.new("Part")
			bush.Name = "Hedge"
			bush.Shape = Enum.PartType.Ball
			bush.Anchored = true
			bush.CanCollide = false
			bush.Size = Vector3.new(CELL * 0.95, CELL * 0.95, CELL * 0.95)
			bush.CFrame = CFrame.new(mid.X, floorY + WALL_HEIGHT, mid.Z)
			bush.Material = Enum.Material.LeafyGrass
			bush.Color = Color3.fromRGB(45 + (i % 3) * 8, 110 + (i % 4) * 8, 35)
			bush.Parent = folder
		end
	end
end

-- ─── Polar maze geometry helpers ─────────────────────────────────────────────

-- Arc wall: series of thin parts tracing an arc at `radius` from (cx,cz),
-- spanning angles [a1, a2]. Each segment is tangentially oriented so the result
-- looks like a smooth curved wall rather than a polygon.
local function buildArcWall(
	folder: Folder, cx: number, floorY: number, cz: number,
	radius: number, a1: number, a2: number,
	wallH: number, wallMat: Enum.Material, wallColor: Color3
)
	if radius < 0.5 then return end
	local span   = math.abs(a2 - a1)
	local arcLen = span * radius
	local segSpacing = (Constants.POLAR_RING_WIDTH or 11) * (Constants.POLAR_WALL_SEGMENTS or 0.42)
	local nSegs  = math.max(1, math.ceil(arcLen / segSpacing))
	local da     = (a2 - a1) / nSegs

	for i = 0, nSegs - 1 do
		local am     = a1 + (i + 0.5) * da
		local segLen = math.abs(da) * radius + WALL_THICKNESS
		local px = cx + math.cos(am) * radius
		local pz = cz + math.sin(am) * radius

		local tangX =  -math.sin(am)
		local tangZ =   math.cos(am)

		local part = Instance.new("Part")
		part.Name   = "ArcWall"
		part.Size   = Vector3.new(segLen, wallH, WALL_THICKNESS)
		part.CFrame = CFrame.fromMatrix(
			Vector3.new(px, floorY + wallH / 2, pz),
			Vector3.new(tangX, 0, tangZ),
			Vector3.new(0, 1, 0)
		)
		part.Anchored = true
		part.Material = wallMat
		part.Color    = wallColor
		part.TopSurface    = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = folder
	end
end

-- Radial wall: single part from radius r1 to r2 at angle `angle`.
local function buildRadialWall(
	folder: Folder, cx: number, floorY: number, cz: number,
	r1: number, r2: number, angle: number,
	wallH: number, wallMat: Enum.Material, wallColor: Color3
)
	local len = r2 - r1
	if len < 0.5 then return end
	local rm = (r1 + r2) / 2
	local px = cx + math.cos(angle) * rm
	local pz = cz + math.sin(angle) * rm

	local part = Instance.new("Part")
	part.Name   = "RadialWall"
	part.Size   = Vector3.new(len + WALL_THICKNESS, wallH, WALL_THICKNESS)
	part.CFrame = CFrame.fromMatrix(
		Vector3.new(px, floorY + wallH / 2, pz),
		Vector3.new(math.cos(angle), 0, math.sin(angle)),
		Vector3.new(0, 1, 0)
	)
	part.Anchored = true
	part.Material = wallMat
	part.Color    = wallColor
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
end

-- Build a complete polar (circular) maze and return metadata needed for session.
-- Returns { startWorldPos, exitWorldPos, totalRadius }
local function buildPolarBonusMaze(
	worldConfig, bonus, folder: Folder, origin: Vector3,
	seed: number?, endlessRound: number?
): { startWorldPos: Vector3, exitWorldPos: Vector3, totalRadius: number }
	local theme     = worldConfig.theme
	local wallCfg   = THEME_CONFIGS[theme] and THEME_CONFIGS[theme].wall  or THEME_CONFIGS.classic.wall
	local floorCfg  = THEME_CONFIGS[theme] and THEME_CONFIGS[theme].floor or THEME_CONFIGS.classic.floor
	local ceilCfg   = THEME_CONFIGS[theme] and THEME_CONFIGS[theme].ceiling or THEME_CONFIGS.classic.floor

	local round      = endlessRound or 0
	local numRings   = bonus.polarRings or 4
	if bonus.endless then
		numRings = numRings + round
	end
	local maxRings   = bonus.polarMaxRings or Constants.POLAR_MAX_RINGS
	numRings = math.min(numRings, maxRings)

	local numSectors = bonus.polarSectors or 8
	local ringWidth  = bonus.polarRingWidth or Constants.POLAR_RING_WIDTH
	local totalR     = numRings * ringWidth
	local enclosed   = bonus.polarEnclosed == true

	-- Centre the disc in the slot
	local cx = origin.X + totalR + CELL * 2
	local cz = origin.Z + totalR + CELL * 2
	local floorY = origin.Y

	-- Generate polar maze
	local pMaze = PolarMaze.generate(numRings, numSectors, seed)
	local cells  = pMaze.cells
	local sAngle = (2 * math.pi) / numSectors  -- sector angular span

	-- ── Floor disc (cylinder — perfectly round) ───────────────────────────────
	local floorDisc = Instance.new("Part")
	floorDisc.Name      = "PolarFloor"
	floorDisc.Shape     = Enum.PartType.Cylinder
	floorDisc.Size      = Vector3.new(2, totalR * 2 + ringWidth, totalR * 2 + ringWidth)
	floorDisc.CFrame    = CFrame.new(cx, floorY - 1, cz) * CFrame.Angles(0, 0, math.pi / 2)
	floorDisc.Anchored  = true
	floorDisc.Material  = floorCfg.material
	floorDisc.Color     = floorCfg.color
	floorDisc.TopSurface    = Enum.SurfaceType.Smooth
	floorDisc.BottomSurface = Enum.SurfaceType.Smooth
	floorDisc.Parent = folder
	applyIceFloorPhysics(floorDisc, theme)

	-- ── Ceiling disc ──────────────────────────────────────────────────────────
	local ceilDisc = Instance.new("Part")
	ceilDisc.Name    = "PolarCeiling"
	ceilDisc.Shape   = Enum.PartType.Cylinder
	ceilDisc.Size    = Vector3.new(1, totalR * 2 + ringWidth + 4, totalR * 2 + ringWidth + 4)
	ceilDisc.CFrame  = CFrame.new(cx, floorY + WALL_HEIGHT + 0.5, cz) * CFrame.Angles(0, 0, math.pi / 2)
	ceilDisc.Anchored   = true
	ceilDisc.CanCollide = false
	ceilDisc.Transparency = enclosed and 0 or 0.92
	ceilDisc.Material = ceilCfg.material
	ceilDisc.Color    = enclosed and wallCfg.color or ceilCfg.color
	ceilDisc.Parent   = folder

	if enclosed then
		-- Solid roof disc — no sky / outside visible through ceiling
		local roof = Instance.new("Part")
		roof.Name = "PolarRoof"
		roof.Shape = Enum.PartType.Cylinder
		roof.Size = Vector3.new(3, totalR * 2 + ringWidth + 8, totalR * 2 + ringWidth + 8)
		roof.CFrame = CFrame.new(cx, floorY + WALL_HEIGHT + 1.5, cz) * CFrame.Angles(0, 0, math.pi / 2)
		roof.Anchored = true
		roof.CanCollide = false
		roof.Material = wallCfg.material
		roof.Color = wallCfg.color
		roof.Parent = folder
	end

	-- ── Arc walls (ring boundaries) ───────────────────────────────────────────
	local exitSector = pMaze.exitSector

	for r = 1, numRings do
		local innerR = (r - 1) * ringWidth
		for s = 1, numSectors do
			local a1 = (s - 1) * sAngle
			local a2 = s * sAngle
			-- Inner boundary wall (toward ring r-1 / center)
			if not cells[r][s].innerOpen then
				local arcR = (r == 1) and (ringWidth * 0.15) or innerR
				buildArcWall(folder, cx, floorY, cz,
					arcR, a1, a2, WALL_HEIGHT, wallCfg.material, wallCfg.color)
			end
		end
	end

	-- Outer perimeter — leave exit gap
	for s = 1, numSectors do
		if s == exitSector then continue end
		local a1 = (s - 1) * sAngle
		local a2 = s * sAngle
		buildArcWall(folder, cx, floorY, cz,
			totalR, a1, a2, WALL_HEIGHT, wallCfg.material, wallCfg.color)
	end

	-- ── Radial walls (sector boundaries) ─────────────────────────────────────
	for r = 1, numRings do
		local r1 = (r - 1) * ringWidth
		local r2 = r * ringWidth
		for s = 1, numSectors do
			if not cells[r][s].cwOpen then
				local wallAngle = s * sAngle
				buildRadialWall(folder, cx, floorY, cz,
					r1, r2, wallAngle, WALL_HEIGHT, wallCfg.material, wallCfg.color)
			end
		end
	end

	-- ── Centre hub ─────────────────────────────────────────────────────────────
	if enclosed then
		-- Solid closed core: no center light, blocks view into the void
		local coreR = ringWidth * 0.52
		local core = Instance.new("Part")
		core.Name = "CentreCore"
		core.Shape = Enum.PartType.Cylinder
		core.Size = Vector3.new(WALL_HEIGHT + 2, coreR * 2, coreR * 2)
		core.CFrame = CFrame.new(cx, floorY + WALL_HEIGHT / 2, cz) * CFrame.Angles(0, 0, math.pi / 2)
		core.Anchored = true
		core.Material = wallCfg.material
		core.Color = wallCfg.color
		core.Parent = folder

		local coreCap = Instance.new("Part")
		coreCap.Name = "CentreCoreCap"
		coreCap.Shape = Enum.PartType.Cylinder
		coreCap.Size = Vector3.new(2, coreR * 2 + 1, coreR * 2 + 1)
		coreCap.CFrame = CFrame.new(cx, floorY - 0.5, cz) * CFrame.Angles(0, 0, math.pi / 2)
		coreCap.Anchored = true
		coreCap.Material = floorCfg.material
		coreCap.Color = floorCfg.color
		coreCap.Parent = folder
	else
		local pillar = Instance.new("Part")
		pillar.Name   = "CentrePillar"
		pillar.Shape  = Enum.PartType.Cylinder
		pillar.Size   = Vector3.new(WALL_HEIGHT, ringWidth * 0.35, ringWidth * 0.35)
		pillar.CFrame = CFrame.new(cx, floorY + WALL_HEIGHT / 2, cz) * CFrame.Angles(0, 0, math.pi / 2)
		pillar.Anchored = true
		pillar.Material = wallCfg.material
		pillar.Color    = wallCfg.color
		pillar.Parent   = folder
	end

	if enclosed then
		-- Outer shell — hides hub / sky when looking through gaps
		local shellR = totalR + ringWidth * 0.75
		for i = 0, 31 do
			local a1 = (i / 32) * math.pi * 2
			local a2 = ((i + 1) / 32) * math.pi * 2
			buildArcWall(folder, cx, floorY, cz,
				shellR, a1, a2, WALL_HEIGHT + 6, wallCfg.material, wallCfg.color)
		end
	end

	-- ── Coins ─────────────────────────────────────────────────────────────────
	for _, c in ipairs(pMaze.coinCells) do
		local r, s = c.r, c.s
		local am = (s - 0.5) * sAngle
		local rm = (r - 0.5) * ringWidth
		local px = cx + math.cos(am) * rm
		local pz = cz + math.sin(am) * rm

		local coin = Instance.new("Part")
		coin.Name  = "Coin_p" .. r .. "_" .. s
		coin.Size  = Vector3.new(2, 0.3, 2)
		coin.Shape = Enum.PartType.Cylinder
		coin.CFrame = CFrame.new(px, floorY + 2.5, pz)
		coin.Anchored  = true
		coin.CanCollide = false
		coin.Material  = Enum.Material.Neon
		coin.Color     = Color3.fromRGB(255, 200, 30)
		coin.Parent    = folder

		local tag = Instance.new("StringValue")
		tag.Name  = "CoinTag"
		tag.Value = "p" .. r .. "_" .. s
		tag.Parent = coin

		task.spawn(function()
			local angle = 0
			while coin.Parent do
				angle += 0.05
				coin.CFrame = CFrame.new(px, floorY + 2.5 + math.sin(angle) * 0.3, pz)
					* CFrame.Angles(angle, 0, math.pi / 2)
				task.wait(0.03)
			end
		end)
	end

	-- ── Ambient lights (skip center area on enclosed mazes) ───────────────────
	local lightBright, lightRange = getAmbientLightParams(theme)
	for r = 1, numRings, 2 do
		for s = 1, numSectors, 2 do
			if enclosed and r <= 2 then
				continue
			end
			local am = (s - 0.5) * sAngle
			local rm = (r - 0.5) * ringWidth
			local lp = Instance.new("Part")
			lp.Size        = Vector3.new(0.5, 0.5, 0.5)
			lp.CFrame      = CFrame.new(cx + math.cos(am)*rm, floorY + WALL_HEIGHT - 1, cz + math.sin(am)*rm)
			lp.Anchored    = true
			lp.CanCollide  = false
			lp.Transparency = 1
			lp.Parent      = folder
			addPointLight(lp, worldConfig.ambientColor, lightBright, lightRange)
		end
	end

	-- ── Exit portal ───────────────────────────────────────────────────────────
	local exitAng = (exitSector - 0.5) * sAngle
	local exitX   = cx + math.cos(exitAng) * (totalR - ringWidth * 0.5)
	local exitZ   = cz + math.sin(exitAng) * (totalR - ringWidth * 0.5)

	local exitPart = Instance.new("Part")
	exitPart.Name      = "ExitPortal"
	exitPart.Size      = Vector3.new(ringWidth - 2, 0.5, ringWidth - 2)
	exitPart.CFrame    = CFrame.new(exitX, floorY + 0.25, exitZ)
	exitPart.Anchored  = true
	exitPart.CanCollide = false
	exitPart.Material  = Enum.Material.Neon
	exitPart.Color     = Color3.fromRGB(0, 255, 150)
	exitPart.Parent    = folder
	addPointLight(exitPart, Color3.fromRGB(0, 255, 150), 3, 24)

	task.spawn(function()
		while exitPart.Parent do
			local tw = TweenService:Create(exitPart,
				TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Color = Color3.fromRGB(0, 200, 255) })
			tw:Play()
			task.wait(2)
			tw:Cancel()
		end
	end)

	local startAng = 0.5 * sAngle
	local startRm  = enclosed and (ringWidth * 0.65) or 0
	local startX   = cx + math.cos(startAng) * startRm
	local startZ   = cz + math.sin(startAng) * startRm

	return {
		startWorldPos = Vector3.new(startX, floorY + 4, startZ),
		exitWorldPos  = Vector3.new(exitX, floorY + 4, exitZ),
		totalRadius   = totalR,
		centerX       = cx,
		centerZ       = cz,
	}
end

local function bonusToWorldConfig(bonus)
	return {
		name = bonus.name,
		theme = bonus.theme,
		mechanics = bonus.mechanics or {},
		ambientColor = bonus.ambientColor,
		fogEnd = bonus.fogEnd,
		bg = bonus.bg,
		lavaDensity = bonus.lavaDensity,
	}
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

	-- Lava patches (damage over time — not instant kill)
	if table.find(worldConfig.mechanics, "lava") then
		local lavaChance = worldConfig.lavaDensity or 0.08
		local W, H = mazeData.width, mazeData.height
		for y = 2, H - 1 do
			for x = 2, W - 1 do
				if mazeData.cells[y][x].blocked then continue end
				if math.random() < lavaChance then
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

	-- Polar (circular / endless) mazes store absolute start position
	if session.startWorldPos then
		hrp.CFrame = CFrame.new(session.startWorldPos)
		return
	end

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
	local useCheckpoints = Constants.worldUsesCheckpoints(worldConfig)
	local mazeData = MazeGenerator.generate(
		worldConfig.mazeSize.width,
		worldConfig.mazeSize.height,
		seed,
		{ useCheckpoints = useCheckpoints }
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
		useCheckpoints = useCheckpoints,
	})

	task.delay(0.4, function()
		local s = sessions[player.UserId]
		if s then
			spawnPlayerAtMaze(player, s)
			Logger.info(TAG, "Player teleported to maze start", player.Name)
		end
	end)
end

function MazeService.startBonusMaze(player: Player, bonusId: string, endlessRound: number?)
	local bonus = Constants.getBonusLevel(bonusId)
	if not bonus then
		Logger.warn(TAG, "Unknown bonus level", player.Name, bonusId)
		return
	end

	local worldConfig = bonusToWorldConfig(bonus)
	local existing = sessions[player.UserId]
	local slot   = existing and existing.slot or acquireSlot()
	local origin = getOrigin(slot)
	local round  = endlessRound or 0

	Logger.info(TAG, "Starting bonus maze", player.Name, bonus.name,
		"slot=" .. slot, "round=" .. round)

	clearMaze(player)

	local folder = Instance.new("Folder")
	folder.Name   = "Maze_" .. player.UserId
	folder.Parent = mazeFolder

	local seed = os.time() + player.UserId + math.random(1, 99999) + round * 997

	-- ── Polar path (circle / endless): proper curved walls ───────────────────
	if bonus.usePolar then
		local polarData = buildPolarBonusMaze(worldConfig, bonus, folder, origin, seed, round)

		local bgSize = polarData.totalRadius * 2 + CELL * 4
		if not bonus.polarEnclosed then
			local bgOk, bgErr = pcall(function()
				local fakeW = math.ceil(bgSize / CELL)
				buildBackground(worldConfig, origin, folder, fakeW, fakeW)
			end)
			if not bgOk then Logger.warn(TAG, "BG build failed", tostring(bgErr)) end
		end

		local fxOk, fxErr = pcall(buildEffects, worldConfig, origin, folder,
			math.ceil(bgSize / CELL), math.ceil(bgSize / CELL))
		if not fxOk then Logger.warn(TAG, "FX build failed", tostring(fxErr)) end

		sessions[player.UserId] = {
			isBonus       = true,
			isPolar       = true,
			endless       = bonus.endless == true,
			bonusId       = bonusId,
			endlessRound  = round,
			worldId       = nil,
			slot          = slot,
			origin        = origin,
			mazeData      = nil,
			startWorldPos = polarData.startWorldPos,
			startTime     = os.time(),
			activeCheckpoint = nil,
			coinsCollected   = 0,
			usedCheckpoint   = false,
			hintUsed         = false,
		}

		Remotes:WaitForChild(RemoteDefs.MazeLoaded):FireClient(player, {
			bonusId   = bonusId,
			bonusName = bonus.name,
			worldName = bonus.name,
			theme     = bonus.theme,
			mechanics = bonus.mechanics or {},
			fogEnd    = bonus.fogEnd,
			ambient   = bonus.ambientColor,
			bg        = bonus.bg,
			useCheckpoints = false,
			isBonus   = true,
			isPolar   = true,
			endlessRound = round,
		})

		task.delay(0.4, function()
			local s = sessions[player.UserId]
			if s then
				spawnPlayerAtMaze(player, s)
				Logger.info(TAG, "Player teleported to polar maze start", player.Name)
			end
		end)
		return
	end

	-- ── Grid path (pentagon / star / overgrown): shaped grid maze ────────────
	local useCheckpoints = bonus.useCheckpoints == true
	local mazeData = MazeGenerator.generate(
		bonus.mazeSize.width,
		bonus.mazeSize.height,
		seed,
		{ useCheckpoints = useCheckpoints, shape = bonus.shape }
	)

	buildMaze(worldConfig, mazeData, folder, origin, true)
	buildBonusShell(worldConfig, mazeData, folder, origin)
	placeSpecials(worldConfig, mazeData, folder, origin)

	local bgOk, bgErr = pcall(buildBackground, worldConfig, origin, folder, mazeData.width, mazeData.height)
	if not bgOk then Logger.warn(TAG, "Background build failed", tostring(bgErr)) end
	local fxOk, fxErr = pcall(buildEffects, worldConfig, origin, folder, mazeData.width, mazeData.height)
	if not fxOk then Logger.warn(TAG, "Effects build failed", tostring(fxErr)) end

	sessions[player.UserId] = {
		isBonus          = true,
		isPolar          = false,
		endless          = false,
		bonusId          = bonusId,
		endlessRound     = 0,
		worldId          = nil,
		slot             = slot,
		origin           = origin,
		mazeData         = mazeData,
		startWorldPos    = nil,
		startTime        = os.time(),
		activeCheckpoint = nil,
		coinsCollected   = 0,
		usedCheckpoint   = false,
		hintUsed         = false,
	}

	Remotes:WaitForChild(RemoteDefs.MazeLoaded):FireClient(player, {
		bonusId   = bonusId,
		bonusName = bonus.name,
		worldName = bonus.name,
		theme     = bonus.theme,
		mechanics = bonus.mechanics or {},
		width     = mazeData.width,
		height    = mazeData.height,
		fogEnd    = bonus.fogEnd,
		ambient   = bonus.ambientColor,
		bg        = bonus.bg,
		useCheckpoints = useCheckpoints,
		isBonus   = true,
	})

	task.delay(0.4, function()
		local s = sessions[player.UserId]
		if s then
			spawnPlayerAtMaze(player, s)
			Logger.info(TAG, "Player teleported to bonus maze start", player.Name)
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
		local data    = PlayerDataService.get(player)
		if not data then return end

		if session.isBonus then
			local bonus = Constants.getBonusLevel(session.bonusId)
			Logger.info(TAG, "Bonus maze completed", player.Name, "time=" .. elapsed .. "s", "bonus=" .. session.bonusId)

			data.BonusCompletions[session.bonusId] = (data.BonusCompletions[session.bonusId] or 0) + 1
			data.TotalMazesCompleted = (data.TotalMazesCompleted or 0) + 1

			local rewardCoins = bonus and bonus.rewardCoins or 40
			local rewardXP = bonus and bonus.rewardXP or 80
			PlayerDataService.addCoins(player, rewardCoins)
			PlayerDataService.addXP(player, rewardXP)

			data.QuestProgress["complete_maze"]   = (data.QuestProgress["complete_maze"]   or 0) + 1
			data.QuestProgress["complete_3_maze"] = (data.QuestProgress["complete_3_maze"] or 0) + 1
			data.QuestProgress["weekly_mazes"]    = (data.QuestProgress["weekly_mazes"]    or 0) + 1

			-- Endless: scale reward and restart immediately
			if session.endless then
				local nextRound  = (session.endlessRound or 0) + 1
				local bonusExtra = math.floor(rewardCoins * nextRound * 0.12)
				PlayerDataService.addCoins(player, bonusExtra)

				Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
					title = "♾️ Раунд " .. nextRound .. "!",
					text  = "+" .. (rewardCoins + bonusExtra) .. " монет — следующий круг...",
					icon  = "♾️",
					color = "blue",
				})
				Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)

				task.delay(3, function()
					if player.Parent then
						MazeService.startBonusMaze(player, session.bonusId, nextRound)
					end
				end)
				return
			end

			Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
				title = "Bonus Complete!",
				text  = (bonus and bonus.icon or "⭐") .. " " .. (bonus and bonus.name or "Bonus")
					.. " — +" .. rewardCoins .. " coins",
				icon  = "🏆",
				color = "gold",
			})

			Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)

			task.delay(2.5, function()
				if player.Parent then
					MazeService.endSession(player)
					HubService.teleportToHub(player)
				end
			end)
			return
		end

		Logger.info(TAG, "Maze completed", player.Name, "time=" .. elapsed .. "s", "world=" .. session.worldId)
		local worldId = session.worldId

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
		if not session.usedCheckpoint and Constants.worldUsesCheckpoints(Constants.WORLDS[worldId]) then
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

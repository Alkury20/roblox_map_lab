-- MazeGenerator.luau
-- Procedural maze generation using Recursive Backtracker (DFS)
-- Guarantees a valid path from start to exit.

local MazeGenerator = {}

type Cell = {
	x: number,
	y: number,
	walls: { north: boolean, south: boolean, east: boolean, west: boolean },
	visited: boolean,
	isSecretRoom: boolean,
	hasCheckpoint: boolean,
	hasCoin: boolean,
}

type MazeData = {
	width: number,
	height: number,
	cells: { { Cell } },
	startPos: { x: number, y: number },
	exitPos: { x: number, y: number },
	secretRooms: { { x: number, y: number } },
	checkpoints: { { x: number, y: number } },
	coinPositions: { { x: number, y: number } },
}

local DIRECTIONS = {
	{ dx = 0,  dy = -1, wall = "north", opposite = "south" },
	{ dx = 0,  dy = 1,  wall = "south", opposite = "north" },
	{ dx = 1,  dy = 0,  wall = "east",  opposite = "west"  },
	{ dx = -1, dy = 0,  wall = "west",  opposite = "east"  },
}

local function createCell(x: number, y: number): Cell
	return {
		x = x,
		y = y,
		walls = { north = true, south = true, east = true, west = true },
		visited = false,
		isSecretRoom = false,
		hasCheckpoint = false,
		hasCoin = false,
	}
end

local function shuffle(t: { any }, rng: Random): { any }
	local n = #t
	for i = n, 2, -1 do
		local j = rng:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- Recursive Backtracker DFS
local function carve(cells: { { Cell } }, x: number, y: number, width: number, height: number, rng: Random)
	cells[y][x].visited = true

	local dirs = shuffle({ 1, 2, 3, 4 }, rng)
	for _, di in ipairs(dirs) do
		local d = DIRECTIONS[di]
		local nx, ny = x + d.dx, y + d.dy
		if nx >= 1 and nx <= width and ny >= 1 and ny <= height and not cells[ny][nx].visited then
			cells[y][x].walls[d.wall] = false
			cells[ny][nx].walls[d.opposite] = false
			carve(cells, nx, ny, width, height, rng)
		end
	end
end

-- Find dead-ends (cells with 3 walls) for placing secrets, coins, checkpoints
local function findDeadEnds(cells: { { Cell } }, width: number, height: number): { { x: number, y: number } }
	local deadEnds = {}
	for y = 1, height do
		for x = 1, width do
			local cell = cells[y][x]
			local wallCount = 0
			for _, v in pairs(cell.walls) do
				if v then wallCount += 1 end
			end
			if wallCount == 3 then
				table.insert(deadEnds, { x = x, y = y })
			end
		end
	end
	return deadEnds
end

function MazeGenerator.generate(width: number, height: number, seed: number?): MazeData
	-- Ensure odd dimensions for proper maze structure
	if width % 2 == 0 then width += 1 end
	if height % 2 == 0 then height += 1 end

	local rng = Random.new(seed or os.clock())

	-- Initialize grid
	local cells: { { Cell } } = {}
	for y = 1, height do
		cells[y] = {}
		for x = 1, width do
			cells[y][x] = createCell(x, y)
		end
	end

	-- Generate maze from top-left
	carve(cells, 1, 1, width, height, rng)

	-- Start: top-left, Exit: bottom-right
	local startPos = { x = 1, y = 1 }
	local exitPos  = { x = width, y = height }

	-- Open the exit wall
	cells[height][width].walls.south = false

	-- Find dead ends for placement
	local deadEnds = findDeadEnds(cells, width, height)
	shuffle(deadEnds, rng)

	-- Remove start and exit from dead ends
	local function removePos(list, px, py)
		for i, p in ipairs(list) do
			if p.x == px and p.y == py then
				table.remove(list, i)
				return
			end
		end
	end
	removePos(deadEnds, startPos.x, startPos.y)
	removePos(deadEnds, exitPos.x, exitPos.y)

	-- Place secret rooms (use dead-ends far from start)
	local secretRooms = {}
	local numSecrets = math.max(1, math.floor(#deadEnds * 0.10))
	for i = 1, math.min(numSecrets, #deadEnds) do
		local de = deadEnds[i]
		cells[de.y][de.x].isSecretRoom = true
		table.insert(secretRooms, { x = de.x, y = de.y })
	end

	-- Place checkpoints (spread evenly, every ~10 cells along path)
	local checkpoints = {}
	local checkpointInterval = math.floor((width * height) / 8)
	local cpCount = 0
	for y = 1, height do
		for x = 1, width do
			cpCount += 1
			if cpCount % checkpointInterval == 0 then
				if not cells[y][x].isSecretRoom
					and not (x == startPos.x and y == startPos.y)
					and not (x == exitPos.x and y == exitPos.y) then
					cells[y][x].hasCheckpoint = true
					table.insert(checkpoints, { x = x, y = y })
				end
			end
		end
	end

	-- Scatter coins (~25% of open cells)
	local coinPositions = {}
	for y = 1, height do
		for x = 1, width do
			local cell = cells[y][x]
			if not cell.isSecretRoom and not cell.hasCheckpoint
				and not (x == startPos.x and y == startPos.y)
				and not (x == exitPos.x and y == exitPos.y)
				and rng:NextNumber() < 0.22 then
				cell.hasCoin = true
				table.insert(coinPositions, { x = x, y = y })
			end
		end
	end

	return {
		width        = width,
		height       = height,
		cells        = cells,
		startPos     = startPos,
		exitPos      = exitPos,
		secretRooms  = secretRooms,
		checkpoints  = checkpoints,
		coinPositions = coinPositions,
	}
end

-- BFS path validation (used for hint system)
function MazeGenerator.findPath(mazeData: MazeData, fromX: number, fromY: number): { { x: number, y: number } }?
	local width, height = mazeData.width, mazeData.height
	local cells = mazeData.cells
	local ex, ey = mazeData.exitPos.x, mazeData.exitPos.y

	local visited = {}
	local prev = {}
	local queue = { { x = fromX, y = fromY } }
	visited[fromY * (width + 1) + fromX] = true

	local function key(x, y) return y * (width + 1) + x end

	while #queue > 0 do
		local cur = table.remove(queue, 1)
		if cur.x == ex and cur.y == ey then
			-- Reconstruct path
			local path = {}
			local c = cur
			while c do
				table.insert(path, 1, { x = c.x, y = c.y })
				c = prev[key(c.x, c.y)]
			end
			return path
		end

		local cell = cells[cur.y][cur.x]
		for _, d in ipairs(DIRECTIONS) do
			if not cell.walls[d.wall] then
				local nx, ny = cur.x + d.dx, cur.y + d.dy
				local k = key(nx, ny)
				if not visited[k] then
					visited[k] = true
					prev[k] = cur
					table.insert(queue, { x = nx, y = ny })
				end
			end
		end
	end
	return nil
end

return MazeGenerator

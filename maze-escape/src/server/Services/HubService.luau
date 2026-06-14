-- HubService.luau
-- Central hub: world pads, unlock logic, coin/Robux purchases.

local Players              = game:GetService("Players")
local MarketplaceService   = game:GetService("MarketplaceService")
local RunService           = game:GetService("RunService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Workspace            = game:GetService("Workspace")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)
local Logger     = require(ReplicatedStorage.Shared.Logger)

local TAG = "HubService"
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local HubService = {}

local PlayerDataService
local MazeService

local hubFolder: Folder
local padDebounce: { [number]: number } = {}
local pendingUnlockWorld: { [number]: number } = {} -- userId -> worldId awaiting Robux purchase
local wiredPads: { [BasePart]: boolean } = {}
local wiredBonusPads: { [BasePart]: boolean } = {}

-- ─── Unlock logic ───────────────────────────────────────────────────────────────
function HubService.isWorldUnlocked(data, worldId: number): boolean
	if worldId == 1 then return true end
	if not data then return false end

	if data.UnlockedWorlds and data.UnlockedWorlds[worldId] then return true end

	local world = Constants.WORLDS[worldId]
	if not world then return false end

	-- Level requirement
	if (data.Level or 1) >= world.unlockLevel then return true end

	-- Sequential: beat the previous world
	if worldId > 1 and data.CompletedWorlds and data.CompletedWorlds[worldId - 1] then
		return true
	end

	return false
end

function HubService.unlockWorld(player: Player, worldId: number, source: string)
	local data = PlayerDataService.get(player)
	if not data then return false end

	if not data.UnlockedWorlds then data.UnlockedWorlds = {} end
	data.UnlockedWorlds[worldId] = true

	Logger.info(TAG, "World unlocked", player.Name, "world=" .. worldId, "via=" .. source)

	Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
	Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
		title = "World Unlocked!",
		text  = Constants.WORLDS[worldId].name .. " is now available.",
		icon  = "🔓",
		color = "gold",
	})

	return true
end

function HubService.handleProductPurchase(player: Player, productId: number): boolean
	if productId == Constants.PRODUCT_IDS.UnlockWorld
		or productId == Constants.PRODUCT_IDS.SkipLevel then

		local worldId = pendingUnlockWorld[player.UserId]
		if not worldId then
			-- Fallback: first locked world
			local data = PlayerDataService.get(player)
			if data then
				for wid = 2, Constants.WORLD_COUNT do
					if not HubService.isWorldUnlocked(data, wid) then
						worldId = wid
						break
					end
				end
			end
		end

		if worldId then
			HubService.unlockWorld(player, worldId, "robux")
			pendingUnlockWorld[player.UserId] = nil
			return true
		end
		return false
	end

	return false
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function makePart(name, size, cframe, color, material, parent)
	local p = Instance.new("Part")
	p.Name      = name
	p.Size      = size
	p.CFrame    = cframe
	p.Anchored  = true
	p.Color     = color
	p.Material   = material or Enum.Material.SmoothPlastic
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent    = parent
	return p
end

local function billboard(adornee: BasePart, titleText: string, subText: string, accent: Color3)
	local bb = Instance.new("BillboardGui")
	bb.Name = "PadInfo"
	bb.Adornee = adornee
	bb.Size = UDim2.new(0, 200, 0, 70)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Parent = adornee

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextColor3 = accent
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = bb

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Position = UDim2.new(0, 0, 0.6, 0)
	sub.BackgroundTransparency = 1
	sub.Text = subText
	sub.TextColor3 = Color3.fromRGB(230, 230, 240)
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.Parent = bb
end

local function getBonusIdFromPad(pad: Instance): string?
	local idVal = pad:FindFirstChild("BonusId")
	if idVal and idVal:IsA("StringValue") then
		return idVal.Value
	end
	local n = pad.Name:match("^BonusPad_(.+)$")
	if n and Constants.BONUS_LEVELS[n] then
		return n
	end
	return nil
end

local BONUS_PAD_COLORS = {
	circle = Color3.fromRGB(200, 175, 120),
	endless = Color3.fromRGB(70, 130, 220),
	star = Color3.fromRGB(140, 90, 200),
	pentagon = Color3.fromRGB(0, 170, 210),
	overgrown = Color3.fromRGB(45, 130, 50),
}

local function ensureBonusPadBillboard(pad: BasePart, bonusId: string)
	if pad:FindFirstChild("PadInfo") then
		return
	end
	local bonus = Constants.getBonusLevel(bonusId)
	if not bonus then return end
	billboard(
		pad,
		bonus.icon .. " " .. bonus.name,
		"🪙 " .. bonus.runCost .. " / run · unlock " .. bonus.unlockCost,
		Color3.fromRGB(255, 220, 255)
	)
end

local function wireBonusPad(pad: BasePart, bonusId: string)
	if wiredBonusPads[pad] then return end
	wiredBonusPads[pad] = true

	ensureBonusPadBillboard(pad, bonusId)

	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then return end

		local now = os.clock()
		if padDebounce[player.UserId] and now - padDebounce[player.UserId] < 1.5 then
			return
		end
		padDebounce[player.UserId] = now

		local BonusService = require(script.Parent.BonusService)
		BonusService.requestBonus(player, bonusId)
	end)
end

local function wireBonusPads(parent: Instance)
	local wired = 0
	for _, desc in parent:GetDescendants() do
		if desc:IsA("BasePart") then
			local bonusId = getBonusIdFromPad(desc)
			if bonusId and Constants.getBonusLevel(bonusId) then
				wireBonusPad(desc, bonusId)
				wired += 1
			end
		end
	end
	return wired
end

function HubService.ensureBonusPads()
	hubFolder = Workspace:FindFirstChild("Hub")
	if not hubFolder then
		hubFolder = Instance.new("Folder")
		hubFolder.Name = "Hub"
		hubFolder.Parent = Workspace
	end

	local bonusRoot = hubFolder:FindFirstChild("BonusPads")
	if not bonusRoot then
		bonusRoot = Instance.new("Folder")
		bonusRoot.Name = "BonusPads"
		bonusRoot.Parent = hubFolder
	end

	local center = Constants.HUB_CENTER

	if #bonusRoot:GetChildren() == 0 then
		local signPart = makePart("BonusSign",
			Vector3.new(50, 10, 2),
			CFrame.new(center + Vector3.new(0, 14, Constants.HUB_BONUS_PAD_Z - 12)),
			Color3.fromRGB(35, 25, 55),
			Enum.Material.SmoothPlastic,
			bonusRoot)
		local signGui = Instance.new("SurfaceGui")
		signGui.Face = Enum.NormalId.Back
		signGui.CanvasSize = Vector2.new(600, 120)
		signGui.Parent = signPart
		local signText = Instance.new("TextLabel")
		signText.Size = UDim2.new(1, 0, 1, 0)
		signText.BackgroundTransparency = 1
		signText.Text = "⭐ БОНУСНЫЕ УРОВНИ"
		signText.TextColor3 = Color3.fromRGB(220, 180, 255)
		signText.Font = Enum.Font.GothamBold
		signText.TextScaled = true
		signText.Parent = signGui

		local bonusIds = Constants.BONUS_LEVEL_ORDER
		local spacing = Constants.HUB_BONUS_PAD_SPACING
		local startX = -((#bonusIds - 1) * spacing) / 2
		local padZ = center.Z + Constants.HUB_BONUS_PAD_Z

		for i, bonusId in ipairs(bonusIds) do
			local bonus = Constants.getBonusLevel(bonusId)
			if bonus then
				local px = center.X + startX + (i - 1) * spacing
				local color = BONUS_PAD_COLORS[bonusId] or Color3.fromRGB(140, 80, 200)

				local pad = makePart("BonusPad_" .. bonusId,
					Vector3.new(14, 1.5, 14),
					CFrame.new(px, center.Y + 2.75, padZ),
					color,
					Enum.Material.Neon,
					bonusRoot)

				local idVal = Instance.new("StringValue")
				idVal.Name = "BonusId"
				idVal.Value = bonusId
				idVal.Parent = pad

				local beam = makePart("BonusBeam_" .. bonusId,
					Vector3.new(4, 28, 4),
					CFrame.new(px, center.Y + 16, padZ),
					color,
					Enum.Material.Neon,
					bonusRoot)
				beam.Transparency = 0.55
				beam.CanCollide = false
			end
		end

		Logger.info(TAG, "Bonus pads built", "count=" .. #bonusIds)
	end

	local wired = wireBonusPads(bonusRoot)
	Logger.info(TAG, "Bonus pads wired", "pads=" .. wired)
end

local function getWorldIdFromPad(pad: Instance): number?
	local idVal = pad:FindFirstChild("WorldId")
	if idVal and idVal:IsA("IntValue") then
		return idVal.Value
	end
	local n = pad.Name:match("^WorldPad_(%d+)$")
	if n then return tonumber(n) end
	return nil
end

local function ensurePadBillboard(pad: BasePart, worldId: number)
	if pad:FindFirstChild("PadInfo") then
		return
	end
	local world = Constants.WORLDS[worldId]
	if not world then
		return
	end
	billboard(
		pad,
		world.icon .. " " .. world.name,
		"Unlock: Lv " .. world.unlockLevel,
		Color3.fromRGB(255, 255, 255)
	)
end

local function wireWorldPad(pad: BasePart, worldId: number)
	if wiredPads[pad] then return end
	wiredPads[pad] = true

	ensurePadBillboard(pad, worldId)

	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then return end

		local now = os.clock()
		if padDebounce[player.UserId] and now - padDebounce[player.UserId] < 1.5 then
			return
		end
		padDebounce[player.UserId] = now

		HubService.requestWorld(player, worldId)
	end)
end

local function wireHubPads(parent: Instance)
	local wired = 0
	for _, desc in parent:GetDescendants() do
		if desc:IsA("BasePart") then
			local worldId = getWorldIdFromPad(desc)
			if worldId and Constants.WORLDS[worldId] then
				wireWorldPad(desc, worldId)
				wired += 1
			end
		end
	end
	return wired
end

function HubService.getSpawnCFrame(): CFrame
	if hubFolder then
		local spawn = hubFolder:FindFirstChild("HubSpawn", true)
		if spawn then
			if spawn:IsA("BasePart") then
				return spawn.CFrame + Vector3.new(0, 4, 0)
			elseif spawn:IsA("SpawnLocation") then
				return spawn.CFrame + Vector3.new(0, 4, 0)
			end
		end
	end
	return CFrame.new(Constants.HUB_CENTER + Constants.HUB_SPAWN_OFFSET)
end

local function useCustomHub(): boolean
	hubFolder = Workspace:FindFirstChild("Hub")
	if not hubFolder then
		Logger.warn(TAG, "USE_CUSTOM_HUB is on but Workspace.Hub is missing — building default hub")
		return false
	end

	local wired = wireHubPads(hubFolder)
	Logger.info(TAG, "Custom hub loaded from Workspace", "pads=" .. wired)
	if wired == 0 then
		Logger.warn(TAG, "No world pads found — add IntValue WorldId (1-7) to touch parts")
	end
	wireBonusPads(hubFolder)
	return true
end

local function hubHasLayout(): boolean
	if not hubFolder then
		hubFolder = Workspace:FindFirstChild("Hub")
	end
	if not hubFolder then
		return false
	end
	local generated = hubFolder:FindFirstChild("Generated")
	if not generated then
		return false
	end
	return #generated:GetChildren() > 0
end

local function loadBakedHub()
	hubFolder = Workspace:FindFirstChild("Hub")
	if not hubFolder then
		hubFolder = Instance.new("Folder")
		hubFolder.Name = "Hub"
		hubFolder.Parent = Workspace
	end

	if not hubFolder:FindFirstChild("Decor") then
		local decor = Instance.new("Folder")
		decor.Name = "Decor"
		decor.Parent = hubFolder
	end

	local wired = wireHubPads(hubFolder)
	Logger.info(TAG, "Hub loaded from assets (edit mode)", "pads=" .. wired)
	if wired == 0 then
		Logger.warn(TAG, "No world pads in Hub/Generated — run: python tools/bake_hub.py")
	end
end

local function buildHub()
	hubFolder = Workspace:FindFirstChild("Hub")
	if not hubFolder then
		hubFolder = Instance.new("Folder")
		hubFolder.Name = "Hub"
		hubFolder.Parent = Workspace
	end

	-- Only rebuild the functional layout; your decoration in Hub/Decor is kept
	local oldGenerated = hubFolder:FindFirstChild("Generated")
	if oldGenerated then
		oldGenerated:Destroy()
	end

	local generated = Instance.new("Folder")
	generated.Name = "Generated"
	generated.Parent = hubFolder

	if not hubFolder:FindFirstChild("Decor") then
		local decor = Instance.new("Folder")
		decor.Name = "Decor"
		decor.Parent = hubFolder
	end

	local center = Constants.HUB_CENTER
	local hubSize = Constants.HUB_SIZE
	local root = generated

	makePart("HubPlatform",
		Vector3.new(hubSize, 4, hubSize),
		CFrame.new(center),
		Color3.fromRGB(45, 48, 70),
		Enum.Material.SmoothPlastic,
		root)

	makePart("HubBorder",
		Vector3.new(hubSize + 8, 6, hubSize + 8),
		CFrame.new(center - Vector3.new(0, 1, 0)),
		Color3.fromRGB(80, 90, 140),
		Enum.Material.Neon,
		root)

	local spawnPart = Instance.new("SpawnLocation")
	spawnPart.Name = "HubSpawn"
	spawnPart.Size = Vector3.new(14, 1, 14)
	spawnPart.CFrame = CFrame.new(center + Constants.HUB_SPAWN_OFFSET - Vector3.new(0, 4, 0))
	spawnPart.Anchored = true
	spawnPart.Neutral = true
	spawnPart.Duration = 0
	spawnPart.Color = Color3.fromRGB(80, 160, 255)
	spawnPart.Material = Enum.Material.Neon
	spawnPart.TopSurface = Enum.SurfaceType.Smooth
	spawnPart.Parent = root

	local signPart = makePart("HubSign",
		Vector3.new(60, 14, 2),
		CFrame.new(center + Vector3.new(0, 18, hubSize/2 - 6)),
		Color3.fromRGB(25, 28, 45),
		Enum.Material.SmoothPlastic,
		root)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Back
	signGui.CanvasSize = Vector2.new(800, 200)
	signGui.Parent = signPart
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.new(1, 0, 1, 0)
	signText.BackgroundTransparency = 1
	signText.Text = "🏰 MAZE ESCAPE — Choose a World"
	signText.TextColor3 = Color3.fromRGB(255, 220, 120)
	signText.Font = Enum.Font.GothamBold
	signText.TextScaled = true
	signText.Parent = signGui

	local hubLight = makePart("HubLight", Vector3.new(2,2,2),
		CFrame.new(center + Vector3.new(0, 30, 0)),
		Color3.fromRGB(255,255,255), Enum.Material.Neon, root)
	hubLight.Transparency = 1
	local pl = Instance.new("PointLight")
	pl.Brightness = 2
	pl.Range = hubSize
	pl.Color = Color3.fromRGB(180, 200, 255)
	pl.Parent = hubLight

	-- Perimeter walls
	local wallH = 32
	local wallT = 5
	local half = hubSize / 2
	local wallY = center.Y + wallH / 2 + 1
	local wallColor = Color3.fromRGB(32, 35, 52)
	local trimColor = Color3.fromRGB(70, 85, 130)

	local function hubWall(name, size, pos)
		local w = makePart(name, size, pos, wallColor, Enum.Material.Concrete, root)
		-- Neon trim along the top edge
		local trim = makePart(name .. "_Trim",
			Vector3.new(size.X, 1.2, size.Z),
			pos + Vector3.new(0, wallH / 2 - 0.4, 0),
			trimColor, Enum.Material.Neon, root)
		trim.CanCollide = false
		return w
	end

	-- North / South / East / West
	hubWall("HubWall_N",
		Vector3.new(hubSize + wallT * 2, wallH, wallT),
		CFrame.new(center.X, wallY, center.Z - half - wallT / 2))
	hubWall("HubWall_S",
		Vector3.new(hubSize + wallT * 2, wallH, wallT),
		CFrame.new(center.X, wallY, center.Z + half + wallT / 2))
	hubWall("HubWall_E",
		Vector3.new(wallT, wallH, hubSize + wallT * 2),
		CFrame.new(center.X + half + wallT / 2, wallY, center.Z))
	hubWall("HubWall_W",
		Vector3.new(wallT, wallH, hubSize + wallT * 2),
		CFrame.new(center.X - half - wallT / 2, wallY, center.Z))

	-- Corner pillars
	for _, offset in ipairs({
		Vector3.new(-half, 0, -half),
		Vector3.new(half, 0, -half),
		Vector3.new(half, 0, half),
		Vector3.new(-half, 0, half),
	}) do
		local pillar = makePart("HubPillar",
			Vector3.new(6, wallH + 4, 6),
			CFrame.new(center.X + offset.X, wallY + 2, center.Z + offset.Z),
			trimColor, Enum.Material.Neon, root)
		local pillarLight = Instance.new("PointLight")
		pillarLight.Brightness = 1.2
		pillarLight.Range = 20
		pillarLight.Color = trimColor
		pillarLight.Parent = pillar
	end

	local count = Constants.WORLD_COUNT
	local spacing = Constants.HUB_PAD_SPACING
	local startX = -((count - 1) * spacing) / 2
	local padZ = center.Z + 20

	for worldId = 1, count do
		local world = Constants.WORLDS[worldId]
		if world then
		local px = center.X + startX + (worldId - 1) * spacing
		local pad = makePart("WorldPad_" .. worldId,
			Vector3.new(14, 1.5, 14),
			CFrame.new(px, center.Y + 2.75, padZ),
			world.color,
			Enum.Material.Neon,
			root)

		local idVal = Instance.new("IntValue")
		idVal.Name = "WorldId"
		idVal.Value = worldId
		idVal.Parent = pad

		local beam = makePart("PadBeam_" .. worldId,
			Vector3.new(4, 30, 4),
			CFrame.new(px, center.Y + 17, padZ),
			world.color,
			Enum.Material.Neon,
			root)
		beam.Transparency = 0.6
		beam.CanCollide = false

		wireWorldPad(pad, worldId)
		end
	end

	Logger.info(TAG, "Hub built", "pads=" .. count, "decor=Hub/Decor (your edits are kept)")
end

local function setupHub()
	wiredPads = {}
	wiredBonusPads = {}
	if Constants.USE_CUSTOM_HUB and useCustomHub() then
		HubService.ensureBonusPads()
		return
	end
	if hubHasLayout() then
		loadBakedHub()
		HubService.ensureBonusPads()
		return
	end
	-- Fallback: build at runtime if assets/Hub/Generated is empty
	buildHub()
	HubService.ensureBonusPads()
end

-- ─── World selection ────────────────────────────────────────────────────────────
function HubService.requestWorld(player: Player, worldId: number)
	local data = PlayerDataService.get(player)
	if not data then return end

	local world = Constants.WORLDS[worldId]
	if not world then return end

	if HubService.isWorldUnlocked(data, worldId) then
		Logger.info(TAG, "Starting world from hub", player.Name, "world=" .. worldId)
		MazeService.startMaze(player, worldId)
		return
	end

	Logger.info(TAG, "Locked world tapped", player.Name, "world=" .. worldId)

	-- Remember which world the player wants to buy
	pendingUnlockWorld[player.UserId] = worldId

	local coinCost = Constants.WORLD_UNLOCK_COIN_COST
	local canAfford = (data.Coins or 0) >= coinCost

	Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
		title = "🔒 " .. world.name .. " Locked",
		text  = "Need Lv " .. world.unlockLevel
			.. " OR beat World " .. (worldId - 1)
			.. ". Unlock early below!",
		icon  = "🔒",
		color = "gold",
		action = "promptUnlock",
		worldId = worldId,
		worldName = world.name,
		coinCost = coinCost,
		canAffordCoins = canAfford,
		productId = Constants.PRODUCT_IDS.UnlockWorld,
	})
end

function HubService.teleportToHub(player: Player)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	hrp.CFrame = HubService.getSpawnCFrame()
	Remotes:WaitForChild(RemoteDefs.HubEntered):FireClient(player)
	Logger.info(TAG, "Player sent to hub", player.Name)
end

function HubService.init()
	PlayerDataService = require(script.Parent.PlayerDataService)
	MazeService       = require(script.Parent.MazeService)

	setupHub()

	Remotes:WaitForChild(RemoteDefs.SelectWorld).OnServerInvoke = function(player, worldId: number)
		HubService.requestWorld(player, worldId)
		return true
	end

	-- Client asks before opening Robux prompt — stores pending world
	Remotes:WaitForChild(RemoteDefs.PrepareWorldUnlock).OnServerInvoke = function(player, worldId: number)
		local data = PlayerDataService.get(player)
		if not data then return { ok = false, reason = "No data" } end
		if HubService.isWorldUnlocked(data, worldId) then
			return { ok = false, reason = "Already unlocked" }
		end

		pendingUnlockWorld[player.UserId] = worldId
		Logger.info(TAG, "Prepared Robux unlock", player.Name, "world=" .. worldId)

		return {
			ok = true,
			worldId = worldId,
			worldName = Constants.WORLDS[worldId].name,
			productId = Constants.PRODUCT_IDS.UnlockWorld,
			coinCost = Constants.WORLD_UNLOCK_COIN_COST,
			canAffordCoins = (data.Coins or 0) >= Constants.WORLD_UNLOCK_COIN_COST,
			isStudio = RunService:IsStudio(),
		}
	end

	-- Unlock with in-game coins (works in Studio without API access)
	Remotes:WaitForChild(RemoteDefs.UnlockWorldWithCoins).OnServerInvoke = function(player, worldId: number)
		local data = PlayerDataService.get(player)
		if not data then return false, "No data" end
		if HubService.isWorldUnlocked(data, worldId) then
			return false, "Already unlocked"
		end

		local cost = Constants.WORLD_UNLOCK_COIN_COST
		if (data.Coins or 0) < cost then
			return false, "Need " .. cost .. " coins (you have " .. (data.Coins or 0) .. ")"
		end

		data.Coins -= cost
		HubService.unlockWorld(player, worldId, "coins")
		Logger.info(TAG, "Coin unlock", player.Name, "world=" .. worldId, "cost=" .. cost)
		return true, "Unlocked!"
	end

	-- Free unlock in Studio (Robux products don't work with placeholder IDs)
	Remotes:WaitForChild(RemoteDefs.UnlockWorldStudioTest).OnServerInvoke = function(player, worldId: number)
		if not RunService:IsStudio() then
			return false, "Not available"
		end
		local data = PlayerDataService.get(player)
		if not data then return false, "No data" end
		if HubService.isWorldUnlocked(data, worldId) then
			return false, "Already unlocked"
		end
		HubService.unlockWorld(player, worldId, "studio")
		Logger.info(TAG, "Studio test unlock", player.Name, "world=" .. worldId)
		return true, "Unlocked (Studio test)"
	end

	Remotes:WaitForChild(RemoteDefs.ReturnToHub).OnServerEvent:Connect(function(player)
		MazeService.endSession(player)
		HubService.teleportToHub(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		padDebounce[player.UserId] = nil
		pendingUnlockWorld[player.UserId] = nil
	end)

	Logger.info(TAG, "Initialized")
end

return HubService

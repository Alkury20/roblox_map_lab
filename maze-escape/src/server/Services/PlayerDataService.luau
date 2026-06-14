-- PlayerDataService.luau
-- Handles all player data persistence via DataStore

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)
local Logger     = require(ReplicatedStorage.Shared.Logger)

local TAG = "PlayerData"

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PlayerDataService = {}

local dataStore = DataStoreService:GetDataStore(Constants.DATA_STORE_NAME)
local playerData: { [number]: any } = {}
local saveLocks: { [number]: boolean } = {}

-- In Studio without API access, DataStore calls hang for several seconds — skip them.
local SKIP_DATASTORE = RunService:IsStudio()
local SKIP_MARKETPLACE = RunService:IsStudio()

-- Deep copy defaults
local function deepCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = type(v) == "table" and deepCopy(v) or v
	end
	return copy
end

-- Merge new fields into existing data (for updates across versions)
local function reconcile(data, defaults)
	for k, v in pairs(defaults) do
		if data[k] == nil then
			data[k] = type(v) == "table" and deepCopy(v) or v
		elseif type(v) == "table" and type(data[k]) == "table" then
			reconcile(data[k], v)
		end
	end
	return data
end

local function loadDataFromStore(player: Player)
	local userId = player.UserId

	if SKIP_DATASTORE then
		return nil
	end

	local success, result = pcall(function()
		return dataStore:GetAsync("player_" .. userId)
	end)

	if success and result then
		local data = reconcile(result, deepCopy(Constants.DEFAULT_DATA))
		Logger.info(TAG, "Data loaded", player.Name, "Level=" .. data.Level, "Coins=" .. data.Coins)
		return data
	end

	if not success then
		Logger.warn(TAG, "DataStore load failed", player.Name, tostring(result))
	end

	return nil
end

local function giveDefaults(player: Player)
	local data = deepCopy(Constants.DEFAULT_DATA)
	if SKIP_DATASTORE then
		data.Coins = Constants.STUDIO_START_COINS or 500
	end
	playerData[player.UserId] = data
	return data
end

local function pushDataToClient(player: Player)
	local data = playerData[player.UserId]
	if data then
		Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
	end
end

local function saveData(player: Player)
	if SKIP_DATASTORE then return end

	local userId = player.UserId
	if saveLocks[userId] then return end
	saveLocks[userId] = true

	local data = playerData[userId]
	if not data then
		saveLocks[userId] = false
		return
	end

	local success, err = pcall(function()
		dataStore:SetAsync("player_" .. userId, data)
	end)

	if not success then
		Logger.warn(TAG, "DataStore save failed", player.Name, tostring(err))
	end

	saveLocks[userId] = false
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function PlayerDataService.get(player: Player)
	local data = playerData[player.UserId]
	if not data then
		data = giveDefaults(player)
	end
	return data
end

function PlayerDataService.set(player: Player, key: string, value: any)
	local data = playerData[player.UserId]
	if not data then return end
	data[key] = value

	-- Broadcast updated data to client
	Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
end

function PlayerDataService.increment(player: Player, key: string, amount: number)
	local data = playerData[player.UserId]
	if not data then return end
	data[key] = (data[key] or 0) + amount
	Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
end

function PlayerDataService.addXP(player: Player, amount: number)
	local data = playerData[player.UserId]
	if not data then return end

	data.XP = (data.XP or 0) + amount

	-- Level up
	local leveled = false
	repeat
		local xpNeeded = math.floor(Constants.XP_PER_LEVEL * (Constants.XP_LEVEL_SCALE ^ (data.Level - 1)))
		if data.XP >= xpNeeded and data.Level < Constants.MAX_LEVEL then
			data.XP -= xpNeeded
			data.Level += 1
			leveled = true

			Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
				title = "Level Up!",
				text  = "You reached Level " .. data.Level .. "!",
				icon  = "⭐",
				color = "gold",
			})
		else
			break
		end
	until data.Level >= Constants.MAX_LEVEL

	Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
	return leveled
end

function PlayerDataService.addCoins(player: Player, amount: number)
	local data = playerData[player.UserId]
	if not data then return end

	-- Double coins gamepass
	if data.Gamepasses and data.Gamepasses.DoubleCoins then
		amount *= Constants.DOUBLE_COIN_MULTIPLIER
	end

	data.Coins = (data.Coins or 0) + amount
	Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
end

function PlayerDataService.unlockAchievement(player: Player, achievementId: string)
	local data = playerData[player.UserId]
	if not data then return end
	if data.Achievements[achievementId] then return end -- already unlocked

	data.Achievements[achievementId] = true

	-- Find achievement config
	for _, ach in ipairs(Constants.ACHIEVEMENTS) do
		if ach.id == achievementId then
			PlayerDataService.addCoins(player, ach.coins)
			PlayerDataService.addXP(player, ach.xp)

			Remotes:WaitForChild(RemoteDefs.AchievementUnlocked):FireClient(player, ach)
			break
		end
	end

	Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
end

function PlayerDataService.checkAchievements(player: Player)
	local data = playerData[player.UserId]
	if not data then return end

	local total = data.TotalMazesCompleted or 0
	local secrets = data.SecretRoomsFound or 0

	if total >= 1   then PlayerDataService.unlockAchievement(player, "first_maze") end
	if total >= 10  then PlayerDataService.unlockAchievement(player, "maze_10")    end
	if total >= 50  then PlayerDataService.unlockAchievement(player, "maze_50")    end
	if total >= 100 then PlayerDataService.unlockAchievement(player, "maze_100")   end
	if secrets >= 1 then PlayerDataService.unlockAchievement(player, "secret_1")   end
	if secrets >= 10 then PlayerDataService.unlockAchievement(player, "secret_10") end
	if data.Level >= 10 then PlayerDataService.unlockAchievement(player, "level_10") end
	if data.Level >= 50 then PlayerDataService.unlockAchievement(player, "level_50") end
	if (data.Coins or 0) >= 1000 then PlayerDataService.unlockAchievement(player, "rich") end

	-- All worlds completed
	local allDone = true
	for worldId = 1, #Constants.WORLDS do
		if not data.CompletedWorlds[worldId] then
			allDone = false
			break
		end
	end
	if allDone then PlayerDataService.unlockAchievement(player, "all_worlds") end
end

-- ─── Gamepass check ───────────────────────────────────────────────────────────
local MarketplaceService = game:GetService("MarketplaceService")

local function refreshGamepasses(player: Player)
	if SKIP_MARKETPLACE then return end

	local data = playerData[player.UserId]
	if not data then return end

	for passName, passId in pairs(Constants.GAMEPASS_IDS) do
		if passId and passId > 1000 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if ok and owns then
				data.Gamepasses[passName] = true
			end
		end
	end
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function PlayerDataService.init()
	-- Remote: GetPlayerData
	Remotes:WaitForChild(RemoteDefs.GetPlayerData).OnServerInvoke = function(player)
		return PlayerDataService.get(player)
	end

	local function onPlayerAdded(player: Player)
		Logger.info(TAG, "Player joined", player.Name)

		-- Instant defaults — client never waits on a slow DataStore
		local data = giveDefaults(player)
		if SKIP_DATASTORE then
			Logger.info(TAG, "Studio fast-load — defaults ready", player.Name)
		end

		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid")
			local d = playerData[player.UserId]
			if d and d.Gamepasses and d.Gamepasses.SpeedBoost then
				humanoid.WalkSpeed = Constants.PLAYER_SPEED_BOOST
			else
				humanoid.WalkSpeed = Constants.PLAYER_SPEED_DEFAULT
			end
		end)

		-- Notify client immediately (no artificial delay)
		task.defer(pushDataToClient, player)

		-- Load real save + gamepasses in background (live game only)
		task.spawn(function()
			local stored = loadDataFromStore(player)
			if stored then
				playerData[player.UserId] = stored
				pushDataToClient(player)
			end
			refreshGamepasses(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		Logger.info(TAG, "Player leaving, saving", player.Name)
		saveData(player)
		playerData[player.UserId] = nil
	end)

	-- Auto-save loop
	task.spawn(function()
		while true do
			task.wait(Constants.DATA_SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(saveData, player)
			end
		end
	end)

	-- Gamepass purchase callback
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then return end
		local data = playerData[player.UserId]
		if not data then return end

		for passName, id in pairs(Constants.GAMEPASS_IDS) do
			if id == passId then
				data.Gamepasses[passName] = true

				if passName == "SpeedBoost" and player.Character then
					local hum = player.Character:FindFirstChild("Humanoid")
					if hum then hum.WalkSpeed = Constants.PLAYER_SPEED_BOOST end
				end

				Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
					title = "Gamepass Activated!",
					text  = passName .. " is now active.",
					icon  = "✨",
					color = "gold",
				})
				Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
				break
			end
		end
	end)

	Logger.info(TAG, "Initialized")
end

return PlayerDataService

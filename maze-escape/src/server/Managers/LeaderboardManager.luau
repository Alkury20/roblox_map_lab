-- LeaderboardManager.luau
-- Manages OrderedDataStore leaderboards and in-game leaderboard GUI

local Players              = game:GetService("Players")
local DataStoreService     = game:GetService("DataStoreService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LeaderboardManager = {}

local mostMazesStore  = DataStoreService:GetOrderedDataStore("LB_MostMazes_v1")
local fastestTimeStore= DataStoreService:GetOrderedDataStore("LB_FastestTime_v1")
local mostCoinsStore  = DataStoreService:GetOrderedDataStore("LB_MostCoins_v1")

local PlayerDataService

local function updateStores(player: Player)
	local data = PlayerDataService.get(player)
	if not data then return end

	local uid = tostring(player.UserId)

	pcall(function()
		mostMazesStore:SetAsync(uid, data.TotalMazesCompleted or 0)
	end)
	pcall(function()
		mostCoinsStore:SetAsync(uid, data.Coins or 0)
	end)

	-- Fastest time: sum all best times (lower = better, so store negative)
	local totalBest = 0
	for _, t in pairs(data.BestTimes or {}) do
		totalBest += t
	end
	if totalBest > 0 then
		pcall(function()
			fastestTimeStore:SetAsync(uid, -totalBest)
		end)
	end
end

local function getTop10(store: OrderedDataStore): { { name: string, value: number } }
	local results = {}
	local success, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if not success then return results end

	local page = pages:GetCurrentPage()
	for _, entry in ipairs(page) do
		local name = "[Unknown]"
		pcall(function()
			name = Players:GetNameFromUserIdAsync(tonumber(entry.key))
		end)
		table.insert(results, { name = name, value = math.abs(entry.value) })
	end
	return results
end

function LeaderboardManager.init()
	PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)

	-- GetLeaderboard remote
	Remotes:WaitForChild(RemoteDefs.GetLeaderboard).OnServerInvoke = function(player, category: string)
		if category == "mazes" then
			return getTop10(mostMazesStore)
		elseif category == "coins" then
			return getTop10(mostCoinsStore)
		elseif category == "time" then
			return getTop10(fastestTimeStore)
		end
		return {}
	end

	-- Update leaderboard on player leave
	Players.PlayerRemoving:Connect(function(player)
		updateStores(player)
	end)

	-- Periodic update every 5 minutes
	task.spawn(function()
		while true do
			task.wait(300)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(updateStores, player)
			end
		end
	end)

	-- In-game leaderboard (Players leaderboard in top-right)
	Players.PlayerAdded:Connect(function(player)
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player

		local coinsVal = Instance.new("IntValue")
		coinsVal.Name = "Coins"
		coinsVal.Parent = leaderstats

		local levelVal = Instance.new("IntValue")
		levelVal.Name = "Level"
		levelVal.Parent = leaderstats

		local mazesVal = Instance.new("IntValue")
		mazesVal.Name = "Mazes"
		mazesVal.Parent = leaderstats

		-- Sync from data every 5 seconds
		task.spawn(function()
			while player.Parent do
				local data = PlayerDataService.get(player)
				if data then
					coinsVal.Value = data.Coins or 0
					levelVal.Value = data.Level or 1
					mazesVal.Value = data.TotalMazesCompleted or 0
				end
				task.wait(5)
			end
		end)
	end)

	print("[LeaderboardManager] Initialized.")
end

return LeaderboardManager

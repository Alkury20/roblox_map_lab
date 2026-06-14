-- init.server.luau
-- Server entry point: bootstraps all services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteDefs        = require(ReplicatedStorage.Shared.RemoteDefinitions)

local Logger = require(ReplicatedStorage.Shared.Logger)

-- ─── Create Remotes ───────────────────────────────────────────────────────────
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function makeEvent(name: string)
	if not Remotes:FindFirstChild(name) then
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = Remotes
	end
end

local function makeFunction(name: string)
	if not Remotes:FindFirstChild(name) then
		local f = Instance.new("RemoteFunction")
		f.Name = name
		f.Parent = Remotes
	end
end

-- Events
makeEvent(RemoteDefs.DataUpdated)
makeEvent(RemoteDefs.MazeLoaded)
makeEvent(RemoteDefs.PlayerReachedExit)
makeEvent(RemoteDefs.PlayerDied)
makeEvent(RemoteDefs.ActivateCheckpoint)
makeEvent(RemoteDefs.CollectCoin)
makeEvent(RemoteDefs.EnterSecretRoom)
makeEvent(RemoteDefs.PlayEffect)
makeEvent(RemoteDefs.ShowNotification)
makeEvent(RemoteDefs.AchievementUnlocked)

-- Functions
makeFunction(RemoteDefs.GetPlayerData)
makeFunction(RemoteDefs.RequestPathHint)
makeFunction(RemoteDefs.SkipLevel)
makeFunction(RemoteDefs.PurchaseItem)
makeFunction(RemoteDefs.EquipItem)
makeFunction(RemoteDefs.ClaimQuestReward)
makeFunction(RemoteDefs.GetQuests)
makeFunction(RemoteDefs.ClaimDailyReward)
makeFunction(RemoteDefs.GetLeaderboard)
makeFunction(RemoteDefs.SelectWorld)
makeFunction(RemoteDefs.PrepareWorldUnlock)
makeFunction(RemoteDefs.UnlockWorldWithCoins)
makeFunction(RemoteDefs.UnlockWorldStudioTest)
makeFunction(RemoteDefs.CheckAdmin)
makeFunction(RemoteDefs.AdminSetSpeed)
makeFunction(RemoteDefs.AdminToggleFly)
makeEvent(RemoteDefs.ReturnToHub)
makeEvent(RemoteDefs.HubEntered)

Logger.info("Boot", "Remotes created", #Remotes:GetChildren(), "total")

-- ─── Load Services ────────────────────────────────────────────────────────────
-- Rojo maps init.server.luau to the Server Script itself; Services/Managers are children of script.
local Server = script

Logger.info("Boot", "Loading services...")

local PlayerDataService = Logger.requireModule("Boot", Server.Services.PlayerDataService)
local MazeService       = Logger.requireModule("Boot", Server.Services.MazeService)
local HubService        = Logger.requireModule("Boot", Server.Services.HubService)
local ShopService       = Logger.requireModule("Boot", Server.Services.ShopService)
local QuestService      = Logger.requireModule("Boot", Server.Services.QuestService)
local RewardService     = Logger.requireModule("Boot", Server.Services.RewardService)
local LeaderboardManager = Logger.requireModule("Boot", Server.Managers.LeaderboardManager)
local AdminService     = Logger.requireModule("Boot", Server.Services.AdminService)

Logger.info("Boot", "Initializing PlayerDataService")
PlayerDataService.init()
Logger.info("Boot", "Initializing HubService")
HubService.init()
Logger.info("Boot", "Initializing MazeService")
MazeService.init()
Logger.info("Boot", "Initializing ShopService")
ShopService.init()
Logger.info("Boot", "Initializing QuestService")
QuestService.init()
Logger.info("Boot", "Initializing RewardService")
RewardService.init()
Logger.info("Boot", "Initializing LeaderboardManager")
LeaderboardManager.init()
Logger.info("Boot", "Initializing AdminService")
AdminService.init()

Logger.info("Boot", "All services started. MazeEscape ready!")

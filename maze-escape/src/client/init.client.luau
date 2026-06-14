-- init.client.luau
-- Client entry point

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Wait for shared modules
local Shared     = ReplicatedStorage:WaitForChild("Shared")
local Remotes    = ReplicatedStorage:WaitForChild("Remotes")

local Constants  = require(Shared.Constants)
local RemoteDefs = require(Shared.RemoteDefinitions)
local Logger     = require(Shared.Logger)

local TAG = "Boot"

-- Load controllers
-- Rojo maps init.client.luau to the Client LocalScript itself; Controllers/UI are children of script.
local Client = script

Logger.info(TAG, "Loading client modules...")
local MazeController    = Logger.requireModule(TAG, Client.Controllers.MazeController)
local EffectController  = Logger.requireModule(TAG, Client.Controllers.EffectController)
local InputController   = Logger.requireModule(TAG, Client.Controllers.InputController)
local AdminController   = Logger.requireModule(TAG, Client.Controllers.AdminController)
local TutorialController = Logger.requireModule(TAG, Client.Controllers.TutorialController)

-- Load UI modules
local MainGui           = Logger.requireModule(TAG, Client.UI.MainGui)
local ShopGui           = Logger.requireModule(TAG, Client.UI.ShopGui)
local BonusGui          = Logger.requireModule(TAG, Client.UI.BonusGui)
local QuestGui          = Logger.requireModule(TAG, Client.UI.QuestGui)
local LeaderboardGui    = Logger.requireModule(TAG, Client.UI.LeaderboardGui)
local NotificationGui   = Logger.requireModule(TAG, Client.UI.NotificationGui)
local AdminGui          = Logger.requireModule(TAG, Client.UI.AdminGui)

-- Local player state
local playerData = nil

-- ─── Initialize ───────────────────────────────────────────────────────────────
local function init()
	Logger.info(TAG, "Initializing client for", localPlayer.Name)

	-- Fetch initial data
	local getData = Remotes:WaitForChild(RemoteDefs.GetPlayerData)
	playerData = getData:InvokeServer()
	Logger.info(TAG, "Player data received",
		"Level=" .. (playerData and playerData.Level or "?"),
		"Coins=" .. (playerData and playerData.Coins or "?"),
		"World=" .. (playerData and playerData.CurrentWorld or "?")
	)

	-- Init all UIs
	Logger.debug(TAG, "Initializing UI...")
	MainGui.init(playerData)
	ShopGui.init(playerData)
	BonusGui.init(playerData)
	QuestGui.init(playerData)
	LeaderboardGui.init()
	NotificationGui.init()
	AdminGui.init()

	-- Init controllers
	Logger.debug(TAG, "Initializing controllers...")
	MazeController.init()
	EffectController.init(playerData)
	InputController.init()
	AdminController.init()
	TutorialController.init(playerData)

	-- Data update listener
	Remotes:WaitForChild(RemoteDefs.DataUpdated).OnClientEvent:Connect(function(newData)
		playerData = newData
		MainGui.updateData(newData)
		ShopGui.onDataUpdated(newData)
		BonusGui.onDataUpdated(newData)
		EffectController.onDataUpdated(newData)
		TutorialController.onDataUpdated(newData)
	end)

	-- Notification listener
	Remotes:WaitForChild(RemoteDefs.ShowNotification).OnClientEvent:Connect(function(notifData)
		NotificationGui.show(notifData)

		if notifData.action == "daily" then
			QuestGui.showDailyReward()
		end
	end)

	Remotes:WaitForChild(RemoteDefs.AchievementUnlocked).OnClientEvent:Connect(function(achievement)
		NotificationGui.showAchievement(achievement)
	end)

	Remotes:WaitForChild(RemoteDefs.PlayEffect).OnClientEvent:Connect(function(effectData)
		EffectController.onEffect(effectData)
	end)

	Remotes:WaitForChild(RemoteDefs.MazeLoaded).OnClientEvent:Connect(function(mazeInfo)
		Logger.info(TAG, "Maze loaded on client",
			mazeInfo.worldName or "?",
			(mazeInfo.width or "?") .. "x" .. (mazeInfo.height or "?"),
			"theme=" .. (mazeInfo.theme or "?")
		)
		MazeController.onMazeLoaded(mazeInfo)
		MainGui.onMazeLoaded(mazeInfo)
		TutorialController.onMazeLoaded(mazeInfo)
	end)

	Remotes:WaitForChild(RemoteDefs.HubEntered).OnClientEvent:Connect(function()
		Logger.info(TAG, "Entered hub")
		MazeController.onHubEntered()
		MainGui.onHubEntered()
		TutorialController.onHubEntered()
	end)

	Logger.info(TAG, "Client ready for", localPlayer.Name)
end

-- Bootstrap: load modules first, init as soon as character exists
local function bootstrap()
	if not localPlayer.Character then
		Logger.info(TAG, "Waiting for character...")
		localPlayer.CharacterAdded:Wait()
	end
	Logger.debug(TAG, "Character ready — initializing")
	init()
end

bootstrap()

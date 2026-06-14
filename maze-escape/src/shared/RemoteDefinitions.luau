-- RemoteDefinitions.luau
-- Central list of all RemoteEvent / RemoteFunction names

return {
	-- Player data
	GetPlayerData     = "GetPlayerData",      -- RemoteFunction
	DataUpdated       = "DataUpdated",         -- RemoteEvent (server -> client)

	-- Maze
	MazeLoaded        = "MazeLoaded",          -- RemoteEvent (server -> client)
	PlayerReachedExit = "PlayerReachedExit",   -- RemoteEvent (client -> server)
	PlayerDied        = "PlayerDied",          -- RemoteEvent (client -> server)
	ActivateCheckpoint = "ActivateCheckpoint", -- RemoteEvent (client -> server)
	CollectCoin       = "CollectCoin",         -- RemoteEvent (client -> server)
	EnterSecretRoom   = "EnterSecretRoom",     -- RemoteEvent (client -> server)
	RequestPathHint   = "RequestPathHint",     -- RemoteFunction
	SkipLevel         = "SkipLevel",           -- RemoteFunction (uses dev product)

	-- Shop
	PurchaseItem      = "PurchaseItem",        -- RemoteFunction
	EquipItem         = "EquipItem",           -- RemoteFunction

	-- Quests
	ClaimQuestReward  = "ClaimQuestReward",    -- RemoteFunction
	GetQuests         = "GetQuests",           -- RemoteFunction

	-- Daily reward
	ClaimDailyReward  = "ClaimDailyReward",    -- RemoteFunction

	-- Effects (server -> client broadcasts)
	PlayEffect        = "PlayEffect",          -- RemoteEvent
	ShowNotification  = "ShowNotification",    -- RemoteEvent

	-- Leaderboard
	GetLeaderboard    = "GetLeaderboard",      -- RemoteFunction

	-- Achievements
	AchievementUnlocked = "AchievementUnlocked", -- RemoteEvent

	-- World selection / monetization
	SelectWorld       = "SelectWorld",         -- RemoteFunction
	ReturnToHub       = "ReturnToHub",         -- RemoteEvent (client -> server)
	HubEntered        = "HubEntered",          -- RemoteEvent (server -> client)
	PrepareWorldUnlock = "PrepareWorldUnlock", -- RemoteFunction (client -> server)
	UnlockWorldWithCoins = "UnlockWorldWithCoins", -- RemoteFunction
	UnlockWorldStudioTest = "UnlockWorldStudioTest", -- RemoteFunction (Studio only)

	-- Bonus levels
	StartBonusLevel       = "StartBonusLevel",       -- RemoteFunction
	UnlockBonusLevel      = "UnlockBonusLevel",    -- RemoteFunction
	UnlockBonusStudioTest = "UnlockBonusStudioTest", -- RemoteFunction (Studio only)

	-- Admin
	CheckAdmin        = "CheckAdmin",          -- RemoteFunction
	AdminSetSpeed     = "AdminSetSpeed",       -- RemoteFunction
	AdminToggleFly    = "AdminToggleFly",      -- RemoteFunction
}

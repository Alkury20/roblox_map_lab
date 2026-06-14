-- RewardService.luau
-- Handles daily login rewards

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RewardService = {}
local PlayerDataService

local DAY_SECONDS = 86400

function RewardService.init()
	PlayerDataService = require(script.Parent.PlayerDataService)

	Remotes:WaitForChild(RemoteDefs.ClaimDailyReward).OnServerInvoke = function(player)
		local data = PlayerDataService.get(player)
		if not data then return false, "No data" end

		local now = os.time()
		local last = data.LastDailyReward or 0
		local elapsed = now - last

		if elapsed < DAY_SECONDS then
			local remaining = DAY_SECONDS - elapsed
			return false, "Available in " .. math.floor(remaining / 3600) .. "h " .. math.floor((remaining % 3600) / 60) .. "m"
		end

		-- Check if streak is broken (>48h since last claim)
		if elapsed > DAY_SECONDS * 2 then
			data.DailyRewardStreak = 0
		end

		data.DailyRewardStreak = (data.DailyRewardStreak or 0) + 1
		if data.DailyRewardStreak > 7 then data.DailyRewardStreak = 1 end
		data.LastDailyReward = now

		local streakDay = data.DailyRewardStreak
		local reward = Constants.DAILY_REWARDS[streakDay] or Constants.DAILY_REWARDS[1]

		PlayerDataService.addCoins(player, reward.coins)
		PlayerDataService.addXP(player, reward.xp)

		Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
			title = "Daily Reward (Day " .. streakDay .. ")",
			text  = "+" .. reward.coins .. " coins, +" .. reward.xp .. " XP",
			icon  = "🎁",
			color = "gold",
		})

		Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
		return true, {
			coins  = reward.coins,
			xp     = reward.xp,
			streak = streakDay,
		}
	end

	-- Auto-prompt daily reward on join
	Players.PlayerAdded:Connect(function(player)
		task.wait(3)
		local data = PlayerDataService.get(player)
		if not data then return end

		local now = os.time()
		local last = data.LastDailyReward or 0
		if (now - last) >= DAY_SECONDS then
			Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
				title = "Daily Reward Available!",
				text  = "Open the rewards menu to claim your daily bonus.",
				icon  = "🎁",
				color = "gold",
				action = "daily",
			})
		end
	end)

	print("[RewardService] Initialized.")
end

return RewardService

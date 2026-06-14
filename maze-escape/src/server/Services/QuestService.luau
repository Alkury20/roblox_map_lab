-- QuestService.luau
-- Daily and weekly quest management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local QuestService = {}
local PlayerDataService

local DAY_SECONDS  = 86400
local WEEK_SECONDS = 604800

local function getActiveQuests(data)
	local now = os.time()

	-- Reset daily quests if >24h
	if not data.QuestProgress["_daily_reset"] or (now - data.QuestProgress["_daily_reset"]) >= DAY_SECONDS then
		data.QuestProgress["_daily_reset"] = now
		data.QuestProgress["_daily_claimed"] = {}
		-- Pick 3 random daily quests
		local available = {}
		for _, q in ipairs(Constants.DAILY_QUESTS) do
			table.insert(available, q.id)
		end
		-- Shuffle
		local rng = Random.new(math.floor(now / DAY_SECONDS))
		for i = #available, 2, -1 do
			local j = rng:NextInteger(1, i)
			available[i], available[j] = available[j], available[i]
		end
		data.QuestProgress["_daily_active"] = { available[1], available[2], available[3] }
		-- Reset progress for daily quests
		for _, id in ipairs(data.QuestProgress["_daily_active"] or {}) do
			data.QuestProgress["daily_" .. id] = 0
		end
	end

	-- Reset weekly quests if >7 days
	if not data.WeeklyQuestReset or (now - data.WeeklyQuestReset) >= WEEK_SECONDS then
		data.WeeklyQuestReset = now
		data.QuestProgress["_weekly_claimed"] = {}
		for _, q in ipairs(Constants.WEEKLY_QUESTS) do
			data.QuestProgress["weekly_" .. q.id] = 0
		end
	end

	return {
		daily   = data.QuestProgress["_daily_active"] or {},
		claimed_daily  = data.QuestProgress["_daily_claimed"] or {},
		claimed_weekly = data.QuestProgress["_weekly_claimed"] or {},
	}
end

function QuestService.incrementProgress(player: Player, questKey: string, amount: number)
	local data = PlayerDataService.get(player)
	if not data then return end

	data.QuestProgress[questKey] = (data.QuestProgress[questKey] or 0) + amount
	Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
end

function QuestService.init()
	PlayerDataService = require(script.Parent.PlayerDataService)

	-- GetQuests
	Remotes:WaitForChild(RemoteDefs.GetQuests).OnServerInvoke = function(player)
		local data = PlayerDataService.get(player)
		if not data then return nil end

		local active = getActiveQuests(data)
		local result = {
			daily   = {},
			weekly  = {},
		}

		-- Build daily quest objects
		for _, qid in ipairs(active.daily) do
			for _, q in ipairs(Constants.DAILY_QUESTS) do
				if q.id == qid then
					table.insert(result.daily, {
						id       = q.id,
						desc     = q.desc,
						goal     = q.goal,
						progress = data.QuestProgress["daily_" .. q.id] or 0,
						reward   = q.reward,
						claimed  = (active.claimed_daily[q.id] == true),
					})
					break
				end
			end
		end

		-- Weekly quests
		for _, q in ipairs(Constants.WEEKLY_QUESTS) do
			table.insert(result.weekly, {
				id       = q.id,
				desc     = q.desc,
				goal     = q.goal,
				progress = data.QuestProgress["weekly_" .. q.id] or 0,
				reward   = q.reward,
				claimed  = (active.claimed_weekly and active.claimed_weekly[q.id] == true),
			})
		end

		return result
	end

	-- ClaimQuestReward
	Remotes:WaitForChild(RemoteDefs.ClaimQuestReward).OnServerInvoke = function(player, questId: string, questType: string)
		local data = PlayerDataService.get(player)
		if not data then return false, "No data" end

		local active = getActiveQuests(data)

		if questType == "daily" then
			if active.claimed_daily[questId] then return false, "Already claimed" end

			for _, q in ipairs(Constants.DAILY_QUESTS) do
				if q.id == questId then
					local progress = data.QuestProgress["daily_" .. questId] or 0
					if progress < q.goal then return false, "Not complete" end

					active.claimed_daily[questId] = true
					data.QuestProgress["_daily_claimed"] = active.claimed_daily

					PlayerDataService.addCoins(player, q.reward.coins)
					PlayerDataService.addXP(player, q.reward.xp)
					PlayerDataService.addXP(player, Constants.XP_QUEST_COMPLETE)

					Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
						title = "Quest Complete!",
						text  = q.desc .. " — +" .. q.reward.coins .. " coins",
						icon  = "📋",
						color = "green",
					})
					Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
					return true
				end
			end

		elseif questType == "weekly" then
			if active.claimed_weekly and active.claimed_weekly[questId] then return false, "Already claimed" end

			for _, q in ipairs(Constants.WEEKLY_QUESTS) do
				if q.id == questId then
					local progress = data.QuestProgress["weekly_" .. questId] or 0
					if progress < q.goal then return false, "Not complete" end

					if not data.QuestProgress["_weekly_claimed"] then
						data.QuestProgress["_weekly_claimed"] = {}
					end
					data.QuestProgress["_weekly_claimed"][questId] = true

					PlayerDataService.addCoins(player, q.reward.coins)
					PlayerDataService.addXP(player, q.reward.xp)

					Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
						title = "Weekly Quest Complete!",
						text  = q.desc .. " — +" .. q.reward.coins .. " coins",
						icon  = "🗓️",
						color = "gold",
					})
					Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
					return true
				end
			end
		end

		return false, "Quest not found"
	end

	-- Track maze completions for quests
	Players.PlayerAdded:Connect(function(player)
		-- Hook in after data loads
		task.wait(2)
		local data = PlayerDataService.get(player)
		if data then getActiveQuests(data) end
	end)

	print("[QuestService] Initialized.")
end

return QuestService

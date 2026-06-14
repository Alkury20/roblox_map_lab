-- QuestGui.luau
-- Quests panel + Daily Reward popup

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)

local localPlayer = Players.LocalPlayer
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local C           = Constants.UI

local QuestGui = {}

local isOpen = false
local questPanel: Frame?
local dailyRewardPopup: Frame?
local currentData = nil

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

-- ─── Progress Bar helper ──────────────────────────────────────────────────────
local function progressBar(parent, pos, progress, goal, color)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, -16, 0, 8)
	bg.Position = pos
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	bg.BorderSizePixel = 0
	bg.Parent = parent
	corner(bg, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(math.clamp(progress / math.max(goal, 1), 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = color or C.Accent
	fill.BorderSizePixel = 0
	fill.Parent = bg
	corner(fill, 4)

	return bg, fill
end

-- ─── Quest card ───────────────────────────────────────────────────────────────
local function buildQuestCard(parent, quest, questType)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -16, 0, 80)
	card.BackgroundColor3 = C.Surface
	card.BorderSizePixel = 0
	card.Parent = parent
	corner(card, 10)

	-- Description
	local desc = Instance.new("TextLabel")
	desc.Text = quest.desc
	desc.Size = UDim2.new(1, -90, 0, 22)
	desc.Position = UDim2.new(0, 10, 0, 8)
	desc.BackgroundTransparency = 1
	desc.TextColor3 = C.TextPrimary
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 13
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextWrapped = true
	desc.Parent = card

	-- Reward
	local reward = Instance.new("TextLabel")
	reward.Text = "🪙 " .. quest.reward.coins .. "  ⭐ " .. quest.reward.xp
	reward.Size = UDim2.new(0, 100, 0, 20)
	reward.Position = UDim2.new(1, -108, 0, 8)
	reward.BackgroundTransparency = 1
	reward.TextColor3 = C.Gold
	reward.Font = Enum.Font.GothamBold
	reward.TextSize = 12
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.Parent = card

	-- Progress text
	local progText = Instance.new("TextLabel")
	progText.Text = tostring(quest.progress) .. " / " .. tostring(quest.goal)
	progText.Size = UDim2.new(0, 80, 0, 18)
	progText.Position = UDim2.new(0, 10, 0, 34)
	progText.BackgroundTransparency = 1
	progText.TextColor3 = C.TextMuted
	progText.Font = Enum.Font.Gotham
	progText.TextSize = 12
	progText.TextXAlignment = Enum.TextXAlignment.Left
	progText.Parent = card

	progressBar(card, UDim2.new(0, 8, 0, 54), quest.progress, quest.goal,
		quest.progress >= quest.goal and C.Success or C.Accent)

	-- Claim button
	local claimBtn = Instance.new("TextButton")
	claimBtn.Size = UDim2.new(0, 72, 0, 26)
	claimBtn.Position = UDim2.new(1, -80, 0, 46)
	claimBtn.Font = Enum.Font.GothamBold
	claimBtn.TextSize = 12
	claimBtn.BorderSizePixel = 0
	claimBtn.Parent = card
	corner(claimBtn, 6)

	if quest.claimed then
		claimBtn.Text = "✓ Done"
		claimBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
		claimBtn.TextColor3 = C.TextMuted
	elseif quest.progress >= quest.goal then
		claimBtn.Text = "Claim!"
		claimBtn.BackgroundColor3 = C.Success
		claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimBtn.MouseButton1Click:Connect(function()
			local ok = Remotes:WaitForChild(RemoteDefs.ClaimQuestReward):InvokeServer(quest.id, questType)
			if ok then
				claimBtn.Text = "✓ Done"
				claimBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
				claimBtn.TextColor3 = C.TextMuted
			end
		end)
	else
		claimBtn.Text = "In Progress"
		claimBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
		claimBtn.TextColor3 = C.TextMuted
	end

	return card
end

-- ─── Build main quest panel ───────────────────────────────────────────────────
local function buildQuestPanel()
	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")

	local overlay = Instance.new("Frame")
	overlay.Name = "QuestOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.ZIndex = 10
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "QuestPanel"
	panel.Size = UDim2.new(0, 480, 0, 500)
	panel.Position = UDim2.new(0.5, -240, 0.5, -250)
	panel.BackgroundColor3 = C.Background
	panel.ZIndex = 11
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	corner(panel, 16)

	-- Title
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 52)
	titleBar.BackgroundColor3 = C.Surface
	titleBar.BorderSizePixel = 0
	titleBar.ZIndex = 12
	titleBar.Parent = panel
	corner(titleBar, 16)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Text = "📋  Quests"
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	titleLabel.Position = UDim2.new(0, 16, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = C.TextPrimary
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 20
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 13
	titleLabel.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "✕"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -46, 0.5, -18)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 13
	closeBtn.Parent = titleBar
	corner(closeBtn, 8)
	closeBtn.MouseButton1Click:Connect(function() QuestGui.toggle() end)

	-- Scrolling content
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "QuestScroll"
	scroll.Size = UDim2.new(1, -16, 1, -60)
	scroll.Position = UDim2.new(0, 8, 0, 58)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = C.Accent
	scroll.ZIndex = 12
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.Parent = scroll

	return {
		overlay = overlay,
		panel   = panel,
		scroll  = scroll,
	}
end

local questRefs = nil

local function ensureBuilt()
	if not questRefs then
		questRefs = buildQuestPanel()
	end
end

local function populateQuests(questData)
	if not questRefs then return end
	local scroll = questRefs.scroll

	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
	end

	-- Daily quests header
	local dailyHeader = Instance.new("TextLabel")
	dailyHeader.Text = "📅  Daily Quests"
	dailyHeader.Size = UDim2.new(1, -8, 0, 24)
	dailyHeader.BackgroundTransparency = 1
	dailyHeader.TextColor3 = C.Accent
	dailyHeader.Font = Enum.Font.GothamBold
	dailyHeader.TextSize = 15
	dailyHeader.TextXAlignment = Enum.TextXAlignment.Left
	dailyHeader.ZIndex = 12
	dailyHeader.Parent = scroll

	for _, quest in ipairs(questData.daily or {}) do
		buildQuestCard(scroll, quest, "daily")
	end

	-- Weekly header
	local weeklyHeader = Instance.new("TextLabel")
	weeklyHeader.Text = "🗓️  Weekly Quests"
	weeklyHeader.Size = UDim2.new(1, -8, 0, 24)
	weeklyHeader.BackgroundTransparency = 1
	weeklyHeader.TextColor3 = C.Gold
	weeklyHeader.Font = Enum.Font.GothamBold
	weeklyHeader.TextSize = 15
	weeklyHeader.TextXAlignment = Enum.TextXAlignment.Left
	weeklyHeader.ZIndex = 12
	weeklyHeader.Parent = scroll

	for _, quest in ipairs(questData.weekly or {}) do
		buildQuestCard(scroll, quest, "weekly")
	end
end

-- ─── Daily Reward Popup ───────────────────────────────────────────────────────
function QuestGui.showDailyReward()
	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")

	if dailyRewardPopup then dailyRewardPopup:Destroy() end

	local popup = Instance.new("Frame")
	popup.Name = "DailyRewardPopup"
	popup.Size = UDim2.new(0, 320, 0, 280)
	popup.Position = UDim2.new(0.5, -160, 0.5, -140)
	popup.BackgroundColor3 = C.Background
	popup.ZIndex = 20
	popup.BorderSizePixel = 0
	popup.Parent = screenGui
	corner(popup, 16)
	dailyRewardPopup = popup

	local data = currentData
	local streak = data and data.DailyRewardStreak or 0
	local nextStreak = math.clamp((streak % 7) + 1, 1, 7)
	local reward = Constants.DAILY_REWARDS[nextStreak] or Constants.DAILY_REWARDS[1]

	local title = Instance.new("TextLabel")
	title.Text = "🎁  Daily Reward"
	title.Size = UDim2.new(1, 0, 0, 50)
	title.BackgroundTransparency = 1
	title.TextColor3 = C.Gold
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.ZIndex = 21
	title.Parent = popup

	local streakLabel = Instance.new("TextLabel")
	streakLabel.Text = "Day " .. nextStreak .. " of 7  🔥 " .. streak .. " streak"
	streakLabel.Size = UDim2.new(1, 0, 0, 30)
	streakLabel.Position = UDim2.new(0, 0, 0, 50)
	streakLabel.BackgroundTransparency = 1
	streakLabel.TextColor3 = C.TextMuted
	streakLabel.Font = Enum.Font.Gotham
	streakLabel.TextSize = 14
	streakLabel.ZIndex = 21
	streakLabel.Parent = popup

	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Text = "🪙 " .. reward.coins .. " Coins"
	coinsLabel.Size = UDim2.new(1, 0, 0, 40)
	coinsLabel.Position = UDim2.new(0, 0, 0, 95)
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.TextColor3 = C.Gold
	coinsLabel.Font = Enum.Font.GothamBold
	coinsLabel.TextSize = 24
	coinsLabel.ZIndex = 21
	coinsLabel.Parent = popup

	local xpLabel = Instance.new("TextLabel")
	xpLabel.Text = "⭐ " .. reward.xp .. " XP"
	xpLabel.Size = UDim2.new(1, 0, 0, 30)
	xpLabel.Position = UDim2.new(0, 0, 0, 135)
	xpLabel.BackgroundTransparency = 1
	xpLabel.TextColor3 = C.Accent
	xpLabel.Font = Enum.Font.GothamBold
	xpLabel.TextSize = 18
	xpLabel.ZIndex = 21
	xpLabel.Parent = popup

	local claimBtn = Instance.new("TextButton")
	claimBtn.Text = "Claim Reward!"
	claimBtn.Size = UDim2.new(0, 200, 0, 44)
	claimBtn.Position = UDim2.new(0.5, -100, 0, 178)
	claimBtn.BackgroundColor3 = C.Success
	claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	claimBtn.Font = Enum.Font.GothamBold
	claimBtn.TextSize = 16
	claimBtn.BorderSizePixel = 0
	claimBtn.ZIndex = 21
	claimBtn.Parent = popup
	corner(claimBtn, 10)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "Later"
	closeBtn.Size = UDim2.new(0, 80, 0, 30)
	closeBtn.Position = UDim2.new(0.5, -40, 0, 234)
	closeBtn.BackgroundTransparency = 1
	closeBtn.TextColor3 = C.TextMuted
	closeBtn.Font = Enum.Font.Gotham
	closeBtn.TextSize = 13
	closeBtn.ZIndex = 21
	closeBtn.Parent = popup
	closeBtn.MouseButton1Click:Connect(function() popup:Destroy() end)

	claimBtn.MouseButton1Click:Connect(function()
		local ok, result = Remotes:WaitForChild(RemoteDefs.ClaimDailyReward):InvokeServer()
		if ok then
			popup:Destroy()
		else
			claimBtn.Text = tostring(result)
		end
	end)

	-- Animate in
	popup.Position = UDim2.new(0.5, -160, 0.5, -160)
	TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -160, 0.5, -140) }):Play()
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function QuestGui.init(data)
	currentData = data
end

function QuestGui.toggle()
	ensureBuilt()

	isOpen = not isOpen
	questRefs.overlay.Visible = isOpen
	questRefs.panel.Visible   = isOpen

	if isOpen then
		local quests = Remotes:WaitForChild(RemoteDefs.GetQuests):InvokeServer()
		if quests then populateQuests(quests) end

		TweenService:Create(questRefs.panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, -240, 0.5, -250) }):Play()
	end
end

-- Update data reference
ReplicatedStorage:WaitForChild("Remotes")
	:WaitForChild(require(ReplicatedStorage.Shared.RemoteDefinitions).DataUpdated)
	.OnClientEvent:Connect(function(data)
	currentData = data
end)

return QuestGui

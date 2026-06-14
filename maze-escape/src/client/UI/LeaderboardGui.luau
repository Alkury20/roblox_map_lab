-- LeaderboardGui.luau
-- Top-10 leaderboard with 3 categories

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)

local localPlayer = Players.LocalPlayer
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local C           = Constants.UI

local LeaderboardGui = {}

local isOpen = false
local lbRefs = nil
local selectedCategory = "mazes"

local CATEGORIES = {
	{ id = "mazes", label = "🏆 Mazes",  unit = " mazes" },
	{ id = "coins", label = "🪙 Coins",  unit = " coins" },
	{ id = "time",  label = "⚡ Time",   unit = "s total" },
}

local RANK_COLORS = {
	Color3.fromRGB(255, 200, 30),   -- 1st gold
	Color3.fromRGB(180, 180, 180),  -- 2nd silver
	Color3.fromRGB(180, 120, 60),   -- 3rd bronze
}

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function buildPanel()
	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")

	local overlay = Instance.new("Frame")
	overlay.Name = "LBOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.ZIndex = 10
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "LBPanel"
	panel.Size = UDim2.new(0, 400, 0, 480)
	panel.Position = UDim2.new(0.5, -200, 0.5, -240)
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

	local title = Instance.new("TextLabel")
	title.Text = "🏆  Leaderboard"
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.new(0, 16, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = C.TextPrimary
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 13
	title.Parent = titleBar

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
	closeBtn.MouseButton1Click:Connect(function() LeaderboardGui.toggle() end)

	-- Category tabs
	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, -24, 0, 36)
	tabBar.Position = UDim2.new(0, 12, 0, 60)
	tabBar.BackgroundTransparency = 1
	tabBar.ZIndex = 12
	tabBar.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabBar

	local tabBtns: { [string]: TextButton } = {}

	local function selectCat(catId)
		selectedCategory = catId
		for _, b in pairs(tabBtns) do
			b.BackgroundColor3 = C.Surface
			b.TextColor3 = C.TextMuted
		end
		if tabBtns[catId] then
			tabBtns[catId].BackgroundColor3 = C.Accent
			tabBtns[catId].TextColor3 = C.TextPrimary
		end
		LeaderboardGui.refresh()
	end

	for _, cat in ipairs(CATEGORIES) do
		local btn = Instance.new("TextButton")
		btn.Text = cat.label
		btn.Size = UDim2.new(0, 108, 1, 0)
		btn.BackgroundColor3 = C.Surface
		btn.TextColor3 = C.TextMuted
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.BorderSizePixel = 0
		btn.ZIndex = 12
		btn.Parent = tabBar
		corner(btn, 8)
		tabBtns[cat.id] = btn
		btn.MouseButton1Click:Connect(function() selectCat(cat.id) end)
	end

	-- Entry list
	local listFrame = Instance.new("Frame")
	listFrame.Name = "EntryList"
	listFrame.Size = UDim2.new(1, -24, 1, -108)
	listFrame.Position = UDim2.new(0, 12, 0, 104)
	listFrame.BackgroundTransparency = 1
	listFrame.ZIndex = 12
	listFrame.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = listFrame

	return {
		overlay   = overlay,
		panel     = panel,
		listFrame = listFrame,
		tabBtns   = tabBtns,
		selectCat = selectCat,
	}
end

local function populateList(entries, unit)
	if not lbRefs then return end
	local listFrame = lbRefs.listFrame

	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	if #entries == 0 then
		local empty = Instance.new("TextLabel")
		empty.Text = "No data yet. Be the first!"
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.BackgroundTransparency = 1
		empty.TextColor3 = C.TextMuted
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 14
		empty.ZIndex = 12
		empty.Parent = listFrame
		return
	end

	for i, entry in ipairs(entries) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundColor3 = i <= 3 and Color3.fromRGB(35, 30, 50) or C.Surface
		row.BorderSizePixel = 0
		row.ZIndex = 12
		row.Parent = listFrame
		corner(row, 8)

		-- Rank
		local rankLabel = Instance.new("TextLabel")
		rankLabel.Text = i <= 3 and ("" .. (i == 1 and "🥇" or i == 2 and "🥈" or "🥉")) or tostring(i)
		rankLabel.Size = UDim2.new(0, 36, 1, 0)
		rankLabel.Position = UDim2.new(0, 4, 0, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.TextColor3 = RANK_COLORS[i] or C.TextMuted
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.TextSize = i <= 3 and 20 or 14
		rankLabel.ZIndex = 13
		rankLabel.Parent = row

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Text = entry.name
		nameLabel.Size = UDim2.new(1, -120, 1, 0)
		nameLabel.Position = UDim2.new(0, 44, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = C.TextPrimary
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextSize = 14
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.ZIndex = 13
		nameLabel.Parent = row

		-- Value
		local valueLabel = Instance.new("TextLabel")
		valueLabel.Text = tostring(entry.value) .. unit
		valueLabel.Size = UDim2.new(0, 100, 1, 0)
		valueLabel.Position = UDim2.new(1, -108, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.TextColor3 = RANK_COLORS[i] or C.TextMuted
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.TextSize = 13
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.ZIndex = 13
		valueLabel.Parent = row
	end
end

function LeaderboardGui.refresh()
	local entries = Remotes:WaitForChild(RemoteDefs.GetLeaderboard):InvokeServer(selectedCategory)

	local unit = " mazes"
	for _, cat in ipairs(CATEGORIES) do
		if cat.id == selectedCategory then unit = cat.unit break end
	end

	populateList(entries or {}, unit)
end

function LeaderboardGui.init()
	-- nothing to pre-build
end

function LeaderboardGui.toggle()
	if not lbRefs then
		lbRefs = buildPanel()
		lbRefs.selectCat("mazes")
	end

	isOpen = not isOpen
	lbRefs.overlay.Visible = isOpen
	lbRefs.panel.Visible   = isOpen

	if isOpen then
		LeaderboardGui.refresh()
		TweenService:Create(lbRefs.panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, -200, 0.5, -240) }):Play()
	end
end

return LeaderboardGui

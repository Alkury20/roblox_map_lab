-- MainGui.luau
-- Main HUD: coins, level, XP bar, world indicator, timer, quick buttons

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)

local localPlayer = Players.LocalPlayer
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local C           = Constants.UI

local MainGui = {}

local screenGui: ScreenGui
local timerConn: RBXScriptConnection?
local mazeStartTime = 0
local currentMazeInfo = nil

-- ─── Utility ──────────────────────────────────────────────────────────────────
local function newLabel(parent, name, text, size, pos, textSize, bold)
	local l = Instance.new("TextLabel")
	l.Name            = name
	l.Text            = text
	l.Size            = size
	l.Position        = pos
	l.BackgroundTransparency = 1
	l.TextColor3      = C.TextPrimary
	l.TextSize        = textSize or 16
	l.Font            = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextXAlignment  = Enum.TextXAlignment.Left
	l.Parent          = parent
	return l
end

local function newFrame(parent, name, size, pos, color, transparency, cornerRadius)
	local f = Instance.new("Frame")
	f.Name              = name
	f.Size              = size
	f.Position          = pos
	f.BackgroundColor3  = color or C.Surface
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel   = 0
	f.Parent            = parent
	if cornerRadius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, cornerRadius)
		corner.Parent = f
	end
	return f
end

local function newButton(parent, name, text, size, pos, color, textColor)
	local b = Instance.new("TextButton")
	b.Name             = name
	b.Text             = text
	b.Size             = size
	b.Position         = pos
	b.BackgroundColor3 = color or C.Accent
	b.TextColor3       = textColor or C.TextPrimary
	b.Font             = Enum.Font.GothamBold
	b.TextSize         = 14
	b.BorderSizePixel  = 0
	b.AutoButtonColor  = true
	b.Parent           = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	return b
end

local function addStroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color     = color or Color3.fromRGB(255, 255, 255)
	s.Thickness = thickness or 1
	s.Parent    = inst
end

-- ─── Build HUD ────────────────────────────────────────────────────────────────
local function buildHUD(data)
	screenGui = Instance.new("ScreenGui")
	screenGui.Name            = "MazeEscapeGui"
	screenGui.ResetOnSpawn    = false
	screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset  = true
	screenGui.Parent          = localPlayer.PlayerGui

	-- ── Top bar ────────────────────────────────────────────────────────────────
	local topBar = newFrame(screenGui, "TopBar",
		UDim2.new(1, 0, 0, 56),
		UDim2.new(0, 0, 0, 0),
		C.Background, 0.1, 0)

	-- Coin counter
	local coinFrame = newFrame(topBar, "CoinFrame",
		UDim2.new(0, 130, 0, 36),
		UDim2.new(0, 12, 0.5, -18),
		C.Surface, 0, 10)
	addStroke(coinFrame, C.Gold, 1.5)

	local coinIcon = Instance.new("TextLabel")
	coinIcon.Name  = "Icon"
	coinIcon.Text  = "🪙"
	coinIcon.Size  = UDim2.new(0, 30, 1, 0)
	coinIcon.Position = UDim2.new(0, 4, 0, 0)
	coinIcon.BackgroundTransparency = 1
	coinIcon.TextSize = 18
	coinIcon.Font = Enum.Font.Gotham
	coinIcon.Parent = coinFrame

	local coinLabel = newLabel(coinFrame, "CoinsLabel",
		tostring(data and data.Coins or 0),
		UDim2.new(1, -36, 1, 0),
		UDim2.new(0, 36, 0, 0),
		16, true)
	coinLabel.TextColor3 = C.Gold

	-- Level & XP bar
	local levelFrame = newFrame(topBar, "LevelFrame",
		UDim2.new(0, 200, 0, 36),
		UDim2.new(0.5, -100, 0.5, -18),
		C.Surface, 0, 10)
	addStroke(levelFrame, C.Accent, 1.5)

	local levelLabel = newLabel(levelFrame, "LevelLabel",
		"LVL " .. (data and data.Level or 1),
		UDim2.new(0, 60, 1, 0),
		UDim2.new(0, 8, 0, 0),
		14, true)
	levelLabel.TextColor3 = C.Accent

	-- XP bar background
	local xpBg = newFrame(levelFrame, "XPBarBg",
		UDim2.new(1, -72, 0, 8),
		UDim2.new(0, 68, 0.5, -4),
		Color3.fromRGB(50, 50, 70), 0, 4)

	local level = data and data.Level or 1
	local xp    = data and data.XP or 0
	local xpNeeded = math.floor(Constants.XP_PER_LEVEL * (Constants.XP_LEVEL_SCALE ^ (level - 1)))
	local xpFraction = math.clamp(xp / xpNeeded, 0, 1)

	local xpBar = newFrame(xpBg, "XPBar",
		UDim2.new(xpFraction, 0, 1, 0),
		UDim2.new(0, 0, 0, 0),
		C.Accent, 0, 4)

	-- World indicator
	local worldLabel = newLabel(topBar, "WorldLabel",
		"",
		UDim2.new(0, 160, 1, 0),
		UDim2.new(1, -172, 0, 0),
		13, false)
	worldLabel.TextXAlignment = Enum.TextXAlignment.Right
	worldLabel.TextColor3     = C.TextMuted

	-- ── Timer ──────────────────────────────────────────────────────────────────
	local timerFrame = newFrame(screenGui, "TimerFrame",
		UDim2.new(0, 120, 0, 36),
		UDim2.new(0.5, -60, 0, 64),
		C.Surface, 0.1, 10)
	addStroke(timerFrame, C.TextMuted, 1)

	local timerLabel = newLabel(timerFrame, "TimerLabel",
		"00:00",
		UDim2.new(1, 0, 1, 0),
		UDim2.new(0, 0, 0, 0),
		18, true)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- ── Right panel: action buttons ────────────────────────────────────────────
	local rightPanel = newFrame(screenGui, "RightPanel",
		UDim2.new(0, 56, 0, 320),
		UDim2.new(1, -68, 0.5, -160),
		C.Background, 0.8, 12)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder   = Enum.SortOrder.LayoutOrder
	layout.Padding      = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent       = rightPanel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent     = rightPanel

	local function sideBtn(name, icon, color)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = icon
		b.Size = UDim2.new(0, 44, 0, 44)
		b.BackgroundColor3 = color
		b.TextColor3       = Color3.fromRGB(255, 255, 255)
		b.Font             = Enum.Font.Gotham
		b.TextSize         = 22
		b.BorderSizePixel  = 0
		b.AutoButtonColor  = true
		b.LayoutOrder      = 0
		b.Parent           = rightPanel
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = b
		return b
	end

	local shopBtn  = sideBtn("ShopBtn",  "🛍️", Color3.fromRGB(60, 100, 200))
	local questBtn = sideBtn("QuestBtn", "📋", Color3.fromRGB(50, 150, 80))
	local lbBtn    = sideBtn("LBBtn",    "🏆", Color3.fromRGB(180, 130, 20))
	local hintBtn  = sideBtn("HintBtn",  "🗺️", Color3.fromRGB(80, 80, 120))
	local rewardBtn= sideBtn("RewardBtn","🎁", Color3.fromRGB(150, 50, 150))
	local hubBtn   = sideBtn("HubBtn",   "🏠", Color3.fromRGB(200, 70, 70))

	-- Wire buttons to GUI modules (deferred to avoid circular requires)
	shopBtn.MouseButton1Click:Connect(function()
		local ShopGui = require(script.Parent.ShopGui)
		ShopGui.toggle()
	end)
	questBtn.MouseButton1Click:Connect(function()
		local QuestGui = require(script.Parent.QuestGui)
		QuestGui.toggle()
	end)
	lbBtn.MouseButton1Click:Connect(function()
		local LBGui = require(script.Parent.LeaderboardGui)
		LBGui.toggle()
	end)
	hintBtn.MouseButton1Click:Connect(function()
		local MazeController = require(script.Parent.Parent.Controllers.MazeController)
		MazeController.requestHint()
	end)
	rewardBtn.MouseButton1Click:Connect(function()
		local QuestGui = require(script.Parent.QuestGui)
		QuestGui.showDailyReward()
	end)
	hubBtn.MouseButton1Click:Connect(function()
		local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
		Remotes:WaitForChild(RemoteDefs.ReturnToHub):FireServer()
	end)

	return {
		coinLabel  = coinLabel,
		levelLabel = levelLabel,
		xpBar      = xpBar,
		worldLabel = worldLabel,
		timerLabel = timerLabel,
		xpBg       = xpBg,
	}
end

local hudRefs = nil

-- ─── Update helpers ───────────────────────────────────────────────────────────
local function updateTimer()
	if timerConn then timerConn:Disconnect() end
	mazeStartTime = os.time()

	timerConn = RunService.Heartbeat:Connect(function()
		if not hudRefs then return end
		local elapsed = os.time() - mazeStartTime
		local m = math.floor(elapsed / 60)
		local s = elapsed % 60
		hudRefs.timerLabel.Text = string.format("%02d:%02d", m, s)
	end)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function MainGui.init(data)
	hudRefs = buildHUD(data)
	if data then MainGui.updateData(data) end
end

function MainGui.updateData(data)
	if not hudRefs then return end

	hudRefs.coinLabel.Text  = tostring(data.Coins or 0)
	hudRefs.levelLabel.Text = "LVL " .. (data.Level or 1)

	local level   = data.Level or 1
	local xp      = data.XP or 0
	local xpNeeded = math.floor(Constants.XP_PER_LEVEL * (Constants.XP_LEVEL_SCALE ^ (level - 1)))
	local frac    = math.clamp(xp / xpNeeded, 0, 1)

	TweenService:Create(hudRefs.xpBar,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad),
		{ Size = UDim2.new(frac, 0, 1, 0) }):Play()
end

function MainGui.onMazeLoaded(mazeInfo)
	currentMazeInfo = mazeInfo

	if hudRefs then
		local worldConfig = Constants.WORLDS[mazeInfo.worldId]
		if worldConfig then
			hudRefs.worldLabel.Text = worldConfig.icon .. " " .. worldConfig.name
		end
	end

	updateTimer()
end

function MainGui.onHubEntered()
	currentMazeInfo = nil
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end
	if hudRefs then
		hudRefs.worldLabel.Text = "🏠 Hub — pick a world"
		hudRefs.timerLabel.Text = "--:--"
	end
end

return MainGui

-- ShopGui.luau
-- Full shop interface with categories, owned items, equip

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)
local Logger     = require(ReplicatedStorage.Shared.Logger)

local TAG = "ShopGui"

local localPlayer = Players.LocalPlayer
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local C           = Constants.UI

local ShopGui = {}

local shopFrame: Frame?
local isOpen = false
local currentData = nil
local selectedCategory = "trail"

local CATEGORIES = { "trail", "aura", "pet", "effect" }

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function shadow(parent)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(0, 0, 0)
	s.Thickness = 2
	s.Transparency = 0.6
	s.Parent = parent
end

-- ─── Build GUI ────────────────────────────────────────────────────────────────
local function buildShop()
	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")

	-- Overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "ShopOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.ZIndex = 10
	overlay.Parent = screenGui

	-- Main panel
	local panel = Instance.new("Frame")
	panel.Name = "ShopPanel"
	panel.Size = UDim2.new(0, 540, 0, 440)
	panel.Position = UDim2.new(0.5, -270, 0.5, -220)
	panel.BackgroundColor3 = C.Background
	panel.ZIndex = 11
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	corner(panel, 16)
	shadow(panel)

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 52)
	titleBar.BackgroundColor3 = C.Surface
	titleBar.BorderSizePixel = 0
	titleBar.ZIndex = 12
	titleBar.Parent = panel
	corner(titleBar, 16)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Text = "🛍️  Shop"
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
	closeBtn.MouseButton1Click:Connect(function() ShopGui.toggle() end)

	-- Category tabs
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
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

	local function selectCategory(cat: string)
		selectedCategory = cat
		for _, btn in pairs(tabBtns) do
			btn.BackgroundColor3 = C.Surface
			btn.TextColor3 = C.TextMuted
		end
		if tabBtns[cat] then
			tabBtns[cat].BackgroundColor3 = C.Accent
			tabBtns[cat].TextColor3 = C.TextPrimary
		end
		-- Refresh item list
		ShopGui.refreshItems()
	end

	local catIcons = { trail = "✨", aura = "🌟", pet = "🐾", effect = "💫" }
	for _, cat in ipairs(CATEGORIES) do
		local btn = Instance.new("TextButton")
		btn.Name = cat .. "Tab"
		btn.Text = (catIcons[cat] or "") .. " " .. cat:sub(1,1):upper() .. cat:sub(2)
		btn.Size = UDim2.new(0, 110, 1, 0)
		btn.BackgroundColor3 = C.Surface
		btn.TextColor3 = C.TextMuted
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.BorderSizePixel = 0
		btn.ZIndex = 12
		btn.Parent = tabBar
		corner(btn, 8)
		tabBtns[cat] = btn

		btn.MouseButton1Click:Connect(function() selectCategory(cat) end)
	end

	-- Item grid scroll frame
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemGrid"
	scrollFrame.Size = UDim2.new(1, -24, 1, -168)
	scrollFrame.Position = UDim2.new(0, 12, 0, 104)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = C.Accent
	scrollFrame.ZIndex = 12
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = panel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize    = UDim2.new(0, 148, 0, 160)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.Parent      = scrollFrame

	-- Gamepass section
	local gpLabel = Instance.new("TextLabel")
	gpLabel.Name = "GamepassLabel"
	gpLabel.Text = "💎  Gamepasses"
	gpLabel.Size = UDim2.new(1, -24, 0, 30)
	gpLabel.Position = UDim2.new(0, 12, 1, -62)
	gpLabel.BackgroundTransparency = 1
	gpLabel.TextColor3 = C.Gold
	gpLabel.Font = Enum.Font.GothamBold
	gpLabel.TextSize = 15
	gpLabel.TextXAlignment = Enum.TextXAlignment.Left
	gpLabel.ZIndex = 12
	gpLabel.Parent = panel

	local gpScroll = Instance.new("ScrollingFrame")
	gpScroll.Name = "GamepassScroll"
	gpScroll.Size = UDim2.new(1, -24, 0, 44)
	gpScroll.Position = UDim2.new(0, 12, 1, -48)
	gpScroll.BackgroundTransparency = 1
	gpScroll.ScrollBarThickness = 0
	gpScroll.ZIndex = 12
	gpScroll.CanvasSize = UDim2.new(0, 0, 1, 0)
	gpScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	gpScroll.ScrollingDirection = Enum.ScrollingDirection.X
	gpScroll.Parent = panel

	local gpLayout = Instance.new("UIListLayout")
	gpLayout.FillDirection = Enum.FillDirection.Horizontal
	gpLayout.Padding = UDim.new(0, 6)
	gpLayout.Parent = gpScroll

	-- Add gamepass buttons
	local gpNames = { "DoubleCoins", "VIP", "SpeedBoost", "NightVision", "ExtraCheckpoint", "RainbowTrail" }
	local gpIcons = { "×2🪙", "👑 VIP", "⚡ Speed", "👁 Vision", "+🚩 CP", "🌈 Trail" }
	for i, gpName in ipairs(gpNames) do
		local gpBtn = Instance.new("TextButton")
		gpBtn.Text = gpIcons[i]
		gpBtn.Size = UDim2.new(0, 100, 1, -4)
		gpBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 160)
		gpBtn.TextColor3 = C.TextPrimary
		gpBtn.Font = Enum.Font.GothamBold
		gpBtn.TextSize = 12
		gpBtn.BorderSizePixel = 0
		gpBtn.ZIndex = 12
		gpBtn.Parent = gpScroll
		corner(gpBtn, 8)

		gpBtn.MouseButton1Click:Connect(function()
			local id = Constants.GAMEPASS_IDS[gpName]
			if id then
				MarketplaceService:PromptGamePassPurchase(localPlayer, id)
			end
		end)
	end

	return {
		overlay    = overlay,
		panel      = panel,
		scrollFrame = scrollFrame,
		tabBtns    = tabBtns,
		selectCategory = selectCategory,
	}
end

local guiRefs = nil

local function ensureBuilt()
	if not guiRefs then
		guiRefs = buildShop()
		guiRefs.selectCategory("trail")
	end
end

-- ─── Refresh item grid ────────────────────────────────────────────────────────
function ShopGui.refreshItems()
	if not guiRefs then return end

	local scrollFrame = guiRefs.scrollFrame
	-- Clear existing items
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local data = currentData

	for _, item in ipairs(Constants.SHOP_ITEMS) do
		if item.category == selectedCategory then
		local card = Instance.new("Frame")
		card.Name = "Item_" .. item.id
		card.BackgroundColor3 = C.Surface
		card.BorderSizePixel = 0
		card.ZIndex = 13
		card.Parent = scrollFrame
		corner(card, 10)

		-- Color preview
		local colorPreview = Instance.new("Frame")
		colorPreview.Size = UDim2.new(1, -12, 0, 70)
		colorPreview.Position = UDim2.new(0, 6, 0, 6)
		colorPreview.BackgroundColor3 = item.color or C.Accent
		colorPreview.BorderSizePixel = 0
		colorPreview.ZIndex = 14
		colorPreview.Parent = card
		corner(colorPreview, 8)

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(1, 0, 1, 0)
		icon.Text = (item.category == "trail" and "✨") or
		            (item.category == "aura" and "🌟") or
		            (item.category == "pet" and "🐾") or "💫"
		icon.TextSize = 28
		icon.BackgroundTransparency = 1
		icon.TextXAlignment = Enum.TextXAlignment.Center
		icon.ZIndex = 15
		icon.Font = Enum.Font.Gotham
		icon.Parent = colorPreview

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Text = item.name
		nameLabel.Size = UDim2.new(1, -8, 0, 20)
		nameLabel.Position = UDim2.new(0, 4, 0, 80)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = C.TextPrimary
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 13
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.ZIndex = 14
		nameLabel.Parent = card

		-- Price / Status button
		local owned = data and data.OwnedItems and data.OwnedItems[item.id]
		local hasGP = item.gamepass and data and data.Gamepasses and data.Gamepasses[item.gamepass]

		local actionBtn = Instance.new("TextButton")
		actionBtn.Size = UDim2.new(1, -12, 0, 28)
		actionBtn.Position = UDim2.new(0, 6, 1, -34)
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.TextSize = 12
		actionBtn.BorderSizePixel = 0
		actionBtn.ZIndex = 14
		actionBtn.Parent = card
		corner(actionBtn, 6)

		if owned or hasGP then
			-- Check if equipped
			local equipped = data and data.EquippedItems
			local isEquipped = equipped and (
				equipped.Trail == item.id or
				equipped.Aura == item.id or
				equipped.Pet == item.id or
				equipped.Effect == item.id
			)

			if isEquipped then
				actionBtn.Text = "✓ Equipped"
				actionBtn.BackgroundColor3 = C.Success
				actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			else
				actionBtn.Text = "Equip"
				actionBtn.BackgroundColor3 = C.Accent
				actionBtn.TextColor3 = C.TextPrimary
				actionBtn.MouseButton1Click:Connect(function()
					local ok, msg = Remotes:WaitForChild(RemoteDefs.EquipItem):InvokeServer(item.id, item.category)
					if ok then
						Logger.info(TAG, "Equip OK", item.category, item.id, item.name)
						ShopGui.refreshItems()
					else
						Logger.warn(TAG, "Equip failed", item.category, item.id, tostring(msg))
					end
				end)
			end
		elseif item.gamepass then
			actionBtn.Text = "👑 Gamepass"
			actionBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 160)
			actionBtn.TextColor3 = C.Gold
			actionBtn.MouseButton1Click:Connect(function()
				MarketplaceService:PromptGamePassPurchase(localPlayer, Constants.GAMEPASS_IDS[item.gamepass])
			end)
		else
			actionBtn.Text = "🪙 " .. tostring(item.price)
			actionBtn.BackgroundColor3 = C.AccentAlt
			actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			actionBtn.MouseButton1Click:Connect(function()
				local success, msg = Remotes:WaitForChild(RemoteDefs.PurchaseItem):InvokeServer(item.id)
				if success then
					Logger.info(TAG, "Purchase OK", item.id, item.name, tostring(msg))
					ShopGui.refreshItems()
				else
					Logger.warn(TAG, "Purchase failed", item.id, tostring(msg))
				end
			end)
		end
		end
	end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function ShopGui.init(data)
	currentData = data
end

function ShopGui.toggle()
	ensureBuilt()

	isOpen = not isOpen
	guiRefs.overlay.Visible = isOpen
	guiRefs.panel.Visible   = isOpen

	if isOpen then
		ShopGui.refreshItems()
		-- Animate in
		guiRefs.panel.Position = UDim2.new(0.5, -270, 0.5, -240)
		TweenService:Create(guiRefs.panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, -270, 0.5, -220) }):Play()
	end
end

function ShopGui.onDataUpdated(data)
	currentData = data
	if isOpen and guiRefs and guiRefs.overlay then
		ShopGui.refreshItems()
	end
end

return ShopGui

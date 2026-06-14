-- NotificationGui.luau
-- Toast-style notifications and achievement popups

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local C = require(game:GetService("ReplicatedStorage").Shared.Constants).UI

local NotificationGui = {}

local notifQueue: { any } = {}
local isShowing = false

local COLOR_MAP = {
	gold   = Color3.fromRGB(255, 200, 30),
	green  = Color3.fromRGB(50, 200, 100),
	blue   = Color3.fromRGB(80, 160, 255),
	red    = Color3.fromRGB(220, 50, 50),
	purple = Color3.fromRGB(180, 50, 220),
	default = Color3.fromRGB(80, 160, 255),
}

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function showNext()
	if isShowing or #notifQueue == 0 then return end
	isShowing = true

	local notif = table.remove(notifQueue, 1)
	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")

	local accentColor = COLOR_MAP[notif.color] or COLOR_MAP.default

	local frame = Instance.new("Frame")
	frame.Name = "Notification"
	frame.Size = UDim2.new(0, 300, 0, 70)
	frame.Position = UDim2.new(0.5, -150, 0, -80)
	frame.BackgroundColor3 = C.Surface
	frame.ZIndex = 50
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	corner(frame, 12)

	-- Accent bar
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 4, 1, -16)
	accentBar.Position = UDim2.new(0, 6, 0, 8)
	accentBar.BackgroundColor3 = accentColor
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 51
	accentBar.Parent = frame
	corner(accentBar, 2)

	-- Icon
	local icon = Instance.new("TextLabel")
	icon.Text = notif.icon or "ℹ️"
	icon.Size = UDim2.new(0, 30, 0, 30)
	icon.Position = UDim2.new(0, 18, 0.5, -15)
	icon.BackgroundTransparency = 1
	icon.TextSize = 20
	icon.ZIndex = 51
	icon.Font = Enum.Font.Gotham
	icon.Parent = frame

	-- Title
	local title = Instance.new("TextLabel")
	title.Text = notif.title or "Notice"
	title.Size = UDim2.new(1, -60, 0, 24)
	title.Position = UDim2.new(0, 54, 0, 10)
	title.BackgroundTransparency = 1
	title.TextColor3 = C.TextPrimary
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 51
	title.Parent = frame

	-- Message
	local msg = Instance.new("TextLabel")
	msg.Text = notif.text or ""
	msg.Size = UDim2.new(1, -60, 0, 22)
	msg.Position = UDim2.new(0, 54, 0, 36)
	msg.BackgroundTransparency = 1
	msg.TextColor3 = C.TextMuted
	msg.Font = Enum.Font.Gotham
	msg.TextSize = 12
	msg.TextXAlignment = Enum.TextXAlignment.Left
	msg.TextWrapped = true
	msg.ZIndex = 51
	msg.Parent = frame

	-- Slide in
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -150, 0, 20) }):Play()

	-- Wait then slide out
	task.delay(3, function()
		TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, -150, 0, -80) }):Play()
		task.wait(0.35)
		frame:Destroy()
		isShowing = false
		showNext()
	end)
end

function NotificationGui.show(data)
	if data.action == "promptUnlock" then
		NotificationGui.showUnlockPrompt(data)
		return
	end
	if data.action == "promptBonusUnlock" then
		NotificationGui.showBonusPrompt(data)
		return
	end
	table.insert(notifQueue, data)
	showNext()
end

function NotificationGui.showUnlockPrompt(data)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local MarketplaceService = game:GetService("MarketplaceService")
	local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")

	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")

	-- Remove existing popup
	local old = screenGui:FindFirstChild("UnlockPopup")
	if old then old:Destroy() end

	local worldId = data.worldId or 2
	local worldName = data.worldName or "World"
	local coinCost = data.coinCost or 400

	local overlay = Instance.new("Frame")
	overlay.Name = "UnlockPopup"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.ZIndex = 60
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 340, 0, 260)
	panel.Position = UDim2.new(0.5, -170, 0.5, -130)
	panel.BackgroundColor3 = C.Background
	panel.ZIndex = 61
	panel.BorderSizePixel = 0
	panel.Parent = overlay
	corner(panel, 16)

	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Gold
	stroke.Thickness = 2
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Text = "🔒 " .. worldName
	title.Size = UDim2.new(1, -20, 0, 40)
	title.Position = UDim2.new(0, 10, 0, 12)
	title.BackgroundTransparency = 1
	title.TextColor3 = C.Gold
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.ZIndex = 62
	title.Parent = panel

	local desc = Instance.new("TextLabel")
	desc.Text = data.text or "Unlock this world to play it now."
	desc.Size = UDim2.new(1, -20, 0, 50)
	desc.Position = UDim2.new(0, 10, 0, 52)
	desc.BackgroundTransparency = 1
	desc.TextColor3 = C.TextMuted
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 13
	desc.TextWrapped = true
	desc.ZIndex = 62
	desc.Parent = panel

	local function makeBtn(text, color, yPos)
		local btn = Instance.new("TextButton")
		btn.Text = text
		btn.Size = UDim2.new(1, -40, 0, 44)
		btn.Position = UDim2.new(0, 20, 0, yPos)
		btn.BackgroundColor3 = color
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 15
		btn.BorderSizePixel = 0
		btn.ZIndex = 62
		btn.Parent = panel
		corner(btn, 10)
		return btn
	end

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Text = ""
	statusLabel.Size = UDim2.new(1, -20, 0, 24)
	statusLabel.Position = UDim2.new(0, 10, 0, 108)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = C.Danger
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.ZIndex = 62
	statusLabel.Parent = panel

	-- Robux button (in Studio: free test unlock — real Robux needs a Creator Hub product ID)
	local isStudio = RunService:IsStudio()
	local robuxBtn = makeBtn(
		isStudio and "🔧 Unlock (Studio Test)" or "💎 Unlock with Robux",
		Color3.fromRGB(0, 162, 255), 138)
	robuxBtn.MouseButton1Click:Connect(function()
		statusLabel.Text = "Opening purchase..."
		local prep = Remotes:WaitForChild(RemoteDefs.PrepareWorldUnlock):InvokeServer(worldId)
		if prep and prep.ok then
			if prep.isStudio or isStudio then
				statusLabel.Text = "Unlocking (Studio)..."
				statusLabel.TextColor3 = C.TextMuted
				local ok, msg = Remotes:WaitForChild(RemoteDefs.UnlockWorldStudioTest):InvokeServer(worldId)
				if ok then
					overlay:Destroy()
				else
					statusLabel.Text = tostring(msg)
					statusLabel.TextColor3 = C.Danger
				end
				return
			end

			local productId = prep.productId
			if not productId or productId < 1 then
				statusLabel.Text = "Product ID not configured — use coins or set UnlockWorld in Constants"
				statusLabel.TextColor3 = C.Danger
				return
			end

			local ok, err = pcall(function()
				MarketplaceService:PromptProductPurchase(localPlayer, productId)
			end)
			if not ok then
				statusLabel.Text = "Purchase failed: " .. tostring(err)
				statusLabel.TextColor3 = C.Danger
			else
				statusLabel.Text = "Complete the purchase in the popup."
				statusLabel.TextColor3 = C.TextMuted
			end
		else
			statusLabel.Text = prep and prep.reason or "Could not prepare purchase"
			statusLabel.TextColor3 = C.Danger
		end
	end)

	-- Coins button
	local coinBtn = makeBtn("🪙 Unlock for " .. coinCost .. " Coins", Color3.fromRGB(50, 160, 80), 192)
	if not data.canAffordCoins then
		coinBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	end
	coinBtn.MouseButton1Click:Connect(function()
		local ok, msg = Remotes:WaitForChild(RemoteDefs.UnlockWorldWithCoins):InvokeServer(worldId)
		if ok then
			overlay:Destroy()
		else
			statusLabel.Text = tostring(msg)
			statusLabel.TextColor3 = C.Danger
		end
	end)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "Cancel"
	closeBtn.Size = UDim2.new(0, 80, 0, 28)
	closeBtn.Position = UDim2.new(0.5, -40, 1, -36)
	closeBtn.BackgroundTransparency = 1
	closeBtn.TextColor3 = C.TextMuted
	closeBtn.Font = Enum.Font.Gotham
	closeBtn.TextSize = 13
	closeBtn.ZIndex = 62
	closeBtn.Parent = panel
	closeBtn.MouseButton1Click:Connect(function() overlay:Destroy() end)

	-- Listen for purchase result
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= localPlayer.UserId then return end
		if purchased and (productId == data.productId) then
			task.wait(0.5)
			if overlay.Parent then overlay:Destroy() end
		elseif not purchased then
			statusLabel.Text = "Purchase cancelled."
		end
	end)
end

function NotificationGui.showBonusPrompt(data)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")

	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")
	local old = screenGui:FindFirstChild("BonusUnlockPopup")
	if old then old:Destroy() end

	local bonusId = data.bonusId or "circle"
	local bonusName = data.bonusName or "Bonus"
	local runCost = data.runCost or 30
	local unlockCost = data.unlockCost or 300

	local overlay = Instance.new("Frame")
	overlay.Name = "BonusUnlockPopup"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.ZIndex = 60
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 340, 0, 280)
	panel.Position = UDim2.new(0.5, -170, 0.5, -140)
	panel.BackgroundColor3 = C.Background
	panel.ZIndex = 61
	panel.BorderSizePixel = 0
	panel.Parent = overlay
	corner(panel, 16)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(160, 100, 220)
	stroke.Thickness = 2
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Text = (data.icon or "⭐") .. " " .. bonusName
	title.Size = UDim2.new(1, -20, 0, 40)
	title.Position = UDim2.new(0, 10, 0, 12)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(220, 180, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.ZIndex = 62
	title.Parent = panel

	local desc = Instance.new("TextLabel")
	desc.Text = data.text or "Платный бонусный уровень."
	desc.Size = UDim2.new(1, -20, 0, 44)
	desc.Position = UDim2.new(0, 10, 0, 52)
	desc.BackgroundTransparency = 1
	desc.TextColor3 = C.TextMuted
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 13
	desc.TextWrapped = true
	desc.ZIndex = 62
	desc.Parent = panel

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Text = ""
	statusLabel.Size = UDim2.new(1, -20, 0, 24)
	statusLabel.Position = UDim2.new(0, 10, 0, 98)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = C.Danger
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.ZIndex = 62
	statusLabel.Parent = panel

	local function makeBtn(text, color, yPos)
		local btn = Instance.new("TextButton")
		btn.Text = text
		btn.Size = UDim2.new(1, -40, 0, 44)
		btn.Position = UDim2.new(0, 20, 0, yPos)
		btn.BackgroundColor3 = color
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 15
		btn.BorderSizePixel = 0
		btn.ZIndex = 62
		btn.Parent = panel
		corner(btn, 10)
		return btn
	end

	local playBtn = makeBtn("▶ Играть (" .. runCost .. " 🪙)", C.Accent, 128)
	if not data.canAffordRun then
		playBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	end
	playBtn.MouseButton1Click:Connect(function()
		local ok, msg = Remotes:WaitForChild(RemoteDefs.StartBonusLevel):InvokeServer(bonusId)
		if ok then
			overlay:Destroy()
		else
			statusLabel.Text = tostring(msg)
		end
	end)

	local unlockBtn = makeBtn("🔓 Разблокировать (" .. unlockCost .. " 🪙)", Color3.fromRGB(50, 160, 80), 182)
	if not data.canAffordUnlock then
		unlockBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	end
	unlockBtn.MouseButton1Click:Connect(function()
		local ok, msg = Remotes:WaitForChild(RemoteDefs.UnlockBonusLevel):InvokeServer(bonusId)
		if ok then
			overlay:Destroy()
		else
			if RunService:IsStudio() then
				local studioOk = Remotes:WaitForChild(RemoteDefs.UnlockBonusStudioTest):InvokeServer(bonusId)
				if studioOk then
					overlay:Destroy()
					return
				end
			end
			statusLabel.Text = tostring(msg)
		end
	end)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "Отмена"
	closeBtn.Size = UDim2.new(0, 80, 0, 28)
	closeBtn.Position = UDim2.new(0.5, -40, 1, -36)
	closeBtn.BackgroundTransparency = 1
	closeBtn.TextColor3 = C.TextMuted
	closeBtn.Font = Enum.Font.Gotham
	closeBtn.TextSize = 13
	closeBtn.ZIndex = 62
	closeBtn.Parent = panel
	closeBtn.MouseButton1Click:Connect(function() overlay:Destroy() end)
end

function NotificationGui.showAchievement(achievement)
	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")

	local frame = Instance.new("Frame")
	frame.Name = "AchievementPopup"
	frame.Size = UDim2.new(0, 340, 0, 90)
	frame.Position = UDim2.new(0.5, -170, 1, -110)
	frame.BackgroundColor3 = Color3.fromRGB(30, 25, 50)
	frame.ZIndex = 50
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	corner(frame, 14)

	-- Gold border
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Gold
	stroke.Thickness = 2
	stroke.Parent = frame

	local trophy = Instance.new("TextLabel")
	trophy.Text = "🏆"
	trophy.Size = UDim2.new(0, 50, 1, 0)
	trophy.Position = UDim2.new(0, 10, 0, 0)
	trophy.BackgroundTransparency = 1
	trophy.TextSize = 32
	trophy.ZIndex = 51
	trophy.Font = Enum.Font.Gotham
	trophy.Parent = frame

	local unlocked = Instance.new("TextLabel")
	unlocked.Text = "Achievement Unlocked!"
	unlocked.Size = UDim2.new(1, -70, 0, 24)
	unlocked.Position = UDim2.new(0, 66, 0, 12)
	unlocked.BackgroundTransparency = 1
	unlocked.TextColor3 = C.Gold
	unlocked.Font = Enum.Font.GothamBold
	unlocked.TextSize = 14
	unlocked.TextXAlignment = Enum.TextXAlignment.Left
	unlocked.ZIndex = 51
	unlocked.Parent = frame

	local achName = Instance.new("TextLabel")
	achName.Text = achievement.name
	achName.Size = UDim2.new(1, -70, 0, 22)
	achName.Position = UDim2.new(0, 66, 0, 36)
	achName.BackgroundTransparency = 1
	achName.TextColor3 = C.TextPrimary
	achName.Font = Enum.Font.GothamBold
	achName.TextSize = 16
	achName.TextXAlignment = Enum.TextXAlignment.Left
	achName.ZIndex = 51
	achName.Parent = frame

	local achDesc = Instance.new("TextLabel")
	achDesc.Text = achievement.desc
	achDesc.Size = UDim2.new(1, -70, 0, 18)
	achDesc.Position = UDim2.new(0, 66, 0, 60)
	achDesc.BackgroundTransparency = 1
	achDesc.TextColor3 = C.TextMuted
	achDesc.Font = Enum.Font.Gotham
	achDesc.TextSize = 12
	achDesc.TextXAlignment = Enum.TextXAlignment.Left
	achDesc.ZIndex = 51
	achDesc.Parent = frame

	-- Slide up from bottom
	TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -170, 1, -110) }):Play()

	task.delay(4, function()
		TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad),
			{ Position = UDim2.new(0.5, -170, 1, 20) }):Play()
		task.wait(0.35)
		frame:Destroy()
	end)
end

function NotificationGui.init()
	-- nothing, all lazy
end

return NotificationGui

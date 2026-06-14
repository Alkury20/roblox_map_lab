-- AdminGui.luau
-- Admin panel: fly toggle + speed slider (admins only)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)

local localPlayer = Players.LocalPlayer
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local C           = Constants.UI

local AdminGui = {}

local isAdmin = false
local isOpen = false
local panel: Frame?
local flyEnabled = false
local speedSlider: TextBox?
local statusLabel: TextLabel?

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function makeBtn(parent, text, color, size, pos)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.BorderSizePixel = 0
	b.Parent = parent
	corner(b, 8)
	return b
end

local function setStatus(text, isError)
	if statusLabel then
		statusLabel.Text = text
		statusLabel.TextColor3 = isError and C.Danger or C.Success
	end
end

local function buildPanel()
	local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui")

	panel = Instance.new("Frame")
	panel.Name = "AdminPanel"
	panel.Size = UDim2.new(0, 300, 0, 280)
	panel.Position = UDim2.new(0, 16, 0.5, -140)
	panel.BackgroundColor3 = C.Background
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 70
	panel.Parent = screenGui
	corner(panel, 14)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 80, 80)
	stroke.Thickness = 2
	stroke.Parent = panel

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3 = Color3.fromRGB(80, 20, 30)
	titleBar.BorderSizePixel = 0
	titleBar.ZIndex = 71
	titleBar.Parent = panel
	corner(titleBar, 14)

	local title = Instance.new("TextLabel")
	title.Text = "🛡️ Admin Panel"
	title.Size = UDim2.new(1, -44, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 200, 200)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 72
	title.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "✕"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -38, 0.5, -16)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 72
	closeBtn.Parent = titleBar
	corner(closeBtn, 6)
	closeBtn.MouseButton1Click:Connect(function() AdminGui.toggle() end)

	-- Fly section
	local flyLabel = Instance.new("TextLabel")
	flyLabel.Text = "✈️ Flight"
	flyLabel.Size = UDim2.new(1, -24, 0, 22)
	flyLabel.Position = UDim2.new(0, 12, 0, 54)
	flyLabel.BackgroundTransparency = 1
	flyLabel.TextColor3 = C.TextPrimary
	flyLabel.Font = Enum.Font.GothamBold
	flyLabel.TextSize = 14
	flyLabel.TextXAlignment = Enum.TextXAlignment.Left
	flyLabel.ZIndex = 71
	flyLabel.Parent = panel

	local flyBtn = makeBtn(panel, "Enable Fly", Color3.fromRGB(50, 120, 200),
		UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 0, 80))
	flyBtn.ZIndex = 71

	flyBtn.MouseButton1Click:Connect(function()
		local ok, enabled = Remotes:WaitForChild(RemoteDefs.AdminToggleFly):InvokeServer()
		if ok then
			flyEnabled = enabled
			flyBtn.Text = enabled and "Disable Fly" or "Enable Fly"
			flyBtn.BackgroundColor3 = enabled and Color3.fromRGB(200, 80, 40) or Color3.fromRGB(50, 120, 200)
			local AdminController = require(script.Parent.Parent.Controllers.AdminController)
			AdminController.setFlyEnabled(enabled)
			setStatus(enabled and "Fly ON (WASD + Space/Ctrl)" or "Fly OFF", false)
		else
			setStatus("Fly toggle denied", true)
		end
	end)

	local flyHint = Instance.new("TextLabel")
	flyHint.Text = "WASD — move | Space — up | Ctrl — down"
	flyHint.Size = UDim2.new(1, -24, 0, 18)
	flyHint.Position = UDim2.new(0, 12, 0, 124)
	flyHint.BackgroundTransparency = 1
	flyHint.TextColor3 = C.TextMuted
	flyHint.Font = Enum.Font.Gotham
	flyHint.TextSize = 11
	flyHint.ZIndex = 71
	flyHint.Parent = panel

	-- Speed section
	local speedLabel = Instance.new("TextLabel")
	speedLabel.Text = "⚡ Walk Speed"
	speedLabel.Size = UDim2.new(1, -24, 0, 22)
	speedLabel.Position = UDim2.new(0, 12, 0, 152)
	speedLabel.BackgroundTransparency = 1
	speedLabel.TextColor3 = C.TextPrimary
	speedLabel.Font = Enum.Font.GothamBold
	speedLabel.TextSize = 14
	speedLabel.TextXAlignment = Enum.TextXAlignment.Left
	speedLabel.ZIndex = 71
	speedLabel.Parent = panel

	speedSlider = Instance.new("TextBox")
	speedSlider.Name = "SpeedInput"
	speedSlider.Text = tostring(Constants.PLAYER_SPEED_DEFAULT)
	speedSlider.Size = UDim2.new(0, 80, 0, 36)
	speedSlider.Position = UDim2.new(0, 12, 0, 178)
	speedSlider.BackgroundColor3 = C.Surface
	speedSlider.TextColor3 = C.TextPrimary
	speedSlider.Font = Enum.Font.GothamBold
	speedSlider.TextSize = 16
	speedSlider.ClearTextOnFocus = false
	speedSlider.ZIndex = 71
	speedSlider.Parent = panel
	corner(speedSlider, 8)

	local applyBtn = makeBtn(panel, "Apply", C.Accent,
		UDim2.new(0, 80, 0, 36), UDim2.new(0, 100, 0, 178))
	applyBtn.ZIndex = 71

	local resetBtn = makeBtn(panel, "Reset", Color3.fromRGB(80, 80, 100),
		UDim2.new(0, 80, 0, 36), UDim2.new(0, 188, 0, 178))
	resetBtn.ZIndex = 71

	local function applySpeed(speed)
		local ok, result = Remotes:WaitForChild(RemoteDefs.AdminSetSpeed):InvokeServer(speed)
		if ok then
			speedSlider.Text = tostring(result)
			setStatus("Speed set to " .. result, false)
		else
			setStatus(tostring(result), true)
		end
	end

	applyBtn.MouseButton1Click:Connect(function()
		local n = tonumber(speedSlider.Text)
		if not n then
			setStatus("Enter a number", true)
			return
		end
		applySpeed(n)
	end)

	resetBtn.MouseButton1Click:Connect(function()
		applySpeed(Constants.PLAYER_SPEED_DEFAULT)
	end)

	-- Quick presets
	local presets = { 16, 32, 50, 100 }
	for i, spd in ipairs(presets) do
		local pBtn = makeBtn(panel, tostring(spd),
			Color3.fromRGB(45, 55, 80),
			UDim2.new(0, 60, 0, 28),
			UDim2.new(0, 12 + (i - 1) * 68, 0, 222))
		pBtn.TextSize = 12
		pBtn.ZIndex = 71
		pBtn.MouseButton1Click:Connect(function()
			speedSlider.Text = tostring(spd)
			applySpeed(spd)
		end)
	end

	statusLabel = Instance.new("TextLabel")
	statusLabel.Text = "Ready"
	statusLabel.Size = UDim2.new(1, -24, 0, 20)
	statusLabel.Position = UDim2.new(0, 12, 1, -28)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = C.TextMuted
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 11
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.ZIndex = 71
	statusLabel.Parent = panel
end

function AdminGui.init()
	local ok, result = pcall(function()
		return Remotes:WaitForChild(RemoteDefs.CheckAdmin):InvokeServer()
	end)

	isAdmin = ok and result == true
	if not isAdmin then return end

	buildPanel()

	-- Visible admin button in the right HUD panel (not only F9)
	task.defer(function()
		local screenGui = localPlayer.PlayerGui:WaitForChild("MazeEscapeGui", 10)
		if not screenGui then return end
		local rightPanel = screenGui:FindFirstChild("RightPanel")
		if not rightPanel then return end

		local adminBtn = Instance.new("TextButton")
		adminBtn.Name = "AdminBtn"
		adminBtn.Text = "🛡️"
		adminBtn.Size = UDim2.new(0, 44, 0, 44)
		adminBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 60)
		adminBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		adminBtn.Font = Enum.Font.Gotham
		adminBtn.TextSize = 22
		adminBtn.BorderSizePixel = 0
		adminBtn.LayoutOrder = 99
		adminBtn.Parent = rightPanel
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = adminBtn
		adminBtn.MouseButton1Click:Connect(function()
			AdminGui.toggle()
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.F9 then
			AdminGui.toggle()
		end
	end)
end

function AdminGui.toggle()
	if not isAdmin or not panel then return end
	isOpen = not isOpen
	panel.Visible = isOpen
end

return AdminGui

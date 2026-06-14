-- InputController.luau
-- Mobile support (on-screen buttons), keyboard shortcuts

local Players              = game:GetService("Players")
local UserInputService     = game:GetService("UserInputService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local StarterGui           = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer

local InputController = {}

-- Disable default Roblox leaderboard (we have our own)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

function InputController.init()
	-- Keyboard hint shortcut (H)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.H then
			-- Request path hint
			local MazeController = require(script.Parent.MazeController)
			MazeController.requestHint()
		end
	end)

	-- Mobile: hint button is created in MainGui
	print("[InputController] Initialized.")
end

return InputController

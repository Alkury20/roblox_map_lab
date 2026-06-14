-- AdminController.luau
-- Client-side admin fly (enabled only after server grants permission)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local localPlayer = Players.LocalPlayer

local AdminController = {}

local flying = false
local flyConn: RBXScriptConnection?
local bodyVelocity: BodyVelocity?
local bodyGyro: BodyGyro?
local flySpeed = Constants.ADMIN_FLY_SPEED

local function getCharacter()
	return localPlayer.Character
end

local function cleanupFlyBodies()
	if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
	if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
	if flyConn then flyConn:Disconnect() flyConn = nil end
end

local function stopFly()
	flying = false
	cleanupFlyBodies()

	local char = getCharacter()
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
			local saved = localPlayer:GetAttribute("AdminSpeed") or Constants.PLAYER_SPEED_DEFAULT
			hum.WalkSpeed = saved
		end
	end
end

local function startFly()
	local char = getCharacter()
	if not char then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	cleanupFlyBodies()
	flying = true

	hum.PlatformStand = true
	hum.WalkSpeed = 0

	bodyGyro = Instance.new("BodyGyro")
	bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	bodyGyro.P = 9000
	bodyGyro.Parent = hrp

	bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bodyVelocity.Velocity = Vector3.zero
	bodyVelocity.Parent = hrp

	flyConn = RunService.RenderStepped:Connect(function()
		if not flying or not hrp.Parent then
			stopFly()
			return
		end

		local cam = workspace.CurrentCamera
		if not cam then return end

		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end

		if move.Magnitude > 0 then
			move = move.Unit * flySpeed
		end

		bodyVelocity.Velocity = move
		bodyGyro.CFrame = cam.CFrame
	end)
end

function AdminController.setFlyEnabled(enabled: boolean)
	if enabled then
		startFly()
	else
		stopFly()
	end
end

function AdminController.setFlySpeed(speed: number)
	flySpeed = math.clamp(speed, 16, Constants.ADMIN_MAX_SPEED)
end

function AdminController.init()
	local function onFlyAttributeChanged()
		local shouldFly = localPlayer:GetAttribute("AdminFly") == true
		if shouldFly and not flying then
			startFly()
		elseif not shouldFly and flying then
			stopFly()
		end
	end

	localPlayer:GetAttributeChangedSignal("AdminFly"):Connect(onFlyAttributeChanged)

	localPlayer.CharacterAdded:Connect(function()
		task.wait(0.3)
		onFlyAttributeChanged()
	end)

	if localPlayer:GetAttribute("AdminFly") then
		onFlyAttributeChanged()
	end
end

return AdminController

-- AdminService.luau
-- Server-side admin validation: fly permission + speed changes

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)
local Logger     = require(ReplicatedStorage.Shared.Logger)

local TAG = "AdminService"
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AdminService = {}

local adminSpeed: { [number]: number } = {}
local adminFlying: { [number]: boolean } = {}
local adminUserIds: { [number]: boolean } = {}

local function registerAdminId(userId: number, source: string?)
	if userId and userId > 0 then
		adminUserIds[userId] = true
		if source then
			Logger.info(TAG, "Admin registered", "userId=" .. userId, "via=" .. source)
		end
	end
end

local function loadAdminList()
	table.clear(adminUserIds)

	for _, userId in ipairs(Constants.ADMIN_USER_IDS or {}) do
		registerAdminId(userId, "ADMIN_USER_IDS")
	end

	local names = Constants.ADMIN_USERNAMES
	if names and #names > 0 then
		for _, username in ipairs(names) do
			local ok, userId = pcall(function()
				return Players:GetUserIdFromNameAsync(username)
			end)
			if ok and typeof(userId) == "number" and userId > 0 then
				registerAdminId(userId, "username:" .. username)
			else
				Logger.warn(TAG, "Admin username not found", username)
			end
		end
	end

	local count = 0
	for _ in pairs(adminUserIds) do
		count += 1
	end
	Logger.info(TAG, "Admin list loaded", "entries=" .. count)
end

local function isAdmin(player: Player): boolean
	if not player then return false end
	if player.UserId == game.CreatorId then return true end
	return adminUserIds[player.UserId] == true
end

local function applySpeed(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local speed = adminSpeed[player.UserId] or Constants.PLAYER_SPEED_DEFAULT

	-- Don't override speed while flying (fly uses its own velocity)
	if not adminFlying[player.UserId] then
		hum.WalkSpeed = speed
	end
end

local function syncAttributes(player: Player)
	player:SetAttribute("IsAdmin", isAdmin(player))
	player:SetAttribute("AdminFly", adminFlying[player.UserId] == true)
	player:SetAttribute("AdminSpeed", adminSpeed[player.UserId] or Constants.PLAYER_SPEED_DEFAULT)
end

function AdminService.init()
	loadAdminList()

	Remotes:WaitForChild(RemoteDefs.CheckAdmin).OnServerInvoke = function(player)		local admin = isAdmin(player)
		if admin then
			syncAttributes(player)
			Logger.info(TAG, "Admin panel access", player.Name)
		end
		return admin
	end

	Remotes:WaitForChild(RemoteDefs.AdminSetSpeed).OnServerInvoke = function(player, speed: number)
		if not isAdmin(player) then
			Logger.warn(TAG, "Non-admin tried to set speed", player.Name)
			return false, "Not admin"
		end

		speed = math.clamp(math.floor(speed), Constants.ADMIN_MIN_SPEED, Constants.ADMIN_MAX_SPEED)
		adminSpeed[player.UserId] = speed
		syncAttributes(player)
		applySpeed(player)

		Logger.info(TAG, "Speed set", player.Name, "speed=" .. speed)
		return true, speed
	end

	Remotes:WaitForChild(RemoteDefs.AdminToggleFly).OnServerInvoke = function(player)
		if not isAdmin(player) then
			Logger.warn(TAG, "Non-admin tried to toggle fly", player.Name)
			return false, false
		end

		adminFlying[player.UserId] = not adminFlying[player.UserId]
		syncAttributes(player)

		if adminFlying[player.UserId] then
			-- Stop walk speed while flying
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.WalkSpeed = 0 end
		else
			applySpeed(player)
		end

		Logger.info(TAG, "Fly toggled", player.Name, "enabled=" .. tostring(adminFlying[player.UserId]))
		return true, adminFlying[player.UserId]
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			syncAttributes(player)
		end)

		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			if isAdmin(player) then
				applySpeed(player)
				syncAttributes(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		adminSpeed[player.UserId] = nil
		adminFlying[player.UserId] = nil
	end)

	for _, player in Players:GetPlayers() do
		syncAttributes(player)
	end

	Logger.info(TAG, "Initialized")
end

return AdminService

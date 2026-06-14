-- ShopService.luau
-- Handles coin-based purchases and item equipping

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants         = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs        = require(ReplicatedStorage.Shared.RemoteDefinitions)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ShopService = {}
local PlayerDataService

local function notify(player, title, text, icon, color)
	Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
		title = title, text = text, icon = icon, color = color,
	})
end

function ShopService.init()
	PlayerDataService = require(script.Parent.PlayerDataService)

	-- PurchaseItem
	Remotes:WaitForChild(RemoteDefs.PurchaseItem).OnServerInvoke = function(player, itemId: string)
		local data = PlayerDataService.get(player)
		if not data then return false, "No data" end

		-- Find item config
		local itemConfig
		for _, item in ipairs(Constants.SHOP_ITEMS) do
			if item.id == itemId then
				itemConfig = item
				break
			end
		end

		if not itemConfig then return false, "Item not found" end

		-- Gamepass items
		if itemConfig.gamepass then
			if data.Gamepasses[itemConfig.gamepass] then
				data.OwnedItems[itemId] = true
				Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
				return true, "Unlocked via Gamepass"
			else
				return false, "Requires " .. itemConfig.gamepass .. " Gamepass"
			end
		end

		-- Already owned
		if data.OwnedItems[itemId] then
			return false, "Already owned"
		end

		-- Check coins
		if (data.Coins or 0) < itemConfig.price then
			return false, "Not enough coins"
		end

		-- Deduct and grant
		data.Coins -= itemConfig.price
		data.OwnedItems[itemId] = true

		notify(player, "Purchased!", itemConfig.name .. " added to your collection.", "🛍️", "green")
		Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
		return true, "Success"
	end

	-- EquipItem
	Remotes:WaitForChild(RemoteDefs.EquipItem).OnServerInvoke = function(player, itemId: string, slot: string)
		local data = PlayerDataService.get(player)
		if not data then return false end

		-- Validate ownership
		if itemId ~= "none" and not data.OwnedItems[itemId] then
			-- Check gamepass items
			local itemConfig
			for _, item in ipairs(Constants.SHOP_ITEMS) do
				if item.id == itemId then itemConfig = item break end
			end
			if itemConfig and itemConfig.gamepass then
				if not data.Gamepasses[itemConfig.gamepass] then
					return false
				end
			else
				return false
			end
		end

		-- Valid slots
		local validSlots = { trail = true, aura = true, effect = true, pet = true }
		if not validSlots[slot:lower()] then return false end

		local slotKey = slot:sub(1,1):upper() .. slot:sub(2):lower()
		if data.EquippedItems[slotKey] ~= nil then
			data.EquippedItems[slotKey] = itemId
		end

		-- Broadcast equip to all clients for visual effect
		Remotes:WaitForChild(RemoteDefs.PlayEffect):FireAllClients({
			type     = "equip",
			userId   = player.UserId,
			itemId   = itemId,
			slot     = slot,
		})

		Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
		return true
	end

	print("[ShopService] Initialized.")
end

return ShopService

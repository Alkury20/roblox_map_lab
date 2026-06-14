-- ShopService.luau
-- Handles coin-based purchases and item equipping

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants  = require(ReplicatedStorage.Shared.Constants)
local RemoteDefs = require(ReplicatedStorage.Shared.RemoteDefinitions)
local Logger     = require(ReplicatedStorage.Shared.Logger)

local TAG = "ShopService"
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ShopService = {}
local PlayerDataService

local function findItem(itemId: string)
	for _, item in ipairs(Constants.SHOP_ITEMS) do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

local function notify(player, title, text, icon, color)
	Remotes:WaitForChild(RemoteDefs.ShowNotification):FireClient(player, {
		title = title, text = text, icon = icon, color = color,
	})
end

local VALID_SLOTS = { trail = true, aura = true, effect = true, pet = true }

local function slotKeyFromCategory(category: string): string?
	local lower = category:lower()
	if not VALID_SLOTS[lower] then
		return nil
	end
	return lower:sub(1, 1):upper() .. lower:sub(2)
end

local function applyEquip(player: Player, data, itemId: string, itemConfig, slotLower: string): (boolean, string?)
	local slotKey = slotKeyFromCategory(slotLower)
	if not slotKey or data.EquippedItems[slotKey] == nil then
		return false, "Invalid slot"
	end

	local previous = data.EquippedItems[slotKey]
	data.EquippedItems[slotKey] = itemId

	Logger.info(TAG, "Equip success",
		player.Name,
		"slot=" .. slotKey,
		"item=" .. itemId,
		itemConfig and itemConfig.name or itemId,
		"was=" .. tostring(previous))

	Remotes:WaitForChild(RemoteDefs.PlayEffect):FireAllClients({
		type   = "equip",
		userId = player.UserId,
		itemId = itemId,
		slot   = slotLower,
	})

	return true, slotKey
end

function ShopService.init()
	PlayerDataService = require(script.Parent.PlayerDataService)

	Remotes:WaitForChild(RemoteDefs.PurchaseItem).OnServerInvoke = function(player, itemId: string)
		local data = PlayerDataService.get(player)
		if not data then
			Logger.warn(TAG, "Purchase failed — no data", player.Name, itemId)
			return false, "No data"
		end

		local itemConfig = findItem(itemId)
		if not itemConfig then
			Logger.warn(TAG, "Purchase failed — item not found", player.Name, itemId)
			return false, "Item not found"
		end

		if itemConfig.gamepass then
			if data.Gamepasses[itemConfig.gamepass] then
				data.OwnedItems[itemId] = true
				Logger.info(TAG, "Purchase via gamepass", player.Name, itemId, itemConfig.name)
				Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
				return true, "Unlocked via Gamepass"
			end
			Logger.info(TAG, "Purchase denied — needs gamepass", player.Name, itemId, itemConfig.gamepass)
			return false, "Requires " .. itemConfig.gamepass .. " Gamepass"
		end

		if data.OwnedItems[itemId] then
			Logger.info(TAG, "Purchase skipped — already owned", player.Name, itemId)
			return false, "Already owned"
		end

		if (data.Coins or 0) < itemConfig.price then
			Logger.info(TAG, "Purchase denied — not enough coins",
				player.Name, itemId, "need=" .. itemConfig.price, "have=" .. (data.Coins or 0))
			return false, "Not enough coins"
		end

		data.Coins -= itemConfig.price
		data.OwnedItems[itemId] = true

		Logger.info(TAG, "Purchase success",
			player.Name, itemId, itemConfig.name,
			"price=" .. itemConfig.price, "coinsLeft=" .. data.Coins)

		local autoEquipped = false
		local slotKey = slotKeyFromCategory(itemConfig.category or "")
		if slotKey and data.EquippedItems[slotKey] ~= nil then
			local ok = applyEquip(player, data, itemId, itemConfig, itemConfig.category:lower())
			autoEquipped = ok
			if ok then
				Logger.info(TAG, "Auto-equipped after purchase", player.Name, slotKey, itemId)
			end
		end

		if autoEquipped then
			notify(player, "Purchased & Equipped!", itemConfig.name .. " is now active.", "✨", "green")
		else
			notify(player, "Purchased!", itemConfig.name .. " added to your collection.", "🛍️", "green")
		end

		Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
		return true, autoEquipped and "Purchased and equipped" or "Success"
	end

	Remotes:WaitForChild(RemoteDefs.EquipItem).OnServerInvoke = function(player, itemId: string, slot: string)
		local data = PlayerDataService.get(player)
		if not data then
			Logger.warn(TAG, "Equip failed — no data", player.Name, itemId, slot)
			return false, "No data"
		end

		local itemConfig = findItem(itemId)
		local slotLower = slot:lower()

		if itemId ~= "none" and not data.OwnedItems[itemId] then
			if itemConfig and itemConfig.gamepass then
				if not data.Gamepasses[itemConfig.gamepass] then
					Logger.warn(TAG, "Equip denied — gamepass required",
						player.Name, itemId, itemConfig.gamepass)
					return false, "Requires gamepass"
				end
			else
				Logger.warn(TAG, "Equip denied — not owned", player.Name, itemId, slotLower)
				return false, "Not owned"
			end
		end

		local validSlots = VALID_SLOTS
		if not validSlots[slotLower] then
			Logger.warn(TAG, "Equip denied — invalid slot", player.Name, slot)
			return false, "Invalid slot"
		end

		local slotKey = slotKeyFromCategory(slotLower)
		if not slotKey or data.EquippedItems[slotKey] == nil then
			Logger.warn(TAG, "Equip failed — slot missing in data", player.Name, tostring(slotKey))
			return false, "Invalid slot"
		end

		local ok, result = applyEquip(player, data, itemId, itemConfig, slotLower)
		if not ok then
			return false, result
		end

		local itemName = itemConfig and itemConfig.name or itemId
		notify(player, "Equipped!", itemName .. " (" .. result .. ")", "✨", "blue")

		Remotes:WaitForChild(RemoteDefs.DataUpdated):FireClient(player, data)
		return true, "Equipped"
	end

	Logger.info(TAG, "Initialized")
end

return ShopService

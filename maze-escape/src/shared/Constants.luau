-- Constants.luau
-- Central configuration for MazeEscape

local Constants = {}

-- ─── DataStore ────────────────────────────────────────────────────────────────
Constants.DATA_STORE_NAME = "MazeEscape_v1"
Constants.DATA_SAVE_INTERVAL = 60 -- seconds

-- ─── Player Defaults ──────────────────────────────────────────────────────────
Constants.DEFAULT_DATA = {
	Coins       = 0,
	XP          = 0,
	Level       = 1,
	CurrentWorld = 1,
	CurrentLevel = 1,
	BestTimes   = {},       -- [worldId] = bestSeconds
	CompletedWorlds = {},   -- [worldId] = true
	UnlockedWorlds  = {},   -- [worldId] = true (bought with coins / Robux)
	OwnedItems  = {},       -- itemId = true
	EquippedItems = {
		Trail  = "none",
		Aura   = "none",
		Effect = "none",
		Pet    = "none",
	},
	Achievements = {},
	QuestProgress = {},
	DailyRewardStreak = 0,
	LastDailyReward   = 0,
	WeeklyQuestReset  = 0,
	TotalMazesCompleted = 0,
	SecretRoomsFound    = 0,
	UnlockedBonusLevels = {},   -- [bonusId] = true (permanent unlock)
	BonusCompletions    = {},   -- [bonusId] = count
	Gamepasses = {
		DoubleCoins    = false,
		VIP            = false,
		SpeedBoost     = false,
		NightVision    = false,
		ExtraCheckpoint = false,
		RainbowTrail   = false,
	},
}

-- ─── XP & Levels ─────────────────────────────────────────────────────────────
Constants.XP_PER_LEVEL = 500        -- base XP required
Constants.XP_LEVEL_SCALE = 1.25     -- each level costs 25% more
Constants.XP_MAZE_COMPLETE = 100
Constants.XP_SECRET_FOUND  = 50
Constants.XP_QUEST_COMPLETE = 75
Constants.MAX_LEVEL = 100

-- ─── Coins ────────────────────────────────────────────────────────────────────
Constants.COIN_VALUE     = 1
Constants.COIN_PER_MAZE  = 25       -- bonus for completing maze
Constants.DOUBLE_COIN_MULTIPLIER = 2

-- ─── Worlds ───────────────────────────────────────────────────────────────────
Constants.WORLDS = {
	[1] = {
		id       = 1,
		name     = "Classic Maze",
		icon     = "🏰",
		color    = Color3.fromRGB(180, 140, 100),
		unlockLevel = 1,
		description = "Simple corridors. Learn the basics.",
		mechanics = {},
		mazeSize  = { width = 9, height = 9 },
		useCheckpoints = false,
		theme     = "classic",
		ambientColor = Color3.fromRGB(200, 190, 170),
		fogEnd   = 600,
		bg = {
			skyTop    = Color3.fromRGB(135, 195, 255),
			skyBottom = Color3.fromRGB(225, 235, 250),
			clockTime = 14,
			effect    = "none",
		},
	},
	[2] = {
		id       = 2,
		name     = "Forest Maze",
		icon     = "🌲",
		color    = Color3.fromRGB(34, 100, 34),
		unlockLevel = 3,
		description = "Fog and false paths await you.",
		mechanics = { "fog", "falsePaths" },
		mazeSize  = { width = 11, height = 11 },
		useCheckpoints = false,
		theme     = "forest",
		ambientColor = Color3.fromRGB(50, 80, 40),
		fogEnd   = 55,
		bg = {
			skyTop    = Color3.fromRGB(25, 45, 30),
			skyBottom = Color3.fromRGB(55, 75, 45),
			clockTime = 8,
			effect    = "leaves",
		},
	},
	[3] = {
		id       = 3,
		name     = "Ice Maze",
		icon     = "❄️",
		color    = Color3.fromRGB(100, 140, 170),
		unlockLevel = 6,
		description = "Slippery surfaces challenge every step.",
		mechanics = { "slippery" },
		mazeSize  = { width = 13, height = 13 },
		useCheckpoints = false,
		theme     = "ice",
		ambientColor = Color3.fromRGB(88, 102, 118),
		fogEnd   = 200,
		bg = {
			skyTop    = Color3.fromRGB(72, 88, 108),
			skyBottom = Color3.fromRGB(98, 112, 128),
			clockTime = 10,
			effect    = "snow",
		},
	},
	[4] = {
		id       = 4,
		name     = "Lava Maze",
		icon     = "🌋",
		color    = Color3.fromRGB(220, 60, 20),
		unlockLevel = 10,
		description = "Hot zones hurt over time — watch your step.",
		mechanics = { "lava", "damage" },
		mazeSize  = { width = 15, height = 15 },
		useCheckpoints = true,
		lavaDensity = 0.06,
		theme     = "lava",
		ambientColor = Color3.fromRGB(180, 80, 20),
		fogEnd   = 300,
		bg = {
			skyTop    = Color3.fromRGB(60, 15, 10),
			skyBottom = Color3.fromRGB(160, 40, 10),
			clockTime = 18,
			effect    = "embers",
		},
	},
	[5] = {
		id       = 5,
		name     = "Dark Maze",
		icon     = "🌑",
		color    = Color3.fromRGB(30, 20, 50),
		unlockLevel = 15,
		description = "Almost no light. Find your way in the dark.",
		mechanics = { "darkness" },
		mazeSize  = { width = 17, height = 17 },
		useCheckpoints = false,
		theme     = "dark",
		ambientColor = Color3.fromRGB(10, 5, 20),
		fogEnd   = 60,
		bg = {
			skyTop    = Color3.fromRGB(5, 3, 12),
			skyBottom = Color3.fromRGB(15, 10, 30),
			clockTime = 0,
			effect    = "stars",
		},
	},
	[6] = {
		id       = 6,
		name     = "Tech Maze",
		icon     = "⚙️",
		color    = Color3.fromRGB(0, 180, 200),
		unlockLevel = 21,
		description = "Doors, buttons, and switches block the path.",
		mechanics = { "doors", "buttons", "switches" },
		mazeSize  = { width = 19, height = 19 },
		useCheckpoints = false,
		theme     = "tech",
		ambientColor = Color3.fromRGB(20, 60, 80),
		fogEnd   = 350,
		bg = {
			skyTop    = Color3.fromRGB(8, 20, 35),
			skyBottom = Color3.fromRGB(20, 50, 75),
			clockTime = 20,
			effect    = "sparks",
		},
	},
	[7] = {
		id       = 7,
		name     = "Chaos Maze",
		icon     = "💀",
		color    = Color3.fromRGB(120, 0, 180),
		unlockLevel = 28,
		description = "Every mechanic combined. Only the best survive.",
		mechanics = { "fog", "slippery", "lava", "darkness", "doors", "buttons", "switches", "falsePaths" },
		mazeSize  = { width = 23, height = 23 },
		useCheckpoints = true,
		lavaDensity = 0.07,
		theme     = "chaos",
		ambientColor = Color3.fromRGB(40, 0, 60),
		fogEnd   = 45,
		bg = {
			skyTop    = Color3.fromRGB(20, 0, 35),
			skyBottom = Color3.fromRGB(60, 0, 90),
			clockTime = 3,
			effect    = "chaos",
		},
	},
}

Constants.WORLD_COUNT = 7

-- ─── Bonus levels (paid, special shapes) ─────────────────────────────────────
Constants.BONUS_LEVELS = {
	circle = {
		id = "circle",
		name = "Круговой лабиринт",
		icon = "⭕",
		description = "Полярный лабиринт: кольца и секторы, стены — дуги.",
		shape = "circle",
		usePolar = true,
		polarRings = 8,
		polarSectors = 12,
		polarRingWidth = 14,
		polarEnclosed = true,
		mazeSize = { width = 17, height = 17 },  -- fallback only
		theme = "classic",
		mechanics = {},
		useCheckpoints = false,
		runCost = 35,
		unlockCost = 280,
		rewardCoins = 45,
		rewardXP = 90,
		ambientColor = Color3.fromRGB(190, 175, 150),
		fogEnd = 180,
		bg = {
			skyTop = Color3.fromRGB(120, 160, 220),
			skyBottom = Color3.fromRGB(200, 210, 230),
			clockTime = 15,
			effect = "none",
		},
	},
	star = {
		id = "star",
		name = "Звёздный лабиринт",
		icon = "⭐",
		description = "Пятиконечная звезда — узкие лучи и тупики.",
		shape = "star",
		mazeSize = { width = 21, height = 21 },
		theme = "dark",
		mechanics = { "darkness" },
		useCheckpoints = false,
		runCost = 50,
		unlockCost = 400,
		rewardCoins = 60,
		rewardXP = 120,
		ambientColor = Color3.fromRGB(30, 20, 50),
		fogEnd = 70,
		bg = {
			skyTop = Color3.fromRGB(10, 5, 25),
			skyBottom = Color3.fromRGB(40, 20, 60),
			clockTime = 0,
			effect = "stars",
		},
	},
	pentagon = {
		id = "pentagon",
		name = "Пентагон",
		icon = "⬠",
		description = "Пятиконечник — пять острых углов.",
		shape = "pentagon",
		mazeSize = { width = 19, height = 19 },
		theme = "tech",
		mechanics = {},
		useCheckpoints = false,
		runCost = 45,
		unlockCost = 350,
		rewardCoins = 55,
		rewardXP = 110,
		ambientColor = Color3.fromRGB(30, 70, 100),
		fogEnd = 350,
		bg = {
			skyTop = Color3.fromRGB(10, 25, 45),
			skyBottom = Color3.fromRGB(25, 55, 80),
			clockTime = 20,
			effect = "sparks",
		},
	},
	overgrown = {
		id = "overgrown",
		name = "Из зарослей",
		icon = "🌿",
		description = "Органическая форма, окружённая густыми кустами.",
		shape = "overgrown",
		mazeSize = { width = 19, height = 19 },
		theme = "forest",
		mechanics = { "fog" },
		useCheckpoints = false,
		runCost = 40,
		unlockCost = 320,
		rewardCoins = 50,
		rewardXP = 100,
		ambientColor = Color3.fromRGB(45, 90, 35),
		fogEnd = 50,
		bg = {
			skyTop = Color3.fromRGB(20, 40, 25),
			skyBottom = Color3.fromRGB(50, 70, 40),
			clockTime = 9,
			effect = "leaves",
		},
	},
	endless = {
		id = "endless",
		name = "Бесконечный лабиринт",
		icon = "♾️",
		description = "Круговой лабиринт. После каждого прохождения — новый, больше и сложнее. Без конца.",
		shape = "circle",
		usePolar = true,
		endless = true,
		polarRings = 10,
		polarSectors = 12,
		polarRingWidth = 14,
		polarMaxRings = 20,
		mazeSize = { width = 1, height = 1 },
		theme = "tech",
		mechanics = {},
		useCheckpoints = false,
		runCost = 30,
		unlockCost = 220,
		rewardCoins = 40,
		rewardXP = 80,
		ambientColor = Color3.fromRGB(20, 60, 90),
		fogEnd = 400,
		bg = {
			skyTop = Color3.fromRGB(8, 20, 40),
			skyBottom = Color3.fromRGB(20, 50, 80),
			clockTime = 22,
			effect = "sparks",
		},
	},
}

Constants.BONUS_LEVEL_ORDER = { "circle", "endless", "star", "pentagon", "overgrown" }

function Constants.getBonusLevel(bonusId: string)
	return Constants.BONUS_LEVELS[bonusId]
end

function Constants.isBonusUnlocked(data, bonusId: string): boolean
	return data.UnlockedBonusLevels and data.UnlockedBonusLevels[bonusId] == true
end

-- Checkpoints only on worlds where the player can die (lava / damage)
function Constants.worldUsesCheckpoints(worldConfig): boolean
	if worldConfig.useCheckpoints ~= nil then
		return worldConfig.useCheckpoints
	end
	for _, mechanic in ipairs(worldConfig.mechanics or {}) do
		if mechanic == "lava" or mechanic == "damage" then
			return true
		end
	end
	return false
end

-- ─── Gamepass IDs (replace with real IDs before publishing) ──────────────────
Constants.GAMEPASS_IDS = {
	DoubleCoins     = 000000001,
	VIP             = 000000002,
	SpeedBoost      = 000000003,
	NightVision     = 000000004,
	ExtraCheckpoint = 000000005,
	RainbowTrail    = 000000006,
}

-- ─── Developer Product IDs (replace with real IDs) ────────────────────────────
Constants.PRODUCT_IDS = {
	SkipLevel          = 100000001,
	PathHint           = 100000002,
	TeleportCheckpoint = 100000003,
	Revive             = 100000004,
	UnlockWorld        = 100000005,  -- replace with real Developer Product ID in Creator Hub
	UnlockBonusPack    = 100000006,  -- optional: unlock all bonus levels (Robux)
}

-- Cost to unlock a locked world early with in-game coins
Constants.WORLD_UNLOCK_COIN_COST = 400

-- Starting coins when testing in Studio (DataStore skipped)
Constants.STUDIO_START_COINS = 500

-- ─── Shop Items ───────────────────────────────────────────────────────────────
Constants.SHOP_ITEMS = {
	-- Trails
	{ id = "trail_blue",    category = "trail",  name = "Blue Trail",    price = 150,  color = Color3.fromRGB(0, 100, 255) },
	{ id = "trail_red",     category = "trail",  name = "Red Trail",     price = 150,  color = Color3.fromRGB(255, 30, 30) },
	{ id = "trail_green",   category = "trail",  name = "Green Trail",   price = 150,  color = Color3.fromRGB(30, 220, 30) },
	{ id = "trail_gold",    category = "trail",  name = "Gold Trail",    price = 500,  color = Color3.fromRGB(255, 200, 0) },
	{ id = "trail_rainbow", category = "trail",  name = "Rainbow Trail", price = 0,    gamepass = "RainbowTrail" },

	-- Auras
	{ id = "aura_fire",     category = "aura",   name = "Fire Aura",     price = 300,  color = Color3.fromRGB(255, 100, 0) },
	{ id = "aura_ice",      category = "aura",   name = "Ice Aura",      price = 300,  color = Color3.fromRGB(100, 200, 255) },
	{ id = "aura_dark",     category = "aura",   name = "Dark Aura",     price = 400,  color = Color3.fromRGB(80, 0, 120) },

	-- Pets
	{ id = "pet_slime",     category = "pet",    name = "Slime Pet",     price = 500 },
	{ id = "pet_ghost",     category = "pet",    name = "Ghost Pet",     price = 800 },
	{ id = "pet_dragon",    category = "pet",    name = "Dragon Pet",    price = 1500 },

	-- Effects
	{ id = "effect_stars",  category = "effect", name = "Star Effect",   price = 200 },
	{ id = "effect_sparks", category = "effect", name = "Sparks Effect",  price = 250 },
}

-- ─── Achievements ─────────────────────────────────────────────────────────────
Constants.ACHIEVEMENTS = {
	{ id = "first_maze",    name = "First Steps",      desc = "Complete your first maze",        xp = 50,  coins = 10 },
	{ id = "maze_10",       name = "Getting Good",     desc = "Complete 10 mazes",               xp = 100, coins = 25 },
	{ id = "maze_50",       name = "Maze Master",      desc = "Complete 50 mazes",               xp = 250, coins = 75 },
	{ id = "maze_100",      name = "Legendary",        desc = "Complete 100 mazes",              xp = 500, coins = 200 },
	{ id = "secret_1",      name = "Secret Seeker",    desc = "Find your first secret room",     xp = 75,  coins = 20 },
	{ id = "secret_10",     name = "Explorer",         desc = "Find 10 secret rooms",            xp = 200, coins = 60 },
	{ id = "all_worlds",    name = "World Conqueror",  desc = "Complete all 7 worlds",           xp = 750, coins = 300 },
	{ id = "speed_run",     name = "Speed Demon",      desc = "Complete a maze in under 60s",    xp = 150, coins = 50 },
	{ id = "no_checkpoint", name = "Iron Will",        desc = "Complete a maze without using checkpoints", xp = 200, coins = 75 },
	{ id = "level_10",      name = "Rising Star",      desc = "Reach account level 10",          xp = 0,   coins = 50 },
	{ id = "level_50",      name = "Veteran",          desc = "Reach account level 50",          xp = 0,   coins = 200 },
	{ id = "rich",          name = "Coin Collector",   desc = "Collect 1000 total coins",        xp = 100, coins = 0 },
}

-- ─── Daily Quests ─────────────────────────────────────────────────────────────
Constants.DAILY_QUESTS = {
	{ id = "complete_maze",    desc = "Complete 1 maze",          goal = 1,  reward = { coins = 30,  xp = 50  } },
	{ id = "complete_3_maze",  desc = "Complete 3 mazes",         goal = 3,  reward = { coins = 75,  xp = 100 } },
	{ id = "collect_coins_50", desc = "Collect 50 coins",         goal = 50, reward = { coins = 25,  xp = 40  } },
	{ id = "find_secret",      desc = "Find a secret room",       goal = 1,  reward = { coins = 50,  xp = 75  } },
	{ id = "complete_world2",  desc = "Complete World 2 maze",    goal = 1,  reward = { coins = 60,  xp = 80  } },
	{ id = "no_hint",          desc = "Complete maze without hints", goal = 1, reward = { coins = 40, xp = 60  } },
}

-- ─── Weekly Quests ────────────────────────────────────────────────────────────
Constants.WEEKLY_QUESTS = {
	{ id = "weekly_mazes",   desc = "Complete 20 mazes this week",    goal = 20,  reward = { coins = 300, xp = 500 } },
	{ id = "weekly_secrets", desc = "Find 5 secret rooms this week",  goal = 5,   reward = { coins = 200, xp = 350 } },
	{ id = "weekly_coins",   desc = "Collect 500 coins this week",    goal = 500, reward = { coins = 150, xp = 250 } },
	{ id = "weekly_worlds",  desc = "Complete 3 different worlds",    goal = 3,   reward = { coins = 250, xp = 400 } },
}

-- ─── Daily Reward Streak ─────────────────────────────────────────────────────
Constants.DAILY_REWARDS = {
	[1]  = { coins = 20,  xp = 30  },
	[2]  = { coins = 25,  xp = 40  },
	[3]  = { coins = 35,  xp = 50  },
	[4]  = { coins = 50,  xp = 60  },
	[5]  = { coins = 75,  xp = 75  },
	[6]  = { coins = 100, xp = 100 },
	[7]  = { coins = 200, xp = 200 },  -- week streak bonus
}

-- ─── Gameplay ─────────────────────────────────────────────────────────────────
Constants.PLAYER_SPEED_DEFAULT = 32
Constants.PLAYER_SPEED_BOOST   = 48       -- with SpeedBoost gamepass
Constants.LAVA_DAMAGE_PER_SECOND = 10   -- legacy reference
Constants.LAVA_DAMAGE_INTERVAL   = 0.6  -- seconds between lava ticks
Constants.LAVA_DAMAGE_PER_TICK   = 5    -- HP per tick (not instant)
Constants.LAVA_TOUCH_RADIUS      = 5    -- horizontal studs to count as "on" lava
Constants.COIN_PICKUP_RADIUS   = 6
Constants.CHECKPOINT_ACTIVATE_RADIUS = 8
Constants.CELL_SIZE = 16                  -- studs per maze cell (2x wider corridors)
Constants.WALL_HEIGHT = 28
Constants.WALL_THICKNESS = 1

-- Ice / slippery worlds (client-side momentum)
-- SLIPPERY_FRICTION     — затухание скорости вдоль движения (ближе к 1 = дольше едет)
-- SLIPPERY_SIDE_FRICTION — затухание бокового заноса (ниже = дольше заносит в поворотах)
-- SLIPPERY_ACCEL        — разгон от ввода (ниже = тяжелее разогнаться/затормозить)
-- SLIPPERY_STEER        — боковая сила руля (ниже = тяжелее повернуть, больше занос)
Constants.SLIPPERY_FRICTION       = 0.990   -- продольное затухание
Constants.SLIPPERY_SIDE_FRICTION  = 0.968   -- боковое затухание (занос гасится медленно)
Constants.SLIPPERY_ACCEL          = 2.2     -- ускорение от ввода
Constants.SLIPPERY_STEER          = 0.35    -- слабый руль → сильный занос в поворотах
Constants.SLIPPERY_MAX_SPEED_MULT = 0.80    -- предельная скорость (80% от обычной)
Constants.SLIPPERY_FLOOR_FRICTION = 0.01    -- CustomPhysicalProperties friction on ice floor

-- Polar (circular) bonus mazes — tune size & corridor width here
Constants.POLAR_RING_WIDTH   = 14         -- corridor width in studs
Constants.POLAR_MAX_RINGS    = 18         -- endless mode cap
Constants.POLAR_WALL_SEGMENTS = 0.42      -- arc smoothness (lower = more segments, smoother curve)

-- Maze camera zoom (scroll wheel in maze zone; restored in hub)
-- MAZE_CAMERA_LOCK_FIRST_PERSON = true  → locked first-person, no zoom
-- MAZE_CAMERA_MIN_ZOOM / MAX_ZOOM       → how close/far you can scroll (studs from character)
Constants.MAZE_CAMERA_LOCK_FIRST_PERSON = false
Constants.MAZE_CAMERA_MIN_ZOOM = 2        -- closest (2 = near shoulder view)
Constants.MAZE_CAMERA_MAX_ZOOM = 17       -- farthest (raise to 20–30 for more overview)

-- ─── World layout (multiplayer-safe placement) ────────────────────────────────
-- Each player's maze is generated in its own isolated region high above the hub,
-- so multiple players can play different worlds simultaneously without overlap.
Constants.MAZE_BASE_Y      = 1000         -- mazes are built high above the hub
Constants.MAZE_SLOT_SPACING = 4000        -- horizontal spacing between player slots
Constants.MAZE_MAX_SLOTS   = 40           -- supports up to 40 concurrent players
-- Y threshold: below = hub zone (hub lighting), above = maze zone (per-world lighting)
Constants.MAZE_ZONE_MIN_Y  = 800

-- ─── Hub ──────────────────────────────────────────────────────────────────────
-- Hub geometry lives in assets/Hub (Rojo) — visible in Studio WITHOUT Play.
-- Edit Hub/Generated or Hub/Decor in Studio, then Rojo → Export selection.
-- false = use baked hub + wire pads on Play; true = fully custom Hub from Studio
Constants.USE_CUSTOM_HUB = false

Constants.HUB_CENTER     = Vector3.new(0, 0, 0)
Constants.HUB_SIZE       = 160            -- hub platform side length (studs)
Constants.HUB_SPAWN_OFFSET = Vector3.new(0, 6, -50)  -- fallback spawn if no HubSpawn part
Constants.HUB_PAD_SPACING  = 22           -- distance between world selection pads (auto-build only)
Constants.HUB_BONUS_PAD_SPACING = 24      -- bonus pads row spacing
Constants.HUB_BONUS_PAD_Z  = -32          -- Z offset from hub center (world pads use +20)

-- ─── Admin ────────────────────────────────────────────────────────────────────
-- Who gets the admin panel (fly, speed slider, F9 / 🛡️ button):
--   1. Game owner (CreatorId) — always admin
--   2. ADMIN_USER_IDS — add Roblox UserId numbers
--   3. ADMIN_USERNAMES — add display names (resolved on server start)
--
-- How to find UserId: profile URL roblox.com/users/123456789/profile → 123456789
-- Or in Studio: Game Settings → Permissions, or print(player.UserId) in Play
Constants.ADMIN_USER_IDS = {
	2899219134, -- NeMo_Alkury
	8122558221, -- another admin (uncomment and replace)
}
Constants.ADMIN_USERNAMES = {
	"Labrador_shore",  -- no UserId needed — add name here
}
Constants.ADMIN_MIN_SPEED = 0
Constants.ADMIN_MAX_SPEED = 150
Constants.ADMIN_FLY_SPEED = 80

-- ─── UI Colors ────────────────────────────────────────────────────────────────
Constants.UI = {
	Background  = Color3.fromRGB(15, 15, 25),
	Surface     = Color3.fromRGB(25, 25, 40),
	Accent      = Color3.fromRGB(80, 160, 255),
	AccentAlt   = Color3.fromRGB(255, 160, 30),
	Success     = Color3.fromRGB(50, 200, 100),
	Danger      = Color3.fromRGB(220, 50, 50),
	TextPrimary = Color3.fromRGB(240, 240, 255),
	TextMuted   = Color3.fromRGB(140, 140, 160),
	Gold        = Color3.fromRGB(255, 200, 30),
}

return Constants

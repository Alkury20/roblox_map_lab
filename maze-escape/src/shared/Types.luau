-- Types.luau
-- Shared type definitions

export type PlayerData = {
	Coins: number,
	XP: number,
	Level: number,
	CurrentWorld: number,
	CurrentLevel: number,
	BestTimes: { [number]: number },
	CompletedWorlds: { [number]: boolean },
	OwnedItems: { [string]: boolean },
	EquippedItems: {
		Trail: string,
		Aura: string,
		Effect: string,
		Pet: string,
	},
	Achievements: { [string]: boolean },
	QuestProgress: { [string]: number },
	DailyRewardStreak: number,
	LastDailyReward: number,
	WeeklyQuestReset: number,
	TotalMazesCompleted: number,
	SecretRoomsFound: number,
	Gamepasses: { [string]: boolean },
}

export type MazeCell = {
	x: number,
	y: number,
	walls: { north: boolean, south: boolean, east: boolean, west: boolean },
	visited: boolean,
	isSecretRoom: boolean,
	hasCheckpoint: boolean,
	hasCoin: boolean,
}

export type MazeData = {
	width: number,
	height: number,
	cells: { { MazeCell } },
	startPos: { x: number, y: number },
	exitPos: { x: number, y: number },
	secretRooms: { { x: number, y: number } },
	checkpoints: { { x: number, y: number } },
	coinPositions: { { x: number, y: number } },
}

export type WorldConfig = {
	id: number,
	name: string,
	icon: string,
	color: Color3,
	unlockLevel: number,
	description: string,
	mechanics: { string },
	mazeSize: { width: number, height: number },
	theme: string,
	ambientColor: Color3,
	fogEnd: number,
}

export type QuestData = {
	id: string,
	desc: string,
	goal: number,
	reward: { coins: number, xp: number },
}

export type AchievementData = {
	id: string,
	name: string,
	desc: string,
	xp: number,
	coins: number,
}

export type ShopItem = {
	id: string,
	category: string,
	name: string,
	price: number,
	color: Color3?,
	gamepass: string?,
}

return {}

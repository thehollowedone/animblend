--!strict

local StockCatalog = {}

StockCatalog.Slots = {
	"idle",
	"walk",
	"run",
	"jump",
	"fall",
	"climb",
	"swim",
	"swimidle",
	"sit",
	"toolnone",
	"toolslash",
	"toollunge",
	"wave",
	"point",
	"dance",
	"dance1",
	"dance2",
	"dance3",
	"laugh",
	"cheer",
}

StockCatalog.ToolSlots = {
	"toolnone",
	"toolslash",
	"toollunge",
}

StockCatalog.ToolSlotByState = {
	None = "toolnone",
	Slash = "toolslash",
	Lunge = "toollunge",
}

StockCatalog.ToolIdsByRig = {
	R6 = {
		toolnone = "rbxassetid://182393478",
		toolslash = "rbxassetid://129967390",
		toollunge = "rbxassetid://129967478",
	},
	R15 = {
		toolnone = "rbxassetid://507768375",
		toolslash = "rbxassetid://522635514",
		toollunge = "rbxassetid://522638767",
	},
}

StockCatalog.EmoteSlots = {
	"wave",
	"point",
	"dance",
	"dance1",
	"dance2",
	"dance3",
	"laugh",
	"cheer",
}

StockCatalog.EmoteIndexByName = {
	wave = 1,
	point = 2,
	dance = 3,
	dance1 = 4,
	dance2 = 5,
	dance3 = 6,
	laugh = 7,
	cheer = 8,
}

StockCatalog.EmoteNameByIndex = {
	[1] = "wave",
	[2] = "point",
	[3] = "dance",
	[4] = "dance1",
	[5] = "dance2",
	[6] = "dance3",
	[7] = "laugh",
	[8] = "cheer",
}

StockCatalog.LoopedEmotes = {
	dance = true,
	dance1 = true,
	dance2 = true,
	dance3 = true,
}

StockCatalog.R6DanceSlots = {
	"dance1",
	"dance2",
	"dance3",
}

StockCatalog.EmoteFireToggle = 16
StockCatalog.EmoteInputAttribute = "AnimBlendEmoteInput"
StockCatalog.ToolDuration = 0.3

return StockCatalog

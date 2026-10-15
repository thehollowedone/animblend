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
	"wave",
	"point",
	"dance",
	"dance1",
	"dance2",
	"dance3",
	"laugh",
	"cheer",
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

local EmoteIndexByName: { [string]: number } = {
	wave = 1,
	point = 2,
	dance = 3,
	dance1 = 4,
	dance2 = 5,
	dance3 = 6,
	laugh = 7,
	cheer = 8,
}
StockCatalog.EmoteIndexByName = EmoteIndexByName

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

local LoopedEmotes: { [string]: boolean } = {
	dance = true,
	dance1 = true,
	dance2 = true,
	dance3 = true,
}
StockCatalog.LoopedEmotes = LoopedEmotes

StockCatalog.R6DanceSlots = {
	"dance1",
	"dance2",
	"dance3",
}

StockCatalog.EmoteFireToggle = 16
StockCatalog.EmoteInputAttribute = "AnimBlendEmoteInput"

return StockCatalog

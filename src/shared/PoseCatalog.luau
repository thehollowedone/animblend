--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local VariantPicker = require(Root:WaitForChild("VariantPicker"))

local PoseCatalog = {}

export type Variant = VariantPicker.Variant

export type Catalog = {
	Slots: { [string]: { Variant } },
	AllIds: { string },
	SustainIds: { string },
	TransientIds: { string },
	SlotIds: { [string]: { string } },
	Primary: { [string]: string },
	HasDistinctRun: boolean,
	HasSwimSlots: boolean,
	WalkIsDefault: boolean,
}

local SustainSlots: { [string]: boolean } = {
	idle = true,
	walk = true,
	run = true,
}

local DefaultWeight = 1
local DefaultWalkId = "rbxassetid://180426354"

PoseCatalog.Slots = {
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
}

function PoseCatalog.NormalizeId(Id: number | string): string
	if type(Id) == "number" then
		return ("rbxassetid://%d"):format(math.floor(Id))
	end
	local Text = Id :: string
	local First = string.byte(Text, 1)
	if First and First >= 48 and First <= 57 and string.match(Text, "^%d+$") then
		return "rbxassetid://" .. Text
	end
	return Text
end

local function ReadWeight(Source: Instance): number
	local Weight = Source:FindFirstChild("Weight")
	if Weight and Weight:IsA("NumberValue") and Weight.Value > 0 then
		return Weight.Value
	end
	return DefaultWeight
end

local function Collect(Node: Instance, Into: { Variant }, Seen: { [string]: boolean })
	if Node:IsA("Animation") and Node.AnimationId ~= "" then
		local Id = PoseCatalog.NormalizeId(Node.AnimationId)
		if not Seen[Id] then
			Seen[Id] = true
			Into[#Into + 1] = { Id = Id, Weight = ReadWeight(Node) }
		end
		return
	end

	if Node:IsA("StringValue") and Node.Value ~= "" then
		local Direct = PoseCatalog.NormalizeId(Node.Value)
		if string.find(Direct, "rbxassetid://", 1, true) then
			if not Seen[Direct] then
				Seen[Direct] = true
				Into[#Into + 1] = { Id = Direct, Weight = ReadWeight(Node) }
			end
			return
		end
	end

	for _, Child in Node:GetChildren() do
		Collect(Child, Into, Seen)
	end
end

local function IdsMatch(Left: { Variant }?, Right: { Variant }?): boolean
	if not Left or not Right or #Left == 0 or #Right == 0 then
		return false
	end
	local LeftIds: { [string]: boolean } = {}
	for _, Entry in Left do
		LeftIds[Entry.Id] = true
	end
	for _, Entry in Right do
		if not LeftIds[Entry.Id] then
			return false
		end
	end
	return #Left == #Right
end

function PoseCatalog.Build(Animate: Instance?): Catalog
	local Slots: { [string]: { Variant } } = {}
	local AllIds: { string } = {}
	local SeenGlobal: { [string]: boolean } = {}

	if Animate then
		for _, Slot in PoseCatalog.Slots do
			local Folder = Animate:FindFirstChild(Slot)
			if Folder then
				local Variants: { Variant } = {}
				Collect(Folder, Variants, {})
				if #Variants > 0 then
					Slots[Slot] = Variants
					for _, Entry in Variants do
						if not SeenGlobal[Entry.Id] then
							SeenGlobal[Entry.Id] = true
							AllIds[#AllIds + 1] = Entry.Id
						end
					end
				end
			end
		end
	end

	local Walk = Slots.walk
	local Run = Slots.run

	local WalkIsDefault = false
	if Walk then
		for _, Entry in Walk do
			if Entry.Id == DefaultWalkId then
				WalkIsDefault = true
				break
			end
		end
	end

	local SustainSet: { [string]: boolean } = {}
	for Slot, Variants in Slots do
		if SustainSlots[Slot] then
			for _, Entry in Variants do
				SustainSet[Entry.Id] = true
			end
		end
	end

	local SustainIds: { string } = {}
	local TransientIds: { string } = {}
	for _, Id in AllIds do
		if SustainSet[Id] then
			SustainIds[#SustainIds + 1] = Id
		else
			TransientIds[#TransientIds + 1] = Id
		end
	end

	local Catalog: any = {
		Slots = Slots,
		AllIds = AllIds,
		SustainIds = SustainIds,
		TransientIds = TransientIds,
		HasDistinctRun = Run ~= nil and #Run > 0 and not IdsMatch(Walk, Run),
		HasSwimSlots = Slots.swim ~= nil or Slots.swimidle ~= nil,
		WalkIsDefault = WalkIsDefault,
		SlotIds = {},
		Primary = {},
	}

	for _, Slot in PoseCatalog.Slots do
		local Variants = PoseCatalog.Fallback(Catalog, Slot)
		if Variants and #Variants > 0 then
			local Ids: { string } = {}
			local Best: string? = nil
			local BestWeight = -1
			for _, Entry in Variants do
				Ids[#Ids + 1] = Entry.Id
				if Entry.Weight > BestWeight then
					BestWeight = Entry.Weight
					Best = Entry.Id
				end
			end
			Catalog.SlotIds[Slot] = Ids
			Catalog.Primary[Slot] = Best
		end
	end

	return Catalog
end

function PoseCatalog.Fallback(Catalog: Catalog, Slot: string): { Variant }?
	local Direct = Catalog.Slots[Slot]
	if Direct then
		return Direct
	end
	if Slot == "run" then
		return Catalog.Slots.walk
	end
	if Slot == "walk" then
		return Catalog.Slots.run
	end
	if Slot == "swimidle" then
		return Catalog.Slots.swim or Catalog.Slots.idle
	end
	if Slot == "swim" then
		return Catalog.Slots.swimidle or Catalog.Slots.idle
	end
	if Slot == "sit" or Slot == "fall" or Slot == "jump" or Slot == "climb" then
		return Catalog.Slots.idle
	end
	return nil
end

function PoseCatalog.VariantCount(Catalog: Catalog, Slot: string): number
	local Variants = PoseCatalog.Fallback(Catalog, Slot)
	if not Variants then
		return 0
	end
	return #Variants
end

function PoseCatalog.Pick(Catalog: Catalog, Slot: string, Bucket: number): string?
	local Variants = PoseCatalog.Fallback(Catalog, Slot)
	if not Variants then
		return nil
	end
	local Chosen = VariantPicker.Pick(Variants, Bucket)
	if not Chosen then
		return nil
	end
	return Chosen.Id
end

return PoseCatalog

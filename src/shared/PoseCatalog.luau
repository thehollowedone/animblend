--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local StockCatalog = require(Root:WaitForChild("StockCatalog"))
local VariantPicker = require(Root:WaitForChild("VariantPicker"))

local PoseCatalog = {}

-- Deterministic catalog limits. AnimBlend drives every catalog entry in a
-- fixed simulation callback, so accepting an unbounded animation hierarchy
-- would turn content configuration into unbounded frame work. These caps are
-- intentionally much larger than stock R6/R15 packs.
PoseCatalog.Limits = {
	MaxVariantsPerSlot = 32,
	MaxDirectionalVariants = 32,
	MaxEntries = 256,
	MaxUniqueIds = 128,
	MaxAssetIdLength = 512,
	MaxEncodedBytes = 256 * 1024,
	MaxWeight = 1_000_000,
	MaxVelocityComponent = 10_000,
}

export type Variant = VariantPicker.Variant
export type DirectionalVariant = {
	Id: string,
	Weight: number,
	Velocity: Vector2,
}

export type Catalog = {
	Slots: { [string]: { Variant } },
	Directional: { DirectionalVariant },
	DirectionalIds: { string },
	AllIds: { string },
	SustainIds: { string },
	TransientIds: { string },
	SlotIds: { [string]: { string } },
	Primary: { [string]: string },
	HasDistinctRun: boolean,
	HasSwimSlots: boolean,
	WalkIsDefault: boolean,
	HasDirectional: boolean,
}

local SustainSlots: { [string]: boolean } = {
	idle = true,
	walk = true,
	run = true,
}

local DefaultWeight = 1
local StockWeight = 10
local DefaultWalkId = "rbxassetid://180426354"
local Limits = PoseCatalog.Limits

PoseCatalog.Slots = StockCatalog.Slots

local function IsFinite(Value: number): boolean
	return Value == Value and Value > -math.huge and Value < math.huge
end

local function SourceName(Source: Instance): string
	local Name = Source.Name
	return if type(Name) == "string" and Name ~= "" then Name else "<unnamed>"
end

local function IdProblem(Id: string): string?
	if Id == "" then
		return "animation ID must not be empty"
	end
	if #Id > Limits.MaxAssetIdLength then
		return ("animation ID exceeds the %d-byte limit"):format(Limits.MaxAssetIdLength)
	end
	if string.find(Id, "[\r\n\t%z]") then
		return "animation ID contains a forbidden control character"
	end
	return nil
end

local function AssertId(Id: string, Context: string): string
	local Problem = IdProblem(Id)
	if Problem then
		error(("AnimBlend catalog %s: %s"):format(Context, Problem), 3)
	end
	return Id
end

function PoseCatalog.NormalizeId(Id: number | string): string
	if type(Id) == "number" then
		if not IsFinite(Id) or Id <= 0 then
			error("AnimBlend catalog animation ID numbers must be finite and positive", 2)
		end
		return ("rbxassetid://%d"):format(math.floor(Id))
	end
	local Text = Id :: string
	local Numeric = string.match(Text, "^%d+$")
		or string.match(Text, "^rbxassetid://(%d+)$")
		or string.match(Text, "[?&]id=(%d+)")
	if Numeric then
		return "rbxassetid://" .. Numeric
	end
	return Text
end

local function ReadWeight(Source: Instance): number
	local Weight = Source:FindFirstChild("Weight")
	if Weight and Weight:IsA("NumberValue") then
		local Value = Weight.Value
		if not IsFinite(Value) or Value <= 0 or Value > Limits.MaxWeight then
			error(
				("AnimBlend catalog %s.Weight must be finite and within (0, %s]; got %s"):format(
					SourceName(Source),
					tostring(Limits.MaxWeight),
					tostring(Value)
				),
				3
			)
		end
		return Value
	end
	return DefaultWeight
end

local function ReadVelocity(Source: Instance): Vector2?
	local Velocity = Source:GetAttribute("LinearVelocity")
	if Velocity == nil then
		return nil
	end
	if typeof(Velocity) ~= "Vector2" then
		error(
			("AnimBlend catalog %s.LinearVelocity must be a Vector2"):format(SourceName(Source)),
			3
		)
	end
	local Vector = Velocity :: Vector2
	if
		not IsFinite(Vector.X)
		or not IsFinite(Vector.Y)
		or math.abs(Vector.X) > Limits.MaxVelocityComponent
		or math.abs(Vector.Y) > Limits.MaxVelocityComponent
		or Vector.Magnitude <= 0
	then
		error(
			("AnimBlend catalog %s.LinearVelocity must be finite, non-zero, and bounded to +/- %s"):format(
				SourceName(Source),
				tostring(Limits.MaxVelocityComponent)
			),
			3
		)
	end
	return Vector
end

local function Collect(Node: Instance, Into: { Variant }, Seen: { [string]: boolean }, Slot: string)
	if Node:IsA("Animation") and Node.AnimationId ~= "" then
		local Id = AssertId(PoseCatalog.NormalizeId(Node.AnimationId), ("slot %s"):format(Slot))
		if not Seen[Id] then
			if #Into >= Limits.MaxVariantsPerSlot then
				error(
					("AnimBlend catalog slot %s exceeds the %d-variant limit"):format(
						Slot,
						Limits.MaxVariantsPerSlot
					),
					3
				)
			end
			Seen[Id] = true
			Into[#Into + 1] = { Id = Id, Weight = ReadWeight(Node), Velocity = ReadVelocity(Node) }
		end
		return
	end

	if Node:IsA("StringValue") and Node.Value ~= "" then
		local Direct = AssertId(PoseCatalog.NormalizeId(Node.Value), ("slot %s"):format(Slot))
		if string.find(Direct, "rbxassetid://", 1, true) then
			if not Seen[Direct] then
				if #Into >= Limits.MaxVariantsPerSlot then
					error(
						("AnimBlend catalog slot %s exceeds the %d-variant limit"):format(
							Slot,
							Limits.MaxVariantsPerSlot
						),
						3
					)
				end
				Seen[Direct] = true
				Into[#Into + 1] = { Id = Direct, Weight = ReadWeight(Node) }
			end
			return
		end
	end

	for _, Child in Node:GetChildren() do
		Collect(Child, Into, Seen, Slot)
	end
end

local function CollectDirectional(
	Node: Instance,
	Into: { DirectionalVariant },
	Seen: { [string]: boolean }
)
	if Node:IsA("Animation") and Node.AnimationId ~= "" then
		local Velocity = ReadVelocity(Node)
		if Velocity then
			local Id = AssertId(PoseCatalog.NormalizeId(Node.AnimationId), "directional set")
			if not Seen[Id] then
				if #Into >= Limits.MaxDirectionalVariants then
					error(
						("AnimBlend directional catalog exceeds the %d-variant limit"):format(
							Limits.MaxDirectionalVariants
						),
						3
					)
				end
				Seen[Id] = true
				Into[#Into + 1] = { Id = Id, Weight = ReadWeight(Node), Velocity = Velocity }
			end
		end
		return
	end

	for _, Child in Node:GetChildren() do
		CollectDirectional(Child, Into, Seen)
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

local function SupportsDirectional(
	Slots: { [string]: { Variant } },
	Directional: { DirectionalVariant }
): boolean
	if #Directional < 4 then
		return false
	end

	local WalkIds: { [string]: boolean } = {}
	local RunIds: { [string]: boolean } = {}
	for _, Entry in Slots.walk or {} do
		WalkIds[Entry.Id] = true
	end
	for _, Entry in Slots.run or {} do
		RunIds[Entry.Id] = true
	end

	local HasWalk = false
	local HasRun = false
	local MinX, MaxX, MinY, MaxY = 0, 0, 0, 0
	for _, Entry in Directional do
		local Velocity = Entry.Velocity
		if Velocity then
			MinX = math.min(MinX, Velocity.X)
			MaxX = math.max(MaxX, Velocity.X)
			MinY = math.min(MinY, Velocity.Y)
			MaxY = math.max(MaxY, Velocity.Y)
		end
		HasWalk = HasWalk or WalkIds[Entry.Id] == true
		HasRun = HasRun or RunIds[Entry.Id] == true
	end
	return HasWalk and HasRun and MinX < 0 and MaxX > 0 and MinY < 0 and MaxY > 0
end

local function Finalize(
	Slots: { [string]: { Variant } },
	Directional: { DirectionalVariant }?
): Catalog
	local DirectionalEntries = Directional or {}
	local EntryCount = #DirectionalEntries
	for Slot, Variants in Slots do
		if #Variants > Limits.MaxVariantsPerSlot then
			error(
				("AnimBlend catalog slot %s exceeds the %d-variant limit"):format(
					Slot,
					Limits.MaxVariantsPerSlot
				),
				3
			)
		end
		EntryCount += #Variants
	end
	if #DirectionalEntries > Limits.MaxDirectionalVariants then
		error(
			("AnimBlend directional catalog exceeds the %d-variant limit"):format(
				Limits.MaxDirectionalVariants
			),
			3
		)
	end
	if EntryCount > Limits.MaxEntries then
		error(
			("AnimBlend catalog exceeds the %d-entry limit; got %d"):format(
				Limits.MaxEntries,
				EntryCount
			),
			3
		)
	end
	local HasDirectional = SupportsDirectional(Slots, DirectionalEntries)
	if not HasDirectional then
		DirectionalEntries = {}
	end
	local AllIds: { string } = {}
	local SeenGlobal: { [string]: boolean } = {}
	for _, Slot in PoseCatalog.Slots do
		local Variants = Slots[Slot]
		if Variants then
			for _, Entry in Variants do
				if not SeenGlobal[Entry.Id] then
					SeenGlobal[Entry.Id] = true
					AllIds[#AllIds + 1] = Entry.Id
				end
			end
		end
	end
	for _, Entry in DirectionalEntries do
		if not SeenGlobal[Entry.Id] then
			SeenGlobal[Entry.Id] = true
			AllIds[#AllIds + 1] = Entry.Id
		end
	end
	if #AllIds > Limits.MaxUniqueIds then
		error(
			("AnimBlend catalog exceeds the %d-unique-animation limit; got %d"):format(
				Limits.MaxUniqueIds,
				#AllIds
			),
			3
		)
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
	for _, Entry in DirectionalEntries do
		SustainSet[Entry.Id] = true
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
		Directional = DirectionalEntries,
		DirectionalIds = {},
		AllIds = AllIds,
		SustainIds = SustainIds,
		TransientIds = TransientIds,
		HasDistinctRun = Run ~= nil and #Run > 0 and not IdsMatch(Walk, Run),
		HasSwimSlots = Slots.swim ~= nil or Slots.swimidle ~= nil,
		WalkIsDefault = WalkIsDefault,
		HasDirectional = HasDirectional,
		SlotIds = {},
		Primary = {},
	}
	for _, Entry in DirectionalEntries do
		Catalog.DirectionalIds[#Catalog.DirectionalIds + 1] = Entry.Id
	end

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

local function ApplyStockToolIds(Slots: { [string]: { Variant } }, RigName: string)
	local TargetRig = if RigName == "R6" then "R6" else "R15"
	local OtherRig = if TargetRig == "R6" then "R15" else "R6"
	local TargetIds = StockCatalog.ToolIdsByRig[TargetRig]
	local OtherIds = StockCatalog.ToolIdsByRig[OtherRig]

	for _, Slot in StockCatalog.ToolSlots do
		local TargetId = TargetIds[Slot]
		local OtherId = OtherIds[Slot]
		local Variants = Slots[Slot]
		if not Variants or #Variants == 0 then
			Slots[Slot] = { { Id = TargetId, Weight = StockWeight } }
			continue
		end

		local SeenTarget = false
		for _, Entry in Variants do
			if Entry.Id == TargetId then
				SeenTarget = true
			end
		end
		for Index = #Variants, 1, -1 do
			local Entry = Variants[Index]
			if Entry.Id == OtherId then
				if SeenTarget then
					table.remove(Variants, Index)
				else
					Entry.Id = TargetId
					SeenTarget = true
				end
			end
		end
	end
end

function PoseCatalog.Build(Animate: Instance?, RigName: string?): Catalog
	local Slots: { [string]: { Variant } } = {}
	local Directional: { DirectionalVariant } = {}
	if Animate then
		for _, Slot in PoseCatalog.Slots do
			local Folder = Animate:FindFirstChild(Slot)
			if Folder then
				local Variants: { Variant } = {}
				Collect(Folder, Variants, {}, Slot)
				if #Variants > 0 then
					Slots[Slot] = Variants
				end
			end
		end
		CollectDirectional(Animate, Directional, {})
		if RigName then
			ApplyStockToolIds(Slots, RigName)
		end
	end
	return Finalize(Slots, Directional)
end

function PoseCatalog.Encode(Catalog: Catalog): string
	local Lines: { string } = {}
	for _, Slot in PoseCatalog.Slots do
		local Variants = Catalog.Slots[Slot]
		if Variants then
			for _, Entry in Variants do
				Lines[#Lines + 1] = Slot .. "\t" .. Entry.Id .. "\t" .. tostring(Entry.Weight)
			end
		end
	end
	for _, Entry in Catalog.Directional do
		local Velocity = Entry.Velocity
		if Velocity then
			Lines[#Lines + 1] = table.concat({
				"@directional",
				Entry.Id,
				tostring(Entry.Weight),
				tostring(Velocity.X),
				tostring(Velocity.Y),
			}, "\t")
		end
	end
	local Encoded = table.concat(Lines, "\n")
	if #Encoded > Limits.MaxEncodedBytes then
		error(
			("AnimBlend catalog encoding exceeds the %d-byte limit; got %d"):format(
				Limits.MaxEncodedBytes,
				#Encoded
			),
			2
		)
	end
	return Encoded
end

function PoseCatalog.Decode(Encoded: string): (Catalog?, string?)
	local function Reject(Message: string): (nil, string)
		return nil, "AnimBlend catalog decode rejected: " .. Message
	end

	if #Encoded > Limits.MaxEncodedBytes then
		return Reject(
			("payload exceeds the %d-byte limit; got %d"):format(Limits.MaxEncodedBytes, #Encoded)
		)
	end
	local ValidSlots: { [string]: boolean } = {}
	for _, Slot in PoseCatalog.Slots do
		ValidSlots[Slot] = true
	end

	local Slots: { [string]: { Variant } } = {}
	local Directional: { DirectionalVariant } = {}
	local SeenBySlot: { [string]: { [string]: boolean } } = {}
	local SeenDirectional: { [string]: boolean } = {}
	local SeenUnique: { [string]: boolean } = {}
	local UniqueCount = 0
	local EntryCount = 0
	local function CountUnique(Id: string): string?
		if not SeenUnique[Id] then
			SeenUnique[Id] = true
			UniqueCount += 1
			if UniqueCount > Limits.MaxUniqueIds then
				return ("catalog exceeds the %d-unique-animation limit"):format(Limits.MaxUniqueIds)
			end
		end
		return nil
	end
	for Line in string.gmatch(Encoded, "[^\n]+") do
		local Marker, DirectionalId, DirectionalWeight, XText, YText =
			string.match(Line, "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
		if Marker == "@directional" then
			local Weight = tonumber(DirectionalWeight)
			local X = tonumber(XText)
			local Y = tonumber(YText)
			if
				not DirectionalId
				or not Weight
				or not IsFinite(Weight)
				or Weight <= 0
				or Weight > Limits.MaxWeight
				or not X
				or not IsFinite(X)
				or math.abs(X) > Limits.MaxVelocityComponent
				or not Y
				or not IsFinite(Y)
				or math.abs(Y) > Limits.MaxVelocityComponent
			then
				return Reject("directional entry has an invalid weight or velocity")
			end
			local Id = PoseCatalog.NormalizeId(DirectionalId)
			local Problem = IdProblem(Id)
			if Problem then
				return Reject("directional entry " .. Problem)
			end
			if SeenDirectional[Id] then
				return Reject(("directional animation %s is duplicated"):format(Id))
			end
			local UniqueProblem = CountUnique(Id)
			if UniqueProblem then
				return Reject(UniqueProblem)
			end
			if #Directional >= Limits.MaxDirectionalVariants then
				return Reject(
					("directional set exceeds the %d-variant limit"):format(
						Limits.MaxDirectionalVariants
					)
				)
			end
			local Velocity = Vector2.new(X, Y)
			if Velocity.Magnitude <= 0 then
				return Reject("directional velocity must be non-zero")
			end
			EntryCount += 1
			if EntryCount > Limits.MaxEntries then
				return Reject(("catalog exceeds the %d-entry limit"):format(Limits.MaxEntries))
			end
			SeenDirectional[Id] = true
			Directional[#Directional + 1] = {
				Id = Id,
				Weight = Weight,
				Velocity = Velocity,
			}
			continue
		elseif Marker ~= nil then
			return Reject("entry has too many tab-separated fields")
		end

		local Slot, Id, WeightText = string.match(Line, "^([^\t]+)\t([^\t]+)\t([^\t]+)$")
		local Weight = if WeightText then tonumber(WeightText) else nil
		if
			not Slot
			or not ValidSlots[Slot]
			or not Id
			or not Weight
			or not IsFinite(Weight)
			or Weight <= 0
			or Weight > Limits.MaxWeight
		then
			return Reject("slot entry has an invalid slot, ID, or weight")
		end
		local NormalizedId = PoseCatalog.NormalizeId(Id)
		local Problem = IdProblem(NormalizedId)
		if Problem then
			return Reject(("slot %s %s"):format(Slot, Problem))
		end
		local Variants = Slots[Slot]
		local SlotSeen = SeenBySlot[Slot]
		if not Variants then
			Variants = {}
			Slots[Slot] = Variants
			SlotSeen = {}
			SeenBySlot[Slot] = SlotSeen
		end
		if (SlotSeen :: { [string]: boolean })[NormalizedId] then
			return Reject(("slot %s duplicates animation %s"):format(Slot, NormalizedId))
		end
		local UniqueProblem = CountUnique(NormalizedId)
		if UniqueProblem then
			return Reject(UniqueProblem)
		end
		if #Variants >= Limits.MaxVariantsPerSlot then
			return Reject(
				("slot %s exceeds the %d-variant limit"):format(Slot, Limits.MaxVariantsPerSlot)
			)
		end
		EntryCount += 1
		if EntryCount > Limits.MaxEntries then
			return Reject(("catalog exceeds the %d-entry limit"):format(Limits.MaxEntries))
		end
		(SlotSeen :: { [string]: boolean })[NormalizedId] = true
		Variants[#Variants + 1] = { Id = NormalizedId, Weight = Weight }
	end

	if next(Slots) == nil then
		return Reject("catalog contains no recognized animation slots")
	end
	local Catalog = Finalize(Slots, Directional)
	return Catalog, nil
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

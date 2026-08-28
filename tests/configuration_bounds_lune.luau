local Expect = require("./support/expect")
local RigProfile = require("../src/shared/RigProfile")
local Stub = require("./support/roblox_stub")

local T = Expect.New("ConfigurationBounds")
local Caps = { HasDistinctRun = true, HasSwimSlots = true }

local function RejectsOverride(Name, Overrides, Expected)
	local Ok, Message = pcall(RigProfile.Resolve, Name, Caps, Overrides)
	T:False(Name .. " override is rejected", Ok)
	T:True(
		Name .. " override explains the rejected field",
		type(Message) == "string" and string.find(Message, Expected, 1, true) ~= nil
	)
end

RejectsOverride("R15", { WalkDivisor = 0 }, "RigOverrides.R15.WalkDivisor")
RejectsOverride("R15", { FadeWalk = math.huge }, "must be a finite number")
RejectsOverride("R15", { RunBlendLow = 2, RunBlendHigh = 1 }, "must be less than RunBlendHigh")
RejectsOverride(
	"R15",
	{ SwimStopGate = 2, SwimStartGate = 1 },
	"must be less than or equal to SwimStartGate"
)
RejectsOverride("R6", { HasRunBlend = true }, "is derived by AnimBlend")
RejectsOverride("R6", { TypoedDivisor = 12 }, "is not a supported profile field")
RejectsOverride("R6", { SupportsRunBlend = "yes" }, "must be a boolean")

do
	local Profile = RigProfile.Resolve("R15", Caps, {
		WalkDivisor = 20,
		FadeWalk = 0.25,
		SupportsRunBlend = true,
	})
	T:Equal("valid divisor override is retained", Profile.WalkDivisor, 20)
	T:Equal("valid fade override is retained", Profile.FadeWalk, 0.25)
	T:True("derived run capability remains enabled", Profile.HasRunBlend)
end

local Modules = Stub.Build()
local PoseCatalog = Modules.PoseCatalog
local Limits = PoseCatalog.Limits

local function RejectsBuild(Name, Animate, Expected)
	local Ok, Message = pcall(PoseCatalog.Build, Animate)
	T:False(Name .. " build is rejected", Ok)
	T:True(
		Name .. " build error is actionable",
		type(Message) == "string" and string.find(Message, Expected, 1, true) ~= nil
	)
end

RejectsBuild(
	"infinite weight",
	Stub.BuildAnimate({ idle = { { Id = "rbxassetid://1", Weight = math.huge } } }),
	"Weight must be finite"
)
RejectsBuild(
	"zero directional velocity",
	Stub.BuildAnimate({
		walk = { { Id = "rbxassetid://2", Velocity = Stub.Vector2(0, 0) } },
	}),
	"LinearVelocity must be finite, non-zero"
)

do
	local Variants = {}
	for Index = 1, Limits.MaxVariantsPerSlot + 1 do
		Variants[Index] = { Id = "rbxassetid://slot" .. tostring(Index) }
	end
	RejectsBuild(
		"oversized slot",
		Stub.BuildAnimate({ idle = Variants }),
		("exceeds the %d-variant limit"):format(Limits.MaxVariantsPerSlot)
	)
end

do
	local Catalog, Reason = PoseCatalog.Decode("idle\trbxassetid://1\t1\nidle\trbxassetid://1\t1")
	T:Equal("duplicate decoded animation is rejected", Catalog, nil)
	T:True(
		"duplicate rejection includes the slot and ID",
		type(Reason) == "string" and string.find(Reason, "duplicates animation", 1, true) ~= nil
	)
end

do
	local Oversized = string.rep("x", Limits.MaxEncodedBytes + 1)
	local Catalog, Reason = PoseCatalog.Decode(Oversized)
	T:Equal("oversized encoded catalog is rejected", Catalog, nil)
	T:True(
		"oversized rejection reports the byte limit",
		type(Reason) == "string" and string.find(Reason, "byte limit", 1, true) ~= nil
	)
end

do
	local Catalog, Reason = PoseCatalog.Decode("idle\trbxassetid://valid\t1")
	T:True("a bounded catalog still decodes", Catalog ~= nil)
	T:Equal("a valid catalog has no rejection reason", Reason, nil)
end

do
	local Ok, Message = pcall(function()
		Stub.Build({ ExternalControlAttribute = "" })
	end)
	T:False("an empty external-control attribute name is rejected", Ok)
	T:True(
		"the external-control attribute error identifies its configuration field",
		type(Message) == "string"
			and string.find(Message, "ExternalControlAttribute", 1, true) ~= nil
	)
end

return T

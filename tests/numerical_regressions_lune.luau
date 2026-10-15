local DirectionalSolver = require("../src/shared/DirectionalSolver")
local Expect = require("./support/expect")
local VariantPicker = require("../src/shared/VariantPicker")

local T = Expect.New("NumericalRegressions")

-- Fractional weights represent proportions, even when their total is below one.
for _, Weights in
	{
		{ 0.5, 0.5 },
		{ 0.1, 0.9 },
		{ 0.01, 0.09 },
		{ 1.25, 3.75 },
		{ 5e-324, 5e-324 },
		{ 5e-324, 1e-323 },
		{ 1e-300, 3e-300 },
	}
do
	local Variants = {
		{ Id = "first", Weight = Weights[1] },
		{ Id = "second", Weight = Weights[2] },
		{ Id = "disabled", Weight = 0 },
	}
	local First, Disabled = 0, 0
	for Bucket = 1, 10000 do
		local Selected = VariantPicker.Pick(Variants, Bucket)
		if Selected and Selected.Id == "first" then
			First += 1
		elseif not Selected or Selected.Id ~= "second" then
			Disabled += 1
		end
	end
	local Fraction = Weights[1] / (Weights[1] + Weights[2])
	local Tag = ("weights %s:%s"):format(tostring(Weights[1]), tostring(Weights[2]))
	T:Between("fractional proportions at " .. Tag, First / 10000, Fraction - 0.01, Fraction + 0.01)
	T:Equal("zero-weight entries remain unreachable at " .. Tag, Disabled, 0)
end

-- Multiplying every weight by the same value must preserve each seeded choice.
local IntegerWeights = { { Id = "first", Weight = 1 }, { Id = "second", Weight = 3 } }
for _, Scale in { 1e-300, 0.001, 0.125, 0.5, 1.25, 1000 } do
	local ScaledWeights = {
		{ Id = "first", Weight = Scale },
		{ Id = "second", Weight = 3 * Scale },
	}
	local Stable = true
	for Bucket = 1, 10000 do
		local Original = VariantPicker.Pick(IntegerWeights, Bucket)
		local Scaled = VariantPicker.Pick(ScaledWeights, Bucket)
		if not Original or not Scaled or Original.Id ~= Scaled.Id then
			Stable = false
			break
		end
	end
	T:True("seeded choices ignore common weight scale " .. tostring(Scale), Stable)
end

local NoWeights = {
	{ Id = "first", Weight = 0 },
	{ Id = "second", Weight = -1 },
}
local Fallback = VariantPicker.Pick(NoWeights, 42)
T:True("all nonpositive weights retain the fallback", Fallback ~= nil)
T:Equal(
	"the nonpositive fallback remains deterministic",
	VariantPicker.Pick(NoWeights, 42),
	Fallback
)

local function Sample(Id, X, Y)
	return {
		Id = Id,
		Velocity = { X = X, Y = Y, Magnitude = math.sqrt(X * X + Y * Y) },
		Weight = 1,
	}
end

local Samples = {}
for _, Speed in { 6.4, 16 } do
	for _, Direction in { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } } do
		Samples[#Samples + 1] =
			Sample(tostring(#Samples + 1), Direction[1] * Speed, Direction[2] * Speed)
	end
end

-- Reconstruct playback from public outputs. Pruning and smoothing can leave a
-- raw contribution sum below one, but track weights are normalized to one.
for _, Speed in { 3.2, 6.4, 9.6, 16, 24 } do
	for _, Height in { 0.5, 1, 2 } do
		for _, Degrees in { 0, 9, 15, 30, 45, 75, 90, 135, 180, 225, 270, 315 } do
			local Angle = math.rad(Degrees)
			local Weights = {}
			local Rate = DirectionalSolver.Solve(
				Speed * Height * math.sin(Angle),
				Speed * Height * math.cos(Angle),
				Height,
				Samples,
				Weights
			)
			local Sum, X, Y = 0, 0, 0
			local Nonnegative = true
			for Index, Entry in Samples do
				local Weight = Weights[Index]
				Sum += Weight
				X += Weight * Entry.Velocity.X
				Y += Weight * Entry.Velocity.Y
				Nonnegative = Nonnegative and Weight >= 0
			end
			local Tag = ("speed %s height %s angle %s"):format(Speed, Height, Degrees)
			T:True("directional weights are nonnegative at " .. Tag, Nonnegative)
			T:Near("directional weights normalize at " .. Tag, Sum, 1)
			T:Near(
				"normalized playback reconstructs target speed at " .. Tag,
				(Rate or 0) * math.sqrt(X * X + Y * Y),
				Speed
			)
		end
	end
end

local NearAxis = {}
local NearAxisRate = DirectionalSolver.Solve(
	6.4 * math.sin(math.rad(9)),
	6.4 * math.cos(math.rad(9)),
	1,
	Samples,
	NearAxis
)
T:Near("pruned near-axis blend plays at natural speed", NearAxisRate or 0, 1)

local Weights = { 1, 1, 1, 1, 1, 1, 1, 1 }
T:Equal(
	"stationary movement has no directional result",
	DirectionalSolver.Solve(0, 0, 1, Samples, Weights),
	nil
)
for Index = 1, #Samples do
	T:Equal("stationary movement clears prior weight " .. Index, Weights[Index], 0)
end
T:Equal(
	"an empty catalog has no directional result",
	DirectionalSolver.Solve(0, 6.4, 1, {}, {}),
	nil
)
T:Equal(
	"zero-velocity samples have no directional result",
	DirectionalSolver.Solve(0, 6.4, 1, { Sample("zero", 0, 0) }, {}),
	nil
)

return T

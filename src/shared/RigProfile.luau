--!strict

local RigProfile = {}

-- Public configuration limits. These are deliberately generous enough for
-- unusual creatures while still rejecting values that would poison the fixed
-- simulation with infinities or turn a typo into a minutes-long blend.
RigProfile.Limits = {
	MaxMotionScalar = 10_000,
	MaxBlendSeconds = 60,
	MaxBlendGate = 100,
	MaxEpsilon = 0.1,
	MaxAssetIdLength = 512,
}

export type Profile = {
	Name: string,
	MoveGate: number,
	WalkDivisor: number,
	RateScale: number,
	ClimbDivisor: number,
	SwimDivisor: number,
	SwimStartGate: number,
	SwimStopGate: number,
	JumpHold: number,
	FadeIdle: number,
	FadeWalk: number,
	FadeJump: number,
	FadeFall: number,
	FadeClimb: number,
	FadeSwim: number,
	FadeSit: number,
	FadeReroll: number,
	FadeTool: number,
	MinAnimSpeed: number,
	RunBlendLow: number,
	RunBlendHigh: number,
	BlendEpsilon: number,
	SupportsRunBlend: boolean,
	ScaleOnlyDefaultWalk: boolean,
	UseRigScale: boolean,
	DefaultWalkId: string?,
	HasRunBlend: boolean,
	HasSwimPoses: boolean,
}

export type Capabilities = {
	HasDistinctRun: boolean,
	HasSwimSlots: boolean,
}

RigProfile.R15 = {
	Name = "R15",
	MoveGate = 0.75,
	WalkDivisor = 16,
	RateScale = 1.25,
	ClimbDivisor = 5,
	SwimDivisor = 10,
	SwimStartGate = 1.025,
	SwimStopGate = 0.975,
	JumpHold = 0.31,
	FadeIdle = 0.2,
	FadeWalk = 0.2,
	FadeJump = 0.1,
	FadeFall = 0.2,
	FadeClimb = 0.1,
	FadeSwim = 0.4,
	FadeSit = 0.5,
	FadeReroll = 0.15,
	FadeTool = 0.1,
	MinAnimSpeed = 0.01,
	RunBlendLow = 0.5,
	RunBlendHigh = 1,
	BlendEpsilon = 0.0001,
	SupportsRunBlend = true,
	ScaleOnlyDefaultWalk = false,
	UseRigScale = false,
	DefaultWalkId = nil,
	HasRunBlend = false,
	HasSwimPoses = false,
}

RigProfile.R6 = {
	Name = "R6",
	MoveGate = 0.01,
	WalkDivisor = 14.5,
	RateScale = 1,
	ClimbDivisor = 12,
	SwimDivisor = 10,
	SwimStartGate = 0.01,
	SwimStopGate = 0.01,
	JumpHold = 0.3,
	FadeIdle = 0.1,
	FadeWalk = 0.1,
	FadeJump = 0.1,
	FadeFall = 0.3,
	FadeClimb = 0.1,
	FadeSwim = 0.4,
	FadeSit = 0.5,
	FadeReroll = 0,
	FadeTool = 0.1,
	MinAnimSpeed = 0.01,
	RunBlendLow = 0.5,
	RunBlendHigh = 1,
	BlendEpsilon = 0.0001,
	SupportsRunBlend = false,
	ScaleOnlyDefaultWalk = true,
	UseRigScale = true,
	DefaultWalkId = "rbxassetid://180426354",
	HasRunBlend = false,
	HasSwimPoses = false,
}

type NumericRule = {
	Min: number,
	Max: number,
	MinExclusive: boolean?,
}

local Limits = RigProfile.Limits
local NumericRules: { [string]: NumericRule } = {
	MoveGate = { Min = 0, Max = Limits.MaxMotionScalar },
	WalkDivisor = { Min = 0, Max = Limits.MaxMotionScalar, MinExclusive = true },
	RateScale = { Min = 0, Max = Limits.MaxMotionScalar, MinExclusive = true },
	ClimbDivisor = { Min = 0, Max = Limits.MaxMotionScalar, MinExclusive = true },
	SwimDivisor = { Min = 0, Max = Limits.MaxMotionScalar, MinExclusive = true },
	SwimStartGate = { Min = 0, Max = Limits.MaxMotionScalar },
	SwimStopGate = { Min = 0, Max = Limits.MaxMotionScalar },
	JumpHold = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeIdle = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeWalk = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeJump = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeFall = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeClimb = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeSwim = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeSit = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeReroll = { Min = 0, Max = Limits.MaxBlendSeconds },
	FadeTool = { Min = 0, Max = Limits.MaxBlendSeconds },
	MinAnimSpeed = { Min = 0, Max = Limits.MaxMotionScalar, MinExclusive = true },
	RunBlendLow = { Min = 0, Max = Limits.MaxBlendGate },
	RunBlendHigh = { Min = 0, Max = Limits.MaxBlendGate, MinExclusive = true },
	BlendEpsilon = { Min = 0, Max = Limits.MaxEpsilon, MinExclusive = true },
}

local BooleanFields: { [string]: boolean } = {
	SupportsRunBlend = true,
	ScaleOnlyDefaultWalk = true,
	UseRigScale = true,
}

local DerivedFields: { [string]: boolean } = {
	Name = true,
	HasRunBlend = true,
	HasSwimPoses = true,
}

local function IsFinite(Value: number): boolean
	return Value == Value and Value > -math.huge and Value < math.huge
end

local function OverrideError(RigName: string, Field: string, Message: string): never
	error(("AnimBlend RigOverrides.%s.%s %s"):format(RigName, Field, Message), 3)
end

local function ValidateNumeric(RigName: string, Field: string, Value: any, Rule: NumericRule)
	if type(Value) ~= "number" or not IsFinite(Value) then
		OverrideError(RigName, Field, "must be a finite number")
	end
	local Number = Value :: number
	local TooLow = if Rule.MinExclusive then Number <= Rule.Min else Number < Rule.Min
	if TooLow or Number > Rule.Max then
		local Opening = if Rule.MinExclusive then "(" else "["
		OverrideError(
			RigName,
			Field,
			("must be within %s%s, %s]; got %s"):format(
				Opening,
				tostring(Rule.Min),
				tostring(Rule.Max),
				tostring(Number)
			)
		)
	end
end

local function ValidateOverride(RigName: string, Overrides: any?)
	if Overrides == nil then
		return
	end
	if type(Overrides) ~= "table" then
		error(
			("AnimBlend RigOverrides.%s must be a table; got %s"):format(RigName, type(Overrides)),
			3
		)
	end

	for Field, Value in Overrides do
		if type(Field) ~= "string" then
			error(("AnimBlend RigOverrides.%s keys must be strings"):format(RigName), 3)
		end
		if DerivedFields[Field] then
			OverrideError(RigName, Field, "is derived by AnimBlend and cannot be overridden")
		end
		local Rule = NumericRules[Field]
		if Rule then
			ValidateNumeric(RigName, Field, Value, Rule)
		elseif BooleanFields[Field] then
			if type(Value) ~= "boolean" then
				OverrideError(RigName, Field, "must be a boolean")
			end
		elseif Field == "DefaultWalkId" then
			if
				type(Value) ~= "string"
				or Value == ""
				or #Value > Limits.MaxAssetIdLength
				or string.find(Value, "[\r\n\t%z]") ~= nil
			then
				OverrideError(
					RigName,
					Field,
					("must be a non-empty single-line string of at most %d bytes"):format(
						Limits.MaxAssetIdLength
					)
				)
			end
		else
			OverrideError(RigName, Field, "is not a supported profile field")
		end
	end
end

local function ValidateResolved(RigName: string, Resolved: { [string]: any })
	if Resolved.SwimStopGate > Resolved.SwimStartGate then
		OverrideError(
			RigName,
			"SwimStopGate",
			"must be less than or equal to SwimStartGate so swim hysteresis cannot invert"
		)
	end
	if Resolved.RunBlendLow >= Resolved.RunBlendHigh then
		OverrideError(RigName, "RunBlendLow", "must be less than RunBlendHigh")
	end
	if Resolved.BlendEpsilon >= 1 then
		OverrideError(RigName, "BlendEpsilon", "must be less than 1")
	end
end

function RigProfile.Resolve(RigTypeName: string, Caps: Capabilities, Overrides: any?): Profile
	local RigName = if RigTypeName == "R6" then "R6" else "R15"
	local Base = if RigName == "R6" then RigProfile.R6 else RigProfile.R15
	ValidateOverride(RigName, Overrides)

	local Resolved: { [string]: any } = {}
	for Key, Value in Base :: any do
		Resolved[Key] = Value
	end

	if Overrides then
		for Key, Value in Overrides do
			Resolved[Key] = Value
		end
	end
	ValidateResolved(RigName, Resolved)

	Resolved.HasRunBlend = Resolved.SupportsRunBlend == true and Caps.HasDistinctRun == true
	Resolved.HasSwimPoses = Caps.HasSwimSlots == true

	return Resolved :: any
end

return RigProfile

--!strict

local RigProfile = {}

export type Profile = {
	Name: string,
	MoveGate: number,
	WalkDivisor: number,
	RateScale: number,
	ClimbDivisor: number,
	SwimDivisor: number,
	SwimGate: number,
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
	SwimGate = 1,
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
	SwimGate = 1,
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

function RigProfile.Resolve(
	RigTypeName: string,
	Caps: Capabilities,
	Overrides: { [string]: any }?
): Profile
	local Base = if RigTypeName == "R6" then RigProfile.R6 else RigProfile.R15

	local Resolved: { [string]: any } = {}
	for Key, Value in Base :: any do
		Resolved[Key] = Value
	end

	if Overrides then
		for Key, Value in Overrides do
			Resolved[Key] = Value
		end
	end

	Resolved.HasRunBlend = Resolved.SupportsRunBlend == true and Caps.HasDistinctRun == true
	Resolved.HasSwimPoses = Caps.HasSwimSlots == true

	return Resolved :: any
end

return RigProfile

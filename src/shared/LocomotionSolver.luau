--!strict

local LocomotionSolver = {}

export type Profile = {
	MoveGate: number,
	WalkDivisor: number,
	RateScale: number,
	ClimbDivisor: number,
	SwimDivisor: number,
	SwimGate: number,
	JumpHold: number,
	MinAnimSpeed: number,
	RunBlendLow: number,
	RunBlendHigh: number,
	BlendEpsilon: number,
	ScaleOnlyDefaultWalk: boolean,
	HasRunBlend: boolean,
	HasSwimPoses: boolean,
}

export type Input = {
	StateName: string,
	GroundSpeed: number,
	TotalSpeed: number,
	ClimbSpeed: number,
	OnAir: boolean,
	HeightScale: number,
	RigScale: number,
	JumpElapsed: number?,
	ActionPlaying: boolean,
	WalkIsDefault: boolean,
}

export type Field = {
	Idle: number,
	Walk: number,
	Run: number,
	Jump: number,
	Fall: number,
	Climb: number,
	Swim: number,
	SwimIdle: number,
	Sit: number,
	Rate: number,
	ClimbRate: number,
	SwimRate: number,
}

LocomotionSolver.SlotInfo = {
	{ Slot = "idle", Key = "Idle", Fade = "FadeIdle", Looped = true, Sustain = true, Rate = nil },
	{ Slot = "walk", Key = "Walk", Fade = "FadeWalk", Looped = true, Sustain = true, Rate = "Rate" },
	{ Slot = "run", Key = "Run", Fade = "FadeWalk", Looped = true, Sustain = true, Rate = "Rate" },
	{ Slot = "jump", Key = "Jump", Fade = "FadeJump", Looped = false, Sustain = false, Rate = nil },
	{ Slot = "fall", Key = "Fall", Fade = "FadeFall", Looped = true, Sustain = false, Rate = nil },
	{ Slot = "climb", Key = "Climb", Fade = "FadeClimb", Looped = true, Sustain = false, Rate = "ClimbRate" },
	{ Slot = "swim", Key = "Swim", Fade = "FadeSwim", Looped = true, Sustain = false, Rate = "SwimRate" },
	{ Slot = "swimidle", Key = "SwimIdle", Fade = "FadeSwim", Looped = true, Sustain = false, Rate = nil },
	{ Slot = "sit", Key = "Sit", Fade = "FadeSit", Looped = true, Sustain = false, Rate = nil },
}

local function Blank(): Field
	return {
		Idle = 0,
		Walk = 0,
		Run = 0,
		Jump = 0,
		Fall = 0,
		Climb = 0,
		Swim = 0,
		SwimIdle = 0,
		Sit = 0,
		Rate = 1,
		ClimbRate = 1,
		SwimRate = 1,
	}
end

local ReleaseStates: { [string]: boolean } = {
	Dead = true,
	FallingDown = true,
	Flying = true,
	GettingUp = true,
	None = true,
	Physics = true,
	PlatformStanding = true,
	Ragdoll = true,
}

function LocomotionSolver.ReleasesTracks(StateName: string): boolean
	return ReleaseStates[StateName] == true
end

local function Scaled(Value: number, RigScale: number): number
	if RigScale > 0 then
		return Value / RigScale
	end
	return Value
end

local function FloorSustain(F: Field, Epsilon: number)
	if F.Idle < Epsilon then
		F.Idle = Epsilon
	end
	if F.Walk < Epsilon then
		F.Walk = Epsilon
	end
	if F.Run < Epsilon then
		F.Run = Epsilon
	end
end

function LocomotionSolver.Solve(In: Input, P: Profile): Field
	local F = Blank()

	-- Action owns the pose.
	if In.ActionPlaying then
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	local Ground = Scaled(In.GroundSpeed, In.RigScale)
	local Rate0 = Ground / P.WalkDivisor
	local HeightScale = if In.HeightScale > 0 then In.HeightScale else 1

	-- Stock's queuedAnimSpeed. Height compensation belongs to the run blend only.
	if P.ScaleOnlyDefaultWalk and not In.WalkIsDefault then
		F.Rate = 1
	else
		F.Rate = math.max(Rate0, P.MinAnimSpeed)
	end

	local State = In.StateName

	if LocomotionSolver.ReleasesTracks(State) then
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	if State == "Seated" then
		F.Sit = 1
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	if State == "Climbing" then
		F.ClimbRate = math.max(Scaled(In.ClimbSpeed, In.RigScale) / P.ClimbDivisor, P.MinAnimSpeed)
		F.Climb = 1
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	if State == "Swimming" and P.HasSwimPoses then
		if In.TotalSpeed > P.SwimGate then
			F.SwimRate = math.max(In.TotalSpeed / P.SwimDivisor, P.MinAnimSpeed)
			F.Swim = 1
		else
			F.SwimIdle = 1
		end
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	if State == "Jumping" then
		F.Jump = 1
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	local Elapsed = In.JumpElapsed
	if State == "Freefall" and (In.OnAir or Elapsed ~= nil) then
		if Elapsed ~= nil and Elapsed < P.JumpHold then
			F.Jump = 1
		else
			F.Fall = 1
		end
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	-- Stock switches between Standing and Running at a threshold; it never blends
	-- idle into walk.
	if Ground <= P.MoveGate * HeightScale then
		F.Idle = 1
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	if P.HasRunBlend then
		-- Stock's getRunWalkBlendWeights: the walk clip carries the whole low
		-- range at a warped rate, the crossfade band runs at natural rate, and the
		-- run clip warps above it.
		local RunSpeed = math.max(Rate0 * P.RateScale / HeightScale, P.MinAnimSpeed)
		if RunSpeed <= P.RunBlendLow then
			F.Walk = 1
			F.Rate = RunSpeed / P.RunBlendLow
		elseif RunSpeed < P.RunBlendHigh then
			local FadeInRun = (RunSpeed - P.RunBlendLow) / (P.RunBlendHigh - P.RunBlendLow)
			F.Walk = 1 - FadeInRun
			F.Run = FadeInRun
			F.Rate = 1
		else
			F.Run = 1
			F.Rate = RunSpeed / P.RunBlendHigh
		end
	else
		F.Walk = 1
	end

	FloorSustain(F, P.BlendEpsilon)
	return F
end

return LocomotionSolver

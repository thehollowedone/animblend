--!strict

local LocomotionSolver = {}

export type Profile = {
	MoveGate: number,
	WalkDivisor: number,
	RateScale: number,
	ClimbDivisor: number,
	SwimDivisor: number,
	SwimStartGate: number,
	SwimStopGate: number,
	JumpHold: number,
	MinAnimSpeed: number,
	RunBlendLow: number,
	RunBlendHigh: number,
	BlendEpsilon: number,
	ScaleOnlyDefaultWalk: boolean,
	UseRigScale: boolean,
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
	WantsMove: boolean,
	WasSwimming: boolean,
	WalkIsDefault: boolean,
}

export type Field = {
	Resolved: boolean,
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

export type Slot = {
	Slot: string,
	Key: string,
	Fade: string,
	Looped: boolean,
	Sustain: boolean,
	Rate: string?,
}

LocomotionSolver.SlotInfo = {
	{ Slot = "idle", Key = "Idle", Fade = "FadeIdle", Looped = true, Sustain = true, Rate = nil },
	{
		Slot = "walk",
		Key = "Walk",
		Fade = "FadeWalk",
		Looped = true,
		Sustain = true,
		Rate = "Rate",
	},
	{ Slot = "run", Key = "Run", Fade = "FadeWalk", Looped = true, Sustain = true, Rate = "Rate" },
	{ Slot = "jump", Key = "Jump", Fade = "FadeJump", Looped = false, Sustain = false, Rate = nil },
	{ Slot = "fall", Key = "Fall", Fade = "FadeFall", Looped = true, Sustain = false, Rate = nil },
	{
		Slot = "climb",
		Key = "Climb",
		Fade = "FadeClimb",
		Looped = true,
		Sustain = false,
		Rate = "ClimbRate",
	},
	{
		Slot = "swim",
		Key = "Swim",
		Fade = "FadeSwim",
		Looped = true,
		Sustain = false,
		Rate = "SwimRate",
	},
	{
		Slot = "swimidle",
		Key = "SwimIdle",
		Fade = "FadeSwim",
		Looped = true,
		Sustain = false,
		Rate = nil,
	},
	{ Slot = "sit", Key = "Sit", Fade = "FadeSit", Looped = true, Sustain = false, Rate = nil },
} :: { Slot }

local function Blank(): Field
	return {
		Resolved = false,
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

type PoseKind = "Ground" | "Air" | "Jump" | "Climb" | "Swim" | "Sit"

-- This is a registry of animation capabilities, not a list of states to
-- suppress. A state is owned only when it resolves to a pose AnimBlend knows
-- how to produce. Physics controllers, ragdolls, and future states naturally
-- remain unresolved and therefore receive the rig without an exception here.
local PoseByState: { [string]: PoseKind } = {
	Climbing = "Climb",
	Freefall = "Air",
	Jumping = "Jump",
	Landed = "Ground",
	Running = "Ground",
	RunningNoPhysics = "Ground",
	Seated = "Sit",
	StrafingNoPhysics = "Ground",
	Swimming = "Swim",
}

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
	local Pose = PoseByState[State]
	if Pose == nil then
		return F
	end
	F.Resolved = true

	if Pose == "Sit" then
		F.Sit = 1
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	if Pose == "Climb" then
		local ClimbSpeed = if P.UseRigScale
			then Scaled(In.ClimbSpeed, In.RigScale)
			else In.ClimbSpeed / HeightScale
		F.ClimbRate = math.max(ClimbSpeed / P.ClimbDivisor, P.MinAnimSpeed)
		F.Climb = 1
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	if Pose == "Swim" then
		if not P.HasSwimPoses then
			if P.UseRigScale then
				-- R6 has no swim clips. Match stock by using walk at natural
				-- speed while moving and idle otherwise.
				if Scaled(In.TotalSpeed, In.RigScale) > P.MoveGate then
					F.Walk = 1
					F.Rate = 1
				else
					F.Idle = 1
				end
			else
				-- A custom R15 Animate may omit swim slots. Its idle fallback is
				-- preferable to pretending the rig is walking underwater.
				F.Idle = 1
			end
			FloorSustain(F, P.BlendEpsilon)
			return F
		end

		local SwimSpeed = In.TotalSpeed / HeightScale
		local SwimGate = if In.WasSwimming then P.SwimStopGate else P.SwimStartGate
		if In.WantsMove and SwimSpeed > SwimGate then
			F.SwimRate = math.max(SwimSpeed / P.SwimDivisor, P.MinAnimSpeed)
			F.Swim = 1
		else
			F.SwimIdle = 1
		end
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	if Pose == "Jump" then
		F.Jump = 1
		FloorSustain(F, P.BlendEpsilon)
		return F
	end

	local Elapsed = In.JumpElapsed
	if Pose == "Air" and (In.OnAir or Elapsed ~= nil) then
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

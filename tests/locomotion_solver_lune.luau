local Expect = require("./support/expect")
local LocomotionSolver = require("../src/shared/LocomotionSolver")
local RigProfile = require("../src/shared/RigProfile")

local T = Expect.New("LocomotionSolver")

local R15 = RigProfile.Resolve("R15", { HasDistinctRun = true, HasSwimSlots = true })
local R15NoRun = RigProfile.Resolve("R15", { HasDistinctRun = false, HasSwimSlots = true })
local R15NoSwim = RigProfile.Resolve("R15", { HasDistinctRun = true, HasSwimSlots = false })
local R6 = RigProfile.Resolve("R6", { HasDistinctRun = false, HasSwimSlots = false })

local Eps = 0.0001

local function In(Fields: { [string]: any })
	local Base = {
		StateName = "Running",
		GroundSpeed = 0,
		TotalSpeed = 0,
		ClimbSpeed = 0,
		OnAir = false,
		HeightScale = 1,
		RigScale = 1,
		JumpElapsed = nil,
		WantsMove = true,
		WasSwimming = false,
		WalkIsDefault = true,
	}
	for Key, Value in Fields do
		Base[Key] = Value
	end
	return Base
end

-- Stock reference: onRunning switches Standing/Running at 0.75 * heightScale,
-- then getRunWalkBlendWeights blends on speed / 16 * 1.25 / heightScale.
local function StockR15(RawSpeed: number, HeightScale: number)
	if RawSpeed <= 0.75 * HeightScale then
		return { Idle = 1, Walk = Eps, Run = Eps }
	end
	local RunSpeed = RawSpeed / 16 * 1.25 / HeightScale
	if RunSpeed <= 0.5 then
		return { Idle = Eps, Walk = 1, Run = Eps, Rate = RunSpeed / 0.5 }
	elseif RunSpeed < 1 then
		local F = (RunSpeed - 0.5) / 0.5
		return { Idle = Eps, Walk = 1 - F, Run = F, Rate = 1 }
	end
	return { Idle = Eps, Walk = Eps, Run = 1, Rate = RunSpeed }
end

for _, Speed in { 0, 0.5, 0.75, 0.8, 2, 6, 6.4, 8, 9.6, 12, 12.8, 16, 24, 40 } do
	for _, Height in { 1, 0.5, 2 } do
		local Got = LocomotionSolver.Solve(In({ GroundSpeed = Speed, HeightScale = Height }), R15)
		local Want = StockR15(Speed, Height)
		local Tag = ("speed %s height %s"):format(tostring(Speed), tostring(Height))
		T:Near("stock parity idle at " .. Tag, Got.Idle, Want.Idle)
		T:Near("stock parity walk at " .. Tag, Got.Walk, Want.Walk)
		T:Near("stock parity run at " .. Tag, Got.Run, Want.Run)
		if Want.Rate then
			T:Near("stock parity rate at " .. Tag, Got.Rate, math.max(Want.Rate, 0.01))
		end
	end
end

local Standing = LocomotionSolver.Solve(In({ GroundSpeed = 0 }), R15)
T:Near("standing is fully idle", Standing.Idle, 1)
T:Near("standing keeps walk alive at epsilon", Standing.Walk, Eps)
T:Near("standing keeps run alive at epsilon", Standing.Run, Eps)
T:Near("standing has no jump", Standing.Jump, 0)

-- Stock's threshold, and no idle/walk cross-blend on either side of it.
T:Near(
	"at the stock gate it is still idle",
	LocomotionSolver.Solve(In({ GroundSpeed = 0.75 }), R15).Idle,
	1
)
local JustMoving = LocomotionSolver.Solve(In({ GroundSpeed = 0.76 }), R15)
T:Near("one step past the gate walk is already full", JustMoving.Walk, 1)
T:Near("and idle drops straight to the floor", JustMoving.Idle, Eps)
T:Near(
	"the gate scales with height like stock",
	LocomotionSolver.Solve(In({ GroundSpeed = 1.4, HeightScale = 2 }), R15).Idle,
	1
)

-- The walk clip carries everything below the crossfade band, warped in rate.
local Walking = LocomotionSolver.Solve(In({ GroundSpeed = 3.2 }), R15)
T:Near("slow walk is all walk", Walking.Walk, 1)
T:Near("slow walk leaves run at the sustain floor", Walking.Run, Eps)
T:Near("slow walk warps the walk rate", Walking.Rate, 0.5)

local Ramp = LocomotionSolver.Solve(In({ GroundSpeed = 9.6 }), R15)
T:Near("mid band walk", Ramp.Walk, 0.5)
T:Near("mid band run", Ramp.Run, 0.5)
T:Near("the crossfade band plays at natural rate", Ramp.Rate, 1)

local Running = LocomotionSolver.Solve(In({ GroundSpeed = 16 }), R15)
T:Near("full run drops walk to the sustain floor", Running.Walk, Eps)
T:Near("full run run weight", Running.Run, 1)
T:Near("above the band the run rate warps", Running.Rate, 1.25)

T:Near(
	"height scale moves the blend, not the rate",
	LocomotionSolver.Solve(In({ GroundSpeed = 16, HeightScale = 2 }), R15).Rate,
	1
)
T:Near(
	"and shifts the weights instead",
	LocomotionSolver.Solve(In({ GroundSpeed = 16, HeightScale = 2 }), R15).Run,
	0.25
)

-- Without a distinct run clip stock skips the blend entirely and uses
-- queuedAnimSpeed, which carries no height compensation.
local NoRun = LocomotionSolver.Solve(In({ GroundSpeed = 14.4 }), R15NoRun)
T:Near("no distinct run keeps walk at full", NoRun.Walk, 1)
T:Near("no distinct run leaves run at epsilon", NoRun.Run, Eps)
T:Near("no distinct run uses the unwarped pose speed", NoRun.Rate, 0.9)

T:Near("r6 rate at divisor", LocomotionSolver.Solve(In({ GroundSpeed = 14.5 }), R6).Rate, 1)
T:Near("r6 rate doubles", LocomotionSolver.Solve(In({ GroundSpeed = 29 }), R6).Rate, 2)
local R6SlowMovement = LocomotionSolver.Solve(In({ GroundSpeed = 0.02 }), R6)
T:Near("r6 genuine low-speed movement walks", R6SlowMovement.Walk, 1)
T:Near("r6 genuine low-speed movement leaves idle", R6SlowMovement.Idle, Eps)
T:Near(
	"r6 custom walk is not speed scaled",
	LocomotionSolver.Solve(In({ GroundSpeed = 29, WalkIsDefault = false }), R6).Rate,
	1
)
T:Near(
	"rate floors at min anim speed",
	LocomotionSolver.Solve(In({ GroundSpeed = 0.05 }), R15).Rate,
	0.01
)
T:Near(
	"rate is still reported while airborne so muted tracks stay correct",
	LocomotionSolver.Solve(In({ StateName = "Freefall", OnAir = true, GroundSpeed = 16 }), R15).Rate,
	1
)

T:Near(
	"r6 rig scale divides input",
	LocomotionSolver.Solve(In({ GroundSpeed = 8, RigScale = 2 }), R6).Walk,
	1
)
T:Near(
	"r6 rig scale can drop below gate",
	LocomotionSolver.Solve(In({ GroundSpeed = 0.015, RigScale = 4 }), R6).Idle,
	1
)

local Jumped = LocomotionSolver.Solve(In({ StateName = "Jumping" }), R15)
T:Near("jumping is fully jump", Jumped.Jump, 1)
T:Near("jumping has no fall", Jumped.Fall, 0)
T:Near("jumping keeps walk cycling at epsilon", Jumped.Walk, Eps)

local HeldJump =
	LocomotionSolver.Solve(In({ StateName = "Freefall", OnAir = true, JumpElapsed = 0.2 }), R15)
T:Near("inside the jump hold shows jump", HeldJump.Jump, 1)
T:Near("inside the jump hold has no fall", HeldJump.Fall, 0)

local PastHold =
	LocomotionSolver.Solve(In({ StateName = "Freefall", OnAir = true, JumpElapsed = 0.31 }), R15)
T:Near("at the hold boundary shows fall", PastHold.Fall, 1)
T:Near("at the hold boundary drops jump", PastHold.Jump, 0)

local NoJumpTrack = LocomotionSolver.Solve(In({ StateName = "Freefall", OnAir = true }), R15)
T:Near("freefall without a jump track falls", NoJumpTrack.Fall, 1)

T:Near(
	"r6 holds jump for 0.3",
	LocomotionSolver.Solve(In({ StateName = "Freefall", OnAir = true, JumpElapsed = 0.29 }), R6).Jump,
	1
)
T:Near(
	"r6 falls past 0.3",
	LocomotionSolver.Solve(In({ StateName = "Freefall", OnAir = true, JumpElapsed = 0.3 }), R6).Fall,
	1
)

local Grounded =
	LocomotionSolver.Solve(In({ StateName = "Freefall", OnAir = false, GroundSpeed = 8 }), R15)
T:Near("grounded freefall resolves to ground locomotion", Grounded.Walk + Grounded.Run, 1)
T:Near("grounded freefall is not idle", Grounded.Idle, Eps)
T:Near("grounded freefall does not fall", Grounded.Fall, 0)

local Sat = LocomotionSolver.Solve(In({ StateName = "Seated" }), R15)
T:Near("seated is fully sit", Sat.Sit, 1)
T:Near("seated keeps walk cycling", Sat.Walk, Eps)

local Climbing = LocomotionSolver.Solve(In({ StateName = "Climbing", ClimbSpeed = 10 }), R15)
T:Near("climbing is fully climb", Climbing.Climb, 1)
T:Near("r15 climb rate", Climbing.ClimbRate, 2)
T:Near(
	"r6 climb rate",
	LocomotionSolver.Solve(In({ StateName = "Climbing", ClimbSpeed = 10 }), R6).ClimbRate,
	10 / 12
)
T:Near(
	"r15 climb rate follows height scale",
	LocomotionSolver.Solve(In({ StateName = "Climbing", ClimbSpeed = 10, HeightScale = 2 }), R15).ClimbRate,
	1
)

T:Near(
	"swim start gate boundary is swimidle",
	LocomotionSolver.Solve(In({ StateName = "Swimming", TotalSpeed = 1.025 }), R15).SwimIdle,
	1
)
local Swim = LocomotionSolver.Solve(In({ StateName = "Swimming", TotalSpeed = 1.03 }), R15)
T:Near("swim above the gate", Swim.Swim, 1)
T:Near("swim rate", Swim.SwimRate, 0.103)
T:Near(
	"swim hysteresis keeps moving below the start gate",
	LocomotionSolver.Solve(In({ StateName = "Swimming", TotalSpeed = 1, WasSwimming = true }), R15).Swim,
	1
)
T:Near(
	"swim intent prevents root-motion feedback",
	LocomotionSolver.Solve(In({ StateName = "Swimming", TotalSpeed = 5, WantsMove = false }), R15).SwimIdle,
	1
)
T:Near(
	"r15 swim rate follows height scale",
	LocomotionSolver.Solve(In({ StateName = "Swimming", TotalSpeed = 4, HeightScale = 2 }), R15).SwimRate,
	0.2
)
T:Near(
	"r6 swimming uses walk at natural speed",
	LocomotionSolver.Solve(In({ StateName = "Swimming", TotalSpeed = 5 }), R6).Walk,
	1
)
T:Near(
	"r6 swimming does not warp walk",
	LocomotionSolver.Solve(In({ StateName = "Swimming", TotalSpeed = 5 }), R6).Rate,
	1
)
T:Near(
	"r15 without swim clips uses its idle fallback",
	LocomotionSolver.Solve(In({ StateName = "Swimming", TotalSpeed = 5 }), R15NoSwim).Idle,
	1
)

local Dead = LocomotionSolver.Solve(In({ StateName = "Dead" }), R15)
T:False("dead has no locomotion pose", Dead.Resolved)
T:Near("dead plays nothing", Dead.Idle, 0)
T:Near("dead does not walk", Dead.Walk, 0)
local UnresolvedStates = {
	"Dead",
	"FallingDown",
	"Flying",
	"GettingUp",
	"None",
	"Physics",
	"PlatformStanding",
	"Ragdoll",
}
for _, State in UnresolvedStates do
	local Quiet = LocomotionSolver.Solve(In({ StateName = State, GroundSpeed = 8 }), R15)
	T:False(State .. " has no registered locomotion pose", Quiet.Resolved)
	T:Near(State .. " plays nothing", Quiet.Idle, 0)
	T:Near(State .. " does not walk", Quiet.Walk, 0)
	T:Near(State .. " does not sit", Quiet.Sit, 0)
end
local Unknown =
	LocomotionSolver.Solve(In({ StateName = "FutureExternalController", GroundSpeed = 8 }), R15)
T:False("an unknown future state has no registered locomotion pose", Unknown.Resolved)
T:Near("an unknown future state never guesses a walk pose", Unknown.Walk, 0)
for _, State in
	{
		"Running",
		"RunningNoPhysics",
		"StrafingNoPhysics",
		"Landed",
		"Seated",
		"Climbing",
		"Swimming",
		"Jumping",
		"Freefall",
	}
do
	local Resolved = LocomotionSolver.Solve(In({ StateName = State }), R15)
	T:True(State .. " resolves through an AnimBlend pose provider", Resolved.Resolved)
end

local Stepping = LocomotionSolver.Solve(In({ GroundSpeed = 8 }), R15)
T:Near("a normal step is unaffected by the action branch", Stepping.Walk + Stepping.Run, 1)

local Slots = LocomotionSolver.SlotInfo
T:Equal("every pose slot is described", #Slots, 9)
local Sustained, Looping = 0, 0
for _, Info in Slots do
	if Info.Sustain then
		Sustained += 1
	end
	if Info.Looped then
		Looping += 1
	end
end
T:Equal("only locomotion slots sustain", Sustained, 3)
T:Equal("only jump is one-shot", Looping, 8)

return T

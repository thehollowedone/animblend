local Expect = require("./support/expect")
local RigProfile = require("../src/shared/RigProfile")

local T = Expect.New("RigProfile")

local R15 = RigProfile.R15
T:Equal("r15 move gate matches stock onRunning", R15.MoveGate, 0.75)
T:Equal("r15 walk divisor", R15.WalkDivisor, 16)
T:Equal("r15 rate scale", R15.RateScale, 1.25)
T:Equal("r15 climb divisor", R15.ClimbDivisor, 5)
T:Equal("r15 swim divisor", R15.SwimDivisor, 10)
T:Equal("r15 swim start gate", R15.SwimStartGate, 1.025)
T:Equal("r15 swim stop gate", R15.SwimStopGate, 0.975)
T:Equal("r15 jump hold", R15.JumpHold, 0.31)
T:Equal("r15 fade idle", R15.FadeIdle, 0.2)
T:Equal("r15 fade walk", R15.FadeWalk, 0.2)
T:Equal("r15 fade jump", R15.FadeJump, 0.1)
T:Equal("r15 fade fall", R15.FadeFall, 0.2)
T:Equal("r15 fade climb", R15.FadeClimb, 0.1)
T:Equal("r15 fade swim", R15.FadeSwim, 0.4)
T:Equal("r15 fade sit", R15.FadeSit, 0.5)
T:Equal("r15 fade reroll", R15.FadeReroll, 0.15)
T:Equal("r15 fade tool", R15.FadeTool, 0.1)
T:Equal("r15 blend low", R15.RunBlendLow, 0.5)
T:Equal("r15 blend high", R15.RunBlendHigh, 1)
T:Equal("r15 blend epsilon", R15.BlendEpsilon, 0.0001)
T:Equal("r15 min anim speed", R15.MinAnimSpeed, 0.01)
T:True("r15 supports run blend", R15.SupportsRunBlend)
T:False("r15 scale only default walk", R15.ScaleOnlyDefaultWalk)
T:False("r15 does not use rig scale", R15.UseRigScale)

local R6 = RigProfile.R6
T:Equal("r6 move gate", R6.MoveGate, 0.01)
T:Equal("r6 walk divisor", R6.WalkDivisor, 14.5)
T:Equal("r6 rate scale", R6.RateScale, 1)
T:Equal("r6 climb divisor", R6.ClimbDivisor, 12)
T:Equal("r6 jump hold", R6.JumpHold, 0.3)
T:Equal("r6 fade idle", R6.FadeIdle, 0.1)
T:Equal("r6 fade walk", R6.FadeWalk, 0.1)
T:Equal("r6 fade jump", R6.FadeJump, 0.1)
T:Equal("r6 fade fall", R6.FadeFall, 0.3)
T:Equal("r6 fade climb", R6.FadeClimb, 0.1)
T:Equal("r6 fade sit", R6.FadeSit, 0.5)
T:Equal("r6 fade reroll", R6.FadeReroll, 0)
T:Equal("r6 fade tool", R6.FadeTool, 0.1)
T:False("r6 supports run blend", R6.SupportsRunBlend)
T:True("r6 scale only default walk", R6.ScaleOnlyDefaultWalk)
T:True("r6 uses rig scale", R6.UseRigScale)
T:Equal("r6 default walk id", R6.DefaultWalkId, "rbxassetid://180426354")

local BlendCaps = { HasDistinctRun = true, HasSwimSlots = true }
local NoRunCaps = { HasDistinctRun = false, HasSwimSlots = true }
local R6Caps = { HasDistinctRun = true, HasSwimSlots = false }

T:True("r15 distinct run enables blend", RigProfile.Resolve("R15", BlendCaps).HasRunBlend)
T:False("r15 without distinct run", RigProfile.Resolve("R15", NoRunCaps).HasRunBlend)
T:True("r15 swim slots", RigProfile.Resolve("R15", BlendCaps).HasSwimPoses)

T:False("r6 never blends by default", RigProfile.Resolve("R6", R6Caps).HasRunBlend)
T:False("r6 without swim slots", RigProfile.Resolve("R6", R6Caps).HasSwimPoses)
T:True(
	"r6 blend override honoured",
	RigProfile.Resolve("R6", R6Caps, { SupportsRunBlend = true }).HasRunBlend
)
T:Equal(
	"override scalar applies",
	RigProfile.Resolve("R15", BlendCaps, { MoveGate = 0.75 }).MoveGate,
	0.75
)

T:Equal("unknown rig falls back to r15", RigProfile.Resolve("Whatever", BlendCaps).Name, "R15")
T:Equal("r6 name", RigProfile.Resolve("R6", R6Caps).Name, "R6")

local Copy = RigProfile.Resolve("R15", BlendCaps)
Copy.MoveGate = 99
T:Equal("resolve returns a fresh table", RigProfile.R15.MoveGate, 0.75)

return T

local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")

local T = Expect.New("Integration")

local Modules = Stub.Build()
local AnimBlend = Modules.AnimBlend
local RigProfile = Modules.RigProfile

local WalkId = "rbxassetid://180426354"
local RunId = "rbxassetid://run"
local IdleId = "rbxassetid://idle"
local JumpId = "rbxassetid://jump"
local FallId = "rbxassetid://fall"

local Delta = 1 / 60
local Eps = 0.0001

local FullSlots = {
	idle = { IdleId },
	walk = { WalkId },
	run = { RunId },
	jump = { JumpId },
	fall = { FallId },
}

local function NewWorld(Slots, RigName)
	local Animator = Stub.Animator({
		[WalkId] = 1,
		[RunId] = 1,
		[IdleId] = 2,
		[JumpId] = 0.5,
		[FallId] = 1,
	})
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(Modules.PoseCatalog, Slots)
	local Profile = RigProfile.Resolve(RigName, {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	})
	local Session = Stub.Session(Humanoid, Profile, Catalog)
	return Animator, Humanoid, Session
end

local function Drive(Session, Animator, Humanoid, Speed, Frames)
	for _ = 1, Frames do
		Session.Root.AssemblyLinearVelocity = Stub.Vector3(Speed, 0, 0)
		AnimBlend.Step(Session)
		Stub.Advance(Animator, Delta)
	end
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 60)
	local Walk = Animator.Tracks[WalkId]
	local Idle = Animator.Tracks[IdleId]

	T:Equal("steady walk plays once", Walk.PlayCount, 1)
	T:True("steady walk advances", Walk.Elapsed > 0.5)
	T:True("idle is kept alive while walking", Idle.IsPlaying)
	T:Near("idle sits at the sustain floor while walking", Idle.WeightTarget, Eps)
	T:True("idle keeps cycling while walking", Idle.Elapsed > 0.5)

	local BeforeSpam = Walk.Elapsed
	for _ = 1, 40 do
		Drive(Session, Animator, Humanoid, 12, 3)
		Drive(Session, Animator, Humanoid, 0.6, 3)
	end
	T:Equal("spam tapping never replays walk", Walk.PlayCount, 1)
	T:Equal("spam tapping never stops walk", Walk.StopCount, 0)
	T:Equal("spam tapping never replays idle", Idle.PlayCount, 1)
	T:Equal("spam tapping never stops idle", Idle.StopCount, 0)
	T:True("spam tapping keeps the gait cycling", Walk.Elapsed > BeforeSpam + 1.5)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 30)
	local Walk = Animator.Tracks[WalkId]
	local Idle = Animator.Tracks[IdleId]

	for _ = 1, 20 do
		Drive(Session, Animator, Humanoid, 0.2, 6)
		Drive(Session, Animator, Humanoid, 6, 6)
	end

	T:Equal("tapping across the gate never replays walk", Walk.PlayCount, 1)
	T:Equal("tapping across the gate never stops walk", Walk.StopCount, 0)
	T:Equal("tapping across the gate never replays idle", Idle.PlayCount, 1)
	T:Equal("tapping across the gate never stops idle", Idle.StopCount, 0)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 1.25, 20)
	local Walk = Animator.Tracks[WalkId]
	local Idle = Animator.Tracks[IdleId]

	-- Stock has no idle/walk cross-blend: past the gate, walk owns the pose.
	T:Near("past the gate walk owns the pose", Walk.WeightTarget, 1)
	T:Near("and idle sits at the sustain floor", Idle.WeightTarget, 0.0001)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 30)
	local Walk = Animator.Tracks[WalkId]
	local Idle = Animator.Tracks[IdleId]
	local Resting = Walk.Elapsed

	Drive(Session, Animator, Humanoid, 0, 60)
	T:Near("stopping drives walk to the sustain floor", Walk.WeightTarget, Eps)
	T:Near("stopping raises idle to full", Idle.WeightTarget, 1)
	T:Equal("stopping never stops walk", Walk.StopCount, 0)
	T:True("walk keeps cycling while stopped", Walk.Elapsed > Resting)

	local Parked = Walk.Elapsed
	Drive(Session, Animator, Humanoid, 8, 10)
	T:Equal("resuming never replays walk", Walk.PlayCount, 1)
	T:True("resuming continues the cycle", Walk.Elapsed > Parked)
	T:True("resuming restores walk weight", Walk.WeightTarget > 0.4)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 4, 10)
	local Walk = Animator.Tracks[WalkId]
	local BeforeRamp = Walk.Elapsed

	for Step = 1, 60 do
		Drive(Session, Animator, Humanoid, 4 + Step * 0.2, 1)
	end

	local Run = Animator.Tracks[RunId]
	T:Equal("run crossover never replays walk", Walk.PlayCount, 1)
	T:Equal("run track plays once", Run.PlayCount, 1)
	T:True("walk keeps advancing through the crossover", Walk.Elapsed > BeforeRamp + 0.5)
	T:Near("run reaches full weight", Run.WeightTarget, 1)
	T:Near("walk falls to the sustain floor", Walk.WeightTarget, Eps)
end

do
	-- Stock blends walk/run with AdjustWeight's default while both clips are
	-- visible, spending the pose transition time only when a pose enters or
	-- leaves. Passing the pose fade every step made the weights lag twice as far.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	local Walk = Animator.Tracks[WalkId]
	local Run = Animator.Tracks[RunId]
	T:True("both clips are visible inside the band", Walk.WeightTarget > 0.01 and Run.WeightTarget > 0.01)

	Drive(Session, Animator, Humanoid, 10, 4)
	T:Equal("moving within the band uses the stock blend fade", Walk.LastWeightFade, 0.1)
	T:Equal("for the run side too", Run.LastWeightFade, 0.1)

	Drive(Session, Animator, Humanoid, 0, 4)
	T:Equal("leaving the pose spends the pose transition time", Walk.LastWeightFade, 0.2)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	local Walk = Animator.Tracks[WalkId]

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	local Jump = Animator.Tracks[JumpId]
	T:Equal("jump plays", Jump.PlayCount, 1)
	T:Equal("jump uses the stock jump fade", Jump.LastPlayFade, 0.1)
	T:False("jump is not looped", Jump.Looped)
	T:Near("jump is at full weight", Jump.WeightTarget, 1)

	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air
	Drive(Session, Animator, Humanoid, 8, 12)
	T:Near("jump holds while its own clock is under the hold", Jump.WeightTarget, 1)
	T:Equal("jump is not replayed while held", Jump.PlayCount, 1)

	Drive(Session, Animator, Humanoid, 8, 20)
	local Fall = Animator.Tracks[FallId]
	T:Near("fall takes over once the jump clock passes the hold", Fall.WeightTarget, 1)
	T:Equal("fall plays once", Fall.PlayCount, 1)
	T:Equal("fall crossfades in rather than cutting", Fall.LastPlayFade, 0.2)
	T:True("fall is looped", Fall.Looped)
	T:True("walk keeps cycling through the whole jump", Walk.IsPlaying)

	Drive(Session, Animator, Humanoid, 8, 40)
	T:Equal("fall is never replayed while airborne", Fall.PlayCount, 1)

	Humanoid.StateName = "Running"
	Humanoid.FloorMaterial = Stub.Enum.Material.Plastic
	Drive(Session, Animator, Humanoid, 8, 60)
	T:Equal("landing never replays walk", Walk.PlayCount, 1)
	T:True("transient fall is stopped once it settles", Fall.StopCount > 0)
	T:True("transient jump is stopped once it settles", Jump.StopCount > 0)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	local ReJump = Animator.Tracks[JumpId]
	T:True("re-jumping plays a jump track from the top", ReJump.IsPlaying)
	T:Equal("re-jumping plays that track exactly once", ReJump.PlayCount, 1)
	T:Equal("a stopped transient pose is legitimately reloaded, not cached", Animator.LoadCallCounts[JumpId], 2)
end

do
	-- Roblox's Animator:GetTrackByAnimationId can stop returning a track once it
	-- has fully stopped and settled (modeled by the stub's Forgotten flag). If
	-- TrackDriver ever falls back to that lookup alone, a fully-settled jump/fall
	-- track gets silently replaced by a fresh LoadAnimation call every cycle -
	-- a brand new AnimationTrack object with none of the previous one's
	-- evaluation history, discovered live in Studio as inconsistent jump->fall
	-- blending. TrackDriver must hold its own reference so this never happens.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)

	for _ = 1, 5 do
		Humanoid.StateName = "Jumping"
		Drive(Session, Animator, Humanoid, 8, 1)
		Humanoid.StateName = "Freefall"
		Humanoid.FloorMaterial = Stub.Enum.Material.Air
		Drive(Session, Animator, Humanoid, 8, 40)
		Humanoid.StateName = "Running"
		Humanoid.FloorMaterial = Stub.Enum.Material.Plastic
		Drive(Session, Animator, Humanoid, 8, 60)
	end

	-- Reloading a stopped transient pose per airborne cycle is the documented
	-- pattern, so five cycles means five loads. What must never happen is
	-- reloading while the pose is continuously live.
	T:Equal("jump loads once per airborne cycle, not more", Animator.LoadCallCounts[JumpId], 5)
	T:Equal("fall loads once per airborne cycle, not more", Animator.LoadCallCounts[FallId], 5)
	T:Equal("the live jump track was played once, not per step", Animator.Tracks[JumpId].PlayCount, 1)
	T:Equal("the live fall track was played once, not per step", Animator.Tracks[FallId].PlayCount, 1)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 40)
	local Walk = Animator.Tracks[WalkId]

	Walk:Stop(0)
	Drive(Session, Animator, Humanoid, 8, 2)
	local Restored = Animator.Tracks[WalkId]
	T:True("a rewound track is restored with no dirty flag", Restored.IsPlaying)
	T:True("restoring loads a fresh track rather than driving the dead handle", Restored ~= Walk)
	T:Equal("the restored track is played exactly once", Restored.PlayCount, 1)

	local Idle = Animator.Tracks[IdleId]
	Idle:AdjustWeight(0.7, 0)
	Drive(Session, Animator, Humanoid, 8, 2)
	T:Near("a rewound weight is corrected back to the field", Idle.WeightTarget, Eps)
end

do
	local R6Slots = { idle = { IdleId }, walk = { WalkId }, jump = { JumpId }, fall = { FallId } }
	local Animator, Humanoid, Session = NewWorld(R6Slots, "R6")
	Drive(Session, Animator, Humanoid, 40, 30)

	local Walk = Animator.Tracks[WalkId]
	T:Equal("r6 walk plays once", Walk.PlayCount, 1)
	T:Equal("r6 loads no run track", Animator.Tracks[RunId], nil)
	T:Near("r6 walk stays at full weight", Walk.WeightTarget, 1)
	T:Near("r6 rate uses the 14.5 divisor", Walk.Speed, 40 / 14.5)

	Drive(Session, Animator, Humanoid, 0, 60)
	T:Near("r6 idles when stopped", Animator.Tracks[IdleId].WeightTarget, 1)
	T:Equal("r6 idle uses the r6 fade", Animator.Tracks[IdleId].LastPlayFade, 0.1)

	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air
	Drive(Session, Animator, Humanoid, 0, 60)
	T:Near("r6 falls", Animator.Tracks[FallId].WeightTarget, 1)
	T:Equal("r6 fall uses the 0.3 fade", Animator.Tracks[FallId].LastPlayFade, 0.3)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	local Walk = Animator.Tracks[WalkId]

	local Emote = Animator:LoadAnimation({ AnimationId = "rbxassetid://emote" })
	Emote.Priority = Stub.Enum.AnimationPriority.Action
	Emote:Play(0.1, 1, 1)
	Stub.Advance(Animator, 0.2)

	Drive(Session, Animator, Humanoid, 8, 20)
	T:Equal("emote is never stopped by animblend", Emote.StopCount, 0)
	T:Equal("locomotion is not replayed under an emote", Walk.PlayCount, 1)
	T:Near("locomotion yields to the emote", Walk.WeightTarget, Eps)
	T:True("the gait keeps cycling under an emote", Walk.IsPlaying)

	local Parked = Walk.Elapsed
	Emote:Stop(0.1)
	Stub.Advance(Animator, 0.2)
	Drive(Session, Animator, Humanoid, 8, 20)
	T:True("locomotion returns after the emote", Walk.WeightTarget > 0.4)
	T:Equal("returning from an emote never replays walk", Walk.PlayCount, 1)
	T:True("returning from an emote resumes mid-stride", Walk.Elapsed > Parked)
end

do
	local IdleA = "rbxassetid://idleA"
	local IdleB = "rbxassetid://idleB"
	local Animator = Stub.Animator({ [IdleA] = 1, [IdleB] = 1, [WalkId] = 1, [RunId] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(Modules.PoseCatalog, { idle = { IdleA, IdleB }, walk = { WalkId }, run = { RunId } })
	local Profile = RigProfile.Resolve("R15", { HasDistinctRun = true, HasSwimSlots = false })
	local Session = Stub.Session(Humanoid, Profile, Catalog)

	Drive(Session, Animator, Humanoid, 0, 900)

	local PlayedA = Animator.Tracks[IdleA] and Animator.Tracks[IdleA].PlayCount or 0
	local PlayedB = Animator.Tracks[IdleB] and Animator.Tracks[IdleB].PlayCount or 0
	T:True("idle re-rolls across loop wraps", PlayedA + PlayedB > 1)
	T:True("both idle variants get used", PlayedA > 0 and PlayedB > 0)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 4, 600)
	T:Equal("single-variant walk never re-rolls", Animator.Tracks[WalkId].PlayCount, 1)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	local Walk = Animator.Tracks[WalkId]

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	local Jump = Animator.Tracks[JumpId]
	T:Equal("jump fades in over the jump fade", Jump.LastPlayFade, 0.1)
	T:Equal("walk yields over the incoming jump fade", Walk.LastWeightFade, 0.1)

	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air

	local Dipped = 2
	for _ = 1, 60 do
		Drive(Session, Animator, Humanoid, 8, 1)
		local Sum = 0
		for _, Track in Animator.Tracks do
			if Track.IsPlaying then
				Sum += Track.WeightCurrent
			end
		end
		if Sum < Dipped then
			Dipped = Sum
		end
	end

	local Fall = Animator.Tracks[FallId]
	T:Equal("fall fades in over the fall fade", Fall.LastPlayFade, 0.2)
	T:Equal("jump fades out over the incoming fall fade", Jump.LastWeightFade, 0.2)
	T:True("airborne weight never dips during the handover", Dipped > 0.9)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	Humanoid.StateName = "Seated"
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal("walk yields over the incoming sit fade", Animator.Tracks[WalkId].LastWeightFade, 0.5)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air
	Drive(Session, Animator, Humanoid, 8, 40)

	local WasPlaying = {}
	for _, Id in Session.Catalog.AllIds do
		local Track = Animator.Tracks[Id]
		if Track and Track.IsPlaying then
			WasPlaying[#WasPlaying + 1] = Id
		end
	end
	T:True("some tracks are live before the toggle", #WasPlaying > 0)

	Modules.TrackDriver.StopAll(Animator, Session.Catalog.AllIds, 0.15)

	for _, Id in WasPlaying do
		local Track = Animator.Tracks[Id]
		T:Equal("toggle stops " .. Id, Track.StopIn ~= nil or not Track.IsPlaying, true)
		T:Equal("toggle hands over with a fade for " .. Id, Track.LastStopFade, 0.15)
	end

	Stub.Advance(Animator, 0.3)
	for _, Id in Session.Catalog.AllIds do
		local Track = Animator.Tracks[Id]
		if Track then
			T:False("nothing is left running after the toggle: " .. Id, Track.IsPlaying)
		end
	end
end

do
	local Plain = "rbxassetid://idlePlain"
	local Alt = "rbxassetid://idleAlt"
	local Animator = Stub.Animator({ [Plain] = 1, [Alt] = 1.5, [WalkId] = 1, [RunId] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(
		Modules.PoseCatalog,
		{ idle = { Plain, Alt }, walk = { WalkId }, run = { RunId } },
		{ [Plain] = 9, [Alt] = 1 }
	)
	local Profile = RigProfile.Resolve("R15", { HasDistinctRun = true, HasSwimSlots = false })
	local Session = Stub.Session(Humanoid, Profile, Catalog)

	Drive(Session, Animator, Humanoid, 8, 3600)
	local AltTrack = Animator.Tracks[Alt]
	T:Equal("the alternate idle is never played while moving", AltTrack == nil or AltTrack.PlayCount == 0, true)
	T:True("the plain idle is the one kept alive while moving", Animator.Tracks[Plain].IsPlaying)
	T:True("the plain idle keeps an unbroken cycle while moving", Animator.Tracks[Plain].Elapsed > 59)

	-- Stock picks a weighted idle variant every time it enters Standing, so an
	-- alternate is a legitimate outcome here. What must hold is that exactly one
	-- of them owns the pose.
	Drive(Session, Animator, Humanoid, 0, 12)
	local Full, Floored = 0, 0
	for _, Id in { Plain, Alt } do
		local Track = Animator.Tracks[Id]
		if Track and Track.WeightTarget > 0.5 then
			Full += 1
		else
			Floored += 1
		end
	end
	T:Equal("exactly one idle variant owns the pose on stopping", Full, 1)
	T:Equal("the other stays at the floor", Floored, 1)
end

do
	local Plain = "rbxassetid://idlePlain2"
	local Alt = "rbxassetid://idleAlt2"
	local Animator = Stub.Animator({ [Plain] = 1, [Alt] = 1.5, [WalkId] = 1, [RunId] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(
		Modules.PoseCatalog,
		{ idle = { Plain, Alt }, walk = { WalkId }, run = { RunId } },
		{ [Plain] = 9, [Alt] = 1 }
	)
	local Profile = RigProfile.Resolve("R15", { HasDistinctRun = true, HasSwimSlots = false })
	local Session = Stub.Session(Humanoid, Profile, Catalog)

	Drive(Session, Animator, Humanoid, 0, 3600)
	local AltTrack = Animator.Tracks[Alt]
	T:True("standing still long enough does reach an alternate", AltTrack ~= nil and AltTrack.PlayCount > 0)
	T:True("the plain idle still dominates the time", Animator.Tracks[Plain].PlayCount >= 1)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 30)

	Humanoid.StateName = "Dead"
	Drive(Session, Animator, Humanoid, 0, 30)
	for _, Id in Session.Catalog.AllIds do
		local Track = Animator.Tracks[Id]
		if Track and Track.IsPlaying then
			T:True("death leaves " .. Id .. " silent", Track.WeightTarget <= Eps + 1e-9)
		end
	end
end

do
	-- Every other slot gets its own dedicated track so jump is the ONLY slot
	-- that falls back to idle. Without this isolation, fall/climb/swim/swimidle/
	-- sit also fall back to idle and are pushed after jump in SlotInfo order,
	-- re-asserting Looped = true regardless of how jump's contribution merges -
	-- which let a real regression here slip past every earlier version of this test.
	local FallId2 = "rbxassetid://bareFall"
	local ClimbId2 = "rbxassetid://bareClimb"
	local SwimId2 = "rbxassetid://bareSwim"
	local SwimIdleId2 = "rbxassetid://bareSwimIdle"
	local SitId2 = "rbxassetid://bareSit"
	local Bare = {
		idle = { IdleId },
		walk = { WalkId },
		fall = { FallId2 },
		climb = { ClimbId2 },
		swim = { SwimId2 },
		swimidle = { SwimIdleId2 },
		sit = { SitId2 },
	}
	local Animator = Stub.Animator({ [IdleId] = 2, [WalkId] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(Modules.PoseCatalog, Bare)
	T:Equal("jump is the only slot borrowing idle", Catalog.SlotIds.jump[1], IdleId)
	local Profile = RigProfile.Resolve("R15", { HasDistinctRun = false, HasSwimSlots = true })
	local Session = Stub.Session(Humanoid, Profile, Catalog)

	Drive(Session, Animator, Humanoid, 8, 30)
	local Idle = Animator.Tracks[IdleId]
	T:True("a rig with no jump animation still keeps idle alive", Idle.IsPlaying)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	T:True("borrowing idle for jump must not make it one-shot", Idle.Looped)

	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air
	Drive(Session, Animator, Humanoid, 8, 120)
	T:True("the borrowed track survives the whole airborne phase", Idle.IsPlaying)
	T:True("the borrowed track is still looping", Idle.Looped)

	Humanoid.StateName = "Running"
	Humanoid.FloorMaterial = Stub.Enum.Material.Plastic
	Drive(Session, Animator, Humanoid, 8, 60)
	local Walk = Animator.Tracks[WalkId]
	T:True("locomotion recovers after landing on a bare rig", Walk.WeightTarget > 0.4)
	T:Equal("the bare rig never restarts its walk", Walk.PlayCount, 1)
end

do
	-- Action animations have experience-owned IDs, so Roblox's documented
	-- non-caching path is to inspect the Animator's current playing tracks.
	-- A handle retained through rollback can keep locomotion muted after the
	-- visually represented action has already been replaced.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 5)

	local ActionId = "rbxassetid://actiontest"
	local Emote = Animator:LoadAnimation({ AnimationId = ActionId })
	Emote.Priority = Stub.Enum.AnimationPriority.Action

	T:False(
		"no action track before any Action-priority track plays",
		Modules.TrackDriver.IsActionPlaying(Animator)
	)

	Emote:Play(0, 1, 1)
	T:True(
		"a currently represented Action-priority track is detected",
		Modules.TrackDriver.IsActionPlaying(Animator)
	)

	Animator.Tracks[ActionId] = nil
	T:False(
		"a rollback-replaced action handle is never retained",
		Modules.TrackDriver.IsActionPlaying(Animator)
	)

	local NonAction = Animator:LoadAnimation({ AnimationId = "rbxassetid://coretest" })
	NonAction.Priority = Stub.Enum.AnimationPriority.Core
	NonAction:Play(0.1, 1, 1)
	T:False(
		"a Core-priority play is never treated as an action",
		Modules.TrackDriver.IsActionPlaying(Animator)
	)
end

do
	-- toolnone auto-adapts to whatever a rig's Animate/toolnone folder
	-- contains and to whether ANY Tool is currently equipped (FindFirstChildOfClass
	-- "Tool" matches every equippable, not a specific hardcoded weapon), mirroring
	-- stock's animateTool(). It layers at Idle priority above locomotion's Core,
	-- so it never competes with idle/walk/run, and is not part of the mutually
	-- exclusive pose field at all.
	local ToolNoneId = "rbxassetid://toolnone"
	local Slots = {
		idle = { IdleId },
		walk = { WalkId },
		run = { RunId },
		toolnone = { ToolNoneId },
	}
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")

	Drive(Session, Animator, Humanoid, 8, 20)
	local ToolTrack = Animator.Tracks[ToolNoneId]
	T:Equal("toolnone never plays with no tool equipped", ToolTrack, nil)

	local FakeTool = Stub.Tool("Sword")
	Session.Character:SetTool(FakeTool)
	Drive(Session, Animator, Humanoid, 3, 10)

	ToolTrack = Animator.Tracks[ToolNoneId]
	T:True("equipping any Tool starts toolnone", ToolTrack ~= nil and ToolTrack.IsPlaying)
	T:Equal("toolnone uses the stock tool fade", ToolTrack.LastPlayFade, 0.1)
	T:Equal("toolnone uses Idle priority, not Core", ToolTrack.Priority.Name, "Idle")
	T:Near("toolnone reaches full weight while equipped", ToolTrack.WeightTarget, 1)

	local Walk = Animator.Tracks[WalkId]
	T:True("locomotion keeps playing underneath toolnone", Walk.IsPlaying)
	T:Near("locomotion is undisturbed by toolnone", Walk.WeightTarget, 1)

	Session.Character:SetTool(nil)
	Drive(Session, Animator, Humanoid, 8, 10)
	T:Near("unequipping drops toolnone back to zero", ToolTrack.WeightTarget, 0)

	Session.Character:SetTool(FakeTool)
	Drive(Session, Animator, Humanoid, 3, 10)
	local ReTool = Animator.Tracks[ToolNoneId]
	T:Equal(
		"re-equipping restarts toolnone from frame 0, matching stock's stop+replay",
		ReTool.PlayCount,
		1
	)
	T:True("re-equipping restores full weight", ReTool.WeightTarget > 0.4)
end

do
	-- Stock gates every tool animation on the Tool having a Handle.
	local ToolNoneId = "rbxassetid://toolnone-handleless"
	local Slots = { idle = { IdleId }, walk = { WalkId }, toolnone = { ToolNoneId } }
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")

	Session.Character:SetTool(Stub.Tool("Ability", false))
	Drive(Session, Animator, Humanoid, 8, 20)
	T:Equal("a Handle-less tool animates nothing, as in stock", Animator.Tracks[ToolNoneId], nil)

	Session.Character:SetTool(Stub.Tool("Sword"))
	Drive(Session, Animator, Humanoid, 8, 10)
	local ToolTrack = Animator.Tracks[ToolNoneId]
	T:True("a tool with a Handle still starts toolnone", ToolTrack ~= nil and ToolTrack.IsPlaying)
end

do
	-- A rig with no toolnone folder at all must not error or synthesize one -
	-- adapting automatically means doing nothing when there is nothing to adapt to.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Session.Character:SetTool(Stub.Tool("Wrench"))
	Drive(Session, Animator, Humanoid, 8, 20)
	T:Equal("no toolnone id exists to drive on a bare rig", Session.Catalog.SlotIds.toolnone, nil)
end

do
	-- A real Action-priority track (an emote, or the game's own tool-slash
	-- animation) must still be able to take visual precedence over toolnone -
	-- Roblox's own priority layering, not AnimBlend gating toolnone off.
	local ToolNoneId2 = "rbxassetid://toolnone2"
	local Slots = { idle = { IdleId }, walk = { WalkId }, toolnone = { ToolNoneId2 } }
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")
	Session.Character:SetTool(Stub.Tool("Axe"))
	Drive(Session, Animator, Humanoid, 0, 10)

	local Slash = Animator:LoadAnimation({ AnimationId = "rbxassetid://toolslash" })
	Slash.Priority = Stub.Enum.AnimationPriority.Action
	Slash:Play(0, 1, 1)

	Drive(Session, Animator, Humanoid, 0, 10)
	local ToolTrack = Animator.Tracks[ToolNoneId2]
	T:True("toolnone keeps playing under an action, ready to resume", ToolTrack.IsPlaying)
	T:Equal("the action track is untouched by AnimBlend", Slash.StopCount, 0)
end


do
	-- Roblox's server-authority guidance has a section titled "Avoid Track
	-- Caching": a handle held across frames can stop being the track actually
	-- on screen, so driving it makes AdjustWeight/AdjustSpeed "operate on
	-- tracks no longer visually represented". Under server authority the
	-- server AND the local client both drive the same character's Animator,
	-- so a stale handle is driven while a different live track for the same id
	-- plays - two copies of one animation out of phase. TrackDriver therefore
	-- holds nothing: every lookup asks the Animator for the live track.
	local Id = "rbxassetid://noCache"
	local Animator = Stub.Animator({ [Id] = 0.5 })
	local First = Modules.TrackDriver.Resolve(Animator, Id)
	T:True("resolve returns the engine's own track", First == Animator.Tracks[Id])

	-- A different live object for the same id, exactly what replicated
	-- playback produces, must win immediately with nothing shadowing it.
	local Replicated = Stub.Track(Id, 0.5)
	Animator.Tracks[Id] = Replicated
	T:True(
		"the engine's current track always wins",
		Modules.TrackDriver.Find(Animator, Id) == Replicated
	)
	T:False("no stale handle is ever returned", Modules.TrackDriver.Find(Animator, Id) == First)

	-- A fully stopped track correctly reports nil rather than a stale handle,
	-- and the next use loads a fresh one - the documented pattern.
	Replicated.Forgotten = true
	T:Equal("a stopped track reports nil, not a stale handle", Modules.TrackDriver.Find(Animator, Id), nil)
	local Fresh = Modules.TrackDriver.Resolve(Animator, Id)
	T:True("resolve then loads a genuinely fresh track", Fresh ~= nil and Fresh ~= Replicated)
end

do
	-- SlotIds resolves through PoseCatalog.Fallback, so on a rig with no jump
	-- animation SlotIds.jump hands back IDLE - a sustain track that is always
	-- playing. Using that as the jump clock made JumpElapsed permanently
	-- non-nil, which pins the jump hold on and stops Freefall from ever
	-- falling through to ground locomotion. Only the rig's own jump animation
	-- may act as the clock.
	local Bare = { idle = { IdleId }, walk = { WalkId }, fall = { FallId } }
	local Animator = Stub.Animator({ [IdleId] = 2, [WalkId] = 1, [FallId] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(Modules.PoseCatalog, Bare)
	T:Equal("the bare rig really does fall jump back to idle", Catalog.SlotIds.jump[1], IdleId)
	T:Equal("but has no jump slot of its own", Catalog.Slots.jump, nil)

	local Profile = RigProfile.Resolve("R15", { HasDistinctRun = false, HasSwimSlots = false })
	local Session = Stub.Session(Humanoid, Profile, Catalog)

	Drive(Session, Animator, Humanoid, 8, 30)

	-- Grounded Freefall must resolve to ground locomotion, not be trapped in
	-- an imaginary jump hold driven by idle's forever-cycling TimePosition.
	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Plastic
	Drive(Session, Animator, Humanoid, 8, 20)

	local Walk = Animator.Tracks[WalkId]
	T:True("grounded freefall still resolves to ground locomotion", Walk.WeightTarget > 0.4)
	T:Equal("the fall pose is not started while grounded", Animator.Tracks[FallId], nil)
end

do
	-- A track whose asset has not streamed in yet reports Length 0. The
	-- requested fade must survive that: observed live, the server played a
	-- character's very first idle/walk with fade=0 (a hard snap), and if only
	-- one side has the asset ready the two sides disagree on fade entirely.
	local Id = "rbxassetid://unstreamed"
	local Animator = Stub.Animator({ [Id] = 0.8 }, { [Id] = true })
	local Track = Modules.TrackDriver.Resolve(Animator, Id)
	T:Equal("the asset has not streamed in yet", Track.Length, 0)

	Modules.TrackDriver.Drive(Animator, {
		Id = Id,
		Weight = 1,
		Rate = 1,
		Fade = 0.2,
		Looped = true,
		Sustain = true,
	})
	T:Equal("the requested fade survives an unstreamed asset", Track.LastPlayFade, 0.2)
	T:True("and the track is genuinely playing", Track.IsPlaying)
end

do
	-- The first jump asset may still be streaming, in which case its track
	-- clock cannot be trusted to advance. The jump-to-fall handoff must use
	-- synchronized simulation state and complete on time anyway.
	local Animator = Stub.Animator({
		[IdleId] = 2,
		[WalkId] = 1,
		[RunId] = 1,
		[JumpId] = 0.5,
		[FallId] = 1,
	}, { [JumpId] = true })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(Modules.PoseCatalog, FullSlots)
	local Profile = RigProfile.Resolve("R15", {
		HasDistinctRun = true,
		HasSwimSlots = false,
	})
	local Session = Stub.Session(Humanoid, Profile, Catalog)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	T:Equal("the first jump is still unstreamed", Animator.Tracks[JumpId].Length, 0)

	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air
	Drive(Session, Animator, Humanoid, 8, 30)
	T:Near(
		"an unstreamed first jump still hands off to fall on time",
		Animator.Tracks[FallId].WeightTarget,
		1
	)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	Humanoid.StateName = "Freefall"
	Drive(Session, Animator, Humanoid, 8, 1)
	T:Near(
		"a directly chained second jump receives a fresh hold clock",
		Animator.Tracks[JumpId].WeightTarget,
		1
	)
end

do
	-- Bunny-hopping: the second jump lands inside the first jump's fade-out, so
	-- the live track is reused rather than reloaded. Stock replays the pose from
	-- the start every time, so the reused track has to be rewound - otherwise the
	-- second jump shows the tail of the first clip.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 6)
	local Jump = Animator.Tracks[JumpId]
	T:True("the first jump clip has advanced", Jump.TimePosition > 3 * Delta)

	Humanoid.StateName = "Running"
	Drive(Session, Animator, Humanoid, 8, 2)
	T:True("landing starts fading the jump out", Jump.WeightTarget <= 0.001)
	T:True("but the jump track is still live", Jump.IsPlaying)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	T:Equal("the second jump reuses the live track", Animator.LoadCallCounts[JumpId], 1)
	T:True("the second jump restarts the clip", Jump.TimePosition < Delta + Eps)
	T:Near("the second jump is at full weight", Jump.WeightTarget, 1)
end

do
	-- Takeover: stock's leftover track is unresolvable, so releasing by id left it
	-- playing and it survived into AnimBlend's session.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	local Leftover = Animator:AddStray(IdleId, 1)
	Modules.TrackDriver.StopAll(Animator, Session.Catalog.AllIds, 0)
	T:False("StopAll releases unresolvable copies too", Leftover.IsPlaying)
end

do
	-- Stock uses legacy http asset URLs while catalog IDs are normalized. They
	-- are one asset and must resolve to one live track.
	local NumericId = "rbxassetid://123456"
	local Animator = Stub.Animator({ [NumericId] = 2 })
	local StockTrack = Animator:AddStray("http://www.roblox.com/asset/?id=123456", 1)
	local Resolved = Modules.TrackDriver.Resolve(Animator, NumericId)
	T:Equal("normalized lookup reuses the stock track", Resolved, StockTrack)
	T:Equal("normalized lookup does not load a duplicate", Animator.LoadCallCounts[NumericId], nil)
end

do
	-- Match stock's bootstrap synchronously. Deferring prediction preparation
	-- races the first simulation frame after every respawn.
	local ClientModules = Stub.Build(nil, true)
	local Animator = Stub.Animator({ [IdleId] = 2 })
	local Humanoid = Stub.Humanoid(Animator)

	local Got = ClientModules.TrackDriver.EnsureAnimator(Humanoid)
	T:Equal("the client uses the replicated animator", Got, Animator)

	local Calls = ClientModules.RunService.PredictionCalls
	T:Equal("plain lookup does not mutate prediction", #Calls, 0)
	T:Equal("prepare returns the replicated animator", ClientModules.TrackDriver.PrepareAnimator(Humanoid), Animator)
	T:Equal("prediction is prepared synchronously", #Calls, 1)
	ClientModules.TrackDriver.PrepareAnimator(Humanoid)
	T:Equal("the animator is prepared once", #Calls, 1)

	local First = ClientModules.TrackDriver.Resolve(Animator, IdleId)
	local Second = ClientModules.TrackDriver.Resolve(Animator, IdleId)
	T:True("the client resolves a track on its first synchronized frame", First ~= nil)
	T:Equal("repeated resolution reuses the live track", Second, First)
end

do
	-- Warming is asset-only. No rollback-sensitive handle or dormant track may
	-- exist before the first synchronized simulation frame.
	local Id = "rbxassetid://warmOnly"
	local Animator = Stub.Animator({ [Id] = 0.5 })
	local Humanoid = Stub.Humanoid(Animator)
	Modules.TrackDriver.Warm(Humanoid, { Id, Id })
	T:Equal("warming leaves no dormant track", Animator.Tracks[Id], nil)

	Modules.TrackDriver.Drive(Animator, {
		Id = Id,
		Weight = 1,
		Rate = 1,
		Fade = 0.1,
		Looped = false,
		Sustain = false,
	})
	T:Equal("the synchronized drive creates exactly one live track", Animator.LoadCallCounts[Id], 1)
	T:True("the synchronized drive starts that track", Animator.Tracks[Id].IsPlaying)
end

do
	-- Server-authority animation control must be registered on Roblox's fixed,
	-- replayable simulation clock. This protects against accidentally restoring
	-- the old PostSimulation/PreRender split that made the first jump depend on
	-- which side happened to create its track first.
	local ServerModules = Stub.Build()
	ServerModules.AnimBlend.Init()
	T:Equal(
		"existing characters are catalogued before ownership handoff",
		ServerModules.CharacterBinder.Calls[1],
		"Start"
	)
	T:Equal(
		"ownership handoff follows the proven legacy startup order",
		ServerModules.CharacterBinder.Calls[2],
		"SetOwning:true"
	)
	T:Equal(
		"server authority binds the shared driver to simulation",
		#ServerModules.RunService.SimulationCallbacks,
		1
	)
	T:True(
		"server publishes readiness before clients initialize",
		ServerModules.Root:GetAttribute("AnimBlendServerReady") == true
	)
	-- Match stock's cadence and run one priority point later, making AnimBlend the
	-- deterministic final writer if stock bound before takeover.
	T:Equal(
		"server matches stock Animate's cadence",
		ServerModules.RunService.SimulationBindings[1].Frequency,
		Stub.Enum.StepFrequency.Hz60
	)
	T:Equal("server runs immediately after stock", ServerModules.RunService.SimulationBindings[1].Priority, 4001)

	-- The package has no Automatic-authority clock. The client waits for the
	-- server loader's readiness barrier and then mirrors the exact binding.
	local ClientModules = Stub.Build(nil, true)
	ClientModules.AnimBlend.Init()
	T:Equal(
		"client binds the mirrored driver to simulation",
		#ClientModules.RunService.SimulationCallbacks,
		1
	)
	T:Equal(
		"client matches the same cadence",
		ClientModules.RunService.SimulationBindings[1].Frequency,
		Stub.Enum.StepFrequency.Hz60
	)
	T:Equal("client matches the same ordering slot", ClientModules.RunService.SimulationBindings[1].Priority, 4001)
end

do
	-- The weight field's core promise: at every instant exactly one pose-worth
	-- of weight drives the rig. Too little and the rig drifts toward its rest
	-- pose (the mid-handover dip that reads as a snap); too much and two poses
	-- blend at once (the double-drive that reads as jitter). Sweep a realistic
	-- session and assert the commanded total never leaves a tight band.
	local Slots = {
		idle = { IdleId },
		walk = { WalkId },
		run = { RunId },
		jump = { JumpId },
		fall = { FallId },
	}
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")
	local Eps3 = 0.0001

	local Worst, Best = 0, math.huge
	local function Sweep(Frames)
		for _ = 1, Frames do
			AnimBlend.Step(Session)
			Stub.Advance(Animator, Delta)
			local Total = 0
			for _, Track in Animator.Tracks do
				if Track.IsPlaying then
					Total += Track.WeightTarget
				end
			end
			if Total > Worst then
				Worst = Total
			end
			if Total < Best then
				Best = Total
			end
		end
	end

	local function SetSpeed(Speed)
		Session.Root.AssemblyLinearVelocity = Stub.Vector3(Speed, 0, 0)
	end

	SetSpeed(0)
	Sweep(30)
	SetSpeed(1.2)
	Sweep(30)
	SetSpeed(8)
	Sweep(30)
	SetSpeed(15)
	Sweep(30)

	Humanoid.StateName = "Jumping"
	Sweep(2)
	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air
	Sweep(50)
	Humanoid.StateName = "Running"
	Humanoid.FloorMaterial = Stub.Enum.Material.Plastic
	Sweep(40)

	SetSpeed(0)
	Sweep(40)
	Humanoid.StateName = "Seated"
	Sweep(30)
	Humanoid.StateName = "Running"
	Sweep(40)

	-- Three sustain slots are floored at BlendEpsilon each, so the ceiling is
	-- one full pose plus those floors.
	T:True("the rig is never under-driven", Best > 0.95)
	T:True("the rig is never double-driven", Worst < 1 + 4 * Eps3 + 0.02)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 10)
	local Walk = Animator.Tracks[WalkId]
	local Action = Animator:LoadAnimation({ AnimationId = "rbxassetid://platformAction" })
	Action.Priority = Stub.Enum.AnimationPriority.Action
	Action:Play(0, 1, 1)

	Humanoid.PlatformStand = true
	Drive(Session, Animator, Humanoid, 8, 10)
	T:False("PlatformStand immediately releases locomotion", Walk.IsPlaying)
	T:True("PlatformStand leaves action tracks alone", Action.IsPlaying)
	T:Equal("PlatformStand does not restart locomotion", Animator.LoadCallCounts[WalkId], 1)

	-- Model Roblox rewinding the AnimationTrack while ordinary Lua table state
	-- remains at its latest value. The replayed step must release the live track
	-- again rather than trusting a remembered handoff flag.
	Walk.IsPlaying = true
	Walk.Forgotten = false
	Walk.WeightTarget = 1
	Walk.WeightCurrent = 1
	Drive(Session, Animator, Humanoid, 8, 10)
	T:False("PlatformStand handoff survives animation rollback", Walk.IsPlaying)
	T:Equal("rollback replay reapplies the handoff", Walk.StopCount, 2)

	Humanoid.PlatformStand = false
	Drive(Session, Animator, Humanoid, 8, 1)
	T:Equal("locomotion resumes after PlatformStand", Animator.LoadCallCounts[WalkId], 2)
	T:True("resumed locomotion is playing", Animator.Tracks[WalkId].IsPlaying)
end

for _, StateName in {
	"Dead",
	"FallingDown",
	"Flying",
	"GettingUp",
	"None",
	"Physics",
	"PlatformStanding",
	"Ragdoll",
} do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 10)
	local Walk = Animator.Tracks[WalkId]

	Humanoid.StateName = StateName
	Drive(Session, Animator, Humanoid, 8, 1)
	T:False(StateName .. " releases locomotion", Walk.IsPlaying)

	-- A correction can restore the AnimationTrack without rewinding Lua state.
	Walk.IsPlaying = true
	Walk.Forgotten = false
	Walk.WeightTarget = 1
	Walk.WeightCurrent = 1
	Drive(Session, Animator, Humanoid, 8, 1)
	T:False(StateName .. " release survives rollback", Walk.IsPlaying)
	T:Equal(StateName .. " replay reapplies release", Walk.StopCount, 2)

	Humanoid.StateName = "Running"
	Drive(Session, Animator, Humanoid, 8, 1)
	T:True(StateName .. " resumes locomotion", Animator.Tracks[WalkId].IsPlaying)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	local FirstStart = Humanoid:GetAttribute("AnimBlendJumpStartedAt")
	T:True("jump timing is stored on the predicted Humanoid", type(FirstStart) == "number")
	T:Equal("jump phase is rollback-visible", Humanoid:GetAttribute("AnimBlendJumpPhase"), "Jumping")

	Humanoid.StateName = "Physics"
	Drive(Session, Animator, Humanoid, 8, 10)
	T:Equal("handoff clears the jump start", Humanoid:GetAttribute("AnimBlendJumpStartedAt"), nil)
	T:Equal("handoff clears the jump phase", Humanoid:GetAttribute("AnimBlendJumpPhase"), nil)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	local NextStart = Humanoid:GetAttribute("AnimBlendJumpStartedAt")
	T:True("jump after handoff receives a fresh clock", type(NextStart) == "number" and NextStart > FirstStart)

	-- Rollback replays the same simulation frame more than once. The clock must
	-- not restart on a replay, or a corrected jump would keep re-arming the hold.
	AnimBlend.Step(Session)
	AnimBlend.Step(Session)
	T:Equal("replayed jump frames keep the original clock", Humanoid:GetAttribute("AnimBlendJumpStartedAt"), NextStart)

	Humanoid.StateName = "Freefall"
	Drive(Session, Animator, Humanoid, 8, 1)
	AnimBlend.Step(Session)
	T:Equal("freefall replay keeps the jump clock", Humanoid:GetAttribute("AnimBlendJumpStartedAt"), NextStart)
	T:Equal("freefall records the phase once", Humanoid:GetAttribute("AnimBlendJumpPhase"), "Freefall")
end

return T

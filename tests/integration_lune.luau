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
local WalkForwardId = "rbxassetid://walkForward"
local WalkBackwardId = "rbxassetid://walkBackward"
local WalkLeftId = "rbxassetid://walkLeft"
local WalkRightId = "rbxassetid://walkRight"
local RunForwardId = "rbxassetid://runForward"
local RunBackwardId = "rbxassetid://runBackward"
local RunLeftId = "rbxassetid://runLeft"
local RunRightId = "rbxassetid://runRight"

local Delta = 1 / 60
local Eps = 0.0001

local FullSlots = {
	idle = { IdleId },
	walk = { WalkId },
	run = { RunId },
	jump = { JumpId },
	fall = { FallId },
}

local DirectionalSlots = {
	idle = { { Id = IdleId } },
	walk = { { Id = WalkForwardId, Velocity = Stub.Vector2(0, 6.4) } },
	run = { { Id = RunForwardId, Velocity = Stub.Vector2(0, 16) } },
	walkBackward = { { Id = WalkBackwardId, Velocity = Stub.Vector2(0, -6.4) } },
	walkLeft = { { Id = WalkLeftId, Velocity = Stub.Vector2(-6.4, 0) } },
	walkRight = { { Id = WalkRightId, Velocity = Stub.Vector2(6.4, 0) } },
	runBackward = { { Id = RunBackwardId, Velocity = Stub.Vector2(0, -16) } },
	runLeft = { { Id = RunLeftId, Velocity = Stub.Vector2(-16, 0) } },
	runRight = { { Id = RunRightId, Velocity = Stub.Vector2(16, 0) } },
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
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Profile = RigProfile.Resolve(RigName, {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	})
	local Session = Stub.Session(Humanoid, Profile, Catalog)
	return Animator, Humanoid, Session
end

local function Weight(Animator, Id)
	local Track = Animator.Tracks[Id]
	if not Track or not Track.IsPlaying then
		return 0
	end
	return Track.WeightTarget
end

local function Drive(Session, Animator, Humanoid, Speed, Frames)
	for _ = 1, Frames do
		local Velocity = Stub.Vector3(Speed, 0, 0)
		Session.Root.AssemblyLinearVelocity = Velocity
		Humanoid.RelativeVelocity = Velocity
		Humanoid.MoveDirection = if Speed == 0 then Stub.Vector3(0, 0, 0) else Stub.Vector3(1, 0, 0)
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
	T:True(
		"an idle that has played remains live at the replication floor",
		Idle == nil or Idle.WeightTarget == 0.001
	)

	local BeforeSpam = Walk.Elapsed
	for _ = 1, 40 do
		Drive(Session, Animator, Humanoid, 12, 3)
		Drive(Session, Animator, Humanoid, 0.6, 3)
	end
	T:Equal("spam tapping never replays walk", Walk.PlayCount, 1)
	T:True("spam tapping keeps the gait cycling", Walk.Elapsed > BeforeSpam + 1.5)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Session.Root.AssemblyLinearVelocity = Stub.Vector3(8, 0, 0)
	Humanoid.RelativeVelocity = Stub.Vector3(0, 0, 0)
	Humanoid.MoveDirection = Stub.Vector3(0, 0, 0)
	for _ = 1, 5 do
		AnimBlend.Step(Session)
		Stub.Advance(Animator, Delta)
	end
	T:Near("r15 ignores floor and assembly motion at rest", Weight(Animator, IdleId), 1)
	T:Near("r15 does not walk on raw root motion", Weight(Animator, WalkId), 0)

	Session.Root.AssemblyLinearVelocity = Stub.Vector3(0, 0, 0)
	Humanoid.RelativeVelocity = Stub.Vector3(8, 0, 0)
	Humanoid.MoveDirection = Stub.Vector3(1, 0, 0)
	for _ = 1, 5 do
		AnimBlend.Step(Session)
		Stub.Advance(Animator, Delta)
	end
	T:True("r15 follows floor-relative movement", Weight(Animator, WalkId) > 0.4)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Session.Root.Size = Stub.Vector3(4, 4, 2)
	Humanoid.AutomaticScalingEnabled = false
	Humanoid.RelativeVelocity = Stub.Vector3(1, 0, 0)
	Humanoid.MoveDirection = Stub.Vector3(1, 0, 0)
	AnimBlend.Step(Session)
	T:Near("manually scaled r15 derives its gate from live geometry", Weight(Animator, IdleId), 1)

	Session.Root.Size = Stub.Vector3(2, 2, 1)
	Humanoid.AutomaticScalingEnabled = true
	Humanoid.HipHeight = 4
	AnimBlend.Step(Session)
	T:Near("automatically scaled r15 derives its gate from hip height", Weight(Animator, IdleId), 1)

	Humanoid.RelativeVelocity = Stub.Vector3(2, 0, 0)
	AnimBlend.Step(Session)
	T:True("scaled r15 walks once relative speed clears its gate", Weight(Animator, WalkId) > 0.4)
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
	-- Releasing is not replaying: a pose re-entering inside its fade still holds
	-- weight, so it carries its cycle over as stock's carryOverTimePosition does.
	T:Equal("tapping across the gate never replays idle", Animator.Tracks[IdleId].PlayCount, 1)
end

do
	local Lengths = { [IdleId] = 2 }
	for _, Group in DirectionalSlots do
		for _, Entry in Group do
			Lengths[Entry.Id] = 1
		end
	end
	local Animator = Stub.Animator(Lengths)
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Modules.PoseCatalog.Build(Stub.BuildAnimate(DirectionalSlots))
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Profile = RigProfile.Resolve("R15", {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	})
	local Session = Stub.Session(Humanoid, Profile, Catalog)
	Humanoid.RelativeVelocity = Stub.Vector3(0, 0, -6.4)
	Humanoid.MoveDirection = Stub.Vector3(0, 0, -1)

	T:True(
		"complete LinearVelocity catalog enables stock directional blending",
		Catalog.HasDirectional
	)
	T:Equal("directional catalog includes animations outside named slots", #Catalog.Directional, 8)
	local Incomplete = Modules.PoseCatalog.Build(Stub.BuildAnimate({
		walk = DirectionalSlots.walk,
		run = DirectionalSlots.run,
	}))
	T:False(
		"incomplete direction metadata keeps legacy walk and run behavior",
		Incomplete.HasDirectional
	)
	T:Equal("incomplete direction metadata does not expand the track set", #Incomplete.AllIds, 2)

	local SharedPhaseObserved = false
	local PreviousForward = math.huge
	for Frame = 0, 90 do
		local Angle = math.rad(Frame)
		Session.Root.CFrame = {
			RightVector = Stub.Vector3(math.cos(Angle), 0, -math.sin(Angle)),
			LookVector = Stub.Vector3(-math.sin(Angle), 0, -math.cos(Angle)),
		}
		AnimBlend.Step(Session)
		Stub.Advance(Animator, Delta)

		local Forward = Weight(Animator, WalkForwardId)
		local Right = Weight(Animator, WalkRightId)
		T:True(
			"shift-lock rotation never snaps the forward blend upward",
			Forward <= PreviousForward + Eps
		)
		PreviousForward = Forward
		if Forward > 0.01 and Right > 0.01 then
			local ForwardTrack = Animator.Tracks[WalkForwardId]
			local RightTrack = Animator.Tracks[WalkRightId]
			local PhaseDistance = math.abs(ForwardTrack.TimePosition - RightTrack.TimePosition)
			PhaseDistance = math.min(PhaseDistance, 1 - PhaseDistance)
			T:True("new strafe tracks join the live gait phase", PhaseDistance < Delta + Eps)
			SharedPhaseObserved = true
		end
	end

	T:True("rotation crossfades through a shared directional phase", SharedPhaseObserved)
	T:True("quarter turn reaches the right strafe pose", Weight(Animator, WalkRightId) > 0.9)
	T:True(
		"quarter turn releases forward to the replication floor",
		Weight(Animator, WalkForwardId) <= 0.001
	)
	T:Equal("rotation never restarts the forward gait", Animator.Tracks[WalkForwardId].PlayCount, 1)
	T:Equal("rotation never restarts the right gait", Animator.Tracks[WalkRightId].PlayCount, 1)

	local NearGate = {}
	local PastGate = {}
	local function SolveAngle(Degrees, Weights)
		local Angle = math.rad(Degrees)
		Modules.DirectionalSolver.Solve(
			math.sin(Angle) * 6.4,
			math.cos(Angle) * 6.4,
			1,
			Catalog.Directional,
			Weights
		)
	end
	SolveAngle(9, NearGate)
	SolveAngle(9.1, PastGate)
	local GateDelta = 0
	for Index = 1, #Catalog.Directional do
		GateDelta += math.abs((NearGate[Index] or 0) - (PastGate[Index] or 0))
	end
	T:True("sub-degree yaw corrections cannot jump the directional pose", GateDelta < 0.005)

	local Decoded = Modules.PoseCatalog.Decode(Modules.PoseCatalog.Encode(Catalog))
	T:True(
		"directional catalog replicates to the owning client",
		Decoded ~= nil and Decoded.HasDirectional
	)
	T:Equal("replicated directional catalog preserves every motion sample", #Decoded.Directional, 8)
	local DecodedRight = nil
	for _, Entry in Decoded.Directional do
		if Entry.Id == WalkRightId then
			DecodedRight = Entry
			break
		end
	end
	T:True("replicated right strafe sample remains addressable", DecodedRight ~= nil)
	if DecodedRight then
		T:Near("replicated right strafe velocity is exact", DecodedRight.Velocity.X, 6.4)
	end
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 1.25, 20)
	local Walk = Animator.Tracks[WalkId]
	local Idle = Animator.Tracks[IdleId]

	-- Stock has no idle/walk cross-blend: past the gate, walk owns the pose.
	T:Near("past the gate walk owns the pose", Walk.WeightTarget, 1)
	T:True("and idle contributes at most the replication floor", Weight(Animator, IdleId) <= 0.001)
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 30)
	local Walk = Animator.Tracks[WalkId]
	local Resting = Walk.Elapsed

	Drive(Session, Animator, Humanoid, 0, 60)
	T:Near("stopping retains walk at the replication floor", Weight(Animator, WalkId), 0.001)
	T:Near("stopping raises idle to full", Weight(Animator, IdleId), 1)
	T:True("walk leaves over its pose fade, never cut", Walk.LastWeightFade > 0)
	T:True("walk keeps cycling through the release fade", Walk.Elapsed > Resting)

	Drive(Session, Animator, Humanoid, 8, 10)
	T:True("resuming restores walk weight", Weight(Animator, WalkId) > 0.4)
	T:True("resuming re-enters through a Play", Animator.Tracks[WalkId].IsPlaying)
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
	T:Near("walk is retained once run owns the pose", Weight(Animator, WalkId), 0.001)
end

do
	-- Stock blends walk/run with AdjustWeight's default while both clips are
	-- visible, spending the pose transition time only when a pose enters or
	-- leaves. Passing the pose fade every step made the weights lag twice as far.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	local Walk = Animator.Tracks[WalkId]
	local Run = Animator.Tracks[RunId]
	T:True(
		"both clips are visible inside the band",
		Walk.WeightTarget > 0.01 and Run.WeightTarget > 0.01
	)

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
	T:Near("walk is retained through the airborne pose", Walk.WeightTarget, 0.001)

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
	T:Equal(
		"a stopped transient pose is legitimately reloaded, not cached",
		Animator.LoadCallCounts[JumpId],
		2
	)
end

do
	-- Roblox's Animator:GetTrackByAnimationId can stop returning a track once it
	-- has fully stopped and settled (modeled by the stub's Forgotten flag). That
	-- stopped handle must be forgotten and loaded fresh on the next cycle, while
	-- a continuously live pose must keep resolving to the engine's current track
	-- without extra loads.
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
	T:Equal(
		"the live jump track was played once, not per step",
		Animator.Tracks[JumpId].PlayCount,
		1
	)
	T:Equal(
		"the live fall track was played once, not per step",
		Animator.Tracks[FallId].PlayCount,
		1
	)
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

	local Field = Restored.WeightTarget
	Restored:AdjustWeight(Field - 0.3, 0)
	Drive(Session, Animator, Humanoid, 8, 2)
	T:Near("a rewound weight is corrected back to the field", Restored.WeightTarget, Field)
end

do
	local R6Slots = { idle = { IdleId }, walk = { WalkId }, jump = { JumpId }, fall = { FallId } }
	local Animator, Humanoid, Session = NewWorld(R6Slots, "R6")
	Humanoid.HipHeight = 0
	Humanoid.AutomaticScalingEnabled = true
	Session.Root.AssemblyLinearVelocity = Stub.Vector3(0.01372, 0, 0)
	Humanoid.RelativeVelocity = Stub.Vector3(0, 0, 0)
	Humanoid.MoveDirection = Stub.Vector3(0, 0, 0)
	for _ = 1, 5 do
		AnimBlend.Step(Session)
		Stub.Advance(Animator, Delta)
	end
	T:Near("r6 ignores server-authority root drift", Weight(Animator, IdleId), 1)
	T:Near("r6 drift releases walk", Weight(Animator, WalkId), 0)

	Drive(Session, Animator, Humanoid, 40, 30)

	local Walk = Animator.Tracks[WalkId]
	T:Equal("r6 walk plays once", Walk.PlayCount, 1)
	T:Equal("r6 loads no run track", Animator.Tracks[RunId], nil)
	T:Near("r6 walk stays at full weight", Walk.WeightTarget, 1)
	T:Near("r6 rate uses the 14.5 divisor", Walk.Speed, 40 / 14.5)

	Session.Root.Size = Stub.Vector3(4, 4, 2)
	Drive(Session, Animator, Humanoid, 29, 5)
	T:Near("r6 derives uniform scale from its live root", Walk.Speed, 1)
	Session.Root.Size = Stub.Vector3(2, 2, 1)

	Drive(Session, Animator, Humanoid, 0, 60)
	T:Near("r6 idles when stopped", Weight(Animator, IdleId), 1)
	T:Equal("r6 idle uses the r6 fade", Animator.Tracks[IdleId].LastPlayFade, 0.1)

	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air
	Drive(Session, Animator, Humanoid, 0, 60)
	T:Near("r6 falls", Weight(Animator, FallId), 1)
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
	T:True("locomotion remains live under the emote", Walk.WeightTarget > 0.4)
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
	local Catalog = Stub.Catalog(
		Modules.PoseCatalog,
		{ idle = { IdleA, IdleB }, walk = { WalkId }, run = { RunId } }
	)
	Modules.TrackDriver.Prepare(Catalog.AllIds)
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
	T:Equal("jump fades out over the incoming fall fade", Jump.LastStopFade, 0.2)
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
	local Plain = "rbxassetid://920001"
	local Alt = "rbxassetid://920002"
	local Animator = Stub.Animator({ [Plain] = 1, [Alt] = 1.5, [WalkId] = 1, [RunId] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(
		Modules.PoseCatalog,
		{ idle = { Plain, Alt }, walk = { WalkId }, run = { RunId } },
		{ [Plain] = 9, [Alt] = 1 }
	)
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Profile = RigProfile.Resolve("R15", { HasDistinctRun = true, HasSwimSlots = false })
	local Session = Stub.Session(Humanoid, Profile, Catalog)

	Drive(Session, Animator, Humanoid, 8, 3600)
	local AltTrack = Animator.Tracks[Alt]
	T:Equal(
		"the alternate idle is never played while moving",
		AltTrack == nil or AltTrack.PlayCount == 0,
		true
	)
	-- No idle variant is held open while moving: a pose nobody can see costs a
	-- viewer the whole rig once replication drops the track.
	T:Near("no idle variant is left open while moving", Weight(Animator, Plain), 0)

	local BaseBucket = math.floor(Stub.Now() / 8)
	for Seed = 0, 100 do
		if Modules.PoseCatalog.Pick(Catalog, "idle", BaseBucket + Seed) == Alt then
			Session.Seed = Seed
			break
		end
	end
	Drive(Session, Animator, Humanoid, 0, 12)
	T:True("stopping starts on the primary idle", Weight(Animator, Plain) > 0.5)
	T:Equal("stopping never snaps straight into an alternate idle", Animator.Tracks[Alt], nil)
end

do
	local Plain = "rbxassetid://910001"
	local Alt = "rbxassetid://910002"
	local Animator = Stub.Animator({ [Plain] = 1, [Alt] = 1.5, [WalkId] = 1, [RunId] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(
		Modules.PoseCatalog,
		{ idle = { Plain, Alt }, walk = { WalkId }, run = { RunId } },
		{ [Plain] = 9, [Alt] = 1 }
	)
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Profile = RigProfile.Resolve("R15", { HasDistinctRun = true, HasSwimSlots = false })
	local Session = Stub.Session(Humanoid, Profile, Catalog)
	local BaseBucket = math.floor(Stub.Now() / 8)
	for Seed = 0, 100 do
		if Modules.PoseCatalog.Pick(Catalog, "idle", BaseBucket + Seed + 1) == Alt then
			Session.Seed = Seed
			break
		end
	end

	Drive(Session, Animator, Humanoid, 0, 3600)
	local AltTrack = Animator.Tracks[Alt]
	T:True(
		"standing still long enough does reach an alternate",
		AltTrack ~= nil and AltTrack.PlayCount > 0
	)
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
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	T:Equal("jump is the only slot borrowing idle", Catalog.SlotIds.jump[1], IdleId)
	local Profile = RigProfile.Resolve("R15", { HasDistinctRun = false, HasSwimSlots = true })
	local Session = Stub.Session(Humanoid, Profile, Catalog)

	Drive(Session, Animator, Humanoid, 8, 30)
	T:Near("a rig with no jump animation releases idle while walking", Weight(Animator, IdleId), 0)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	local Idle = Animator.Tracks[IdleId]
	T:True("borrowing idle for jump must not make it one-shot", Idle.Looped)

	-- fall owns its own clip here, so once jump ends the borrowed idle is no longer
	-- any pose's clip and is released rather than parked where no viewer can see it.
	Humanoid.StateName = "Freefall"
	Humanoid.FloorMaterial = Stub.Enum.Material.Air
	Drive(Session, Animator, Humanoid, 8, 120)
	T:Near(
		"the borrowed track is retained once fall owns the pose",
		Weight(Animator, IdleId),
		0.001
	)
	T:True("the dedicated fall clip owns the airborne pose", Weight(Animator, FallId2) > 0.5)
	T:True("the borrowed track is still looping", Animator.Tracks[IdleId].Looped)

	Humanoid.StateName = "Running"
	Humanoid.FloorMaterial = Stub.Enum.Material.Plastic
	Drive(Session, Animator, Humanoid, 8, 60)
	local Walk = Animator.Tracks[WalkId]
	T:True("locomotion recovers after landing on a bare rig", Walk.WeightTarget > 0.4)
	T:Equal("the bare rig never restarts its walk", Walk.PlayCount, 1)
end

do
	-- Actions are composed by Roblox per joint. AnimBlend must keep the gait alive underneath:
	-- upper-body clips expose it on the legs, while full-body clips override it themselves.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	local Walk = Animator.Tracks[WalkId]
	local Run = Animator.Tracks[RunId]
	T:True("walk is active before an action", Walk.IsPlaying and Walk.WeightTarget > 0.4)
	local WalkWeight = Walk.WeightTarget
	local RunWeight = Run.WeightTarget

	local ActionId = "rbxassetid://actiontest"
	local Emote = Animator:LoadAnimation({ AnimationId = ActionId })
	Emote.Priority = Stub.Enum.AnimationPriority.Action
	Emote:Play(0, 1, 1)
	Drive(Session, Animator, Humanoid, 8, 10)
	T:True("locomotion stays live beneath an action", Walk.IsPlaying)
	T:Near("an action does not change the walk field", Walk.WeightTarget, WalkWeight)
	T:Near("an action does not change the run field", Run.WeightTarget, RunWeight)
	T:Near("the locomotion blend remains normalized", Walk.WeightTarget + Run.WeightTarget, 1)
	T:Equal("AnimBlend never stops an action track", Emote.StopCount, 0)
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
	T:Equal(
		"a stopped track reports nil, not a stale handle",
		Modules.TrackDriver.Find(Animator, Id),
		nil
	)
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
	Modules.TrackDriver.Prepare(Catalog.AllIds)
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
	Modules.TrackDriver.Prepare(Catalog.AllIds)
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
	T:Near("an unstreamed first jump still hands off to fall on time", Weight(Animator, FallId), 1)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	Humanoid.StateName = "Freefall"
	Drive(Session, Animator, Humanoid, 8, 1)
	T:Near(
		"a directly chained second jump receives a fresh hold clock",
		Weight(Animator, JumpId),
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
	local Legacy = "http://www.roblox.com/asset/?id=123456"
	local Catalog = Stub.Catalog(Modules.PoseCatalog, { idle = { Legacy }, walk = { WalkId } })
	T:Equal("legacy catalog IDs are canonicalized", Catalog.AllIds[1], "rbxassetid://123456")
	local Encoded = Modules.PoseCatalog.Encode(Catalog)
	local Decoded = Modules.PoseCatalog.Decode(Encoded)
	T:True("published catalogs decode", Decoded ~= nil)
	T:Equal(
		"published catalogs preserve idle IDs",
		Decoded.SlotIds.idle[1],
		Catalog.SlotIds.idle[1]
	)
	T:Equal(
		"published catalogs preserve walk IDs",
		Decoded.SlotIds.walk[1],
		Catalog.SlotIds.walk[1]
	)
	T:Equal(
		"malformed published catalogs are rejected",
		Modules.PoseCatalog.Decode("idle\tbad\tzero"),
		nil
	)
end

do
	local ServerModules = Stub.Build()
	local Old = Stub.Animator()
	local Humanoid = Stub.Humanoid(Old)
	Old.Parent = Humanoid
	local Track = Old:LoadAnimation({ AnimationId = IdleId })
	Track:Play(0, 1, 1)

	local Owned = ServerModules.TrackDriver.TakeOwnership(Humanoid)
	T:True("takeover replaces the stock animator", Owned ~= nil and Owned ~= Old)
	T:True("takeover marks the replacement", ServerModules.TrackDriver.IsOwned(Owned))
	T:True("takeover preserves scalable animation LOD by default", Owned.PreferLodEnabled)
	T:Equal(
		"takeover installs the replacement on the humanoid",
		Humanoid:FindFirstChildOfClass("Animator"),
		Owned
	)
	T:False("takeover stops stock playback", Track.IsPlaying)
	T:Equal("takeover destroys the stock animator", Old.Parent, nil)
	T:Equal("takeover is idempotent", ServerModules.TrackDriver.TakeOwnership(Humanoid), Owned)
	T:True("idempotent takeover preserves the configured LOD policy", Owned.PreferLodEnabled)
end

do
	local Ids = {}
	for Index = 1, 10 do
		Ids[Index] = "rbxassetid://budget" .. tostring(Index)
	end
	Modules.TrackDriver.Prepare(Ids)
	local Animator = Stub.Animator()
	local Previous = nil
	for _, Id in Ids do
		if Previous then
			Modules.TrackDriver.Drive(Animator, {
				Id = Previous,
				Weight = 0,
				Rate = 1,
				Fade = 10,
				Looped = true,
				Sustain = false,
			})
		end
		Modules.TrackDriver.Drive(Animator, {
			Id = Id,
			Weight = 1,
			Rate = 1,
			Fade = 0.1,
			Looped = true,
			Sustain = false,
		})
		local Managed = 0
		for _, Track in Animator:GetPlayingAnimationTracks() do
			if
				Track.Priority == Stub.Enum.AnimationPriority.Core
				or Track.Priority == Stub.Enum.AnimationPriority.Idle
			then
				Managed += 1
			end
		end
		T:True("managed playback stays below the Animator limit", Managed <= 4)
		Previous = Id
	end
end

do
	local ServerModules = Stub.Build(nil, false, true)
	local EmptyAnimator = Stub.Animator()
	local EmptyHumanoid = Stub.Humanoid(EmptyAnimator)
	EmptyAnimator.Parent = EmptyHumanoid
	local EmptyCatalog = ServerModules.PoseCatalog.Build(nil)
	local EmptySession = Stub.Session(
		EmptyHumanoid,
		RigProfile.Resolve("R15", {
			HasDistinctRun = false,
			HasSwimSlots = false,
		}),
		EmptyCatalog
	)
	ServerModules.CharacterBinder.Rebuild(EmptySession)
	T:Equal(
		"server waits for a real catalog before takeover",
		EmptyHumanoid:FindFirstChildOfClass("Animator"),
		EmptyAnimator
	)
	T:False(
		"an empty catalog never claims the stock animator",
		ServerModules.TrackDriver.IsOwned(EmptyAnimator)
	)

	local Old = Stub.Animator()
	local Humanoid = Stub.Humanoid(Old)
	Old.Parent = Humanoid
	local Animate = Stub.BuildAnimate({
		idle = { { Id = IdleId } },
		walk = { { Id = WalkId } },
	})
	local Initial = ServerModules.PoseCatalog.Build(Animate)
	local Session = Stub.Session(
		Humanoid,
		RigProfile.Resolve("R15", {
			HasDistinctRun = false,
			HasSwimSlots = false,
		}),
		Initial
	)
	Session.Animate = Animate

	ServerModules.CharacterBinder.Rebuild(Session)
	local Owned = Humanoid:FindFirstChildOfClass("Animator")
	local PublishedCatalog = Session.Character:FindFirstChild("AnimBlendCatalog")
	local Signature = PublishedCatalog and PublishedCatalog.Value
	T:True("server publishes the owned animation catalog", type(Signature) == "string")
	T:Equal("server session records the published catalog", Session.CatalogSignature, Signature)

	local ClientModules = Stub.Build(nil, true, true)
	local ClientAnimator = Stub.Animator()
	ClientAnimator:SetAttribute("AnimBlendOwned", true)
	local ClientHumanoid = Stub.Humanoid(ClientAnimator)
	local ClientSession = Stub.Session(
		ClientHumanoid,
		RigProfile.Resolve("R15", {
			HasDistinctRun = false,
			HasSwimSlots = false,
		}),
		ClientModules.PoseCatalog.Build(nil)
	)
	T:False(
		"client does not drive before the server catalog arrives",
		ClientModules.CharacterBinder.ShouldDrive(ClientSession)
	)
	ClientSession.Character:AddChild({
		Name = "AnimBlendCatalog",
		Value = Signature,
		Changed = Stub.Event(),
		IsA = function(_, ClassName)
			return ClassName == "StringValue"
		end,
	})
	ClientModules.CharacterBinder.Rebuild(ClientSession)
	T:Equal(
		"client accepts only the server catalog signature",
		ClientSession.CatalogSignature,
		Signature
	)
	T:Equal("client receives the server idle asset", ClientSession.Catalog.SlotIds.idle[1], IdleId)
	T:Equal("client receives the server walk asset", ClientSession.Catalog.SlotIds.walk[1], WalkId)
	T:True(
		"client drives after accepting the exact server catalog",
		ClientModules.CharacterBinder.ShouldDrive(ClientSession)
	)
end

do
	local SwimId = "rbxassetid://swim"
	local SwimIdleId = "rbxassetid://swimidle"
	local Slots =
		{ idle = { IdleId }, walk = { WalkId }, swim = { SwimId }, swimidle = { SwimIdleId } }
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")
	Humanoid.StateName = "Swimming"
	Drive(Session, Animator, Humanoid, 2, 1)
	T:Equal(
		"swim hysteresis enters synchronized root state",
		Session.Root:GetAttribute("AnimBlendSwimActive"),
		true
	)
	Drive(Session, Animator, Humanoid, 1, 1)
	T:True(
		"synchronized swim hysteresis holds through the deadband",
		Animator.Tracks[SwimId].IsPlaying
	)
	Humanoid.StateName = "Running"
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"leaving swim clears synchronized root state",
		Session.Root:GetAttribute("AnimBlendSwimActive"),
		nil
	)
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
	T:Equal(
		"prepare returns the replicated animator",
		ClientModules.TrackDriver.PrepareAnimator(Humanoid),
		Animator
	)
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
	local ServerModules, ServerWorkspace = Stub.Build()
	local ServerCanReadAuthorityMode = pcall(function()
		return ServerWorkspace.AuthorityMode
	end)
	T:False(
		"server code never relies on RobloxScriptSecurity AuthorityMode",
		ServerCanReadAuthorityMode
	)
	ServerModules.AnimBlend.Init()
	T:Equal(
		"existing characters are catalogued before ownership handoff",
		ServerModules.CharacterBinder.Calls[1],
		"Start"
	)
	T:Equal(
		"always-on startup has no ownership toggle pass",
		#ServerModules.CharacterBinder.Calls,
		1
	)
	T:Equal(
		"server authority binds the shared driver to simulation",
		#ServerModules.RunService.SimulationCallbacks,
		1
	)
	T:Equal(
		"server corrects presentation after simulation",
		ServerModules.RunService.PostSimulation.ConnectCount,
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
	T:Equal(
		"server runs immediately after stock",
		ServerModules.RunService.SimulationBindings[1].Priority,
		4001
	)

	-- The package has no Automatic-authority clock. The client waits for the
	-- server loader's readiness barrier and then mirrors the exact binding.
	local ClientModules, ClientWorkspace = Stub.Build(nil, true)
	local ClientCanReadAuthorityMode = pcall(function()
		return ClientWorkspace.AuthorityMode
	end)
	T:False(
		"client code never relies on RobloxScriptSecurity AuthorityMode",
		ClientCanReadAuthorityMode
	)
	ClientModules.AnimBlend.Init()
	T:Equal(
		"client binds the mirrored driver to simulation",
		#ClientModules.RunService.SimulationCallbacks,
		1
	)
	T:Equal(
		"client corrects presentation after simulation",
		ClientModules.RunService.PostSimulation.ConnectCount,
		1
	)
	T:Equal(
		"client matches the same cadence",
		ClientModules.RunService.SimulationBindings[1].Frequency,
		Stub.Enum.StepFrequency.Hz60
	)
	T:Equal(
		"client matches the same ordering slot",
		ClientModules.RunService.SimulationBindings[1].Priority,
		4001
	)
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
	Session.Root:SetAttribute("AnimBlendWalkCycle", 0.75)

	Humanoid.PlatformStand = true
	Humanoid.StateName = "PlatformStanding"
	Drive(Session, Animator, Humanoid, 8, 10)
	T:False("PlatformStand immediately releases locomotion", Walk.IsPlaying)
	T:True("PlatformStand leaves action tracks alone", Action.IsPlaying)
	T:Equal("PlatformStand does not restart locomotion", Animator.LoadCallCounts[WalkId], 1)
	T:Equal(
		"PlatformStand clears stale gait phase",
		Session.Root:GetAttribute("AnimBlendWalkCycle"),
		nil
	)

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
	Humanoid.StateName = "Running"
	Drive(Session, Animator, Humanoid, 8, 1)
	T:Equal("locomotion resumes after PlatformStand", Animator.LoadCallCounts[WalkId], 2)
	T:True("resumed locomotion is playing", Animator.Tracks[WalkId].IsPlaying)
end

for _, StateName in
	{
		"Dead",
		"FallingDown",
		"Flying",
		"GettingUp",
		"None",
		"Physics",
		"PlatformStanding",
		"Ragdoll",
	}
do
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
	local FirstStart = Session.Root:GetAttribute("AnimBlendJumpStartedAt")
	T:True("jump timing is stored on the predicted root", type(FirstStart) == "number")
	T:Equal(
		"jump phase is rollback-visible",
		Session.Root:GetAttribute("AnimBlendJumpPhase"),
		"Jumping"
	)

	Humanoid.StateName = "Physics"
	Drive(Session, Animator, Humanoid, 8, 10)
	T:Equal(
		"handoff clears the jump start",
		Session.Root:GetAttribute("AnimBlendJumpStartedAt"),
		nil
	)
	T:Equal("handoff clears the jump phase", Session.Root:GetAttribute("AnimBlendJumpPhase"), nil)

	Humanoid.StateName = "Jumping"
	Drive(Session, Animator, Humanoid, 8, 1)
	local NextStart = Session.Root:GetAttribute("AnimBlendJumpStartedAt")
	T:True(
		"jump after handoff receives a fresh clock",
		type(NextStart) == "number" and NextStart > FirstStart
	)

	-- Rollback replays the same simulation frame more than once. The clock must
	-- not restart on a replay, or a corrected jump would keep re-arming the hold.
	AnimBlend.Step(Session)
	AnimBlend.Step(Session)
	T:Equal(
		"replayed jump frames keep the original clock",
		Session.Root:GetAttribute("AnimBlendJumpStartedAt"),
		NextStart
	)

	Humanoid.StateName = "Freefall"
	Drive(Session, Animator, Humanoid, 8, 1)
	AnimBlend.Step(Session)
	T:Equal(
		"freefall replay keeps the jump clock",
		Session.Root:GetAttribute("AnimBlendJumpStartedAt"),
		NextStart
	)
	T:Equal(
		"freefall records the phase once",
		Session.Root:GetAttribute("AnimBlendJumpPhase"),
		"Freefall"
	)
end

-- Rollback restores predicted instances, not the engine's AnimationTrack set, so
-- the variant roll must be derivable rather than latched off a live track. Two
-- peers running out of phase have to reach the same clip, and a replayed frame
-- has to re-roll what the authoritative pass rolled.
do
	local IdleA = "rbxassetid://930001"
	local IdleB = "rbxassetid://930002"
	local Slots = { idle = { IdleA, IdleB }, walk = { WalkId }, run = { RunId } }

	local function Peer()
		local Animator = Stub.Animator({ [IdleA] = 2, [IdleB] = 3, [WalkId] = 1, [RunId] = 1 })
		local Humanoid = Stub.Humanoid(Animator)
		local Catalog = Stub.Catalog(Modules.PoseCatalog, Slots)
		Modules.TrackDriver.Prepare(Catalog.AllIds)
		local Profile = RigProfile.Resolve("R15", {
			HasDistinctRun = Catalog.HasDistinctRun,
			HasSwimSlots = Catalog.HasSwimSlots,
		})
		return Animator, Humanoid, Stub.Session(Humanoid, Profile, Catalog)
	end

	local AnimatorA, HumanoidA, SessionA = Peer()
	local AnimatorB, HumanoidB, SessionB = Peer()
	SessionB.Root = SessionA.Root

	local function Chosen(Animator)
		for _, Id in { IdleA, IdleB } do
			local Track = Animator.Tracks[Id]
			if Track and Track.WeightTarget > 0.5 then
				return Id
			end
		end
		return nil
	end

	Drive(SessionB, AnimatorB, HumanoidB, 0, 17)
	for _ = 1, 600 do
		AnimBlend.Step(SessionA)
		AnimBlend.Step(SessionB)
		Stub.Advance(AnimatorA, Delta)
		Stub.Advance(AnimatorB, Delta)
	end

	T:True("a variant is chosen", Chosen(AnimatorA) ~= nil)
	T:Equal("out-of-phase peers agree on the variant", Chosen(AnimatorA), Chosen(AnimatorB))
	T:Equal(
		"the roll commits nothing to the predicted root",
		SessionA.Root:GetAttribute("AnimBlendVariantidle"),
		nil
	)

	local Repeated = Chosen(AnimatorA)
	for _ = 1, 8 do
		AnimBlend.Step(SessionA)
	end
	T:Equal("replaying a frame re-rolls the same variant", Chosen(AnimatorA), Repeated)
end

-- A peer that does not simulate the character must write nothing, or it fights
-- replication from the peer that does.
do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 30)
	T:True("the driving peer writes tracks", Weight(Animator, WalkId) > 0.5)

	local Walk = Weight(Animator, WalkId)
	local Idle = Weight(Animator, IdleId)
	Session.Drives = false
	Drive(Session, Animator, Humanoid, 0, 30)
	T:Near("a non-driving peer leaves the walk weight untouched", Weight(Animator, WalkId), Walk)
	T:Near("a non-driving peer leaves the idle weight untouched", Weight(Animator, IdleId), Idle)
end

-- The replication contract. Measured against a live server in Studio: a track
-- driven by a per-step stream of AdjustWeight calls is dropped outright by every
-- viewer that is not simulating the character, and once dropped only a fresh Play
-- restores it. So the driver must command sparsely and must never leave a track
-- parked at zero weight waiting for a nudge that can no longer reach anyone.
do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 20)
	local Walk = Animator.Tracks[WalkId]

	local Weights = Walk.WeightCalls
	local Speeds = Walk.SpeedCalls
	Drive(Session, Animator, Humanoid, 8, 120)
	T:True("a steady gait does not stream weight commands", Walk.WeightCalls - Weights <= 4)
	T:True("a steady gait does not stream speed commands", Walk.SpeedCalls - Speeds <= 4)
	T:Near(
		"and the weight still holds its field value",
		Weight(Animator, WalkId),
		Walk.WeightTarget
	)

	-- A blend still has to land its endpoint exactly, or the pose never reaches
	-- full weight and the rig drifts toward its rest pose.
	Drive(Session, Animator, Humanoid, 24, 60)
	T:Near("a blend still lands full weight exactly", Weight(Animator, RunId), 1)
end

do
	-- Sweep a whole locomotion cycle and assert no managed track is ever left
	-- playing at zero weight.
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	local States = { "Running", "Jumping", "Freefall", "Running", "Seated", "Running" }
	for _, StateName in States do
		Humanoid.StateName = StateName
		Humanoid.FloorMaterial = if StateName == "Freefall"
			then Stub.Enum.Material.Air
			else Stub.Enum.Material.Plastic
		for _, Speed in { 0, 6, 16, 0 } do
			Drive(Session, Animator, Humanoid, Speed, 20)
			for _, Id in Session.Catalog.AllIds do
				local Track = Animator.Tracks[Id]
				if Track and Track.IsPlaying then
					T:True(
						"no track is parked at zero weight in " .. StateName,
						Track.WeightTarget > 0.0009
					)
				end
			end
		end
	end
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	local LastCycle = 0

	for Tap = 1, 8 do
		Drive(Session, Animator, Humanoid, 8, 1)
		local Walk = Animator.Tracks[WalkId]
		local Cycle = Walk.TimePosition / Walk.Length
		T:True("separated tap " .. Tap .. " advances the walk cycle", Cycle > LastCycle)
		LastCycle = Cycle
		Drive(Session, Animator, Humanoid, 0, 30)
	end
end

do
	local Animator, Humanoid, Session = NewWorld(FullSlots, "R15")
	Drive(Session, Animator, Humanoid, 8, 30)
	local Walk = Animator.Tracks[WalkId]
	local Stops = Walk.StopCount
	local Loads = Animator.LoadCallCounts[WalkId]
	local Plays = Walk.PlayCount

	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal("a gait handoff does not stop the replicated walk", Walk.StopCount, Stops)
	T:True(
		"a gait handoff fades instead of snapping",
		Walk.WeightCurrent > 0.001 and Walk.WeightCurrent < 1
	)

	Drive(Session, Animator, Humanoid, 0, 30)
	T:True("the outgoing gait remains replicated", Walk.IsPlaying)
	T:Near("the outgoing gait settles on a visible-safe floor", Walk.WeightTarget, 0.001)

	Drive(Session, Animator, Humanoid, 8, 2)
	T:Equal("resuming gait reuses the replicated track", Animator.Tracks[WalkId], Walk)
	T:Equal("resuming gait does not reload the animation", Animator.LoadCallCounts[WalkId], Loads)
	T:Equal("resuming gait does not replay the animation", Walk.PlayCount, Plays)

	Drive(Session, Animator, Humanoid, 24, 30)
	local FloorSpeedCalls = Walk.SpeedCalls
	for _ = 1, 20 do
		Drive(Session, Animator, Humanoid, 16, 1)
		Drive(Session, Animator, Humanoid, 24, 1)
	end
	T:Equal(
		"a retained gait does not stream invisible speed commands",
		Walk.SpeedCalls,
		FloorSpeedCalls
	)
end

do
	local Ids = {
		"rbxassetid://retained-a",
		"rbxassetid://retained-b",
		"rbxassetid://retained-c",
		"rbxassetid://retained-d",
		"rbxassetid://retained-e",
	}
	Modules.TrackDriver.Prepare(Ids)
	local Animator = Stub.Animator()
	for Index = 1, 3 do
		Modules.TrackDriver.Drive(Animator, {
			Id = Ids[Index],
			Weight = 1,
			Rate = 1,
			Fade = 0.1,
			Looped = true,
			Sustain = true,
		})
		Modules.TrackDriver.Drive(Animator, {
			Id = Ids[Index],
			Weight = 0,
			Rate = 1,
			Fade = 0.1,
			Looped = true,
			Sustain = true,
		})
	end
	for Index = 4, 5 do
		Modules.TrackDriver.Drive(Animator, {
			Id = Ids[Index],
			Weight = 1,
			Rate = 1,
			Fade = 0.1,
			Looped = false,
			Sustain = false,
		})
	end

	local EvictedId = nil
	for Index = 1, 3 do
		local Track = Animator.Tracks[Ids[Index]]
		if not Track.IsPlaying then
			EvictedId = Ids[Index]
			break
		end
	end
	T:True("track pressure evicts an invisible retained gait", EvictedId ~= nil)
	if EvictedId then
		local Loads = Animator.LoadCallCounts[EvictedId]
		for _ = 1, 20 do
			Modules.TrackDriver.Drive(Animator, {
				Id = EvictedId,
				Weight = 0,
				Rate = 1,
				Fade = 0.1,
				Looped = true,
				Sustain = true,
			})
		end
		T:Equal(
			"an evicted retained gait does not churn",
			Animator.LoadCallCounts[EvictedId],
			Loads
		)
	end
end

do
	local Slots = {}
	for _, Slot in Modules.StockCatalog.Slots do
		Slots[Slot] = { "rbxassetid://stock-" .. Slot }
	end
	local Catalog = Stub.Catalog(Modules.PoseCatalog, Slots)
	local RoundTrip = Modules.PoseCatalog.Decode(Modules.PoseCatalog.Encode(Catalog))
	T:True("the complete stock Animate catalog round-trips", RoundTrip ~= nil)
	for _, Slot in Modules.StockCatalog.Slots do
		T:True("the stock catalog includes " .. Slot, RoundTrip.SlotIds[Slot] ~= nil)
	end
end

do
	local Stock = Modules.StockCatalog.ToolIdsByRig
	local WrongRig = Modules.PoseCatalog.Build(
		Stub.BuildAnimate({
			idle = { { Id = IdleId } },
			toolnone = { { Id = Stock.R15.toolnone } },
			toolslash = { { Id = Stock.R15.toolslash } },
			toollunge = { { Id = Stock.R15.toollunge } },
		}),
		"R6"
	)
	for _, Slot in Modules.StockCatalog.ToolSlots do
		T:Equal("r6 replaces wrong-rig stock " .. Slot, WrongRig.Primary[Slot], Stock.R6[Slot])
	end
	local WrongRigR15 = Modules.PoseCatalog.Build(
		Stub.BuildAnimate({
			idle = { { Id = IdleId } },
			toolnone = { { Id = Stock.R6.toolnone } },
			toolslash = { { Id = Stock.R6.toolslash } },
			toollunge = { { Id = Stock.R6.toollunge } },
		}),
		"R15"
	)
	for _, Slot in Modules.StockCatalog.ToolSlots do
		T:Equal("r15 replaces wrong-rig stock " .. Slot, WrongRigR15.Primary[Slot], Stock.R15[Slot])
	end

	local Missing = Modules.PoseCatalog.Build(
		Stub.BuildAnimate({
			idle = { { Id = IdleId } },
		}),
		"R15"
	)
	for _, Slot in Modules.StockCatalog.ToolSlots do
		T:Equal("r15 supplies missing stock " .. Slot, Missing.Primary[Slot], Stock.R15[Slot])
	end

	local CustomSlash = "rbxassetid://custom-toolslash"
	local Custom = Modules.PoseCatalog.Build(
		Stub.BuildAnimate({
			idle = { { Id = IdleId } },
			toolslash = { { Id = CustomSlash } },
		}),
		"R6"
	)
	T:Equal("rig repair preserves a custom toolslash", Custom.Primary.toolslash, CustomSlash)
	T:Equal(
		"rig repair still fills a missing custom toolnone",
		Custom.Primary.toolnone,
		Stock.R6.toolnone
	)
end

do
	local ToolNoneId = "rbxassetid://synchronized-toolnone"
	local ToolSlashId = "rbxassetid://synchronized-toolslash"
	local ToolLungeId = "rbxassetid://synchronized-toollunge"
	local Animator, Humanoid, Session = NewWorld({
		idle = { IdleId },
		walk = { WalkId },
		toolnone = { ToolNoneId },
		toolslash = { ToolSlashId },
		toollunge = { ToolLungeId },
	}, "R15")
	local Tool = Stub.Tool("SynchronizedSword")
	local Handle = Tool:FindFirstChild("Handle")
	Handle:SetAttribute("ToolAnimationInputContext", "SwordContext")
	Handle:SetAttribute("ToolAnimationInputAction", "SwordAction")
	Handle:SetAttribute("ToolAnimationSequence", 0)
	Handle:SetAttribute("State", "None")
	Session.Character:SetTool(Tool)
	Drive(Session, Animator, Humanoid, 0, 2)

	Handle:SetAttribute("State", "Slash")
	Drive(Session, Animator, Humanoid, 0, 1)
	local Slash = Animator.Tracks[ToolSlashId]
	T:True("synchronized tool state starts slash", Slash ~= nil and Slash.IsPlaying)
	T:Near("synchronized slash starts without an action fade", Slash.LastPlayFade, 0)
	T:Equal(
		"synchronized tool state is consumed in simulation",
		Handle:GetAttribute("State"),
		"None"
	)
	T:Equal("synchronized slash has one playback edge", Slash.PlayCount, 1)

	Handle:SetAttribute("ToolAnimationSequence", 1)
	Drive(Session, Animator, Humanoid, 0, 2)
	T:Equal("a sequence confirmation cannot replay synchronized slash", Slash.PlayCount, 1)

	Handle:SetAttribute("State", "Lunge")
	Drive(Session, Animator, Humanoid, 0, 1)
	local Lunge = Animator.Tracks[ToolLungeId]
	T:True("synchronized tool state starts lunge", Lunge ~= nil and Lunge.IsPlaying)
	T:Equal("synchronized lunge has one playback edge", Lunge.PlayCount, 1)
	T:Equal("synchronized lunge is consumed in simulation", Handle:GetAttribute("State"), "None")

	Drive(Session, Animator, Humanoid, 0, 20)
	T:Near(
		"synchronized tool action keeps the stock 0.3 second window",
		Weight(Animator, ToolNoneId),
		1
	)
	T:Equal("synchronized lunge does not replay during release", Lunge.PlayCount, 1)
end

do
	local ToolNoneId = "rbxassetid://stock-toolnone"
	local ToolSlashId = "rbxassetid://stock-toolslash"
	local ToolLungeId = "rbxassetid://stock-toollunge"
	local Slots = {
		idle = { IdleId },
		walk = { WalkId },
		toolnone = { ToolNoneId },
		toolslash = { ToolSlashId },
		toollunge = { ToolLungeId },
	}
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")
	local Tool = Stub.Tool("Sword")
	local Handle = Tool:FindFirstChild("Handle")
	Handle:SetAttribute("ToolAnimationSequence", 0)
	Handle:SetAttribute("State", "None")
	Session.Character:SetTool(Tool)
	Drive(Session, Animator, Humanoid, 0, 5)
	T:Near("stock tool idle begins while equipped", Weight(Animator, ToolNoneId), 1)

	Stub.AdvanceSimulationTime(1)
	local Predicted = {
		ClassName = "StringValue",
		Value = "Slash",
		IsA = function(_, ClassName)
			return ClassName == "StringValue"
		end,
	}
	Tool:SetChild("toolanim", Predicted)
	Drive(Session, Animator, Humanoid, 0, 1)
	local PredictedSlash = Animator.Tracks[ToolSlashId]
	T:True(
		"stock toolanim predicts slash without writing authoritative state",
		PredictedSlash ~= nil and PredictedSlash.IsPlaying
	)
	T:Equal(
		"prediction preserves the server sequence",
		Handle:GetAttribute("ToolAnimationSequence"),
		0
	)
	Tool:SetChild("toolanim", nil)

	Handle:SetAttribute("State", "Slash")
	Handle:SetAttribute("ToolAnimationSequence", 1)
	Drive(Session, Animator, Humanoid, 0, 1)
	local Slash = Animator.Tracks[ToolSlashId]
	T:True("server confirmation keeps the predicted slash track", Slash == PredictedSlash)
	T:Equal("server confirmation does not replay predicted slash", Slash.PlayCount, 1)
	T:True("Slash starts the stock toolslash clip", Slash ~= nil and Slash.IsPlaying)
	T:Equal("toolslash uses Action priority", Slash.Priority.Name, "Action")
	T:False("toolslash is non-looped", Slash.Looped)
	T:Equal("toolslash plays at authored speed", Slash.Speed, 1)
	T:Near(
		"server confirmation preserves the synchronized predicted phase",
		Session.Root:GetAttribute("AnimBlendToolStartedAt"),
		Stub.Now() - 2 * Delta
	)
	T:Equal(
		"the animation producer retains tool state ownership",
		Handle:GetAttribute("State"),
		"Slash"
	)
	T:Near("toolslash replaces toolnone during its window", Weight(Animator, ToolNoneId), 0)

	Handle:SetAttribute("State", "Lunge")
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"a state write cannot tear an already committed sequence",
		Session.Root:GetAttribute("AnimBlendToolId"),
		ToolSlashId
	)
	T:Equal("a torn state does not start the next action", Animator.Tracks[ToolLungeId], nil)
	Handle:SetAttribute("State", "Slash")

	local FirstSlash = Slash
	FirstSlash.TimePosition = 0.2
	Session.Root:SetAttribute("AnimBlendToolSlot", nil)
	Session.Root:SetAttribute("AnimBlendToolId", nil)
	Session.Root:SetAttribute("AnimBlendToolStartedAt", nil)
	Session.Root:SetAttribute("AnimBlendToolEndsAt", nil)
	Handle:SetAttribute("State", "Slash")
	Drive(Session, Animator, Humanoid, 0, 1)
	T:True(
		"an authoritative confirmation keeps the predicted tool track",
		Animator.Tracks[ToolSlashId] == FirstSlash
	)
	T:Equal(
		"a confirmation does not load a duplicate tool track",
		Animator.LoadCallCounts[ToolSlashId],
		1
	)
	T:Near(
		"a confirmation leaves a live predicted phase advancing naturally",
		FirstSlash.TimePosition,
		0.2 + Delta
	)

	Handle:SetAttribute("State", "Slash")
	local CommittedStart = Stub.Now() - 0.12
	Handle:SetAttribute("ToolAnimationStartedAt", CommittedStart)
	Handle:SetAttribute("ToolAnimationSequence", 2)
	Drive(Session, Animator, Humanoid, 0, 1)
	T:True("a new slash reacquires its warmed track", Animator.Tracks[ToolSlashId] == FirstSlash)
	T:Equal("a new slash does not load a duplicate track", Animator.LoadCallCounts[ToolSlashId], 1)
	T:Equal("a new slash emits one playback edge", Animator.Tracks[ToolSlashId].PlayCount, 2)
	T:Near(
		"a new slash resets the warmed track phase",
		Animator.Tracks[ToolSlashId].TimePosition,
		1 / 60
	)
	T:Near(
		"a committed action preserves the producer's timeline",
		Session.Root:GetAttribute("AnimBlendToolStartedAt"),
		CommittedStart
	)
	Handle:SetAttribute("ToolAnimationStartedAt", nil)

	Handle:SetAttribute("ToolAnimationSequence", 3)
	Handle:SetAttribute("State", "Lunge")
	Drive(Session, Animator, Humanoid, 0, 1)
	local Lunge = Animator.Tracks[ToolLungeId]
	T:True("Lunge starts the stock toollunge clip", Lunge ~= nil and Lunge.IsPlaying)
	T:Equal("toollunge uses Action priority", Lunge.Priority.Name, "Action")
	T:Equal("toollunge plays at authored speed", Lunge.Speed, 1)

	Handle:SetAttribute("ToolAnimationSequence", 2)
	Handle:SetAttribute("State", "Slash")
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"a stale rollback keeps the newest tool action",
		Session.Root:GetAttribute("AnimBlendToolId"),
		ToolLungeId
	)
	T:Near("a stale rollback does not rewind the newest action", Lunge.TimePosition, 2 / 60)

	Drive(Session, Animator, Humanoid, 0, 20)
	T:Near("toolnone resumes after the stock action window", Weight(Animator, ToolNoneId), 1)
	T:Near("toolslash releases after the stock action window", Weight(Animator, ToolSlashId), 0)

	local LungePlayCount = Lunge.PlayCount
	Handle:SetAttribute("ToolAnimationSequence", 3)
	Handle:SetAttribute("State", "Lunge")
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"an expired confirmation does not restore tool action state",
		Session.Root:GetAttribute("AnimBlendToolId"),
		nil
	)
	T:Equal("an expired confirmation does not replay its track", Lunge.PlayCount, LungePlayCount)

	Handle:SetAttribute("ToolAnimationSequence", 4)
	Handle:SetAttribute("State", "Slash")
	Drive(Session, Animator, Humanoid, 0, 1)
	Handle:SetAttribute("State", "Slash")
	Session.Character:SetTool(nil)
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"unequip clears the active tool action",
		Session.Root:GetAttribute("AnimBlendToolId"),
		nil
	)
	Session.Character:SetTool(Tool)
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"reequip leaves producer-owned tool state unchanged",
		Handle:GetAttribute("State"),
		"Slash"
	)
	T:Near("reequip returns directly to toolnone", Weight(Animator, ToolNoneId), 1)

	Handle:SetAttribute("ToolAnimationSequence", 5)
	Handle:SetAttribute("State", "Slash")
	Drive(Session, Animator, Humanoid, 0, 1)
	Humanoid.StateName = "Physics"
	Drive(Session, Animator, Humanoid, 0, 1)
	Humanoid.StateName = "Running"
	Handle:SetAttribute("State", "Slash")
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"a handoff cannot resurrect its cancelled action",
		Session.Root:GetAttribute("AnimBlendToolId"),
		nil
	)
end

do
	local ToolNoneId = "rbxassetid://race-toolnone"
	local ToolSlashId = "rbxassetid://race-toolslash"
	local Slots = {
		idle = { IdleId },
		walk = { WalkId },
		toolnone = { ToolNoneId },
		toolslash = { ToolSlashId },
	}
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")
	local Tool = Stub.Tool("RaceSword")
	local Handle = Tool:FindFirstChild("Handle")
	Session.Character:SetTool(Tool)
	Drive(Session, Animator, Humanoid, 0, 1)

	local Replicated = Animator:LoadAnimation({ AnimationId = ToolSlashId })
	Replicated.Looped = false
	Replicated.Priority = Stub.Enum.AnimationPriority.Action
	Replicated:Play(0, 1, 1)
	Drive(Session, Animator, Humanoid, 0, 2)
	local PhaseBeforeMetadata = Replicated.TimePosition
	T:True("a replicated action survives metadata arriving later", Replicated.IsPlaying)
	T:Equal("a metadata gap does not stop the replicated action", Replicated.StopCount, 0)

	Handle:SetAttribute("ToolAnimationSequence", 1)
	Handle:SetAttribute("State", "Slash")
	Drive(Session, Animator, Humanoid, 0, 1)
	T:Equal("late metadata adopts rather than replays the action", Replicated.PlayCount, 1)
	T:True("the adopted action keeps advancing", Replicated.TimePosition > PhaseBeforeMetadata)
	T:Equal(
		"late metadata does not load a duplicate action",
		Animator.LoadCallCounts[ToolSlashId],
		1
	)
	local Duplicate = Animator:AddStray(ToolSlashId, 1)
	Duplicate.TimePosition = Replicated.TimePosition - Delta
	local Kept = Modules.TrackDriver.Collapse(Animator, ToolSlashId)
	T:Equal("duplicate collapse preserves the furthest action phase", Kept, Replicated)
	T:False("duplicate collapse releases the trailing action copy", Duplicate.IsPlaying)
	T:True("duplicate collapse keeps the canonical action playing", Replicated.IsPlaying)
end

do
	local Stock = Modules.StockCatalog.ToolIdsByRig.R6
	local Slots = {
		idle = { IdleId },
		walk = { WalkId },
		toolnone = { Stock.toolnone },
		toolslash = { Stock.toolslash },
		toollunge = { Stock.toollunge },
	}
	local Animator, Humanoid, Session = NewWorld(Slots, "R6")
	local Tool = Stub.Tool("R6Sword")
	local Handle = Tool:FindFirstChild("Handle")
	Session.Character:SetTool(Tool)
	local Predicted = {
		ClassName = "StringValue",
		Value = "Slash",
		IsA = function(_, ClassName)
			return ClassName == "StringValue"
		end,
	}
	Tool:SetChild("toolanim", Predicted)
	Drive(Session, Animator, Humanoid, 0, 1)
	local PredictedSlash = Animator.Tracks[Stock.toolslash]
	Tool:SetChild("toolanim", nil)
	Handle:SetAttribute("ToolAnimationSequence", 1)
	Handle:SetAttribute("State", "Slash")
	Drive(Session, Animator, Humanoid, 0, 1)
	T:True(
		"R6 confirmation keeps its predicted slash",
		Animator.Tracks[Stock.toolslash] == PredictedSlash
	)
	T:Equal("R6 confirmation does not replay its predicted slash", PredictedSlash.PlayCount, 1)
	T:True("R6 slash starts its own stock action", Animator.Tracks[Stock.toolslash].IsPlaying)
	T:Equal(
		"R6 slash keeps Action priority",
		Animator.Tracks[Stock.toolslash].Priority.Name,
		"Action"
	)
	Handle:SetAttribute("ToolAnimationSequence", 2)
	Handle:SetAttribute("State", "Lunge")
	Drive(Session, Animator, Humanoid, 0, 1)
	T:True("R6 lunge starts its own stock action", Animator.Tracks[Stock.toollunge].IsPlaying)
	T:Equal(
		"R6 lunge keeps Action priority",
		Animator.Tracks[Stock.toollunge].Priority.Name,
		"Action"
	)
end

do
	local IdleVariant = "rbxassetid://equipped-idle-variant"
	local Slots = {
		idle = { IdleId, IdleVariant },
		walk = { WalkId },
		toolnone = { "rbxassetid://equipped-toolnone" },
	}
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")
	Session.Character:SetTool(Stub.Tool("Sword"))
	Drive(Session, Animator, Humanoid, 0, 1)
	T:True(
		"equipped toolnone preserves the ordinary idle variant clock",
		type(Session.Root:GetAttribute("AnimBlendIdleStartedAt")) == "number"
	)
end

do
	local WaveId = "rbxassetid://stock-wave"
	local DanceId = "rbxassetid://stock-dance"
	local Slots = {
		idle = { IdleId },
		walk = { WalkId },
		run = { RunId },
		wave = { WaveId },
		dance = { DanceId },
	}
	local Animator, Humanoid, Session = NewWorld(Slots, "R15")
	Session.EmoteAction = Stub.InputAction()
	Drive(Session, Animator, Humanoid, 0, 5)

	Session.EmoteAction:Fire(1)
	Drive(Session, Animator, Humanoid, 0, 2)
	local Wave = Animator.Tracks[WaveId]
	T:True("wave replaces the standing pose", Wave ~= nil and Wave.IsPlaying)
	T:Equal("stock emotes use Core priority", Wave.Priority.Name, "Core")
	T:False("wave is non-looped", Wave.Looped)
	T:Near("locomotion yields while an emote plays", Weight(Animator, IdleId), 0.001)

	Drive(Session, Animator, Humanoid, 0, 65)
	T:Near("a non-looped emote returns to idle", Weight(Animator, IdleId), 1)
	T:Near("a completed non-looped emote releases", Weight(Animator, WaveId), 0)

	Session.EmoteAction:Fire(3)
	Drive(Session, Animator, Humanoid, 0, 2)
	local Dance = Animator.Tracks[DanceId]
	T:True("dance begins from standing", Dance ~= nil and Dance.IsPlaying)
	T:True("dance loops like stock Animate", Dance.Looped)
	Drive(Session, Animator, Humanoid, 8, 10)
	T:Near("movement interrupts a looping dance", Weight(Animator, DanceId), 0)
	T:True("movement resumes after a dance", Weight(Animator, WalkId) > 0.4)
end

do
	local Slots = {
		idle = { IdleId },
		walk = { WalkId },
		dance1 = { "rbxassetid://960001" },
		dance2 = { "rbxassetid://960002" },
		dance3 = { "rbxassetid://960003" },
	}
	local Animator, Humanoid, Session = NewWorld(Slots, "R6")
	Session.EmoteAction = Stub.InputAction()
	Session.EmoteAction:Fire(3)
	Drive(Session, Animator, Humanoid, 0, 2)
	local Playing = 0
	for _, Slot in { "dance1", "dance2", "dance3" } do
		Playing += if Weight(Animator, Slots[Slot][1]) > 0.5 then 1 else 0
	end
	T:Equal("R6 generic dance selects exactly one stock dance", Playing, 1)
end

return T

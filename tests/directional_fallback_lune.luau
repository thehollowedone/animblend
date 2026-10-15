local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")

local T = Expect.New("DirectionalFallback")
local IdleId = "rbxassetid://fallback-idle"
local WalkId = "rbxassetid://fallback-walk"
local RunId = "rbxassetid://fallback-run"
local BackWalkId = "rbxassetid://fallback-back-walk"
local BackRunId = "rbxassetid://fallback-back-run"
local LocomotionIds = { WalkId, RunId, BackWalkId, BackRunId }

-- This passes the catalog's coverage test, but has no sample in either of
-- the mixed-sign quadrants. The walk/run IDs also occur in Directional, so
-- its zero-weight cleanup targets must not replace the ordinary fallback.
local Slots = {
	idle = { { Id = IdleId } },
	walk = { { Id = WalkId, Velocity = Stub.Vector2(6.4, 6.4) } },
	run = { { Id = RunId, Velocity = Stub.Vector2(16, 16) } },
	backwalk = { { Id = BackWalkId, Velocity = Stub.Vector2(-6.4, -6.4) } },
	backrun = { { Id = BackRunId, Velocity = Stub.Vector2(-16, -16) } },
}

local function NewWorld()
	local Modules = Stub.Build()
	local Catalog = Modules.PoseCatalog.Build(Stub.BuildAnimate(Slots))
	local Animator = Stub.Animator()
	local Humanoid = Stub.Humanoid(Animator)
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Profile = Modules.RigProfile.Resolve("R15", {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	})
	return Modules, Animator, Humanoid, Stub.Session(Humanoid, Profile, Catalog)
end

local function SetVelocity(Humanoid, X, Z)
	Humanoid.RelativeVelocity = Stub.Vector3(X, 0, Z)
	Humanoid.MoveDirection = Stub.Vector3(X, 0, Z)
end

local function Step(Modules, Animator, Humanoid, Session, X, Z, Frames)
	SetVelocity(Humanoid, X, Z)
	for _ = 1, Frames do
		Modules.AnimBlend.Step(Session)
		Stub.Advance(Animator, 1 / 60)
	end
end

local function Weight(Animator, Id, Current)
	local Track = Animator.Tracks[Id]
	if not Track or not Track.IsPlaying then
		return 0
	end
	return if Current then Track.WeightCurrent else Track.WeightTarget
end

local function LocomotionWeight(Animator, Current)
	local Sum = 0
	for _, Id in LocomotionIds do
		Sum += Weight(Animator, Id, Current)
	end
	return Sum
end

local function OrdinaryField(Modules, Session, X, Z)
	local Speed = math.sqrt(X * X + Z * Z)
	return Modules.LocomotionSolver.Solve({
		StateName = "Running",
		GroundSpeed = Speed,
		TotalSpeed = Speed,
		ClimbSpeed = 0,
		OnAir = false,
		HeightScale = 1,
		RigScale = 1,
		JumpElapsed = nil,
		WantsMove = true,
		WasSwimming = false,
		WalkIsDefault = Session.Catalog.WalkIsDefault,
	}, Session.Profile)
end

for _, Sign in { -1, 1 } do
	for _, Component in { 3.2, 6.4, 16 } do
		local Modules, Animator, Humanoid, Session = NewWorld()
		local Catalog = Session.Catalog
		local X, Z = Sign * Component, Sign * Component
		local Tag = ("gap %s speed component %s"):format(tostring(Sign), tostring(Component))
		T:True(Tag .. " remains an accepted directional catalog", Catalog.HasDirectional)
		T:Equal(Tag .. " keeps all four directional samples", #Catalog.Directional, 4)
		local Weights = {}
		T:Equal(
			Tag .. " has no directional solution",
			Modules.DirectionalSolver.Solve(X, -Z, 1, Catalog.Directional, Weights),
			nil
		)
		for Index, Entry in Catalog.Directional do
			T:Near(Tag .. " produces zero directional weight for " .. Entry.Id, Weights[Index], 0)
		end

		local Expected = OrdinaryField(Modules, Session, X, Z)
		Step(Modules, Animator, Humanoid, Session, X, Z, 60)
		T:True(
			Tag .. " leaves visible locomotion after settling",
			LocomotionWeight(Animator, true) > 0.9
		)
		for Slot, Id in { Walk = WalkId, Run = RunId } do
			local Track = Animator.Tracks[Id]
			-- An inactive sample need not be loaded. Once present, TrackDriver
			-- retains it at a replication floor below the visibility threshold.
			if Expected[Slot] > 0.01 then
				T:True(
					Tag .. " keeps fallback " .. Slot .. " playing",
					Track ~= nil and Track.IsPlaying
				)
				if Track then
					T:Near(
						Tag .. " preserves shared-ID " .. Slot .. " fallback weight",
						Track.WeightTarget,
						Expected[Slot]
					)
					T:Near(
						Tag .. " preserves shared-ID " .. Slot .. " fallback rate",
						Track.Speed,
						Expected.Rate
					)
				end
			else
				T:True(
					Tag .. " keeps inactive " .. Slot .. " below visibility",
					Weight(Animator, Id) <= 0.001
				)
			end
		end
		T:True(Tag .. " leaves backward walk invisible", Weight(Animator, BackWalkId) <= 0.001)
		T:True(Tag .. " leaves backward run invisible", Weight(Animator, BackRunId) <= 0.001)
	end
end

do
	local Modules, Animator, Humanoid, Session = NewWorld()
	Step(Modules, Animator, Humanoid, Session, -6.4, 6.4, 60)
	T:True(
		"a covered direction starts its backward walk sample",
		Weight(Animator, BackWalkId, true) > 0.9
	)
	T:True(
		"a covered direction suppresses ordinary forward fallback",
		Weight(Animator, WalkId) <= 0.001
	)
	local OriginalBackWalk = Animator.Tracks[BackWalkId]

	local Expected = OrdinaryField(Modules, Session, 6.4, 6.4)
	for Frame = 1, 60 do
		Step(Modules, Animator, Humanoid, Session, 6.4, 6.4, 1)
		T:True(
			"directional-to-fallback frame " .. Frame .. " keeps a visible target",
			LocomotionWeight(Animator) > 0.9
		)
	end
	T:Near(
		"directional-to-fallback restores ordinary walk weight",
		Weight(Animator, WalkId),
		Expected.Walk
	)
	T:Near(
		"directional-to-fallback restores ordinary run weight",
		Weight(Animator, RunId),
		Expected.Run
	)
	T:True(
		"fallback releases the old backward sample after fading",
		Weight(Animator, BackWalkId, true) <= 0.001
	)
	local FallbackWalk = Animator.Tracks[WalkId]
	local FallbackRun = Animator.Tracks[RunId]

	for Frame = 1, 60 do
		Step(Modules, Animator, Humanoid, Session, 6.4, -6.4, 1)
		T:True(
			"fallback-to-directional frame " .. Frame .. " keeps a visible target",
			LocomotionWeight(Animator) > 0.9
		)
	end
	T:True(
		"returning to a covered direction restores its full walk sample",
		Weight(Animator, WalkId, true) > 0.9
	)
	T:True(
		"returning to directional removes the old fallback run weight",
		Weight(Animator, RunId, true) <= 0.001
	)
	for Id, Original in
		{
			[BackWalkId] = OriginalBackWalk,
			[WalkId] = FallbackWalk,
			[RunId] = FallbackRun,
		}
	do
		T:Equal("transitions retain the same track for " .. Id, Animator.Tracks[Id], Original)
		T:Equal("transitions do not restart " .. Id, Original.PlayCount, 1)
	end
end

return T

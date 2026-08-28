local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")

local T = Expect.New("ContinuityHardening")
local WalkId = "rbxassetid://continuity-walk"
local RunId = "rbxassetid://continuity-run"
local IdleId = "rbxassetid://continuity-idle"

local function NewWorld(Modules)
	local Animator = Stub.Animator({ [WalkId] = 1, [RunId] = 0.8, [IdleId] = 2 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(Modules.PoseCatalog, {
		idle = { IdleId },
		walk = { WalkId },
		run = { RunId },
	})
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Profile = Modules.RigProfile.Resolve("R15", {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	})
	return Animator, Humanoid, Stub.Session(Humanoid, Profile, Catalog)
end

local function Step(Modules, Session, Animator, Humanoid, Speed, Frames)
	for _ = 1, Frames do
		local Velocity = Stub.Vector3(Speed, 0, 0)
		Humanoid.RelativeVelocity = Velocity
		Humanoid.MoveDirection = if Speed > 0 then Stub.Vector3(1, 0, 0) else Stub.Vector3(0, 0, 0)
		Modules.AnimBlend.Step(Session)
		Stub.Advance(Animator, 1 / 60)
	end
end

do
	local Modules = Stub.Build()
	local Animator, Humanoid, Session = NewWorld(Modules)
	Step(Modules, Session, Animator, Humanoid, 4, 37)
	local Walk = Animator.Tracks[WalkId]
	local WalkCycle = (Walk.TimePosition / Walk.Length) % 1
	Humanoid.RelativeVelocity = Stub.Vector3(16, 0, 0)
	Humanoid.MoveDirection = Stub.Vector3(1, 0, 0)
	Modules.AnimBlend.Step(Session)
	local Run = Animator.Tracks[RunId]
	T:True("walk-to-run crossover starts the run track", Run ~= nil and Run.IsPlaying)
	T:Near(
		"walk-to-run crossover preserves normalized stride phase",
		(Run.TimePosition / Run.Length) % 1,
		WalkCycle
	)
end

do
	local Modules = Stub.Build()
	local First = { "rbxassetid://lease-a", "rbxassetid://lease-shared" }
	local Second = { "rbxassetid://lease-shared", "rbxassetid://lease-b" }
	Modules.TrackDriver.ReplaceLease({}, First)
	local Cached, Leases = Modules.TrackDriver.CacheCounts()
	T:Equal("a catalog lease retains its unique animations", Cached, 2)
	T:Equal("a catalog lease counts one live catalog", Leases, 2)
	Modules.TrackDriver.ReplaceLease(First, Second)
	Cached, Leases = Modules.TrackDriver.CacheCounts()
	T:Equal("catalog replacement drops retired IDs without churning shared IDs", Cached, 2)
	T:Equal("catalog replacement preserves the bounded lease set", Leases, 2)
	Modules.TrackDriver.ReplaceLease(Second, {})
	Cached, Leases = Modules.TrackDriver.CacheCounts()
	T:Equal("releasing the final catalog clears the strong animation cache", Cached, 0)
	T:Equal("releasing the final catalog clears every lease", Leases, 0)
end

do
	local Modules = Stub.Build()
	local Animator, Humanoid, Session = NewWorld(Modules)
	Step(Modules, Session, Animator, Humanoid, 8, 3)
	local Walk = Animator.Tracks[WalkId]

	-- PlatformStand is the authoritative property used by flight controllers;
	-- the Humanoid state event can trail it by a simulation edge.
	Humanoid.PlatformStand = true
	Humanoid.StateName = "Running"
	Step(Modules, Session, Animator, Humanoid, 8, 1)
	T:False("PlatformStand releases locomotion even before StateChanged catches up", Walk.IsPlaying)

	Humanoid.PlatformStand = false
	Session.Character:SetAttribute("AnimBlendExternalControl", true)
	Walk.IsPlaying = true
	Step(Modules, Session, Animator, Humanoid, 8, 1)
	T:False("an explicit external controller receives the whole rig", Walk.IsPlaying)

	Session.Character:SetAttribute("AnimBlendExternalControl", nil)
	Step(Modules, Session, Animator, Humanoid, 8, 1)
	T:True(
		"locomotion resumes after the external controller releases the rig",
		Animator.Tracks[WalkId].IsPlaying
	)

	local ResumedWalk = Animator.Tracks[WalkId]
	Humanoid.Health = 0
	Humanoid.StateName = "Running"
	Step(Modules, Session, Animator, Humanoid, 8, 1)
	T:False("death releases locomotion even before the state transition", ResumedWalk.IsPlaying)
end

do
	local Modules = Stub.Build()
	Modules.RunService.BindingError = true
	local Ok, Message = pcall(Modules.AnimBlend.Init)
	T:False("an unavailable synchronized simulation binding is rejected before takeover", Ok)
	T:True(
		"binding failure is actionable",
		string.find(tostring(Message), "Server Authority", 1, true) ~= nil
			and string.find(tostring(Message), "BindToSimulation", 1, true) ~= nil
	)
	T:Equal("binding failure starts no binder", #Modules.CharacterBinder.Calls, 0)
	T:Equal(
		"binding failure registers no simulation callback",
		#Modules.RunService.SimulationCallbacks,
		0
	)
	Modules.RunService.BindingError = false
	Modules.AnimBlend.Init()
	T:Equal(
		"a restored simulation capability can retry initialization",
		#Modules.RunService.SimulationCallbacks,
		1
	)
end

do
	local Modules = Stub.Build({ AnimatorPreferLodEnabled = false })
	local Animator = Stub.Animator()
	local Humanoid = Stub.Humanoid(Animator)
	Animator.Parent = Humanoid
	local Owned = Modules.TrackDriver.TakeOwnership(Humanoid)
	T:True(
		"small experiences can opt out of Animator LOD",
		Owned ~= nil and not Owned.PreferLodEnabled
	)
end

do
	local Modules = Stub.Build(nil, true, true)
	local Animator, _, Session = NewWorld(Modules)
	Animator:SetAttribute("AnimBlendOwned", true)
	Session.CatalogSignature = "published"
	Modules.RunService.PredictionError = true
	T:False(
		"a transient prediction-status error fails closed on the client",
		Modules.CharacterBinder.ShouldDrive(Session)
	)
	Modules.RunService.PredictionError = false
	Modules.RunService.PredictionStatus = Stub.Enum.PredictionStatus.None
	T:False(
		"a non-predicting client does not fight replicated animation",
		Modules.CharacterBinder.ShouldDrive(Session)
	)
	Modules.RunService.PredictionStatus = Stub.Enum.PredictionStatus.Authoritative
	T:True(
		"prediction gating recovers after the transient failure",
		Modules.CharacterBinder.ShouldDrive(Session)
	)
end

do
	local Modules = Stub.Build()
	local Animator = Stub.Animator()
	local Humanoid = Stub.Humanoid(Animator)
	local SlashId = "rbxassetid://rollback-tool-slash"
	local Catalog = Stub.Catalog(Modules.PoseCatalog, {
		idle = { IdleId },
		walk = { WalkId },
		toolnone = { "rbxassetid://rollback-tool-idle" },
		toolslash = { SlashId },
	})
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Profile = Modules.RigProfile.Resolve("R15", {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	})
	local Session = Stub.Session(Humanoid, Profile, Catalog)
	local Tool = Stub.Tool("RollbackSword")
	local Handle = Tool:FindFirstChild("Handle")
	Handle:SetAttribute("ToolAnimationSequence", 1)
	Handle:SetAttribute("State", "Slash")
	Session.Character:SetTool(Tool)
	Step(Modules, Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"tool request begins before cancellation",
		Session.Root:GetAttribute("AnimBlendToolId"),
		SlashId
	)

	Session.Character:SetTool(nil)
	Step(Modules, Session, Animator, Humanoid, 0, 1)
	Session.Character:SetTool(Tool)
	Step(Modules, Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"real unequip cancellation cannot resurrect the same confirmed sequence",
		Session.Root:GetAttribute("AnimBlendToolId"),
		nil
	)

	-- Server Authority rewinds predicted attributes, but ordinary Lua tables are
	-- not rewound. Clearing the synchronized cancellation marker models the
	-- replayed pre-unequip frame; the exact confirmation must become valid again.
	Session.Root:SetAttribute("AnimBlendToolCancelledSequence", nil)
	Session.Root:SetAttribute("AnimBlendToolCancelledId", nil)
	Step(Modules, Session, Animator, Humanoid, 0, 1)
	T:Equal(
		"rollback-visible cancellation state allows a pre-unequip replay",
		Session.Root:GetAttribute("AnimBlendToolId"),
		SlashId
	)
end

do
	local Modules = Stub.Build()
	local GoodAnimator, GoodHumanoid, Good = NewWorld(Modules)
	local BadAnimator, BadHumanoid, Bad = NewWorld(Modules)
	BadHumanoid.GetState = function()
		error("isolated test fault")
	end
	Modules.CharacterBinder.Sessions[1] = Good
	Modules.CharacterBinder.Sessions[2] = Bad
	Modules.AnimBlend.Init()
	local Callback = Modules.RunService.SimulationCallbacks[1]
	local Ok = pcall(Callback)
	T:True("one malformed character cannot abort the shared simulation callback", Ok)
	T:True(
		"a healthy character still advances after another character faults",
		GoodAnimator.Tracks[IdleId] ~= nil
	)
	T:Equal("the malformed character did not start a track", BadAnimator.Tracks[IdleId], nil)
end

return T

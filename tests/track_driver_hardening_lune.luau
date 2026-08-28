local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")

local T = Expect.New("TrackDriverHardening")
local Modules = Stub.Build()
local TrackDriver = Modules.TrackDriver

local function Target(Id, Weight, Sustain, Elapsed)
	return {
		Id = Id,
		Weight = Weight,
		Rate = 1,
		Fade = 0.1,
		Looped = Sustain,
		Sustain = Sustain,
		Priority = Stub.Enum.AnimationPriority.Core,
		Elapsed = Elapsed,
	}
end

do
	local Animator = Stub.Animator()
	local FallbackId = "rbxassetid://step-fallback"
	local Fallback = Animator:AddStray(FallbackId, 1)
	local Scans = 0
	local GetPlaying = Animator.GetPlayingAnimationTracks
	Animator.GetPlayingAnimationTracks = function(Self)
		Scans += 1
		return GetPlaying(Self)
	end

	local Step = TrackDriver.BeginStep(Animator)
	T:Equal("beginning a step performs one fallback scan", Scans, 1)
	for Index = 1, 20 do
		TrackDriver.Find(Animator, "rbxassetid://missing-" .. tostring(Index), Step)
	end
	T:Equal("indexed misses perform no additional playing-track scans", Scans, 1)
	T:Equal(
		"the step index resolves a live fallback track",
		TrackDriver.Find(Animator, FallbackId, Step),
		Fallback
	)

	local DirectId = "rbxassetid://direct-after-index"
	local Direct = Animator:LoadAnimation({ AnimationId = DirectId })
	T:Equal(
		"direct lookup remains authoritative within a step",
		TrackDriver.Find(Animator, DirectId, Step),
		Direct
	)

	Fallback:Stop(0)
	local Replacement = Animator:AddStray(FallbackId, 1)
	local NextStep = TrackDriver.BeginStep(Animator)
	T:Equal(
		"a new step observes replacement fallback tracks",
		TrackDriver.Find(Animator, FallbackId, NextStep),
		Replacement
	)
	T:Equal("each new step performs exactly one fresh scan", Scans, 2)
end

do
	local Animator = Stub.Animator()
	local Ids = {}
	for Index = 1, 5 do
		Ids[Index] = "rbxassetid://" .. tostring(910000 + Index)
	end
	TrackDriver.Prepare(Ids)
	local External = Animator:AddStray("rbxassetid://919999", 0)
	local Step = TrackDriver.BeginStep(Animator)
	for Index = 1, 4 do
		TrackDriver.Drive(Animator, Target(Ids[Index], 1, false, nil), nil, Step)
	end
	TrackDriver.Drive(Animator, Target(Ids[5], 1, false, nil), nil, Step)

	T:True("an unrelated Core track survives managed pressure", External.IsPlaying)
	T:Equal("managed pressure never stops an unrelated track", External.StopCount, 0)
	T:False("a fifth visible managed track is refused", Animator.Tracks[Ids[5]].IsPlaying)
	local ManagedPlaying = 0
	for _, Id in Ids do
		local Track = Animator.Tracks[Id]
		ManagedPlaying += if Track and Track.IsPlaying then 1 else 0
	end
	T:Equal("the managed visible-track budget is a hard cap", ManagedPlaying, 4)
end

do
	local Animator = Stub.Animator()
	local Ids = {}
	for Index = 1, 5 do
		Ids[Index] = "rbxassetid://" .. tostring(920000 + Index)
	end
	TrackDriver.Prepare(Ids)
	local External = Animator:AddStray("rbxassetid://929999", 0)
	local Step = TrackDriver.BeginStep(Animator)
	for Index = 1, 4 do
		TrackDriver.Drive(Animator, Target(Ids[Index], 1, true, nil), nil, Step)
	end
	local Safe = Animator.Tracks[Ids[1]]
	TrackDriver.Drive(Animator, Target(Ids[1], 0, true, nil), nil, Step)
	TrackDriver.Drive(Animator, Target(Ids[5], 1, false, nil), nil, Step)

	T:False("pressure evicts an invisible managed track", Safe.IsPlaying)
	T:True("pressure still leaves an invisible external track alone", External.IsPlaying)
	T:Equal("external tracks receive no stop command", External.StopCount, 0)
	T:True("the new managed track starts after safe eviction", Animator.Tracks[Ids[5]].IsPlaying)
end

do
	local Id = "rbxassetid://940001"
	local Animator = Stub.Animator({ [Id] = 0.5 })
	TrackDriver.Prepare({ Id })
	local Request = Target(Id, 1, false, 0)
	TrackDriver.Drive(Animator, Request, nil, TrackDriver.BeginStep(Animator))
	local First = Animator.Tracks[Id]
	T:Equal("the transient starts once", First.PlayCount, 1)
	First:Stop(0)

	Request.Elapsed = 0.5
	TrackDriver.Drive(Animator, Request, nil, TrackDriver.BeginStep(Animator))
	T:Equal("a naturally completed transient is not reacquired", Animator.LoadCallCounts[Id], 1)

	Request.Elapsed = 0.2
	TrackDriver.Drive(Animator, Request, nil, TrackDriver.BeginStep(Animator))
	T:Equal("rollback before completion permits reacquisition", Animator.LoadCallCounts[Id], 2)
	T:True("the reacquired transient is playing", Animator.Tracks[Id].IsPlaying)
end

return T

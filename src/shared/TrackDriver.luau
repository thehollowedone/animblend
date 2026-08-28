--!strict

local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local Root = game:GetService("ReplicatedStorage"):WaitForChild("AnimBlend")
local Config = require(Root:WaitForChild("Config"))

local TrackDriver = {}

export type Target = {
	Id: string,
	Weight: number,
	Rate: number,
	Fade: number,
	Looped: boolean,
	Sustain: boolean,
	Priority: Enum.AnimationPriority?,
	CycleAttribute: string?,
	Cycle: number?,
	Elapsed: number?,
}

export type StepTracks = {
	Animator: Animator,
	ByKey: { [string]: AnimationTrack },
	Tracks: { AnimationTrack },
	Seen: { [AnimationTrack]: boolean },
}

local WeightEpsilon = 0.001
local RetainedWeight = WeightEpsilon
local WeightCommandBand = 0.05
local SpeedCommandBand = 0.08
local BlendFade = 0.1
local BlendVisible = 0.01
local Priority = Enum.AnimationPriority.Core
local ManagedTrackBudget = 4
local IsClient = RunService:IsClient()
local AnimatorPreferLodEnabled = Config.AnimatorPreferLodEnabled
if type(AnimatorPreferLodEnabled) ~= "boolean" then
	error("AnimBlend: Config.AnimatorPreferLodEnabled must be a boolean")
end

local AnimationById: { [string]: Animation } = {}
local PreloadedIds: { [string]: boolean } = {}
local LeaseCounts: { [string]: number } = {}
local PreparedAnimators: { [Animator]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local ManagedTracks: { [AnimationTrack]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local DurationById: { [string]: number } = {}
local OwnedAttribute = "AnimBlendOwned"

local function AssetKey(AnimationId: string): string
	return AnimationId:match("%d+") or AnimationId
end

local function AnimationForId(AnimationId: string): Animation
	local Key = AssetKey(AnimationId)
	local Existing = AnimationById[Key]
	if Existing then
		return Existing
	end
	local Created = Instance.new("Animation")
	Created.AnimationId = AnimationId
	AnimationById[Key] = Created
	return Created
end

local function IdSet(AnimationIds: { string }): { [string]: string }
	local Set: { [string]: string } = {}
	for _, Id in AnimationIds do
		if Id ~= "" then
			Set[AssetKey(Id)] = Id
		end
	end
	return Set
end

-- Catalog leases bound the strong process-wide caches to the animation IDs
-- used by live sessions. Replacements are diffed atomically so shared IDs do
-- not churn while a character's custom pack is rebuilt.
function TrackDriver.ReplaceLease(PreviousIds: { string }, NextIds: { string })
	local Previous = IdSet(PreviousIds)
	local Next = IdSet(NextIds)
	for Key in Previous do
		if not Next[Key] then
			local Remaining = (LeaseCounts[Key] or 1) - 1
			if Remaining > 0 then
				LeaseCounts[Key] = Remaining
			else
				LeaseCounts[Key] = nil
				PreloadedIds[Key] = nil
				DurationById[Key] = nil
				local Animation = AnimationById[Key]
				AnimationById[Key] = nil
				if Animation then
					task.delay(1, function()
						if LeaseCounts[Key] == nil and AnimationById[Key] ~= Animation then
							Animation:Destroy()
						end
					end)
				end
			end
		end
	end
	for Key, Id in Next do
		if not Previous[Key] then
			LeaseCounts[Key] = (LeaseCounts[Key] or 0) + 1
			AnimationForId(Id)
		end
	end
end

function TrackDriver.CacheCounts(): (number, number)
	local Animations = 0
	local Leases = 0
	for _ in AnimationById do
		Animations += 1
	end
	for _, Count in LeaseCounts do
		Leases += Count
	end
	return Animations, Leases
end

local function TrackKey(Track: AnimationTrack): string?
	local Animation = Track.Animation
	return if Animation then AssetKey(Animation.AnimationId) else nil
end

-- A StepTracks value is deliberately short-lived. It coalesces the fallback
-- GetPlayingAnimationTracks scan within one simulation step without retaining
-- rollback-sensitive AnimationTrack handles between steps.
function TrackDriver.BeginStep(Animator: Animator): StepTracks
	local Tracks = Animator:GetPlayingAnimationTracks()
	local ByKey: { [string]: AnimationTrack } = {}
	local Seen: { [AnimationTrack]: boolean } = {}
	for _, Track in Tracks do
		Seen[Track] = true
		local Key = TrackKey(Track)
		if Key and not ByKey[Key] then
			ByKey[Key] = Track
		end
	end
	return {
		Animator = Animator,
		ByKey = ByKey,
		Tracks = Tracks,
		Seen = Seen,
	}
end

local function AddStepTrack(Step: StepTracks?, Animator: Animator, Track: AnimationTrack)
	if not Step or Step.Animator ~= Animator or Step.Seen[Track] then
		return
	end
	Step.Seen[Track] = true
	Step.Tracks[#Step.Tracks + 1] = Track
	local Key = TrackKey(Track)
	if Key and (not Step.ByKey[Key] or not Step.ByKey[Key].IsPlaying) then
		Step.ByKey[Key] = Track
	end
end

local function ObserveDuration(AnimationId: string, Track: AnimationTrack): number?
	local Key = AssetKey(AnimationId)
	local Known = DurationById[Key]
	if Known then
		return Known
	end
	local Length = Track.Length
	if type(Length) == "number" and Length > 0 then
		DurationById[Key] = Length
		return Length
	end
	return nil
end

local function Completed(Target: Target): boolean
	if Target.Looped or Target.Sustain or type(Target.Elapsed) ~= "number" then
		return false
	end
	local Duration = DurationById[AssetKey(Target.Id)]
	return Duration ~= nil and Duration > 0 and (Target.Elapsed :: number) >= Duration
end

local function DirectTrack(Animator: Animator, AnimationId: string): AnimationTrack?
	return Animator:GetTrackByAnimationId(AnimationId)
end

function TrackDriver.EnsureAnimator(Humanoid: Humanoid): Animator?
	local Existing = Humanoid:FindFirstChildOfClass("Animator")
	if Existing then
		return Existing
	end
	if IsClient then
		return nil
	end
	local Created = Instance.new("Animator")
	Created.Parent = Humanoid
	return Created
end

function TrackDriver.IsOwned(Animator: Animator): boolean
	return Animator:GetAttribute(OwnedAttribute) == true
end

function TrackDriver.TakeOwnership(Humanoid: Humanoid): Animator?
	local Existing = Humanoid:FindFirstChildOfClass("Animator")
	if IsClient then
		return Existing
	end
	if Existing and TrackDriver.IsOwned(Existing) then
		Existing.PreferLodEnabled = AnimatorPreferLodEnabled
		return Existing
	end

	local Created = Instance.new("Animator")
	Created:SetAttribute(OwnedAttribute, true)
	Created.PreferLodEnabled = AnimatorPreferLodEnabled

	if Existing then
		for _, Track in Existing:GetPlayingAnimationTracks() do
			pcall(Track.Stop, Track, 0)
		end
		Existing:Destroy()
	end

	Created.Parent = Humanoid
	return Created
end

function TrackDriver.PrepareAnimator(Humanoid: Humanoid): Animator?
	local Animator = TrackDriver.EnsureAnimator(Humanoid)
	if not Animator or not IsClient or PreparedAnimators[Animator] then
		return Animator
	end
	local Ok = pcall(RunService.SetPredictionMode, RunService, Animator, Enum.PredictionMode.On)
	if Ok then
		PreparedAnimators[Animator] = true
	end
	return Animator
end

function TrackDriver.Find(
	Animator: Animator,
	AnimationId: string,
	Step: StepTracks?
): AnimationTrack?
	local Direct = DirectTrack(Animator, AnimationId)
	if Direct then
		return Direct
	end

	local Key = AssetKey(AnimationId)
	if Step and Step.Animator == Animator then
		local Indexed = Step.ByKey[Key]
		return if Indexed and Indexed.IsPlaying then Indexed else nil
	end
	for _, Track in Animator:GetPlayingAnimationTracks() do
		local Anim = Track.Animation
		if Anim and AssetKey(Anim.AnimationId) == Key then
			return Track
		end
	end
	return nil
end

function TrackDriver.Resolve(
	Animator: Animator,
	AnimationId: string,
	Step: StepTracks?
): AnimationTrack?
	local Existing = TrackDriver.Find(Animator, AnimationId, Step)
	if Existing then
		return Existing
	end
	local Ok, Loaded = pcall(Animator.LoadAnimation, Animator, AnimationForId(AnimationId))
	if not Ok or not Loaded then
		return nil
	end
	Loaded.Priority = Priority
	return Loaded
end

function TrackDriver.Collapse(
	Animator: Animator,
	AnimationId: string,
	Step: StepTracks?
): AnimationTrack?
	local Key = AssetKey(AnimationId)
	local Keep: AnimationTrack? = nil
	local Tracks = if Step and Step.Animator == Animator
		then Step.Tracks
		else Animator:GetPlayingAnimationTracks()
	for _, Track in Tracks do
		local Anim = Track.Animation
		if Anim and Track.IsPlaying and AssetKey(Anim.AnimationId) == Key then
			if not Keep or Track.TimePosition > (Keep :: AnimationTrack).TimePosition then
				Keep = Track
			end
		end
	end
	if not Keep then
		return nil
	end
	for _, Track in Tracks do
		local Anim = Track.Animation
		if Track ~= Keep and Anim and Track.IsPlaying and AssetKey(Anim.AnimationId) == Key then
			Track:Stop(0)
		end
	end
	return Keep
end

function TrackDriver.Length(Animator: Animator, AnimationId: string, Step: StepTracks?): number?
	local Track = TrackDriver.Find(Animator, AnimationId, Step)
	if Track and Track.Length > 0 then
		return ObserveDuration(AnimationId, Track)
	end
	return DurationById[AssetKey(AnimationId)]
end

local function ResolvePrepared(
	Animator: Animator,
	AnimationId: string,
	Step: StepTracks?
): AnimationTrack?
	local Existing = TrackDriver.Find(Animator, AnimationId, Step)
	if Existing then
		return Existing
	end

	local Animation = AnimationById[AssetKey(AnimationId)]
	if not Animation then
		return nil
	end

	local Ok, Loaded = pcall(Animator.LoadAnimation, Animator, Animation)
	if not Ok or not Loaded then
		return nil
	end
	Loaded.Priority = Priority
	return Loaded
end

local function NeedsWeight(Current: number, Wanted: number): boolean
	if Wanted <= WeightEpsilon or Wanted >= 1 - WeightEpsilon then
		return math.abs(Current - Wanted) > WeightEpsilon
	end
	return math.abs(Current - Wanted) > WeightCommandBand
end

local function IsManagedPriority(Track: AnimationTrack): boolean
	return Track.Priority == Enum.AnimationPriority.Core
		or Track.Priority == Enum.AnimationPriority.Idle
end

local function MakeRoom(Animator: Animator, Exclude: AnimationTrack, Step: StepTracks?): boolean
	if not IsManagedPriority(Exclude) then
		return true
	end

	local Tracks = if Step and Step.Animator == Animator
		then Step.Tracks
		else Animator:GetPlayingAnimationTracks()
	local Managed = 0
	for _, Track in Tracks do
		if Track.IsPlaying and ManagedTracks[Track] and IsManagedPriority(Track) then
			Managed += 1
		end
	end

	local AddsTrack = not Exclude.IsPlaying
	local Needed = Managed - ManagedTrackBudget + (if AddsTrack then 1 else 0)
	while Needed > 0 do
		local Candidate: AnimationTrack? = nil
		local Weight = math.huge
		for _, Track in Tracks do
			if
				Track ~= Exclude
				and Track.IsPlaying
				and ManagedTracks[Track]
				and IsManagedPriority(Track)
				and Track.WeightTarget <= WeightEpsilon
				and Track.WeightTarget < Weight
			then
				Candidate = Track
				Weight = Track.WeightTarget
			end
		end
		if not Candidate then
			return false
		end
		Candidate:Stop(0)
		Needed -= 1
	end
	return true
end

function TrackDriver.Restart(Animator: Animator, Target: Target, Step: StepTracks?): boolean
	local Track = TrackDriver.Find(Animator, Target.Id, Step)
	if not Track then
		local Ok, Loaded = pcall(Animator.LoadAnimation, Animator, AnimationForId(Target.Id))
		if not Ok or not Loaded then
			return false
		end
		Track = Loaded
	end
	local Live = Track :: AnimationTrack
	ManagedTracks[Live] = true
	ObserveDuration(Target.Id, Live)
	if Target.Priority and Live.Priority ~= Target.Priority then
		Live.Priority = Target.Priority
	end
	if not MakeRoom(Animator, Live, Step) then
		return false
	end
	Live.Looped = Target.Looped
	if Live.IsPlaying then
		Live:Stop(0)
	end
	Live:Play(Target.Fade, Target.Weight, Target.Rate)
	AddStepTrack(Step, Animator, Live)
	return true
end

function TrackDriver.Drive(
	Animator: Animator,
	Target: Target,
	State: Instance?,
	Step: StepTracks?
): number?
	local Wanted = if Target.Sustain then math.max(Target.Weight, RetainedWeight) else Target.Weight
	local Wants = Target.Sustain or Wanted > WeightEpsilon
	local Track = TrackDriver.Find(Animator, Target.Id, Step)

	if not Track then
		if not Wants or (Target.Sustain and Target.Weight <= WeightEpsilon) then
			return
		end
		if Completed(Target) then
			return
		end
		Track = ResolvePrepared(Animator, Target.Id, Step)
		if not Track then
			return
		end
	end

	local Live = Track :: AnimationTrack
	ManagedTracks[Live] = true
	ObserveDuration(Target.Id, Live)

	if Target.Priority and Live.Priority ~= Target.Priority then
		Live.Priority = Target.Priority
	end

	if not Live.IsPlaying then
		if not Wants or (Target.Sustain and Target.Weight <= WeightEpsilon) then
			return
		end
		if Completed(Target) or not MakeRoom(Animator, Live, Step) then
			return
		end
		Live.Looped = Target.Looped
		Live:Play(Target.Fade, Wanted, Target.Rate)
		AddStepTrack(Step, Animator, Live)
		local Cycle = if Target.CycleAttribute and State
			then State:GetAttribute(Target.CycleAttribute)
			else nil
		if Target.Cycle ~= nil then
			Cycle = Target.Cycle
		end
		if type(Cycle) == "number" and Cycle >= 0 and Cycle < 1 and Live.Length > 0 then
			Live.TimePosition = (Cycle % 1) * Live.Length
		end
		return
	end

	if Live.Looped ~= Target.Looped then
		Live.Looped = Target.Looped
	end

	if not Wants then
		if Live.WeightTarget > WeightEpsilon then
			local Cycle: number? = nil
			if Target.CycleAttribute and Live.Length > 0 then
				Cycle = (Live.TimePosition / Live.Length) % 1
			end
			Live:Stop(Target.Fade)
			return Cycle
		end
		return
	end

	if not Target.Sustain and Live.WeightTarget <= WeightEpsilon then
		Live.TimePosition = 0
	end

	local Current = Live.WeightTarget
	if NeedsWeight(Current, Wanted) then
		local Fade = Target.Fade
		if Current > BlendVisible and Wanted > BlendVisible then
			Fade = BlendFade
		end
		Live:AdjustWeight(Wanted, Fade)
	end
	if
		(Wanted > RetainedWeight or Current > RetainedWeight)
		and math.abs(Live.Speed - Target.Rate) > SpeedCommandBand
	then
		Live:AdjustSpeed(Target.Rate)
	end
end

function TrackDriver.VisibleCycle(
	Animator: Animator,
	AnimationIds: { string },
	Step: StepTracks?
): number?
	local BestWeight = WeightEpsilon
	local Cycle: number? = nil
	for _, Id in AnimationIds do
		local Track = TrackDriver.Find(Animator, Id, Step)
		if Track and Track.IsPlaying and Track.Length > 0 and Track.WeightTarget > BestWeight then
			BestWeight = Track.WeightTarget
			Cycle = (Track.TimePosition / Track.Length) % 1
		end
	end
	return Cycle
end

function TrackDriver.Apply(
	Animator: Animator,
	Targets: { Target },
	Count: number,
	State: Instance?,
	Step: StepTracks?
)
	for Index = 1, Count do
		local Target = Targets[Index]
		if Target and Target.Id ~= "" then
			local Attribute = Target.CycleAttribute
			local Cycle = TrackDriver.Drive(Animator, Target, State, Step)
			if Cycle ~= nil and Attribute and State then
				State:SetAttribute(Attribute, Cycle)
			end
		end
	end
end

function TrackDriver.StopKnown(Animator: Animator, Ids: { string }, Fade: number, Step: StepTracks?)
	for _, Id in Ids do
		if Id ~= "" then
			local Track = TrackDriver.Find(Animator, Id, Step)
			if Track and Track.IsPlaying then
				Track:Stop(Fade)
			end
		end
	end
end

function TrackDriver.StopAll(Animator: Animator, Ids: { string }, Fade: number)
	local Managed: { [string]: boolean } = {}
	for _, Id in Ids do
		if Id ~= "" then
			Managed[AssetKey(Id)] = true
		end
	end

	for _, Track in Animator:GetPlayingAnimationTracks() do
		local Anim = Track.Animation
		if Anim and Track.IsPlaying and Managed[AssetKey(Anim.AnimationId)] then
			Track:Stop(Fade)
		end
	end
end

function TrackDriver.Prepare(AnimationIds: { string })
	for _, Id in AnimationIds do
		if Id ~= "" then
			AnimationForId(Id)
		end
	end
end

function TrackDriver.Warm(Humanoid: Humanoid, AnimationIds: { string })
	TrackDriver.Prepare(AnimationIds)
	if not TrackDriver.EnsureAnimator(Humanoid) then
		return
	end

	local Assets: { Animation } = {}
	local Seen: { [string]: boolean } = {}
	for _, Id in AnimationIds do
		local Key = AssetKey(Id)
		if Id ~= "" and not Seen[Key] and not PreloadedIds[Key] then
			Seen[Key] = true
			local Asset = AnimationById[Key]
			if Asset then
				Assets[#Assets + 1] = Asset
			end
		end
	end

	if #Assets == 0 then
		return
	end

	local Ok = pcall(ContentProvider.PreloadAsync, ContentProvider, Assets)
	if Ok then
		for _, Asset in Assets do
			PreloadedIds[AssetKey(Asset.AnimationId)] = true
		end
	end
end

return TrackDriver

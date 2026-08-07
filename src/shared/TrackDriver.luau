--!strict

local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local TrackDriver = {}

export type Target = {
	Id: string,
	Weight: number,
	Rate: number,
	Fade: number,
	Looped: boolean,
	Sustain: boolean,
	-- nil keeps the track's current priority.
	Priority: Enum.AnimationPriority?,
}

local WeightEpsilon = 0.001
local SpeedEpsilon = 0.01
local SettledEpsilon = 0.002
local BlendFade = 0.1
local BlendVisible = 0.01
local Priority = Enum.AnimationPriority.Core
local IsClient = RunService:IsClient()

local ActionPriorities: { [Enum.AnimationPriority]: boolean } = {
	[Enum.AnimationPriority.Action] = true,
	[Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true,
	[Enum.AnimationPriority.Action4] = true,
}

local AnimationById: { [string]: Animation } = {}
local PreloadedIds: { [string]: boolean } = {}
local HasGetTrackById: boolean? = nil
local PreparedAnimators: { [Animator]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Stock stores http:// asset URLs, we normalize to rbxassetid://; both resolve
-- to the same asset.
local function AssetKey(AnimationId: string): string
	return AnimationId:match("%d+") or AnimationId
end

local function AnimationForId(AnimationId: string): Animation
	local Existing = AnimationById[AnimationId]
	if Existing then
		return Existing
	end
	local Created = Instance.new("Animation")
	Created.AnimationId = AnimationId
	AnimationById[AnimationId] = Created
	return Created
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

-- Match Roblox's Server Authority Animate bootstrap: prediction is enabled
-- synchronously before either peer starts loading tracks.
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

-- Never cache track handles: rollback replaces them.
function TrackDriver.Find(Animator: Animator, AnimationId: string): AnimationTrack?
	if HasGetTrackById == nil then
		HasGetTrackById = type((Animator :: any).GetTrackByAnimationId) == "function"
	end
	if HasGetTrackById then
		local Direct = (Animator :: any):GetTrackByAnimationId(AnimationId)
		if Direct then
			return Direct
		end
	end
	local Key = AssetKey(AnimationId)
	for _, Track in Animator:GetPlayingAnimationTracks() do
		local Anim = Track.Animation
		if Anim and AssetKey(Anim.AnimationId) == Key then
			return Track
		end
	end
	return nil
end

function TrackDriver.Resolve(Animator: Animator, AnimationId: string): AnimationTrack?
	local Existing = TrackDriver.Find(Animator, AnimationId)
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

-- Honour the fade even before the asset streams in.
function TrackDriver.Drive(Animator: Animator, Target: Target)
	local Wanted = Target.Weight
	local Track = TrackDriver.Find(Animator, Target.Id)

	if not Track then
		if Wanted <= WeightEpsilon and not Target.Sustain then
			return
		end
		Track = TrackDriver.Resolve(Animator, Target.Id)
		if not Track then
			return
		end
	end

	local Live = Track :: AnimationTrack

	if Target.Priority and Live.Priority ~= Target.Priority then
		Live.Priority = Target.Priority
	end

	if not Live.IsPlaying then
		if Wanted <= WeightEpsilon and not Target.Sustain then
			return
		end
		Live.Looped = Target.Looped
		Live:Play(Target.Fade, Wanted, Target.Rate)
		return
	end

	if Live.Looped ~= Target.Looped then
		Live.Looped = Target.Looped
	end

	-- Rewind a pose re-armed mid-fade.
	if
		not Target.Sustain
		and Wanted > WeightEpsilon
		and Live.WeightTarget <= WeightEpsilon
	then
		Live.TimePosition = 0
	end

	if math.abs(Live.WeightTarget - Wanted) > WeightEpsilon then
		-- Stock uses the pose transition time only when a pose enters or leaves,
		-- and AdjustWeight's default for the continuous walk/run blend.
		local Fade = Target.Fade
		if Live.WeightTarget > BlendVisible and Wanted > BlendVisible then
			Fade = BlendFade
		end
		Live:AdjustWeight(Wanted, Fade)
	end
	if math.abs(Live.Speed - Target.Rate) > SpeedEpsilon then
		Live:AdjustSpeed(Target.Rate)
	end

	if
		not Target.Sustain
		and Wanted <= WeightEpsilon
		and Live.WeightCurrent <= SettledEpsilon
	then
		Live:Stop(0)
	end
end

function TrackDriver.Apply(Animator: Animator, Targets: { Target }, Count: number)
	for Index = 1, Count do
		local Target = Targets[Index]
		if Target and Target.Id ~= "" then
			TrackDriver.Drive(Animator, Target)
		end
	end
end

-- Sweeps live tracks rather than resolving each id: a copy left behind by stock
-- or by a takeover is often unresolvable, and must still be released.
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

function TrackDriver.VisibleId(Animator: Animator, Ids: { string }): (string?, number)
	local FallbackId: string? = nil
	local FallbackTime = 0
	for _, Id in Ids do
		local Track = TrackDriver.Find(Animator, Id)
		if Track and Track.IsPlaying then
			if Track.WeightTarget > WeightEpsilon then
				return Id, Track.TimePosition
			end
			if FallbackId == nil then
				FallbackId = Id
				FallbackTime = Track.TimePosition
			end
		end
	end
	return FallbackId, FallbackTime
end

function TrackDriver.IsActionPlaying(Animator: Animator): boolean
	-- Never retain action handles.
	for _, Track in Animator:GetPlayingAnimationTracks() do
		if
			ActionPriorities[Track.Priority]
			and Track.IsPlaying
			and Track.WeightCurrent > WeightEpsilon
		then
			return true
		end
	end
	return false
end

-- Assets only; Drive creates every track.
function TrackDriver.Warm(Humanoid: Humanoid, AnimationIds: { string })
	if not TrackDriver.EnsureAnimator(Humanoid) then
		return
	end

	local Assets: { Animation } = {}
	local Seen: { [string]: boolean } = {}
	for _, Id in AnimationIds do
		if Id ~= "" and not Seen[Id] and not PreloadedIds[Id] then
			Seen[Id] = true
			local Asset = AnimationForId(Id)
			Assets[#Assets + 1] = Asset
		end
	end

	if #Assets == 0 then
		return
	end

	local Ok = pcall(ContentProvider.PreloadAsync, ContentProvider, Assets)
	if Ok then
		for _, Asset in Assets do
			PreloadedIds[Asset.AnimationId] = true
		end
	end
end

return TrackDriver

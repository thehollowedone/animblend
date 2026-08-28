--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local CharacterBinder = require(Root:WaitForChild("CharacterBinder"))
local Config = require(Root:WaitForChild("Config"))
local DirectionalSolver = require(Root:WaitForChild("DirectionalSolver"))
local LocomotionSolver = require(Root:WaitForChild("LocomotionSolver"))
local PoseCatalog = require(Root:WaitForChild("PoseCatalog"))
local StockCatalog = require(Root:WaitForChild("StockCatalog"))
local TrackDriver = require(Root:WaitForChild("TrackDriver"))

local AnimBlend = {}

local ServerReadyAttribute = "AnimBlendServerReady"
local ServerReadyTimeout = 30
local StepFrequency = Config.SimulationFrequency
local StepPriority = Config.SimulationPriority
local DefaultHipHeight = 2
local DefaultRootHeight = 2
local VariantVisible = 0.5
local VariantSelectionPeriod = 8
local AirMaterial = Enum.Material.Air
local SlotInfo = LocomotionSolver.SlotInfo

local IsClient = RunService:IsClient()
local Started = false

if
	type(StepPriority) ~= "number"
	or StepPriority ~= StepPriority
	or math.abs(StepPriority) == math.huge
	or StepPriority % 1 ~= 0
then
	error("AnimBlend: Config.SimulationPriority must be a finite integer")
end
local ValidStepFrequency = StepFrequency == Enum.StepFrequency.Hz60
	or StepFrequency == Enum.StepFrequency.Hz30
	or StepFrequency == Enum.StepFrequency.Hz15
	or StepFrequency == Enum.StepFrequency.Hz10
	or StepFrequency == Enum.StepFrequency.Hz5
	or StepFrequency == Enum.StepFrequency.Hz1
if not ValidStepFrequency then
	error("AnimBlend: Config.SimulationFrequency must be an Enum.StepFrequency value")
end

local ExternalControlAttribute = Config.ExternalControlAttribute
if
	ExternalControlAttribute ~= nil
	and (type(ExternalControlAttribute) ~= "string" or ExternalControlAttribute == "")
then
	error("AnimBlend: Config.ExternalControlAttribute must be nil or a non-empty string")
end

local Buffer: { TrackDriver.Target } = {}
local IndexById: { [string]: number } = {}
local DirectionalWeights: { number } = {}
local Count = 0
local PendingStepErrors: { [CharacterBinder.Session]: string } = setmetatable({}, { __mode = "k" }) :: any
local ReportedStepErrors: { [CharacterBinder.Session]: boolean } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

local function IsLive(InstanceValue: Instance): boolean
	return (InstanceValue :: any).Parent ~= nil
end

local function FindWhichIsA(Parent: Instance, ClassName: string): Instance?
	return Parent:FindFirstChildWhichIsA(ClassName)
end

local function CurrentRoot(Session: CharacterBinder.Session): BasePart?
	local HumanoidRoot = Session.Humanoid.RootPart
	if HumanoidRoot and IsLive(HumanoidRoot) then
		return HumanoidRoot
	end
	if IsLive(Session.Root) then
		return Session.Root
	end
	return nil
end

local function GeometryScale(RootPart: BasePart): number
	return math.max(RootPart.Size.Y / DefaultRootHeight, 0.01)
end

local function HeightScale(Session: CharacterBinder.Session, RootPart: BasePart): number
	if Session.Profile.UseRigScale then
		return 1
	end

	local Geometry = GeometryScale(RootPart)
	local Hip = Session.Humanoid.HipHeight
	local Damp = Session.ScaleDamp
	local HipScale = math.max(Hip / DefaultHipHeight, 0.01)
	if Damp and Damp.Parent ~= nil then
		HipScale = math.max(1 + (Hip - DefaultHipHeight) * Damp.Value / DefaultHipHeight, 0.01)
	end
	return math.max(Geometry, HipScale)
end

local function RigScale(Session: CharacterBinder.Session, RootPart: BasePart): number
	if not Session.Profile.UseRigScale then
		return 1
	end
	return GeometryScale(RootPart)
end

local function CurrentBucket(Session: CharacterBinder.Session): number
	return math.floor(time() / VariantSelectionPeriod) + Session.Seed
end

local function ShouldDrive(Session: CharacterBinder.Session): boolean
	return CharacterBinder.ShouldDrive(Session)
end

local function ChooseId(
	Catalog: PoseCatalog.Catalog,
	Slot: string,
	Ids: { string },
	Bucket: number,
	Weight: number
): string?
	if #Ids == 1 then
		return Ids[1]
	end

	local Primary = Catalog.Primary[Slot] or Ids[1]
	if Weight < VariantVisible then
		return Primary
	end
	return PoseCatalog.Pick(Catalog, Slot, Bucket) or Primary
end

local JumpStartedAttribute = "AnimBlendJumpStartedAt"
local JumpPhaseAttribute = "AnimBlendJumpPhase"
local SwimActiveAttribute = "AnimBlendSwimActive"
local IdleStartedAttribute = "AnimBlendIdleStartedAt"
local CycleAttributes: { [string]: string } = {
	idle = "AnimBlendIdleCycle",
	walk = "AnimBlendWalkCycle",
	run = "AnimBlendRunCycle",
}
local DirectionalCycleAttribute = "AnimBlendLocomotionCycle"
local EmoteInputAttribute = StockCatalog.EmoteInputAttribute
local EmoteSlotAttribute = "AnimBlendEmoteSlot"
local EmoteIdAttribute = "AnimBlendEmoteId"
local EmoteStartAttribute = "AnimBlendEmoteStartedAt"
local EmoteEndAttribute = "AnimBlendEmoteEndsAt"
local ToolSlotAttribute = "AnimBlendToolSlot"
local ToolIdAttribute = "AnimBlendToolId"
local ToolStartAttribute = "AnimBlendToolStartedAt"
local ToolEndAttribute = "AnimBlendToolEndsAt"
local ToolSequenceAttribute = "ToolAnimationSequence"
local ToolStartedAttribute = "ToolAnimationStartedAt"
local ToolInputContextAttribute = "ToolAnimationInputContext"
local ToolInputActionAttribute = "ToolAnimationInputAction"
local ToolCancelledSequenceAttribute = "AnimBlendToolCancelledSequence"
local ToolCancelledIdAttribute = "AnimBlendToolCancelledId"
local LegacyToolAnimationName = "toolanim"

type ToolRequest = {
	Sequence: number,
	Slot: string,
	Id: string,
	StartedAt: number,
}

type ToolPrediction = {
	Signal: Instance,
	BaseSequence: number,
	Slot: string,
	Id: string,
	StartedAt: number,
}

local ProcessedToolRequests: { [Instance]: ToolRequest } = setmetatable({}, { __mode = "k" }) :: any
local PredictedToolRequests: { [Instance]: ToolPrediction } = setmetatable({}, { __mode = "k" }) :: any
local LastToolStates: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local CancelledToolHandles: { [CharacterBinder.Session]: Instance } = setmetatable(
	{},
	{ __mode = "k" }
) :: any
local LastLegacyToolSignals: { [Instance]: Instance } = setmetatable({}, { __mode = "k" }) :: any
local LastToolHandles: { [any]: Instance } = setmetatable({}, { __mode = "k" }) :: any
local PendingToolPhases: { [Animator]: { Id: string, StartedAt: number } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any
local StockFade = 0.1
local CycleAttributeList = {
	CycleAttributes.idle,
	CycleAttributes.walk,
	CycleAttributes.run,
	DirectionalCycleAttribute,
}

local function ClearSustainState(RootPart: BasePart)
	for _, Attribute in CycleAttributeList do
		if RootPart:GetAttribute(Attribute) ~= nil then
			RootPart:SetAttribute(Attribute, nil)
		end
	end
	if RootPart:GetAttribute(IdleStartedAttribute) ~= nil then
		RootPart:SetAttribute(IdleStartedAttribute, nil)
	end
end

local function IdleVariantsReady(RootPart: BasePart, Weight: number): boolean
	local Started = RootPart:GetAttribute(IdleStartedAttribute)
	if Weight < VariantVisible then
		if Started ~= nil then
			RootPart:SetAttribute(IdleStartedAttribute, nil)
		end
		return false
	end

	local Now = time()
	if type(Started) ~= "number" or Started > Now then
		RootPart:SetAttribute(IdleStartedAttribute, Now)
		return false
	end
	return Now - Started >= VariantSelectionPeriod
end

local function ClearJumpState(RootPart: BasePart)
	RootPart:SetAttribute(JumpStartedAttribute, nil)
	RootPart:SetAttribute(JumpPhaseAttribute, nil)
end

local function JumpElapsed(
	Session: CharacterBinder.Session,
	RootPart: BasePart,
	StateName: string
): number?
	if not Session.Catalog.Slots.jump then
		return nil
	end

	local Now = time()
	local Started = RootPart:GetAttribute(JumpStartedAttribute)
	local Phase = RootPart:GetAttribute(JumpPhaseAttribute)

	if StateName == "Jumping" then
		local StartedAt: number
		if Phase ~= "Jumping" or type(Started) ~= "number" then
			StartedAt = Now
			RootPart:SetAttribute(JumpStartedAttribute, StartedAt)
			RootPart:SetAttribute(JumpPhaseAttribute, "Jumping")
		else
			StartedAt = Started
		end
		return math.max(Now - StartedAt, 0)
	end

	if StateName == "Freefall" then
		if type(Started) == "number" then
			if Phase ~= "Freefall" then
				RootPart:SetAttribute(JumpPhaseAttribute, "Freefall")
			end
			return math.max(Now - Started, 0)
		end
		return nil
	end

	ClearJumpState(RootPart)
	return nil
end

local ClearEmoteState: (BasePart) -> ()
local ClearToolState: (BasePart) -> ()
local EventBucket: (CharacterBinder.Session) -> number
local ReadEmoteEvent: (CharacterBinder.Session, BasePart) -> string?
local ChooseEmote: (CharacterBinder.Session, string, number) -> (string?, string?)
local UpdateEmote: (
	CharacterBinder.Session,
	BasePart,
	Animator,
	boolean,
	TrackDriver.StepTracks
) -> (string?, string?)

local function Push(
	Id: string,
	Weight: number,
	Rate: number,
	Fade: number,
	Looped: boolean,
	Sustain: boolean,
	Priority: Enum.AnimationPriority?,
	CycleAttribute: string?,
	Cycle: number?,
	Elapsed: number?
)
	local Index = IndexById[Id]
	if Index then
		local Existing = Buffer[Index]
		if Weight > Existing.Weight then
			Existing.Weight = Weight
			Existing.Rate = Rate
			Existing.Fade = Fade
			Existing.CycleAttribute = CycleAttribute
			Existing.Cycle = Cycle
			Existing.Elapsed = Elapsed
		end
		Existing.Looped = Existing.Looped or Looped
		Existing.Sustain = Existing.Sustain or Sustain
		if Priority and (not Existing.Priority or Priority.Value > Existing.Priority.Value) then
			Existing.Priority = Priority
		end
		return
	end

	Count += 1
	local Target = Buffer[Count]
	if Target then
		Target.Id = Id
		Target.Weight = Weight
		Target.Rate = Rate
		Target.Fade = Fade
		Target.Looped = Looped
		Target.Sustain = Sustain
		Target.Priority = Priority
		Target.CycleAttribute = CycleAttribute
		Target.Cycle = Cycle
		Target.Elapsed = Elapsed
	else
		Buffer[Count] = {
			Id = Id,
			Weight = Weight,
			Rate = Rate,
			Fade = Fade,
			Looped = Looped,
			Sustain = Sustain,
			Priority = Priority,
			CycleAttribute = CycleAttribute,
			Cycle = Cycle,
			Elapsed = Elapsed,
		}
	end
	IndexById[Id] = Count
end

local function PushEmotes(Session: CharacterBinder.Session, ActiveSlot: string?, ActiveId: string?)
	for _, Slot in StockCatalog.EmoteSlots do
		local Ids = Session.Catalog.SlotIds[Slot]
		if Ids then
			for _, Id in Ids do
				local Active = Slot == ActiveSlot and Id == ActiveId
				Push(
					Id,
					if Active then 1 else 0,
					1,
					StockFade,
					StockCatalog.LoopedEmotes[Slot] == true,
					false,
					Enum.AnimationPriority.Core,
					nil,
					nil
				)
			end
		end
	end
end

local function CancelToolRequest(
	Session: CharacterBinder.Session,
	RootPart: BasePart,
	Handle: Instance?
)
	if not Handle then
		return
	end
	local Request = ProcessedToolRequests[Handle]
	if not Request then
		return
	end
	CancelledToolHandles[Session] = Handle
	RootPart:SetAttribute(ToolCancelledSequenceAttribute, Request.Sequence)
	RootPart:SetAttribute(ToolCancelledIdAttribute, Request.Id)
end

local function IsToolRequestCancelled(
	Session: CharacterBinder.Session,
	RootPart: BasePart,
	Handle: Instance,
	Request: ToolRequest
): boolean
	return CancelledToolHandles[Session] == Handle
		and RootPart:GetAttribute(ToolCancelledSequenceAttribute) == Request.Sequence
		and RootPart:GetAttribute(ToolCancelledIdAttribute) == Request.Id
end

local function ClearToolCancellation(Session: CharacterBinder.Session, RootPart: BasePart)
	CancelledToolHandles[Session] = nil
	RootPart:SetAttribute(ToolCancelledSequenceAttribute, nil)
	RootPart:SetAttribute(ToolCancelledIdAttribute, nil)
end

local function PushTools(
	Session: CharacterBinder.Session,
	RootPart: BasePart,
	Animator: Animator,
	Handle: Instance?,
	Bucket: number,
	StepTracks: TrackDriver.StepTracks
)
	local function StopAction(Id: any)
		if type(Id) ~= "string" then
			return
		end
		local Track = TrackDriver.Find(Animator, Id, StepTracks)
		if Track and Track.IsPlaying then
			Track:Stop(0)
		end
	end

	local PreviousHandle = LastToolHandles[Session]
	if PreviousHandle ~= Handle then
		StopAction(RootPart:GetAttribute(ToolIdAttribute))
		if PreviousHandle then
			CancelToolRequest(Session, RootPart, PreviousHandle)
			PredictedToolRequests[PreviousHandle] = nil
		end
		LastToolHandles[Session] = Handle
		ClearToolState(RootPart)
	end

	local HasSynchronizedInput = false
	if Handle then
		local ContextName = Handle:GetAttribute(ToolInputContextAttribute)
		local ActionName = Handle:GetAttribute(ToolInputActionAttribute)
		HasSynchronizedInput = type(ContextName) == "string" and type(ActionName) == "string"
	end
	local Now = if HasSynchronizedInput then time() else Workspace:GetServerTimeNow()
	local ActiveSlot = RootPart:GetAttribute(ToolSlotAttribute)
	local ActiveId = RootPart:GetAttribute(ToolIdAttribute)
	local StartedAt = RootPart:GetAttribute(ToolStartAttribute)
	local Ends = RootPart:GetAttribute(ToolEndAttribute)
	if
		type(ActiveSlot) ~= "string"
		or type(ActiveId) ~= "string"
		or type(StartedAt) ~= "number"
		or type(Ends) ~= "number"
	then
		ActiveSlot, ActiveId, StartedAt, Ends = nil, nil, nil, nil
	end

	if not Handle then
		StopAction(ActiveId)
		ClearToolState(RootPart)
		ActiveSlot, ActiveId, StartedAt, Ends = nil, nil, nil, nil
	elseif ActiveSlot and Now >= Ends then
		StopAction(ActiveId)
		ClearToolState(RootPart)
		ActiveSlot, ActiveId, StartedAt, Ends = nil, nil, nil, nil
	end

	if Handle then
		local Tool = Handle.Parent
		local LegacySignal = if Tool then Tool:FindFirstChild(LegacyToolAnimationName) else nil
		if LegacySignal and not LegacySignal:IsA("StringValue") then
			LegacySignal = nil
		end
		local SynchronizedState = if HasSynchronizedInput then Handle:GetAttribute("State") else nil
		local SynchronizedRequest = if type(SynchronizedState) == "string"
			then StockCatalog.ToolSlotByState[SynchronizedState]
			else nil
		local IsSynchronizedEdge = SynchronizedRequest ~= nil and SynchronizedRequest ~= "toolnone"
		if IsSynchronizedEdge then
			Handle:SetAttribute("State", "None")
		end

		local ReplicatedSequence = Handle:GetAttribute(ToolSequenceAttribute)
		local IsNewLegacyEdge = not HasSynchronizedInput
			and LegacySignal ~= nil
			and LastLegacyToolSignals[Handle] ~= LegacySignal
		local Prediction = if HasSynchronizedInput then nil else PredictedToolRequests[Handle]
		if HasSynchronizedInput then
			PredictedToolRequests[Handle] = nil
		end
		if Prediction and Now >= Prediction.StartedAt + StockCatalog.ToolDuration then
			PredictedToolRequests[Handle] = nil
			Prediction = nil
		end

		local HoldPrediction = false
		if Prediction and not IsNewLegacyEdge then
			if
				type(ReplicatedSequence) == "number"
				and ReplicatedSequence > Prediction.BaseSequence
			then
				local CommittedState = Handle:GetAttribute("State")
				local CommittedSlot = if type(CommittedState) == "string"
					then StockCatalog.ToolSlotByState[CommittedState]
					else nil
				if CommittedSlot == Prediction.Slot then
					ProcessedToolRequests[Handle] = {
						Sequence = ReplicatedSequence,
						Slot = Prediction.Slot,
						Id = Prediction.Id,
						StartedAt = Prediction.StartedAt,
					}
					PredictedToolRequests[Handle] = nil
					Prediction = nil
				elseif LegacySignal == Prediction.Signal then
					Prediction.BaseSequence = ReplicatedSequence
					HoldPrediction = true
				else
					PredictedToolRequests[Handle] = nil
					Prediction = nil
				end
			else
				HoldPrediction = true
			end
		end

		if HoldPrediction and Prediction then
			ActiveSlot = Prediction.Slot
			ActiveId = Prediction.Id
			StartedAt = Prediction.StartedAt
			Ends = StartedAt + StockCatalog.ToolDuration
			RootPart:SetAttribute(ToolSlotAttribute, ActiveSlot)
			RootPart:SetAttribute(ToolIdAttribute, ActiveId)
			RootPart:SetAttribute(ToolStartAttribute, StartedAt)
			RootPart:SetAttribute(ToolEndAttribute, Ends)
		end

		local RequestSequence = if HasSynchronizedInput or IsNewLegacyEdge
			then nil
			else ReplicatedSequence
		local HasSequence = type(RequestSequence) == "number"
		local State = if HasSynchronizedInput
			then SynchronizedState
			elseif IsNewLegacyEdge then (LegacySignal :: StringValue).Value
			elseif HasSequence then Handle:GetAttribute("State")
			elseif LegacySignal then (LegacySignal :: StringValue).Value
			else Handle:GetAttribute("State")
		local Requested = if type(State) == "string"
			then StockCatalog.ToolSlotByState[State]
			else nil
		if not Requested or Requested == "toolnone" then
			LastToolStates[Handle] = nil
			if not LegacySignal then
				LastLegacyToolSignals[Handle] = nil
			end
		end
		if not HoldPrediction and Requested and Requested ~= "toolnone" then
			local Ids = Session.Catalog.SlotIds[Requested]
			local Id = if Ids then ChooseId(Session.Catalog, Requested, Ids, Bucket, 1) else nil
			local IsLegacyEdge = not HasSynchronizedInput
				and not HasSequence
				and if LegacySignal
					then LastLegacyToolSignals[Handle] ~= LegacySignal
					else LastToolStates[Handle] ~= State
			local IsRequestEdge = IsSynchronizedEdge or IsLegacyEdge
			if IsLegacyEdge then
				LastToolStates[Handle] = State :: string
				if LegacySignal then
					LastLegacyToolSignals[Handle] = LegacySignal
				end
			end
			local Processed = ProcessedToolRequests[Handle]
			local IsSameSequence = Processed ~= nil
				and HasSequence
				and RequestSequence == Processed.Sequence
			local IsExactConfirmation = Id ~= nil
				and IsSameSequence
				and Processed ~= nil
				and Processed.Slot == Requested
				and Processed.Id == Id
			local IsStale = (not HasSequence and not IsRequestEdge)
				or (Processed ~= nil and HasSequence and RequestSequence < Processed.Sequence)
				or (IsSameSequence and not IsExactConfirmation)
			if not IsStale then
				if Id then
					local LiveTrack = TrackDriver.Find(Animator, Id, StepTracks)
					local IsConfirmation = IsExactConfirmation
					local KnownEnds = if IsConfirmation
						then Processed.StartedAt + StockCatalog.ToolDuration
						else nil
					if
						IsConfirmation
						and not IsToolRequestCancelled(
							Session,
							RootPart,
							Handle,
							Processed :: ToolRequest
						)
						and Now < (KnownEnds :: number)
					then
						ActiveSlot, ActiveId, StartedAt, Ends =
							Requested, Id, Processed.StartedAt, KnownEnds
						RootPart:SetAttribute(ToolSlotAttribute, ActiveSlot)
						RootPart:SetAttribute(ToolIdAttribute, ActiveId)
						RootPart:SetAttribute(ToolStartAttribute, StartedAt)
						RootPart:SetAttribute(ToolEndAttribute, Ends)
						if not LiveTrack or not LiveTrack.IsPlaying then
							local Restored = TrackDriver.Restart(Animator, {
								Id = Id,
								Weight = 1,
								Rate = 1,
								Fade = 0,
								Looped = false,
								Sustain = false,
								Priority = Enum.AnimationPriority.Action,
								CycleAttribute = nil,
								Cycle = nil,
							}, StepTracks)
							if Restored then
								PendingToolPhases[Animator] = {
									Id = Id,
									StartedAt = Processed.StartedAt,
								}
							end
						end
					elseif not IsConfirmation then
						ClearToolCancellation(Session, RootPart)
						if ActiveId ~= Id then
							StopAction(ActiveId)
						end
						local Started = if Processed == nil then LiveTrack else nil
						if not Started or not Started.IsPlaying then
							local DidStart = TrackDriver.Restart(Animator, {
								Id = Id,
								Weight = 1,
								Rate = 1,
								Fade = 0,
								Looped = false,
								Sustain = false,
								Priority = Enum.AnimationPriority.Action,
								CycleAttribute = nil,
								Cycle = nil,
							}, StepTracks)
							Started = if DidStart
								then TrackDriver.Find(Animator, Id, StepTracks)
								else nil
						end
						if Started then
							local Elapsed =
								math.clamp(Started.TimePosition, 0, StockCatalog.ToolDuration)
							local CommittedStart = Handle:GetAttribute(ToolStartedAttribute)
							local ActionStart = if HasSequence
									and type(CommittedStart) == "number"
								then CommittedStart
								else Now - Elapsed
							ActiveSlot, ActiveId, StartedAt, Ends =
								Requested, Id, ActionStart, ActionStart + StockCatalog.ToolDuration
							RootPart:SetAttribute(ToolSlotAttribute, ActiveSlot)
							RootPart:SetAttribute(ToolIdAttribute, ActiveId)
							RootPart:SetAttribute(ToolStartAttribute, StartedAt)
							RootPart:SetAttribute(ToolEndAttribute, Ends)
							if HasSequence then
								ProcessedToolRequests[Handle] = {
									Sequence = RequestSequence,
									Slot = Requested,
									Id = Id,
									StartedAt = ActionStart,
								}
							elseif LegacySignal and not HasSynchronizedInput then
								PredictedToolRequests[Handle] = {
									Signal = LegacySignal,
									BaseSequence = if type(ReplicatedSequence) == "number"
										then ReplicatedSequence
										else -1,
									Slot = Requested,
									Id = Id,
									StartedAt = ActionStart,
								}
							end
						end
					end
				end
			end
		end
	end

	local ToolIdleIds = Session.Catalog.SlotIds.toolnone
	if ToolIdleIds then
		local Weight = if Handle and not ActiveId then 1 else 0
		local Chosen = ChooseId(Session.Catalog, "toolnone", ToolIdleIds, Bucket, Weight)
		for _, Id in ToolIdleIds do
			Push(
				Id,
				if Id == Chosen then Weight else 0,
				1,
				StockFade,
				true,
				false,
				Enum.AnimationPriority.Idle,
				nil,
				nil
			)
		end
	end
	if ActiveId then
		TrackDriver.Collapse(Animator, ActiveId, StepTracks)
	end
end

local function CorrectPendingToolPhases()
	for Animator, Pending in PendingToolPhases do
		PendingToolPhases[Animator] = nil
		local ActiveTrack = TrackDriver.Find(Animator, Pending.Id)
		if ActiveTrack and ActiveTrack.IsPlaying then
			ActiveTrack.TimePosition = math.clamp(
				Workspace:GetServerTimeNow() - Pending.StartedAt,
				0,
				StockCatalog.ToolDuration
			)
		end
	end
end

local function ReleaseManagedTracks(
	Session: CharacterBinder.Session,
	RootPart: BasePart,
	Animator: Animator,
	StepTracks: TrackDriver.StepTracks
)
	local Handle = LastToolHandles[Session]
	CancelToolRequest(Session, RootPart, Handle)
	PendingToolPhases[Animator] = nil
	ClearJumpState(RootPart)
	ClearSustainState(RootPart)
	ClearEmoteState(RootPart)
	ClearToolState(RootPart)
	if RootPart:GetAttribute(SwimActiveAttribute) ~= nil then
		RootPart:SetAttribute(SwimActiveAttribute, nil)
	end
	TrackDriver.StopKnown(Animator, Session.Catalog.AllIds, 0, StepTracks)
end

local function StepSession(Session: CharacterBinder.Session)
	if not Session.Owns or not IsLive(Session.Humanoid) then
		return
	end

	local RootPart = CurrentRoot(Session)
	if not RootPart then
		return
	end

	local Animator = FindWhichIsA(Session.Humanoid, "Animator") :: Animator?
	if not Animator or not ShouldDrive(Session) then
		return
	end
	local StepTracks = TrackDriver.BeginStep(Animator)

	local Humanoid = Session.Humanoid
	local StateName = Humanoid:GetState().Name
	local ExternalControl = ExternalControlAttribute ~= nil
		and Session.Character:GetAttribute(ExternalControlAttribute) == true
	-- These are direct ownership/lifecycle signals, so they take precedence over
	-- a state value that may still reflect the preceding simulation edge.
	if Humanoid.PlatformStand or Humanoid.Health <= 0 or ExternalControl then
		ReleaseManagedTracks(Session, RootPart, Animator, StepTracks)
		return
	end

	local Catalog = Session.Catalog
	local Profile = Session.Profile
	local Velocity = Humanoid:GetRelativeVelocityAtFloor()
	local Horizontal = math.sqrt(Velocity.X * Velocity.X + Velocity.Z * Velocity.Z)
	local JumpTime = JumpElapsed(Session, RootPart, StateName)
	local Height = HeightScale(Session, RootPart)

	local Field = LocomotionSolver.Solve({
		StateName = StateName,
		GroundSpeed = Horizontal,
		TotalSpeed = Velocity.Magnitude,
		ClimbSpeed = math.abs(Velocity.Y),
		OnAir = Humanoid.FloorMaterial == AirMaterial,
		HeightScale = Height,
		RigScale = RigScale(Session, RootPart),
		JumpElapsed = JumpTime,
		WantsMove = Humanoid.MoveDirection.Magnitude > 0,
		WasSwimming = StateName == "Swimming"
			and RootPart:GetAttribute(SwimActiveAttribute) == true,
		WalkIsDefault = Catalog.WalkIsDefault,
	}, Profile)
	if not Field.Resolved then
		ReleaseManagedTracks(Session, RootPart, Animator, StepTracks)
		return
	end
	local CanEmote = (StateName == "Running" or StateName == "RunningNoPhysics")
		and Humanoid.MoveDirection.Magnitude <= Profile.BlendEpsilon
		and Horizontal <= Profile.MoveGate
	local EmoteSlot, EmoteId = UpdateEmote(Session, RootPart, Animator, CanEmote, StepTracks)
	local LocomotionWeight = if EmoteId then 0 else 1

	if StateName == "Swimming" then
		local SwimActive = Field.Swim > VariantVisible
		if RootPart:GetAttribute(SwimActiveAttribute) ~= SwimActive then
			RootPart:SetAttribute(SwimActiveAttribute, SwimActive)
		end
	elseif RootPart:GetAttribute(SwimActiveAttribute) ~= nil then
		RootPart:SetAttribute(SwimActiveAttribute, nil)
	end

	Count = 0
	table.clear(IndexById)

	local AnyField: any = Field
	local AnyProfile: any = Profile
	local Bucket = CurrentBucket(Session)
	local Tool = FindWhichIsA(Session.Character, "Tool")
	local ToolHandle = if Tool then Tool:FindFirstChild("Handle") else nil
	local DirectionalEnabled = Catalog.HasDirectional and Profile.Name == "R15"
	local DirectionalRate: number? = nil
	local LocomotionCycle = TrackDriver.VisibleCycle(
		Animator,
		Catalog.SlotIds.walk or {},
		StepTracks
	) or TrackDriver.VisibleCycle(Animator, Catalog.SlotIds.run or {}, StepTracks)
	if DirectionalEnabled and not EmoteId and Field.Walk + Field.Run > VariantVisible then
		local Frame = RootPart.CFrame
		DirectionalRate = DirectionalSolver.Solve(
			Frame.RightVector:Dot(Velocity),
			Frame.LookVector:Dot(Velocity),
			Height,
			Catalog.Directional,
			DirectionalWeights
		)
	end
	local UseDirectional = DirectionalRate ~= nil

	local Fade = AnyProfile.FadeIdle
	local Dominant = -1
	for _, Info in SlotInfo do
		local Weight = AnyField[Info.Key] * LocomotionWeight
		if Weight > Dominant then
			Dominant = Weight
			Fade = AnyProfile[Info.Fade]
		end
	end

	for _, Info in SlotInfo do
		if DirectionalEnabled and (Info.Slot == "walk" or Info.Slot == "run") then
			continue
		end
		local Ids = Catalog.SlotIds[Info.Slot]
		if Ids then
			local Weight = AnyField[Info.Key] * LocomotionWeight
			local Chosen: string?
			if Info.Slot == "idle" and #Ids > 1 and not IdleVariantsReady(RootPart, Weight) then
				Chosen = Catalog.Primary[Info.Slot] or Ids[1]
			else
				Chosen = ChooseId(Catalog, Info.Slot, Ids, Bucket, Weight)
			end
			local Rate = if Info.Rate then AnyField[Info.Rate] else 1
			local CycleAttribute = CycleAttributes[Info.Slot]
			for _, Id in Ids do
				local Active = Id == Chosen
				Push(
					Id,
					if Active then Weight else 0,
					Rate,
					Fade,
					Info.Looped,
					Info.Sustain and Active,
					nil,
					CycleAttribute,
					if Info.Slot == "walk" or Info.Slot == "run" then LocomotionCycle else nil,
					if Info.Slot == "jump" then JumpTime else nil
				)
			end
		end
	end

	if DirectionalEnabled then
		local Cycle = if UseDirectional
			then TrackDriver.VisibleCycle(Animator, Catalog.DirectionalIds, StepTracks)
			else nil
		for Index, Entry in Catalog.Directional do
			local Weight = if UseDirectional then DirectionalWeights[Index] or 0 else 0
			if Weight <= Profile.BlendEpsilon then
				Push(
					Entry.Id,
					0,
					DirectionalRate or 1,
					Profile.FadeWalk,
					true,
					true,
					nil,
					DirectionalCycleAttribute,
					Cycle
				)
			end
		end
		for Index, Entry in Catalog.Directional do
			local Weight = if UseDirectional then DirectionalWeights[Index] or 0 else 0
			if Weight > Profile.BlendEpsilon then
				Push(
					Entry.Id,
					Weight,
					DirectionalRate or 1,
					Profile.FadeWalk,
					true,
					true,
					nil,
					DirectionalCycleAttribute,
					Cycle
				)
			end
		end
	end

	PushEmotes(Session, EmoteSlot, EmoteId)

	PushTools(Session, RootPart, Animator, ToolHandle, Bucket, StepTracks)

	TrackDriver.Apply(Animator, Buffer, Count, RootPart, StepTracks)
end

ClearEmoteState = function(RootPart: BasePart)
	RootPart:SetAttribute(EmoteSlotAttribute, nil)
	RootPart:SetAttribute(EmoteIdAttribute, nil)
	RootPart:SetAttribute(EmoteStartAttribute, nil)
	RootPart:SetAttribute(EmoteEndAttribute, nil)
end

ClearToolState = function(RootPart: BasePart)
	RootPart:SetAttribute(ToolSlotAttribute, nil)
	RootPart:SetAttribute(ToolIdAttribute, nil)
	RootPart:SetAttribute(ToolStartAttribute, nil)
	RootPart:SetAttribute(ToolEndAttribute, nil)
end

EventBucket = function(Session: CharacterBinder.Session): number
	return math.floor(time() * 60 + 0.5) + Session.Seed
end

ReadEmoteEvent = function(Session: CharacterBinder.Session, RootPart: BasePart): string?
	local Action = Session.EmoteAction
	if not Action or not IsLive(Action) then
		return nil
	end
	local Ok, State = pcall(Action.GetState, Action)
	if not Ok or type(State) ~= "number" then
		return nil
	end
	local Value = math.floor(State + 0.5)
	local Previous = RootPart:GetAttribute(EmoteInputAttribute)
	if type(Previous) ~= "number" then
		Previous = 0
	end
	if Previous == Value then
		return nil
	end
	RootPart:SetAttribute(EmoteInputAttribute, Value)
	local Index = Value % StockCatalog.EmoteFireToggle
	return StockCatalog.EmoteNameByIndex[Index]
end

ChooseEmote = function(
	Session: CharacterBinder.Session,
	Requested: string,
	Bucket: number
): (string?, string?)
	local Catalog = Session.Catalog
	local Slot = Requested
	if Requested == "dance" and Session.Profile.Name == "R6" then
		local Available = {}
		for _, Candidate in StockCatalog.R6DanceSlots do
			if Catalog.SlotIds[Candidate] then
				Available[#Available + 1] = Candidate
			end
		end
		if #Available > 0 then
			Slot = Available[(Bucket % #Available) + 1]
		end
	elseif not Catalog.SlotIds[Slot] and string.sub(Slot, 1, 5) == "dance" then
		Slot = if Catalog.SlotIds.dance then "dance" else Slot
	end
	local Ids = Catalog.SlotIds[Slot]
	if not Ids then
		return nil, nil
	end
	return Slot, ChooseId(Catalog, Slot, Ids, Bucket, 1)
end

UpdateEmote = function(
	Session: CharacterBinder.Session,
	RootPart: BasePart,
	Animator: Animator,
	CanEmote: boolean,
	StepTracks: TrackDriver.StepTracks
): (string?, string?)
	local Now = time()
	local Slot = RootPart:GetAttribute(EmoteSlotAttribute)
	local Id = RootPart:GetAttribute(EmoteIdAttribute)
	if type(Slot) ~= "string" or type(Id) ~= "string" then
		Slot, Id = nil, nil
	end

	if Slot and Id then
		if not CanEmote then
			ClearEmoteState(RootPart)
			Slot, Id = nil, nil
		elseif not StockCatalog.LoopedEmotes[Slot] then
			local Started = RootPart:GetAttribute(EmoteStartAttribute)
			local Ends = RootPart:GetAttribute(EmoteEndAttribute)
			if type(Started) ~= "number" then
				ClearEmoteState(RootPart)
				Slot, Id = nil, nil
			elseif type(Ends) ~= "number" then
				local Length = TrackDriver.Length(Animator, Id, StepTracks)
				if Length then
					Ends = Started + Length
					RootPart:SetAttribute(EmoteEndAttribute, Ends)
				elseif Now - Started >= 10 then
					ClearEmoteState(RootPart)
					Slot, Id = nil, nil
				end
			end
			if Slot and type(Ends) == "number" and Now >= Ends then
				ClearEmoteState(RootPart)
				Slot, Id = nil, nil
			end
		end
	end

	local Requested = ReadEmoteEvent(Session, RootPart)
	if Requested and (CanEmote or Slot ~= nil) then
		local ChosenSlot, ChosenId = ChooseEmote(Session, Requested, EventBucket(Session))
		if ChosenSlot and ChosenId then
			Slot, Id = ChosenSlot, ChosenId
			RootPart:SetAttribute(EmoteSlotAttribute, Slot)
			RootPart:SetAttribute(EmoteIdAttribute, Id)
			RootPart:SetAttribute(EmoteStartAttribute, Now)
			local Length = TrackDriver.Length(Animator, Id, StepTracks)
			RootPart:SetAttribute(
				EmoteEndAttribute,
				if StockCatalog.LoopedEmotes[Slot] or not Length then nil else Now + Length
			)
			TrackDriver.Restart(Animator, {
				Id = Id,
				Weight = 1,
				Rate = 1,
				Fade = StockFade,
				Looped = StockCatalog.LoopedEmotes[Slot] == true,
				Sustain = false,
				Priority = Enum.AnimationPriority.Core,
				CycleAttribute = nil,
				Cycle = nil,
			}, StepTracks)
		end
	end
	return Slot, Id
end

AnimBlend.Step = StepSession

local function StepAll()
	local Sessions = CharacterBinder.Sessions
	for Index = #Sessions, 1, -1 do
		local Session = Sessions[Index]
		if Session then
			local Ok, Message = pcall(StepSession, Session)
			if not Ok and not ReportedStepErrors[Session] then
				PendingStepErrors[Session] = tostring(Message)
			end
		end
	end
end

local function ReportStepErrors()
	for Session, Message in PendingStepErrors do
		PendingStepErrors[Session] = nil
		ReportedStepErrors[Session] = true
		warn(("AnimBlend isolated a character simulation error: %s"):format(Message))
	end
end

local function AfterSimulation()
	CorrectPendingToolPhases()
	ReportStepErrors()
end

local function WaitForServerReady()
	local Thread = coroutine.running()
	local Resumed = false
	local Conn: RBXScriptConnection? = nil

	local function Finish(TimedOut: boolean)
		if Resumed then
			return
		end
		Resumed = true
		if Conn then
			Conn:Disconnect()
			Conn = nil
		end
		task.spawn(Thread, TimedOut)
	end

	Conn = Root:GetAttributeChangedSignal(ServerReadyAttribute):Connect(function()
		if Root:GetAttribute(ServerReadyAttribute) == true then
			Finish(false)
		end
	end)
	task.delay(ServerReadyTimeout, Finish, true)

	if coroutine.yield() then
		warn(
			("AnimBlend: server never published %s within %d seconds; starting anyway"):format(
				ServerReadyAttribute,
				ServerReadyTimeout
			)
		)
	end
end

function AnimBlend.Init()
	if Started then
		return
	end

	if IsClient then
		if Root:GetAttribute(ServerReadyAttribute) ~= true then
			WaitForServerReady()
		end
	else
		Root:SetAttribute(ServerReadyAttribute, false)
	end

	-- Workspace.AuthorityMode is RobloxScriptSecurity and cannot be read by
	-- ordinary server or client scripts. BindToSimulation is the capability-safe
	-- runtime boundary we actually require; per-character prediction status is
	-- then checked by CharacterBinder before any animation drive.
	local Bound, BindingError =
		pcall(RunService.BindToSimulation, RunService, StepAll, StepFrequency, StepPriority)
	if not Bound then
		error(
			("AnimBlend requires Server Authority and RunService:BindToSimulation(): %s"):format(
				tostring(BindingError)
			),
			2
		)
	end
	Started = true

	CharacterBinder.Start()
	RunService.PostSimulation:Connect(AfterSimulation)

	if not IsClient then
		Root:SetAttribute(ServerReadyAttribute, true)
	end
end

return AnimBlend

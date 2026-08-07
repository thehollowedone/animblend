--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local CharacterBinder = require(Root:WaitForChild("CharacterBinder"))
local Config = require(Root:WaitForChild("Config"))
local LocomotionSolver = require(Root:WaitForChild("LocomotionSolver"))
local PoseCatalog = require(Root:WaitForChild("PoseCatalog"))
local TrackDriver = require(Root:WaitForChild("TrackDriver"))

local AnimBlend = {}

local ServerReadyAttribute = "AnimBlendServerReady"
local ServerReadyTimeout = 30
local StepFrequency = Enum.StepFrequency.Hz60
local StepPriority = 4001
local DefaultHipHeight = 2
local WrapWindow = 0.06
local VariantVisible = 0.5
local VariantSelectionHz = 4
local AirMaterial = Enum.Material.Air
local SlotInfo = LocomotionSolver.SlotInfo

local IsClient = RunService:IsClient()
local Started = false

local Buffer: { TrackDriver.Target } = {}
local IndexById: { [string]: number } = {}
local Count = 0

-- Hoisted: no per-frame closure.
local function ReadAutomaticScaling(Humanoid: Humanoid)
	return Humanoid.AutomaticScalingEnabled
end

local function ReadModelScale(Character: Model)
	return Character:GetScale()
end

local function HeightScale(Session: CharacterBinder.Session): number
	local Humanoid = Session.Humanoid

	local BodyHeightScale = Humanoid:FindFirstChild("BodyHeightScale")
	if BodyHeightScale and BodyHeightScale:IsA("NumberValue") and BodyHeightScale.Value > 0 then
		return BodyHeightScale.Value
	end

	local Ok, Automatic = pcall(ReadAutomaticScaling, Humanoid)
	if not Ok or not Automatic then
		return 1
	end

	local Hip = Humanoid.HipHeight
	local Damp = Session.ScaleDamp
	if Damp and Damp.Parent then
		return math.max(1 + (Hip - DefaultHipHeight) * Damp.Value / DefaultHipHeight, 0.01)
	end
	return math.max(Hip / DefaultHipHeight, 0.01)
end

local function RigScale(Session: CharacterBinder.Session): number
	if not Session.Profile.UseRigScale then
		return 1
	end
	local Ok, Scale = pcall(ReadModelScale, Session.Character)
	if Ok and type(Scale) == "number" and Scale > 0 then
		return Scale
	end
	return 1
end

local function CurrentBucket(): number
	-- Simulation clock: replay-stable on both peers.
	return math.floor(time() * VariantSelectionHz)
end

local function ChooseId(
	Animator: Animator,
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

	local Current, Elapsed = TrackDriver.VisibleId(Animator, Ids)
	local Desired = PoseCatalog.Pick(Catalog, Slot, Bucket)

	if Current and Desired ~= Current and Elapsed > WrapWindow then
		return Current
	end
	return Desired or Current or Primary
end

local JumpStartedAttribute = "AnimBlendJumpStartedAt"
local JumpPhaseAttribute = "AnimBlendJumpPhase"

local function ClearJumpState(Session: CharacterBinder.Session)
	Session.Humanoid:SetAttribute(JumpStartedAttribute, nil)
	Session.Humanoid:SetAttribute(JumpPhaseAttribute, nil)
end

local function JumpElapsed(Session: CharacterBinder.Session, StateName: string): number?
	if not Session.Catalog.Slots.jump then
		return nil
	end

	local Now = time()
	local Humanoid = Session.Humanoid
	local Started = Humanoid:GetAttribute(JumpStartedAttribute)
	local Phase = Humanoid:GetAttribute(JumpPhaseAttribute)

	if StateName == "Jumping" then
		-- New jump, not a replayed one.
		if Phase ~= "Jumping" or type(Started) ~= "number" then
			Started = Now
			Humanoid:SetAttribute(JumpStartedAttribute, Started)
			Humanoid:SetAttribute(JumpPhaseAttribute, "Jumping")
		end
		return math.max(Now - Started, 0)
	end

	if StateName == "Freefall" then
		if type(Started) == "number" then
			if Phase ~= "Freefall" then
				Humanoid:SetAttribute(JumpPhaseAttribute, "Freefall")
			end
			return math.max(Now - Started, 0)
		end
		return nil
	end

	ClearJumpState(Session)
	return nil
end

local function Push(
	Id: string,
	Weight: number,
	Rate: number,
	Fade: number,
	Looped: boolean,
	Sustain: boolean,
	Priority: Enum.AnimationPriority?
)
	local Index = IndexById[Id]
	if Index then
		local Existing = Buffer[Index]
		if Weight > Existing.Weight then
			Existing.Weight = Weight
			Existing.Rate = Rate
			Existing.Fade = Fade
		end
		Existing.Looped = Existing.Looped or Looped
		Existing.Sustain = Existing.Sustain or Sustain
		Existing.Priority = Existing.Priority or Priority
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
	else
		Buffer[Count] = {
			Id = Id,
			Weight = Weight,
			Rate = Rate,
			Fade = Fade,
			Looped = Looped,
			Sustain = Sustain,
			Priority = Priority,
		}
	end
	IndexById[Id] = Count
end

local function StepSession(Session: CharacterBinder.Session)
	if not Session.Owns then
		return
	end

	if
		Session.PartsDirty
		or not Session.Character.Parent
		or not Session.Humanoid.Parent
		or not Session.Root.Parent
	then
		if not CharacterBinder.Refresh(Session) then
			return
		end
	end

	local Humanoid = Session.Humanoid
	local StateName = Humanoid:GetState().Name
	-- Re-release on every replay.
	if Humanoid.PlatformStand or LocomotionSolver.ReleasesTracks(StateName) then
		ClearJumpState(Session)
		local Animator = Humanoid:FindFirstChildOfClass("Animator")
		if Animator then
			TrackDriver.StopAll(Animator, Session.Catalog.AllIds, 0)
		end
		return
	end

	local Animator = TrackDriver.EnsureAnimator(Humanoid)
	if not Animator then
		return
	end

	local Catalog = Session.Catalog
	local Profile = Session.Profile
	local Velocity = Session.Root.AssemblyLinearVelocity
	local Horizontal = math.sqrt(Velocity.X * Velocity.X + Velocity.Z * Velocity.Z)
	local JumpTime = JumpElapsed(Session, StateName)

	local Field = LocomotionSolver.Solve({
		StateName = StateName,
		GroundSpeed = Horizontal,
		TotalSpeed = Velocity.Magnitude,
		ClimbSpeed = math.abs(Velocity.Y),
		OnAir = Humanoid.FloorMaterial == AirMaterial,
		HeightScale = HeightScale(Session),
		RigScale = RigScale(Session),
		JumpElapsed = JumpTime,
		ActionPlaying = Config.RespectActionPriority ~= false
			and TrackDriver.IsActionPlaying(Animator),
		WalkIsDefault = Catalog.WalkIsDefault,
	}, Profile)

	Count = 0
	table.clear(IndexById)

	local AnyField: any = Field
	local AnyProfile: any = Profile
	local Bucket = CurrentBucket()

	local Fade = AnyProfile.FadeIdle
	local Dominant = -1
	for _, Info in SlotInfo do
		local Weight = AnyField[Info.Key]
		if Weight > Dominant then
			Dominant = Weight
			Fade = AnyProfile[Info.Fade]
		end
	end

	for _, Info in SlotInfo do
		local Ids = Catalog.SlotIds[Info.Slot]
		if Ids then
			local Weight = AnyField[Info.Key]
			local Chosen = ChooseId(Animator, Catalog, Info.Slot, Ids, Bucket, Weight)
			local Rate = if Info.Rate then AnyField[Info.Rate] else 1
			for _, Id in Ids do
				local Active = Id == Chosen
				Push(
					Id,
					if Active then Weight else 0,
					Rate,
					Fade,
					Info.Looped,
					Info.Sustain and Active
				)
			end
		end
	end

	-- Additive Idle-priority layer.
	local ToolIds = Catalog.SlotIds.toolnone
	if ToolIds then
		-- Stock requires a Handle.
		local Tool = Session.Character:FindFirstChildOfClass("Tool")
		local ToolWeight = if Tool and Tool:FindFirstChild("Handle") then 1 else 0
		local ToolChosen = ChooseId(Animator, Catalog, "toolnone", ToolIds, Bucket, ToolWeight)
		for _, Id in ToolIds do
			local Active = Id == ToolChosen
			Push(
				Id,
				if Active then ToolWeight else 0,
				1,
				Profile.FadeTool,
				true,
				false,
				Enum.AnimationPriority.Idle
			)
		end
	end

	TrackDriver.Apply(Animator, Buffer, Count)
end

AnimBlend.Step = StepSession

local function StepServer()
	local Sessions = CharacterBinder.Sessions
	for Index = #Sessions, 1, -1 do
		local Session = Sessions[Index]
		if Session then
			StepSession(Session)
		end
	end
end

-- Must stay on BindToSimulation, never PreRender/PostSimulation.
local function StepClientSimulation()
	local LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then
		return
	end
	local Character = LocalPlayer.Character
	if not Character then
		return
	end
	local Session = CharacterBinder.Get(Character)
	if Session then
		StepSession(Session)
	end
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
	Started = true

	if IsClient then
		if Root:GetAttribute(ServerReadyAttribute) ~= true then
			WaitForServerReady()
		end
	else
		Root:SetAttribute(ServerReadyAttribute, true)
	end

	-- Hand off stock Animate before binding the driver.
	CharacterBinder.Start()
	CharacterBinder.SetOwning(true)

	-- Run immediately after stock's Hz60/4000 slot. If stock already bound before
	-- its bootstrap scripts were disabled, AnimBlend remains the final writer.
	if IsClient then
		RunService:BindToSimulation(StepClientSimulation, StepFrequency, StepPriority)
	else
		RunService:BindToSimulation(StepServer, StepFrequency, StepPriority)
	end
end

return AnimBlend

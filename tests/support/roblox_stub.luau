local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Stub = {}

local ServerTime = 1000
local SimulationTime = 1000

local function Signal()
	return {
		__signal = true,
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end

-- A fireable event, distinct from the inert Signal() above: supports Connect,
-- Once and Fire so tests can exercise event-driven code paths (AnimationPlayed,
-- Stopped) rather than only polling ones.
local function Event()
	local Listeners = {}
	local Ev
	Ev = {
		__signal = true,
		ConnectCount = 0,
		Connect = function(_, Fn)
			Ev.ConnectCount += 1
			local Entry = { Fn = Fn, Connected = true }
			table.insert(Listeners, Entry)
			return {
				Disconnect = function()
					Entry.Connected = false
				end,
			}
		end,
		Once = function(_, Fn)
			local Entry = { Connected = true }
			Entry.Fn = function(...)
				Entry.Connected = false
				Fn(...)
			end
			table.insert(Listeners, Entry)
			return {
				Disconnect = function()
					Entry.Connected = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, Entry in Listeners do
				if Entry.Connected then
					Entry.Fn(...)
				end
			end
		end,
		Wait = function(_)
			local Co = coroutine.running()
			Ev:Once(function(...)
				local Ok, Err = coroutine.resume(Co, ...)
				if not Ok then
					error(Err, 0)
				end
			end)
			return coroutine.yield()
		end,
	}
	return Ev
end
Stub.Event = Event

-- A single Heartbeat shared across every Animator/Session built in this test
-- run, regardless of whether they came from Stub.Build() or were constructed
-- directly - RunService.Heartbeat fires once per frame globally, not once per
-- character, so anything suspended on a real Heartbeat:Wait() resumes the next
-- time ANY test drives a frame forward via Stub.Advance.
local SharedHeartbeat = Event()
Stub.Heartbeat = SharedHeartbeat

local function EnumItem(Name: string, Value: number)
	return { Name = Name, Value = Value }
end

local Enum = {
	AnimationPriority = {
		Core = EnumItem("Core", 0),
		Idle = EnumItem("Idle", 1),
		Movement = EnumItem("Movement", 2),
		Action = EnumItem("Action", 3),
		Action2 = EnumItem("Action2", 4),
		Action3 = EnumItem("Action3", 5),
		Action4 = EnumItem("Action4", 6),
	},
	AuthorityMode = {
		Automatic = EnumItem("Automatic", 0),
		Server = EnumItem("Server", 1),
	},
	Material = { Air = EnumItem("Air", 1), Plastic = EnumItem("Plastic", 2) },
	HumanoidRigType = { R6 = EnumItem("R6", 0), R15 = EnumItem("R15", 1) },
	PredictionMode = {
		Automatic = EnumItem("Automatic", 0),
		On = EnumItem("On", 1),
		Off = EnumItem("Off", 2),
	},
	PredictionStatus = {
		None = EnumItem("None", 0),
		Authoritative = EnumItem("Authoritative", 1),
	},
	StepFrequency = {
		Hz60 = EnumItem("Hz60", 0),
		Hz30 = EnumItem("Hz30", 1),
		Hz15 = EnumItem("Hz15", 2),
		Hz10 = EnumItem("Hz10", 3),
		Hz5 = EnumItem("Hz5", 4),
		Hz1 = EnumItem("Hz1", 5),
	},
	InputActionType = {
		Direction1D = EnumItem("Direction1D", 0),
	},
}

Stub.Enum = Enum

function Stub.Vector3(X: number, Y: number, Z: number)
	return {
		X = X,
		Y = Y,
		Z = Z,
		Magnitude = math.sqrt(X * X + Y * Y + Z * Z),
		Dot = function(Self, Other)
			return Self.X * Other.X + Self.Y * Other.Y + Self.Z * Other.Z
		end,
	}
end

function Stub.Vector2(X: number, Y: number)
	return {
		X = X,
		Y = Y,
		Magnitude = math.sqrt(X * X + Y * Y),
		__type = "Vector2",
	}
end

-- StreamsLate models Roblox's real "Length reads 0 until the asset has
-- actually streamed in" behavior. A track built with StreamsLate=true starts
-- at Length=0; RevealLength() (fired by the stub's ContentProvider.PreloadAsync
-- once its assets are handed to it) sets it to the real value.
function Stub.Track(AnimationId: string, Length: number, StreamsLate: boolean?)
	local Track
	Track = {
		AnimationId = AnimationId,
		Animation = { AnimationId = AnimationId },
		Length = if StreamsLate then 0 else Length,
		RevealLength = function(_)
			Track.Length = Length
		end,
		IsPlaying = false,
		Looped = true,
		Priority = Enum.AnimationPriority.Core,
		Speed = 1,
		TimePosition = 0,
		Elapsed = 0,
		WeightTarget = 1,
		WeightCurrent = 1,
		PlayCount = 0,
		StopCount = 0,
		StopIn = nil,
		MuteCount = 0,
		FadeLeft = 0,
		FadeTotal = 0,
		FadeFrom = 0,
		LastPlayFade = -1,
		LastStopFade = -1,
		WeightCalls = 0,
		SpeedCalls = 0,
		LastWeightFade = -1,
		-- Models Roblox's real behavior: Animator:GetTrackByAnimationId can stop
		-- returning a track once it has fully stopped and settled. The next cycle
		-- must then load a fresh track rather than retain this stale handle.
		Forgotten = false,
		Stopped = Event(),

		Play = function(_, Fade, Weight, Rate)
			Track.IsPlaying = true
			Track.Forgotten = false
			Track.StopIn = nil
			Track.PlayCount += 1
			Track.LastPlayFade = Fade
			Track.WeightTarget = Weight or 1
			Track.Speed = Rate or 1
			Track.TimePosition = 0
			if Fade and Fade > 0 then
				Track.WeightCurrent = 0
				Track.FadeFrom = 0
				Track.FadeLeft = Fade
				Track.FadeTotal = Fade
			else
				Track.WeightCurrent = Track.WeightTarget
				Track.FadeLeft = 0
			end
		end,
		Stop = function(_, Fade)
			Track.StopCount += 1
			Track.LastStopFade = Fade
			Track.WeightTarget = 0
			if Fade and Fade > 0 then
				Track.StopIn = Fade
			else
				Track.IsPlaying = false
				Track.WeightCurrent = 0
				Track.Forgotten = true
				Track.Stopped:Fire()
			end
		end,
		AdjustWeight = function(_, Weight, Fade)
			Track.WeightCalls += 1
			Track.WeightTarget = Weight
			Track.LastWeightFade = Fade
			if Fade and Fade > 0 then
				Track.FadeFrom = Track.WeightCurrent
				Track.FadeLeft = Fade
				Track.FadeTotal = Fade
			else
				Track.WeightCurrent = Weight
				Track.FadeLeft = 0
			end
			if Weight <= 0.0001 then
				Track.MuteCount += 1
			end
		end,
		AdjustSpeed = function(_, Rate)
			Track.SpeedCalls += 1
			Track.Speed = Rate
		end,
	}
	return Track
end

function Stub.Animator(Lengths: { [string]: number }?, LateIds: { [string]: boolean }?)
	local Tracks: { [string]: any } = {}
	local Strays: { any } = {}
	local LoadCallCounts: { [string]: number } = {}
	local AnimationPlayed = Event()
	local Attributes = {}
	local AttributeSignals = {}
	local Animator
	local function Instrument(Track)
		local OriginalPlay = Track.Play
		Track.Play = function(Self, Fade, Weight, Rate)
			OriginalPlay(Self, Fade, Weight, Rate)
			AnimationPlayed:Fire(Track)
		end
		return Track
	end
	Animator = {
		Parent = true,
		PreferLodEnabled = true,
		Tracks = Tracks,
		Strays = Strays,
		LoadCallCounts = LoadCallCounts,
		PlayingTrackScans = 0,
		AnimationPlayed = AnimationPlayed,
		IsA = function(_, ClassName)
			return ClassName == "Animator"
		end,
		GetAttribute = function(_, Name)
			return Attributes[Name]
		end,
		SetAttribute = function(_, Name, Value)
			Attributes[Name] = Value
			local Changed = AttributeSignals[Name]
			if Changed then
				Changed:Fire()
			end
		end,
		GetAttributeChangedSignal = function(_, Name)
			local Changed = AttributeSignals[Name]
			if not Changed then
				Changed = Event()
				AttributeSignals[Name] = Changed
			end
			return Changed
		end,
		Destroy = function(Self)
			local Parent = Self.Parent
			Self.Parent = nil
			if type(Parent) == "table" and Parent.Animator == Self then
				Parent.Animator = nil
			end
		end,
		-- A second live copy of one animation, as observed on a client whose own
		-- LoadAnimation raced the server's replicated track.
		AddStray = function(_, Id: string, Weight: number)
			local Length = if Lengths and Lengths[Id] then Lengths[Id] else 1
			local Track = Instrument(Stub.Track(Id, Length))
			Track:Play(0, Weight, 1)
			table.insert(Strays, Track)
			return Track
		end,
		GetTrackByAnimationId = function(_, Id)
			local Existing = Tracks[Id]
			if Existing and not Existing.Forgotten then
				return Existing
			end
			return nil
		end,
		LoadAnimation = function(_, Animation)
			local Id = Animation.AnimationId
			local Existing = Tracks[Id]
			if Existing and not Existing.Forgotten then
				return Existing
			end
			LoadCallCounts[Id] = (LoadCallCounts[Id] or 0) + 1
			local Length = if Lengths and Lengths[Id] then Lengths[Id] else 1
			local StreamsLate = LateIds ~= nil and LateIds[Id] == true
			local Created = Instrument(Stub.Track(Id, Length, StreamsLate))
			Created.Animation = Animation
			Tracks[Id] = Created
			return Created
		end,
		GetPlayingAnimationTracks = function()
			Animator.PlayingTrackScans += 1
			local Playing = {}
			for _, Track in Tracks do
				if Track.IsPlaying then
					Playing[#Playing + 1] = Track
				end
			end
			-- Strays are visible here but never through GetTrackByAnimationId,
			-- exactly like a client-loaded copy of a replicated track.
			for _, Track in Strays do
				if Track.IsPlaying then
					Playing[#Playing + 1] = Track
				end
			end
			return Playing
		end,
	}
	return Animator
end

function Stub.Advance(Animator, Delta: number)
	ServerTime += Delta
	SimulationTime += Delta
	local Ticking = {}
	for _, Track in Animator.Tracks do
		table.insert(Ticking, Track)
	end
	for _, Track in Animator.Strays do
		table.insert(Ticking, Track)
	end
	for _, Track in Ticking do
		if Track.IsPlaying then
			local Step = Delta * Track.Speed
			Track.Elapsed += Step
			if Track.Length > 0 then
				Track.TimePosition += Step
				if Track.Looped and Track.TimePosition >= Track.Length then
					Track.TimePosition %= Track.Length
				end
			end
			if Track.FadeLeft > 0 then
				Track.FadeLeft -= Delta
				if Track.FadeLeft <= 0 then
					Track.FadeLeft = 0
					Track.WeightCurrent = Track.WeightTarget
				else
					local Alpha = 1 - Track.FadeLeft / Track.FadeTotal
					Track.WeightCurrent = Track.FadeFrom
						+ (Track.WeightTarget - Track.FadeFrom) * Alpha
				end
			end
			if Track.StopIn then
				Track.StopIn -= Delta
				if Track.StopIn <= 0 then
					Track.StopIn = nil
					Track.IsPlaying = false
					Track.WeightCurrent = 0
					Track.Forgotten = true
					Track.Stopped:Fire()
				end
			end
		end
	end
	SharedHeartbeat:Fire()
end

function Stub.Humanoid(Animator)
	local Attributes = {}
	local PropertySignals = {}
	local Humanoid
	Humanoid = {
		Parent = true,
		Animator = Animator,
		ChildAdded = Event(),
		HipHeight = 2,
		FloorMaterial = Enum.Material.Plastic,
		PlatformStand = false,
		EvaluateStateMachine = true,
		Health = 100,
		StateName = "Running",
		AutomaticScalingEnabled = false,
		RigType = Enum.HumanoidRigType.R15,
		MoveDirection = Stub.Vector3(0, 0, 0),
		RelativeVelocity = Stub.Vector3(0, 0, 0),
		IsA = function(_, ClassName)
			return ClassName == "Humanoid"
		end,
		GetPropertyChangedSignal = function(_, Name)
			local Changed = PropertySignals[Name]
			if not Changed then
				Changed = Event()
				PropertySignals[Name] = Changed
			end
			return Changed
		end,
		SetProperty = function(_, Name, Value)
			Humanoid[Name] = Value
			local Changed = PropertySignals[Name]
			if Changed then
				Changed:Fire()
			end
		end,
		GetState = function()
			return { Name = Humanoid.StateName }
		end,
		GetRelativeVelocityAtFloor = function()
			return Humanoid.RelativeVelocity
		end,
		GetAttribute = function(_, Name)
			return Attributes[Name]
		end,
		SetAttribute = function(_, Name, Value)
			Attributes[Name] = Value
		end,
		FindFirstChild = function()
			return nil
		end,
		FindFirstChildOfClass = function(_, ClassName)
			if ClassName == "Animator" then
				return Humanoid.Animator
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(_, ClassName)
			if ClassName == "Animator" then
				return Humanoid.Animator
			end
			return nil
		end,
		SetAnimator = function(_, Value)
			Humanoid.Animator = Value
			Value.Parent = Humanoid
			Humanoid.ChildAdded:Fire(Value)
		end,
	}
	return Humanoid
end

-- Stock Animate only animates a Tool that actually has a Handle, so a stub tool
-- has to be able to answer FindFirstChild("Handle") both ways.
function Stub.Tool(Name: string, WithHandle: boolean?)
	local Children: { [string]: any } = {}
	local Tool: any = nil
	if WithHandle ~= false then
		local Attributes = {}
		Children.Handle = {
			ClassName = "Part",
			Name = "Handle",
			GetAttribute = function(_, Attribute)
				return Attributes[Attribute]
			end,
			SetAttribute = function(_, Attribute, Value)
				Attributes[Attribute] = Value
			end,
		}
	end
	Tool = {
		ClassName = "Tool",
		Name = Name,
		FindFirstChild = function(_, ChildName)
			return Children[ChildName]
		end,
		SetChild = function(_, ChildName, Child)
			Children[ChildName] = Child
			if Child then
				Child.Parent = Tool
			end
		end,
	}
	if Children.Handle then
		Children.Handle.Parent = Tool
	end
	return Tool
end

function Stub.Session(Humanoid, Profile, Catalog)
	local ToolChild = nil
	local CharacterChildren = {}
	local CharacterAttributes = {}
	local Character
	Character = {
		Parent = true,
		ChildAdded = Event(),
		FindFirstChild = function(_, Name)
			return CharacterChildren[Name]
		end,
		FindFirstChildOfClass = function(_, ClassName)
			if ClassName == "Tool" and ToolChild then
				return ToolChild
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(_, ClassName)
			if ClassName == "Tool" and ToolChild then
				return ToolChild
			end
			return nil
		end,
		SetTool = function(_, ToolOrNil)
			ToolChild = ToolOrNil
		end,
		GetAttribute = function(_, Name)
			return CharacterAttributes[Name]
		end,
		SetAttribute = function(_, Name, Value)
			CharacterAttributes[Name] = Value
		end,
		AddChild = function(_, Child)
			CharacterChildren[Child.Name] = Child
			Character.ChildAdded:Fire(Child)
		end,
	}
	return {
		Character = Character,
		Player = nil,
		Humanoid = Humanoid,
		Root = {
			Parent = true,
			AssemblyLinearVelocity = Stub.Vector3(0, 0, 0),
			Size = Stub.Vector3(2, 2, 1),
			CFrame = {
				RightVector = Stub.Vector3(1, 0, 0),
				LookVector = Stub.Vector3(0, 0, -1),
			},
			Attributes = {},
			GetAttribute = function(self, Name)
				return self.Attributes[Name]
			end,
			SetAttribute = function(self, Name, Value)
				self.Attributes[Name] = Value
			end,
		},
		Animate = nil,
		ScaleDamp = nil,
		EmoteAction = nil,
		PlayEmote = nil,
		Catalog = Catalog,
		CatalogSignature = nil,
		LeasedIds = {},
		Profile = Profile,
		PartsDirty = false,
		Owns = true,
		Drives = true,
		RebuildQueued = false,
		Seed = 0,
		Conns = {},
		AnimateConns = {},
		AnimateInputConns = {},
		HumanoidConns = {},
		CatalogConn = nil,
	}
end

-- A minimal fake Instance tree, just capable enough for PoseCatalog.Build's
-- Collect/ReadWeight walk (IsA, FindFirstChild, GetChildren). Test catalogs are
-- built by feeding this through the REAL PoseCatalog.Build rather than
-- reimplementing its fallback/merge logic by hand, so tests can't drift from
-- production the way a parallel implementation silently did before.
function Stub.NewInstance(ClassName: string, Name: string, Props: { [string]: any }?)
	local PropertySignals = {}
	local AttributeSignals = {}
	local Node: any
	Node = {
		ClassName = ClassName,
		Name = Name,
		Children = {},
		Attributes = {},
		Changed = Event(),
		DescendantAdded = Event(),
		DescendantRemoving = Event(),
		AncestryChanged = Event(),
	}
	if Props then
		for Key, Value in Props do
			Node[Key] = Value
		end
	end
	Node.IsA = function(_, Query)
		return Query == ClassName
	end
	Node.FindFirstChild = function(_, ChildName)
		for _, Child in Node.Children do
			if Child.Name == ChildName then
				return Child
			end
		end
		return nil
	end
	Node.GetChildren = function(_)
		local Copy = {}
		for Index, Child in Node.Children do
			Copy[Index] = Child
		end
		return Copy
	end
	Node.GetAttribute = function(_, AttributeName)
		return Node.Attributes[AttributeName]
	end
	Node.SetAttribute = function(_, AttributeName, Value)
		Node.Attributes[AttributeName] = Value
		local Signal = AttributeSignals[AttributeName]
		if Signal then
			Signal:Fire()
		end
	end
	Node.GetAttributeChangedSignal = function(_, AttributeName)
		local Signal = AttributeSignals[AttributeName]
		if not Signal then
			Signal = Event()
			AttributeSignals[AttributeName] = Signal
		end
		return Signal
	end
	Node.GetPropertyChangedSignal = function(_, PropertyName)
		local Signal = PropertySignals[PropertyName]
		if not Signal then
			Signal = Event()
			PropertySignals[PropertyName] = Signal
		end
		return Signal
	end
	Node.SetProperty = function(_, PropertyName, Value)
		Node[PropertyName] = Value
		Node.Changed:Fire(Value)
		local Signal = PropertySignals[PropertyName]
		if Signal then
			Signal:Fire()
		end
	end
	Node.GetDescendants = function(_)
		local Descendants = {}
		local function Visit(Current)
			for _, Child in Current.Children do
				Descendants[#Descendants + 1] = Child
				Visit(Child)
			end
		end
		Visit(Node)
		return Descendants
	end
	return Node
end

function Stub.BinderCharacter(Humanoid, RootPart, Animate)
	local CurrentHumanoid = Humanoid
	local Children = {
		HumanoidRootPart = RootPart,
		Animate = Animate,
	}
	local Character
	Character = {
		Parent = true,
		AncestryChanged = Event(),
		ChildAdded = Event(),
		ChildRemoved = Event(),
		FindFirstChild = function(_, Name)
			return Children[Name]
		end,
		FindFirstChildOfClass = function(_, ClassName)
			return if ClassName == "Humanoid" then CurrentHumanoid else nil
		end,
		AddChild = function(_, Child)
			Children[Child.Name] = Child
			Child.Parent = Character
			Character.ChildAdded:Fire(Child)
		end,
		AddHumanoid = function(_, NextHumanoid)
			CurrentHumanoid = NextHumanoid
			NextHumanoid.Parent = Character
			Character.ChildAdded:Fire(NextHumanoid)
		end,
	}
	RootPart.Name = "HumanoidRootPart"
	RootPart.Parent = Character
	RootPart.IsA = function(_, ClassName)
		return ClassName == "BasePart"
	end
	Humanoid.Parent = Character
	Humanoid.RootPart = RootPart
	if Animate then
		Animate.Parent = Character
	end
	return Character
end

function Stub.InputAction(Value: number?)
	local State = Value or 0
	return {
		Parent = true,
		GetState = function()
			return State
		end,
		Fire = function(_, Next)
			State = Next
		end,
	}
end

-- SlotSpecs: { [slot] = { { Id = string, Weight = number?, Velocity = Vector2? }, ... } }
function Stub.BuildAnimate(
	SlotSpecs: { [string]: { { Id: string, Weight: number?, Velocity: any? } } }
)
	local Animate = Stub.NewInstance("Folder", "Animate")
	for Slot, Variants in SlotSpecs do
		local Folder = Stub.NewInstance("Folder", Slot)
		for Index, Variant in Variants do
			local Anim = Stub.NewInstance("Animation", "Animation" .. Index, {
				AnimationId = Variant.Id,
			})
			if Variant.Velocity then
				Anim:SetAttribute("LinearVelocity", Variant.Velocity)
			end
			if Variant.Weight then
				table.insert(
					Anim.Children,
					Stub.NewInstance("NumberValue", "Weight", { Value = Variant.Weight })
				)
			end
			table.insert(Folder.Children, Anim)
		end
		table.insert(Animate.Children, Folder)
	end
	return Animate
end

-- Slots: { [slot] = { id, id, ... } } (order doubles as ascending Weight, so the
-- last id in a list is the primary/heaviest unless Weights overrides it)
function Stub.Catalog(
	PoseCatalogModule: any,
	Slots: { [string]: { string } },
	Weights: { [string]: number }?
)
	local SlotSpecs: { [string]: { { Id: string, Weight: number? } } } = {}
	for Slot, Ids in Slots do
		local Variants = {}
		for _, Id in Ids do
			local Weight = if Weights and Weights[Id] then Weights[Id] else nil
			Variants[#Variants + 1] = { Id = Id, Weight = Weight }
		end
		SlotSpecs[Slot] = Variants
	end
	return PoseCatalogModule.Build(Stub.BuildAnimate(SlotSpecs))
end

function Stub.SetServerTime(Value: number)
	ServerTime = Value
	SimulationTime = Value
end

function Stub.Now(): number
	return ServerTime
end

function Stub.AdvanceSimulationTime(Delta: number)
	SimulationTime += Delta
end

function Stub.Build(ConfigOverrides: { [string]: any }?, Client: boolean?, RealBinder: boolean?)
	local Registry: { [any]: any } = {}
	local Modules: { [string]: any } = {}
	local Deferred: { { Fn: (...any) -> (), Args: any } } = {}

	local Workspace = {
		Attributes = {},
		GetServerTimeNow = function()
			return ServerTime
		end,
		GetAttribute = function(self, Name)
			return self.Attributes[Name]
		end,
		SetAttribute = function(self, Name, Value)
			self.Attributes[Name] = Value
		end,
		GetAttributeChangedSignal = function()
			return Signal()
		end,
	}
	setmetatable(Workspace, {
		__index = function(_, Name)
			if Name == "AuthorityMode" then
				error(
					"The current thread cannot read 'AuthorityMode' (lacking capability RobloxScript)"
				)
			end
			return nil
		end,
	})

	local RunService = {
		Heartbeat = SharedHeartbeat,
		PostSimulation = Event(),
		SimulationCallbacks = {},
		SimulationBindings = {},
		BindToSimulation = function(self, Callback, Frequency, Priority)
			if self.BindingError then
				error("stub BindToSimulation unavailable")
			end
			table.insert(self.SimulationCallbacks, Callback)
			table.insert(self.SimulationBindings, {
				Callback = Callback,
				Frequency = Frequency,
				Priority = Priority,
			})
		end,
		BindingError = false,
		IsClient = function()
			return Client == true
		end,
		IsServer = function()
			return Client ~= true
		end,
		PredictionCalls = {},
		PredictionStatus = Enum.PredictionStatus.Authoritative,
		PredictionError = false,
		SetPredictionMode = function(self, Instance, Mode)
			table.insert(self.PredictionCalls, { Instance = Instance, Mode = Mode })
		end,
		GetPredictionStatus = function(self)
			if self.PredictionError then
				error("stub prediction status failure")
			end
			return self.PredictionStatus
		end,
	}

	local LocalPlayer = nil
	if Client then
		local AttributeSignals = {}
		LocalPlayer = {
			UserId = 24680,
			Character = nil,
			DescendantAdded = Signal(),
			Attributes = {},
			FindFirstChild = function()
				return nil
			end,
			GetAttribute = function(self, Name)
				return self.Attributes[Name]
			end,
			GetAttributeChangedSignal = function(_, Name)
				local Changed = AttributeSignals[Name]
				if not Changed then
					Changed = Event()
					AttributeSignals[Name] = Changed
				end
				return Changed
			end,
		}
	end

	local Services = {
		Workspace = Workspace,
		RunService = RunService,
		ContentProvider = {
			PreloadAsync = function() end,
		},
		Players = {
			LocalPlayer = LocalPlayer,
			GetPlayers = function()
				return {}
			end,
			GetPlayerFromCharacter = function()
				return nil
			end,
			PlayerAdded = Signal(),
			PlayerRemoving = Signal(),
		},
	}

	local AnimBlendFolder
	AnimBlendFolder = {
		Attributes = if Client then { AnimBlendServerReady = true } else {},
		AttributeSignals = {},
		GetAttribute = function(self, Name)
			return self.Attributes[Name]
		end,
		SetAttribute = function(self, Name, Value)
			self.Attributes[Name] = Value
			local Changed = self.AttributeSignals[Name]
			if Changed then
				Changed:Fire()
			end
		end,
		GetAttributeChangedSignal = function(self, Name)
			local Changed = self.AttributeSignals[Name]
			if not Changed then
				Changed = Event()
				self.AttributeSignals[Name] = Changed
			end
			return Changed
		end,
		WaitForChild = function(_, Name)
			local Marker = Registry[Name]
			if not Marker then
				Marker = { __module = Name }
				Registry[Name] = Marker
			end
			return Marker
		end,
		FindFirstChild = function()
			return nil
		end,
	}

	Services.ReplicatedStorage = {
		WaitForChild = function()
			return AnimBlendFolder
		end,
	}

	local Env: { [string]: any } = {}
	Env.game = {
		GetService = function(_, Name)
			local Found = Services[Name]
			if not Found then
				error("stub missing service " .. Name)
			end
			return Found
		end,
	}
	Env.workspace = Workspace
	Env.Enum = Enum
	Env.time = function()
		return SimulationTime
	end
	Env.Vector3 = { new = Stub.Vector3 }
	Env.Vector2 = { new = Stub.Vector2 }
	Env.Instance = {
		new = function(ClassName)
			if ClassName == "Animation" then
				return { ClassName = ClassName, AnimationId = "" }
			end
			if ClassName == "StringValue" then
				local Created = {
					ClassName = ClassName,
					Name = "StringValue",
					Value = "",
					Changed = Event(),
					IsA = function(_, Query)
						return Query == "StringValue"
					end,
				}
				return setmetatable(Created, {
					__newindex = function(Self, Key, Value)
						rawset(Self, Key, Value)
						if Key == "Parent" and type(Value) == "table" and Value.AddChild then
							Value:AddChild(Self)
						end
					end,
				})
			end
			if ClassName == "Animator" then
				local Created = Stub.Animator()
				Created.Parent = nil
				return setmetatable(Created, {
					__newindex = function(Self, Key, Value)
						rawset(Self, Key, Value)
						if Key == "Parent" and type(Value) == "table" and Value.SetAnimator then
							Value:SetAnimator(Self)
						end
					end,
				})
			end
			return { ClassName = ClassName }
		end,
	}
	Env.typeof = function(Value)
		if type(Value) == "table" and Value.__signal then
			return "RBXScriptSignal"
		end
		if type(Value) == "table" and Value.__type then
			return Value.__type
		end
		return type(Value)
	end
	Env.task = {
		-- Queued, not discarded: anything Roblox forbids inside a simulation
		-- callback has to be deferred out of it, and tests must be able to run it.
		defer = function(Fn, ...)
			table.insert(Deferred, { Fn = Fn, Args = table.pack(...) })
		end,
		delay = function() end,
		-- Real coroutine semantics: runs Fn immediately up to its first yield
		-- (e.g. RunService.Heartbeat:Wait()), same as Roblox's task.spawn.
		-- task.defer/delay are still inert no-ops, so anything that must
		-- genuinely run across a frame boundary has to use task.spawn to be
		-- exercised by tests at all rather than silently discarded.
		spawn = function(Fn, ...)
			local Co = coroutine.create(Fn)
			local Ok, Err = coroutine.resume(Co, ...)
			if not Ok then
				error(Err, 0)
			end
			return Co
		end,
	}
	Env.require = function(Target)
		if type(Target) == "table" and Target.__module then
			local Module = Modules[Target.__module]
			if not Module then
				error("stub module not loaded: " .. Target.__module)
			end
			return Module
		end
		error("unexpected require target")
	end

	local function Load(Name: string, Path: string)
		local Source = fs.readFile(Path)
		local Chunk = luau.load(Source, {
			debugName = Name,
			environment = Env,
			injectGlobals = true,
		})
		Modules[Name] = Chunk()
		AnimBlendFolder:WaitForChild(Name)
		return Modules[Name]
	end

	Modules.Config = {
		SimulationFrequency = Enum.StepFrequency.Hz60,
		SimulationPriority = 4_001,
		AnimatorPreferLodEnabled = true,
		ExternalControlAttribute = "AnimBlendExternalControl",
		RigOverrides = { R6 = {}, R15 = {} },
	}
	if ConfigOverrides then
		for Key, Value in ConfigOverrides do
			Modules.Config[Key] = Value
		end
	end
	AnimBlendFolder:WaitForChild("Config")

	if not RealBinder then
		local BinderCalls = {}
		Modules.CharacterBinder = {
			Sessions = {},
			Calls = BinderCalls,
			Get = function()
				return nil
			end,
			Refresh = function()
				return true
			end,
			ShouldDrive = function(Session)
				return Session.Drives ~= false
			end,
			MarkAllDirty = function() end,
			Start = function()
				BinderCalls[#BinderCalls + 1] = "Start"
			end,
		}
		AnimBlendFolder:WaitForChild("CharacterBinder")
	end

	Load("VariantPicker", "src/shared/VariantPicker.luau")
	Load("StockCatalog", "src/shared/StockCatalog.luau")
	Load("RigProfile", "src/shared/RigProfile.luau")
	Load("LocomotionSolver", "src/shared/LocomotionSolver.luau")
	Load("DirectionalSolver", "src/shared/DirectionalSolver.luau")
	Load("PoseCatalog", "src/shared/PoseCatalog.luau")
	Load("TrackDriver", "src/shared/TrackDriver.luau")
	if RealBinder then
		Load("CharacterBinder", "src/shared/CharacterBinder.luau")
	end
	Load("AnimBlend", "src/shared/AnimBlend.luau")
	Modules.RunService = RunService
	Modules.Players = Services.Players
	Modules.Root = AnimBlendFolder
	Modules.FlushDeferred = function()
		local Queued = Deferred
		Deferred = {}
		for _, Entry in Queued do
			Entry.Fn(table.unpack(Entry.Args, 1, Entry.Args.n))
		end
		return #Queued
	end

	return Modules, Workspace
end

return Stub

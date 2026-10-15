local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")

local T = Expect.New("SwordCompatibility")
local Modules = Stub.Build()
Modules.AnimBlend.Init()

-- A small behavioral model, not a copy of the third-party sword script:
-- https://devforum.roblox.com/t/attempting-to-decipher-the-script-of-the-linked-sword-default-sword/2388604
-- The May 2023 source disables on Activated, branches on the next Stepped
-- timestamp, and APPENDS a fresh toolanim StringValue. Slash has no extra wait;
-- Lunge stays disabled for 0.25 + 0.25 + 0.5 seconds. The producer itself does
-- not load animation tracks or publish State, sequences, or synchronized input.
local function AppendSignal(World, Value)
	local Signal = Stub.NewInstance("StringValue", "toolanim", { Value = Value })
	Signal.Parent = World.Tool
	Signal.DestroyCount = 0
	Signal.Destroy = function(Self)
		Self.DestroyCount += 1
		if World.InSimulation then
			World.DestroysInSimulation += 1
		end
		local Parent = Self.Parent
		if Parent then
			local Index = table.find(Parent.Children, Self)
			if Index then
				table.remove(Parent.Children, Index)
			end
		end
		Self.Parent = nil
	end
	table.insert(World.Tool.Children, Signal)
	return Signal
end

local function ClassicProducer(World)
	local Producer = {
		LastAcceptedStep = 0,
		WaitingForStep = false,
		EnabledAt = nil,
		Emitted = {},
		Accepted = 0,
		Ignored = 0,
	}
	local Tool = World.Tool
	Tool.Enabled = true
	Tool.Activated = Stub.Event()
	Tool.Activated:Connect(function()
		if not Tool.Enabled then
			Producer.Ignored += 1
			return
		end
		Tool.Enabled = false
		Producer.WaitingForStep = true
		Producer.Accepted += 1
	end)
	function Producer:Stepped(Timestamp)
		if self.EnabledAt and Timestamp >= self.EnabledAt then
			self.EnabledAt = nil
			Tool.Enabled = true
		end
		if not self.WaitingForStep then
			return
		end
		self.WaitingForStep = false
		local State = if Timestamp - self.LastAcceptedStep < 0.2 then "Lunge" else "Slash"
		self.LastAcceptedStep = Timestamp
		table.insert(self.Emitted, AppendSignal(World, State))
		if State == "Lunge" then
			self.EnabledAt = Timestamp + 0.25 + 0.25 + 0.5
		else
			Tool.Enabled = true
		end
	end
	return Producer
end

local function NewWorld(RigName)
	Stub.SetServerTime(0)
	local Stock = Modules.StockCatalog.ToolIdsByRig[RigName]
	local Animator = Stub.Animator({ [Stock.toolslash] = 1, [Stock.toollunge] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	Humanoid.RigType = Stub.Enum.HumanoidRigType[RigName]
	local Catalog = Modules.PoseCatalog.Build(
		Stub.BuildAnimate({
			idle = { { Id = "rbxassetid://sword-fixture-idle" } },
			walk = { { Id = "rbxassetid://sword-fixture-walk" } },
		}),
		RigName
	)
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Session = Stub.Session(
		Humanoid,
		Modules.RigProfile.Resolve(RigName, {
			HasDistinctRun = Catalog.HasDistinctRun,
			HasSwimSlots = Catalog.HasSwimSlots,
		}),
		Catalog
	)
	local Tool = Stub.Tool("LinkedClassicSword")
	local World = {
		Animator = Animator,
		Session = Session,
		Tool = Tool,
		Handle = Tool:FindFirstChild("Handle"),
		Stock = Stock,
		Time = 0,
		InSimulation = false,
		DestroysInSimulation = 0,
	}
	Session.Character:SetTool(Tool)
	function World:AdvanceTo(At)
		assert(At >= self.Time, "forward frames must not rewind time")
		Stub.Advance(self.Animator, At - self.Time)
		-- Avoid accumulated clock roundoff, especially at the strict 0.2 boundary.
		Stub.SetServerTime(At)
		self.Time = At
	end
	function World:PostSimulation()
		Modules.RunService.PostSimulation:Fire()
	end
	function World:Consume(Cleanup)
		self.InSimulation = true
		Modules.AnimBlend.Step(self.Session)
		self.InSimulation = false
		if Cleanup ~= false then
			self:PostSimulation()
		end
	end
	function World:ClickAt(At, Cleanup)
		self:AdvanceTo(At)
		self.Tool.Activated:Fire()
		self.Producer:Stepped(At)
		self:Consume(Cleanup)
	end
	function World:FrameAt(At)
		self:AdvanceTo(At)
		if self.Producer then
			self.Producer:Stepped(At)
		end
		self:Consume()
	end
	World:Consume()
	return World
end

local function ActionChecks(Label, World, Slot, Start)
	local Track = World.Animator.Tracks[World.Stock[Slot]]
	T:True(Label .. " plays the rig's stock action", Track ~= nil and Track.IsPlaying)
	T:Equal(Label .. " uses Action priority", if Track then Track.Priority.Name else nil, "Action")
	T:False(Label .. " is not looped", if Track then Track.Looped else nil)
	T:Near(Label .. " begins at authored phase zero", if Track then Track.TimePosition else nil, 0)
	T:Near(Label .. " uses authored speed", if Track then Track.Speed else nil, 1)
	T:Equal(
		Label .. " publishes the stock slot",
		World.Session.Root:GetAttribute("AnimBlendToolSlot"),
		Slot
	)
	T:Near(
		Label .. " publishes its own start",
		World.Session.Root:GetAttribute("AnimBlendToolStartedAt"),
		Start
	)
	T:Near(
		Label .. " gets the full 0.3-second window",
		World.Session.Root:GetAttribute("AnimBlendToolEndsAt"),
		Start + 0.3
	)
	return Track
end

for _, RigName in { "R6", "R15" } do
	local Prefix = RigName .. " classic "
	do
		local World = NewWorld(RigName)
		World.Producer = ClassicProducer(World)
		local Producer = World.Producer
		World.Tool.Activated:Fire()
		T:False(Prefix .. "activation disables before Stepped", World.Tool.Enabled)
		T:Equal(Prefix .. "activation waits for Stepped", #Producer.Emitted, 0)
		World:AdvanceTo(0.25)
		Producer:Stepped(0.25)
		T:Equal(Prefix .. "first ordinary click emits Slash", Producer.Emitted[1].Value, "Slash")
		T:True(Prefix .. "Slash reenables without another yield", World.Tool.Enabled)
		T:Equal(
			Prefix .. "producer does not load slash tracks",
			World.Animator.Tracks[World.Stock.toolslash],
			nil
		)
		for _, Attribute in
			{
				"State",
				"ToolAnimationSequence",
				"ToolAnimationInputContext",
				"ToolAnimationInputAction",
			}
		do
			T:Equal(
				Prefix .. "producer does not publish " .. Attribute,
				World.Handle:GetAttribute(Attribute),
				nil
			)
		end
		World:Consume(false)
		local Slash = ActionChecks(Prefix .. "first Slash", World, "toolslash", 0.25)
		local Signal = Producer.Emitted[1]
		T:Equal(Prefix .. "consumption does not destroy during simulation", Signal.DestroyCount, 0)
		T:Equal(Prefix .. "consumed value stays parented until cleanup", Signal.Parent, World.Tool)
		World:Consume(false)
		T:Equal(Prefix .. "unchanged object is not another playback edge", Slash.PlayCount, 1)
		World:PostSimulation()
		T:Equal(Prefix .. "consumed value is destroyed after simulation", Signal.DestroyCount, 1)
		T:Equal(Prefix .. "consumed value leaves the tool", Signal.Parent, nil)
		T:Equal(
			Prefix .. "no toolanim remains to mask the next request",
			World.Tool:FindFirstChild("toolanim"),
			nil
		)
		T:Equal(Prefix .. "no destruction occurs in Step", World.DestroysInSimulation, 0)
		World:FrameAt(0.3)
		T:Equal(Prefix .. "cleanup does not manufacture another edge", Slash.PlayCount, 1)
	end

	do
		local World = NewWorld(RigName)
		World.Producer = ClassicProducer(World)
		World:ClickAt(0.25)
		local Slash = World.Animator.Tracks[World.Stock.toolslash]
		for Index, At in { 0.5, 0.75 } do
			World:AdvanceTo(At)
			T:True(Prefix .. "previous Slash still plays before repeat " .. Index, Slash.IsPlaying)
			T:Near(
				Prefix .. "repeat overlaps the previous 0.3-second window " .. Index,
				Slash.TimePosition,
				0.25
			)
			World.Tool.Activated:Fire()
			World.Producer:Stepped(At)
			local Signals = World.Producer.Emitted
			T:Equal(
				Prefix .. "0.25-second repeat stays Slash " .. Index,
				Signals[Index + 1].Value,
				"Slash"
			)
			T:True(
				Prefix .. "repeat appends a fresh value object " .. Index,
				Signals[Index + 1] ~= Signals[Index]
			)
			World:Consume()
			T:Equal(
				Prefix .. "repeat reuses the warm track " .. Index,
				World.Animator.Tracks[World.Stock.toolslash],
				Slash
			)
			T:Equal(
				Prefix .. "fresh same-Slash edge restarts exactly once " .. Index,
				Slash.PlayCount,
				Index + 1
			)
			ActionChecks(Prefix .. "repeat Slash " .. Index, World, "toolslash", At)
			T:Equal(
				Prefix .. "consumed repeat is cleaned up " .. Index,
				Signals[Index + 1].DestroyCount,
				1
			)
		end
		T:Equal(
			Prefix .. "repeat never reloads the warm track",
			World.Animator.LoadCallCounts[World.Stock.toolslash],
			1
		)
		World:FrameAt(1.04)
		T:True(Prefix .. "latest Slash retains its own full window", Slash.IsPlaying)
		World:FrameAt(1.06)
		T:False(Prefix .. "latest Slash expires on its own deadline", Slash.IsPlaying)
		T:Equal(
			Prefix .. "expiry returns to tool idle",
			World.Animator.Tracks[World.Stock.toolnone].WeightTarget,
			1
		)
	end

	do
		local World = NewWorld(RigName)
		World.Producer = ClassicProducer(World)
		World:ClickAt(0.25)
		World:ClickAt(0.375)
		T:Equal(
			Prefix .. "rapid second activation emits Lunge",
			World.Producer.Emitted[2].Value,
			"Lunge"
		)
		local Lunge = ActionChecks(Prefix .. "double-click Lunge", World, "toollunge", 0.375)
		T:False(Prefix .. "Lunge keeps Tool disabled", World.Tool.Enabled)
		T:False(
			Prefix .. "Lunge replaces the earlier Slash",
			World.Animator.Tracks[World.Stock.toolslash].IsPlaying
		)
		World:ClickAt(0.5)
		T:Equal(Prefix .. "busy activation produces no extra value", #World.Producer.Emitted, 2)
		T:Equal(Prefix .. "busy activation is ignored", World.Producer.Ignored, 1)
		T:Equal(
			Prefix .. "busy activation cannot replay Lunge",
			if Lunge then Lunge.PlayCount else nil,
			1
		)
		World:FrameAt(0.875)
		T:False(Prefix .. "half-second lunge still blocks activation", World.Tool.Enabled)
		T:False(
			Prefix .. "animation window is separate from producer lockout",
			Lunge ~= nil and Lunge.IsPlaying
		)
		World:ClickAt(1.374)
		T:Equal(Prefix .. "lockout lasts the whole one second", #World.Producer.Emitted, 2)
		World:FrameAt(1.375)
		T:True(Prefix .. "one-second lunge completion reenables Tool", World.Tool.Enabled)
		World:ClickAt(1.5)
		T:Equal(
			Prefix .. "next accepted activation is an ordinary Slash",
			World.Producer.Emitted[3].Value,
			"Slash"
		)
		ActionChecks(Prefix .. "post-Lunge Slash", World, "toolslash", 1.5)
	end

	do
		local World = NewWorld(RigName)
		World.Producer = ClassicProducer(World)
		World:ClickAt(0.25)
		T:Equal(Prefix .. "boundary fixture is exactly 0.2 seconds", 0.45 - 0.25, 0.2)
		World:ClickAt(0.45)
		T:Equal(Prefix .. "exact 0.2 is Slash, not Lunge", World.Producer.Emitted[2].Value, "Slash")
		local Slash = ActionChecks(Prefix .. "strict-threshold Slash", World, "toolslash", 0.45)
		T:Equal(Prefix .. "strict-threshold repeat has two playback edges", Slash.PlayCount, 2)
		T:Equal(
			Prefix .. "strict threshold never loads Lunge",
			World.Animator.Tracks[World.Stock.toollunge],
			nil
		)
	end

	do
		-- Two producer activations can be queued before the consumer gets a turn.
		-- Both same-name children must survive append, then drain in order.
		local World = NewWorld(RigName)
		World.Producer = ClassicProducer(World)
		for _, At in { 0.25, 0.375 } do
			World:AdvanceTo(At)
			World.Tool.Activated:Fire()
			World.Producer:Stepped(At)
		end
		local First, Second = World.Producer.Emitted[1], World.Producer.Emitted[2]
		T:Equal(Prefix .. "producer appends both same-named children", #World.Tool.Children, 3)
		World:Consume(false)
		T:Equal(
			Prefix .. "queue first consumes Slash",
			World.Session.Root:GetAttribute("AnimBlendToolSlot"),
			"toolslash"
		)
		T:Equal(Prefix .. "queue does not destroy its head during Step", First.DestroyCount, 0)
		T:Equal(Prefix .. "queue does not destroy its tail during Step", Second.DestroyCount, 0)
		World:PostSimulation()
		T:Equal(Prefix .. "queue cleanup removes only the consumed head", First.DestroyCount, 1)
		T:Equal(Prefix .. "queue preserves its unconsumed tail", Second.DestroyCount, 0)
		T:Equal(
			Prefix .. "next queued value becomes discoverable",
			World.Tool:FindFirstChild("toolanim"),
			Second
		)
		World:Consume()
		ActionChecks(Prefix .. "queued Lunge", World, "toollunge", 0.375)
		T:Equal(Prefix .. "queue tail is consumed once", Second.DestroyCount, 1)
		T:Equal(
			Prefix .. "queue is empty after both requests",
			World.Tool:FindFirstChild("toolanim"),
			nil
		)
		T:Equal(Prefix .. "queue cleanup is outside simulation", World.DestroysInSimulation, 0)
	end

	do
		-- This is the generic synchronized adapter contract, not sword behavior.
		local World = NewWorld(RigName)
		local Handle, Root = World.Handle, World.Session.Root
		Handle:SetAttribute("ToolAnimationInputContext", "SwordContext")
		Handle:SetAttribute("ToolAnimationInputAction", "SwordAction")
		Handle:SetAttribute("ToolAnimationSequence", 0)
		Handle:SetAttribute("State", "None")
		local UnrelatedLegacySignal = AppendSignal(World, "Lunge")
		World:AdvanceTo(0.25)
		Handle:SetAttribute("State", "Slash")
		World:Consume()
		local Slash = ActionChecks(RigName .. " synchronized first Slash", World, "toolslash", 0.25)
		T:Equal(
			RigName .. " synchronized first State is consumed",
			Handle:GetAttribute("State"),
			"None"
		)
		World:AdvanceTo(0.5)
		Handle:SetAttribute("State", "Slash")
		local BeforeRoot = table.clone(Root.Attributes)
		local BeforeHandle = table.clone(Handle.Attributes)
		local BeforePhase = Slash.TimePosition
		World:Consume()
		T:Equal(RigName .. " synchronized repeat restarts exactly once", Slash.PlayCount, 2)
		ActionChecks(RigName .. " synchronized repeat Slash", World, "toolslash", 0.5)
		local ExpectedId = Root:GetAttribute("AnimBlendToolId")
		local ExpectedStart = Root:GetAttribute("AnimBlendToolStartedAt")
		local ExpectedEnd = Root:GetAttribute("AnimBlendToolEndsAt")
		World:AdvanceTo(0.55)
		Handle:SetAttribute("ToolAnimationSequence", 1)
		World:Consume()
		T:Equal(
			RigName .. " synchronized sequence confirmation does not restart",
			Slash.PlayCount,
			2
		)
		T:Near(RigName .. " synchronized confirmation preserves phase", Slash.TimePosition, 0.05)
		T:Near(
			RigName .. " synchronized confirmation preserves start",
			Root:GetAttribute("AnimBlendToolStartedAt"),
			ExpectedStart
		)

		-- Restore engine snapshot data to immediately before the repeated input.
		-- Playback counters intentionally remain cumulative instrumentation.
		Root.Attributes = table.clone(BeforeRoot)
		Handle.Attributes = table.clone(BeforeHandle)
		Slash.TimePosition = BeforePhase
		Slash.IsPlaying = true
		Slash.WeightTarget = 1
		World.Time = 0.5
		Stub.SetServerTime(0.5)
		World:Consume()
		T:Equal(
			RigName .. " rollback reconsumes the restored State",
			Handle:GetAttribute("State"),
			"None"
		)
		T:Equal(RigName .. " rollback repeats exactly one playback edge", Slash.PlayCount, 3)
		T:Near(RigName .. " rollback replay resets phase deterministically", Slash.TimePosition, 0)
		T:Equal(
			RigName .. " rollback replay chooses the same ID",
			Root:GetAttribute("AnimBlendToolId"),
			ExpectedId
		)
		T:Near(
			RigName .. " rollback replay restores the same start",
			Root:GetAttribute("AnimBlendToolStartedAt"),
			ExpectedStart
		)
		T:Near(
			RigName .. " rollback replay restores the same deadline",
			Root:GetAttribute("AnimBlendToolEndsAt"),
			ExpectedEnd
		)
		World:Consume()
		T:Equal(RigName .. " unchanged replay snapshot does not restart again", Slash.PlayCount, 3)
		T:Equal(
			RigName .. " synchronized path never consumes legacy children",
			UnrelatedLegacySignal.Parent,
			World.Tool
		)
		T:Equal(
			RigName .. " synchronized path never destroys legacy children",
			UnrelatedLegacySignal.DestroyCount,
			0
		)
	end

	do
		-- Initial sequenced metadata may legitimately arrive behind replication.
		local World = NewWorld(RigName)
		local Slash = World.Animator:LoadAnimation({ AnimationId = World.Stock.toolslash })
		Slash.Priority = Stub.Enum.AnimationPriority.Action
		Slash:Play(0, 1, 1)
		World:AdvanceTo(0.125)
		World.Handle:SetAttribute("State", "Slash")
		World.Handle:SetAttribute("ToolAnimationSequence", 1)
		World:Consume()
		T:Equal(
			RigName .. " initial sequenced metadata adopts replicated track",
			World.Animator.Tracks[World.Stock.toolslash],
			Slash
		)
		T:Equal(RigName .. " initial metadata adoption does not restart", Slash.PlayCount, 1)
		T:Near(RigName .. " initial metadata adoption preserves phase", Slash.TimePosition, 0.125)
		T:Near(
			RigName .. " initial metadata adoption preserves inferred start",
			World.Session.Root:GetAttribute("AnimBlendToolStartedAt"),
			0
		)
		World:Consume()
		T:Equal(RigName .. " same sequenced confirmation stays idempotent", Slash.PlayCount, 1)
	end
end

return T

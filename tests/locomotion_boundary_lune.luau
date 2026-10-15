local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")
local T = Expect.New("LocomotionBoundary")

for _, Client in { false, true } do
	local Modules = Stub.Build(nil, Client)
	local Driver = Modules.TrackDriver
	local Id = "rbxassetid://810001"
	local Catalog = Modules.PoseCatalog.Build(
		Stub.BuildAnimate({
			idle = { { Id = Id } },
			walk = { { Id = "rbxassetid://810002" } },
			toolnone = { { Id = "rbxassetid://810003" } },
			toolslash = { { Id = "rbxassetid://810004" } },
			toollunge = { { Id = "rbxassetid://810005" } },
		}),
		"R15"
	)
	for _, Slot in { "toolnone", "toolslash", "toollunge" } do
		T:Equal("tool slot is not catalogued", Catalog.SlotIds[Slot], nil)
	end
	local Animator = Stub.Animator()
	local Humanoid = Stub.Humanoid(Animator)
	local Session = Stub.Session(
		Humanoid,
		Modules.RigProfile.Resolve("R15", { HasDistinctRun = false, HasSwimSlots = false }),
		Catalog
	)
	Driver.Prepare(Catalog.AllIds)
	local Tool = Stub.Tool("ExternalSword")
	local Handle = Tool:FindFirstChild("Handle")
	Handle:SetAttribute("AnimBlendToolIdentity", nil)
	Handle:SetAttribute("State", "Slash")
	Handle:SetAttribute("ToolAnimationInputContext", "SwordContext")
	Handle:SetAttribute("ToolAnimationInputAction", "Attack")
	local Signal = Stub.NewInstance("StringValue", "toolanim")
	Signal.Value = "Lunge"
	Tool:SetChild("toolanim", Signal)
	Session.Character:SetTool(Tool)
	Modules.AnimBlend.Init()
	for _ = 1, 20 do
		Modules.AnimBlend.Step(Session)
		Modules.RunService.PostSimulation:Fire()
		Stub.Advance(Animator, 1 / 60)
	end
	T:True("locomotion still runs with legacy gear", Animator.Tracks[Id].IsPlaying)
	T:Equal("legacy command survives simulation and cleanup", Signal.Parent, Tool)
	T:Equal("legacy command value untouched", Signal.Value, "Lunge")
	T:Equal("producer State is never consumed", Handle:GetAttribute("State"), "Slash")
	T:Equal("no tool identity is assigned", Handle:GetAttribute("AnimBlendToolIdentity"), nil)
	for Name in Session.Root.Attributes do
		T:False("root contains no combat state", string.find(Name, "Tool", 1, true) ~= nil)
	end
	for _, Priority in
		{
			Stub.Enum.AnimationPriority.Idle,
			Stub.Enum.AnimationPriority.Movement,
			Stub.Enum.AnimationPriority.Action,
			Stub.Enum.AnimationPriority.Action2,
			Stub.Enum.AnimationPriority.Action3,
			Stub.Enum.AnimationPriority.Action4,
		}
	do
		local Shared = Stub.Animator()
		local Body = Stub.Humanoid(Shared)
		Shared.Parent = Body
		local External = Shared:AddStray(Id, 1)
		External.Priority = Priority
		local Other = Shared:AddStray(Id, 1)
		Other.Priority = Priority
		T:Equal("claim preserves shared Animator", Driver.TakeOwnership(Body), Shared)
		T:Equal("claim does not stop external tracks", External.StopCount, 0)
		local Step = Driver.BeginStep(Shared)
		T:Equal("same-ID external track is not adopted", Driver.Find(Shared, Id, Step), nil)
		Driver.Drive(Shared, {
			Id = Id,
			Weight = 1,
			Rate = 1,
			Fade = 0.1,
			Looped = true,
			Sustain = true,
			Priority = Stub.Enum.AnimationPriority.Core,
		}, nil, Step)
		Driver.Collapse(Shared, Id, Step)
		Driver.StopKnown(Shared, { Id }, 0, Step)
		Driver.StopAll(Shared, { Id }, 0)
		T:Equal("external priority never changed", External.Priority, Priority)
		T:True(
			"external same-ID tracks survive drive and release",
			External.IsPlaying and Other.IsPlaying
		)
		T:Equal("external track receives no stop commands", External.StopCount + Other.StopCount, 0)
	end
end

return T

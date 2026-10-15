local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")

local T = Expect.New("ToolIdentity")
local Attribute = "AnimBlendToolIdentity"

local function NewWorld(Client)
	local Modules = Stub.Build(nil, Client, true)
	local Animator = Stub.Animator()
	local Humanoid = Stub.Humanoid(Animator)
	Animator.Parent = Humanoid
	local Animate = Stub.BuildAnimate({
		idle = { { Id = "rbxassetid://identity-idle" } },
		walk = { { Id = "rbxassetid://identity-walk" } },
		toolnone = { { Id = "rbxassetid://identity-tool" } },
	})
	local Placeholder = Stub.Session(
		Humanoid,
		Modules.RigProfile.Resolve("R15", { HasDistinctRun = false, HasSwimSlots = false }),
		Modules.PoseCatalog.Build(nil)
	)
	local Character = Stub.BinderCharacter(Humanoid, Placeholder.Root, Animate)
	if Client then
		Modules.Players.LocalPlayer.Character = Character
	end
	return Modules, Character
end

local function UntaggedTool(Name)
	local Tool = Stub.Tool(Name)
	Tool:FindFirstChild("Handle"):SetAttribute(Attribute, nil)
	return Tool
end

local function Identity(Tool)
	return Tool:FindFirstChild("Handle"):GetAttribute(Attribute)
end

do
	local Modules, Character = NewWorld(false)
	local First = UntaggedTool("Sword")
	local Handle = First:FindFirstChild("Handle")
	Character:AddChild(First)
	T:Equal("unclaimed characters have no generated identity", Identity(First), nil)
	T:True("server claims the initial character", Modules.CharacterBinder.Claim(Character))
	local FirstIdentity = Identity(First)
	T:True(
		"server assigns initial tool identity",
		type(FirstIdentity) == "string" and FirstIdentity ~= ""
	)
	T:Equal("initial tool uses one GUID", Modules.HttpService.GenerateGUIDCalls, 1)
	Modules.CharacterBinder.Claim(Character)
	T:Equal("repeated claims preserve identity", Identity(First), FirstIdentity)
	T:Equal("repeated claims do not generate GUIDs", Modules.HttpService.GenerateGUIDCalls, 1)

	Character:RemoveChild(First)
	Character:AddChild(First)
	T:Equal("reparenting the same Handle preserves identity", Identity(First), FirstIdentity)
	T:Equal("reparenting does not regenerate identity", Modules.HttpService.GenerateGUIDCalls, 1)

	Character:RemoveChild(First)
	local Clone = UntaggedTool("Sword")
	Clone:FindFirstChild("Handle"):SetAttribute(Attribute, FirstIdentity)
	Character:AddChild(Clone)
	local CloneIdentity = Identity(Clone)
	T:True("same-named cloned tools cannot inherit identity", CloneIdentity ~= FirstIdentity)
	T:Equal(
		"dynamic tool arrival generates its own identity",
		Modules.HttpService.GenerateGUIDCalls,
		2
	)

	local Replacement = Stub.NewInstance("Part", "Handle")
	Replacement:SetAttribute(Attribute, CloneIdentity)
	Clone:SetChild("Handle", Replacement)
	T:True("replacing the Handle changes tool identity", Identity(Clone) ~= CloneIdentity)
	T:Equal("replacement Handle generates one GUID", Modules.HttpService.GenerateGUIDCalls, 3)
	Clone:SetChild("Handle", Handle)
	T:Equal(
		"moving an existing Handle to another Tool preserves its identity",
		Identity(Clone),
		FirstIdentity
	)
	T:Equal("moved Handles reuse their GUID", Modules.HttpService.GenerateGUIDCalls, 3)

	local Delayed = Stub.Tool("Delayed", false)
	Character:AddChild(Delayed)
	T:Equal("a Tool without Handle does not get a GUID", Modules.HttpService.GenerateGUIDCalls, 3)
	local DelayedHandle = Stub.NewInstance("Part", "Handle")
	Delayed:SetChild("Handle", DelayedHandle)
	T:True("delayed Handle arrival receives identity", type(Identity(Delayed)) == "string")
	T:Equal("delayed Handle generates one GUID", Modules.HttpService.GenerateGUIDCalls, 4)

	local LooseHandle = Stub.NewInstance("Part", "Handle")
	Character:AddChild(LooseHandle)
	local FakeHandle = Stub.NewInstance("Folder", "Handle")
	local NotAPart = Stub.Tool("NotAPart", false)
	NotAPart:SetChild("Handle", FakeHandle)
	Character:AddChild(NotAPart)
	T:Equal(
		"a loose part named Handle is not a Tool Handle",
		LooseHandle:GetAttribute(Attribute),
		nil
	)
	T:Equal("a nonphysical Handle is not tagged", FakeHandle:GetAttribute(Attribute), nil)
	T:Equal(
		"invalid Handle candidates do not generate GUIDs",
		Modules.HttpService.GenerateGUIDCalls,
		4
	)

	local Session = Modules.CharacterBinder.Get(Character)
	Modules.AnimBlend.Step(Session)
	Modules.AnimBlend.Step(Session)
	T:Equal("simulation steps never generate tool GUIDs", Modules.HttpService.GenerateGUIDCalls, 4)

	Modules.CharacterBinder.Release(Character)
	local AfterRelease = UntaggedTool("AfterRelease")
	Character:AddChild(AfterRelease)
	T:Equal("released characters stop assigning identity", Identity(AfterRelease), nil)
	T:Equal("release disconnects the descendant listener", Modules.HttpService.GenerateGUIDCalls, 4)
	Modules.CharacterBinder.Claim(Character)
	T:Equal("reclaim preserves known Handle identity", Identity(Clone), FirstIdentity)
	T:True("reclaim tags newly discovered Handles", type(Identity(AfterRelease)) == "string")
	T:Equal(
		"reclaim generates GUIDs only for new Handles",
		Modules.HttpService.GenerateGUIDCalls,
		5
	)
end

do
	local Modules, Character = NewWorld(true)
	local Initial = UntaggedTool("Initial")
	local Replicated = UntaggedTool("Replicated")
	Replicated:FindFirstChild("Handle"):SetAttribute(Attribute, "server-published-identity")
	Character:AddChild(Initial)
	Character:AddChild(Replicated)
	T:True("client claims its local character", Modules.CharacterBinder.Claim(Character))
	T:Equal("client does not assign initial identity", Identity(Initial), nil)
	T:Equal(
		"client preserves replicated identity",
		Identity(Replicated),
		"server-published-identity"
	)
	local Added = UntaggedTool("Added")
	Character:AddChild(Added)
	T:Equal("client does not assign dynamic identity", Identity(Added), nil)
	local Delayed = Stub.Tool("Delayed", false)
	Character:AddChild(Delayed)
	Delayed:SetChild("Handle", Stub.NewInstance("Part", "Handle"))
	T:Equal("client does not assign delayed Handle identity", Identity(Delayed), nil)
	Replicated:SetChild("Handle", Stub.NewInstance("Part", "Handle"))
	T:Equal("client does not assign replacement Handle identity", Identity(Replicated), nil)
	T:Equal("client never generates tool GUIDs", Modules.HttpService.GenerateGUIDCalls, 0)
end

return T

local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")
local T = Expect.New("ToolRollbackRegressions")
local M = Stub.Build()
local SlashId = "rbxassetid://rollback-slash"
local function NewWorld()
	Stub.SetServerTime(1000)
	local Animator = Stub.Animator({ [SlashId] = 1 })
	local Humanoid = Stub.Humanoid(Animator)
	local Catalog = Stub.Catalog(M.PoseCatalog, {
		idle = { "rbxassetid://rollback-idle" },
		walk = { "rbxassetid://rollback-walk" },
		toolslash = { SlashId },
		toolnone = { "rbxassetid://rollback-toolnone" },
	})
	M.TrackDriver.Prepare(Catalog.AllIds)
	local Session = Stub.Session(
		Humanoid,
		M.RigProfile.Resolve("R15", {
			HasDistinctRun = false,
			HasSwimSlots = false,
		}),
		Catalog
	)
	return Animator, Session
end
local function Sword(Identity)
	local Tool = Stub.Tool("SameNameSword")
	local Handle = Tool:FindFirstChild("Handle")
	Handle:SetAttribute("AnimBlendToolIdentity", Identity)
	Handle:SetAttribute("ToolAnimationInputContext", "SwordContext")
	Handle:SetAttribute("ToolAnimationInputAction", "SwordAction")
	Handle:SetAttribute("State", "None")
	return Tool, Handle
end
local function Restore(Animator, Session, Tool, Attributes, At, Position)
	Session.Character:SetTool(Tool)
	Session.Root.Attributes = table.clone(Attributes)
	Stub.SetServerTime(At)
	local Track = Animator.Tracks[SlashId]
	Track.IsPlaying = true
	Track.WeightTarget = 1
	Track.TimePosition = Position
end

for _, Swap in { false, true } do
	local Animator, Session = NewWorld()
	local Tool, Handle = Sword("tool-a")
	Session.Character:SetTool(Tool)
	M.AnimBlend.Step(Session)
	Handle:SetAttribute("State", "Slash")
	M.AnimBlend.Step(Session)
	Stub.Advance(Animator, 0.1)
	M.AnimBlend.Step(Session)
	local Snapshot = table.clone(Session.Root.Attributes)
	local Slash = Animator.Tracks[SlashId]
	local Plays = Slash.PlayCount
	local Other = Sword("tool-b")
	Session.Character:SetTool(if Swap then Other else nil)
	M.AnimBlend.Step(Session)
	T:False("departure stops prior action", Slash.IsPlaying)
	Restore(Animator, Session, Tool, Snapshot, 1000.1, 0.1)
	M.AnimBlend.Step(Session)
	T:True("rollback restores active action after departure", Slash.IsPlaying)
	T:Equal("rollback preserves active ID", Session.Root:GetAttribute("AnimBlendToolId"), SlashId)
	T:Near("rollback preserves deadline", Session.Root:GetAttribute("AnimBlendToolEndsAt"), 1000.3)
	T:Near("rollback preserves phase", Slash.TimePosition, 0.1)
	T:Equal("rollback does not create another playback edge", Slash.PlayCount, Plays)
	M.AnimBlend.Step(Session)
	T:Equal("unchanged replay does not restart", Slash.PlayCount, Plays)
	Session.Character:SetTool(nil)
	M.AnimBlend.Step(Session)
	Session.Character:SetTool(Tool)
	M.AnimBlend.Step(Session)
	T:False("genuine reequip does not resurrect consumed action", Slash.IsPlaying)
	T:Equal("genuine reequip clears active ID", Session.Root:GetAttribute("AnimBlendToolId"), nil)
end

do
	local Animator, Session = NewWorld()
	local Tool, Handle = Sword(nil)
	Session.Character:SetTool(Tool)
	Handle:SetAttribute("State", "Slash")
	M.AnimBlend.Step(Session)
	T:Equal(
		"missing identity leaves synchronized request unconsumed",
		Handle:GetAttribute("State"),
		"Slash"
	)
	T:Equal(
		"missing identity leaves root action untouched",
		Session.Root:GetAttribute("AnimBlendToolId"),
		nil
	)
	Handle:SetAttribute("AnimBlendToolIdentity", "late-id")
	M.AnimBlend.Step(Session)
	T:Equal("late identity permits the pending request", Handle:GetAttribute("State"), "None")
	T:True("pending request plays when identity arrives", Animator.Tracks[SlashId].IsPlaying)
end
do
	local Animator, Session = NewWorld()
	local Tool, Handle = Sword("known-id")
	Session.Character:SetTool(Tool)
	Handle:SetAttribute("State", "Slash")
	M.AnimBlend.Step(Session)
	local NextTool, NextHandle = Sword(nil)
	NextHandle:SetAttribute("State", "Slash")
	Session.Character:SetTool(NextTool)
	M.AnimBlend.Step(Session)
	T:False("pending identity releases previous tool action", Animator.Tracks[SlashId].IsPlaying)
	T:Equal(
		"pending identity cannot inherit previous owner",
		Session.Root:GetAttribute("AnimBlendToolOwner"),
		nil
	)
	T:Equal(
		"pending identity keeps next action unconsumed",
		NextHandle:GetAttribute("State"),
		"Slash"
	)
	NextHandle:SetAttribute("AnimBlendToolIdentity", "next-id")
	M.AnimBlend.Step(Session)
	T:True("identified replacement starts its own action", Animator.Tracks[SlashId].IsPlaying)
	T:Near(
		"identified replacement begins at its own phase",
		Animator.Tracks[SlashId].TimePosition,
		0
	)
end
return T

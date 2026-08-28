local Expect = require("./support/expect")
local Stub = require("./support/roblox_stub")

local T = Expect.New("BinderHardening")

local function NewClaimedWorld()
	local Modules = Stub.Build(nil, false, true)
	local Animator = Stub.Animator()
	local Humanoid = Stub.Humanoid(Animator)
	Animator.Parent = Humanoid
	local Animate = Stub.BuildAnimate({
		idle = { { Id = "rbxassetid://binder-idle", Weight = 2 } },
		walk = { { Id = "rbxassetid://binder-walk" } },
	})
	local Placeholder = Stub.Session(
		Humanoid,
		Modules.RigProfile.Resolve("R15", {
			HasDistinctRun = false,
			HasSwimSlots = false,
		}),
		Modules.PoseCatalog.Build(nil)
	)
	local Character = Stub.BinderCharacter(Humanoid, Placeholder.Root, Animate)
	T:True("binder claims a complete character", Modules.CharacterBinder.Claim(Character))
	local Session = Modules.CharacterBinder.Get(Character)
	T:True("claimed character has a live session", Session ~= nil)
	return Modules, Character, Animate, Humanoid, Session
end

do
	local Modules, _, Animate, _, Session = NewClaimedWorld()
	local IdleFolder = Animate:FindFirstChild("idle")
	local Idle = IdleFolder:FindFirstChild("Animation1")
	Idle:SetProperty("AnimationId", "rbxassetid://binder-idle-updated")
	T:True("AnimationId mutation queues a catalog rebuild", Session.RebuildQueued)
	Modules.FlushDeferred()
	T:Equal(
		"AnimationId mutation replaces the published catalog entry",
		Session.Catalog.Primary.idle,
		"rbxassetid://binder-idle-updated"
	)

	local Weight = Idle:FindFirstChild("Weight")
	local BeforeWeight = Session.CatalogSignature
	Weight:SetProperty("Value", 7)
	T:True("Weight mutation queues a catalog rebuild", Session.RebuildQueued)
	Modules.FlushDeferred()
	T:True("Weight mutation republishes the catalog", Session.CatalogSignature ~= BeforeWeight)

	Idle:SetAttribute("LinearVelocity", Stub.Vector2(0, 6.4))
	T:True("LinearVelocity mutation queues a catalog rebuild", Session.RebuildQueued)
	Modules.FlushDeferred()

	local WalkFolder = Animate:FindFirstChild("walk")
	WalkFolder:SetProperty("Name", "run")
	T:True("slot name mutation queues a catalog rebuild", Session.RebuildQueued)
	Modules.FlushDeferred()
	T:Equal("renamed slot leaves no stale walk entry", Session.Catalog.Slots.walk, nil)
	T:True("renamed slot is adopted as run", Session.Catalog.Slots.run ~= nil)
end

do
	local Modules, Character, _, OriginalHumanoid, Session = NewClaimedWorld()
	local ReplacementAnimator = Stub.Animator()
	local ReplacementHumanoid = Stub.Humanoid(ReplacementAnimator)
	ReplacementAnimator.Parent = ReplacementHumanoid
	Character:AddHumanoid(ReplacementHumanoid)
	T:Equal("Humanoid replacement updates the live session", Session.Humanoid, ReplacementHumanoid)
	T:True(
		"Humanoid replacement immediately reclaims Animator ownership",
		Modules.TrackDriver.IsOwned(ReplacementHumanoid.Animator)
	)

	local Foreign = Stub.Animator()
	ReplacementHumanoid:SetAnimator(Foreign)
	Modules.FlushDeferred()
	local Reclaimed = ReplacementHumanoid.Animator
	T:True("replacement Humanoid watches and reclaims a foreign Animator", Reclaimed ~= Foreign)
	T:True("reclaimed replacement Animator is owned", Modules.TrackDriver.IsOwned(Reclaimed))

	local RetiredForeign = Stub.Animator()
	OriginalHumanoid:SetAnimator(RetiredForeign)
	Modules.FlushDeferred()
	T:Equal(
		"retired Humanoid callbacks cannot affect the live replacement",
		ReplacementHumanoid.Animator,
		Reclaimed
	)
end

do
	local Modules = Stub.Build(nil, true, true)
	local Animator = Stub.Animator()
	local Humanoid = Stub.Humanoid(Animator)
	Animator.Parent = Humanoid
	local Animate = Stub.BuildAnimate({
		idle = { { Id = "rbxassetid://client-idle" } },
		walk = { { Id = "rbxassetid://client-walk" } },
	})
	local Placeholder = Stub.Session(
		Humanoid,
		Modules.RigProfile.Resolve("R15", {
			HasDistinctRun = false,
			HasSwimSlots = false,
		}),
		Modules.PoseCatalog.Build(nil)
	)
	local Character = Stub.BinderCharacter(Humanoid, Placeholder.Root, Animate)
	Modules.Players.LocalPlayer.Character = Character
	T:True(
		"local character claims survive a transient GetPlayerFromCharacter miss",
		Modules.CharacterBinder.Claim(Character)
	)
	local Session = Modules.CharacterBinder.Get(Character)
	T:Equal("local claim recovers the Player identity", Session.Player, Modules.Players.LocalPlayer)
	T:Equal("local claim keeps the server-matching deterministic seed", Session.Seed, 24680)
	T:True(
		"local claim explicitly enables Animator prediction",
		#Modules.RunService.PredictionCalls > 0
	)
end

return T

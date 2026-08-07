--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local Config = require(Root:WaitForChild("Config"))
local PoseCatalog = require(Root:WaitForChild("PoseCatalog"))
local RigProfile = require(Root:WaitForChild("RigProfile"))
local TrackDriver = require(Root:WaitForChild("TrackDriver"))

local CharacterBinder = {}

export type Session = {
	Character: Model,
	Player: Player?,
	Humanoid: Humanoid,
	Root: BasePart,
	Animate: Instance?,
	ScaleDamp: NumberValue?,
	Catalog: PoseCatalog.Catalog,
	Profile: RigProfile.Profile,
	PartsDirty: boolean,
	Owns: boolean,
	RebuildQueued: boolean,
	Conns: { RBXScriptConnection },
	AnimateConns: { RBXScriptConnection },
}

local BindWaitSeconds = 30
local ToggleFade = 0.15
local IsClient = RunService:IsClient()

local Sessions: { Session } = {}
local ByCharacter: { [Model]: Session } = {}
local PlayerCharacter: { [Player]: Model } = {}
local PendingBinds: { [Model]: boolean } = {}
local Enabled = false
local EnabledAttribute = "AnimBlendEnabled"

CharacterBinder.Sessions = Sessions

local ReleaseCharacter: (Model) -> ()
local AttachAnimate: (Session, Instance?) -> ()
local ResetTracks: (Session, number?) -> ()
local SetSessionOwning: (Session, boolean) -> ()

local function FindAnimate(Character: Model): Instance?
	return Character:FindFirstChild("Animate")
end

local function FindRoot(Character: Model, Humanoid: Humanoid?): BasePart?
	local Found = Character:FindFirstChild("HumanoidRootPart")
	if Found and Found:IsA("BasePart") then
		return Found
	end
	local Hum = Humanoid or Character:FindFirstChildOfClass("Humanoid")
	if Hum then
		local HumanoidRoot = Hum.RootPart
		if HumanoidRoot and HumanoidRoot:IsA("BasePart") then
			return HumanoidRoot
		end
	end
	return nil
end

local function SetAnimateDisabled(Animate: Instance?, Disabled: boolean)
	if not Animate then
		return
	end
	if Animate:IsA("LocalScript") or Animate:IsA("Script") then
		Animate.Disabled = Disabled
	end
	for _, Child in Animate:GetDescendants() do
		if Child:IsA("LocalScript") or Child:IsA("Script") then
			Child.Disabled = Disabled
		end
	end
end

local function RigTypeName(Humanoid: Humanoid): string
	local Ok, Value = pcall(function()
		return Humanoid.RigType
	end)
	if Ok and Value == Enum.HumanoidRigType.R6 then
		return "R6"
	end
	return "R15"
end

local function DisconnectList(List: { RBXScriptConnection })
	for _, Conn in List do
		Conn:Disconnect()
	end
	table.clear(List)
end

local function Overrides(Name: string): { [string]: any }?
	local Table = Config.RigOverrides
	if type(Table) ~= "table" then
		return nil
	end
	return Table[Name]
end

local function PlayerWantsAnimBlend(Player: Player?): boolean
	if not Player then
		return true
	end
	local Value = Player:GetAttribute(EnabledAttribute)
	if type(Value) == "boolean" then
		return Value
	end
	return Config.EnabledByDefault ~= false
end

local function Rebuild(Session: Session)
	local Animate = Session.Animate
	local Catalog = PoseCatalog.Build(Animate)
	Session.Catalog = Catalog

	local Name = RigTypeName(Session.Humanoid)
	Session.Profile = RigProfile.Resolve(Name, {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	}, Overrides(Name))

	local Damp = if Animate then Animate:FindFirstChild("ScaleDampeningPercent") else nil
	Session.ScaleDamp = if Damp and Damp:IsA("NumberValue") then Damp else nil

	-- Animator creation stays server-only; clients synchronously prepare the
	-- replicated Animator before the first simulation step.
	TrackDriver.PrepareAnimator(Session.Humanoid)

	if #Catalog.AllIds > 0 then
		TrackDriver.Warm(Session.Humanoid, Catalog.AllIds)
	end
end

CharacterBinder.Rebuild = Rebuild

local function QueueRebuild(Session: Session)
	if Session.RebuildQueued then
		return
	end
	Session.RebuildQueued = true
	task.defer(function()
		Session.RebuildQueued = false
		if ByCharacter[Session.Character] == Session then
			Rebuild(Session)
		end
	end)
end

local function WatchAnimate(Session: Session, Animate: Instance)
	local Conns = Session.AnimateConns
	local function OnChanged(Child: Instance)
		if
			Child:IsA("Animation")
			or Child:IsA("StringValue")
			or Child:IsA("NumberValue")
			or Child:IsA("Folder")
		then
			QueueRebuild(Session)
		end
	end

	table.insert(Conns, Animate.DescendantAdded:Connect(OnChanged))
	table.insert(Conns, Animate.DescendantRemoving:Connect(OnChanged))
	table.insert(
		Conns,
		Animate.AncestryChanged:Connect(function(_, Parent)
			if not Parent then
				local Live = ByCharacter[Session.Character]
				if Live == Session and Live.Animate == Animate then
					AttachAnimate(Live, FindAnimate(Session.Character))
				end
			end
		end)
	)
end

AttachAnimate = function(Session: Session, Animate: Instance?)
	DisconnectList(Session.AnimateConns)
	Session.Animate = Animate
	if Animate then
		WatchAnimate(Session, Animate)
		SetAnimateDisabled(Animate, Session.Owns)
	end
	Rebuild(Session)
end

local function Insert(Session: Session)
	ByCharacter[Session.Character] = Session
	Sessions[#Sessions + 1] = Session
end

local function Remove(Session: Session)
	ByCharacter[Session.Character] = nil
	local Index = table.find(Sessions, Session)
	if Index then
		table.remove(Sessions, Index)
	end
end

function CharacterBinder.Refresh(Session: Session): boolean
	local Character = Session.Character
	if not Character.Parent then
		ReleaseCharacter(Character)
		return false
	end

	local Humanoid = Session.Humanoid
	if not Humanoid.Parent then
		local NextHumanoid = Character:FindFirstChildOfClass("Humanoid")
		if not NextHumanoid then
			return false
		end
		Session.Humanoid = NextHumanoid
		Humanoid = NextHumanoid
	end

	if not Session.Root.Parent then
		local NextRoot = FindRoot(Character, Humanoid)
		if not NextRoot then
			return false
		end
		Session.Root = NextRoot
	else
		local HumanoidRoot = Humanoid.RootPart
		if HumanoidRoot and HumanoidRoot ~= Session.Root and HumanoidRoot.Parent == Character then
			Session.Root = HumanoidRoot
		end
	end

	local Animate = Session.Animate
	if not Animate or not Animate.Parent then
		AttachAnimate(Session, FindAnimate(Character))
	elseif next(Session.Catalog.Slots) == nil then
		Rebuild(Session)
	end

	Session.PartsDirty = false
	return true
end

local function ClaimCharacter(Character: Model): boolean
	if ByCharacter[Character] then
		return true
	end
	if not Character.Parent then
		return false
	end
	if IsClient then
		local LocalPlayer = Players.LocalPlayer
		if not LocalPlayer or Character ~= LocalPlayer.Character then
			return false
		end
	end

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local RootPart = FindRoot(Character, Humanoid)
	if not Humanoid or not RootPart then
		return false
	end

	local Conns: { RBXScriptConnection } = {}
	local Player = Players:GetPlayerFromCharacter(Character)
	local DesiredOwns = Enabled and PlayerWantsAnimBlend(Player)
	local Session: Session = {
		Character = Character,
		Player = Player,
		Humanoid = Humanoid,
		Root = RootPart,
		Animate = nil,
		ScaleDamp = nil,
		Catalog = PoseCatalog.Build(nil),
		Profile = RigProfile.Resolve(RigTypeName(Humanoid), {
			HasDistinctRun = false,
			HasSwimSlots = false,
		}, nil),
		PartsDirty = false,
		-- Stock stays live until Rebuild finishes.
		Owns = false,
		RebuildQueued = false,
		Conns = Conns,
		AnimateConns = {},
	}

	table.insert(
		Conns,
		Character.AncestryChanged:Connect(function(_, Parent)
			if not Parent then
				ReleaseCharacter(Character)
			end
		end)
	)
	table.insert(
		Conns,
		Character.ChildAdded:Connect(function(Child)
			local Live = ByCharacter[Character]
			if not Live then
				return
			end
			Live.PartsDirty = true
			if Child.Name == "Animate" then
				AttachAnimate(Live, Child)
			elseif Child.Name == "HumanoidRootPart" and Child:IsA("BasePart") then
				Live.Root = Child
			elseif Child:IsA("Humanoid") then
				Live.Humanoid = Child
				local NextRoot = FindRoot(Character, Child)
				if NextRoot then
					Live.Root = NextRoot
				end
				Rebuild(Live)
			end
		end)
	)
	table.insert(
		Conns,
		Character.ChildRemoved:Connect(function(Child)
			local Live = ByCharacter[Character]
			if not Live then
				return
			end
			Live.PartsDirty = true
			if Child == Live.Animate then
				AttachAnimate(Live, FindAnimate(Character))
			end
		end)
	)
	table.insert(
		Conns,
		Humanoid:GetPropertyChangedSignal("RigType"):Connect(function()
			local Live = ByCharacter[Character]
			if Live then
				Rebuild(Live)
			end
		end)
	)

	Insert(Session)
	PendingBinds[Character] = nil
	AttachAnimate(Session, FindAnimate(Character))
	SetSessionOwning(Session, DesiredOwns)
	return true
end

CharacterBinder.Claim = ClaimCharacter

ReleaseCharacter = function(Character: Model)
	PendingBinds[Character] = nil
	local Session = ByCharacter[Character]
	if not Session then
		return
	end
	if Session.Owns then
		ResetTracks(Session, 0)
	end
	DisconnectList(Session.Conns)
	DisconnectList(Session.AnimateConns)
	Remove(Session)
	Session.Owns = false
	SetAnimateDisabled(Session.Animate, false)
	local Player = Session.Player
	if Player and PlayerCharacter[Player] == Character then
		PlayerCharacter[Player] = nil
	end
end

CharacterBinder.Release = ReleaseCharacter

local function BindCharacter(Character: Model)
	local Existing = ByCharacter[Character]
	if Existing then
		Existing.PartsDirty = true
		CharacterBinder.Refresh(Existing)
		return
	end
	if PendingBinds[Character] then
		return
	end
	if ClaimCharacter(Character) then
		return
	end

	PendingBinds[Character] = true
	local Conn: RBXScriptConnection? = nil
	Conn = Character.ChildAdded:Connect(function()
		if ClaimCharacter(Character) then
			if Conn then
				Conn:Disconnect()
				Conn = nil
			end
		end
	end)
	task.delay(BindWaitSeconds, function()
		if Conn then
			Conn:Disconnect()
			Conn = nil
		end
		PendingBinds[Character] = nil
		if Character.Parent and not ByCharacter[Character] then
			ClaimCharacter(Character)
		end
	end)
	task.defer(function()
		if Character.Parent and PendingBinds[Character] then
			ClaimCharacter(Character)
		end
	end)
end

CharacterBinder.Bind = BindCharacter

function CharacterBinder.Get(Character: Model): Session?
	return ByCharacter[Character]
end

ResetTracks = function(Session: Session, Fade: number?)
	local Animator = Session.Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		return
	end
	TrackDriver.StopAll(Animator, Session.Catalog.AllIds, Fade or ToggleFade)
end

CharacterBinder.ResetTracks = ResetTracks

SetSessionOwning = function(Session: Session, Active: boolean)
	if Session.Owns == Active then
		return
	end
	Session.Owns = Active
	if Active then
		SetAnimateDisabled(Session.Animate, true)
		Session.PartsDirty = true
		CharacterBinder.Refresh(Session)
		ResetTracks(Session)
	else
		-- Stock cannot re-initialize mid-life; it returns on the next respawn.
		ResetTracks(Session)
		SetAnimateDisabled(Session.Animate, false)
	end
end

function CharacterBinder.SetOwning(Active: boolean)
	Enabled = Active
	for _, Session in Sessions do
		SetSessionOwning(Session, Active and PlayerWantsAnimBlend(Session.Player))
	end
end

function CharacterBinder.SetPlayerOwning(Player: Player, Active: boolean)
	for _, Session in Sessions do
		if Session.Player == Player then
			SetSessionOwning(Session, Enabled and Active)
		end
	end
end

local function TrackPlayer(Player: Player)
	if IsClient and Player ~= Players.LocalPlayer then
		return
	end

	Player:GetAttributeChangedSignal(EnabledAttribute):Connect(function()
		CharacterBinder.SetPlayerOwning(Player, PlayerWantsAnimBlend(Player))
	end)

	Player.CharacterAdded:Connect(function(Character)
		local Prev = PlayerCharacter[Player]
		if Prev and Prev ~= Character then
			ReleaseCharacter(Prev)
		end
		PlayerCharacter[Player] = Character
		BindCharacter(Character)
	end)
	Player.CharacterRemoving:Connect(function(Character)
		if PlayerCharacter[Player] == Character then
			PlayerCharacter[Player] = nil
		end
		ReleaseCharacter(Character)
	end)

	local Current = Player.Character
	if Current then
		PlayerCharacter[Player] = Current
		BindCharacter(Current)
	end
end

function CharacterBinder.Start()
	for _, Player in Players:GetPlayers() do
		TrackPlayer(Player)
	end
	Players.PlayerAdded:Connect(TrackPlayer)
	Players.PlayerRemoving:Connect(function(Player)
		local Character = PlayerCharacter[Player] or Player.Character
		if Character then
			ReleaseCharacter(Character)
		end
		PlayerCharacter[Player] = nil
	end)
end

return CharacterBinder

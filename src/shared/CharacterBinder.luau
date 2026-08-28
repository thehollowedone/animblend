--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local Config = require(Root:WaitForChild("Config"))
local PoseCatalog = require(Root:WaitForChild("PoseCatalog"))
local RigProfile = require(Root:WaitForChild("RigProfile"))
local StockCatalog = require(Root:WaitForChild("StockCatalog"))
local TrackDriver = require(Root:WaitForChild("TrackDriver"))

local CharacterBinder = {}

export type Session = {
	Character: Model,
	Player: Player?,
	Humanoid: Humanoid,
	Root: BasePart,
	Animate: Instance?,
	EmoteAction: InputAction?,
	PlayEmote: BindableFunction?,
	ScaleDamp: NumberValue?,
	Catalog: PoseCatalog.Catalog,
	CatalogSignature: string?,
	LeasedIds: { string },
	Profile: RigProfile.Profile,
	PartsDirty: boolean,
	Owns: boolean,
	Drives: boolean,
	RebuildQueued: boolean,
	Seed: number,
	Conns: { RBXScriptConnection },
	AnimateConns: { RBXScriptConnection },
	AnimateInputConns: { RBXScriptConnection },
	HumanoidConns: { RBXScriptConnection },
	CatalogConn: RBXScriptConnection?,
}

local BindWaitSeconds = 30
local ToggleFade = 0.15
local IsClient = RunService:IsClient()
local IsServer = RunService:IsServer()

local Sessions: { Session } = {}
local ByCharacter: { [Model]: Session } = {}
local PlayerCharacter: { [Player]: Model } = {}
local PendingBinds: { [Model]: boolean } = {}
local CatalogValueName = "AnimBlendCatalog"

CharacterBinder.Sessions = Sessions

local ReleaseCharacter: (Model) -> ()
local AttachAnimate: (Session, Instance?) -> ()
local ResetTracks: (Session, number?) -> ()
local SetSessionOwning: (Session, boolean) -> ()
local SetupEmotes: (Session) -> ()

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
	if Animate:IsA("BaseScript") then
		Animate.Enabled = not Disabled
	end
	for _, Child in Animate:GetDescendants() do
		if Child:IsA("BaseScript") then
			Child.Enabled = not Disabled
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

-- Only the owning client predicts its character; every other rig it renders is
-- replicated, and forcing prediction on those would fight replication.
local function IsPredictedLocally(Session: Session): boolean
	local LocalPlayer = Players.LocalPlayer
	return IsClient and LocalPlayer ~= nil and Session.Character == LocalPlayer.Character
end

local function FindCatalogValue(Character: Model): StringValue?
	local Found = Character:FindFirstChild(CatalogValueName)
	if Found and Found:IsA("StringValue") then
		return Found
	end
	return nil
end

local function ClearEmoteBinding(Session: Session)
	local Bindable = Session.PlayEmote
	if Bindable then
		Bindable.OnInvoke = nil
	end
	Session.PlayEmote = nil
end

local function FindCharacterContext(Player: Player): Instance?
	local Contexts = Player:FindFirstChild("InputContexts")
	return if Contexts then Contexts:FindFirstChild("CharacterContext") else nil
end

SetupEmotes = function(Session: Session)
	ClearEmoteBinding(Session)
	local Player = Session.Player
	if not Player then
		Session.EmoteAction = nil
		return
	end

	local Context = FindCharacterContext(Player)
	local Found = if Context then Context:FindFirstChild("EmoteAction") else nil
	if not Found and IsServer and Context then
		local Created = Instance.new("InputAction")
		Created.Name = "EmoteAction"
		Created.Type = Enum.InputActionType.Direction1D
		Created.Parent = Context
		Found = Created
	end
	Session.EmoteAction = if Found and Found:IsA("InputAction") then Found else nil

	if not IsClient or Player ~= Players.LocalPlayer or not Session.Animate then
		return
	end
	local Candidate = Session.Animate:FindFirstChild("PlayEmote")
	if not Candidate or not Candidate:IsA("BindableFunction") then
		return
	end

	local function Invoke(Emote: any): boolean
		if type(Emote) ~= "string" then
			return false
		end
		local Index = StockCatalog.EmoteIndexByName[Emote]
		local Action = Session.EmoteAction
		if not Index or not Action or not Action.Parent then
			return false
		end
		local Previous = Session.Root:GetAttribute(StockCatalog.EmoteInputAttribute)
		local Toggled = type(Previous) == "number" and Previous > StockCatalog.EmoteFireToggle
		local Value = Index + (if Toggled then 0 else StockCatalog.EmoteFireToggle)
		local Fired = pcall(Action.Fire, Action, Value)
		return Fired
	end

	Session.PlayEmote = Candidate
	Candidate.OnInvoke = Invoke
end

local function PublishCatalog(Character: Model, Signature: string)
	local Value = FindCatalogValue(Character)
	if not Value then
		Value = Instance.new("StringValue")
		Value.Name = CatalogValueName
		Value.Value = Signature
		Value.Parent = Character
	elseif Value.Value ~= Signature then
		Value.Value = Signature
	end
end

local function Rebuild(Session: Session)
	local Animate = Session.Animate
	local PreviousCatalog = Session.Catalog
	local PreviousSignature = Session.CatalogSignature
	local LocalCatalog = PoseCatalog.Build(Animate, RigTypeName(Session.Humanoid))
	local Animator: Animator?
	if IsPredictedLocally(Session) then
		Animator = TrackDriver.PrepareAnimator(Session.Humanoid)
	elseif IsServer and Session.Owns and #LocalCatalog.AllIds > 0 then
		SetAnimateDisabled(Animate, true)
		Animator = TrackDriver.TakeOwnership(Session.Humanoid)
	else
		Animator = TrackDriver.EnsureAnimator(Session.Humanoid)
	end

	local CatalogValue = if IsClient then FindCatalogValue(Session.Character) else nil
	local Published = if CatalogValue then CatalogValue.Value else nil
	local Decoded = if IsClient
			and Animator
			and TrackDriver.IsOwned(Animator)
			and type(Published) == "string"
			and Published ~= ""
		then PoseCatalog.Decode(Published)
		else nil
	local Catalog = Decoded or LocalCatalog
	local Signature = if Decoded then Published :: string else nil
	if IsServer and Session.Owns and Animator and #Catalog.AllIds > 0 then
		Signature = PoseCatalog.Encode(Catalog)
	end
	if Animator and PreviousSignature ~= nil and Signature ~= PreviousSignature then
		TrackDriver.StopAll(Animator, PreviousCatalog.AllIds, ToggleFade)
	end
	Session.Catalog = Catalog
	Session.CatalogSignature = Signature
	TrackDriver.ReplaceLease(Session.LeasedIds, Catalog.AllIds)
	Session.LeasedIds = table.clone(Catalog.AllIds)
	if IsClient then
		SetAnimateDisabled(Animate, Session.Owns and Decoded ~= nil)
	end

	local Name = RigTypeName(Session.Humanoid)
	Session.Profile = RigProfile.Resolve(Name, {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	}, Overrides(Name))

	local Damp = if Animate then Animate:FindFirstChild("ScaleDampeningPercent") else nil
	Session.ScaleDamp = if Damp and Damp:IsA("NumberValue") then Damp else nil
	SetupEmotes(Session)

	if IsServer and Signature and Animator then
		PublishCatalog(Session.Character, Signature)
	end

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

local function WatchAnimator(Session: Session)
	TrackDriver.PrepareAnimator(Session.Humanoid)
	QueueRebuild(Session)
end

local function BindHumanoid(Session: Session, Humanoid: Humanoid, RebuildNow: boolean)
	DisconnectList(Session.HumanoidConns)
	Session.Humanoid = Humanoid
	local NextRoot = FindRoot(Session.Character, Humanoid)
	if NextRoot then
		Session.Root = NextRoot
	end

	local function IsCurrent(): boolean
		return ByCharacter[Session.Character] == Session and Session.Humanoid == Humanoid
	end

	table.insert(
		Session.HumanoidConns,
		Humanoid:GetPropertyChangedSignal("RigType"):Connect(function()
			if IsCurrent() then
				Rebuild(Session)
			end
		end)
	)
	table.insert(
		Session.HumanoidConns,
		Humanoid.ChildAdded:Connect(function(Child)
			if not Child:IsA("Animator") or not IsCurrent() then
				return
			end
			if IsPredictedLocally(Session) then
				WatchAnimator(Session)
			elseif IsServer and Session.Owns and not TrackDriver.IsOwned(Child) then
				task.defer(function()
					if IsCurrent() and Session.Owns then
						TrackDriver.TakeOwnership(Humanoid)
					end
				end)
			end
		end)
	)

	if RebuildNow and IsCurrent() then
		Rebuild(Session)
	end
end

local function WatchCatalog(Session: Session, Value: StringValue?)
	if Session.CatalogConn then
		Session.CatalogConn:Disconnect()
		Session.CatalogConn = nil
	end
	Session.CatalogSignature = nil
	if Value then
		Session.CatalogConn = Value.Changed:Connect(function()
			if ByCharacter[Session.Character] == Session then
				Session.CatalogSignature = nil
				QueueRebuild(Session)
			end
		end)
	end
	if ByCharacter[Session.Character] == Session then
		QueueRebuild(Session)
	end
end

local function WatchAnimate(Session: Session, Animate: Instance)
	local Conns = Session.AnimateConns
	local InputConns = Session.AnimateInputConns

	local function QueueIfLive()
		if ByCharacter[Session.Character] == Session and Session.Animate == Animate then
			SetupEmotes(Session)
			QueueRebuild(Session)
		end
	end

	local function WatchInput(Input: Instance)
		if Input:IsA("Animation") then
			table.insert(
				InputConns,
				Input:GetPropertyChangedSignal("AnimationId"):Connect(QueueIfLive)
			)
			table.insert(
				InputConns,
				Input:GetAttributeChangedSignal("LinearVelocity"):Connect(QueueIfLive)
			)
		elseif Input:IsA("StringValue") or Input:IsA("NumberValue") then
			table.insert(InputConns, Input.Changed:Connect(QueueIfLive))
		end
		if
			Input:IsA("Animation")
			or Input:IsA("StringValue")
			or Input:IsA("NumberValue")
			or Input:IsA("Folder")
		then
			table.insert(InputConns, Input:GetPropertyChangedSignal("Name"):Connect(QueueIfLive))
		end
	end

	local function RewatchInputs()
		DisconnectList(InputConns)
		if ByCharacter[Session.Character] ~= Session or Session.Animate ~= Animate then
			return
		end
		for _, Descendant in Animate:GetDescendants() do
			WatchInput(Descendant)
		end
	end

	local function OnChanged(Child: Instance)
		if Child.Name == "PlayEmote" then
			SetupEmotes(Session)
		end
		if
			Child:IsA("Animation")
			or Child:IsA("StringValue")
			or Child:IsA("NumberValue")
			or Child:IsA("Folder")
		then
			QueueRebuild(Session)
		end
		task.defer(RewatchInputs)
	end

	RewatchInputs()
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
	DisconnectList(Session.AnimateInputConns)
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
		BindHumanoid(Session, NextHumanoid, true)
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
	if
		IsClient
		and not Player
		and Players.LocalPlayer
		and Character == Players.LocalPlayer.Character
	then
		-- GetPlayerFromCharacter can lag the local Character assignment during
		-- join/respawn. Losing the Player here also loses prediction setup and the
		-- server-matching variant seed, which presents as owner-view catch-up.
		Player = Players.LocalPlayer
	end
	local Session: Session = {
		Character = Character,
		Player = Player,
		Humanoid = Humanoid,
		Root = RootPart,
		Animate = nil,
		EmoteAction = nil,
		PlayEmote = nil,
		ScaleDamp = nil,
		Catalog = PoseCatalog.Build(nil),
		CatalogSignature = nil,
		LeasedIds = {},
		Profile = RigProfile.Resolve(RigTypeName(Humanoid), {
			HasDistinctRun = false,
			HasSwimSlots = false,
		}, nil),
		PartsDirty = false,
		Owns = false,
		Drives = true,
		RebuildQueued = false,
		Seed = if Player then Player.UserId else 0,
		Conns = Conns,
		AnimateConns = {},
		AnimateInputConns = {},
		HumanoidConns = {},
		CatalogConn = nil,
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
			elseif IsClient and Child.Name == CatalogValueName and Child:IsA("StringValue") then
				WatchCatalog(Live, Child)
			elseif Child.Name == "HumanoidRootPart" and Child:IsA("BasePart") then
				Live.Root = Child
			elseif Child:IsA("Humanoid") then
				BindHumanoid(Live, Child, true)
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
			elseif IsClient and Child.Name == CatalogValueName then
				WatchCatalog(Live, FindCatalogValue(Character))
			end
		end)
	)
	if Player then
		table.insert(
			Conns,
			Player.DescendantAdded:Connect(function(Descendant)
				if Descendant.Name == "CharacterContext" or Descendant.Name == "EmoteAction" then
					local Live = ByCharacter[Character]
					if Live then
						SetupEmotes(Live)
					end
				end
			end)
		)
	end

	Insert(Session)
	BindHumanoid(Session, Humanoid, false)
	PendingBinds[Character] = nil
	AttachAnimate(Session, FindAnimate(Character))
	SetSessionOwning(Session, true)
	if IsPredictedLocally(Session) then
		WatchCatalog(Session, FindCatalogValue(Character))
		local Animator = Humanoid:FindFirstChildOfClass("Animator")
		if Animator then
			WatchAnimator(Session)
		end
	end
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
	TrackDriver.ReplaceLease(Session.LeasedIds, {})
	table.clear(Session.LeasedIds)
	DisconnectList(Session.Conns)
	DisconnectList(Session.AnimateConns)
	DisconnectList(Session.AnimateInputConns)
	DisconnectList(Session.HumanoidConns)
	ClearEmoteBinding(Session)
	if Session.CatalogConn then
		Session.CatalogConn:Disconnect()
		Session.CatalogConn = nil
	end
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

-- Stock's own gate: only a peer that simulates the character may write to it,
-- authoritatively on the server or predictively on the owning client. Writing
-- from a peer that merely receives the character fights replication.
local function IsSimulated(Instance: Instance): boolean
	local Ok, Status = pcall(RunService.GetPredictionStatus, RunService, Instance)
	if not Ok then
		-- A transient status read failure must never permanently turn prediction
		-- gating off. The server remains authoritative; clients retry next step.
		return not IsClient
	end
	return Status ~= Enum.PredictionStatus.None
end

-- Level-triggered on purpose. Session.Drives is plain Lua state that a rollback
-- does not restore, so an edge on it must never carry a side effect: a replayed
-- frame would fire a stop the authoritative pass never asked for.
function CharacterBinder.ShouldDrive(Session: Session): boolean
	local Animator = Session.Humanoid:FindFirstChildWhichIsA("Animator")
	Session.Drives = Animator ~= nil
		and TrackDriver.IsOwned(Animator)
		and (not IsClient or type(Session.CatalogSignature) == "string")
		and IsSimulated(Session.Root)
		and IsSimulated(Animator)
	return Session.Drives
end

SetSessionOwning = function(Session: Session, Active: boolean)
	if Session.Owns == Active then
		return
	end
	Session.Owns = Active
	if Active then
		Rebuild(Session)
	else
		ResetTracks(Session)
		SetAnimateDisabled(Session.Animate, false)
	end
end

local function TrackPlayer(Player: Player)
	if IsClient and Player ~= Players.LocalPlayer then
		return
	end

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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local Config = require(Root:WaitForChild("Config"))
local AnimBlend = require(Root:WaitForChild("AnimBlend"))

local EnabledAttribute = "AnimBlendEnabled"
local ToggleAvailable = Config.ShowToggleUi == true and RunService:IsStudio()

local function InitializePlayer(Player: Player)
    if Player:GetAttribute(EnabledAttribute) == nil then
        Player:SetAttribute(EnabledAttribute, Config.EnabledByDefault ~= false)
    end
end

Players.PlayerAdded:Connect(InitializePlayer)
for _, Player in Players:GetPlayers() do
    InitializePlayer(Player)
end

local Remotes = Root:FindFirstChild("Remotes")
local Existing = if Remotes then Remotes:FindFirstChild("SetEnabled") else nil
local SetEnabled: RemoteEvent? = nil

if ToggleAvailable then
    if not Remotes then
        Remotes = Instance.new("Folder")
        Remotes.Name = "Remotes"
        Remotes.Parent = Root
    end
    if Existing and Existing:IsA("RemoteEvent") then
        SetEnabled = Existing
    else
        if Existing then
            Existing:Destroy()
        end
        SetEnabled = Instance.new("RemoteEvent")
        SetEnabled.Name = "SetEnabled"
        SetEnabled.Parent = Remotes
    end
else
    if Existing then
        Existing:Destroy()
    end
    if Remotes and #Remotes:GetChildren() == 0 then
        Remotes:Destroy()
    end
end

AnimBlend.Init()

if SetEnabled then
    SetEnabled.OnServerEvent:Connect(function(Player, Value)
        if type(Value) == "boolean" then
            Player:SetAttribute(EnabledAttribute, Value)
            -- Stock only comes back on a fresh character.
            if not Value then
                Player:LoadCharacter()
            end
        end
    end)
end

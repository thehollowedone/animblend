local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")

local ToggleUi = {}

local GuiName = "AnimBlendToggle"
local EnabledAttribute = "AnimBlendEnabled"
local RemoteWaitSeconds = 10

local function IsOn(Player: Player): boolean
    return Player:GetAttribute(EnabledAttribute) == true
end

local function SetLabel(Player: Player, Button: TextButton)
    Button.Text = if IsOn(Player) then "AnimBlend: ON" else "AnimBlend: OFF"
    Button.BackgroundColor3 = if IsOn(Player)
        then Color3.fromRGB(40, 120, 70)
        else Color3.fromRGB(90, 50, 50)
end

function ToggleUi.Mount()
    local Player = Players.LocalPlayer
    local PlayerGui = Player:WaitForChild("PlayerGui")
    if PlayerGui:FindFirstChild(GuiName) then
        return
    end

    local Remotes = Root:WaitForChild("Remotes", RemoteWaitSeconds)
    local SetEnabled = if Remotes
        then Remotes:WaitForChild("SetEnabled", RemoteWaitSeconds)
        else nil
    if not SetEnabled or not SetEnabled:IsA("RemoteEvent") then
        warn("AnimBlend: toggle UI is enabled on the client but the server never published its RemoteEvent")
        return
    end

    local Gui = Instance.new("ScreenGui")
    Gui.Name = GuiName
    Gui.ResetOnSpawn = false
    Gui.IgnoreGuiInset = true
    Gui.DisplayOrder = 1000
    Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local Button = Instance.new("TextButton")
    Button.Name = "Toggle"
    Button.AnchorPoint = Vector2.new(1, 0)
    Button.Position = UDim2.new(1, -16, 0, 16)
    Button.Size = UDim2.fromOffset(148, 36)
    Button.BorderSizePixel = 0
    Button.AutoButtonColor = true
    Button.Font = Enum.Font.GothamMedium
    Button.TextSize = 14
    Button.TextColor3 = Color3.fromRGB(245, 245, 245)
    Button.Parent = Gui

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 8)
    Corner.Parent = Button

    local Stroke = Instance.new("UIStroke")
    Stroke.Thickness = 1
    Stroke.Color = Color3.fromRGB(255, 255, 255)
    Stroke.Transparency = 0.75
    Stroke.Parent = Button

    SetLabel(Player, Button)
    Button.Activated:Connect(function()
        SetEnabled:FireServer(not IsOn(Player))
    end)
    Player:GetAttributeChangedSignal(EnabledAttribute):Connect(function()
        if Button.Parent then
            SetLabel(Player, Button)
        end
    end)

    Gui.Parent = PlayerGui
end

return ToggleUi

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local Config = require(Root:WaitForChild("Config"))
local AnimBlend = require(Root:WaitForChild("AnimBlend"))

AnimBlend.Init()

if Config.ShowToggleUi == true and RunService:IsStudio() then
    require(script:WaitForChild("ToggleUi")).Mount()
end

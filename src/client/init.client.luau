--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("AnimBlend")
local AnimBlend = require(Root:WaitForChild("AnimBlend"))

AnimBlend.Init()

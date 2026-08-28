local Expect = require("./support/expect")
local VariantPicker = require("../src/shared/VariantPicker")

local T = Expect.New("VariantPicker")

local Empty = {}
local Single = { { Id = "rbxassetid://1", Weight = 10 } }
local Weighted =
	{ { Id = "rbxassetid://heavy", Weight = 9 }, { Id = "rbxassetid://light", Weight = 1 } }
local Triple = {
	{ Id = "rbxassetid://a", Weight = 1 },
	{ Id = "rbxassetid://b", Weight = 1 },
	{ Id = "rbxassetid://c", Weight = 9 },
}

T:Equal("total weight empty", VariantPicker.TotalWeight(Empty), 0)
T:Equal("total weight single", VariantPicker.TotalWeight(Single), 10)
T:Equal("total weight weighted", VariantPicker.TotalWeight(Weighted), 10)
T:Equal("total weight triple", VariantPicker.TotalWeight(Triple), 11)

T:Equal("empty list picks nil", VariantPicker.Pick(Empty, 1234), nil)

local SingleOk = true
for Bucket = 1, 200 do
	local Got = VariantPicker.Pick(Single, Bucket)
	if not Got or Got.Id ~= "rbxassetid://1" then
		SingleOk = false
		break
	end
end
T:True("single variant always selected", SingleOk)

local First = VariantPicker.Pick(Weighted, 987654)
local Stable = true
for _ = 1, 1000 do
	local Again = VariantPicker.Pick(Weighted, 987654)
	if not Again or not First or Again.Id ~= First.Id then
		Stable = false
		break
	end
end
T:True("same bucket is deterministic", Stable)

local Heavy = 0
local Member = true
for Bucket = 1, 10000 do
	local Got = VariantPicker.Pick(Weighted, Bucket)
	if not Got then
		Member = false
		break
	end
	if Got.Id == "rbxassetid://heavy" then
		Heavy += 1
	elseif Got.Id ~= "rbxassetid://light" then
		Member = false
		break
	end
end
T:True("always returns a member", Member)
T:Between("weight 9 of 10 dominates", Heavy / 10000, 0.8, 0.95)

local BigOk = true
for _, Bucket in { 7.0e9, 6.9e9 + 13, 2 ^ 40, 2147483647, 4294967296 } do
	local Got = VariantPicker.Pick(Triple, Bucket)
	if not Got then
		BigOk = false
		break
	end
end
T:True("huge buckets stay valid", BigOk)

local BigStable = true
local BigFirst = VariantPicker.Pick(Triple, 7.0e9)
for _ = 1, 200 do
	local Again = VariantPicker.Pick(Triple, 7.0e9)
	if not Again or not BigFirst or Again.Id ~= BigFirst.Id then
		BigStable = false
		break
	end
end
T:True("huge buckets are deterministic", BigStable)

local Spread = {}
for Bucket = 1, 3000 do
	local Got = VariantPicker.Pick(Triple, Bucket)
	if Got then
		Spread[Got.Id] = true
	end
end
T:True(
	"all triple variants reachable",
	Spread["rbxassetid://a"] and Spread["rbxassetid://b"] and Spread["rbxassetid://c"]
)

return T

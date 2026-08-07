local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Roots = { "src/shared", "src/server", "src/client", "tests" }

local Checked, Failed = 0, 0

local function Walk(Path: string)
	for _, Entry in fs.readDir(Path) do
		local Full = Path .. "/" .. Entry
		if fs.isDir(Full) then
			Walk(Full)
		elseif string.match(Entry, "%.luau$") then
			Checked += 1
			local Source = fs.readFile(Full)
			local Ok, Err = pcall(luau.compile, Source)
			if not Ok then
				Failed += 1
				print(string.format("SYNTAX FAIL %s\n  %s", Full, tostring(Err)))
			end
		end
	end
end

for _, Root in Roots do
	if fs.isDir(Root) then
		Walk(Root)
	end
end

print(string.format("syntax checked=%d failed=%d", Checked, Failed))
if Failed > 0 then
	process.exit(1)
end

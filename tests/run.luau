local Suites = {
	require("./rig_profile_lune"),
	require("./variant_picker_lune"),
	require("./locomotion_solver_lune"),
	require("./integration_lune"),
}

local Passed, Failed = 0, 0
for _, Suite in Suites do
	Passed += Suite.Passed
	Failed += Suite.Failed
end

print(string.format("passed=%d failed=%d", Passed, Failed))
if Failed > 0 then
	error(string.format("%d assertion(s) failed", Failed))
end

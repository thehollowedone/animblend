local Suites = {
	require("./rig_profile_lune"),
	require("./variant_picker_lune"),
	require("./locomotion_solver_lune"),
	require("./configuration_bounds_lune"),
	require("./track_driver_hardening_lune"),
	require("./continuity_hardening_lune"),
	require("./binder_hardening_lune"),
	require("./integration_lune"),
	require("./server_authority_seams_lune"),
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

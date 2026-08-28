--!strict

return {
	SimulationFrequency = Enum.StepFrequency.Hz60,
	SimulationPriority = 4_001,
	-- Keep Roblox's distance/importance animation LOD by default for scale.
	-- Small experiences may set false when every remote avatar needs full-rate
	-- evaluation; the predicting owner's nearby character remains prioritized.
	AnimatorPreferLodEnabled = true,

	-- Optional synchronized Character attribute declaring that another system
	-- owns animation control. When true, AnimBlend immediately releases every
	-- track it manages and resumes only after the controller clears it. Rename
	-- the contract or set nil when an integration does not need explicit leases.
	ExternalControlAttribute = "AnimBlendExternalControl",

	RigOverrides = {
		R6 = {},
		R15 = {},
	},
}

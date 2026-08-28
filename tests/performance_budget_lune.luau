local Stub = require("./support/roblox_stub")

local CharacterCounts = { 40, 100, 200 }
local Frames = 300

local function Benchmark(CharacterCount: number)
	local Modules = Stub.Build()
	local Catalog = Stub.Catalog(Modules.PoseCatalog, {
		idle = { "rbxassetid://benchmark-idle-a", "rbxassetid://benchmark-idle-b" },
		walk = { "rbxassetid://benchmark-walk" },
		run = { "rbxassetid://benchmark-run" },
		jump = { "rbxassetid://benchmark-jump" },
		fall = { "rbxassetid://benchmark-fall" },
		climb = { "rbxassetid://benchmark-climb" },
		swim = { "rbxassetid://benchmark-swim" },
		swimidle = { "rbxassetid://benchmark-swim-idle" },
		sit = { "rbxassetid://benchmark-sit" },
		toolnone = { "rbxassetid://benchmark-tool" },
	})
	Modules.TrackDriver.Prepare(Catalog.AllIds)
	local Profile = Modules.RigProfile.Resolve("R15", {
		HasDistinctRun = Catalog.HasDistinctRun,
		HasSwimSlots = Catalog.HasSwimSlots,
	})
	local Worlds = {}
	for _ = 1, CharacterCount do
		local Animator = Stub.Animator()
		local Humanoid = Stub.Humanoid(Animator)
		local Session = Stub.Session(Humanoid, Profile, Catalog)
		Worlds[#Worlds + 1] = { Animator = Animator, Humanoid = Humanoid, Session = Session }
	end

	local Started = os.clock()
	for Frame = 1, Frames do
		local Speed = if Frame % 120 < 60 then 8 else 18
		for _, World in Worlds do
			World.Humanoid.RelativeVelocity = Stub.Vector3(Speed, 0, 0)
			World.Humanoid.MoveDirection = Stub.Vector3(1, 0, 0)
			Modules.AnimBlend.Step(World.Session)
		end
	end
	local Elapsed = os.clock() - Started
	local Scans = 0
	for _, World in Worlds do
		Scans += World.Animator.PlayingTrackScans
	end
	local ExpectedScans = CharacterCount * Frames
	if Scans ~= ExpectedScans then
		error(
			("expected one live-track scan per character-step; got %d, expected %d"):format(
				Scans,
				ExpectedScans
			)
		)
	end
	print(
		("characters=%d frames=%d total_ms=%.2f ms_per_frame=%.3f us_per_character_step=%.3f scans_per_step=1"):format(
			CharacterCount,
			Frames,
			Elapsed * 1_000,
			Elapsed * 1_000 / Frames,
			Elapsed * 1_000_000 / ExpectedScans
		)
	)
end

for _, CharacterCount in CharacterCounts do
	Benchmark(CharacterCount)
end

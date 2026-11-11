# AnimBlend

AnimBlend blends R6/R15 locomotion animations for Roblox **Server Authority**.
It replaces stock `Animate` and uses the same animation catalog format.

## Requirements

In Studio, select `Workspace` in Explorer and set `AuthorityMode` to **Server**
in Properties. AnimBlend requires `RunService:BindToSimulation()` at startup;
setup stops with an error if the engine rejects that binding.

## Install

```sh
rojo serve AnimBlend.project.json
```

Manual placement:

```text
ReplicatedStorage
└── AnimBlend                  <- src/shared
ServerScriptService
└── AnimBlendServer            <- src/server
StarterPlayer
└── StarterPlayerScripts
    └── AnimBlendClient        <- src/client
```

Deploy matching server and client modules together. Catalog payloads with legacy
tool slots are incompatible with the current modules.

## Configuration

Edit [src/shared/Config.luau](src/shared/Config.luau), which maps to
`ReplicatedStorage.AnimBlend.Config`. Configure it before startup: the modules
read the simulation, LOD and external-control settings when they load.

| Setting | Purpose |
| --- | --- |
| `SimulationFrequency` | Fixed-step frequency; default `Hz60` |
| `SimulationPriority` | Simulation ordering; default `4001` |
| `AnimatorPreferLodEnabled` | Roblox Animator LOD; default `true` |
| `ExternalControlAttribute` | Optional external-controller lease; default `AnimBlendExternalControl` |
| `RigOverrides` | R6/R15 overrides; defaults to empty tables. See the validated fields in [RigProfile](src/shared/RigProfile.luau). |

## Behavior

- Stock/custom `Animate` catalogs, weighted variants, and runtime edits
- R6 and R15 locomotion with existing stock-emote compatibility
- R15 directional blending and stride-phase continuity
- Roblox animation LOD and coexistence with externally owned action tracks

## Tool animations

Create and play weapon hold and attack tracks in your tool controller at Action priority or higher.
AnimBlend handles locomotion and leaves those independently owned tracks alone.

## Controller handoff

Physics, ragdoll, unknown states, `PlatformStand`, and death release AnimBlend-managed tracks.

Independent controllers should avoid Core-priority tracks with AnimBlend catalog IDs; use a higher priority or the handoff below.

If another controller needs to manage animations while the Humanoid remains in
a locomotion state, set the configured character attribute to boolean `true`:

```lua
character:SetAttribute("AnimBlendExternalControl", true) -- hand off
character:SetAttribute("AnimBlendExternalControl", nil) -- resume
```

Use the name configured by `ExternalControlAttribute` if you rename it. Setting
`ExternalControlAttribute = nil` disables this explicit handoff. Clearing the
attribute allows AnimBlend to resume when the Humanoid's state also permits it.

## Verify

Install Python 3.10 or later, Lune and StyLua for the offline checks below.
`rokit.toml` pins Rojo and luau-lsp; install those pins before type analysis.

```text
python tools/check-types.py
stylua --check --config-path .stylua.toml src tests
lune run tests/run.luau
lune run tests/syntax_check.luau
lune run tests/performance_budget_lune.luau
```

The automated suites use a Roblox test double to check deterministic math,
state transitions, replay fixtures and operation counts. Validate prediction,
replication and animation playback in Studio multiplayer tests.

The type checker scans every runtime module with both Luau solvers under default
flags and all available flags.

## References

- [Server Authority](https://create.roblox.com/docs/projects/server-authority)
- [Server Authority techniques](https://create.roblox.com/docs/projects/server-authority/techniques)

# AnimBlend

R6/R15 locomotion blending controller for Roblox **Server Authority**. Replaces stock `Animate` without replacing its catalog format.

## Requirement

In Studio, select `Workspace` in Explorer and set `AuthorityMode` to **Server** in Properties.

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

Deploy matching server and client modules together; older catalog payloads with tool slots are incompatible.

## Configuration

| Setting | Purpose |
| --- | --- |
| `SimulationFrequency` | Fixed-step frequency; default `Hz60` |
| `SimulationPriority` | Simulation ordering; default `4001` |
| `AnimatorPreferLodEnabled` | Roblox Animator LOD; default `true` |
| `ExternalControlAttribute` | Optional external-controller lease; default `AnimBlendExternalControl` |
| `RigOverrides` | R6/R15 overrides |

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

For controllers that retain a locomotion state:

```lua
character:SetAttribute("AnimBlendExternalControl", true) -- hand off
character:SetAttribute("AnimBlendExternalControl", nil) -- resume
```

## Verify

```text
python tools/check-types.py
stylua --check --config-path .stylua.toml src tests
lune run tests/run.luau
lune run tests/syntax_check.luau
lune run tests/performance_budget_lune.luau
```

The automated suites use a Roblox test double. They verify deterministic math,
state transitions, replay fixtures, and operation counts; they do not replace
Studio multiplayer validation of prediction, replication, and animation playback.

Install the tools pinned in `rokit.toml` before running type analysis. The checker
scans every runtime module with both Luau solvers, using default flags and all
available flags to catch inference differences also seen in Studio Script Analysis.

## References

- [Server Authority](https://create.roblox.com/docs/projects/server-authority)
- [Server Authority techniques](https://create.roblox.com/docs/projects/server-authority/techniques)

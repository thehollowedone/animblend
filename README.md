# AnimBlend

R6/R15 animation controller for Roblox **Server Authority**. Replaces stock `Animate` without replacing its catalog format.

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
- R6 and R15 locomotion, tools, emotes, and action layers
- R15 directional blending and stride-phase continuity
- Roblox animation LOD and external action tracks

Tools use `Handle.State` (`None`, `Slash`, `Lunge`). Synchronized tools may publish `ToolAnimationInputContext` and `ToolAnimationInputAction`; legacy `toolanim` remains supported.

## Controller handoff

Physics, ragdoll, unknown states, `PlatformStand`, and death release AnimBlend-managed tracks.

For controllers that retain a locomotion state:

```lua
character:SetAttribute("AnimBlendExternalControl", true) -- hand off
character:SetAttribute("AnimBlendExternalControl", nil) -- resume
```

## Verify

```text
stylua --check --config-path .stylua.toml src tests
lune run tests/run.luau
lune run tests/syntax_check.luau
lune run tests/performance_budget_lune.luau
```

## References

- [Server Authority](https://create.roblox.com/docs/projects/server-authority)
- [Server Authority techniques](https://create.roblox.com/docs/projects/server-authority/techniques)

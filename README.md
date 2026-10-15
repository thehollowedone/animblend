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

## Weapon animation boundary and migration

AnimBlend does not own weapon or combat animation. The weapon controller owns its
hold and attack poses, inputs, timing, rollback state, and cleanup. Existing stock
emote support remains available; this change does not remove PlayEmote or EmoteAction.

Removed behavior and configuration:

- Legacy `toolanim` StringValues are neither read nor destroyed.
- `Handle.State` commands and `ToolAnimationSequence` / `ToolAnimationStartedAt`
  are no longer consumed.
- `ToolAnimationInputContext` / `ToolAnimationInputAction` are no longer read.
- `AnimBlendToolIdentity` is no longer assigned; `AnimBlendTool*` rollback state
  is no longer written.
- Automatic `toolnone`, `toolslash`, and `toollunge` poses, stock weapon IDs,
  and the `FadeTool` rig override are removed.

Legacy gear relying on those hooks must provide its own hold/attack animation.
Providence's sword at commit `c224698367c222cbe0747fe627581a5f411a8c37`
already presents its poses through its own C0/Grip controller and does not depend
on these hooks. An AnimationTrack-based weapon controller should use Action or
higher priority and own those tracks separately.

AnimBlend keeps an existing shared Animator and leaves external Idle, Movement,
and Action-priority tracks untouched, even when they share a catalog asset ID.
For stock/replicated locomotion compatibility it can adopt Core-priority tracks
whose IDs match its catalog. Do not use the same Core-priority catalog IDs for an
independent controller; use a higher priority or the external-control handoff.
Locally created AnimBlend tracks remain managed by AnimBlend.

Deploy matching server and client modules together. The catalog uses named slots;
older payloads containing tool slots are not accepted by this version. Validate
replicated playback and handoff in Studio multiplayer before release.

## Controller handoff

Physics, ragdoll, unknown states, `PlatformStand`, and death release AnimBlend-managed tracks.

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

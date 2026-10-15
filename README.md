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

The server assigns each equipped Handle an immutable `AnimBlendToolIdentity` outside simulation. AnimBlend records the current identity on the predicted character root, so rollback restores tool ownership together with the action. Clients wait for the identity before consuming synchronized requests. The identity is managed automatically; do not author or copy it as a tool configuration value.


### Sword command compatibility

The [Linked Sword script discussed in this 2023 post](https://devforum.roblox.com/t/attempting-to-decipher-the-script-of-the-linked-sword-default-sword/2388604) emits a fresh `toolanim` value for each accepted attack. A second activation less than 0.2 seconds after the preceding one requests Lunge; otherwise it requests Slash. The lunge blocks further activation for about one second. AnimBlend preserves those producer decisions: each fresh command restarts its requested animation, including another Slash during the previous animation's 0.3-second window. Consumed legacy command objects are removed after simulation so they cannot hide later commands.

That historical script uses ordinary tool events and yields; it is not a Server Authority prediction implementation. Legacy `toolanim` support does not make its attacks, damage, movement, or cooldowns rollback-safe. For predicted combat, port the gameplay producer to synchronized input and rollback-managed state, then publish a one-step `Handle.State` command before AnimBlend's simulation priority. Configure both `ToolAnimationInputContext` and `ToolAnimationInputAction` on that Handle. AnimBlend consumes the command by resetting State to None. Keep click classification and cooldown ownership in the producer. A sequence-only replication update does not create a new synchronized command.

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

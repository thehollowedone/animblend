# AnimBlend

AnimBlend is a server-authority locomotion controller for Roblox R6 and R15 characters. It replaces stock `Animate` locomotion while preserving a clean hand-off for emotes, tools, and custom action animations.

Stock `Animate`, on both R6 and R15, drives poses from `Humanoid` events, caches `AnimationTrack` handles, and times transitions with wall-clock deltas. Under server authority the client is rewound and replayed: events do not re-fire, cached handles stop matching the visible track, and wall-clock timers advance twice. Locomotion sticks, snaps, or plays two poses at once.

## Install

Use Rojo to sync the project:

```bash
rojo serve AnimBlend.project.json
```

| Source | Roblox destination |
|---|---|
| `src/shared` | `ReplicatedStorage.AnimBlend` |
| `src/server` | `ServerScriptService.AnimBlendServer` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.AnimBlendClient` |

Set `AuthorityMode` on `Workspace` Properties to `Server`. AnimBlend is only meant for use on Server Authority.

## How it works

AnimBlend runs the same controller through `RunService:BindToSimulation` on the server and local client. It preloads locomotion assets before disabling stock `Animate` and reacquires live tracks by animation ID on every simulation step. Decisions run on `Enum.StepFrequency.Hz60` at priority `4000`, the same cadence and ordering slot stock `Animate` uses; `BindToSimulation` defaults to `Hz30`, which is half that. The engine interpolates track weights between steps, so render rate is independent of it. Clients set `PredictionMode.On` on the `Animator` before loading anything, as stock does; without it a replicated track cannot be resolved by animation ID and the client drives a duplicate. Clients wait up to 30 seconds for the server handshake, then warn and start.

## Animation behavior

- `idle`, `walk`, and `run` stay alive at a small weight floor so they resume mid-cycle.
- `jump`, `fall`, `climb`, `swim`, `swimidle`, and `sit` are transient poses that stop after fading out and restart from frame 0 when re-triggered.
- Jump holds for stock's window (`0.31` on R15, `0.3` on R6) before falling through to `fall`, regardless of clip length.
- Idle and walk switch at stock's threshold (`0.75 × height scale`) rather than cross-blending.
- R15 uses stock's walk/run blend: walk alone below normalized speed `0.5` at a warped rate, a crossfade to `1.0` at natural rate, then run alone warping above it. R6 uses a single walk track.
- Weights move at the pose transition time when a pose enters or leaves, and at `0.1` while crossfading, matching stock's `AdjustWeight`.
- An `Action`, `Action2`, `Action3`, or `Action4` track takes visual priority over locomotion. AnimBlend leaves action, emote, and tool attack tracks alone.
- `toolnone` is an independent Idle-priority upper-body layer, requiring an equipped `Tool` with a `Handle`. `toolslash` and `toollunge` belong to the tool's own script.
- `Humanoid.PlatformStand`, `PlatformStanding`, `Physics`, `Ragdoll`, `FallingDown`, `GettingUp`, `Flying`, `Dead`, and `None` release AnimBlend's tracks until normal locomotion resumes.

## Custom animations

AnimBlend reads the character's existing `Animate` hierarchy. Replace the `Animation` objects in those folders to use custom locomotion assets:

```text
Character
└── Animate
    ├── idle
    ├── walk
    ├── run
    ├── jump
    ├── fall
    ├── climb
    ├── swim
    ├── swimidle
    ├── sit
    └── toolnone
```

Each folder may contain one or more `Animation` objects. A child `NumberValue` named `Weight` selects how often that variant is chosen; omitted weights default to `1`. Missing `run`, swim, or other optional folders gracefully fall back to compatible poses.

Do not place emotes, attacks, or ability animations in these locomotion folders. Keep them in their own assets and play them from their owning script at Action priority.

## Writing custom animation scripts for server authority

Use these rules for an ability, emote, or custom character controller that plays alongside AnimBlend:

1. Run animation decisions from a shared ModuleScript through `RunService:BindToSimulation` on the server and client.
2. Create the `Animator` on the server.
3. Store animation IDs or `Animation` instances, not `AnimationTrack` handles.
4. Resolve the current `Animator` and live track during each simulation replay. Use `Animator:GetTrackByAnimationId()` before `LoadAnimation()`.
5. Preload required assets before taking control from another animation script.
6. Use `Action` priority or higher for animations that override locomotion.
7. Do not let multiple scripts drive the same animation ID.

Use `Humanoid.PlatformStand` while a temporary physics controller owns the rig. For a full replacement, set the player's `AnimBlendEnabled` attribute from the server and restore it when returning control. Clearing `AnimBlendEnabled` releases AnimBlend's tracks immediately; stock `Animate` only resumes on respawn. `AutoRotate`, `MoveDirection`, `SeatPart`, and `EvaluateStateMachine` are not handoff signals.

Example shared ability driver:

```lua
local RunService = game:GetService("RunService")

local function getOrLoadTrack(animator: Animator, animation: Animation): AnimationTrack
    local track = animator:GetTrackByAnimationId(animation.AnimationId)
    if not track then
        track = animator:LoadAnimation(animation)
    end
    return track
end

local function initialize(character: Model, attackAnimation: Animation)
    local humanoid = character:WaitForChild("Humanoid")

    RunService:BindToSimulation(function()
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            return
        end

        local track = getOrLoadTrack(animator, attackAnimation)
        track.Priority = Enum.AnimationPriority.Action

        -- Read synchronized ability state and drive the live track here.
    end)
end

return initialize
```

Use synchronized inputs and attributes for gameplay state. Keep particles, sound, and UI in render-side code.

AnimBlend keeps jump timing in its own session state, derived from `time()`, and sets no attributes on the character. `AnimBlendServerReady` on the `AnimBlend` folder and `AnimBlendEnabled` on a `Player` are the only attributes it uses.

## Configuration

Edit `src/shared/Config.luau`:

| Key | Default | Meaning |
|---|---|---|
| `EnabledByDefault` | `true` | Initial per-player state when they join |
| `ShowToggleUi` | `true` | A/B toggle button, Studio only |
| `RespectActionPriority` | `true` | Yields locomotion to Action-priority tracks |
| `RigOverrides.R6` / `.R15` | `{}` | Per-rig animation tuning overrides |

The A/B toggle is Studio only. Elsewhere, and whenever `ShowToggleUi` is `false`, neither the button nor its `RemoteEvent` is created. Toggling off respawns the character so stock `Animate` restarts; toggling on takes effect immediately.

Weighted variants are selected automatically from synchronized simulation time.

## Roblox references

- [Server authority model](https://create.roblox.com/docs/projects/server-authority)
- [Server authority techniques](https://create.roblox.com/docs/projects/server-authority/techniques)
- [Animator and AnimationTrack replication](https://create.roblox.com/docs/reference/engine/classes/Animator/LoadAnimation)

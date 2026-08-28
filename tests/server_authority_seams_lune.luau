local Expect = require("./support/expect")
local fs = require("@lune/fs")

local T = Expect.New("ServerAuthoritySeams")
local Driver = fs.readFile("src/shared/AnimBlend.luau")
local Tracks = fs.readFile("src/shared/TrackDriver.luau")
local Binder = fs.readFile("src/shared/CharacterBinder.luau")
local ServerLoader = fs.readFile("src/server/init.server.luau")
local ClientLoader = fs.readFile("src/client/init.client.luau")
local Config = fs.readFile("src/shared/Config.luau")

T:False("toggle UI module is absent", fs.isFile("src/client/ToggleUi.luau"))

T:False(
	"fixed driver does not call lifecycle refresh",
	string.find(Driver, "CharacterBinder.Refresh(Session)", 1, true) ~= nil
)
T:False(
	"fixed driver does not read AutomaticScalingEnabled",
	string.find(Driver, "AutomaticScalingEnabled", 1, true) ~= nil
)
T:False(
	"variant choice does not depend on live track time",
	string.find(Driver, "TrackDriver.VisibleId", 1, true) ~= nil
)
T:True(
	"real runtime uses simulation safe child lookup",
	string.find(Driver, "FindFirstChildWhichIsA", 1, true) ~= nil
)
T:True(
	"real runtime gates animation writes on prediction status",
	string.find(Driver, "CharacterBinder.ShouldDrive(Session)", 1, true) ~= nil
)
T:True(
	"fixed release path uses direct managed lookup",
	string.find(Driver, "TrackDriver.StopKnown", 1, true) ~= nil
)
T:True(
	"fixed track creation only uses prepared animation objects",
	string.find(Tracks, "local Animation = AnimationById[AssetKey(AnimationId)]", 1, true) ~= nil
)
T:True(
	"cached scale damp is checked for live hierarchy membership",
	string.find(Driver, "Damp.Parent ~= nil", 1, true) ~= nil
)
T:False(
	"production and test behavior do not branch on the script global",
	string.find(Driver .. Tracks, "if script", 1, true) ~= nil
)
T:True(
	"swim hysteresis is synchronized on the predicted root",
	string.find(Driver, "AnimBlendSwimActive", 1, true) ~= nil
)
T:False(
	"swim decisions do not read live track state",
	string.find(Driver, "IsSlotVisible", 1, true) ~= nil
)
T:True(
	"server takeover uses an exclusively owned animator",
	string.find(Tracks, "function TrackDriver.TakeOwnership", 1, true) ~= nil
)
T:True(
	"catalog replication is lifecycle data outside predicted attributes",
	string.find(Binder, 'Instance.new("StringValue")', 1, true) ~= nil
)
T:False(
	"catalog replication does not exceed predicted string attribute limits",
	string.find(Binder, "SetAttribute(CatalogValueName", 1, true) ~= nil
)
T:False(
	"server publishes no disable remote",
	string.find(ServerLoader, "RemoteEvent", 1, true) ~= nil
)
T:False("client mounts no toggle UI", string.find(ClientLoader, "Toggle", 1, true) ~= nil)
T:False(
	"client loader does not add a render loop",
	string.find(ClientLoader, "RenderStepped", 1, true) ~= nil
		or string.find(ClientLoader, "BindToRenderStep", 1, true) ~= nil
)
T:False(
	"animation runtime does not own camera input",
	string.find(Driver .. ClientLoader, "CurrentCamera", 1, true) ~= nil
		or string.find(Driver .. ClientLoader, "UserInputService", 1, true) ~= nil
)
T:False(
	"animation runtime does not write character facing",
	string.find(Driver, "AutoRotate", 1, true) ~= nil
		or string.find(Driver, "RootPart.CFrame =", 1, true) ~= nil
		or string.find(Driver, ":PivotTo(", 1, true) ~= nil
)
T:False(
	"configuration exposes no package enable switch",
	string.find(Config, "\n\tEnabled =", 1, true) ~= nil
)
T:False(
	"character ownership has no player opt-out",
	string.find(Binder, "SetPlayerOwning", 1, true) ~= nil
)
T:True(
	"owned animators use the explicit scalable LOD policy",
	string.find(Tracks, "AnimatorPreferLodEnabled", 1, true) ~= nil
)
T:True(
	"server readiness begins closed",
	string.find(Driver, "Root:SetAttribute(ServerReadyAttribute, false)", 1, true) ~= nil
)
T:True(
	"server readiness opens after the simulation binding",
	string.find(Driver, "Root:SetAttribute(ServerReadyAttribute, true)", 1, true) ~= nil
)

return T

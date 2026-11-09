# Roblox Racing Game

A multiplayer oval-track racing game for Roblox: timed races with a countdown, boost pads, drift boosts, power-ups, and a garage with saved coins, upgrades and paint.

## Features

- **Races:** 15 s of free driving, then a 3-2-1-GO countdown with cars frozen on the grid. The first to 3 laps wins, and everyone else gets 30 s to finish. A podium screen shows places, times and coins earned.
- **Lap timing:** an invisible checkpoint on the far straight must be passed for a lap to count. The scoreboard shows Laps, Best Lap, Wins and Coins.
- **Boosts:** glowing boost pads on the track. Hold **Shift** (or the mobile DRIFT button) while steering to drift and charge a boost.
- **Track features:** a chicane, a ramp jump, and a narrow shortcut bridge across the infield. Cars that leave the track are put back where they left it after 1.5 s.
- **Power-ups:** item boxes give a Boost, an Oil Slick or a Shield, used with **E**. Leaders roll fewer boosts and last place rolls more, to keep races close.
- **Garage (G):** coins buy Top Speed, Acceleration and Tire Grip upgrades (3 levels each) and 10 paint colors. Progress is saved with DataStores.

## Controls

| Action | Keyboard | Gamepad | Mobile |
|---|---|---|---|
| Drive / steer | W A S D | Thumbstick / triggers | On-screen thumbstick |
| Drift | Shift | R1 | DRIFT button |
| Use item | E | X | ITEM button |
| Garage | G | – | GARAGE button |

## Project layout

```
src/
  ServerScriptService/
    GameServer.server.luau     -- wires modules together, remotes, shop
    Modules/
      PlayerData.luau          -- DataStore progress + leaderstats
      CarService.luau          -- per-player cars, upgrades/paint, seating, track recovery
      ItemService.luau         -- boost pads, item boxes, Boost / Oil / Shield
      RaceService.luau         -- intermission -> countdown -> race -> results loop
      TrackUtil.luau           -- oval geometry, lap progress, on-track poses
  ReplicatedStorage/
    ShopCatalog.luau           -- prices, colors, stats, rewards, lap count (tweak here)
  StarterPlayerScripts/
    RaceClient.client.luau     -- HUD, countdown, results, garage UI, controls
  Car/
    CarEngine.server.luau      -- goes in Workspace.SimpleCar.VehicleSeat
```

## Required place setup

The scripts expect these objects in the place. They are in the published place, not in this repo:

- `Workspace.RaceTrack` (Folder) with attributes `Radius = 100`, `Width = 40`, `StraightLength = 300`, containing:
  - `FinishLine` (Part, anchored, CanCollide off) across the front straight at z = 0
  - `Checkpoint` (Part, invisible, CanCollide off) across the back straight
  - `BoostPads` (Folder of Parts)
  - Item box Parts tagged `ItemBox`, each with a BillboardGui
- `Workspace.SimpleCar` (Model, PrimaryPart `Chassis`): rear wheels on `HingeConstraint`s named `DriveMotor`; front wheels hinged to chassis attachments named `WheelFLSteerAxle` / `WheelFRSteerAxle`; a `VehicleSeat` containing `CarEngine`. At runtime it is moved to ServerStorage and cloned for each player.
- `ReplicatedStorage.Remotes` (Folder): RemoteEvents `UseItem`, `SetDrift`, `RaceResults`, `Notify` and the RemoteFunction `Shop`.
- `StarterPlayer.EnableMouseLockOption = false`, because Shift is the drift key.

## Syncing with Rojo

```bash
rojo serve
```

Then connect from the Rojo plugin in Studio. `default.project.json` syncs the server scripts, `ShopCatalog` and `RaceClient`. `CarEngine` lives inside the car model, so copy it into `Workspace.SimpleCar.VehicleSeat` by hand.

## Saving progress

DataStores only work in a published place. In Studio, also turn on **Game Settings → Security → Enable Studio Access to API Services**. Without them the game runs normally but progress isn't saved.

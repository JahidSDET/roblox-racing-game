-- GameServer: wires the modules together (leaderboard, cars, items, races, shop).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent:WaitForChild("Modules")
local PlayerData = require(Modules.PlayerData)
local CarService = require(Modules.CarService)
local ItemService = require(Modules.ItemService)
local RaceService = require(Modules.RaceService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local setDrift = remotes:WaitForChild("SetDrift") :: RemoteEvent
local shop = remotes:WaitForChild("Shop") :: RemoteFunction

CarService.init()
ItemService.init()
RaceService.init()

local function onPlayerAdded(player: Player)
	PlayerData.load(player)
	RaceService.setupPlayer(player)
	player.CharacterAdded:Connect(function()
		-- During a race you respawn where you left the track; otherwise on your grid slot
		CarService.spawnCar(player, RaceService.respawnPose(player))
	end)
	if player.Character then
		task.spawn(CarService.spawnCar, player, nil)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	CarService.releasePlayer(player)
	PlayerData.release(player)
end)

-- Drift button (Shift / mobile button) -> car attribute read by CarEngine
setDrift.OnServerEvent:Connect(function(player, on)
	local car = CarService.getCar(player)
	if car and CarService.driverOf(car) == player then
		car:SetAttribute("Drifting", on == true)
	end
end)

-- Garage purchases
shop.OnServerInvoke = function(player, kind, id)
	if type(kind) ~= "string" or type(id) ~= "string" then return false, "Bad request" end
	local ok, msg = PlayerData.purchase(player, kind, id)
	if ok then
		local car = CarService.getCar(player)
		if car then CarService.applyCustomization(car, player) end
	end
	return ok, msg
end

RaceService.run()

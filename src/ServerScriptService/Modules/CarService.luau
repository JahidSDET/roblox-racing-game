-- CarService: one car per player, customization, seating, freezing, teleport/recovery.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))
local PlayerData = require(script.Parent.PlayerData)
local TrackUtil = require(script.Parent.TrackUtil)

local CarService = {}

local template: Model
local baseCFrame: CFrame
local cars: {[Player]: Model} = {}
local slotOf: {[Player]: number} = {}
local safePose: {[Model]: CFrame} = {}
local offTrackTime: {[Model]: number} = {}

local BODY_PARTS = { Chassis = true, Hood = true }

function CarService.init()
	local t = workspace:WaitForChild("SimpleCar") :: Model
	baseCFrame = t:GetPivot()
	t.Parent = ServerStorage
	template = t
end

function CarService.slotCFrame(slot: number): CFrame
	local row = slot // 2
	local col = slot % 2
	local x = TrackUtil.R + (if col == 0 then -8 else 8)
	local z = 18 + row * 12 + col * 6
	return CFrame.new(x, baseCFrame.Position.Y, z) * baseCFrame.Rotation
end

local function claimSlot(player: Player): number
	if slotOf[player] then return slotOf[player] end
	local used = {}
	for _, s in slotOf do used[s] = true end
	local s = 0
	while used[s] do s += 1 end
	slotOf[player] = s
	return s
end

function CarService.getCar(player: Player): Model?
	local car = cars[player]
	if car and car.Parent then return car end
	return nil
end

-- The car model a touching part belongs to (nil if not a car)
function CarService.carFromPart(part: BasePart): Model?
	local m = part:FindFirstAncestorOfClass("Model")
	while m and m:GetAttribute("OwnerUserId") == nil do
		m = m:FindFirstAncestorOfClass("Model")
	end
	return m
end

function CarService.driverOf(car: Model): Player?
	local seat = car:FindFirstChildOfClass("VehicleSeat")
	local hum = seat and seat.Occupant
	return hum and Players:GetPlayerFromCharacter(hum.Parent) or nil
end

-- Apply saved upgrades and paint to a car
function CarService.applyCustomization(car: Model, player: Player)
	local d = PlayerData.get(player)
	if not d then return end
	local S = Catalog.Stats
	local seat = car:FindFirstChildOfClass("VehicleSeat") :: VehicleSeat
	seat.MaxSpeed = S.baseSpeed + d.Speed * S.speedPerLevel
	seat.Torque = S.baseTorque + d.Accel * S.torquePerLevel
	local grip = S.baseGrip + d.Grip * S.gripPerLevel
	car:SetAttribute("Grip", grip)
	for _, w in car:GetChildren() do
		if w:IsA("BasePart") and w.Name:match("^Wheel..$") then
			w.CustomPhysicalProperties = PhysicalProperties.new(1, grip, 0, 50, 50)
		end
	end
	local paint = Catalog.getColor(d.Color) or Catalog.Colors[1]
	for name in BODY_PARTS do
		local p = car:FindFirstChild(name) :: BasePart?
		if p then
			p.Color = paint.color
			p.Material = paint.material or Enum.Material.SmoothPlastic
		end
	end
end

function CarService.removeCar(player: Player)
	local car = cars[player]
	if car then
		safePose[car] = nil
		offTrackTime[car] = nil
		car:Destroy()
		cars[player] = nil
	end
end

function CarService.releasePlayer(player: Player)
	CarService.removeCar(player)
	slotOf[player] = nil
end

function CarService.seatPlayer(player: Player, car: Model)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = car:FindFirstChildOfClass("VehicleSeat")
	if not (character and humanoid and seat) then return end
	if not character:FindFirstChild("HumanoidRootPart") then
		character:WaitForChild("HumanoidRootPart", 5)
	end
	humanoid.Sit = false
	task.wait(0.2)
	if not car.Parent or humanoid.Health <= 0 then return end
	-- Move onto the seat first, otherwise Sit() drags the car to the character
	character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	task.wait(0.1)
	if car.Parent then seat:Sit(humanoid) end
end

-- Spawns (or respawns) the player's car at cf (default: their grid slot) and seats them. Yields.
function CarService.spawnCar(player: Player, cf: CFrame?): Model
	CarService.removeCar(player)
	local car = template:Clone()
	car.Name = "SimpleCar_" .. player.Name
	car:SetAttribute("OwnerUserId", player.UserId)
	CarService.applyCustomization(car, player)
	car:PivotTo(cf or CarService.slotCFrame(claimSlot(player)))
	car.Parent = workspace
	cars[player] = car
	CarService.seatPlayer(player, car)
	return car
end

function CarService.setFrozen(car: Model, frozen: boolean)
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	if not chassis then return end
	chassis.Anchored = frozen
	if not frozen then
		local driver = CarService.driverOf(car)
		if chassis:CanSetNetworkOwnership() then chassis:SetNetworkOwner(driver) end
	end
end

-- Server-side teleport of a (possibly client-owned) car
function CarService.teleport(car: Model, cf: CFrame)
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	if not chassis then return end
	if chassis:CanSetNetworkOwnership() then chassis:SetNetworkOwner(nil) end
	car:PivotTo(cf)
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	task.delay(0.3, function()
		if car.Parent and chassis:CanSetNetworkOwnership() then
			chassis:SetNetworkOwner(CarService.driverOf(car))
		end
	end)
end

-- Where to put a player's car back on the track (last safe on-track pose)
function CarService.lastSafePose(player: Player): CFrame?
	local car = cars[player]
	return car and safePose[car] or nil
end

-- Track watcher: remember last safe pose; recover cars that leave the track (infield, outside, fell)
local OFF_TRACK_LIMIT = 1.5
task.spawn(function()
	while true do
		local dt = task.wait(0.25)
		for _, car in cars do
			local chassis = car.Parent and car:FindFirstChild("Chassis") :: BasePart?
			if chassis and not chassis.Anchored then
				local pos = chassis.Position
				local lat = math.abs(TrackUtil.lateral(pos))
				local onTrackSurface = lat <= TrackUtil.W / 2 - 2 and pos.Y > 0.3 and pos.Y < 2.6
				local offTrack = (lat > TrackUtil.W / 2 + 2 and pos.Y < 3) or pos.Y < -20
				if onTrackSurface and chassis.CFrame.UpVector.Y > 0.8 then
					safePose[car] = TrackUtil.poseAt(pos, true)
				end
				if offTrack then
					offTrackTime[car] = (offTrackTime[car] or 0) + dt
					if offTrackTime[car] >= OFF_TRACK_LIMIT then
						offTrackTime[car] = 0
						CarService.teleport(car, safePose[car] or TrackUtil.poseAt(pos))
					end
				else
					offTrackTime[car] = 0
				end
			end
		end
	end
end)

return CarService

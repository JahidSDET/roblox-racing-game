-- CarEngine: VehicleSeat.Throttle / Steer -> rear hinge motors + front steering,
-- plus boost (BoostUntil), drift charge (Drifting) and spin-outs (SpinUntil).
-- Lives at Workspace.SimpleCar.VehicleSeat.CarEngine (the car is cloned per player).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local seat = script.Parent :: VehicleSeat
local car = seat.Parent :: Model
local chassis = car:WaitForChild("Chassis") :: BasePart

local WHEEL_RADIUS = 0.75
local TORQUE_SCALE = 40       -- MotorMaxTorque per drive wheel = seat.Torque * TORQUE_SCALE
local COAST_TORQUE = 250      -- engine braking when no throttle
local BRAKE_TORQUE = 500      -- while spinning out
local MAX_STEER_DEG = 32
local HIGH_SPEED_STEER = 0.45 -- fraction of steer angle kept at top speed
local BOOST_SPEED_MULT = 1.45
local BOOST_TORQUE_MULT = 3
local DRIFT_GRIP = 0.5        -- rear tire friction while drifting
local DRIFT_STEER_MULT = 1.35
local DRIFT_MIN_SPEED = 25
local DRIFT_MAX_CHARGE = 2    -- seconds of drifting for a full boost
local DRIFT_MIN_CHARGE = 0.5
local DRIFT_BOOST_PER_SEC = 0.9

local motors: {HingeConstraint} = {}
local rearWheels: {BasePart} = {}
for _, d in car:GetDescendants() do
	if d:IsA("HingeConstraint") and d.Name == "DriveMotor" then
		table.insert(motors, d)
		local wheel = d.Attachment1 and d.Attachment1.Parent
		if wheel and wheel:IsA("BasePart") then table.insert(rearWheels, wheel) end
	end
end

type SteerAxle = { att: Attachment, base: CFrame }
local steerAxles: {SteerAxle} = {}
for _, a in chassis:GetChildren() do
	if a:IsA("Attachment") and a.Name:match("SteerAxle$") then
		table.insert(steerAxles, { att = a, base = a.CFrame })
	end
end

local function now() return workspace:GetServerTimeNow() end

local currentSteer = 0
local driftCharge = 0
local currentRearGrip = -1
local lastChargeSent = -1

local function setRearGrip(f: number)
	if math.abs(f - currentRearGrip) < 0.01 then return end
	currentRearGrip = f
	for _, w in rearWheels do
		w.CustomPhysicalProperties = PhysicalProperties.new(1, f, 0, 50, 50)
	end
end

local function setMotors(angVel: number, torque: number)
	for _, m in motors do
		m.AngularVelocity = angVel
		m.MotorMaxTorque = torque
	end
end

seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local hum = seat.Occupant
	local player = hum and Players:GetPlayerFromCharacter(hum.Parent)
	if not chassis.Anchored and chassis:CanSetNetworkOwnership() then
		chassis:SetNetworkOwner(player)
	end
	if not hum then
		seat.Throttle = 0
		seat.Steer = 0
		car:SetAttribute("Drifting", false)
	end
end)

local flippedFor = 0
RunService.Heartbeat:Connect(function(dt)
	if not chassis.Parent then return end
	local t = now()
	local speed = chassis.AssemblyLinearVelocity.Magnitude
	local boosting = (car:GetAttribute("BoostUntil") or 0) > t
	local spinning = (car:GetAttribute("SpinUntil") or 0) > t
	local occupied = seat.Occupant ~= nil

	-- Engine
	local maxSpeed = seat.MaxSpeed * (if boosting then BOOST_SPEED_MULT else 1)
	local torque = seat.Torque * TORQUE_SCALE * (if boosting then BOOST_TORQUE_MULT else 1)
	if spinning then
		setMotors(0, BRAKE_TORQUE)
	elseif boosting and occupied and seat.Throttle >= 0 then
		setMotors(-maxSpeed / WHEEL_RADIUS, torque) -- negative = forward (-Z)
	elseif seat.Throttle ~= 0 then
		setMotors(-seat.Throttle * maxSpeed / WHEEL_RADIUS, torque)
	else
		setMotors(0, COAST_TORQUE)
	end

	-- Drift: low rear grip while held at speed; steering through it charges a boost
	local wantDrift = car:GetAttribute("Drifting") == true and occupied and not spinning
	local drifting = wantDrift and speed > DRIFT_MIN_SPEED
	if drifting and seat.Steer ~= 0 then
		driftCharge = math.min(DRIFT_MAX_CHARGE, driftCharge + dt)
	elseif not drifting and driftCharge > 0 then
		if driftCharge >= DRIFT_MIN_CHARGE and not spinning then
			local untilT = math.max(car:GetAttribute("BoostUntil") or 0, t + driftCharge * DRIFT_BOOST_PER_SEC)
			car:SetAttribute("BoostUntil", untilT)
		end
		driftCharge = 0
	end
	setRearGrip(if drifting then DRIFT_GRIP else (car:GetAttribute("Grip") or 1.6))
	local chargeFrac = math.floor(driftCharge / DRIFT_MAX_CHARGE * 20) / 20
	if chargeFrac ~= lastChargeSent then
		lastChargeSent = chargeFrac
		car:SetAttribute("DriftCharge", chargeFrac)
	end

	-- Steering (speed-sensitive; wobbles while spinning out)
	local speedFactor = 1 - (1 - HIGH_SPEED_STEER) * math.clamp(speed / seat.MaxSpeed, 0, 1)
	local target = -seat.Steer * MAX_STEER_DEG * speedFactor * (if drifting then DRIFT_STEER_MULT else 1)
	if spinning then
		target = MAX_STEER_DEG * math.sin(t * 20)
	end
	local maxStep = seat.TurnSpeed * 60 * dt
	currentSteer += math.clamp(target - currentSteer, -maxStep, maxStep)
	for _, s in steerAxles do
		s.att.CFrame = s.base * CFrame.Angles(0, math.rad(currentSteer), 0)
	end

	-- Auto-unflip
	if chassis.CFrame.UpVector.Y < 0.3 and speed < 8 then
		flippedFor += dt
		if flippedFor > 2 then
			flippedFor = 0
			local look = chassis.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
			local pos = chassis.Position + Vector3.new(0, 4, 0)
			car:PivotTo(CFrame.lookAt(pos, pos + look.Unit))
			for _, p in car:GetDescendants() do
				if p:IsA("BasePart") then
					p.AssemblyLinearVelocity = Vector3.zero
					p.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end
	else
		flippedFor = 0
	end
end)

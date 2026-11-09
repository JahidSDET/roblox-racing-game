-- ItemService: boost pads, item boxes and the items (Boost, Oil Slick, Shield).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarService = require(script.Parent.CarService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local notify = remotes:WaitForChild("Notify") :: RemoteEvent

local ItemService = {}

local PAD_BOOST = 1.5
local ITEM_BOOST = 2.5
local SHIELD_TIME = 6
local SPIN_TIME = 1.3
local OIL_LIFETIME = 20
local BOX_RESPAWN = 4

local function now() return workspace:GetServerTimeNow() end

function ItemService.boost(car: Model, seconds: number)
	local untilT = math.max(car:GetAttribute("BoostUntil") or 0, now() + seconds)
	car:SetAttribute("BoostUntil", untilT)
end

function ItemService.shield(car: Model)
	car:SetAttribute("ShieldUntil", now() + SHIELD_TIME)
	local old = car:FindFirstChild("ShieldGlow")
	if old then old:Destroy() end
	local h = Instance.new("Highlight")
	h.Name = "ShieldGlow"
	h.FillColor = Color3.fromRGB(80, 200, 255)
	h.FillTransparency = 0.6
	h.OutlineColor = Color3.fromRGB(180, 240, 255)
	h.Parent = car
	task.delay(SHIELD_TIME, function()
		if h.Parent then h:Destroy() end
	end)
end

-- Returns true if the car spun out (false if shielded)
function ItemService.spinOut(car: Model): boolean
	if (car:GetAttribute("ShieldUntil") or 0) > now() then
		return false
	end
	car:SetAttribute("SpinUntil", now() + SPIN_TIME)
	car:SetAttribute("BoostUntil", 0)
	return true
end

local function dropOil(car: Model, owner: Player)
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	if not chassis then return end
	local back = chassis.Position - chassis.CFrame.LookVector * 9
	local oil = Instance.new("Part")
	oil.Name = "OilSlick"
	oil.Shape = Enum.PartType.Cylinder
	oil.Size = Vector3.new(0.4, 8, 8)
	oil.CFrame = CFrame.new(back.X, 0.1, back.Z) * CFrame.Angles(0, 0, math.pi / 2)
	oil.Anchored = true
	oil.CanCollide = false
	oil.CastShadow = false
	oil.Color = Color3.fromRGB(15, 15, 20)
	oil.Material = Enum.Material.Glass
	oil.Reflectance = 0.3
	oil.Parent = workspace
	local dropped = now()
	oil.Touched:Connect(function(hit)
		if not oil.Parent then return end
		local victim = CarService.carFromPart(hit)
		if not victim then return end
		if victim == car and now() - dropped < 2 then return end -- don't hit yourself right away
		oil:Destroy()
		local spun = ItemService.spinOut(victim)
		local driver = CarService.driverOf(victim)
		if driver then
			notify:FireClient(driver, if spun then "You hit an oil slick!" else "Your shield blocked an oil slick!")
		end
		if spun and driver and driver ~= owner then
			notify:FireClient(owner, driver.DisplayName .. " slipped on your oil!")
		end
	end)
	task.delay(OIL_LIFETIME, function()
		if oil.Parent then oil:Destroy() end
	end)
end

-- Leaders get fewer boosts, players further back get more (catch-up)
local function rollItem(player: Player): string
	local pos = player:GetAttribute("RacePos") or 1
	local count = player:GetAttribute("RaceCount") or 1
	local weights
	if count > 1 and pos == 1 then
		weights = { Boost = 15, Oil = 55, Shield = 30 }
	elseif count > 1 and pos == count then
		weights = { Boost = 65, Oil = 15, Shield = 20 }
	else
		weights = { Boost = 40, Oil = 35, Shield = 25 }
	end
	local total = 0
	for _, w in weights do total += w end
	local r = math.random() * total
	for name, w in weights do
		r -= w
		if r <= 0 then return name end
	end
	return "Boost"
end

local function useItem(player: Player)
	local item = player:GetAttribute("Item")
	if not item or item == "" then return end
	local car = CarService.getCar(player)
	if not car or CarService.driverOf(car) ~= player then return end
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	if chassis and chassis.Anchored then return end -- frozen during countdown
	player:SetAttribute("Item", "")
	if item == "Boost" then
		ItemService.boost(car, ITEM_BOOST)
	elseif item == "Oil" then
		dropOil(car, player)
	elseif item == "Shield" then
		ItemService.shield(car)
	end
end

local function setupBox(box: BasePart)
	local active = true
	local gui = box:FindFirstChildWhichIsA("BillboardGui")
	box.Touched:Connect(function(hit)
		if not active then return end
		local car = CarService.carFromPart(hit)
		local player = car and CarService.driverOf(car)
		if not player then return end
		active = false
		box.Transparency = 1
		if gui then gui.Enabled = false end
		local current = player:GetAttribute("Item")
		if not current or current == "" then
			player:SetAttribute("Item", rollItem(player))
		end
		task.delay(BOX_RESPAWN, function()
			active = true
			box.Transparency = 0.25
			if gui then gui.Enabled = true end
		end)
	end)
end

function ItemService.init()
	local raceTrack = workspace:WaitForChild("RaceTrack")
	for _, pad in raceTrack:WaitForChild("BoostPads"):GetChildren() do
		if pad:IsA("BasePart") then
			pad.Touched:Connect(function(hit)
				local car = CarService.carFromPart(hit)
				if car and CarService.driverOf(car) then
					ItemService.boost(car, PAD_BOOST)
				end
			end)
		end
	end
	for _, box in CollectionService:GetTagged("ItemBox") do
		if box:IsA("BasePart") and box:IsDescendantOf(workspace) then
			setupBox(box)
		end
	end
	local useRemote = remotes:WaitForChild("UseItem") :: RemoteEvent
	useRemote.OnServerEvent:Connect(useItem)
	Players.PlayerAdded:Connect(function(p) p:SetAttribute("Item", "") end)
	for _, p in Players:GetPlayers() do p:SetAttribute("Item", "") end
end

function ItemService.clearItems()
	for _, p in Players:GetPlayers() do p:SetAttribute("Item", "") end
	for _, o in workspace:GetChildren() do
		if o.Name == "OilSlick" then o:Destroy() end
	end
end

return ItemService

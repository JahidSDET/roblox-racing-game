-- ShopCatalog: shared between server (prices, effects) and client (garage UI).
local Catalog = {}

Catalog.RaceLaps = 3

Catalog.Upgrades = {
	{ id = "Speed", name = "Top Speed", desc = "+6 top speed per level", costs = { 100, 200, 350 } },
	{ id = "Accel", name = "Acceleration", desc = "+6 engine torque per level", costs = { 100, 200, 350 } },
	{ id = "Grip", name = "Tire Grip", desc = "+0.25 tire grip per level", costs = { 100, 200, 350 } },
}

Catalog.Stats = {
	baseSpeed = 70,
	baseTorque = 25,
	baseGrip = 1.6,
	speedPerLevel = 6,
	torquePerLevel = 6,
	gripPerLevel = 0.25,
}

Catalog.Colors = {
	{ id = "Blue", color = Color3.fromRGB(13, 105, 172), cost = 0 },
	{ id = "Red", color = Color3.fromRGB(196, 40, 28), cost = 75 },
	{ id = "Green", color = Color3.fromRGB(40, 160, 60), cost = 75 },
	{ id = "Yellow", color = Color3.fromRGB(245, 205, 48), cost = 75 },
	{ id = "Orange", color = Color3.fromRGB(230, 120, 20), cost = 75 },
	{ id = "Purple", color = Color3.fromRGB(120, 50, 180), cost = 75 },
	{ id = "Pink", color = Color3.fromRGB(255, 100, 180), cost = 75 },
	{ id = "Black", color = Color3.fromRGB(25, 25, 25), cost = 75 },
	{ id = "White", color = Color3.fromRGB(240, 240, 240), cost = 75 },
	{ id = "Gold", color = Color3.fromRGB(212, 175, 55), cost = 400, material = Enum.Material.Foil },
}

Catalog.Rewards = {
	place = { 50, 35, 25 }, -- 1st / 2nd / 3rd
	finish = 15,           -- finished but 4th or lower
	participate = 5,       -- raced but did not finish
	perLap = 5,
	personalBest = 10,
}

function Catalog.getUpgrade(id: string)
	for _, u in Catalog.Upgrades do
		if u.id == id then return u end
	end
	return nil
end

function Catalog.getColor(id: string)
	for _, c in Catalog.Colors do
		if c.id == id then return c end
	end
	return nil
end

return Catalog

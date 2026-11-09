-- PlayerData: saved progress (coins, wins, best lap, upgrades, colors) + leaderstats.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))

local STORE_NAME = "SpeedwayRacers_v1"
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then store = result else warn("[PlayerData] DataStore unavailable, progress won't save:", result) end
end

local PlayerData = {}
local cache: {[Player]: any} = {}
local loaded: {[Player]: boolean} = {}

local function defaults()
	return {
		Coins = 0,
		Wins = 0,
		BestLap = 0, -- 0 = none yet
		Speed = 0,
		Accel = 0,
		Grip = 0,
		Color = "Blue",
		OwnedColors = { Blue = true },
	}
end

local function formatTime(t: number): string
	if t <= 0 then return "--" end
	return string.format("%d:%05.2f", math.floor(t / 60), t % 60)
end
PlayerData.formatTime = formatTime

-- Push data to leaderstats + player attributes (the client UI reads these)
local function publish(player: Player)
	local d = cache[player]
	if not d then return end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Coins.Value = d.Coins
		ls.Wins.Value = d.Wins
		ls["Best Lap"].Value = formatTime(d.BestLap)
	end
	player:SetAttribute("Coins", d.Coins)
	player:SetAttribute("SpeedLvl", d.Speed)
	player:SetAttribute("AccelLvl", d.Accel)
	player:SetAttribute("GripLvl", d.Grip)
	player:SetAttribute("CarColor", d.Color)
	player:SetAttribute("OwnedColors", HttpService:JSONEncode(d.OwnedColors))
end

function PlayerData.load(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local laps = Instance.new("IntValue"); laps.Name = "Laps"; laps.Parent = ls
	local best = Instance.new("StringValue"); best.Name = "Best Lap"; best.Value = "--"; best.Parent = ls
	local wins = Instance.new("IntValue"); wins.Name = "Wins"; wins.Parent = ls
	local coins = Instance.new("IntValue"); coins.Name = "Coins"; coins.Parent = ls
	ls.Parent = player

	local data = defaults()
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync("player_" .. player.UserId)
		end)
		if ok and type(saved) == "table" then
			for k, v in saved do data[k] = v end
			data.OwnedColors = data.OwnedColors or {}
			data.OwnedColors.Blue = true
		elseif not ok then
			warn("[PlayerData] load failed for", player.Name, saved)
		end
	end
	cache[player] = data
	loaded[player] = true
	publish(player)
end

function PlayerData.get(player: Player)
	return cache[player]
end

function PlayerData.save(player: Player)
	local d = cache[player]
	if not (store and d and loaded[player]) then return end
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, d)
	end)
	if not ok then warn("[PlayerData] save failed for", player.Name, err) end
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	cache[player] = nil
	loaded[player] = nil
end

function PlayerData.addCoins(player: Player, amount: number)
	local d = cache[player]
	if not d then return end
	d.Coins += amount
	publish(player)
end

function PlayerData.addWin(player: Player)
	local d = cache[player]
	if not d then return end
	d.Wins += 1
	publish(player)
end

-- Returns true if this is a new personal best
function PlayerData.submitLap(player: Player, lapTime: number): boolean
	local d = cache[player]
	if not d then return false end
	if d.BestLap <= 0 or lapTime < d.BestLap then
		local hadOne = d.BestLap > 0
		d.BestLap = lapTime
		publish(player)
		return hadOne
	end
	return false
end

-- kind: "Upgrade" | "Color". Returns (ok, message)
function PlayerData.purchase(player: Player, kind: string, id: string): (boolean, string)
	local d = cache[player]
	if not d then return false, "Data not loaded yet" end
	if kind == "Upgrade" then
		local u = Catalog.getUpgrade(id)
		if not u then return false, "Unknown upgrade" end
		local lvl = d[id] or 0
		if lvl >= #u.costs then return false, u.name .. " is maxed out" end
		local cost = u.costs[lvl + 1]
		if d.Coins < cost then return false, "Not enough coins" end
		d.Coins -= cost
		d[id] = lvl + 1
		publish(player)
		return true, u.name .. " upgraded to level " .. (lvl + 1)
	elseif kind == "Color" then
		local c = Catalog.getColor(id)
		if not c then return false, "Unknown color" end
		if not d.OwnedColors[id] then
			if d.Coins < c.cost then return false, "Not enough coins" end
			d.Coins -= c.cost
			d.OwnedColors[id] = true
		end
		d.Color = id
		publish(player)
		return true, id .. " paint equipped"
	end
	return false, "Unknown purchase"
end

-- Autosave + save on shutdown
task.spawn(function()
	while true do
		task.wait(120)
		for _, p in Players:GetPlayers() do
			PlayerData.save(p)
		end
	end
end)

game:BindToClose(function()
	for _, p in Players:GetPlayers() do
		PlayerData.save(p)
	end
end)

return PlayerData

-- RaceService: intermission -> countdown -> race (first to N laps) -> results -> repeat.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))
local PlayerData = require(script.Parent.PlayerData)
local CarService = require(script.Parent.CarService)
local ItemService = require(script.Parent.ItemService)
local TrackUtil = require(script.Parent.TrackUtil)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local resultsRemote = remotes:WaitForChild("RaceResults") :: RemoteEvent
local notify = remotes:WaitForChild("Notify") :: RemoteEvent

local LAPS = Catalog.RaceLaps
local INTERMISSION = 15
local FINISH_GRACE = 30   -- seconds others get after the winner finishes
local MAX_RACE_TIME = 360
local RESULTS_TIME = 8
local CROSS_DEBOUNCE = 2

local RaceService = {}

type Racer = {
	laps: number,
	started: boolean,
	passedCheckpoint: boolean,
	lapStart: number,
	lastCross: number,
	finished: boolean,
	finishTime: number,
	progress: number,
}

local state = "Intermission"
local racers: {[Player]: Racer} = {}
local finishOrder: {Player} = {}
local raceStart = 0
local firstFinishAt: number? = nil

local function setState(s: string)
	state = s
	ReplicatedStorage:SetAttribute("RaceState", s)
end
local function setMessage(m: string)
	ReplicatedStorage:SetAttribute("RaceMessage", m)
end
local function setCountdown(c: string)
	ReplicatedStorage:SetAttribute("Countdown", c)
end

function RaceService.getState() return state end

local function clearPlayerRaceAttrs(p: Player)
	p:SetAttribute("InRace", false)
	p:SetAttribute("RaceLap", 0)
	p:SetAttribute("RacePos", 0)
	p:SetAttribute("RaceCount", 0)
	p:SetAttribute("RaceFinished", false)
	local ls = p:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Laps") then ls.Laps.Value = 0 end
end

----------------------------------------------------------------- lap detection
local function onFinishTouched(hit: BasePart)
	if state ~= "Racing" then return end
	local car = CarService.carFromPart(hit)
	local player = car and CarService.driverOf(car)
	local r = player and racers[player]
	if not r or r.finished then return end
	local t = os.clock()
	if t - r.lastCross < CROSS_DEBOUNCE then return end
	r.lastCross = t

	if not r.started then
		r.started = true -- first crossing from the grid
		return
	end
	if not r.passedCheckpoint then return end -- skipped part of the lap

	r.passedCheckpoint = false
	r.laps += 1
	local lapTime = t - r.lapStart
	r.lapStart = t
	local ls = player:FindFirstChild("leaderstats")
	if ls then ls.Laps.Value = r.laps end
	if PlayerData.submitLap(player, lapTime) then
		PlayerData.addCoins(player, Catalog.Rewards.personalBest)
		notify:FireClient(player, "New personal best lap: " .. PlayerData.formatTime(lapTime) .. "  (+" .. Catalog.Rewards.personalBest .. " coins)")
	else
		notify:FireClient(player, "Lap " .. r.laps .. ": " .. PlayerData.formatTime(lapTime))
	end

	if r.laps >= LAPS then
		r.finished = true
		r.finishTime = t - raceStart
		table.insert(finishOrder, player)
		player:SetAttribute("RaceFinished", true)
		player:SetAttribute("RaceLap", LAPS)
		if #finishOrder == 1 then
			firstFinishAt = t
			setMessage(player.DisplayName .. " wins! " .. FINISH_GRACE .. "s for everyone else to finish")
		end
	else
		player:SetAttribute("RaceLap", r.laps + 1)
		if r.laps == LAPS - 1 then
			notify:FireClient(player, "FINAL LAP!")
		end
	end
end

local function onCheckpointTouched(hit: BasePart)
	if state ~= "Racing" then return end
	local car = CarService.carFromPart(hit)
	local player = car and CarService.driverOf(car)
	local r = player and racers[player]
	if r and r.started then
		r.passedCheckpoint = true
	end
end

----------------------------------------------------------------- positions
local function updatePositions()
	local list = {}
	for p, r in racers do
		if p.Parent then
			local car = CarService.getCar(p)
			local chassis = car and car:FindFirstChild("Chassis") :: BasePart?
			if chassis then
				local s = TrackUtil.locate(chassis.Position)
				if not r.started then s -= TrackUtil.TOTAL end
				-- Don't count the far half of the lap until the checkpoint is passed
				if r.started and not r.passedCheckpoint and s > TrackUtil.TOTAL * 0.6 then s = 0 end
				r.progress = s
			end
			table.insert(list, p)
		end
	end
	local function score(p: Player): number
		local r = racers[p]
		if r.finished then
			return 1e9 - (table.find(finishOrder, p) or 0)
		end
		return r.laps * TrackUtil.TOTAL + r.progress
	end
	table.sort(list, function(a, b) return score(a) > score(b) end)
	for i, p in list do
		p:SetAttribute("RacePos", i)
		p:SetAttribute("RaceCount", #list)
	end
	return list
end

----------------------------------------------------------------- race phases
local function runIntermission()
	setState("Intermission")
	setCountdown("")
	local t = INTERMISSION
	while t > 0 do
		if #Players:GetPlayers() == 0 then
			setMessage("Waiting for players...")
			t = INTERMISSION
		else
			setMessage("Free drive - next race in " .. t .. "s")
			t -= 1
		end
		task.wait(1)
	end
end

local function runCountdown(): boolean
	setState("Countdown")
	setMessage("Get ready!")
	ItemService.clearItems()
	racers = {}
	finishOrder = {}
	firstFinishAt = nil

	local entrants = {}
	for _, p in Players:GetPlayers() do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then table.insert(entrants, p) end
	end
	if #entrants == 0 then return false end

	for i, p in entrants do
		racers[p] = { laps = 0, started = false, passedCheckpoint = false, lapStart = 0, lastCross = 0,
			finished = false, finishTime = 0, progress = 0 }
		clearPlayerRaceAttrs(p)
		p:SetAttribute("InRace", true)
		p:SetAttribute("RaceLap", 1)
		task.spawn(function()
			local car = CarService.spawnCar(p, CarService.slotCFrame(i - 1))
			if state == "Countdown" then CarService.setFrozen(car, true) end
		end)
	end
	task.wait(1.5)
	for p in racers do
		local car = CarService.getCar(p)
		if car then CarService.setFrozen(car, true) end
	end
	updatePositions()
	for _, n in { "3", "2", "1" } do
		setCountdown(n)
		task.wait(1)
	end
	setCountdown("GO!")
	raceStart = os.clock()
	for p, r in racers do
		r.lapStart = raceStart
		local car = CarService.getCar(p)
		if car then CarService.setFrozen(car, false) end
	end
	task.delay(1.2, function()
		if ReplicatedStorage:GetAttribute("Countdown") == "GO!" then setCountdown("") end
	end)
	return true
end

local function runRace()
	setState("Racing")
	setMessage("First to " .. LAPS .. " laps wins!")
	while true do
		task.wait(0.25)
		local list = updatePositions()
		local t = os.clock()
		local allDone = true
		for _, p in list do
			if not racers[p].finished then allDone = false end
		end
		if #list == 0 or allDone then break end
		if firstFinishAt then
			local left = math.ceil(FINISH_GRACE - (t - firstFinishAt))
			if left <= 0 then break end
			setMessage(finishOrder[1].DisplayName .. " wins! Race ends in " .. left .. "s")
		end
		if t - raceStart > MAX_RACE_TIME then break end
	end
end

local function runResults()
	setState("Results")
	setMessage("Race over!")
	local list = updatePositions()
	local R = Catalog.Rewards
	local results = {}
	for place, p in list do
		local r = racers[p]
		local coins = r.laps * R.perLap
		if r.finished then
			coins += R.place[place] or R.finish
		else
			coins += R.participate
		end
		PlayerData.addCoins(p, coins)
		if place == 1 and r.finished then PlayerData.addWin(p) end
		table.insert(results, {
			name = p.DisplayName,
			userId = p.UserId,
			place = place,
			finished = r.finished,
			time = if r.finished then PlayerData.formatTime(r.finishTime) else (r.laps .. "/" .. LAPS .. " laps"),
			coins = coins,
		})
	end
	resultsRemote:FireAllClients(results)
	task.wait(RESULTS_TIME)
	for p in racers do
		if p.Parent then clearPlayerRaceAttrs(p) end
	end
	racers = {}
end

----------------------------------------------------------------- public
function RaceService.init()
	local raceTrack = workspace:WaitForChild("RaceTrack")
	local finishLine = raceTrack:WaitForChild("FinishLine") :: BasePart
	finishLine.Touched:Connect(onFinishTouched)
	local checkpoint = raceTrack:WaitForChild("Checkpoint") :: BasePart
	checkpoint.Touched:Connect(onCheckpointTouched)
	ReplicatedStorage:SetAttribute("RaceLaps", LAPS)
	Players.PlayerRemoving:Connect(function(p)
		racers[p] = nil
	end)
end

-- Where a player's car should respawn when their character respawns
function RaceService.respawnPose(player: Player): CFrame?
	if (state == "Racing" or state == "Countdown") and racers[player] then
		return CarService.lastSafePose(player)
	end
	return nil -- grid slot
end

function RaceService.run()
	while true do
		runIntermission()
		if runCountdown() then
			runRace()
			runResults()
		end
	end
end

function RaceService.setupPlayer(p: Player)
	clearPlayerRaceAttrs(p)
end

return RaceService

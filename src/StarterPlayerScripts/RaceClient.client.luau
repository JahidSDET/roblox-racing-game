-- RaceClient: race HUD, countdown, results, garage shop, drift/item controls, item box spin.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Catalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local useItemRemote = remotes:WaitForChild("UseItem") :: RemoteEvent
local setDriftRemote = remotes:WaitForChild("SetDrift") :: RemoteEvent
local resultsRemote = remotes:WaitForChild("RaceResults") :: RemoteEvent
local notifyRemote = remotes:WaitForChild("Notify") :: RemoteEvent
local shopRemote = remotes:WaitForChild("Shop") :: RemoteFunction

------------------------------------------------------------------ UI helpers
local FONT = Enum.Font.GothamBold
local DARK = Color3.fromRGB(20, 22, 30)
local ACCENT = Color3.fromRGB(255, 170, 0)

local function make(class: string, props: {[string]: any}, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in props do (o :: any)[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(parent: Instance, r: number?)
	make("UICorner", { CornerRadius = UDim.new(0, r or 10) }, parent)
end
local function panel(props: {[string]: any}, parent: Instance)
	local f = make("Frame", props, parent)
	if props.BackgroundColor3 == nil then f.BackgroundColor3 = DARK end
	if props.BackgroundTransparency == nil then f.BackgroundTransparency = 0.25 end
	f.BorderSizePixel = 0
	corner(f)
	return f
end
local function text(props: {[string]: any}, parent: Instance)
	local t = make("TextLabel", props, parent)
	t.BackgroundTransparency = 1
	if props.Font == nil then t.Font = FONT end
	if props.TextColor3 == nil then t.TextColor3 = Color3.new(1, 1, 1) end
	if props.TextScaled == nil then t.TextScaled = true end
	return t
end
local function button(props: {[string]: any}, parent: Instance)
	local b = make("TextButton", props, parent)
	if props.Font == nil then b.Font = FONT end
	if props.TextColor3 == nil then b.TextColor3 = Color3.new(1, 1, 1) end
	if props.BackgroundColor3 == nil then b.BackgroundColor3 = ACCENT end
	b.TextScaled = true
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	corner(b, 8)
	return b
end

local gui = make("ScreenGui", { Name = "RaceHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

------------------------------------------------------------------ status + countdown
local statusFrame = panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(460, 40) }, gui)
local statusLabel = text({ Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 4), Text = "" }, statusFrame)

local countdownLabel = text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(400, 200),
	Text = "", Font = Enum.Font.GothamBlack, TextColor3 = ACCENT, TextStrokeTransparency = 0 }, gui)

local toast = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(520, 34),
	Text = "", TextStrokeTransparency = 0.2, TextTransparency = 1, TextStrokeColor3 = Color3.new(0, 0, 0) }, gui)

------------------------------------------------------------------ race panel (lap / position)
local racePanel = panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 60), Size = UDim2.fromOffset(170, 90), Visible = false }, gui)
local lapLabel = text({ Size = UDim2.new(1, -16, 0.5, -4), Position = UDim2.fromOffset(8, 4), Text = "LAP 1/3", TextXAlignment = Enum.TextXAlignment.Left }, racePanel)
local posLabel = text({ Size = UDim2.new(1, -16, 0.5, -4), Position = UDim2.new(0, 8, 0.5, 0), Text = "POS 1/1", TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left }, racePanel)

------------------------------------------------------------------ item slot + drift meter
local itemFrame = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(90, 90) }, gui)
local itemIcon = text({ Size = UDim2.new(1, -10, 0.7, 0), Position = UDim2.fromOffset(5, 4), Text = "" }, itemFrame)
local itemHint = text({ Size = UDim2.new(1, -10, 0.25, 0), Position = UDim2.new(0, 5, 0.73, 0), Text = "no item", TextColor3 = Color3.fromRGB(180, 180, 190) }, itemFrame)

local driftBack = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -116), Size = UDim2.fromOffset(220, 14), BackgroundTransparency = 0.4 }, gui)
local driftFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 120, 30), BorderSizePixel = 0 }, driftBack)
corner(driftFill)
local driftText = text({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromOffset(260, 18), Text = "Hold SHIFT + steer to drift", TextColor3 = Color3.fromRGB(220, 220, 230) }, driftBack)
local boostLabel = text({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.fromOffset(240, 40), Text = "BOOST!",
	Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(0, 220, 255), TextStrokeTransparency = 0, Visible = false }, gui)

local ITEM_ICONS = { Boost = "⚡", Oil = "🛢️", Shield = "🛡️" }
local ITEM_NAMES = { Boost = "Boost", Oil = "Oil Slick", Shield = "Shield" }
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function refreshItem()
	local item = player:GetAttribute("Item")
	if item and item ~= "" then
		itemIcon.Text = ITEM_ICONS[item] or "?"
		itemHint.Text = (ITEM_NAMES[item] or item) .. (if isTouch then "" else " [E]")
		itemHint.TextColor3 = ACCENT
	else
		itemIcon.Text = ""
		itemHint.Text = "no item"
		itemHint.TextColor3 = Color3.fromRGB(180, 180, 190)
	end
end
player:GetAttributeChangedSignal("Item"):Connect(refreshItem)
refreshItem()

------------------------------------------------------------------ coins + garage button
local coinFrame = panel({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -18), Size = UDim2.fromOffset(170, 44) }, gui)
local coinLabel = text({ Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5), Text = "🪙 0", TextXAlignment = Enum.TextXAlignment.Left }, coinFrame)
local garageButton = button({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -70), Size = UDim2.fromOffset(170, 44), Text = "🔧 GARAGE" }, gui)

local function refreshCoins()
	coinLabel.Text = "🪙 " .. tostring(player:GetAttribute("Coins") or 0)
end
player:GetAttributeChangedSignal("Coins"):Connect(refreshCoins)
refreshCoins()

------------------------------------------------------------------ toasts
local toastToken = 0
local function showToast(msg: string)
	toastToken += 1
	local my = toastToken
	toast.Text = msg
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.2
	task.delay(2.5, function()
		if my ~= toastToken then return end
		TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end
notifyRemote.OnClientEvent:Connect(showToast)

------------------------------------------------------------------ race state
local function refreshStatus()
	statusLabel.Text = ReplicatedStorage:GetAttribute("RaceMessage") or ""
end
local function refreshCountdown()
	local c = ReplicatedStorage:GetAttribute("Countdown") or ""
	countdownLabel.Text = c
	if c ~= "" then
		countdownLabel.Size = UDim2.fromOffset(520, 260)
		TweenService:Create(countdownLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(400, 200) }):Play()
		countdownLabel.TextColor3 = if c == "GO!" then Color3.fromRGB(60, 230, 90) else ACCENT
	end
end
local function refreshRacePanel()
	local inRace = player:GetAttribute("InRace") == true
	racePanel.Visible = inRace
	if inRace then
		local laps = ReplicatedStorage:GetAttribute("RaceLaps") or 3
		if player:GetAttribute("RaceFinished") then
			lapLabel.Text = "FINISHED"
		else
			lapLabel.Text = "LAP " .. (player:GetAttribute("RaceLap") or 1) .. "/" .. laps
		end
		posLabel.Text = "POS " .. (player:GetAttribute("RacePos") or 1) .. "/" .. (player:GetAttribute("RaceCount") or 1)
	end
end
ReplicatedStorage:GetAttributeChangedSignal("RaceMessage"):Connect(refreshStatus)
ReplicatedStorage:GetAttributeChangedSignal("Countdown"):Connect(refreshCountdown)
for _, a in { "InRace", "RaceLap", "RacePos", "RaceCount", "RaceFinished" } do
	player:GetAttributeChangedSignal(a):Connect(refreshRacePanel)
end
refreshStatus(); refreshCountdown(); refreshRacePanel()

------------------------------------------------------------------ results podium
local resultsFrame = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 330), Visible = false, BackgroundTransparency = 0.1 }, gui)
text({ Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 8), Text = "🏁 RACE RESULTS", Font = Enum.Font.GothamBlack, TextColor3 = ACCENT }, resultsFrame)
local resultsList = make("Frame", { Size = UDim2.new(1, -20, 1, -64), Position = UDim2.fromOffset(10, 56), BackgroundTransparency = 1 }, resultsFrame)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, resultsList)
local MEDALS = { "🥇", "🥈", "🥉" }

resultsRemote.OnClientEvent:Connect(function(results)
	for _, c in resultsList:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end
	for i, r in results do
		if i > 6 then break end
		local row = panel({ Size = UDim2.new(1, 0, 0, 38), LayoutOrder = i,
			BackgroundColor3 = if r.userId == player.UserId then Color3.fromRGB(70, 60, 20) else Color3.fromRGB(40, 44, 58), BackgroundTransparency = 0 }, resultsList)
		text({ Size = UDim2.new(0.14, 0, 1, -8), Position = UDim2.fromOffset(6, 4), Text = MEDALS[r.place] or ("#" .. r.place) }, row)
		text({ Size = UDim2.new(0.44, 0, 1, -10), Position = UDim2.new(0.15, 0, 0, 5), Text = r.name, TextXAlignment = Enum.TextXAlignment.Left }, row)
		text({ Size = UDim2.new(0.22, 0, 1, -12), Position = UDim2.new(0.6, 0, 0, 6), Text = r.time, TextColor3 = Color3.fromRGB(200, 200, 210) }, row)
		text({ Size = UDim2.new(0.16, 0, 1, -12), Position = UDim2.new(0.83, 0, 0, 6), Text = "+" .. r.coins .. "🪙", TextColor3 = ACCENT }, row)
	end
	resultsFrame.Visible = true
	task.delay(8, function() resultsFrame.Visible = false end)
end)

------------------------------------------------------------------ garage shop
local garage = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 430), Visible = false, BackgroundTransparency = 0.05 }, gui)
text({ Size = UDim2.new(1, -120, 0, 40), Position = UDim2.fromOffset(14, 8), Text = "🔧 GARAGE", Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left }, garage)
local garageCoins = text({ AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(150, 30), Position = UDim2.new(1, -60, 0, 14), Text = "", TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Right }, garage)
local closeButton = button({ AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -12, 0, 10), Text = "✕", BackgroundColor3 = Color3.fromRGB(180, 50, 50) }, garage)
local shopMsg = text({ AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0.5, 0, 1, -8), Text = "", TextColor3 = Color3.fromRGB(200, 200, 210) }, garage)

text({ Size = UDim2.new(1, -28, 0, 24), Position = UDim2.fromOffset(14, 54), Text = "UPGRADES", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(170, 175, 190) }, garage)
local upgradeRows = {}
for i, u in Catalog.Upgrades do
	local row = panel({ Size = UDim2.new(1, -28, 0, 44), Position = UDim2.fromOffset(14, 82 + (i - 1) * 50), BackgroundColor3 = Color3.fromRGB(40, 44, 58), BackgroundTransparency = 0 }, garage)
	text({ Size = UDim2.new(0.42, 0, 0.55, 0), Position = UDim2.fromOffset(10, 3), Text = u.name, TextXAlignment = Enum.TextXAlignment.Left }, row)
	text({ Size = UDim2.new(0.42, 0, 0.35, 0), Position = UDim2.new(0, 10, 0.6, 0), Text = u.desc, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(160, 165, 180) }, row)
	local pips = text({ Size = UDim2.new(0.2, 0, 0.6, 0), Position = UDim2.new(0.45, 0, 0.2, 0), Text = "", TextColor3 = ACCENT }, row)
	local buy = button({ AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.new(0.3, 0, 0, 32), Position = UDim2.new(1, -8, 0.5, 0), Text = "" }, row)
	buy.MouseButton1Click:Connect(function()
		local ok, msg = shopRemote:InvokeServer("Upgrade", u.id)
		shopMsg.Text = msg or ""
		shopMsg.TextColor3 = if ok then Color3.fromRGB(90, 230, 110) else Color3.fromRGB(255, 110, 110)
	end)
	upgradeRows[u.id] = { pips = pips, buy = buy, def = u }
end

text({ Size = UDim2.new(1, -28, 0, 24), Position = UDim2.fromOffset(14, 236), Text = "PAINT", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(170, 175, 190) }, garage)
local colorGrid = make("Frame", { Size = UDim2.new(1, -28, 0, 130), Position = UDim2.fromOffset(14, 262), BackgroundTransparency = 1 }, garage)
make("UIGridLayout", { CellSize = UDim2.fromOffset(90, 60), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, colorGrid)
local colorButtons = {}
for i, c in Catalog.Colors do
	local b = button({ LayoutOrder = i, Text = "", BackgroundColor3 = c.color }, colorGrid)
	local stroke = make("UIStroke", { Thickness = 0, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local lbl = text({ AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -6, 0.42, 0), Position = UDim2.new(0.5, 0, 1, -3), Text = "",
		TextStrokeTransparency = 0 }, b)
	b.MouseButton1Click:Connect(function()
		local ok, msg = shopRemote:InvokeServer("Color", c.id)
		shopMsg.Text = msg or ""
		shopMsg.TextColor3 = if ok then Color3.fromRGB(90, 230, 110) else Color3.fromRGB(255, 110, 110)
	end)
	colorButtons[c.id] = { label = lbl, stroke = stroke, def = c }
end

local function refreshGarage()
	garageCoins.Text = "🪙 " .. tostring(player:GetAttribute("Coins") or 0)
	local attrFor = { Speed = "SpeedLvl", Accel = "AccelLvl", Grip = "GripLvl" }
	for id, row in upgradeRows do
		local lvl = player:GetAttribute(attrFor[id]) or 0
		local max = #row.def.costs
		row.pips.Text = string.rep("●", lvl) .. string.rep("○", max - lvl)
		if lvl >= max then
			row.buy.Text = "MAXED"
			row.buy.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
		else
			row.buy.Text = "BUY 🪙" .. row.def.costs[lvl + 1]
			row.buy.BackgroundColor3 = ACCENT
		end
	end
	local owned = {}
	local ok, decoded = pcall(function() return HttpService:JSONDecode(player:GetAttribute("OwnedColors") or "{}") end)
	if ok and type(decoded) == "table" then owned = decoded end
	local equipped = player:GetAttribute("CarColor") or "Blue"
	for id, cb in colorButtons do
		if id == equipped then
			cb.label.Text = "✔ " .. id
			cb.stroke.Thickness = 3
		elseif owned[id] then
			cb.label.Text = id
			cb.stroke.Thickness = 0
		else
			cb.label.Text = "🪙" .. cb.def.cost
			cb.stroke.Thickness = 0
		end
	end
end
for _, a in { "Coins", "SpeedLvl", "AccelLvl", "GripLvl", "CarColor", "OwnedColors" } do
	player:GetAttributeChangedSignal(a):Connect(refreshGarage)
end
refreshGarage()

garageButton.MouseButton1Click:Connect(function()
	garage.Visible = not garage.Visible
	shopMsg.Text = "Upgrades and paint apply to your car right away"
	shopMsg.TextColor3 = Color3.fromRGB(200, 200, 210)
end)
closeButton.MouseButton1Click:Connect(function() garage.Visible = false end)

------------------------------------------------------------------ controls
local driftHeld = false
local function setDrift(on: boolean)
	if on == driftHeld then return end
	driftHeld = on
	setDriftRemote:FireServer(on)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift or k == Enum.KeyCode.ButtonR1 then
		setDrift(true)
	elseif k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonX then
		useItemRemote:FireServer()
	elseif k == Enum.KeyCode.G then
		garage.Visible = not garage.Visible
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local k = input.KeyCode
	if k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift or k == Enum.KeyCode.ButtonR1 then
		setDrift(false)
	end
end)

if UserInputService.TouchEnabled then
	local driftBtn = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -170), Size = UDim2.fromOffset(90, 90), Text = "DRIFT", BackgroundColor3 = Color3.fromRGB(230, 100, 30) }, gui)
	local itemBtn = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -120, 1, -170), Size = UDim2.fromOffset(80, 80), Text = "ITEM" }, gui)
	driftBtn.MouseButton1Down:Connect(function() setDrift(true) end)
	driftBtn.MouseButton1Up:Connect(function() setDrift(false) end)
	driftBtn.MouseLeave:Connect(function() setDrift(false) end)
	itemBtn.MouseButton1Click:Connect(function() useItemRemote:FireServer() end)
	driftText.Text = "Hold DRIFT + steer to charge a boost"
end

------------------------------------------------------------------ per-frame: drift meter, boost label, item box spin
RunService.RenderStepped:Connect(function(dt)
	local car = workspace:FindFirstChild("SimpleCar_" .. player.Name)
	local charge = car and car:GetAttribute("DriftCharge") or 0
	driftFill.Size = UDim2.fromScale(charge, 1)
	driftFill.BackgroundColor3 = if charge >= 0.25 then Color3.fromRGB(255, 120, 30) else Color3.fromRGB(150, 150, 160)
	boostLabel.Visible = car ~= nil and (car:GetAttribute("BoostUntil") or 0) > workspace:GetServerTimeNow()
	for _, box in CollectionService:GetTagged("ItemBox") do
		if box:IsA("BasePart") then
			box.CFrame = box.CFrame * CFrame.Angles(0, dt * 2, 0)
		end
	end
end)

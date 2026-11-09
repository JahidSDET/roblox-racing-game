-- TrackUtil: geometry of the oval. Driving direction: front straight (x = +R) toward -Z,
-- turn 1-2 around z = -L/2, back straight (x = -R) toward +Z, turn 3-4 around z = +L/2.
local raceTrack = workspace:WaitForChild("RaceTrack")

local R = raceTrack:GetAttribute("Radius") or 100
local W = raceTrack:GetAttribute("Width") or 40
local L = raceTrack:GetAttribute("StraightLength") or 300
local HALF = L / 2
local TOTAL = 2 * L + 2 * math.pi * R

local TrackUtil = { R = R, W = W, L = L, TOTAL = TOTAL }

-- Returns distance along the lap from the finish line (0..TOTAL), the nearest centerline
-- point (y = 0) and the forward (driving) direction there.
function TrackUtil.locate(pos: Vector3): (number, Vector3, Vector3)
	local x, z = pos.X, pos.Z
	if z <= HALF and z >= -HALF then
		if x >= 0 then
			local s = if z <= 0 then -z else TOTAL - z
			return s, Vector3.new(R, 0, z), Vector3.new(0, 0, -1)
		else
			return HALF + math.pi * R + (z + HALF), Vector3.new(-R, 0, z), Vector3.new(0, 0, 1)
		end
	elseif z < -HALF then
		local th = math.clamp(math.atan2(-(z + HALF), x), 0, math.pi)
		local p = Vector3.new(math.cos(th) * R, 0, -HALF - math.sin(th) * R)
		return HALF + R * th, p, Vector3.new(-math.sin(th), 0, -math.cos(th))
	else
		local th = math.clamp(math.atan2(z - HALF, x), 0, math.pi)
		local p = Vector3.new(math.cos(th) * R, 0, HALF + math.sin(th) * R)
		return HALF + math.pi * R + L + R * (math.pi - th), p, Vector3.new(math.sin(th), 0, -math.cos(th))
	end
end

-- Signed sideways distance from the centerline (+ = right of driving direction)
function TrackUtil.lateral(pos: Vector3): number
	local _, p, f = TrackUtil.locate(pos)
	local right = f:Cross(Vector3.yAxis)
	return (Vector3.new(pos.X, 0, pos.Z) - p):Dot(right)
end

-- A car pose on the track nearest to pos, facing the driving direction
function TrackUtil.poseAt(pos: Vector3, keepLateral: boolean?): CFrame
	local _, p, f = TrackUtil.locate(pos)
	local right = f:Cross(Vector3.yAxis)
	local lat = 0
	if keepLateral then
		lat = math.clamp(TrackUtil.lateral(pos), -(W / 2 - 4), W / 2 - 4)
	end
	local base = p + right * lat + Vector3.new(0, 1.6, 0)
	return CFrame.lookAt(base, base + f)
end

return TrackUtil

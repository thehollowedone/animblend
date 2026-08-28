--!strict

local DirectionalSolver = {}

export type Sample = {
	Id: string,
	Velocity: Vector2,
}

local AngleWeight = 2
local ContributionFloor = 0.1
local ContributionFull = 0.2
local Epsilon = 0.0001

local function SameQuadrant(X: number, Y: number, Velocity: Vector2): boolean
	return X * Velocity.X >= 0 and Y * Velocity.Y >= 0
end

local function SignedAngle(AX: number, AY: number, BX: number, BY: number): number
	return -math.atan2(AX * BY - AY * BX, AX * BX + AY * BY)
end

local function PairWeight(
	TargetX: number,
	TargetY: number,
	TargetSpeed: number,
	First: Vector2,
	Second: Vector2
): number
	local FirstSpeed = First.Magnitude
	local SecondSpeed = Second.Magnitude
	local AverageSpeed = 0.5 * (FirstSpeed + SecondSpeed)
	if AverageSpeed <= Epsilon then
		return 0
	end

	local PX = (TargetSpeed - FirstSpeed) / AverageSpeed
	local PY = AngleWeight * SignedAngle(First.X, First.Y, TargetX, TargetY)
	local SegmentX = (SecondSpeed - FirstSpeed) / AverageSpeed
	local SegmentY = AngleWeight * SignedAngle(First.X, First.Y, Second.X, Second.Y)
	local Denominator = Epsilon + SegmentX * SegmentX + SegmentY * SegmentY
	return math.clamp(1 - (PX * SegmentX + PY * SegmentY) / Denominator, 0, 1)
end

function DirectionalSolver.Solve(
	WorldX: number,
	WorldY: number,
	HeightScale: number,
	Samples: { Sample },
	Weights: { number }
): number?
	local Scale = if HeightScale > 0 then HeightScale else 1
	local TargetX = WorldX / Scale
	local TargetY = WorldY / Scale
	local TargetSpeed = math.sqrt(TargetX * TargetX + TargetY * TargetY)
	local Count = #Samples

	for Index = 1, Count do
		Weights[Index] = 0
	end
	if TargetSpeed <= Epsilon then
		return nil
	end

	local Sum = 0
	for Index, First in Samples do
		local FirstVelocity = First.Velocity
		if SameQuadrant(TargetX, TargetY, FirstVelocity) then
			local Best = math.huge
			for _, Second in Samples do
				local SecondVelocity = Second.Velocity
				if SameQuadrant(TargetX, TargetY, SecondVelocity) then
					Best = math.min(
						Best,
						PairWeight(TargetX, TargetY, TargetSpeed, FirstVelocity, SecondVelocity)
					)
				end
			end
			if Best < math.huge then
				Weights[Index] = Best
				Sum += Best
			end
		end
	end
	if Sum <= Epsilon then
		return nil
	end

	local Kept = 0
	local WeightedX = 0
	local WeightedY = 0
	for Index, Sample in Samples do
		local Weight = Weights[Index]
		local Share = Weight / Sum
		if Share > ContributionFloor then
			local Alpha = math.clamp(
				(Share - ContributionFloor) / (ContributionFull - ContributionFloor),
				0,
				1
			)
			Alpha = Alpha * Alpha * (3 - 2 * Alpha)
			local Smoothed = Weight * Alpha
			Weights[Index] = Smoothed
			Kept += Smoothed
			WeightedX += Smoothed * Sample.Velocity.X
			WeightedY += Smoothed * Sample.Velocity.Y
		else
			Weights[Index] = 0
		end
	end
	if Kept <= Epsilon then
		return nil
	end

	for Index = 1, Count do
		Weights[Index] /= Kept
	end

	local WeightedSpeed = math.sqrt(WeightedX * WeightedX + WeightedY * WeightedY)
	if WeightedSpeed <= Epsilon then
		return nil
	end
	return math.max(TargetSpeed / WeightedSpeed, Epsilon)
end

return DirectionalSolver

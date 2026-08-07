--!strict

local VariantPicker = {}

export type Variant = {
	Id: string,
	Weight: number,
}

local Modulus = 2147483647
local Multiplier = 48271

local function Hash(Value: number): number
	local X = math.floor(Value) % Modulus
	if X <= 0 then
		X += Modulus - 1
	end
	X = (X * Multiplier) % Modulus
	return (X * Multiplier) % Modulus
end

function VariantPicker.TotalWeight(Variants: { Variant }): number
	local Total = 0
	for _, Entry in Variants do
		local Weight = Entry.Weight
		if type(Weight) == "number" and Weight > 0 then
			Total += Weight
		end
	end
	return Total
end

function VariantPicker.Pick(Variants: { Variant }, Bucket: number): Variant?
	local Count = #Variants
	if Count == 0 then
		return nil
	end
	if Count == 1 then
		return Variants[1]
	end

	local Total = VariantPicker.TotalWeight(Variants)
	if Total <= 0 then
		return Variants[(Hash(Bucket) % Count) + 1]
	end

	local Roll = (Hash(Bucket) % Total) + 1
	for _, Entry in Variants do
		local Weight = Entry.Weight
		if type(Weight) == "number" and Weight > 0 then
			if Roll <= Weight then
				return Entry
			end
			Roll -= Weight
		end
	end

	return Variants[Count]
end

return VariantPicker

local Expect = {}

local Tolerance = 1e-6

export type Suite = {
	Passed: number,
	Failed: number,
	Equal: (Suite, string, any, any) -> (),
	Near: (Suite, string, number, number) -> (),
	True: (Suite, string, any) -> (),
	False: (Suite, string, any) -> (),
}

function Expect.New(Label: string)
	local Suite = {
		Label = Label,
		Passed = 0,
		Failed = 0,
	}

	function Suite:Fail(Name: string, Got: any, Want: any)
		self.Failed += 1
		print(string.format("FAIL [%s] %s: got %s want %s", self.Label, Name, tostring(Got), tostring(Want)))
	end

	function Suite:Equal(Name: string, Got: any, Want: any)
		if Got == Want then
			self.Passed += 1
			return
		end
		self:Fail(Name, Got, Want)
	end

	function Suite:Near(Name: string, Got: number, Want: number)
		if type(Got) == "number" and math.abs(Got - Want) <= Tolerance then
			self.Passed += 1
			return
		end
		self:Fail(Name, Got, Want)
	end

	function Suite:Between(Name: string, Got: number, Low: number, High: number)
		if type(Got) == "number" and Got >= Low and Got <= High then
			self.Passed += 1
			return
		end
		self:Fail(Name, Got, string.format("[%s, %s]", tostring(Low), tostring(High)))
	end

	function Suite:True(Name: string, Got: any)
		self:Equal(Name, Got, true)
	end

	function Suite:False(Name: string, Got: any)
		self:Equal(Name, Got, false)
	end

	return Suite
end

return Expect

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Agent = require(script.Agent)

local Toto = CollectionService:GetTagged("Toto")[1]
local TotoHumanoid = Toto:FindFirstChildOfClass("Humanoid")
local Tata = CollectionService:GetTagged("Tata")[1]

local TotoAgent = Agent.new({
	Inputs = { "DeltaX", "DeltaZ", "Distance" },
	Outputs = { "MoveX", "MoveZ", "Jump" },
})

local bestDistance = math.huge
local bestBrain = TotoAgent:GetWeights() -- On sauvegarde le cerveau initial
local stepTimer = 0
local cycleDuration = 20 -- Nombre de frames par test (laisser le temps de bouger)

local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

bestBrain = deepCopy(TotoAgent.Weights)

task.spawn(function()
	RunService.Heartbeat:Connect(function()
		local relative = (Tata:GetPivot().Position - Toto:GetPivot().Position)
		local dist = relative.Magnitude

		local inputs = {
			relative.X / 50,
			relative.Z / 50,
			math.clamp(dist / 50, 0, 1),
		}

		local decisions = TotoAgent:Decide(inputs)

		local dir = Vector3.new((decisions["MoveX"] - 0.5) * 2, 0, (decisions["MoveZ"] - 0.5) * 2)
		if dir.Magnitude > 0.2 then
			TotoHumanoid:Move(dir, false)
		end

		stepTimer += 1

		if stepTimer >= cycleDuration then
			stepTimer = 0

			if dist < bestDistance then
				print("Progrès ! Dist:", math.floor(dist))
				bestDistance = dist

				bestBrain = deepCopy(TotoAgent.Weights)

				TotoAgent:Evolve(0.05)
			else
				TotoAgent.Weights = deepCopy(bestBrain)
				TotoAgent:Evolve(0.3) -- Mutation plus forte pour tenter de débloquer
			end
		end
	end)
end)

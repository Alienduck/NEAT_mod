-- src/server/init.server.luau
--[[
	HEADER:

]]
local RunService = game:GetService("RunService")
local NeuralNetwork = require(script.NeuralNetwork)

-- --- GAME CONFIG ---
local SIMULATION_SPEED = 1 -- Upgrade the speed like 5 or 10 to go faster in the simulation
local GEN_DURATION = 15 / SIMULATION_SPEED
local TARGET = workspace:WaitForChild("Tata")
local MOB_MODEL = workspace:WaitForChild("Toto")

-- --- INITIALIZATION ---
-- Ask the Neural Network module to create a Solver
local AI_Solver = NeuralNetwork.newSolver({
	PopulationSize = 20,
	Structure = { 3, 6, 2 }, -- 3 Inputs -> 6 Neurons (Cachés) -> 2 Outputs
	MutationRate = 0.1,
	Elitism = 2,
})

local Agents = {} -- Link between 3D model and Brain

-- --- RESET MAP FUNCTION ---
local function ResetMap()
	for _, agent in ipairs(Agents) do
		agent.Model:Destroy()
	end
	table.clear(Agents)

	for i = 1, AI_Solver.PopSize do
		local mob = MOB_MODEL:Clone()
		mob.Parent = workspace
		mob:PivotTo(CFrame.new(0, 50, 0))

		-- Link Model with its Brain
		table.insert(Agents, {
			Model = mob,
			Brain = AI_Solver:GetGenome(i), -- Get the Neural Network from the Solver
		})
	end
end

-- --- MAIN LOOP ---
task.spawn(function()
	ResetMap()
	local startTime = os.clock()

	while true do
		local _ = RunService.Heartbeat:Wait()

		-- Manage Generation Timing
		if os.clock() - startTime > GEN_DURATION then
			print("Fin de génération. Calcul de l'évolution...")

			-- One generation passed, ask the Solver to evolve the population
			local genId, bestScore = AI_Solver:NextGeneration()

			print(string.format("Gen: %d | Meilleur Score: %.2f", genId, bestScore))
			ResetMap()
			startTime = os.clock()
		end

		-- Physic simulation
		for _, agent in ipairs(Agents) do
			local hum = agent.Model:FindFirstChild("Humanoid")
			local hrp = agent.Model:FindFirstChild("HumanoidRootPart")

			if hum and hrp and hum.Health > 0 then
				-- 1. SENSORS (Perception)
				local vecToTarget = TARGET:GetPivot().Position - hrp.Position
				local inputs = {
					vecToTarget.X / 100, -- Always normalize inputs!
					vecToTarget.Z / 100,
					math.tanh(vecToTarget.Magnitude / 50), -- Distance compressed between 0 and 1
				}

				-- 2. DECISION (Brain)
				local outputs = agent.Brain:Predict(inputs)

				-- 3. ACTION (Muscles)
				local moveDir = Vector3.new(outputs[1], 0, outputs[2])
				hum:Move(moveDir, false)

				-- 4. FITNESS (Fitness)
				-- IMPORTANT : This is a simple fitness function, you can design your own!
				local dist = vecToTarget.Magnitude
				-- Closer is better, so we inverse the distance
				local score = 1000 / (dist * dist + 0.1)

				-- If the agent fall down, end the simulation for it
				if hrp.Position.Y < -5 then
					score = 0
					hum.Health = 0
				end

				-- Assign the score to the Brain for evolution purpose
				agent.Brain.Fitness = score
			end
		end
	end
end)

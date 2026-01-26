local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local NeuralNetwork = require(script.NeuralNetwork)
local Drone = require(script.Drone)

local GEN_TIME = 20
local POPULATION = 150
local DroneModel = ServerStorage:WaitForChild("Drone")
local SpawnPoint = workspace:WaitForChild("SpawnPoint")

-- 3 Outputs only: Speed, Yaw, Pitch (Firing is automatic)
local AI_Solver = NeuralNetwork.newSolver({
	PopulationSize = POPULATION,
	Structure = { 5, 12, 3 },
	MutationRate = 0.1,
	Elitism = 2,
})

local ActiveDrones = {}

local function StartGeneration()
	for _, drone in ipairs(ActiveDrones) do
		drone:Destroy()
	end
	table.clear(ActiveDrones)
	print("--- START GENERATION " .. AI_Solver.Generation .. " ---")

	for i = 1, POPULATION do
		local modelClone = DroneModel:Clone()
		modelClone.Parent = workspace
		local offset = Vector3.new(math.random(-30, 30), 10, math.random(-30, 30))
		modelClone:PivotTo(SpawnPoint.CFrame * CFrame.new(offset))

		local brain = AI_Solver:GetGenome(i)
		local newDrone = Drone.new(modelClone, brain)
		table.insert(ActiveDrones, newDrone)
	end
end

task.spawn(function()
	StartGeneration()
	local genStartTime = os.clock()

	while true do
		local dt = RunService.Heartbeat:Wait()

		if os.clock() - genStartTime > GEN_TIME then
			local genId, bestScore = AI_Solver:NextGeneration()
			print("End Gen " .. (genId - 1) .. " | Best Score: " .. math.floor(bestScore))
			StartGeneration()
			genStartTime = os.clock()
		end

		local target = Players:GetPlayers()[1]
		for _, drone in ipairs(ActiveDrones) do
			drone:Update(dt, target)
		end
	end
end)

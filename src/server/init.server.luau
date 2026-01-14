-- Script (ServerScriptService)
local RunService = game:GetService("RunService")
local NN = require(script.NeuralNetwork)

-- CONFIGURATION
local POPULATION_SIZE = 20
local GEN_DURATION = 15 -- Secondes par génération
local MUTATION_RATE = 0.1
local MUTATION_POWER = 0.5

local Target: Model = workspace:WaitForChild("Tata")
local MobTemplate = workspace:WaitForChild("Toto")

local Population = {} -- Stocke {Agent = Model, Brain = NN, Fitness = 0}
local Generation = 1

local function ResetSimulation(oldBrains)
	for _, data in ipairs(Population) do
		if data.Agent then
			data.Agent:Destroy()
		end
	end
	Population = {}

	for i = 1, POPULATION_SIZE do
		local mob = MobTemplate:Clone()
		mob.Name = mob.Name .. i
		mob.Parent = workspace
		mob:PivotTo(CFrame.new(0, 50, 0)) -- Point de départ fixe (0,5,0)

		-- Si on a des cerveaux de la génération d'avant (oldBrains), on les utilise
		local brain
		if oldBrains and #oldBrains > 0 then
			brain = oldBrains[i]
		else
			-- 3 Inputs (DeltaX, DeltaZ, Dist), 4 Neurones cachés, 2 Outputs (MoveX, MoveZ)
			brain = NN.new({ 3, 4, 2 })
		end

		table.insert(Population, { Agent = mob, Brain = brain, Fitness = 0 })
	end
end

-- Calcule les inputs pour UN agent
local function GetInputs(mob)
	local hrp = mob:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return { 0, 0, 0 }
	end

	local rel = (Target:GetPivot().Position - hrp.Position)
	-- On normalise (diviser par 100)
	return {
		rel.X / 100,
		rel.Z / 100,
		math.clamp(rel.Magnitude / 100, 0, 1),
	}
end

-- Boucle principale
task.spawn(function()
	ResetSimulation(nil) -- Création de la Gen 1

	while true do
		local startTime = os.clock()
		print("--- Generation " .. Generation .. " Started ---")

		-- BOUCLE DE JEU (Pendant X secondes)
		while os.clock() - startTime < GEN_DURATION do
			for _, data in ipairs(Population) do
				local mob = data.Agent
				local hum = mob:FindFirstChild("Humanoid")
				local hrp = mob:FindFirstChild("HumanoidRootPart")

				if hum and hrp and hum.Health > 0 then
					-- 1. Réflexion
					local inputs = GetInputs(mob)
					local outputs = data.Brain:Predict(inputs)

					-- 2. Action (MoveX, MoveZ sont entre -1 et 1)
					local moveDir = Vector3.new(outputs[1], 0, outputs[2])
					hum:Move(moveDir, false)

					-- 3. Fitness (Score) continue
					local dist = (Target:GetPivot().Position - hrp.Position).Magnitude
					-- Plus il est proche, plus le score monte.
					-- Au carré pour pénaliser fortement ceux qui sont loin.
					local score = 1000 / (dist * dist + 1)
					data.Fitness = score

					-- Si tombé du plateau -> Mort
					if not hrp or hrp.Position.Y < -10 then
						hum.Health = 0
					end
				end
			end
			RunService.Heartbeat:Wait()
		end

		-- FIN DE GENERATION : SELECTION & REPRODUCTION
		print("Evolution...")

		-- 1. Trier par Fitness (Meilleurs en premier)
		table.sort(Population, function(a, b)
			return a.Fitness > b.Fitness
		end)

		print("Best Fitness: " .. math.floor(Population[1].Fitness) .. " | From: " .. Population[1].Agent.Name)

		-- 2. Elitisme & Crossover
		local nextGenBrains = {}

		-- On garde le TOP 2 tel quel (Elitisme pur)
		table.insert(nextGenBrains, Population[1].Brain)
		table.insert(nextGenBrains, Population[2].Brain)

		-- Le reste est rempli par des enfants du TOP 50%
		local survivorCount = math.floor(POPULATION_SIZE / 2)

		while #nextGenBrains < POPULATION_SIZE do
			-- Choisir 2 parents au hasard parmi les survivants
			local p1 = Population[math.random(1, survivorCount)].Brain
			local p2 = Population[math.random(1, survivorCount)].Brain

			-- Faire un enfant
			local child = p1:Crossover(p2)
			child:Mutate(MUTATION_RATE, MUTATION_POWER)

			table.insert(nextGenBrains, child)
		end

		Generation += 1
		ResetSimulation(nextGenBrains)
	end
end)

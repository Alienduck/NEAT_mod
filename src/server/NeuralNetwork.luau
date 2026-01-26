-- src/server/NeuralNetwork.luau
local NeuralNetwork = {}
NeuralNetwork.__index = NeuralNetwork

-------------------------------------------------------------------------------
-- PART 1 : THE BRAIN (Neurons network)
-------------------------------------------------------------------------------
local Network = {}
Network.__index = Network

export type NeuralNetwork = {
	Structure: { number },
	Weights: { { number } },
	Fitness: number,

	new: (structure: { number }) -> NeuralNetwork,
	Predict: (self: NeuralNetwork, inputs: { number }) -> { number },
}

--[[
    Initialize the neural network connections
    @param structure: `{ number }`
    @return NeuralNetwork
]]
function Network.new(structure)
	local self: NeuralNetwork = {} :: NeuralNetwork
	setmetatable(self, Network)
	self.Structure = structure
	self.Weights = {}
	self.Fitness = 0

	-- Xavier Initialization (Optimised weights to avoid saturation)
	for i = 1, #structure - 1 do
		local layer = {}
		local inputSize = structure[i]
		local outputSize = structure[i + 1]
		local scale = math.sqrt(6 / (inputSize + outputSize)) -- Seems weird but necessary, it's just scale

		for _ = 1, inputSize * outputSize do
			table.insert(layer, (math.random() * 2 - 1) * scale)
		end
		table.insert(self.Weights, layer)
	end
	return self
end

--[[
    Predict next step by transforming the input, give an output, which is the result of what developer wants
    @param inputs: `{ number }`
    @return inputs
]]
function Network:Predict(inputs)
	local current = inputs
	for l, layerWeights in ipairs(self.Weights) do
		local nextLayer = table.create(self.Structure[l + 1])
		local prevNeurons = #current
		local outputNeurons = self.Structure[l + 1]

		for i = 1, outputNeurons do
			local sum = 0
			for j = 1, prevNeurons do
				sum += current[j] * layerWeights[(i - 1) * prevNeurons + j]
			end
			-- Tanh Activation (Scale number between 1 and -1)
			table.insert(nextLayer, math.tanh(sum))
		end
		current = nextLayer
	end
	return current
end

-------------------------------------------------------------------------------
-- PART 2 : THE GENETIC MANAGER (INTELLIGENCE OF THE GROUP)
-------------------------------------------------------------------------------
local Solver = {}
Solver.__index = Solver

export type SolverConfig = {
	PopulationSize: number?,
	Structure: { number }?,
	MutationRate: number?,
	Elitism: number?,
}

export type Solver = {
	PopSize: number,
	Structure: { number },
	MutationRate: number,
	Elitism: number,
	Genomes: { NeuralNetwork },
	Generation: number,
}

--[[
    @param config: ` Config`
    @return Solver
]]
function NeuralNetwork.newSolver(config: SolverConfig): Solver
	local self = setmetatable({}, Solver)
	self.PopSize = config.PopulationSize or 20
	self.Structure = config.Structure or { 3, 5, 2 }
	self.MutationRate = config.MutationRate or 0.1
	self.Elitism = config.Elitism or 2

	self.Genomes = {} :: { NeuralNetwork } -- List of brains (Network)
	self.Generation = 1

	-- Creation of the first generation
	for _ = 1, self.PopSize do
		table.insert(self.Genomes, Network.new(self.Structure))
	end

	return self
end

--[[
    @param index: `number`
    @return NeuralNetwork
]]
function Solver:GetGenome(index)
	return self.Genomes[index]
end

-- Algorithm of selection by Tournament (More robust than simple sorting)
local function TournamentSelection(population)
	local best = nil
	-- Take 3 random individuals and select the best among them
	for _ = 1, 3 do
		local ind = population[math.random(1, #population)]
		if best == nil or ind.Fitness > best.Fitness then
			best = ind
		end
	end
	return best
end

-- Gaussian Mutation (Permit finer learning)
local function GaussianMutate(network, rate)
	for _, layer in ipairs(network.Weights) do
		for i = 1, #layer do
			if math.random() < rate then
				-- Add a small random value (bell curve) rather than replacing everything
				local noise = (math.random() + math.random() + math.random() - 1.5)
				layer[i] += noise * 0.5
				layer[i] = math.clamp(layer[i], -5, 5) -- Clamp to avoid extreme values
			end
		end
	end
end

-- Crossover between two parents to create a child
local function Crossover(dad, mum)
	local child = Network.new(dad.Structure)
	for i, layer in ipairs(child.Weights) do
		for j = 1, #layer do
			-- Randomly take weight from dad or mum
			layer[j] = (math.random() > 0.5) and dad.Weights[i][j] or mum.Weights[i][j]
		end
	end
	return child
end

-- GO TO NEXT GENERATION
-- This is where the module does all the hard work of evolution
function Solver:NextGeneration()
	-- 1. Sort the population by fitness (best first)
	table.sort(self.Genomes, function(a, b)
		return a.Fitness > b.Fitness
	end)

	local bestFitness = self.Genomes[1].Fitness
	local newGenomes = {}

	-- 2. Elitism - Keep the best individuals
	for i = 1, self.Elitism do
		local elite = Network.new(self.Structure)
		-- Deep copy of weights
		for l, layer in ipairs(self.Genomes[i].Weights) do
			for w, val in ipairs(layer) do
				elite.Weights[l][w] = val
			end
		end
		table.insert(newGenomes, elite)
	end

	-- 3. Reproduction - Fill the rest of the population
	while #newGenomes < self.PopSize do
		local dad = TournamentSelection(self.Genomes)
		local mum = TournamentSelection(self.Genomes)

		local child = Crossover(dad, mum)
		GaussianMutate(child, self.MutationRate)

		table.insert(newGenomes, child)
	end

	self.Genomes = newGenomes
	self.Generation += 1

	return self.Generation, bestFitness
end

return NeuralNetwork

-- ModuleScript: NeuralNetwork
local NN = {}
NN.__index = NN

function NN.new(layerSizes)
	local self = setmetatable({}, NN)
	self.Weights = {}
	self.Layers = layerSizes

	-- Initialisation des poids (Xavier Initialization simplifiée)
	for i = 1, #layerSizes - 1 do
		local layer = {}
		local numWeights = layerSizes[i] * layerSizes[i + 1]
		for j = 1, numWeights do
			table.insert(layer, (math.random() * 2 - 1))
		end
		table.insert(self.Weights, layer)
	end
	return self
end

function NN:Predict(inputs)
	local current = inputs
	for l, layerWeights in ipairs(self.Weights) do
		local nextLayer = {}
		local numNeurons = self.Layers[l + 1]
		local prevNeurons = #current

		for i = 1, numNeurons do
			local sum = 0
			for j = 1, prevNeurons do
				-- Index mapping: flatten 1D array to 2D logic
				sum += current[j] * layerWeights[(i - 1) * prevNeurons + j]
			end
			-- Activation: Tanh (-1 à 1)
			table.insert(nextLayer, math.tanh(sum))
		end
		current = nextLayer
	end
	return current
end

-- Mélange les cerveaux de 2 parents (50/50)
function NN:Crossover(partner)
	local child = NN.new(self.Layers)
	for i, layer in ipairs(self.Weights) do
		for j = 1, #layer do
			-- On prend soit le gène de Papa, soit celui de Maman
			if math.random() > 0.5 then
				child.Weights[i][j] = self.Weights[i][j]
			else
				child.Weights[i][j] = partner.Weights[i][j]
			end
		end
	end
	return child
end

-- Mutation: Petits changements aléatoires
function NN:Mutate(rate, power)
	for i, layer in ipairs(self.Weights) do
		for j = 1, #layer do
			if math.random() < rate then
				layer[j] += (math.random() * 2 - 1) * power
				-- Clamp pour éviter que les poids n'explosent
				layer[j] = math.clamp(layer[j], -5, 5)
			end
		end
	end
end

return NN

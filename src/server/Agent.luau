local Agent = {}
Agent.__index = Agent

function Agent.new(config)
	local self = setmetatable({}, Agent)
	self.Inputs = config.Inputs -- Names of inputs
	self.Outputs = config.Outputs -- Names of outputs
	self.Layers = { #config.Inputs, 10, #config.Outputs }
	self.Weights = {}

	for i = 1, #self.Layers - 1 do
		local layer = {}
		for j = 1, self.Layers[i] * self.Layers[i + 1] do
			table.insert(layer, math.random() * 2 - 1)
		end
		table.insert(self.Weights, layer)
	end
	return self
end

function Agent:GetWeights()
	local copy = {}
	for i, layer in ipairs(self.Weights) do
		local layerCopy = {}
		for j, val in ipairs(layer) do
			table.insert(layerCopy, val)
		end
		table.insert(copy, layerCopy)
	end
	return copy
end

function Agent:SetWeights(savedWeights)
	self.Weights = savedWeights
end

function Agent:Decide(inputValues)
	local current = inputValues
	for _, layer in ipairs(self.Weights) do
		local nextL = {}
		local outNodes = #layer / #current
		for i = 1, outNodes do
			local dot = 0
			for j = 1, #current do
				dot += current[j] * layer[(i - 1) * #current + j]
			end
			table.insert(nextL, math.tanh(dot))
		end
		current = nextL
	end

	local results = {}
	for i, name in ipairs(self.Outputs) do
		results[name] = current[i]
	end
	return results
end

function Agent:Evolve(factor)
	for _, layer in ipairs(self.Weights) do
		for i = 1, #layer do
			if math.random() < 0.2 then
				layer[i] += (math.random() * 2 - 1) * factor
			end
		end
	end
end

return Agent

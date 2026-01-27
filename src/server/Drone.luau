local Players = game:GetService("Players")
local Drone = {}
Drone.__index = Drone

local CONFIG = {
	MAX_SPEED = 30,
	TURN_SPEED = 6, -- Increased to track fast players
	PITCH_SPEED = 3, -- Increased to raise/lower head faster
	VISION_RANGE = 1000,
	FLIGHT_HEIGHT = 8,
}

-- Utility function for smoothing (Lerp)
local function Lerp(a, b, t)
	return a + (b - a) * t
end

function Drone.new(model: Model, brain)
	local self = setmetatable({}, Drone)
	self.Model = model
	self.Eye = model:WaitForChild("Eye")
	self.Humanoid = model:FindFirstChildOfClass("Humanoid")
	self.RootPart = model:WaitForChild("HumanoidRootPart")
	self.Brain = brain
	self.CurrentHealth = self.Humanoid.Health
	self.LastShot = 0

	-- Smoothing variables
	self.SmoothYaw = 0
	self.SmoothPitch = 0
	self.SmoothSpeed = 0

	local gyro = Instance.new("BodyGyro")
	gyro.MaxTorque = Vector3.new(400000, 400000, 400000)
	gyro.P = 4000 -- Stiffer
	gyro.D = 400 -- Less damping for more responsiveness
	gyro.CFrame = self.RootPart.CFrame
	gyro.Parent = self.RootPart
	self.Gyro = gyro

	local velocity = Instance.new("BodyVelocity")
	velocity.MaxForce = Vector3.new(400000, 400000, 400000)
	velocity.Velocity = Vector3.zero
	velocity.Parent = self.RootPart
	self.Motor = velocity

	self.Humanoid.HealthChanged:Connect(function(h)
		self:TakeDamage(h)
	end)

	self.RayParams = RaycastParams.new()
	self.RayParams.FilterDescendantsInstances = { self.Model }
	self.RayParams.FilterType = Enum.RaycastFilterType.Exclude
	return self
end

function Drone:Destroy()
	if self.Model then
		self.Model:Destroy()
	end
end

function Drone:GetInputs(targetRoot)
	if not targetRoot then
		return { 0, 0, 0, 0, 0 }
	end

	local myCFrame = self.Eye.CFrame
	local targetPos = targetRoot.Position
	local localTarget = myCFrame:PointToObjectSpace(targetPos)
	local localDir = localTarget.Unit
	local dist = localTarget.Magnitude

	local wallAhead = 0
	local wallHit = workspace:Raycast(self.Eye.Position, myCFrame.LookVector * 20, self.RayParams)
	if wallHit then
		wallAhead = 1
	end

	return {
		localDir.X, -- 1: Left/Right Error (-1 to 1)
		localDir.Y, -- 2: Up/Down Error (-1 to 1)
		localDir.Z, -- 3: Front/Back
		math.tanh(dist / 100), -- 4: Distance
		wallAhead, -- 5: Wall
	}
end

function Drone:Update(dt, targetPlayer)
	if self.Humanoid.Health <= 0 then
		return
	end

	local targetRoot = targetPlayer
		and targetPlayer.Character
		and targetPlayer.Character:FindFirstChild("HumanoidRootPart")

	-- Inputs / Outputs
	local inputs = self:GetInputs(targetRoot)
	local outputs = self.Brain:Predict(inputs)

	-- ====================================================
	-- 1. STABILIZATION (MORE REACTIVE)
	-- ====================================================
	-- Increasing the factor (0.4) so the drone reacts faster to brain commands
	self.SmoothYaw = Lerp(self.SmoothYaw, outputs[2], 0.4)
	self.SmoothPitch = Lerp(self.SmoothPitch, outputs[3], 0.4)
	self.SmoothSpeed = Lerp(self.SmoothSpeed, outputs[1], 0.2)

	local yaw = self.SmoothYaw * CONFIG.TURN_SPEED * dt
	local pitch = self.SmoothPitch * CONFIG.PITCH_SPEED * dt

	self.Gyro.CFrame = self.Gyro.CFrame * CFrame.Angles(pitch, -yaw, 0)

	local forwardSpeed = self.SmoothSpeed * CONFIG.MAX_SPEED

	-- Altitude Management (Stiffer)
	-- Raycast to find ground height
	local groundHit = workspace:Raycast(self.RootPart.Position, Vector3.new(0, -100, 0), self.RayParams)
	local targetHeight = CONFIG.FLIGHT_HEIGHT
	if groundHit then
		targetHeight = groundHit.Position.Y + CONFIG.FLIGHT_HEIGHT
	end

	local currentHeight = self.RootPart.Position.Y
	local heightError = (targetHeight - currentHeight)
	local verticalForce = math.clamp(heightError * 8, -30, 30)

	local moveVector = self.RootPart.CFrame.LookVector * forwardSpeed
	self.Motor.Velocity = Vector3.new(moveVector.X, verticalForce, moveVector.Z)

	-- ====================================================
	-- 2. IMPROVED FITNESS LOGIC (GRADIENT)
	-- ====================================================
	if targetRoot then
		local dist = (targetRoot.Position - self.RootPart.Position).Magnitude

		-- ALIGNMENT
		local alignmentX = math.abs(inputs[1]) -- 0 = perfect, 1 = bad
		local alignmentY = math.abs(inputs[2])
		local isFacing = inputs[3] < 0

		-- PROGRESSIVE REWARD (This is key!)
		-- Instead of rewarding IF < 0.15, we reward "The closer you are to 0, the more you gain"
		-- (1 - alignment) gives 1.0 if perfect, 0.5 if average, 0.0 if at 90 degrees
		if isFacing then
			local aimQuality = (1 - alignmentX) * (1 - alignmentY)
			-- Continuous reward to encourage aiming refinement
			self.Brain.Fitness += aimQuality * 0.2
		end

		-- STRICT FIRING CONDITION
		-- We fire only if REALLY well aligned (< 0.1)
		if alignmentX < 0.1 and alignmentY < 0.1 and isFacing and (os.clock() - self.LastShot > 0.5) then
			self:Fire()
			self.LastShot = os.clock()
		end

		-- DISTANCE MANAGEMENT
		if dist > 80 then
			self.Brain.Fitness -= 0.1 -- Stronger punishment for camping
		elseif dist < 15 then
			self.Brain.Fitness -= 0.05
		else
			self.Brain.Fitness += 0.05
		end
	end
end

function Drone:Fire()
	local origin = self.Eye.Position
	local dir = self.Eye.CFrame.LookVector

	local laser = Instance.new("Part")
	laser.Size = Vector3.new(0.2, 0.2, 8) -- Longer laser
	laser.Color = Color3.fromRGB(255, 0, 50)
	laser.Material = Enum.Material.Neon
	laser.Anchored = true
	laser.CanCollide = false
	laser.CFrame = CFrame.new(origin + dir * 4, origin + dir * 10)
	laser.Parent = workspace
	game.Debris:AddItem(laser, 0.1)

	local hit = workspace:Raycast(origin, dir * CONFIG.VISION_RANGE, self.RayParams)

	if hit and hit.Instance and hit.Instance.Parent and hit.Instance.Parent:FindFirstChild("Humanoid") then
		local char = hit.Instance.Parent
		if Players:GetPlayerFromCharacter(char) then
			local hum = char.Humanoid
			self.Brain.Fitness += 30
			if hum.Health > 0 then
				self.Brain.Fitness += 150 -- Huge bonus for hitting
				hum:TakeDamage(10)
			end
		end
	else
		-- Light punishment for missed shot (so it doesn't stop firing, but prefers hitting)
		self.Brain.Fitness -= 2
	end
end

function Drone:TakeDamage(newHealth)
	local damage = self.CurrentHealth - newHealth
	self.CurrentHealth = newHealth

	if damage > 0 then
		self.Brain.Fitness -= (damage * 5)
	end

	if newHealth <= 0 then
		self.Brain.Fitness -= 100 -- Severe death punishment
		self.RootPart.Anchored = false
		self.Motor:Destroy()
		self.Gyro:Destroy()
		if self.Eye:FindFirstChild("WeldConstraint") then
			self.Eye.WeldConstraint:Destroy()
		end
	end
end

return Drone

local Players = game:GetService("Players")
local Drone = {}
Drone.__index = Drone

local CONFIG = {
	MAX_SPEED = 20,
	TURN_SPEED = 3,
	PITCH_SPEED = 5,
	VISION_RANGE = 1000,
	FLIGHT_HEIGHT = 8, -- Remis un peu plus haut pour éviter le sol
}

-- Fonction utilitaire pour lisser les mouvements (Lerp)
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

	-- Variables pour le lissage (Anti-Tremblement)
	self.SmoothYaw = 0
	self.SmoothPitch = 0
	self.SmoothSpeed = 0

	local gyro = Instance.new("BodyGyro")
	gyro.MaxTorque = Vector3.new(400000, 400000, 400000)
	gyro.P = 3000
	gyro.D = 600 -- Augmenté un peu pour amortir
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
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { self.Model }
	local wallHit = workspace:Raycast(self.Eye.Position, myCFrame.LookVector * 20, rayParams)
	if wallHit then
		wallAhead = 1
	end

	return {
		localDir.X, -- 1: Erreur Horizontale
		localDir.Y, -- 2: Erreur Verticale
		localDir.Z, -- 3: Devant/Derrière
		math.tanh(dist / 100), -- 4: Distance (Divisé par 100 pour une meilleure perception de loin)
		wallAhead, -- 5: Mur
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
	-- 1. STABILISATION (LISSAGE)
	-- ====================================================
	-- Au lieu d'appliquer directement 'outputs[x]', on fait une moyenne avec la valeur précédente.
	-- 0.1 = Très lisse (lent), 0.9 = Très réactif (tremblement). 0.2 est un bon équilibre.

	self.SmoothYaw = Lerp(self.SmoothYaw, outputs[2], 0.15)
	self.SmoothPitch = Lerp(self.SmoothPitch, outputs[3], 0.15)
	self.SmoothSpeed = Lerp(self.SmoothSpeed, outputs[1], 0.1)

	-- Application des valeurs lissées
	local yaw = self.SmoothYaw * CONFIG.TURN_SPEED * dt
	local pitch = self.SmoothPitch * CONFIG.PITCH_SPEED * dt

	self.Gyro.CFrame = self.Gyro.CFrame * CFrame.Angles(pitch, -yaw, 0)

	local forwardSpeed = self.SmoothSpeed * CONFIG.MAX_SPEED

	-- Gestion Altitude
	local currentHeight = self.RootPart.Position.Y
	local heightError = (CONFIG.FLIGHT_HEIGHT - currentHeight)
	local verticalForce = math.clamp(heightError * 5, -20, 20)

	local moveVector = self.RootPart.CFrame.LookVector * forwardSpeed
	self.Motor.Velocity = Vector3.new(moveVector.X, verticalForce, moveVector.Z)

	-- ====================================================
	-- 2. LOGIQUE DE FITNESS (DISTANCE)
	-- ====================================================
	if targetRoot then
		local dist = (targetRoot.Position - self.RootPart.Position).Magnitude

		-- ALIGNEMENT & TIR
		local isAlignedX = math.abs(inputs[1]) < 0.15
		local isAlignedY = math.abs(inputs[2]) < 0.15
		local isFacing = inputs[3] < 0

		if isAlignedX and isAlignedY and isFacing and (os.clock() - self.LastShot > 0.5) then
			self:Fire()
			self.LastShot = os.clock()
		end

		if isAlignedX and isAlignedY then
			self.Brain.Fitness += 0.1
		end

		-- GESTION DE LA DISTANCE (C'est ici qu'on force l'approche)
		if dist > 80 then
			-- TROP LOIN : Petite punition continue pour les forcer à bouger
			self.Brain.Fitness -= 0.05
		elseif dist < 15 then
			-- TROP PRÈS : Punition pour éviter les collisions (optionnel)
			self.Brain.Fitness -= 0.05
		else
			-- ZONE PARFAITE (Entre 15 et 80 studs) : Récompense !
			self.Brain.Fitness += 0.05
		end
	end
end

function Drone:Fire()
	local origin = self.Eye.Position
	local dir = self.Eye.CFrame.LookVector

	local laser = Instance.new("Part")
	laser.Size = Vector3.new(0.2, 0.2, 6)
	laser.Color = Color3.fromRGB(255, 0, 50)
	laser.Material = Enum.Material.Neon
	laser.Anchored = true
	laser.CanCollide = false
	laser.CFrame = CFrame.new(origin + dir * 3, origin + dir * 10)
	laser.Parent = workspace
	game.Debris:AddItem(laser, 0.1)

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { self.Model }
	local hit = workspace:Raycast(origin, dir * CONFIG.VISION_RANGE, params)

    self.Brain.Fitness += 10 -- RÉCOMPENSE DE TIR

	if hit and hit.Instance and hit.Instance.Parent and hit.Instance.Parent:FindFirstChild("Humanoid") then
		local char = hit.Instance.Parent
		if Players:GetPlayerFromCharacter(char) then
			local hum = char.Humanoid
			-- ON RÉDUIT UN PEU LA RÉCOMPENSE DE TIR SIMPLE
			self.Brain.Fitness += 20
			if hum.Health > 0 then
				self.Brain.Fitness += 100 -- Suffisant pour motiver
				hum:TakeDamage(10)
			end
        elseif hit.Instance.Parent.Name == "Drone" then
            self.Brain.Fitness -= 5 -- PUNITION POUR TIR AMICAL
		end
    else
        self.Brain.Fitness -= 1 -- PUNITION POUR TIR DANS LE VIDE
	end
end

function Drone:TakeDamage(newHealth)
	local damage = self.CurrentHealth - newHealth
	self.CurrentHealth = newHealth

	if damage > 0 then
		self.Brain.Fitness -= (damage * 5)
	end

	if newHealth <= 0 then
		self.Brain.Fitness -= 50
		self.RootPart.Anchored = false
		self.Motor:Destroy()
		self.Gyro:Destroy()
		if self.Eye:FindFirstChild("WeldConstraint") then
			self.Eye.WeldConstraint:Destroy()
		end
	end
end

return Drone

local Players = game:GetService("Players")
local Drone = {}
Drone.__index = Drone

local CONFIG = {
	MAX_SPEED = 30,
	TURN_SPEED = 6, -- Augmenté pour tracker les joueurs rapides
	PITCH_SPEED = 3, -- Augmenté pour lever/baisser la tête plus vite
	VISION_RANGE = 1000,
	FLIGHT_HEIGHT = 8,
}

-- Fonction utilitaire pour lisser (Lerp)
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

	-- Variables pour le lissage
	self.SmoothYaw = 0
	self.SmoothPitch = 0
	self.SmoothSpeed = 0

	local gyro = Instance.new("BodyGyro")
	gyro.MaxTorque = Vector3.new(400000, 400000, 400000)
	gyro.P = 4000 -- Plus rigide
	gyro.D = 400 -- Moins d'amortissement pour plus de réactivité
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
		localDir.X, -- 1: Erreur Gauche/Droite (-1 à 1)
		localDir.Y, -- 2: Erreur Haut/Bas (-1 à 1)
		localDir.Z, -- 3: Devant/Derrière
		math.tanh(dist / 100), -- 4: Distance
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
	-- 1. STABILISATION (PLUS RÉACTIVE)
	-- ====================================================
	-- On augmente le facteur (0.4) pour que le drone réagisse plus vite aux ordres du cerveau
	self.SmoothYaw = Lerp(self.SmoothYaw, outputs[2], 0.4)
	self.SmoothPitch = Lerp(self.SmoothPitch, outputs[3], 0.4)
	self.SmoothSpeed = Lerp(self.SmoothSpeed, outputs[1], 0.2)

	local yaw = self.SmoothYaw * CONFIG.TURN_SPEED * dt
	local pitch = self.SmoothPitch * CONFIG.PITCH_SPEED * dt

	self.Gyro.CFrame = self.Gyro.CFrame * CFrame.Angles(pitch, -yaw, 0)

	local forwardSpeed = self.SmoothSpeed * CONFIG.MAX_SPEED

	-- Gestion Altitude (Plus ferme)
	local currentHeight = self.RootPart.Position.Y
	local heightError = (CONFIG.FLIGHT_HEIGHT - currentHeight)
	local verticalForce = math.clamp(heightError * 8, -30, 30)

	local moveVector = self.RootPart.CFrame.LookVector * forwardSpeed
	self.Motor.Velocity = Vector3.new(moveVector.X, verticalForce, moveVector.Z)

	-- ====================================================
	-- 2. LOGIQUE DE FITNESS AMÉLIORÉE (GRADIENT)
	-- ====================================================
	if targetRoot then
		local dist = (targetRoot.Position - self.RootPart.Position).Magnitude

		-- ALIGNEMENT
		local alignmentX = math.abs(inputs[1]) -- 0 = parfait, 1 = mauvais
		local alignmentY = math.abs(inputs[2])
		local isFacing = inputs[3] < 0

		-- RECOMPENSE PROGRESSIVE (C'est la clé !)
		-- Au lieu de récompenser SI < 0.15, on récompense "Plus tu es proche de 0, plus tu gagnes"
		-- (1 - alignment) donne 1.0 si parfait, 0.5 si moyen, 0.0 si à 90 degrés
		if isFacing then
			local aimQuality = (1 - alignmentX) * (1 - alignmentY)
			-- Récompense continue pour encourager à affiner la visée
			self.Brain.Fitness += aimQuality * 0.2
		end

		-- CONDITION DE TIR STRICTE
		-- On tire seulement si on est VRAIMENT bien aligné (< 0.1)
		if alignmentX < 0.1 and alignmentY < 0.1 and isFacing and (os.clock() - self.LastShot > 0.5) then
			self:Fire()
			self.LastShot = os.clock()
		end

		-- GESTION DE LA DISTANCE
		if dist > 80 then
			self.Brain.Fitness -= 0.1 -- Punition plus forte pour le camping
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
	laser.Size = Vector3.new(0.2, 0.2, 8) -- Laser plus long
	laser.Color = Color3.fromRGB(255, 0, 50)
	laser.Material = Enum.Material.Neon
	laser.Anchored = true
	laser.CanCollide = false
	laser.CFrame = CFrame.new(origin + dir * 4, origin + dir * 10)
	laser.Parent = workspace
	game.Debris:AddItem(laser, 0.1)

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { self.Model }
	local hit = workspace:Raycast(origin, dir * CONFIG.VISION_RANGE, params)

	if hit and hit.Instance and hit.Instance.Parent and hit.Instance.Parent:FindFirstChild("Humanoid") then
		local char = hit.Instance.Parent
		if Players:GetPlayerFromCharacter(char) then
			local hum = char.Humanoid
			self.Brain.Fitness += 30
			if hum.Health > 0 then
				self.Brain.Fitness += 150 -- Enorme bonus pour toucher
				hum:TakeDamage(10)
			end
		end
	else
		-- Punition légère pour tir raté (pour qu'il n'arrête pas de tirer, mais qu'il préfère toucher)
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
		self.Brain.Fitness -= 100 -- Punition de mort sévère
		self.RootPart.Anchored = false
		self.Motor:Destroy()
		self.Gyro:Destroy()
		if self.Eye:FindFirstChild("WeldConstraint") then
			self.Eye.WeldConstraint:Destroy()
		end
	end
end

return Drone

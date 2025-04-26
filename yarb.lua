-- No more pairs
-- Modifiy Services Section
-- player: player:IsA("Player") in Util:Notify

local CONFIG = {
	DEBRIS_TIMES = {
		VELOCITY = 2,
		METEOR = 4.5,
		ORBITAL = 7.5,
		FOLLOWER = 15,
		SHOCKWAVE = 5
	},

	PHYSICS = {
		METEOR_SPEED = {-125, -75},
		ORBIT = {
			RADIUS = 10,
			SPEED = 0.025,
			COUNT = 7
		}
	},

	TIME_MAP = {
		morning = 8,
		noon = 12,
		afternoon = 16,
		evening = 19,
		midnight = 0,
		dawn = 6
	},

	SAFETY = {
		SCALE_RANGE = {0.1, 10},
		FOLLOWER_LIMIT = 20,
		MONEY_RANGE = {0, 10000}
	},

	TIME_WARP = {
		SLOW_FACTOR = 0.5,
		DURATION = 5
	},

	ELEMENTAL = {
		FIRE_DURATION = 10,
		ICE_DURATION = 8,
		LIGHTNING_DURATION = 6,
		ELEMENTAL_COOLDOWN = 30
	},

	ZONES = {
		SPAWN = {
			START_POS = Vector3.new(-100, 2, -100),
			SPACING = 25,
			COLUMNS = 8
		},
		TRIGGER = {
			ACTIVATION_TIME = 2,
			PROGRESS_BAR_HEIGHT = 8
		}
	}
}

local SERVICES = {
	Debris = game:GetService("Debris"),
	DataStoreService = game:GetService("DataStoreService"),
	TweenService = game:GetService("TweenService"),
	PathfindingService = game:GetService("PathfindingService"),
	RunService = game:GetService("RunService")
}

-- Non-service assets and created instances
local ASSETS = {
	WaveAnimation = Instance.new("Animation"),
	RemoteEvents = {
		ServerMessage = game.ReplicatedStorage:WaitForChild("RemoteEvents").ServerMessage
	}
}

-- DataStore configurations
local DATASTORES = {
	Main = SERVICES.DataStoreService:GetDataStore("Main")
}

-- Configure animation asset
ASSETS.WaveAnimation.AnimationId = "rbxassetid://507770239"
ASSETS.WaveAnimation.Parent = workspace


---------------------------------------------------------------------------------------------------
-- UTILITY MODULE
-- Reusable helper functions for common operations
---------------------------------------------------------------------------------------------------
local Util = {}

--[[
    Send a notification to a player's client
    @param player: Target player instance
    @param message: Message content to display
]]
function Util.Notify(player, message)
	if player and player:IsA("Player") and player:IsDescendantOf(game.Players) then
		ASSETS.RemoteEvents.ServerMessage:FireClient(player, message)
	end
end

--[[
    Validate and convert input to a constrained number
    @param input: Value to validate
    @param min: Minimum allowed value (optional)
    @param max: Maximum allowed value (optional)
    @return: (valid: boolean, value: number)
]]
function Util.ValidateNumber(input, min, max)
	local num = tonumber(input)
	local valid = num ~= nil
	if min then valid = valid and (num >= min) end
	if max then valid = valid and (num <= max) end
	return valid, num
end

--[[
    Create a basic part with configurable properties
    @param position: Initial CFrame position
    @param props: Table of part properties
    @return: Created Part instance
]]
function Util.CreatePart(position, props)
	local part = Instance.new("Part")
	part.CFrame = position
	part.Size = props.Size or Vector3.new(5, 5, 5)
	part.Color = props.Color or Color3.new(1, 1, 1)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Anchored = props.Anchored == nil or props.Anchored
	part.CanCollide = props.CanCollide == nil and true or props.CanCollide
	part.Shape = props.Shape or Enum.PartType.Block
	part.Parent = workspace
	return part
end

---------------------------------------------------------------------------------------------------
-- PHYSICS MODULE
-- Handles physics-related operations and special effects
---------------------------------------------------------------------------------------------------
local Physics = {}

--[[
    Apply linear velocity to a target part
    @param target: Part to apply velocity to
    @param attachment: Attachment point for force
    @param direction: Vector3 movement direction
    @param duration: Effect duration in seconds
]]
function Physics.ApplyVelocity(target, attachment, direction, duration)
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.VectorVelocity = direction
	velocity.MaxForce = math.huge
	velocity.Parent = target
	SERVICES.Debris:AddItem(velocity, duration or CONFIG.DEBRIS_TIMES.VELOCITY)
end

--[[
    Create explosion effect at specified position
    @param position: World position for explosion
    @return: Created Explosion instance
]]
function Physics.CreateExplosion(position)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 15
	explosion.BlastPressure = 1000
	explosion.Parent = workspace
	return explosion
end

--[[
    Create shockwave visual effect
    @param position: Center position for shockwave
    @return: Shockwave part instance
]]
function Physics.CreateShockwave(position)
	local shockwave = Util.CreatePart(CFrame.new(position), {
		Size = Vector3.new(0, 0, 0),
		Color = Color3.new(1, 1, 1),
		Anchored = true,
		CanCollide = false,
		Shape = Enum.PartType.Ball,
		Transparency = 0.5
	})

	SERVICES.TweenService:Create(shockwave, TweenInfo.new(CONFIG.DEBRIS_TIMES.SHOCKWAVE), {
		Size = Vector3.new(200, 200, 200),
		Transparency = 1
	}):Play()

	return shockwave
end

---------------------------------------------------------------------------------------------------
-- CHARACTER MODULE
-- Handles character manipulations and ragdoll effects
---------------------------------------------------------------------------------------------------
local Character = {}

--[[
    Replace motor joint with physics constraint
    @param joint: Motor6D joint to replace
]]
local function ReplaceJoint(joint)
	local att0 = Instance.new("Attachment")
	local att1 = Instance.new("Attachment")
	att0.CFrame = joint.C0
	att1.CFrame = joint.C1

	local constraint = Instance.new("BallSocketConstraint")
	constraint.Attachment0 = att0
	constraint.Attachment1 = att1
	constraint.TwistLimitsEnabled = true

	att0.Parent = joint.Part0
	att1.Parent = joint.Part1
	constraint.Parent = joint.Parent
	joint.Enabled = false
end

--[[
    Enable ragdoll physics on character
    @param char: Character model to ragdoll
]]
function Character.EnableRagdoll(char)
	for _, joint in char:GetDescendants() do
		if joint:IsA("Motor6D") then
			ReplaceJoint(joint)
		end
	end
	SERVICES.Remote.SetHumanState:FireClient(
		game.Players:GetPlayerFromCharacter(char),
		Enum.HumanoidStateType.Physics
	)
end

--[[
    Scale R15 character proportions
    @param humanoid: Humanoid to scale
    @param scale: Scaling factor to apply
]]
function Character.ScaleR15(humanoid, scale)
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		for _, value in humanoid:GetChildren() do
			if value:IsA("NumberValue") then
				value.Value = scale
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- ACTION HANDLERS
-- Individual handlers for player-activated commands and effects
---------------------------------------------------------------------------------------------------
local ActionHandlers = {}

--[[
    Instant death command handler
    @param player: Player executing command
]]
function ActionHandlers.die(player)
	player.Character.Humanoid.Health = 0
end

--[[
    Gravity adjustment handler
    @param player: Player executing command
    @param arg: Requested gravity value
]]
function ActionHandlers.grav(player, arg)
	local valid, value = Util.ValidateNumber(arg, 1)
	if valid then
		workspace.Gravity = value
		Util.Notify(player, "Gravity: "..value)
	end
end

--[[
    Teleportation handler
    @param player: Player executing command
    @param arg: Teleportation range
]]
function ActionHandlers.teleport(player, arg)
	local valid, range = Util.ValidateNumber(arg, 1)
	if valid then
		local offset = Vector3.new(math.random(-range, range), 0, math.random(-range, range))
		player.Character:PivotTo(player.Character.HumanoidRootPart.CFrame + offset)
	end
end

--[[
    Speed boost handler
    @param player: Player executing command
]]
function ActionHandlers.run(player)
	local root = player.Character.HumanoidRootPart
	Physics.ApplyVelocity(root, root.RootAttachment, root.CFrame.LookVector * 40, CONFIG.DEBRIS_TIMES.VELOCITY)
end

--[[
    Random part creation handler
    @param player: Player executing command
]]
function ActionHandlers.part(player)
	local lookDirection = player.Character.HumanoidRootPart.CFrame.LookVector
	Util.CreatePart(player.Character.HumanoidRootPart.CFrame + (lookDirection * 10) + Vector3.new(0, 2, 0), {
		Color = Color3.fromRGB(math.random(255), math.random(255), math.random(255)),
		Anchored = true
	})
end

--[[
    Data saving handler
    @param player: Player executing command
]]
function ActionHandlers.savelast(player)
	DATASTORES.Main:SetAsync("LastVisitor", player.Name)
	Util.Notify(player, "Saved as last visitor!")
end

--[[
    Data retrieval handler
    @param player: Player executing command
]]
function ActionHandlers.displaylast(player)
	local last = DATASTORES.Main:GetAsync("LastVisitor") or "None"
	Util.Notify(player, "Last visitor: "..last)
end

--[[
    Animation playback handler
    @param player: Player executing command
]]
function ActionHandlers.wave(player)
	local animator = player.Character.Humanoid.Animator
	local animation = animator:LoadAnimation(SERVICES.WaveAnim)
	animation:Play()
	task.wait(5)
	animation:Stop()
end

--[[
    Ragdoll activation handler
    @param player: Player executing command
]]
function ActionHandlers.ragdoll(player)
	Character.EnableRagdoll(player.Character)
end

--[[
    Gravity inversion handler
    @param player: Player executing command
]]
function ActionHandlers.gravity_swap(player)
	local humanoid = player.Character.Humanoid
	local root = player.Character.HumanoidRootPart

	local originalGravity = workspace.Gravity
	local originalJump = humanoid.JumpPower

	local antiGrav = Instance.new("ParticleEmitter")
	antiGrav.Color = ColorSequence.new(Color3.new(0.5, 1, 1))
	antiGrav.Size = NumberSequence.new(1)
	antiGrav.LightEmission = 0.8
	antiGrav.Parent = root

	humanoid.JumpPower = 0
	workspace.Gravity = -originalGravity

	task.delay(5, function()
		workspace.Gravity = originalGravity
		humanoid.JumpPower = originalJump
		antiGrav:Destroy()
	end)
end

--[[
    Elemental power activation handler
    @param player: Player executing command
]]
function ActionHandlers.elemental_power(player)
	local elements = {"fire", "ice", "lightning"}
	local chosenElement = elements[math.random(3)]
	local humanoid = player.Character.Humanoid

	local elementalEffect = Instance.new("ParticleEmitter")
	elementalEffect.Parent = player.Character.HumanoidRootPart

	if chosenElement == "fire" then
		elementalEffect.Color = ColorSequence.new(Color3.new(1, 0.3, 0))
		elementalEffect.LightEmission = 0.9
		elementalEffect.Size = NumberSequence.new(1.5)

		player.Character.Touched:Connect(function(part)
			if part.Parent:FindFirstChild("Humanoid") then
				part.Parent.Humanoid:TakeDamage(5)
				local fire = Instance.new("Fire")
				fire.Parent = part
				SERVICES.Debris:AddItem(fire, 3)
			end
		end)

	elseif chosenElement == "ice" then
		elementalEffect.Color = ColorSequence.new(Color3.new(0.5, 1, 1))
		elementalEffect.Transparency = NumberSequence.new(0.8)

		player.Character.Touched:Connect(function(part)
			part.Anchored = true
			part.Color = Color3.new(0.8, 1, 1)
			SERVICES.Debris:AddItem(part, 5)
		end)

	else
		elementalEffect.Color = ColorSequence.new(Color3.new(1, 1, 0))
		elementalEffect.LightEmission = 1

		local function strike(target)
			local beam = Instance.new("Beam")
			beam.Color = ColorSequence.new(Color3.new(1, 1, 0))
			beam.Attachment0 = player.Character.HumanoidRootPart.RootAttachment
			beam.Attachment1 = target.HumanoidRootPart.RootAttachment
			beam.Parent = workspace
			target.Humanoid:TakeDamage(15)
			SERVICES.Debris:AddItem(beam, 0.5)
		end

		player.Character.Touched:Connect(function(part)
			if part.Parent:FindFirstChild("Humanoid") then
				strike(part.Parent.Humanoid)
			end
		end)
	end

	SERVICES.Debris:AddItem(elementalEffect, CONFIG.ELEMENTAL[chosenElement:upper().."_DURATION"])
end

--[[
    Time warp effect handler
    @param player: Player executing command
]]
function ActionHandlers.time_warp(player)
	if not player.Character then return end
	local humanoidRoot = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then return end

	local originalGravity = workspace.Gravity
	local originalClock = game.Lighting.ClockTime
	local originalBrightness = game.Lighting.Brightness

	local timeDistortion = Instance.new("BlurEffect")
	timeDistortion.Size = 24
	timeDistortion.Parent = game.Lighting
	SERVICES.Debris:AddItem(timeDistortion, CONFIG.TIME_WARP.DURATION + 1)

	local timeParticles = Instance.new("ParticleEmitter")
	timeParticles.Texture = "rbxassetid://242487987"
	timeParticles.LightEmission = 0.8
	timeParticles.Size = NumberSequence.new(1.5)
	timeParticles.Parent = humanoidRoot
	SERVICES.Debris:AddItem(timeParticles, CONFIG.TIME_WARP.DURATION)

	local connection
	connection = SERVICES.RunService.Heartbeat:Connect(function()
		workspace.Gravity = originalGravity * 0.5
		game.Lighting.ClockTime = 25
		game.Lighting.Brightness = 0.3
	end)

	task.delay(CONFIG.TIME_WARP.DURATION, function()
		if connection then connection:Disconnect() end
		workspace.Gravity = originalGravity
		game.Lighting.ClockTime = originalClock
		game.Lighting.Brightness = originalBrightness
		timeDistortion = nil
		timeParticles = nil
		connection = nil
	end)
end

--[[
    Meteor shower handler
]]
function ActionHandlers.meteor()
	local function CreateMeteor()
		local meteor = Util.CreatePart(CFrame.new(math.random(-250, 250), 200, math.random(-250, 250)), {
			Color = Color3.fromRGB(255, 149, 0),
			Anchored = false
		})

		local attachment = Instance.new("Attachment")
		attachment.Parent = meteor

		Physics.ApplyVelocity(meteor, attachment, 
			Vector3.new(0, math.random(unpack(CONFIG.PHYSICS.METEOR_SPEED)), 0),
			CONFIG.DEBRIS_TIMES.METEOR
		)

		meteor.Touched:Once(function()
			Physics.CreateExplosion(meteor.Position)
			meteor:Destroy()
		end)
	end

	for _ = 1, 20 do CreateMeteor() end
end

--[[
    Orbital effect handler
    @param player: Player executing command
]]
function ActionHandlers.orbit(player)
	local root = player.Character.HumanoidRootPart
	local orbitals = {}

	local colorCount = CONFIG.PHYSICS.ORBIT.COUNT
	local colors = {}
	for i = 1, colorCount do
		local hue = (i-1)/colorCount
		colors[i] = Color3.fromHSV(hue, 0.8, 1)
	end

	local function CreateOrbital(parent, color)
		return Util.CreatePart(parent.CFrame, {
			Size = Vector3.new(3, 3, 3),
			Color = color,
			Shape = Enum.PartType.Ball,
			Anchored = true,
			CanCollide = false,
			Material = Enum.Material.Neon
		})
	end

	for i = 1, CONFIG.PHYSICS.ORBIT.COUNT do
		local orb = CreateOrbital(root, colors[i])
		table.insert(orbitals, orb)
		SERVICES.Debris:AddItem(orb, CONFIG.DEBRIS_TIMES.ORBITAL)
	end

	task.spawn(function()
		local angle = 0
		while #orbitals > 0 do
			for i, orb in orbitals do
				if orb.Parent then
					local offset = Vector3.new(
						math.cos(angle + (i-1)*(math.pi*2/#orbitals)) * CONFIG.PHYSICS.ORBIT.RADIUS,
						0,
						math.sin(angle + (i-1)*(math.pi*2/#orbitals)) * CONFIG.PHYSICS.ORBIT.RADIUS
					)
					orb.Position = root.Position + offset
				end
			end
			angle += CONFIG.PHYSICS.ORBIT.SPEED
			task.wait(0.01)
		end
	end)
end

--[[
    Time of day adjustment handler
    @param player: Player executing command
    @param arg: Time preset name
]]
function ActionHandlers.settime(player, arg)
	if CONFIG.TIME_MAP[arg] then
		game.Lighting.TimeOfDay = CONFIG.TIME_MAP[arg]
		Util.Notify(player, "Time: "..arg)
	end
end

--[[
    Character scaling handler
    @param player: Player executing command
    @param arg: Scaling factor
]]
function ActionHandlers.size(player, arg)
	local valid, value = Util.ValidateNumber(arg, unpack(CONFIG.SAFETY.SCALE_RANGE))
	if valid then
		Character.ScaleR15(player.Character.Humanoid, value)
		Util.Notify(player, "Scaled: "..value.."x")
	end
end

--[[
    Follower NPC creation handler
    @param player: Player executing command
    @param arg: Number of followers to create
]]
function ActionHandlers.followers(player, arg)
	local valid, count = Util.ValidateNumber(arg, 1, CONFIG.SAFETY.FOLLOWER_LIMIT)
	if not valid then return end

	local function CreateFollower()
		local npc = game.Players:CreateHumanoidModelFromUserId(26266254)
		npc:PivotTo(CFrame.new(math.random(-250, 250), 0, math.random(-250, 250)))
		npc.Parent = workspace
		return npc
	end

	local function SetupFollowerAI(npc, player)
		npc.Humanoid.Touched:Connect(function(hit)
			if hit.Parent:FindFirstChild("Humanoid") then
				hit.Parent.Humanoid:TakeDamage(100)
			end
		end)

		task.spawn(function()
			local path = SERVICES.Pathfinding:CreatePath()
			while npc.Parent and player.Character do
				path:ComputeAsync(npc.HumanoidRootPart.Position, player.Character.HumanoidRootPart.Position)
				local waypoints = path:GetWaypoints()
				local targetPos = waypoints[3] and waypoints[3].Position or player.Character.HumanoidRootPart.Position
				npc.Humanoid:MoveTo(targetPos)
				task.wait(0.5)
			end
		end)
	end

	for _ = 1, count do
		local follower = CreateFollower()
		SetupFollowerAI(follower, player)
		SERVICES.Debris:AddItem(follower, CONFIG.DEBRIS_TIMES.FOLLOWER)
	end
end

--[[
    Metatable demonstration handler
    @param player: Player executing command
    @param arg: Money value to set
]]
function ActionHandlers.moneymeta(player, arg)
	local data = setmetatable({}, {__index = {Money = 10}})
	Util.Notify(player, "Initial Money: "..data.Money)

	local valid, value = Util.ValidateNumber(arg, unpack(CONFIG.SAFETY.MONEY_RANGE))
	if valid then
		data.Money = value
		Util.Notify(player, "New Money: "..value)
	end
end

--[[
    Shockwave effect handler
    @param player: Player executing command
]]
function ActionHandlers.wraptime(player)
	local shockwave = Physics.CreateShockwave(player.Character.HumanoidRootPart.Position)
	local blur = Instance.new("BlurEffect")
	blur.Size = 15
	blur.Parent = game.Lighting

	SERVICES.TweenService:Create(blur, TweenInfo.new(5), {Size = 0}):Play()

	local humanoid = player.Character.Humanoid
	humanoid.JumpPower = 75
	workspace.Gravity = 30

	task.wait(8)
	workspace.Gravity = 196.2
	if humanoid then
		humanoid.JumpPower = 50
	end

	SERVICES.Debris:AddItem(shockwave, CONFIG.DEBRIS_TIMES.SHOCKWAVE)
	SERVICES.Debris:AddItem(blur, 5)
end

---------------------------------------------------------------------------------------------------
-- ZONE SYSTEM
-- Creates and manages interactive zones in the game world
---------------------------------------------------------------------------------------------------
local ZoneSystem = {}

--[[
    Create zone label GUI
    @param part: Zone part to label
    @param text: Display text
]]
local function CreateZoneLabel(part, text)
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = part
	billboard.Size = UDim2.new(4, 0, 1.5, 0)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 100
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = text
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.BackgroundTransparency = 1
	label.Parent = billboard
end

--[[
    Create interactive zone
    @param zoneConfig: Zone configuration table
    @param position: World position for zone
]]
function ZoneSystem.CreateZone(zoneConfig, position)
	local part = Util.CreatePart(CFrame.new(position), {
		Size = Vector3.new(10, 2, 10),
		Color = zoneConfig.Color,
		Anchored = true,
		CanCollide = true,
		Material = Enum.Material.Neon
	})
	part.Name = zoneConfig.Name

	CreateZoneLabel(part, zoneConfig.Name)

	local originalColor = part.Color
	local activePlayers = {}

	local function CleanupPlayer(player)
		if activePlayers[player] then
			if activePlayers[player].connection then
				activePlayers[player].connection:Disconnect()
			end
			if part:FindFirstChild("BillboardGui") then
				part.BillboardGui:Destroy()
			end
			SERVICES.TweenService:Create(part, TweenInfo.new(0.3), {Color = originalColor}):Play()
			activePlayers[player] = nil
		end
	end

	part.Touched:Connect(function(hit)
		local player = game.Players:GetPlayerFromCharacter(hit.Parent)
		if player and player.Character and not activePlayers[player] then
			local humanoidRoot = player.Character:FindFirstChild("HumanoidRootPart")
			if humanoidRoot then
				activePlayers[player] = {
					startTime = os.clock(),
					connection = nil
				}

				local gui = Instance.new("BillboardGui")
				gui.Adornee = part
				gui.Size = UDim2.new(4, 0, 0.5, 0)
				gui.StudsOffset = Vector3.new(0, 8, 0)
				gui.AlwaysOnTop = true
				gui.Parent = part

				local frame = Instance.new("Frame")
				frame.Size = UDim2.new(1, 0, 0.2, 0)
				frame.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
				frame.BorderSizePixel = 0
				frame.Parent = gui

				local progress = Instance.new("Frame")
				progress.Size = UDim2.new(0, 0, 1, 0)
				progress.BackgroundColor3 = Color3.new(0, 1, 0)
				progress.BorderSizePixel = 0
				progress.Parent = frame

				activePlayers[player].connection = SERVICES.RunService.Heartbeat:Connect(function()
					if not player.Character or not humanoidRoot.Parent then
						return CleanupPlayer(player)
					end

					local elapsed = os.clock() - activePlayers[player].startTime
					local progressAmount = math.clamp(elapsed / CONFIG.ZONES.TRIGGER.ACTIVATION_TIME, 0, 1)

					progress.Size = UDim2.new(progressAmount, 0, 1, 0)
					part.Color = originalColor:Lerp(Color3.new(0, 1, 0), progressAmount)

					if elapsed >= CONFIG.ZONES.TRIGGER.ACTIVATION_TIME then
						local handler = ActionHandlers[zoneConfig.Action]
						if handler then
							part.Color = Color3.fromRGB(math.random(0,255), math.random(0,255), math.random(0,255))
							SERVICES.TweenService:Create(part, TweenInfo.new(0.5), {Color = originalColor}):Play()

							if zoneConfig.Args then
								handler(player, zoneConfig.Args)
							else
								handler(player)
							end
						end
						CleanupPlayer(player)
					end
				end)
			end
		end
	end)

	part.TouchEnded:Connect(function(hit)
		local player = game.Players:GetPlayerFromCharacter(hit.Parent)
		CleanupPlayer(player)
	end)

	game.Players.PlayerRemoving:Connect(CleanupPlayer)
end

---------------------------------------------------------------------------------------------------
-- INITIALIZE ZONES
-- Create all configured interactive zones in the game world
---------------------------------------------------------------------------------------------------
local ZONE_CONFIG = {
	{Name = "Die Zone", Action = "die", Color = Color3.new(1,0,0)},
	{Name = "Grav Zone 10", Action = "grav", Args = 10, Color = Color3.new(0,1,0)},
	{Name = "Teleport Zone 200", Action = "teleport", Args = 200, Color = Color3.new(0,0,1)},
	{Name = "Run Zone", Action = "run", Color = Color3.new(1,1,0)},
	{Name = "Part Zone", Action = "part", Color = Color3.new(1,0,1)},
	{Name = "SaveLast Zone", Action = "savelast", Color = Color3.new(0,1,1)},
	{Name = "DisplayLast Zone", Action = "displaylast", Color = Color3.new(0.5,0.5,0.5)},
	{Name = "Wave Zone", Action = "wave", Color = Color3.new(0.5,0,0.5)},
	{Name = "Ragdoll Zone (DON'T TOUCH IT)", Action = "ragdoll", Color = Color3.new(0,0.5,0)},
	{Name = "Meteor Zone", Action = "meteor", Color = Color3.new(1,0.5,0)},
	{Name = "Orbit Zone", Action = "orbit", Color = Color3.new(0,0.5,0.5)},
	{Name = "Size Zone 3", Action = "size", Args = 3, Color = Color3.new(0.5,0,0)},
	{Name = "Followers Zone 10", Action = "followers", Args = 10, Color = Color3.new(0.3,0.3,0.3)},
	{Name = "Moneymeta Zone 120", Action = "moneymeta", Args = 25, Color = Color3.new(0.8,0.2,0.2)},
	{Name = "Wraptime Zone", Action = "wraptime", Color = Color3.new(0.2,0.8,0.2)},
	{Name = "Gravity Swap", Action = "gravity_swap", Color = Color3.fromRGB(100, 200, 255)},
	{Name = "Elemental Power", Action = "elemental_power", Color = Color3.fromRGB(200, 50, 150)},
	{Name = "Time Warp", Action = "time_warp", Color = Color3.fromRGB(50, 50, 100)}
}

-- Add time zones dynamically
for timeName in CONFIG.TIME_MAP do
	table.insert(ZONE_CONFIG, {
		Name = "Time: "..timeName,
		Action = "settime",
		Args = timeName,
		Color = Color3.new(0.2,0.2,0.8)
	})
end

-- Position and create all zones
local startPos = CONFIG.ZONES.SPAWN.START_POS
local spacing = CONFIG.ZONES.SPAWN.SPACING
local columns = CONFIG.ZONES.SPAWN.COLUMNS

for index, zone in ZONE_CONFIG do
	local row = math.floor((index-1)/columns)
	local column = (index-1) % columns
	local position = startPos + Vector3.new(column*spacing, 0, row*spacing)
	ZoneSystem.CreateZone(zone, position)
end

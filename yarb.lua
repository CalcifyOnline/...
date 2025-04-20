-- Hey bro please i don't understand What should i do ? Optimize the script or Change the whole idea or what ?
-- Ok i think u don't read the code that's why you think i don't modify or change it.. BTW i have already added some featuers like building Terrains not just destorying also optimized the code

-- Service Declarations
local Players = game:GetService("Players")          -- Player management
local Debris = game:GetService("Debris")            -- Object cleanup
local RunService = game:GetService("RunService")    -- Game loop
local TweenService = game:GetService("TweenService")-- Animation (reserved)

-- Localized Global Functions (optimization)
local floor = math.floor    -- Faster access to math functions
local random = math.random  -- Random number generator
local format = string.format-- String formatting
local Vec3 = Vector3.new    -- Vector3 constructor shorthand

--[[ Configuration Constants
    ENV - Central configuration table for all system parameters
    Contains world settings, physics values, effects, and UI properties ]]
local ENV = {
    World = {
        CellSize = 4,       -- Size of each terrain cube in studs
        Radius = 15,        -- Initial world generation radius
        MaxDepth = 3,       -- Layers destroyed per click
        MarkerTime = 0.3,   -- Impact marker duration
        
        -- Material definitions for different layers
        Materials = {
            Surface = {
                Material = Enum.Material.Grass,
                Color = BrickColor.new("Moss"),
                Texture = "rbxassetid://1312987257"
            },
            Underground = {
                Material = Enum.Material.Sand,
                Color = BrickColor.new("Sandstone"),
                Texture = "rbxassetid://1308385765"
            },
            Bedrock = {
                Material = Enum.Material.Slate,
                Color = BrickColor.new("Slate"),
                Texture = "rbxassetid://1308386819"
            },
        }
    },
    
    Physics = {
        Gravity = 98.1,         -- Custom gravity force
        Drag = 0.95,            -- Air resistance multiplier
        RotationDamp = 0.9,     -- Angular momentum reduction
        EjectForce = Vec3(random(-8,8), 18, random(-8,8)), -- Debris launch vector
    },
    
    Effects = {
        Dust = {
            Color = ColorSequence.new(Color3.fromRGB(225,215,190)),
            Size = NumberSequence.new(0.3,1.2),
            Lifetime = 1.5,      -- Particle lifespan in seconds
            Rate = 25,           -- Particles per second
        },
        Sound = {
            Id = "rbxassetid://130976108", -- Impact sound ID
            Volume = 0.4,
        },
    },
    
    UI = {
        Text = "LEFT CLICK TO BUILD | RIGHT CLICK TO DESTROY",
        Color = Color3.fromRGB(70,60,50),  -- Text color
        BgTrans = 0.9,          -- Background transparency
        Size = UDim2.new(0,280,0,90),      -- UI dimensions
        Position = UDim2.new(0.5,-140,1,-110), -- Screen position
    }
}

--[[ Utility Functions
    Coordinate conversion helpers for grid system ]]
    
-- Converts 3D grid position to string key
local function positionToKey(x, y, z)
    return format("%d:%d:%d", x, y, z)
end

-- Converts 2D column position to string key
local function columnToKey(x, z)
    return format("%d:%d", x, z)
end

--#############################################################################
-- TERRAIN SYSTEM
-- Handles world generation, block management, and destruction effects
--#############################################################################

local TerrainSystem = {}
TerrainSystem.__index = TerrainSystem

--[[ Constructor
    Initializes grid storage and generates initial world ]]
function TerrainSystem.new()
    local self = setmetatable({}, TerrainSystem)
    self.grid = {}      -- 3D grid storage [key: string] = {part, pos}
    self.columns = {}   -- 2D column height tracking [key: string] = number
    
    -- Generate initial terrain columns
    for x = -ENV.World.Radius, ENV.World.Radius do
        for z = -ENV.World.Radius, ENV.World.Radius do
            local height = random(4, 6)
            self.columns[columnToKey(x, z)] = height
            self:_generateColumn(x, z, height)
        end
    end
    return self
end

--[[ Private: Generates vertical column of blocks
    @param x,z    Column coordinates
    @param height Total blocks in column ]]
function TerrainSystem:_generateColumn(x, z, height)
    for y = 0, height do
        self:_createTerrainBlock(x, y, z, height)
    end
end

--[[ Private: Creates individual terrain block
    @param x,y,z          Block coordinates
    @param columnHeight   Total height of containing column ]]
function TerrainSystem:_createTerrainBlock(x, y, z, columnHeight)
    -- Determine material layer based on vertical position
    local layer = (y == columnHeight) and "Surface"
        or (y >= columnHeight - 2) and "Underground"
        or "Bedrock"
    local materialConfig = ENV.World.Materials[layer]

    -- Create and configure block part
    local block = Instance.new("Part")
    block.Size = Vec3(ENV.World.CellSize, ENV.World.CellSize, ENV.World.CellSize)
    block.Position = Vec3(
        x * ENV.World.CellSize,
        y * ENV.World.CellSize,
        z * ENV.World.CellSize
    )
    block.Anchored = true
    block.Material = materialConfig.Material
    block.BrickColor = materialConfig.Color
    block:SetAttribute("NaturalTerrain", true)
    block.Parent = workspace

    -- Apply repeating texture
    local texture = Instance.new("Texture")
    texture.Texture = materialConfig.Texture
    texture.StudsPerTileU = 2
    texture.StudsPerTileV = 2
    texture.Parent = block

    -- Store in grid
    local key = positionToKey(x, y, z)
    self.grid[key] = {
        part = block,
        pos = Vector3.new(x, y, z)
    }
end

--[[ Public: Adds new block to the world
    @param x,y,z Grid coordinates ]]
function TerrainSystem:addBlock(x, y, z)
    local key = positionToKey(x, y, z)
    
    -- Prevent duplicate blocks
    if self.grid[key] then return end

    -- Update column height tracking
    local columnKey = columnToKey(x, z)
    local currentHeight = self.columns[columnKey] or 0
    local newHeight = math.max(currentHeight, y)
    
    -- Initialize new columns as needed
    if not self.columns[columnKey] then
        self.columns[columnKey] = newHeight
    end

    self:_createTerrainBlock(x, y, z, newHeight)
end

--[[ Public: Destroys blocks at impact point
    @param hitPos  World position of impact
    @param normal  Surface normal vector ]]
function TerrainSystem:destroyBlock(hitPos, normal)
    -- Calculate grid position with normal offset
    local adjustedPos = hitPos - normal * 0.2
    local gridX = floor(adjustedPos.X / ENV.World.CellSize + 0.5)
    local gridY = floor(adjustedPos.Y / ENV.World.CellSize + 0.5)
    local gridZ = floor(adjustedPos.Z / ENV.World.CellSize + 0.5)
    
    -- Find base block
    local baseKey = positionToKey(gridX, gridY, gridZ)
    local baseBlock = self.grid[baseKey]
    if not baseBlock then return end

    -- Remove block and layers above
    for depth = 0, ENV.World.MaxDepth do
        local targetKey = positionToKey(
            baseBlock.pos.X,
            baseBlock.pos.Y + depth,
            baseBlock.pos.Z
        )
        
        if self.grid[targetKey] then
            self.grid[targetKey].part:Destroy()
            self.grid[targetKey] = nil
        end
    end

    self:_playDestructionEffects(baseBlock.pos * ENV.World.CellSize)
end

--[[ Private: Creates visual/audio effects for destruction
    @param worldPos Center position for effects ]]
function TerrainSystem:_playDestructionEffects(worldPos)
    -- Dust particles container
    local effectPart = Instance.new("Part")
    effectPart.Size = Vec3(2, 2, 2)
    effectPart.CFrame = CFrame.new(worldPos)
    effectPart.Transparency = 1
    effectPart.Anchored = true
    effectPart.CanCollide = false
    effectPart.Parent = workspace

    -- Particle emitter configuration
    local emitter = Instance.new("ParticleEmitter")
    emitter.Color = ENV.Effects.Dust.Color
    emitter.Size = ENV.Effects.Dust.Size
    emitter.Lifetime = NumberRange.new(ENV.Effects.Dust.Lifetime)
    emitter.Rate = ENV.Effects.Dust.Rate
    emitter.Parent = effectPart
    Debris:AddItem(effectPart, ENV.Effects.Dust.Lifetime)

    -- Debris fragment
    local fragment = Instance.new("Part")
    fragment.Size = Vec3(
        random(2, ENV.World.CellSize),
        random(2, ENV.World.CellSize),
        random(2, ENV.World.CellSize)
    )
    fragment.CFrame = CFrame.new(worldPos)
    fragment.Material = Enum.Material.Slate
    fragment.BrickColor = BrickColor.new("Slate")
    fragment.Parent = workspace
    fragment:ApplyImpulse(ENV.Physics.EjectForce)
    Debris:AddItem(fragment, 6)

    -- Impact sound
    local soundEffect = Instance.new("Sound")
    soundEffect.SoundId = ENV.Effects.Sound.Id
    soundEffect.Volume = ENV.Effects.Sound.Volume
    soundEffect.Parent = fragment
    soundEffect:Play()
    Debris:AddItem(soundEffect, 3)
end

--#############################################################################
-- PHYSICS CONTROLLER
-- Applies custom physics to unanchored parts
--#############################################################################

local PhysicsController = {}
PhysicsController.__index = PhysicsController

function PhysicsController.new()
    return setmetatable({ active = true }, PhysicsController)
end

--[[ Main physics loop
    Applies gravity, drag, and rotation damping ]]
function PhysicsController:start()
    RunService.Heartbeat:Connect(function(deltaTime)
        if not self.active then return end
        
        for _, part in ipairs(workspace:GetChildren()) do
            if part:IsA("BasePart") and not part.Anchored then
                -- Apply gravity
                part.Velocity += Vec3(0, -ENV.Physics.Gravity, 0) * deltaTime
                
                -- Apply air resistance
                part.Velocity *= ENV.Physics.Drag
                
                -- Reduce rotation over time
                part.RotVelocity *= ENV.Physics.RotationDamp
            end
        end
    end)
end

--#############################################################################
-- INPUT HANDLER
-- Manages player input for building/destruction
--#############################################################################

local InputHandler = {}
InputHandler.__index = InputHandler

function InputHandler.new(terrainSystem)
    return setmetatable({
        terrain = terrainSystem
    }, InputHandler)
end

--[[ Initializes input bindings ]]
function InputHandler:enable()
    local player = Players.LocalPlayer
    local mouse = player:GetMouse()

    -- Right-click destruction handler
    mouse.Button2Down:Connect(function()
        local ray = Ray.new(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 100)
        local hitPart, hitPosition, hitNormal = workspace:FindPartOnRay(ray)

        if hitPart and hitPart:GetAttribute("NaturalTerrain") then
            -- Create temporary impact marker
            local marker = Instance.new("Part")
            marker.Size = Vec3(0.3, 0.3, 0.3)
            marker.CFrame = CFrame.new(hitPosition)
            marker.Color = Color3.fromRGB(150,100,50)
            marker.Material = Enum.Material.Sand
            marker.Transparency = 0.5
            marker.Anchored = true
            marker.Parent = workspace
            Debris:AddItem(marker, ENV.World.MarkerTime)

            self.terrain:destroyBlock(hitPosition, hitNormal)
        end
    end)

    -- Left-click building handler
    mouse.Button1Down:Connect(function()
        local ray = Ray.new(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 100)
        local hitPart, hitPosition, hitNormal = workspace:FindPartOnRay(ray)
        
        -- Default to air placement if no surface hit
        local placementPos = hitPosition or (mouse.UnitRay.Origin + mouse.UnitRay.Direction * 50)
        local placementNormal = hitNormal or Vector3.new(0, 1, 0)

        -- Convert to grid coordinates
        local gridX = floor(placementPos.X / ENV.World.CellSize + 0.5)
        local gridY = floor(placementPos.Y / ENV.World.CellSize + 0.5)
        local gridZ = floor(placementPos.Z / ENV.World.CellSize + 0.5)
        
        -- Calculate new block position based on surface normal
        local newX = gridX + floor(placementNormal.X + 0.5)
        local newY = gridY + floor(placementNormal.Y + 0.5)
        local newZ = gridZ + floor(placementNormal.Z + 0.5)

        self.terrain:addBlock(newX, newY, newZ)
    end)
end

--#############################################################################
-- USER INTERFACE
-- Handles on-screen instructions display
--#############################################################################

local Interface = {}
Interface.__index = Interface

function Interface.new()
    return setmetatable({}, Interface)
end

--[[ Creates and positions UI elements ]]
function Interface:load()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TerrainInstructions"
    screenGui.ResetOnSpawn = false

    -- Main container frame
    local frame = Instance.new("Frame")
    frame.Size = ENV.UI.Size
    frame.Position = ENV.UI.Position
    frame.BackgroundColor3 = Color3.fromRGB(240,235,230)
    frame.BackgroundTransparency = ENV.UI.BgTrans
    frame.Parent = screenGui

    -- Instruction text label
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Text = ENV.UI.Text
    label.TextColor3 = ENV.UI.Color
    label.Font = Enum.Font.SourceSans
    label.TextSize = 16
    label.BackgroundTransparency = 1
    label.Parent = frame

    screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--#############################################################################
-- INITIALIZATION
--#############################################################################

-- Create system instances
local terrainSystem = TerrainSystem.new()
local physicsController = PhysicsController.new()
local inputHandler = InputHandler.new(terrainSystem)
local interface = Interface.new()

-- Start systems
physicsController:start()
inputHandler:enable()
interface:load()

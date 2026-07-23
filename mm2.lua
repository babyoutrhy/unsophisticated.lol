-- Ozen UI
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/rhywme/UI-Libraries/main/Unsophisticated-Ui/source.lua"))()
local Window = Library:CreateWindow("Murder Mystery 2")

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StatsService = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

-- Create Main tab
local MainTab = Window:AddTab("Main")
local TeleportTab = Window:AddTab("Teleport")

-- Auto Farm State Management
local autofarmEnabled = false
local collectSpeed = 25
local collectionDelay = 0.5
local autofarmThread = nil  -- Track the autofarm thread

-- Fling system variables
local isFlinging = false
local flingTarget = nil

-- Hitbox modification variables
local modifiedCoins = {}
local coinWatcher = nil

-- Laying down system variables
local isLayingDown = false
local layingDownConnection = nil
local antiVoidPart = nil
local bodyGyro = nil
local bodyPosition = nil
local originalCollide = {}

-- ESP system variables
local espEnabled = false
local playerHighlights = {}
local playerConnections = {}
local espMainConnection = nil

-- Lobby position and teleport settings
local LOBBY_POSITION = Vector3.new(-4958, 305, 58)
local INSTANT_TELEPORT_DISTANCE = 500  -- If coin is more than 500 studs away, use instant teleport

-- Coin collection tracking
local coinAttempts = {}  -- Track attempts per coin
local MAX_ATTEMPTS_PER_COIN = 1  -- Skip coin after 3 failed attempts
local skippedCoins = {}  -- Track skipped coins to avoid retrying

-- Debug mode
local DEBUG_MODE = true  -- Set to false to disable debug prints

-- Cache for performance
local lastCoinContainerCheck = 0
local coinContainerCache = nil
local coinContainerCacheTime = 0
local CACHE_DURATION = 5  -- Cache coin container for 5 seconds

-- Text definitions for debug messages
local TEXT_TAGS = {
    INFO = "[INFO]", SUCCESS = "[SUCCESS]", WARNING = "[WARNING]", ERROR = "[ERROR]", MOVING = "[MOVING]",
    COIN = "[COIN]", SEARCH = "[SEARCH]", WAITING = "[WAITING]", DEAD = "[DEAD]", ALIVE = "[ALIVE]",
    COLLECT = "[COLLECT]", CANCEL = "[CANCEL]", GAMEPASS = "[GAMEPASS]", LIMIT = "[LIMIT]", RESET = "[RESET]", 
    COUNTER = "[COUNTER]", FLING = "[FLING]", MURDERER = "[MURDERER]", MULTIPLE = "[MULTIPLE]", SPECTATOR = "[SPECTATOR]",
    HITBOX = "[HITBOX]", LAYING_DOWN = "[LAYING_DOWN]", TELEPORT = "[TELEPORT]", INSTANT_TELEPORT = "[INSTANT_TELEPORT]",
    SKIP = "[SKIP]", ATTEMPT = "[ATTEMPT]", ESP = "[ESP]"
}

-- Get player root part function
local function GetRoot(player)
    local character = player.Character
    if character and character.Parent and character:IsDescendantOf(workspace) and character:FindFirstChild("HumanoidRootPart") then
        return character.HumanoidRootPart
    end
    return nil
end

-- Get ping function for prediction
local function GetPing()
    local networkStats = StatsService:FindFirstChild("Network")
    if networkStats then
        local pingStat = networkStats:FindFirstChild("ServerStatsItem")
        if pingStat then
            local pingValue = pingStat:GetValueString()
            local pingNumber = tonumber(pingValue:match("%d+"))
            if pingNumber then
                return pingNumber / 1000  -- Convert to seconds
            end
        end
    end
    return 0.1  -- Default to 100ms if can't get ping
end

-- Advanced prediction teleport function
local function PredictionTP(targetPlayer, method)
    local root = GetRoot(targetPlayer)
    if not root then return false end
    
    local localRoot = GetRoot(Players.LocalPlayer)
    if not localRoot then return false end
    
    local pos = root.Position
    local vel = root.Velocity
    local ping = GetPing()
    
    -- Calculate predicted position with ping compensation
    local predictedPosition = Vector3.new(
        pos.X + (vel.X * (ping * 3.5)),
        pos.Y + (vel.Y * (ping * 2)),
        pos.Z + (vel.Z * (ping * 3.5))
    )
    
    -- Teleport to predicted position
    localRoot.CFrame = CFrame.new(predictedPosition)
    
    if method == "safe" then
        task.wait()
        localRoot.CFrame = CFrame.new(pos)
        task.wait()
        localRoot.CFrame = CFrame.new(predictedPosition)
    end
    
    return true
end

-- Safe teleport to lobby function
local function TeleportToLobby()
    local player = Players.LocalPlayer
    local character = player.Character
    
    if not character then
        if DEBUG_MODE then
            print("[Teleport] No character found for teleport")
        end
        return false
    end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then
        if DEBUG_MODE then
            print("[Teleport] No HumanoidRootPart found for teleport")
        end
        return false
    end
    
    -- Disable laying down first if active
    if isLayingDown then
        DisableLayingDown()
    end
    
    -- Wait a frame for laying down to fully disable
    task.wait(0.1)
    
    -- Teleport to lobby position
    humanoidRootPart.CFrame = CFrame.new(LOBBY_POSITION)
    
    if DEBUG_MODE then
        print("[Teleport] Successfully teleported to lobby")
    end
    
    return true
end

-- Instant teleport to coin function
local function InstantTeleportToCoin(coin)
    local player = Players.LocalPlayer
    local character = player.Character
    if not character then return false end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end
    
    -- Position character UNDER the coin (3 units below)
    local targetPosition = coin.Position + Vector3.new(0, -3, 0)
    
    -- Instant teleport with laying down rotation
    humanoidRootPart.CFrame = CFrame.new(targetPosition) * CFrame.Angles(math.rad(90), 0, 0)
    
    if DEBUG_MODE then
        print("[Instant Teleport] Teleported directly to coin")
    end
    
    return true
end

-- Reset coin tracking when round starts
local function ResetCoinTracking()
    coinAttempts = {}
    skippedCoins = {}
    if DEBUG_MODE then
        print("[Coin Tracking] Reset coin attempt tracking")
    end
end

-- Check if coin should be skipped
local function ShouldSkipCoin(coin)
    if skippedCoins[coin] then
        return true
    end
    
    if coinAttempts[coin] and coinAttempts[coin] >= MAX_ATTEMPTS_PER_COIN then
        skippedCoins[coin] = true
        if DEBUG_MODE then
            print("[Coin Tracking] Skipping coin after " .. coinAttempts[coin] .. " failed attempts")
        end
        return true
    end
    
    return false
end

-- Increment coin attempt counter
local function IncrementCoinAttempt(coin)
    if not coinAttempts[coin] then
        coinAttempts[coin] = 0
    end
    coinAttempts[coin] = coinAttempts[coin] + 1
    
    if DEBUG_MODE then
        print("[Coin Tracking] Coin attempt " .. coinAttempts[coin] .. "/" .. MAX_ATTEMPTS_PER_COIN)
    end
end

-- Player role detection function
local function getPlayerRole(player)
    if not player or not player.Character then
        return "Unknown"
    end
    
    -- Method 1: Check backpack first (most reliable)
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        if backpack:FindFirstChild("Gun") then
            return "Sheriff"
        elseif backpack:FindFirstChild("Knife") then
            return "Murderer"
        end
    end
    
    -- Method 2: Check character for equipped weapons
    local character = player.Character
    for _, item in ipairs(character:GetChildren()) do
        if item:IsA("Tool") then
            if item.Name == "Gun" then
                return "Sheriff"
            elseif item.Name == "Knife" then
                return "Murderer"
            end
        end
    end
    
    return "Innocent"
end

-- Find murderer function
local function FindMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            local role = getPlayerRole(player)
            if role == "Murderer" then
                return player
            end
        end
    end
    return nil
end

-- Get all murderers function
local function GetAllMurderers()
    local murderers = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            local role = getPlayerRole(player)
            if role == "Murderer" then
                table.insert(murderers, player)
            end
        end
    end
    return murderers
end

-- Check if murderer is still alive (has knife)
local function IsMurdererAlive(murderer)
    if not murderer then return false end
    return getPlayerRole(murderer) == "Murderer"
end

-- Check if local player is murderer
local function IsLocalPlayerMurderer()
    return getPlayerRole(Players.LocalPlayer) == "Murderer"
end

-- Check if player is in spectator mode
local function IsSpectator(player)
    local character = player.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    return humanoid.NameDisplayDistance == 100
end

-- Check if player is alive
local function IsPlayerAlive(player)
    if not player then player = Players.LocalPlayer end
    
    local character = player.Character
    if not character or not character.Parent then 
        return false 
    end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then 
        return false 
    end
    
    -- Check multiple conditions for death
    if humanoid.Health <= 0 then
        return false
    end
    
    -- Check NameDisplayDistance (spectator mode)
    if humanoid.NameDisplayDistance == 100 then
        return false
    end
    
    -- Check if humanoid root part exists and is in workspace
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp or not hrp:IsDescendantOf(workspace) then
        return false
    end
    
    return true
end

-- Improved stable laying down functions with no collision
local function EnableLayingDown()
    if isLayingDown then return end
    
    local player = Players.LocalPlayer
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not humanoidRootPart then return end
    
    -- Disable animations to prevent collision
    for _, track in pairs(humanoid:GetPlayingAnimationTracks()) do
        track:Stop()
    end
    
    -- Store original CanCollide states and disable collision
    originalCollide = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            originalCollide[part] = part.CanCollide
            part.CanCollide = false
        end
    end
    
    -- Create invisible platform to prevent falling
    if not antiVoidPart then
        antiVoidPart = Instance.new("Part")
        antiVoidPart.Name = "AntiVoidPlatform"
        antiVoidPart.Size = Vector3.new(10, 1, 10)
        antiVoidPart.Transparency = 1
        antiVoidPart.Anchored = true
        antiVoidPart.CanCollide = true
        antiVoidPart.Parent = workspace
    end
    
    -- Remove any existing body movers
    if bodyGyro then
        bodyGyro:Destroy()
        bodyGyro = nil
    end
    if bodyPosition then
        bodyPosition:Destroy()
        bodyPosition = nil
    end
    
    -- Set character to lay flat
    humanoid.PlatformStand = true
    
    -- Create powerful BodyGyro to maintain flat rotation (90 degrees on X-axis)
    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(4000000, 4000000, 4000000) -- Much stronger torque
    bodyGyro.P = 50000 -- Higher P value for stronger correction
    bodyGyro.D = 1000 -- Higher D value for damping
    bodyGyro.CFrame = humanoidRootPart.CFrame * CFrame.Angles(math.rad(90), 0, 0)
    bodyGyro.Parent = humanoidRootPart
    
    -- Create BodyPosition to prevent falling and maintain position
    bodyPosition = Instance.new("BodyPosition")
    bodyPosition.MaxForce = Vector3.new(4000000, 4000000, 4000000) -- Much stronger force
    bodyPosition.Position = humanoidRootPart.Position
    bodyPosition.P = 50000 -- Higher P value
    bodyPosition.D = 1000 -- Higher D value
    bodyPosition.Parent = humanoidRootPart
    
    isLayingDown = true
    
    -- Start steady position maintenance
    layingDownConnection = RunService.Heartbeat:Connect(function()
        if not isLayingDown or not humanoidRootPart or not humanoidRootPart.Parent then
            if layingDownConnection then
                layingDownConnection:Disconnect()
                layingDownConnection = nil
            end
            return
        end
        
        -- Update anti-void platform position
        if antiVoidPart then
            antiVoidPart.Position = Vector3.new(humanoidRootPart.Position.X, humanoidRootPart.Position.Y - 3, humanoidRootPart.Position.Z)
        end
        
        -- Update BodyGyro to maintain flat rotation without any additional rotation
        if bodyGyro and bodyGyro.Parent then
            -- Force the rotation to stay exactly flat
            bodyGyro.CFrame = CFrame.new(humanoidRootPart.Position) * CFrame.Angles(math.rad(90), 0, 0)
        end
        
        -- Update BodyPosition to maintain current position and prevent falling
        if bodyPosition and bodyPosition.Parent then
            bodyPosition.Position = humanoidRootPart.Position
        end
        
        -- Cancel any velocity that might cause movement or rotation
        humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
        humanoidRootPart.RotVelocity = Vector3.new(0, 0, 0)
        
        -- Ensure no collision
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
    
    if DEBUG_MODE then
        print("[Laying Down] Character is now laying flat (No Collision Method)")
    end
end

local function DisableLayingDown()
    if not isLayingDown then return end
    
    -- Disconnect the update loop
    if layingDownConnection then
        layingDownConnection:Disconnect()
        layingDownConnection = nil
    end
    
    -- Remove body movers
    if bodyGyro then
        bodyGyro:Destroy()
        bodyGyro = nil
    end
    if bodyPosition then
        bodyPosition:Destroy()
        bodyPosition = nil
    end
    
    -- Restore original collision states
    for part, collideState in pairs(originalCollide) do
        if part and part.Parent then
            part.CanCollide = collideState
        end
    end
    originalCollide = {}
    
    -- Remove anti-void platform
    if antiVoidPart then
        antiVoidPart:Destroy()
        antiVoidPart = nil
    end
    
    -- Restore normal state
    local player = Players.LocalPlayer
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChild("Humanoid")
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        
        if humanoid then
            humanoid.PlatformStand = false
        end
        
        if humanoidRootPart then
            -- Reset rotation to upright position
            local currentPosition = humanoidRootPart.Position
            humanoidRootPart.CFrame = CFrame.new(currentPosition)
        end
    end
    
    isLayingDown = false
    
    if DEBUG_MODE then
        print("[Laying Down] Character is now standing")
    end
end

-- Working Hitbox Modification Functions
local function modifyCoin(coin)
    if coin:IsA("BasePart") and not modifiedCoins[coin] then
        modifiedCoins[coin] = {
            Size = coin.Size,
            Transparency = coin.Transparency,
            CanCollide = coin.CanCollide
        }
        coin.Size = Vector3.new(8, 8, 8)
        coin.CanCollide = false
    end
end

local function restoreCoins()
    for coin, data in pairs(modifiedCoins) do
        if coin.Parent then
            coin.Size = data.Size
            coin.Transparency = data.Transparency
            coin.CanCollide = data.CanCollide
        end
    end
    modifiedCoins = {}
end

-- Main Resize Logic
local function enableResize()
    if DEBUG_MODE then
        print("[Hitbox Mod] Enabling larger candy hitboxes (8x8x8)...")
    end
    
    -- Process existing coins
    for _, coin in ipairs(workspace:GetDescendants()) do
        if coin.Name == "Coin_Server" then
            modifyCoin(coin)
        end
    end
    
    -- Watch for new coins
    if coinWatcher then 
        coinWatcher:Disconnect() 
    end
    
    coinWatcher = workspace.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "Coin_Server" then
            modifyCoin(descendant)
        end
    end)
end

local function disableResize()
    if DEBUG_MODE then
        print("[Hitbox Mod] Reverting candy hitboxes to default...")
    end
    
    if coinWatcher then 
        coinWatcher:Disconnect()
        coinWatcher = nil
    end
    
    restoreCoins()
end

-- Advanced fling function with ping-based prediction
local function StartFlingMurderer(debugPrint)
    if isFlinging then return end
    
    isFlinging = true
    local player = Players.LocalPlayer
    
    -- Find murderer first
    flingTarget = FindMurderer()
    if not flingTarget or not IsMurdererAlive(flingTarget) then
        if debugPrint then
            debugPrint("No valid murderer found for flinging!", "[MURDERER]")
        end
        isFlinging = false
        return
    end
    
    if debugPrint then
        debugPrint("Starting advanced prediction fling...", "[FLING]")
    end
    
    local function fling()
        local lp = Players.LocalPlayer
        local flingForce = 50000 -- Increased fling force
        local maxDistance = 50 -- Maximum distance to track murderer
        
        while isFlinging and autofarmEnabled and flingTarget and IsMurdererAlive(flingTarget) and IsSpectator(lp) do
            local c = lp.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            
            -- Wait until we have valid character and HRP
            while isFlinging and not (c and c.Parent and hrp and hrp.Parent) do
                RunService.Heartbeat:Wait()
                c = lp.Character
                hrp = c and c:FindFirstChild("HumanoidRootPart")
            end
            
            if isFlinging then
                local murdererRoot = GetRoot(flingTarget)
                if murdererRoot and murdererRoot:IsDescendantOf(workspace) then
                    -- Calculate distance to murderer
                    local distance = (hrp.Position - murdererRoot.Position).Magnitude
                    
                    -- Only fling if within reasonable distance
                    if distance <= maxDistance then
                        -- Use advanced prediction teleport with ping compensation
                        PredictionTP(flingTarget, "safe")
                        
                        -- Apply powerful fling force in multiple directions
                        hrp.Velocity = Vector3.new(
                            math.random(-flingForce, flingForce),
                            math.random(flingForce/2, flingForce),
                            math.random(-flingForce, flingForce)
                        )
                        
                        -- Additional rotational force
                        hrp.RotVelocity = Vector3.new(
                            math.random(-100, 100),
                            math.random(-100, 100),
                            math.random(-100, 100)
                        )
                        
                        if DEBUG_MODE then
                            local ping = GetPing() * 1000  -- Convert to milliseconds for display
                            debugPrint(("Flinging murderer | Distance: %.1f | Ping: %.0fms"):format(distance, ping), "[FLING]")
                        end
                    else
                        if DEBUG_MODE then
                            debugPrint(("Murderer too far | Distance: %.1f"):format(distance), "[FLING]")
                        end
                        -- Use prediction to teleport closer if too far
                        PredictionTP(flingTarget, "normal")
                    end
                else
                    if DEBUG_MODE then
                        debugPrint("Murderer root part not found", "[FLING]")
                    end
                end
            end
            
            RunService.Heartbeat:Wait()
        end
        
        isFlinging = false
        flingTarget = nil
        if debugPrint then
            debugPrint("Spectator fling ended", "[FLING]")
        end
    end
    
    -- Start fling in a new thread
    task.spawn(fling)
end

-- ESP Functions
local function cleanupPlayerESP(player)
    -- Clean up highlight
    local highlight = playerHighlights[player]
    if highlight then
        if highlight:IsA("Highlight") then
            highlight:Destroy()
        end
        playerHighlights[player] = nil
    end
    
    -- Clean up connections
    local connections = playerConnections[player]
    if connections then
        -- Handle both connection objects and tables of connections
        if type(connections) == "table" then
            for _, connection in pairs(connections) do
                -- Check if connection is valid before trying to disconnect
                if connection and type(connection) == "userdata" then
                    -- Use pcall to safely disconnect
                    local success, err = pcall(function()
                        if connection.Disconnect then
                            connection:Disconnect()
                        end
                    end)
                    if not success and DEBUG_MODE then
                        print(TEXT_TAGS.ERROR .. " Failed to disconnect connection: " .. tostring(err))
                    end
                end
            end
        elseif connections.Disconnect then
            -- Handle single connection object
            local success, err = pcall(function() 
                connections:Disconnect() 
            end)
            if not success and DEBUG_MODE then
                print(TEXT_TAGS.ERROR .. " Failed to disconnect connection: " .. tostring(err))
            end
        end
        
        playerConnections[player] = nil
    end
end

local function getPlayerColor(player)
    if not player or not player:IsDescendantOf(game) then
        return Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200) -- Default white
    end
    
    local character = player.Character
    if not character then
        return Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200) -- White for no character
    end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then
        return Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200) -- White for no humanoid
    end
    
    -- Check if player is dead
    if humanoid.NameDisplayDistance == 100 or humanoid.Health <= 0 then
        return Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200) -- White for dead
    end
    
    -- Check player's role
    local function hasTool(player, toolName)
        -- Check backpack
        local backpack = player:FindFirstChild("Backpack")
        if backpack and backpack:FindFirstChild(toolName) then
            return true
        end
        
        -- Check character
        local character = player.Character
        if character then
            for _, item in ipairs(character:GetChildren()) do
                if item:IsA("Tool") and item.Name == toolName then
                    return true
                end
            end
        end
        return false
    end
    
    if hasTool(player, "Knife") then
        return Color3.fromRGB(255, 50, 50), Color3.fromRGB(200, 0, 0) -- Red for murderer
    elseif hasTool(player, "Gun") then
        return Color3.fromRGB(50, 50, 255), Color3.fromRGB(0, 0, 200) -- Blue for sheriff
    else
        return Color3.fromRGB(50, 255, 50), Color3.fromRGB(0, 200, 0) -- Green for innocent/alive
    end
end

local function createPlayerHighlight(player)
    if player == Players.LocalPlayer then return nil end
    if not player:IsDescendantOf(game) then return nil end
    
    -- Clean up any existing highlight first
    cleanupPlayerESP(player)
    
    local character = player.Character
    if not character then return nil end
    
    local highlight = Instance.new("Highlight")
    highlight.Name = player.Name .. "_ESP"
    highlight.FillTransparency = 0.67
    highlight.OutlineTransparency = 1
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = true
    highlight.Adornee = character
    highlight.Parent = character
    
    -- Set initial color
    local fillColor, outlineColor = getPlayerColor(player)
    highlight.FillColor = fillColor
    highlight.OutlineColor = outlineColor
    
    playerHighlights[player] = highlight
    return highlight
end

local function setupPlayerESP(player)
    if player == Players.LocalPlayer then return end
    if not espEnabled then return end
    
    -- Clean up any existing connections first
    if playerConnections[player] then
        cleanupPlayerESP(player)
    end
    
    -- Create initial highlight if character exists
    if player.Character then
        createPlayerHighlight(player)
    end
    
    -- Set up connections
    local connections = {}
    
    -- Character added event
    connections.characterAdded = player.CharacterAdded:Connect(function(character)
        if not espEnabled then return end
        
        -- Wait for character to fully load
        task.wait(0.5)
        
        if not espEnabled or not player:IsDescendantOf(game) then return end
        
        -- Create highlight for new character
        local highlight = createPlayerHighlight(player)
        if highlight then
            -- Force update color after a short delay
            task.wait(0.1)
            local fillColor, outlineColor = getPlayerColor(player)
            highlight.FillColor = fillColor
            highlight.OutlineColor = outlineColor
        end
    end)
    
    -- Character removed event
    connections.characterRemoving = player.CharacterRemoving:Connect(function()
        if not espEnabled then return end
        
        local highlight = playerHighlights[player]
        if highlight then
            highlight.Enabled = false
            highlight.Adornee = nil
        end
    end)
    
    -- Player removed event
    connections.playerRemoving = player.AncestryChanged:Connect(function()
        if not player:IsDescendantOf(game) then
            cleanupPlayerESP(player)
        end
    end)
    
    playerConnections[player] = connections
end

local function updateAllESP()
    if not espEnabled then return end
    
    for player, highlight in pairs(playerHighlights) do
        if player and player:IsDescendantOf(game) and highlight and highlight.Parent then
            local character = player.Character
            if character then
                -- Update highlight position
                if highlight.Adornee ~= character then
                    highlight.Adornee = character
                    highlight.Parent = character
                end
                
                -- Update color
                local fillColor, outlineColor = getPlayerColor(player)
                highlight.FillColor = fillColor
                highlight.OutlineColor = outlineColor
                highlight.Enabled = true
            else
                highlight.Enabled = false
            end
        else
            -- Player left or highlight invalid, clean up
            cleanupPlayerESP(player)
        end
    end
end

local function enableESP()
    if espEnabled then return end
    
    espEnabled = true
    
    if DEBUG_MODE then
        print(TEXT_TAGS.ESP .. " Enabling ESP...")
    end
    
    -- Clean up any existing state first
    for player, _ in pairs(playerHighlights) do
        cleanupPlayerESP(player)
    end
    
    playerHighlights = {}
    playerConnections = {}
    
    -- Setup ESP for existing players
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayerESP(player)
    end
    
    -- Setup for new players
    Players.PlayerAdded:Connect(function(player)
        if espEnabled then
            setupPlayerESP(player)
        end
    end)
    
    -- Setup player removal
    Players.PlayerRemoving:Connect(function(player)
        cleanupPlayerESP(player)
    end)
    
    -- Main update loop
    espMainConnection = RunService.Heartbeat:Connect(function()
        if not espEnabled then
            if espMainConnection then
                espMainConnection:Disconnect()
                espMainConnection = nil
            end
            return
        end
        updateAllESP()
    end)
end

local function disableESP()
    if not espEnabled then return end
    
    espEnabled = false
    
    if DEBUG_MODE then
        print(TEXT_TAGS.ESP .. " Disabling ESP...")
    end
    
    -- Disconnect main update loop
    if espMainConnection then
        espMainConnection:Disconnect()
        espMainConnection = nil
    end
    
    -- Clean up all highlights and connections
    for player, _ in pairs(playerHighlights) do
        cleanupPlayerESP(player)
    end
    
    playerHighlights = {}
    playerConnections = {}
end

-- Optimized Auto Farm System
local function startAutofarm()
    -- Stop any existing autofarm thread
    if autofarmThread then
        autofarmThread = nil
    end
    
    -- Services
    local TweenService = game:GetService("TweenService")
    local MarketplaceService = game:GetService("MarketplaceService")
    
    -- Player references
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    
    -- Constants
    local COIN_CONTAINER_NAME = "CoinContainer"
    local COIN_NAME = "Coin_Server"
    local SCAN_INTERVAL = 0.1
    local UPDATE_THRESHOLD = 5
    local ELITE_GAMEPASS_ID = 429957
    
    -- State management
    local currentCoin = nil
    local currentTween = nil
    local currentContainer = nil
    local inCooldown = false
    local roundActive = false
    local coinLimit = 50
    local hasEliteGamepass = false
    local lastDebugPrint = 0
    local debugPrintCooldown = 1 -- Seconds between debug prints
    local lastWaitingPrint = 0
    local waitingPrintInterval = 10 -- Increased to 10 seconds to reduce spam
    local lastMurdererUpdate = 0
    
    -- Performance optimization
    local lastContainerCheck = 0
    local containerCheckInterval = 3 -- Check for container every 3 seconds when not found
    local activeCoinsCache = {}
    local lastCoinScan = 0
    local coinScanInterval = 0.5 -- Scan for coins every 0.5 seconds instead of every frame
    
    -- Improved debug print function with cooldown
    local function debugPrint(message, tag, force)
        if not DEBUG_MODE then return end
        
        local currentTime = tick()
        if not force and currentTime - lastDebugPrint < debugPrintCooldown then
            return
        end
        
        local tagText = tag or TEXT_TAGS.INFO
        print(tagText .. " [Coin Collector] " .. message)
        lastDebugPrint = currentTime
    end

    -- Improved player alive check
    local function isPlayerAlive()
        if not character or not character.Parent then 
            return false 
        end
        
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then 
            return false 
        end
        
        -- Check multiple conditions for death
        if humanoid.Health <= 0 then
            return false
        end
        
        -- Check NameDisplayDistance (spectator mode)
        if humanoid.NameDisplayDistance == 100 then
            return false
        end
        
        -- Check if humanoid root part exists and is in workspace
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp:IsDescendantOf(workspace) then
            return false
        end
        
        return true
    end

    -- Gamepass check
    local function checkEliteGamepass()
        local success, ownsPass = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, ELITE_GAMEPASS_ID)
        end)
        
        if success then
            hasEliteGamepass = ownsPass
            coinLimit = hasEliteGamepass and 50 or 50
            debugPrint("Gamepass check: " .. (hasEliteGamepass and "ELITE OWNED" or "Standard"), 
                    hasEliteGamepass and TEXT_TAGS.SUCCESS or TEXT_TAGS.WARNING, true)
            return true
        else
            debugPrint("Gamepass check failed: " .. tostring(ownsPass), TEXT_TAGS.ERROR, true)
            return false
        end
    end

    -- Character reset
    local function resetCharacter()
        if character and character.Parent then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                pcall(function() 
                    humanoid.Health = 0 
                end)
                debugPrint("Character reset triggered", TEXT_TAGS.RESET, true)
            end
        end
    end

    -- Tween cancellation
    local function safeCancelTween()
        if currentTween then
            pcall(function()
                if currentTween.PlaybackState == Enum.PlaybackState.Playing then
                    currentTween:Cancel()
                end
            end)
            currentTween = nil
        end
    end

    -- Coin count from GUI
    local function getCoinCount()
        local gui = player:FindFirstChild("PlayerGui")
        if not gui then return 0 end
        
        local mainGUI = gui:FindFirstChild("MainGUI")
        if not mainGUI then return 0 end
        
        local coinBags = mainGUI:FindFirstChild("Game") and mainGUI.Game:FindFirstChild("CoinBags")
                    or mainGUI:FindFirstChild("Lobby") and mainGUI.Lobby:FindFirstChild("Dock") 
                    and mainGUI.Lobby.Dock:FindFirstChild("CoinBags")
        
        if not coinBags then return 0 end
        local container = coinBags:FindFirstChild("Container")
        if not container then return 0 end
        
        local snowTokenContainer = container:FindFirstChild("SnowToken")
        if not snowTokenContainer then return 0 end
        
        local currencyFrame = snowTokenContainer:FindFirstChild("CurrencyFrame")
        if not currencyFrame then return 0 end
        
        local icon = currencyFrame:FindFirstChild("Icon")
        if not icon then return 0 end
        
        local coinsText = icon:FindFirstChild("Coins")
        if not coinsText or not coinsText:IsA("TextLabel") then return 0 end
        
        local cleanText = coinsText.Text:gsub(",", ""):gsub("%D", "")
        return tonumber(cleanText) or 0
    end

    -- Optimized coin container search - no deep search
    local function findCoinContainer()
        local currentTime = tick()
        
        -- Use cached result if still valid
        if coinContainerCache and currentTime - coinContainerCacheTime < CACHE_DURATION then
            if coinContainerCache.Parent then
                return coinContainerCache
            else
                -- Cache is invalid, clear it
                coinContainerCache = nil
            end
        end
        
        -- Check common locations first for performance
        local commonLocations = {
            workspace,
            workspace:FindFirstChild("Map"),
            workspace:FindFirstChild("Game")
        }
        
        for _, location in ipairs(commonLocations) do
            if location then
                local container = location:FindFirstChild(COIN_CONTAINER_NAME)
                if container then
                    -- Cache the result
                    coinContainerCache = container
                    coinContainerCacheTime = currentTime
                    return container
                end
            end
        end
        
        -- Check all direct children of workspace (models) for CoinContainer
        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Model") then
                local container = child:FindFirstChild(COIN_CONTAINER_NAME)
                if container then
                    -- Cache the result
                    coinContainerCache = container
                    coinContainerCacheTime = currentTime
                    return container
                end
            end
        end
        
        return nil
    end

    -- Get active coins with caching and skipping
    local function getActiveCoins(coinContainer)
        local currentTime = tick()
        
        -- Only scan for coins every coinScanInterval seconds to reduce lag
        if currentTime - lastCoinScan < coinScanInterval then
            return activeCoinsCache
        end
        
        lastCoinScan = currentTime
        activeCoinsCache = {}
        
        if coinContainer then
            for _, child in ipairs(coinContainer:GetChildren()) do
                if child.Name == COIN_NAME and child:FindFirstChild("TouchInterest") then
                    -- Check if coin should be skipped
                    if not ShouldSkipCoin(child) then
                        table.insert(activeCoinsCache, child)
                    end
                end
            end
        end
        
        return activeCoinsCache
    end

    -- Find nearest coin (excluding skipped coins)
    local function findNearestCoin(coins)
        if #coins == 0 then return nil end
        
        local closestCoin
        local shortestDistance = math.huge
        local charPos = humanoidRootPart.Position
        
        for _, coin in ipairs(coins) do
            if coin:IsDescendantOf(workspace) then
                local distance = (charPos - coin.Position).Magnitude
                if distance < shortestDistance then
                    shortestDistance = distance
                    closestCoin = coin
                end
            end
        end
        
        return closestCoin, shortestDistance
    end

    -- Reset collector state
    local function resetCollectorState()
        safeCancelTween()
        DisableLayingDown()
        currentCoin = nil
        currentContainer = nil
        inCooldown = false
        roundActive = false
        isFlinging = false
        flingTarget = nil
        -- Clear cache when resetting
        activeCoinsCache = {}
    end

    -- Environment validation
    local function validateCollectionEnvironment(coin)
        if not isPlayerAlive() then
            debugPrint("Player is dead - stopping collection", TEXT_TAGS.DEAD)
            resetCollectorState()
            return false
        end
        
        if not currentContainer or not currentContainer:IsDescendantOf(workspace) then
            debugPrint("CoinContainer disappeared - round ended", TEXT_TAGS.CANCEL)
            resetCollectorState()
            return false
        end
        
        if not coin or not coin:IsDescendantOf(workspace) or not coin:FindFirstChild("TouchInterest") then
            debugPrint("Coin disappeared or collected", TEXT_TAGS.COIN)
            return false
        end
        
        if not character or not humanoidRootPart or not humanoidRootPart:IsDescendantOf(workspace) then
            debugPrint("Character invalid", TEXT_TAGS.ERROR)
            return false
        end
        
        return true
    end

    -- Check if coin was successfully collected
    local function wasCoinCollected(coin, initialCoinCount)
        local newCoinCount = getCoinCount()
        local coinStillExists = coin and coin:IsDescendantOf(workspace) and coin:FindFirstChild("TouchInterest")
        
        -- Coin was collected if:
        -- 1. Coin count increased OR
        -- 2. Coin no longer exists in workspace
        return newCoinCount > initialCoinCount or not coinStillExists
    end

    -- Stable coin collection with instant teleport for long distances and attempt tracking
    local function collectCoin(coin)
        if not coin or not coin:IsDescendantOf(workspace) or not coin:FindFirstChild("TouchInterest") then
            debugPrint("Invalid coin for collection", TEXT_TAGS.ERROR)
            return
        end
        
        if inCooldown or not isPlayerAlive() then 
            return 
        end
        
        inCooldown = true
        currentCoin = coin
        roundActive = true
        
        -- Track coin attempt
        IncrementCoinAttempt(coin)
        local initialCoinCount = getCoinCount()
        
        -- Position character UNDER the coin (3 units below)
        local targetPosition = coin.Position + Vector3.new(0, -3, 0)
        local distance = (humanoidRootPart.Position - targetPosition).Magnitude
        
        -- Enable laying down before moving to coin
        if not isLayingDown then
            EnableLayingDown()
        end
        
        -- Check if we should use instant teleport (if distance is too far)
        if distance > INSTANT_TELEPORT_DISTANCE then
            debugPrint(("Using instant teleport | Distance: %.2f"):format(distance), TEXT_TAGS.INSTANT_TELEPORT)
            InstantTeleportToCoin(coin)
        else
            -- Use normal tween for shorter distances
            local tweenTime = distance / collectSpeed
            debugPrint(("Moving under coin | Distance: %.2f | Time: %.2fs"):format(distance, tweenTime), TEXT_TAGS.MOVING)
            
            -- Tween to position under coin while maintaining laying down rotation
            local tweenInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear)
            currentTween = TweenService:Create(humanoidRootPart, tweenInfo, {
                CFrame = CFrame.new(targetPosition) * CFrame.Angles(math.rad(90), 0, 0)
            })
            currentTween:Play()
            
            local startTime = os.clock()
            local lastValidCheck = os.clock()
            
            while autofarmEnabled and currentTween and currentTween.PlaybackState == Enum.PlaybackState.Playing do
                if os.clock() - lastValidCheck > 0.1 then
                    if not validateCollectionEnvironment(coin) then
                        debugPrint("Cancelling movement", TEXT_TAGS.CANCEL)
                        safeCancelTween()
                        break
                    end
                    lastValidCheck = os.clock()
                end
                
                if os.clock() - startTime > tweenTime + 2 then
                    debugPrint("Tween timeout - cancelling", TEXT_TAGS.WARNING)
                    safeCancelTween()
                    break
                end
                
                task.wait()
            end
            
            safeCancelTween()
        end
        
        -- Check if coin was successfully collected
        local collected = wasCoinCollected(coin, initialCoinCount)
        
        if collected then
            debugPrint("Coin successfully collected", TEXT_TAGS.SUCCESS)
            -- Reset attempt counter for successfully collected coin
            coinAttempts[coin] = nil
        else
            debugPrint("Coin collection failed", TEXT_TAGS.WARNING)
            
            -- Check if we should skip this coin due to too many attempts
            if coinAttempts[coin] and coinAttempts[coin] >= MAX_ATTEMPTS_PER_COIN then
                debugPrint("Skipping coin after maximum attempts", TEXT_TAGS.SKIP)
                skippedCoins[coin] = true
            end
        end
        
        -- Keep laying down state for next coin collection
        -- Don't disable laying down between coins - maintain the state
        
        if autofarmEnabled and roundActive and isPlayerAlive() then
            local coinCount = getCoinCount()
            debugPrint(("Current coins: %d/%d"):format(coinCount, coinLimit), TEXT_TAGS.COUNTER)
            
            -- Check if coin limit reached
            if coinCount >= coinLimit then
                debugPrint("Coin limit reached! Resetting character...", TEXT_TAGS.LIMIT, true)
                resetCharacter()
            else
                debugPrint("Anti-cheat cooldown: " .. collectionDelay .. "s", TEXT_TAGS.WAITING)
                task.wait(collectionDelay)
            end
        end
        
        inCooldown = false
        currentCoin = nil
    end

    -- Character respawn handler
    player.CharacterAdded:Connect(function(newChar)
        character = newChar
        humanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
        debugPrint("Character respawn detected", TEXT_TAGS.INFO, true)
        resetCollectorState()
        
        -- Stop flinging when character respawns
        isFlinging = false
        flingTarget = nil
    end)

    -- Initial setup
    debugPrint("Script initialized", TEXT_TAGS.SUCCESS, true)
    checkEliteGamepass()

    -- Main autofarm loop with improved performance
    while autofarmEnabled do
        -- Update murderer detection every second
        if tick() - lastMurdererUpdate > 1 then
            local allMurderers = GetAllMurderers()
            if #allMurderers > 0 then
                debugPrint(("Murderer detected: %s"):format(allMurderers[1].Name), TEXT_TAGS.MURDERER)
            end
            lastMurdererUpdate = tick()
        end
        
        -- Check if we're in spectator mode and start flinging if there's a murderer
        if IsSpectator(player) and not isFlinging then
            local allMurderers = GetAllMurderers()
            if #allMurderers == 1 then
                debugPrint("Spectator mode detected with murderer! Starting fling...", TEXT_TAGS.SPECTATOR, true)
                task.spawn(function()
                    StartFlingMurderer(debugPrint)
                end)
            else
                debugPrint("Spectator mode - waiting for round to start...", TEXT_TAGS.WAITING)
            end
        end
        
        -- Skip coin collection if we're flinging the murderer or in spectator mode
        if isFlinging or IsSpectator(player) then
            debugPrint("Flinging murderer or in spectator mode - skipping coin collection", TEXT_TAGS.FLING)
            task.wait(1)
        elseif not inCooldown then
            if not isPlayerAlive() then
                debugPrint("Player is dead - waiting for respawn", TEXT_TAGS.DEAD)
                task.wait(2) -- Longer wait when dead
                resetCollectorState()
            else
                -- Only check for container periodically to reduce lag
                local currentTime = tick()
                if not currentContainer or not currentContainer:IsDescendantOf(workspace) or currentTime - lastContainerCheck > containerCheckInterval then
                    currentContainer = findCoinContainer()
                    roundActive = currentContainer ~= nil
                    lastContainerCheck = currentTime
                    
                    if roundActive then
                        debugPrint("Round started - CoinContainer found", TEXT_TAGS.SUCCESS, true)
                        debugPrint(("Coin limit: %d"):format(coinLimit), TEXT_TAGS.LIMIT, true)
                        -- Reset coin tracking when round starts
                        ResetCoinTracking()
                        -- Enable laying down when round starts
                        if not isLayingDown then
                            EnableLayingDown()
                        end
                    else
                        -- Disable laying down when round ends
                        if isLayingDown then
                            DisableLayingDown()
                        end
                        -- Only print waiting message every 10 seconds to reduce spam and FPS drops
                        if currentTime - lastWaitingPrint > waitingPrintInterval then
                            debugPrint("Waiting for round start...", TEXT_TAGS.WAITING)
                            lastWaitingPrint = currentTime
                        end
                    end
                end
                
                if roundActive then
                    local activeCoins = getActiveCoins(currentContainer)
                    
                    if #activeCoins > 0 then
                        local nearestCoin, distance = findNearestCoin(activeCoins)
                        
                        if nearestCoin then
                            debugPrint("Nearest coin distance: " .. math.floor(distance), TEXT_TAGS.SEARCH)
                            
                            if currentCoin then
                                if currentCoin ~= nearestCoin then
                                    local currentDistance = (humanoidRootPart.Position - currentCoin.Position).Magnitude
                                    local improvement = currentDistance - distance
                                    
                                    if improvement > UPDATE_THRESHOLD then
                                        debugPrint("Switching to closer coin (improvement: " .. math.floor(improvement) .. ")", TEXT_TAGS.COLLECT)
                                        resetCollectorState()
                                        task.spawn(collectCoin, nearestCoin)
                                    end
                                end
                            else
                                debugPrint("Starting collection", TEXT_TAGS.COLLECT)
                                task.spawn(collectCoin, nearestCoin)
                            end
                        end
                    else
                        debugPrint("No active coins found", TEXT_TAGS.WARNING)
                    end
                else
                    -- Longer wait when no round is active to reduce lag
                    task.wait(1)
                end
            end
        else
            debugPrint("Skipping scan - in cooldown", TEXT_TAGS.WAITING)
        end
        
        task.wait(SCAN_INTERVAL)
    end
    
    -- Cleanup when autofarm is disabled
    resetCollectorState()
    isFlinging = false
    flingTarget = nil
    debugPrint("Autofarm disabled", TEXT_TAGS.CANCEL, true)
end

-- UI Elements
MainTab:AddToggle({
    Text = "Auto Farm",
    Callback = function(state)
        -- Prevent multiple toggles
        if autofarmEnabled == state then return end
        
        autofarmEnabled = state
        if state then
            -- Stop any existing thread first
            if autofarmThread then
                autofarmThread = nil
            end
            -- Enable hitbox modification
            enableResize()
            -- Start new thread
            autofarmThread = coroutine.create(startAutofarm)
            coroutine.resume(autofarmThread)
        else
            -- Clean up when disabling
            if autofarmThread then
                autofarmThread = nil
            end
            -- Disable hitbox modification
            disableResize()
            -- Disable laying down
            DisableLayingDown()
            
            -- Teleport to lobby if player is alive
            if IsPlayerAlive() then
                if DEBUG_MODE then
                    print("[Auto Farm] Teleporting to lobby...")
                end
                TeleportToLobby()
            else
                if DEBUG_MODE then
                    print("[Auto Farm] Player is dead, skipping lobby teleport")
                end
            end
            
            isFlinging = false
            flingTarget = nil
        end
    end
})

MainTab:AddToggle({
    Text = "ESP",
    Callback = function(state)
        if state then
            enableESP()
        else
            disableESP()
        end
    end
})

MainTab:AddSlider({
    Text = "Collect Speed",
    Min = 10,
    Max = 35,
    Step = 1,
    Default = 25,
    Callback = function(value)
        collectSpeed = value
    end
})

MainTab:AddSlider({
    Text = "Collection Delay",
    Min = 0.1,
    Max = 5,
    Step = 0.1,
    Default = 0.5,
    Callback = function(value)
        collectionDelay = value
    end
})

TeleportTab:AddButton({
    Text = "Map",
    Callback = function()
        local player = Players.LocalPlayer
        local character = player.Character
        
        if not character then
            if DEBUG_MODE then
                print("[Map Teleport] No character found")
            end
            return
        end
        
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            if DEBUG_MODE then
                print("[Map Teleport] No HumanoidRootPart found")
            end
            return
        end
        
        -- First, find the Map model (it has a random name each round, NOT "Lobby")
        local mapModel = nil
        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Model") and child.Name ~= "Lobby" then
                -- Check if this model contains a "Spawns" model
                local spawnsModel = child:FindFirstChild("Spawns")
                if spawnsModel and spawnsModel:IsA("Model") then
                    mapModel = child
                    break
                end
            end
        end
        
        if not mapModel then
            if DEBUG_MODE then
                print("[Map Teleport] No Map model found in workspace (excluding Lobby)")
            end
            return
        end
        
        -- Find the Spawns model inside the Map
        local spawnsModel = mapModel:FindFirstChild("Spawns")
        if not spawnsModel then
            if DEBUG_MODE then
                print("[Map Teleport] No Spawns model found in Map")
            end
            return
        end
        
        -- Collect all valid spawn parts (named "Spawn" or "PlayerSpawn")
        local spawnsList = {}
        for _, spawnPart in ipairs(spawnsModel:GetChildren()) do
            if spawnPart:IsA("BasePart") and (spawnPart.Name == "Spawn" or spawnPart.Name == "PlayerSpawn") then
                table.insert(spawnsList, spawnPart)
            end
        end
        
        if #spawnsList == 0 then
            if DEBUG_MODE then
                print("[Map Teleport] No spawn parts found in Spawns model")
            end
            return
        end
        
        -- Choose a random spawn from the list
        local randomIndex = math.random(1, #spawnsList)
        local chosenSpawn = spawnsList[randomIndex]
        
        -- Disable laying down if active
        if isLayingDown then
            DisableLayingDown()
        end
        
        -- Wait a frame for laying down to fully disable
        task.wait(0.1)
        
        -- Teleport to the spawn position (center of the spawn part)
        local spawnPosition = chosenSpawn.Position + Vector3.new(0, 3, 0) -- 3 units above to avoid clipping
        humanoidRootPart.CFrame = CFrame.new(spawnPosition)
        
        if DEBUG_MODE then
            print("[Map Teleport] Successfully teleported to map spawn (" .. chosenSpawn.Name .. ") in " .. mapModel.Name)
        end
    end
})

TeleportTab:AddButton({
    Text = "Lobby",
    Callback = function()
	    local targetPosition = Vector3.new(-4958, 305, 58)
	    local player = Players.LocalPlayer
        local character = player.Character
        
        if not character then
            if DEBUG_MODE then
                print("[Map Teleport] No character found")
            end
            return
        end
        
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            if DEBUG_MODE then
                print("[Map Teleport] No HumanoidRootPart found")
            end
            return
        end
	humanoidRootPart.CFrame = CFrame.new(targetPosition)
	end
})
TeleportTab:AddButton({
    Text = "Gun",
    Callback = function()
        local player = Players.LocalPlayer
        
        -- Check if player is dead (spectator mode)
        if IsSpectator(player) then
            if DEBUG_MODE then
                print("[Gun Teleport] Player is dead - cannot teleport")
            end
            return
        end
        
        -- Check if player is alive
        if not IsPlayerAlive(player) then
            if DEBUG_MODE then
                print("[Gun Teleport] Player is not alive - cannot teleport")
            end
            return
        end
        
        local character = player.Character
        if not character then
            if DEBUG_MODE then
                print("[Gun Teleport] No character found")
            end
            return
        end
        
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then
            if DEBUG_MODE then
                print("[Gun Teleport] No HumanoidRootPart found")
            end
            return
        end
        
        -- Check if player is murderer (shouldn't teleport to gun)
        if IsLocalPlayerMurderer() then
            if DEBUG_MODE then
                print("[Gun Teleport] Player is murderer - cannot teleport to gun")
            end
            return
        end
        
        -- Perform a deep search (recursive) for "GunDrop"
        local targetPart = workspace:FindFirstChild("GunDrop", true)
        
        if targetPart and targetPart:IsA("BasePart") then
            -- Disable laying down if active
            if isLayingDown then
                DisableLayingDown()
            end
            
            -- Wait a frame for laying down to fully disable
            task.wait(0.1)
            
            -- Teleport to the part's position
            -- Adding an offset of 3 studs up (0, 3, 0) so you don't get stuck in the floor
            humanoidRootPart.CFrame = targetPart.CFrame * CFrame.new(0, 3, 0)
            
            if DEBUG_MODE then
                print("[Gun Teleport] Successfully teleported to GunDrop!")
            end
        else
            -- Do nothing if it's not found
            if DEBUG_MODE then
                print("[Gun Teleport] GunDrop not found in Workspace.")
            end
        end
    end
})

TeleportTab:AddButton({
    Text = "Murderer",
    Callback = function()
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

-- Function to find the player with the specific tool
local function teleportToMurderer()
    local targetToolName = "Knife"
    
    for _, player in ipairs(Players:GetPlayers()) do
        -- Skip the local player so you don't teleport to yourself
        if player ~= localPlayer then
            local hasTool = false
            
            -- Check if the tool is currently equipped (in the character)
            if player.Character and player.Character:FindFirstChild(targetToolName) then
                hasTool = true
            -- Check if the tool is in the inventory (backpack)
            elseif player.Backpack:FindFirstChild(targetToolName) then
                hasTool = true
            end
            
            if hasTool and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                -- Teleport to the player's position
                local targetRoot = player.Character.HumanoidRootPart
                local myRoot = localPlayer.Character:WaitForChild("HumanoidRootPart")
                
                -- Offset slightly so you don't get stuck inside them
                myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
                if DEBUG_MODE then
                print("[Murderer Teleport] Successfully teleported to Murderer (" .. player.Name .. ") in ")
                end
                return -- Stop searching once we find one
            end
        end
    end
    
    if DEBUG_MODE then
    print("[Sheriff Teleport] Sheriff not found")
    end
end

-- Run the function
teleportToMurderer()
end
})

TeleportTab:AddButton({
    Text = "Sheriff",
    Callback = function()
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

-- Function to find the player with the specific tool
local function teleportToSheriff()
    local targetToolName = "Gun"
    
    for _, player in ipairs(Players:GetPlayers()) do
        -- Skip the local player so you don't teleport to yourself
        if player ~= localPlayer then
            local hasTool = false
            
            -- Check if the tool is currently equipped (in the character)
            if player.Character and player.Character:FindFirstChild(targetToolName) then
                hasTool = true
            -- Check if the tool is in the inventory (backpack)
            elseif player.Backpack:FindFirstChild(targetToolName) then
                hasTool = true
            end
            
            if hasTool and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                -- Teleport to the player's position
                local targetRoot = player.Character.HumanoidRootPart
                local myRoot = localPlayer.Character:WaitForChild("HumanoidRootPart")
                
                -- Offset slightly so you don't get stuck inside them
                myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
                if DEBUG_MODE then
                print("[Sheriff Teleport] Successfully teleported to Sheriff (" .. player.Name .. ")")
                end
                return -- Stop searching once we find one
            end
        end
    end
    
    if DEBUG_MODE then
    print("[Sheriff Teleport] Sheriff not found")
    end
end

-- Run the function
teleportToSheriff()
end
})

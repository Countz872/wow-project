--[[
    REPLAY SYSTEM v1.5.0
    Hybrid Movement:
        Normal  -> Humanoid:MoveTo()
        Stuck   -> PathfindingService
        Unstuck -> Humanoid:MoveTo()

    Skills:
        Q Skill dropdown
        E Skill dropdown

    Recording:
        Movement
        Q/E skill activations

    Replay:
        Movement timeline
        Skill timeline
        Death/respawn recovery
]]

--// SERVICES
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

--// PLAYER
local Player = Players.LocalPlayer
local Backpack = Player:WaitForChild("Backpack")

local Remotes = ReplicatedStorage:WaitForChild("remotes")
local AbilityUsed = Remotes:WaitForChild("abilityUsed")

--// CHARACTER
local Character
local Humanoid
local RootPart

local function SetupCharacter()
    Character = Player.Character or Player.CharacterAdded:Wait()

    Humanoid = Character:WaitForChild("Humanoid")
    RootPart = Character:WaitForChild("HumanoidRootPart")
end

SetupCharacter()

Player.CharacterAdded:Connect(function()
    SetupCharacter()
end)

--//========================================================
--// CONFIG
--//========================================================

local VERSION = "v1.5.0"

local RECORD_INTERVAL = 0.05

-- How far the replay target must change before we consider
-- refreshing movement information.
local TARGET_UPDATE_DISTANCE = 2

-- Stuck detection
local STUCK_TIME = 1.0
local STUCK_DISTANCE = 0.6

-- MoveTo refresh
local MOVETO_REFRESH = 0.12

-- Pathfinding
local AGENT_RADIUS = 2
local AGENT_HEIGHT = 5
local WAYPOINT_SPACING = 4

-- Distance where we consider a MoveTo target reached
local TARGET_REACHED_DISTANCE = 2.5

-- Path waypoint reach distance
local WAYPOINT_REACHED_DISTANCE = 2.5

-- How long to allow pathfinding before forcing a recalculation
local PATH_TIMEOUT = 4

-- Starting skills
local QSkillName = "Inner Focus"
local ESkillName = "Pulse Waves"

--//========================================================
--// STATE
--//========================================================

local IsRecording = false
local IsReplaying = false

local CurrentRecording = nil

local Recordings = {}

local ReplayConnection = nil
local RecordConnection = nil
local CharacterConnection = nil

-- Movement state
local MovementMode = "MoveTo"

local CurrentMoveTarget = nil
local LastMoveCommand = 0

local LastProgressPosition = nil
local LastProgressTime = 0

-- Pathfinding state
local CurrentPath = nil
local CurrentWaypoints = nil
local CurrentWaypointIndex = 1
local PathBlockedConnection = nil
local PathStartedTime = 0
local NeedNewPath = false

-- Replay recovery
local ReplayStartIndex = 1
local ReplayStartTime = 0

-- Prevent duplicate skill replay after respawn
local ReplayedActionIndexes = {}

--========================================================
-- UI
--========================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ReplaySystem"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = Player:WaitForChild("PlayerGui")

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 380, 0, 500)
Main.Position = UDim2.new(0.5, -190, 0.5, -250)
Main.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

--// HEADER

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 40)
Header.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -100, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Replay System"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local VersionLabel = Instance.new("TextLabel")
VersionLabel.Size = UDim2.new(0, 65, 1, 0)
VersionLabel.Position = UDim2.new(1, -105, 0, 0)
VersionLabel.BackgroundTransparency = 1
VersionLabel.Text = VERSION
VersionLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
VersionLabel.TextSize = 11
VersionLabel.Font = Enum.Font.Gotham
VersionLabel.Parent = Header

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Size = UDim2.new(0, 35, 0, 30)
MinimizeButton.Position = UDim2.new(1, -40, 0, 5)
MinimizeButton.BackgroundTransparency = 1
MinimizeButton.Text = "-"
MinimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeButton.TextSize = 22
MinimizeButton.Font = Enum.Font.GothamBold
MinimizeButton.Parent = Header

--// CONTENT

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, 0, 1, -40)
Content.Position = UDim2.new(0, 0, 0, 40)
Content.BackgroundTransparency = 1
Content.Parent = Main

--// RECORDING NAME

local NameLabel = Instance.new("TextLabel")
NameLabel.Size = UDim2.new(1, -30, 0, 25)
NameLabel.Position = UDim2.new(0, 15, 0, 10)
NameLabel.BackgroundTransparency = 1
NameLabel.Text = "Recording Name"
NameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
NameLabel.TextSize = 13
NameLabel.Font = Enum.Font.Gotham
NameLabel.TextXAlignment = Enum.TextXAlignment.Left
NameLabel.Parent = Content

local NameBox = Instance.new("TextBox")
NameBox.Size = UDim2.new(1, -30, 0, 35)
NameBox.Position = UDim2.new(0, 15, 0, 35)
NameBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
NameBox.BorderSizePixel = 0
NameBox.PlaceholderText = "Recording name..."
NameBox.Text = ""
NameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
NameBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
NameBox.TextSize = 14
NameBox.Font = Enum.Font.Gotham
NameBox.Parent = Content

local NameCorner = Instance.new("UICorner")
NameCorner.CornerRadius = UDim.new(0, 6)
NameCorner.Parent = NameBox

--//========================================================
--// SKILL DROPDOWNS
--//========================================================

local QLabel = Instance.new("TextLabel")
QLabel.Size = UDim2.new(0.5, -20, 0, 25)
QLabel.Position = UDim2.new(0, 15, 0, 80)
QLabel.BackgroundTransparency = 1
QLabel.Text = "Q Skill"
QLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
QLabel.TextSize = 13
QLabel.Font = Enum.Font.Gotham
QLabel.TextXAlignment = Enum.TextXAlignment.Left
QLabel.Parent = Content

local ELabel = Instance.new("TextLabel")
ELabel.Size = UDim2.new(0.5, -20, 0, 25)
ELabel.Position = UDim2.new(0.5, 5, 0, 80)
ELabel.BackgroundTransparency = 1
ELabel.Text = "E Skill"
ELabel.TextColor3 = Color3.fromRGB(200, 200, 200)
ELabel.TextSize = 13
ELabel.Font = Enum.Font.Gotham
ELabel.TextXAlignment = Enum.TextXAlignment.Left
ELabel.Parent = Content

local QButton = Instance.new("TextButton")
QButton.Size = UDim2.new(0.5, -20, 0, 35)
QButton.Position = UDim2.new(0, 15, 0, 105)
QButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
QButton.BorderSizePixel = 0
QButton.Text = QSkillName
QButton.TextColor3 = Color3.fromRGB(255, 255, 255)
QButton.TextSize = 13
QButton.Font = Enum.Font.Gotham
QButton.Parent = Content

local EButton = Instance.new("TextButton")
EButton.Size = UDim2.new(0.5, -20, 0, 35)
EButton.Position = UDim2.new(0.5, 5, 0, 105)
EButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
EButton.BorderSizePixel = 0
EButton.Text = ESkillName
EButton.TextColor3 = Color3.fromRGB(255, 255, 255)
EButton.TextSize = 13
EButton.Font = Enum.Font.Gotham
EButton.Parent = Content

local QCorner = Instance.new("UICorner")
QCorner.CornerRadius = UDim.new(0, 6)
QCorner.Parent = QButton

local ECorner = Instance.new("UICorner")
ECorner.CornerRadius = UDim.new(0, 6)
ECorner.Parent = EButton

-- Dropdown containers

local QDropdown = Instance.new("Frame")
QDropdown.Size = UDim2.new(0.5, -20, 0, 120)
QDropdown.Position = UDim2.new(0, 15, 0, 142)
QDropdown.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
QDropdown.BorderSizePixel = 0
QDropdown.Visible = false
QDropdown.ZIndex = 20
QDropdown.Parent = Content

local EDropdown = Instance.new("Frame")
EDropdown.Size = UDim2.new(0.5, -20, 0, 120)
EDropdown.Position = UDim2.new(0.5, 5, 0, 142)
EDropdown.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
EDropdown.BorderSizePixel = 0
EDropdown.Visible = false
EDropdown.ZIndex = 20
EDropdown.Parent = Content

local function GetSkills()
    local Skills = {}

    local function Scan(container)
        for _, Object in ipairs(container:GetChildren()) do
            if Object:IsA("Folder")
                or Object:IsA("Tool")
                or Object:IsA("Model") then

                local AbilityEvent = Object:FindFirstChild("abilityEvent")
                local SpellEvent = Object:FindFirstChild("spellEvent")

                if AbilityEvent or SpellEvent then
                    if not table.find(Skills, Object.Name) then
                        table.insert(Skills, Object.Name)
                    end
                end
            end
        end
    end

    Scan(Backpack)

    if Character then
        Scan(Character)
    end

    table.sort(Skills)

    return Skills
end

local function ClearDropdown(Dropdown)
    for _, Child in ipairs(Dropdown:GetChildren()) do
        if Child:IsA("TextButton") then
            Child:Destroy()
        end
    end
end

local function PopulateDropdown(Dropdown, IsQ)
    ClearDropdown(Dropdown)

    local Skills = GetSkills()

    local Y = 5

    for _, SkillName in ipairs(Skills) do

        local Button = Instance.new("TextButton")
        Button.Size = UDim2.new(1, -10, 0, 30)
        Button.Position = UDim2.new(0, 5, 0, Y)
        Button.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        Button.BorderSizePixel = 0
        Button.Text = SkillName
        Button.TextColor3 = Color3.fromRGB(255, 255, 255)
        Button.TextSize = 12
        Button.Font = Enum.Font.Gotham
        Button.ZIndex = 21
        Button.Parent = Dropdown

        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(0, 5)
        Corner.Parent = Button

        Button.MouseButton1Click:Connect(function()

            if IsQ then
                QSkillName = SkillName
                QButton.Text = SkillName
                QDropdown.Visible = false
            else
                ESkillName = SkillName
                EButton.Text = SkillName
                EDropdown.Visible = false
            end

        end)

        Y += 32

        if Y > 110 then
            break
        end
    end
end

QButton.MouseButton1Click:Connect(function()
    EDropdown.Visible = false

    if not QDropdown.Visible then
        PopulateDropdown(QDropdown, true)
    end

    QDropdown.Visible = not QDropdown.Visible
end)

EButton.MouseButton1Click:Connect(function()
    QDropdown.Visible = false

    if not EDropdown.Visible then
        PopulateDropdown(EDropdown, false)
    end

    EDropdown.Visible = not EDropdown.Visible
end)

--//========================================================
--// BUTTONS
--//========================================================

local RecordButton = Instance.new("TextButton")
RecordButton.Size = UDim2.new(0.48, -10, 0, 40)
RecordButton.Position = UDim2.new(0, 15, 0, 180)
RecordButton.BackgroundColor3 = Color3.fromRGB(55, 130, 70)
RecordButton.BorderSizePixel = 0
RecordButton.Text = "RECORD"
RecordButton.TextColor3 = Color3.fromRGB(255, 255, 255)
RecordButton.TextSize = 14
RecordButton.Font = Enum.Font.GothamBold
RecordButton.Parent = Content

local StopButton = Instance.new("TextButton")
StopButton.Size = UDim2.new(0.48, -10, 0, 40)
StopButton.Position = UDim2.new(0.52, -5, 0, 180)
StopButton.BackgroundColor3 = Color3.fromRGB(140, 55, 55)
StopButton.BorderSizePixel = 0
StopButton.Text = "STOP"
StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
StopButton.TextSize = 14
StopButton.Font = Enum.Font.GothamBold
StopButton.Parent = Content

local RecordCorner = Instance.new("UICorner")
RecordCorner.CornerRadius = UDim.new(0, 6)
RecordCorner.Parent = RecordButton

local StopCorner = Instance.new("UICorner")
StopCorner.CornerRadius = UDim.new(0, 6)
StopCorner.Parent = StopButton

--// STATUS

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -30, 0, 30)
StatusLabel.Position = UDim2.new(0, 15, 0, 225)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Idle"
StatusLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
StatusLabel.TextSize = 13
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Content

--//========================================================
--// RECORDING LIST
--//========================================================

local SavedLabel = Instance.new("TextLabel")
SavedLabel.Size = UDim2.new(1, -30, 0, 25)
SavedLabel.Position = UDim2.new(0, 15, 0, 255)
SavedLabel.BackgroundTransparency = 1
SavedLabel.Text = "Saved Recordings"
SavedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
SavedLabel.TextSize = 13
SavedLabel.Font = Enum.Font.Gotham
SavedLabel.TextXAlignment = Enum.TextXAlignment.Left
SavedLabel.Parent = Content

local RecordingDropdownButton = Instance.new("TextButton")
RecordingDropdownButton.Size = UDim2.new(1, -30, 0, 35)
RecordingDropdownButton.Position = UDim2.new(0, 15, 0, 280)
RecordingDropdownButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
RecordingDropdownButton.BorderSizePixel = 0
RecordingDropdownButton.Text = "Select Recording"
RecordingDropdownButton.TextColor3 = Color3.fromRGB(255, 255, 255)
RecordingDropdownButton.TextSize = 13
RecordingDropdownButton.Font = Enum.Font.Gotham
RecordingDropdownButton.TextXAlignment = Enum.TextXAlignment.Left
RecordingDropdownButton.Parent = Content

local RecordingDropdownPadding = Instance.new("UIPadding")
RecordingDropdownPadding.PaddingLeft = UDim.new(0, 10)
RecordingDropdownPadding.Parent = RecordingDropdownButton

local RecordingList = Instance.new("ScrollingFrame")
RecordingList.Size = UDim2.new(1, -30, 0, 100)
RecordingList.Position = UDim2.new(0, 15, 0, 320)
RecordingList.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
RecordingList.BorderSizePixel = 0
RecordingList.ScrollBarThickness = 4
RecordingList.Visible = false
RecordingList.ZIndex = 30
RecordingList.Parent = Content

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 3)
ListLayout.Parent = RecordingList

local ReplayButton = Instance.new("TextButton")
ReplayButton.Size = UDim2.new(1, -30, 0, 45)
ReplayButton.Position = UDim2.new(0, 15, 0, 430)
ReplayButton.BackgroundColor3 = Color3.fromRGB(65, 90, 160)
ReplayButton.BorderSizePixel = 0
ReplayButton.Text = "REPLAY"
ReplayButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ReplayButton.TextSize = 15
ReplayButton.Font = Enum.Font.GothamBold
ReplayButton.Parent = Content

local ReplayCorner = Instance.new("UICorner")
ReplayCorner.CornerRadius = UDim.new(0, 6)
ReplayCorner.Parent = ReplayButton

local SelectedRecording = nil

local function RefreshRecordingList()

    for _, Child in ipairs(RecordingList:GetChildren()) do
        if Child:IsA("TextButton") then
            Child:Destroy()
        end
    end

    for Index, Recording in ipairs(Recordings) do

        local Button = Instance.new("TextButton")
        Button.Size = UDim2.new(1, -8, 0, 30)
        Button.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        Button.BorderSizePixel = 0
        Button.Text = Recording.Name
        Button.TextColor3 = Color3.fromRGB(255, 255, 255)
        Button.TextSize = 12
        Button.Font = Enum.Font.Gotham
        Button.ZIndex = 31
        Button.Parent = RecordingList

        Button.MouseButton1Click:Connect(function()

            SelectedRecording = Index
            RecordingDropdownButton.Text = Recording.Name

            RecordingList.Visible = false

        end)

    end
end

RecordingDropdownButton.MouseButton1Click:Connect(function()
    RecordingList.Visible = not RecordingList.Visible
end)

--========================================================
-- DRAGGING
--========================================================

local Dragging = false
local DragStart
local StartPosition

Header.InputBegan:Connect(function(Input)

    if Input.UserInputType == Enum.UserInputType.MouseButton1 then

        Dragging = true
        DragStart = Input.Position
        StartPosition = Main.Position

    end

end)

Header.InputEnded:Connect(function(Input)

    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
        Dragging = false
    end

end)

UserInputService.InputChanged:Connect(function(Input)

    if not Dragging then
        return
    end

    if Input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end

    local Delta = Input.Position - DragStart

    Main.Position = UDim2.new(
        StartPosition.X.Scale,
        StartPosition.X.Offset + Delta.X,
        StartPosition.Y.Scale,
        StartPosition.Y.Offset + Delta.Y
    )

end)

--========================================================
-- MINIMIZE
--========================================================

local Minimized = false

MinimizeButton.MouseButton1Click:Connect(function()

    Minimized = not Minimized

    Content.Visible = not Minimized

    if Minimized then
        Main.Size = UDim2.new(0, 380, 0, 40)
        MinimizeButton.Text = "+"
    else
        Main.Size = UDim2.new(0, 380, 0, 500)
        MinimizeButton.Text = "-"
    end

end)

--========================================================
-- SKILL FUNCTIONS
--========================================================

local function FindSkill(SkillName)

    if not SkillName then
        return nil
    end

    local Skill = Backpack:FindFirstChild(SkillName)

    if Skill then
        return Skill
    end

    if Character then

        Skill = Character:FindFirstChild(SkillName)

        if Skill then
            return Skill
        end

    end

    return nil
end

local function ReplaySkill(Key, SkillName)

    local Skill = FindSkill(SkillName)

    if not Skill then
        warn("[Replay] Skill not found:", SkillName)
        return false
    end

    local Success, ErrorMessage = pcall(function()

        AbilityUsed:FireServer(Key, Skill)

        local Event = Skill:FindFirstChild("abilityEvent")

        if not Event then
            Event = Skill:FindFirstChild("spellEvent")
        end

        if not Event then
            error("No abilityEvent/spellEvent found")
        end

        Event:FireServer()

    end)

    if not Success then
        warn("[Replay] Skill error:", ErrorMessage)
        return false
    end

    return true
end

--========================================================
-- MOVEMENT RESET
--========================================================

local function ClearPath()

    if PathBlockedConnection then
        PathBlockedConnection:Disconnect()
        PathBlockedConnection = nil
    end

    CurrentPath = nil
    CurrentWaypoints = nil
    CurrentWaypointIndex = 1
    NeedNewPath = false
    PathStartedTime = 0

end

--========================================================
-- PATHFINDING
--========================================================

local function ComputePath(TargetPosition)

    if not RootPart or not Humanoid then
        return false
    end

    ClearPath()

    local Path = PathfindingService:CreatePath({
        AgentRadius = AGENT_RADIUS,
        AgentHeight = AGENT_HEIGHT,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = WAYPOINT_SPACING
    })

    local Success = pcall(function()

        Path:ComputeAsync(
            RootPart.Position,
            TargetPosition
        )

    end)

    if not Success then
        return false
    end

    if Path.Status ~= Enum.PathStatus.Success then
        return false
    end

    local Waypoints = Path:GetWaypoints()

    if #Waypoints < 2 then
        return false
    end

    CurrentPath = Path
    CurrentWaypoints = Waypoints

    -- Start at waypoint 2 because waypoint 1 is usually current position.
    CurrentWaypointIndex = 2

    PathStartedTime = os.clock()

    PathBlockedConnection = Path.Blocked:Connect(function(BlockedWaypointIndex)

        if BlockedWaypointIndex >= CurrentWaypointIndex then
            NeedNewPath = true
        end

    end)

    return true
end

local function FollowPath()

    if not CurrentWaypoints then
        return false
    end

    if not RootPart or not Humanoid then
        return false
    end

    if CurrentWaypointIndex > #CurrentWaypoints then
        return true
    end

    local Waypoint = CurrentWaypoints[CurrentWaypointIndex]

    if not Waypoint then
        return true
    end

    if Waypoint.Action == Enum.PathWaypointAction.Jump then
        Humanoid.Jump = true
    end

    local Distance = (
        RootPart.Position - Waypoint.Position
    ).Magnitude

    if Distance <= WAYPOINT_REACHED_DISTANCE then

        CurrentWaypointIndex += 1

        if CurrentWaypointIndex > #CurrentWaypoints then
            return true
        end

        Waypoint = CurrentWaypoints[CurrentWaypointIndex]

        if Waypoint.Action == Enum.PathWaypointAction.Jump then
            Humanoid.Jump = true
        end

    end

    if os.clock() - LastMoveCommand >= MOVETO_REFRESH then

        Humanoid:MoveTo(Waypoint.Position)
        LastMoveCommand = os.clock()

    end

    if os.clock() - PathStartedTime > PATH_TIMEOUT then
        NeedNewPath = true
    end

    return false
end

--========================================================
-- STUCK DETECTION
--========================================================

local function ResetStuckDetection()

    if RootPart then
        LastProgressPosition = RootPart.Position
    else
        LastProgressPosition = nil
    end

    LastProgressTime = os.clock()

end

local function IsCurrentlyStuck(TargetPosition)

    if not RootPart then
        return false
    end

    if not LastProgressPosition then
        ResetStuckDetection()
        return false
    end

    local MovementDistance = (
        RootPart.Position - LastProgressPosition
    ).Magnitude

    if MovementDistance >= STUCK_DISTANCE then

        LastProgressPosition = RootPart.Position
        LastProgressTime = os.clock()

        return false
    end

    -- If we're already close enough, we're obviously not stuck.
    if TargetPosition then

        local TargetDistance = (
            RootPart.Position - TargetPosition
        ).Magnitude

        if TargetDistance <= TARGET_REACHED_DISTANCE then
            ResetStuckDetection()
            return false
        end

    end

    if os.clock() - LastProgressTime >= STUCK_TIME then
        return true
    end

    return false
end

--========================================================
-- SWITCH TO MOVETO
--========================================================

local function ReturnToMoveTo()

    ClearPath()

    MovementMode = "MoveTo"

    ResetStuckDetection()

end

--========================================================
-- HYBRID MOVEMENT
--========================================================

local function UpdateMovement(TargetPosition)

    if not IsReplaying then
        return
    end

    if not Humanoid or not RootPart then
        return
    end

    if not TargetPosition then
        return
    end

    --====================================================
    -- PATHFINDING MODE
    --====================================================

    if MovementMode == "Pathfinding" then

        -- If the target is now close, return to normal movement.
        local TargetDistance = (
            RootPart.Position - TargetPosition
        ).Magnitude

        if TargetDistance <= TARGET_REACHED_DISTANCE then

            ReturnToMoveTo()
            return

        end

        -- Recalculate if path became blocked.
        if NeedNewPath then

            local Success = ComputePath(TargetPosition)

            if not Success then

                -- If pathfinding fails, try MoveTo again.
                ReturnToMoveTo()

                Humanoid:MoveTo(TargetPosition)
                LastMoveCommand = os.clock()

            end

            return
        end

        -- Follow current path.
        local Finished = FollowPath()

        if Finished then

            ReturnToMoveTo()

            Humanoid:MoveTo(TargetPosition)
            LastMoveCommand = os.clock()

        end

        return
    end

    --====================================================
    -- NORMAL MOVETO MODE
    --====================================================

    MovementMode = "MoveTo"

    local Distance = (
        RootPart.Position - TargetPosition
    ).Magnitude

    -- Already close enough.
    if Distance <= TARGET_REACHED_DISTANCE then

        ResetStuckDetection()
        return

    end

    -- Normal MoveTo.
    if os.clock() - LastMoveCommand >= MOVETO_REFRESH then

        Humanoid:MoveTo(TargetPosition)

        LastMoveCommand = os.clock()

    end

    --====================================================
    -- CHECK FOR STUCK
    --====================================================

    if IsCurrentlyStuck(TargetPosition) then

        print("[Replay] Character stuck. Activating pathfinding.")

        MovementMode = "Pathfinding"

        local Success = ComputePath(TargetPosition)

        if not Success then

            warn("[Replay] Could not compute path. Retrying MoveTo.")

            MovementMode = "MoveTo"

            ResetStuckDetection()

            Humanoid:MoveTo(TargetPosition)
            LastMoveCommand = os.clock()

        end

    end

end

--========================================================
-- RECORDING
--========================================================

local function StartRecording()

    if IsRecording then
        return
    end

    if IsReplaying then
        return
    end

    SetupCharacter()

    local RecordingName = NameBox.Text

    if RecordingName == "" then
        RecordingName = "Recording " .. tostring(#Recordings + 1)
    end

    CurrentRecording = {

        Name = RecordingName,

        StartTime = os.clock(),

        Movement = {},

        Actions = {},

        QSkill = QSkillName,

        ESkill = ESkillName

    }

    IsRecording = true

    StatusLabel.Text = "Status: Recording..."

    ResetStuckDetection()

    -- Initial position
    if RootPart then

        table.insert(CurrentRecording.Movement, {

            Time = 0,

            Position = RootPart.Position,

            CFrame = RootPart.CFrame

        })

    end

    RecordConnection = RunService.Heartbeat:Connect(function()

        if not IsRecording then
            return
        end

        if not RootPart then
            return
        end

        table.insert(CurrentRecording.Movement, {

            Time = os.clock() - CurrentRecording.StartTime,

            Position = RootPart.Position,

            CFrame = RootPart.CFrame

        })

    end)

end

--========================================================
-- STOP RECORDING
--========================================================

local function StopRecording()

    if not IsRecording then
        return
    end

    IsRecording = false

    if RecordConnection then
        RecordConnection:Disconnect()
        RecordConnection = nil
    end

    if CurrentRecording then

        CurrentRecording.Duration =
            os.clock() - CurrentRecording.StartTime

        table.insert(
            Recordings,
            CurrentRecording
        )

        SelectedRecording = #Recordings

        RecordingDropdownButton.Text =
            CurrentRecording.Name

        RefreshRecordingList()

    end

    StatusLabel.Text = "Status: Recording saved"

    CurrentRecording = nil

end

--========================================================
-- RECORD SKILLS
--========================================================

UserInputService.InputBegan:Connect(function(Input, GameProcessed)

    if GameProcessed then
        return
    end

    if not IsRecording then
        return
    end

    if Input.KeyCode == Enum.KeyCode.Q then

        if CurrentRecording then

            table.insert(CurrentRecording.Actions, {

                Time =
                    os.clock() -
                    CurrentRecording.StartTime,

                ActionType = "Skill",

                Key = "q",

                SkillName = QSkillName

            })

        end

    elseif Input.KeyCode == Enum.KeyCode.E then

        if CurrentRecording then

            table.insert(CurrentRecording.Actions, {

                Time =
                    os.clock() -
                    CurrentRecording.StartTime,

                ActionType = "Skill",

                Key = "e",

                SkillName = ESkillName

            })

        end

    end

end)

--========================================================
-- FIND MOVEMENT POINT
--========================================================

local function GetMovementTarget(Movement, ReplayTime)

    if not Movement or #Movement == 0 then
        return nil
    end

    -- Binary-ish linear search.
    -- Recordings are normally small enough that this is fine.

    local Previous = Movement[1]
    local Next = nil

    for Index = 2, #Movement do

        local Point = Movement[Index]

        if Point.Time >= ReplayTime then

            Next = Point
            break

        end

        Previous = Point

    end

    if not Next then
        return Previous.Position
    end

    if not Previous then
        return Next.Position
    end

    local TimeDifference =
        Next.Time - Previous.Time

    if TimeDifference <= 0 then
        return Next.Position
    end

    local Alpha =
        math.clamp(
            (ReplayTime - Previous.Time) /
            TimeDifference,
            0,
            1
        )

    return Previous.Position:Lerp(
        Next.Position,
        Alpha
    )

end

--========================================================
-- FIND NEAREST RECORDED POINT
--========================================================

local function FindNearestMovementIndex(Recording)

    if not Recording or not Recording.Movement then
        return 1
    end

    if not RootPart then
        return 1
    end

    local ClosestIndex = 1
    local ClosestDistance = math.huge

    for Index, Point in ipairs(Recording.Movement) do

        local Distance = (
            RootPart.Position -
            Point.Position
        ).Magnitude

        if Distance < ClosestDistance then

            ClosestDistance = Distance
            ClosestIndex = Index

        end

    end

    return ClosestIndex
end

--========================================================
-- FIND ACTION INDEX FROM MOVEMENT INDEX
--========================================================

local function GetActionStartIndex(Recording, MovementIndex)

    if not Recording
        or not Recording.Movement
        or not Recording.Actions then

        return 1
    end

    local Point = Recording.Movement[MovementIndex]

    if not Point then
        return 1
    end

    local Time = Point.Time

    for Index, Action in ipairs(Recording.Actions) do

        if Action.Time >= Time then
            return Index
        end

    end

    return #Recording.Actions + 1
end

--========================================================
-- REPLAY SKILLS
--========================================================

local function ReplaySkills(Recording, StartingTime)

    if not Recording then
        return
    end

    local Actions = Recording.Actions

    if not Actions then
        return
    end

    for Index, Action in ipairs(Actions) do

        if Action.Time < StartingTime then
            continue
        end

        if not IsReplaying then
            break
        end

        local WaitTime =
            Action.Time -
            StartingTime

        if WaitTime > 0 then
            task.wait(WaitTime)
        end

        if not IsReplaying then
            break
        end

        ReplaySkill(
            Action.Key,
            Action.SkillName
        )

        StartingTime = Action.Time

    end

end

--========================================================
-- REPLAY MOVEMENT
--========================================================

local function ReplayMovement(Recording, StartingTime)

    if not Recording then
        return
    end

    local Movement = Recording.Movement

    if not Movement or #Movement == 0 then
        return
    end

    MovementMode = "MoveTo"

    ClearPath()

    ResetStuckDetection()

    local ReplayClock = os.clock()

    while IsReplaying do

        if not Humanoid or not RootPart then

            task.wait(0.1)

            continue

        end

        local ReplayTime =
            StartingTime +
            (os.clock() - ReplayClock)

        if ReplayTime > Recording.Duration then
            break
        end

        local TargetPosition =
            GetMovementTarget(
                Movement,
                ReplayTime
            )

        if TargetPosition then

            UpdateMovement(
                TargetPosition
            )

        end

        RunService.Heartbeat:Wait()

    end

end

--========================================================
-- REPLAY
--========================================================

local function StartReplay(Recording)

    if IsReplaying then
        return
    end

    if IsRecording then
        return
    end

    if not Recording then
        return
    end

    if not Recording.Movement
        or #Recording.Movement == 0 then

        StatusLabel.Text =
            "Status: Recording has no movement"

        return
    end

    SetupCharacter()

    IsReplaying = true

    MovementMode = "MoveTo"

    ClearPath()

    ResetStuckDetection()

    ReplayedActionIndexes = {}

    StatusLabel.Text =
        "Status: Replaying " .. Recording.Name

    local StartingTime = 0

    --====================================================
    -- MOVEMENT THREAD
    --====================================================

    task.spawn(function()

        ReplayMovement(
            Recording,
            StartingTime
        )

    end)

    --====================================================
    -- SKILL THREAD
    --====================================================

    task.spawn(function()

        ReplaySkills(
            Recording,
            StartingTime
        )

    end)

    --====================================================
    -- WAIT UNTIL REPLAY FINISHES
    --====================================================

    task.spawn(function()

        local StartClock = os.clock()

        while IsReplaying do

            if os.clock() - StartClock >= Recording.Duration then
                break
            end

            task.wait(0.1)

        end

        if IsReplaying then

            IsReplaying = false

            ClearPath()

            MovementMode = "MoveTo"

            StatusLabel.Text =
                "Status: Replay finished"

        end

    end)

end

--========================================================
-- STOP REPLAY
--========================================================

local function StopReplay()

    if not IsReplaying then
        return
    end

    IsReplaying = false

    ClearPath()

    MovementMode = "MoveTo"

    StatusLabel.Text =
        "Status: Replay stopped"

end

--========================================================
-- DEATH / RESPAWN RECOVERY
--========================================================

local function SetupDeathDetection()

    if CharacterConnection then
        CharacterConnection:Disconnect()
        CharacterConnection = nil
    end

    if not Humanoid then
        return
    end

    CharacterConnection =
        Humanoid.Died:Connect(function()

            if not IsReplaying then
                return
            end

            StatusLabel.Text =
                "Status: Waiting for respawn..."

            ClearPath()

            MovementMode = "MoveTo"

            local Recording = nil

            if SelectedRecording then
                Recording = Recordings[SelectedRecording]
            end

            if not Recording then
                IsReplaying = false
                return
            end

            local OldRecording = Recording

            task.spawn(function()

                local NewCharacter =
                    Player.CharacterAdded:Wait()

                Character = NewCharacter

                Humanoid =
                    NewCharacter:WaitForChild(
                        "Humanoid"
                    )

                RootPart =
                    NewCharacter:WaitForChild(
                        "HumanoidRootPart"
                    )

                if not IsReplaying then
                    return
                end

                -- Find the recorded point closest
                -- to where the player respawned.
                local NearestIndex =
                    FindNearestMovementIndex(
                        OldRecording
                    )

                local NearestPoint =
                    OldRecording.Movement[
                        NearestIndex
                    ]

                local ResumeTime = 0

                if NearestPoint then
                    ResumeTime =
                        NearestPoint.Time
                end

                StatusLabel.Text =
                    "Status: Resuming replay..."

                MovementMode = "MoveTo"

                ClearPath()

                ResetStuckDetection()

                -- Continue movement from nearest
                -- recorded point.
                task.spawn(function()

                    ReplayMovement(
                        OldRecording,
                        ResumeTime
                    )

                end)

                -- Resume skills from that point.
                task.spawn(function()

                    ReplaySkills(
                        OldRecording,
                        ResumeTime
                    )

                end)

                SetupDeathDetection()

            end)

        end)

end

SetupDeathDetection()

--========================================================
-- CHARACTER RESPAWN CONNECTION
--========================================================

Player.CharacterAdded:Connect(function(NewCharacter)

    Character = NewCharacter

    Humanoid =
        NewCharacter:WaitForChild(
            "Humanoid"
        )

    RootPart =
        NewCharacter:WaitForChild(
            "HumanoidRootPart"
        )

    SetupDeathDetection()

end)

--========================================================
-- BUTTON CONNECTIONS
--========================================================

RecordButton.MouseButton1Click:Connect(function()

    if IsReplaying then

        StatusLabel.Text =
            "Status: Stop replay first"

        return

    end

    StartRecording()

end)

StopButton.MouseButton1Click:Connect(function()

    if IsRecording then

        StopRecording()

    elseif IsReplaying then

        StopReplay()

    end

end)

ReplayButton.MouseButton1Click:Connect(function()

    if IsRecording then

        StatusLabel.Text =
            "Status: Stop recording first"

        return

    end

    if IsReplaying then

        StatusLabel.Text =
            "Status: Already replaying"

        return

    end

    if not SelectedRecording then

        StatusLabel.Text =
            "Status: Select a recording"

        return

    end

    local Recording =
        Recordings[SelectedRecording]

    if not Recording then
        return
    end

    StartReplay(Recording)

end)

--========================================================
-- INITIAL UI
--========================================================

RefreshRecordingList()

StatusLabel.Text = "Status: Idle"

print("Replay System", VERSION, "loaded.")
print("Movement mode: MoveTo -> Pathfinding when stuck")
print("Q Skill:", QSkillName)
print("E Skill:", ESkillName)
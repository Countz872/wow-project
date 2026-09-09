--[[
    REPLAY SYSTEM v1.6.0

    FEATURES
    ------------------------------------------------
    • Movement recording
    • Q / E skill recording
    • Q skill selector
    • E skill selector
    • Saved recordings
    • Replay
    • MoveTo for normal movement
    • Automatic stuck detection
    • Pathfinding only when stuck
    • Pathfinding around walls
    • Returns to MoveTo after escaping
    • Death / respawn recovery
    • Proper draggable UI
    • Cleaner UI
]]

--====================================================
-- SERVICES
--====================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

--====================================================
-- PLAYER
--====================================================

local Player = Players.LocalPlayer
local Backpack = Player:WaitForChild("Backpack")

local Remotes = ReplicatedStorage:WaitForChild("remotes")
local AbilityUsed = Remotes:WaitForChild("abilityUsed")

local Character
local Humanoid
local RootPart

local function SetupCharacter()
    Character = Player.Character or Player.CharacterAdded:Wait()

    Humanoid = Character:WaitForChild("Humanoid")
    RootPart = Character:WaitForChild("HumanoidRootPart")
end

SetupCharacter()

--====================================================
-- CONFIG
--====================================================

local VERSION = "v1.6.0"

local RECORD_INTERVAL = 0.05

-- MoveTo
local MOVETO_REFRESH = 0.10
local TARGET_REACHED_DISTANCE = 3

-- Stuck detection
local STUCK_TIME = 0.85
local STUCK_MIN_MOVEMENT = 0.45

-- When stuck, look this far ahead in the recording.
local PATH_LOOKAHEAD_POINTS = 15

-- Pathfinding
local AGENT_RADIUS = 2
local AGENT_HEIGHT = 5
local WAYPOINT_SPACING = 3

local WAYPOINT_REACHED_DISTANCE = 2.5

-- How often we are allowed to recompute a path
local PATH_RECALCULATE_DELAY = 0.35

-- Maximum amount of time to remain in pathfinding
-- before trying another path.
local PATH_TIMEOUT = 3

--====================================================
-- SKILLS
--====================================================

local QSkillName = "Inner Focus"
local ESkillName = "Pulse Waves"

--====================================================
-- STATE
--====================================================

local IsRecording = false
local IsReplaying = false

local CurrentRecording = nil

local Recordings = {}
local SelectedRecording = nil

-- Replay timing
local ReplayStartClock = 0
local ReplayStartTime = 0

-- Movement
local MovementMode = "MoveTo"

local CurrentTarget = nil
local LastMoveCommand = 0

-- Stuck detection
local LastCheckPosition = nil
local LastProgressTime = 0

-- Path
local CurrentPath = nil
local CurrentWaypoints = nil
local CurrentWaypointIndex = 1

local PathBlockedConnection = nil
local PathStartedTime = 0
local LastPathCalculation = 0

--====================================================
-- COLORS / UI HELPERS
--====================================================

local BG = Color3.fromRGB(18, 18, 21)
local PANEL = Color3.fromRGB(25, 25, 29)
local PANEL2 = Color3.fromRGB(32, 32, 37)
local INPUT = Color3.fromRGB(38, 38, 44)

local TEXT = Color3.fromRGB(240, 240, 245)
local SUBTEXT = Color3.fromRGB(155, 155, 165)

local GREEN = Color3.fromRGB(70, 170, 95)
local RED = Color3.fromRGB(185, 70, 70)
local BLUE = Color3.fromRGB(75, 105, 190)

local function Corner(Object, Radius)

    local C = Instance.new("UICorner")
    C.CornerRadius = UDim.new(0, Radius or 7)
    C.Parent = Object

    return C
end

local function Stroke(Object)

    local S = Instance.new("UIStroke")
    S.Color = Color3.fromRGB(55, 55, 62)
    S.Thickness = 1
    S.Transparency = 0.35
    S.Parent = Object

    return S
end

local function Label(Parent, Text, Size, Position)

    local L = Instance.new("TextLabel")

    L.BackgroundTransparency = 1
    L.Size = Size
    L.Position = Position

    L.Text = Text
    L.TextColor3 = TEXT
    L.TextSize = 13
    L.Font = Enum.Font.Gotham

    L.TextXAlignment = Enum.TextXAlignment.Left
    L.TextYAlignment = Enum.TextYAlignment.Center

    L.Parent = Parent

    return L
end

local function Button(Parent, Text, Size, Position, Color)

    local B = Instance.new("TextButton")

    B.Size = Size
    B.Position = Position

    B.BackgroundColor3 = Color or INPUT
    B.BorderSizePixel = 0

    B.Text = Text
    B.TextColor3 = TEXT
    B.TextSize = 13
    B.Font = Enum.Font.GothamMedium

    B.AutoButtonColor = true

    B.Parent = Parent

    Corner(B, 7)

    return B
end

--====================================================
-- GUI
--====================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ReplaySystem"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = Player:WaitForChild("PlayerGui")

local Main = Instance.new("Frame")

Main.Name = "Main"
Main.Size = UDim2.fromOffset(410, 535)
Main.Position = UDim2.new(0.5, -205, 0.5, -267)

Main.BackgroundColor3 = BG
Main.BorderSizePixel = 0

Main.Parent = ScreenGui

Corner(Main, 12)
Stroke(Main)

--====================================================
-- HEADER
--====================================================

local Header = Instance.new("Frame")

Header.Size = UDim2.new(1, 0, 0, 52)

Header.BackgroundColor3 = PANEL
Header.BorderSizePixel = 0

Header.Parent = Main

Corner(Header, 12)

-- Cover bottom rounded corners
local HeaderBottom = Instance.new("Frame")
HeaderBottom.Size = UDim2.new(1, 0, 0, 12)
HeaderBottom.Position = UDim2.new(0, 0, 1, -12)
HeaderBottom.BackgroundColor3 = PANEL
HeaderBottom.BorderSizePixel = 0
HeaderBottom.Parent = Header

local Title = Label(
    Header,
    "Replay System",
    UDim2.new(1, -130, 0, 25),
    UDim2.fromOffset(16, 7)
)

Title.Font = Enum.Font.GothamBold
Title.TextSize = 17

local Version = Label(
    Header,
    VERSION,
    UDim2.fromOffset(70, 20),
    UDim2.fromOffset(16, 28)
)

Version.TextColor3 = SUBTEXT
Version.TextSize = 10

local MinimizeButton = Button(
    Header,
    "−",
    UDim2.fromOffset(32, 32),
    UDim2.new(1, -42, 0, 10),
    INPUT
)

MinimizeButton.TextSize = 20

--====================================================
-- DRAGGING
--====================================================

local Dragging = false
local DragInput = nil
local DragStart = nil
local StartPosition = nil

Header.InputBegan:Connect(function(Input)

    if Input.UserInputType == Enum.UserInputType.MouseButton1
        or Input.UserInputType == Enum.UserInputType.Touch then

        Dragging = true

        DragStart = Input.Position
        StartPosition = Main.Position

        DragInput = Input

    end

end)

Header.InputEnded:Connect(function(Input)

    if Input == DragInput then
        Dragging = false
        DragInput = nil
    end

end)

UserInputService.InputChanged:Connect(function(Input)

    if not Dragging then
        return
    end

    if Input.UserInputType ~= Enum.UserInputType.MouseMovement
        and Input.UserInputType ~= Enum.UserInputType.Touch then
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

--====================================================
-- CONTENT
--====================================================

local Content = Instance.new("ScrollingFrame")

Content.Size = UDim2.new(1, -20, 1, -62)
Content.Position = UDim2.fromOffset(10, 57)

Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0

Content.ScrollBarThickness = 3
Content.ScrollBarImageTransparency = 0.4

Content.CanvasSize = UDim2.new(0, 0, 0, 610)

Content.Parent = Main

--====================================================
-- RECORDING SECTION
--====================================================

local RecordingSection = Instance.new("Frame")

RecordingSection.Size = UDim2.new(1, 0, 0, 155)
RecordingSection.Position = UDim2.fromOffset(0, 0)

RecordingSection.BackgroundColor3 = PANEL
RecordingSection.BorderSizePixel = 0

RecordingSection.Parent = Content

Corner(RecordingSection, 9)

local RecordingTitle = Label(
    RecordingSection,
    "RECORDING",
    UDim2.new(1, -20, 0, 25),
    UDim2.fromOffset(12, 8)
)

RecordingTitle.Font = Enum.Font.GothamBold
RecordingTitle.TextSize = 11
RecordingTitle.TextColor3 = SUBTEXT

local NameBox = Instance.new("TextBox")

NameBox.Size = UDim2.new(1, -24, 0, 36)
NameBox.Position = UDim2.fromOffset(12, 37)

NameBox.BackgroundColor3 = INPUT
NameBox.BorderSizePixel = 0

NameBox.PlaceholderText = "Recording name..."
NameBox.PlaceholderColor3 = Color3.fromRGB(110, 110, 120)

NameBox.Text = ""
NameBox.TextColor3 = TEXT
NameBox.TextSize = 13
NameBox.Font = Enum.Font.Gotham

NameBox.ClearTextOnFocus = false

NameBox.Parent = RecordingSection

Corner(NameBox, 7)

local RecordButton = Button(
    RecordingSection,
    "●  Record",
    UDim2.new(0.5, -18, 0, 40),
    UDim2.fromOffset(12, 85),
    GREEN
)

local StopButton = Button(
    RecordingSection,
    "■  Stop",
    UDim2.new(0.5, -18, 0, 40),
    UDim2.new(0.5, 6, 0, 85),
    RED
)

--====================================================
-- SKILL SECTION
--====================================================

local SkillSection = Instance.new("Frame")

SkillSection.Size = UDim2.new(1, 0, 0, 150)
SkillSection.Position = UDim2.fromOffset(0, 165)

SkillSection.BackgroundColor3 = PANEL
SkillSection.BorderSizePixel = 0

SkillSection.Parent = Content

Corner(SkillSection, 9)

local SkillTitle = Label(
    SkillSection,
    "SKILLS",
    UDim2.new(1, -20, 0, 25),
    UDim2.fromOffset(12, 8)
)

SkillTitle.Font = Enum.Font.GothamBold
SkillTitle.TextSize = 11
SkillTitle.TextColor3 = SUBTEXT

local QLabel = Label(
    SkillSection,
    "Q",
    UDim2.fromOffset(30, 25),
    UDim2.fromOffset(12, 36)
)

QLabel.Font = Enum.Font.GothamBold

local ELabel = Label(
    SkillSection,
    "E",
    UDim2.fromOffset(30, 25),
    UDim2.new(0.5, 6, 0, 36)
)

ELabel.Font = Enum.Font.GothamBold

local QButton = Button(
    SkillSection,
    QSkillName,
    UDim2.new(0.5, -45, 0, 36),
    UDim2.fromOffset(42, 33),
    INPUT
)

local EButton = Button(
    SkillSection,
    ESkillName,
    UDim2.new(0.5, -45, 0, 36),
    UDim2.new(0.5, 42, 0, 33),
    INPUT
)

-- Dropdowns

local QDropdown = Instance.new("ScrollingFrame")

QDropdown.Size = UDim2.new(0.5, -24, 0, 75)
QDropdown.Position = UDim2.fromOffset(42, 72)

QDropdown.BackgroundColor3 = PANEL2
QDropdown.BorderSizePixel = 0

QDropdown.ScrollBarThickness = 3
QDropdown.Visible = false
QDropdown.ZIndex = 50

QDropdown.Parent = SkillSection

Corner(QDropdown, 7)

local EDropdown = Instance.new("ScrollingFrame")

EDropdown.Size = UDim2.new(0.5, -24, 0, 75)
EDropdown.Position = UDim2.new(0.5, 42, 0, 72)

EDropdown.BackgroundColor3 = PANEL2
EDropdown.BorderSizePixel = 0

EDropdown.ScrollBarThickness = 3
EDropdown.Visible = false
EDropdown.ZIndex = 50

EDropdown.Parent = SkillSection

Corner(EDropdown, 7)

local function GetSkills()

    local Skills = {}

    local function Scan(Container)

        for _, Object in ipairs(Container:GetChildren()) do

            local AbilityEvent =
                Object:FindFirstChild("abilityEvent")

            local SpellEvent =
                Object:FindFirstChild("spellEvent")

            if AbilityEvent or SpellEvent then

                if not table.find(Skills, Object.Name) then
                    table.insert(Skills, Object.Name)
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

local function PopulateSkillDropdown(Dropdown, IsQ)

    for _, Child in ipairs(Dropdown:GetChildren()) do

        if Child:IsA("TextButton") then
            Child:Destroy()
        end

    end

    local Skills = GetSkills()

    local Y = 4

    for _, SkillName in ipairs(Skills) do

        local SkillButton = Button(
            Dropdown,
            SkillName,
            UDim2.new(1, -8, 0, 27),
            UDim2.fromOffset(4, Y),
            INPUT
        )

        SkillButton.ZIndex = 51
        SkillButton.TextSize = 11

        SkillButton.MouseButton1Click:Connect(function()

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

        Y += 30

    end

    Dropdown.CanvasSize =
        UDim2.new(0, 0, 0, math.max(Y, 75))

end

QButton.MouseButton1Click:Connect(function()

    EDropdown.Visible = false

    PopulateSkillDropdown(QDropdown, true)

    QDropdown.Visible = not QDropdown.Visible

end)

EButton.MouseButton1Click:Connect(function()

    QDropdown.Visible = false

    PopulateSkillDropdown(EDropdown, false)

    EDropdown.Visible = not EDropdown.Visible

end)

--====================================================
-- SAVED RECORDINGS
--====================================================

local SavedSection = Instance.new("Frame")

SavedSection.Size = UDim2.new(1, 0, 0, 190)
SavedSection.Position = UDim2.fromOffset(0, 325)

SavedSection.BackgroundColor3 = PANEL
SavedSection.BorderSizePixel = 0

SavedSection.Parent = Content

Corner(SavedSection, 9)

local SavedTitle = Label(
    SavedSection,
    "SAVED RECORDINGS",
    UDim2.new(1, -20, 0, 25),
    UDim2.fromOffset(12, 8)
)

SavedTitle.Font = Enum.Font.GothamBold
SavedTitle.TextSize = 11
SavedTitle.TextColor3 = SUBTEXT

local RecordingDropdownButton = Button(
    SavedSection,
    "Select recording...",
    UDim2.new(1, -24, 0, 38),
    UDim2.fromOffset(12, 37),
    INPUT
)

RecordingDropdownButton.TextXAlignment = Enum.TextXAlignment.Left

local RecordingPadding = Instance.new("UIPadding")
RecordingPadding.PaddingLeft = UDim.new(0, 10)
RecordingPadding.Parent = RecordingDropdownButton

local RecordingList = Instance.new("ScrollingFrame")

RecordingList.Size = UDim2.new(1, -24, 0, 80)
RecordingList.Position = UDim2.fromOffset(12, 79)

RecordingList.BackgroundColor3 = PANEL2
RecordingList.BorderSizePixel = 0

RecordingList.ScrollBarThickness = 3
RecordingList.Visible = false
RecordingList.ZIndex = 50

RecordingList.Parent = SavedSection

Corner(RecordingList, 7)

local RecordingLayout = Instance.new("UIListLayout")
RecordingLayout.Padding = UDim.new(0, 3)
RecordingLayout.Parent = RecordingList

--====================================================
-- STATUS
--====================================================

local StatusSection = Instance.new("Frame")

StatusSection.Size = UDim2.new(1, 0, 0, 85)
StatusSection.Position = UDim2.fromOffset(0, 525)

StatusSection.BackgroundColor3 = PANEL
StatusSection.BorderSizePixel = 0

StatusSection.Parent = Content

Corner(StatusSection, 9)

local StatusTitle = Label(
    StatusSection,
    "STATUS",
    UDim2.new(1, -20, 0, 20),
    UDim2.fromOffset(12, 7)
)

StatusTitle.Font = Enum.Font.GothamBold
StatusTitle.TextSize = 10
StatusTitle.TextColor3 = SUBTEXT

local StatusLabel = Label(
    StatusSection,
    "Idle",
    UDim2.new(1, -24, 0, 25),
    UDim2.fromOffset(12, 30)
)

StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextColor3 = TEXT

--====================================================
-- REPLAY BUTTON
--====================================================

local ReplayButton = Button(
    Content,
    "▶  REPLAY SELECTED",
    UDim2.new(1, 0, 0, 45),
    UDim2.fromOffset(0, 620),
    BLUE
)

ReplayButton.Font = Enum.Font.GothamBold
ReplayButton.TextSize = 14

Content.CanvasSize = UDim2.fromOffset(0, 680)

--====================================================
-- MINIMIZE
--====================================================

local Minimized = false

MinimizeButton.MouseButton1Click:Connect(function()

    Minimized = not Minimized

    Content.Visible = not Minimized

    if Minimized then

        Main.Size = UDim2.fromOffset(410, 52)
        MinimizeButton.Text = "+"

    else

        Main.Size = UDim2.fromOffset(410, 535)
        MinimizeButton.Text = "−"

    end

end)

--====================================================
-- SKILL REPLAY
--====================================================

local function FindSkill(SkillName)

    if not SkillName then
        return nil
    end

    local Skill =
        Backpack:FindFirstChild(SkillName)

    if Skill then
        return Skill
    end

    if Character then

        Skill =
            Character:FindFirstChild(SkillName)

        if Skill then
            return Skill
        end

    end

    return nil
end

local function ReplaySkill(Key, SkillName)

    local Skill = FindSkill(SkillName)

    if not Skill then

        warn(
            "[Replay] Skill not found:",
            SkillName
        )

        return false
    end

    local Success, ErrorMessage =
        pcall(function()

            AbilityUsed:FireServer(
                Key,
                Skill
            )

            local Event =
                Skill:FindFirstChild(
                    "abilityEvent"
                )

            if not Event then

                Event =
                    Skill:FindFirstChild(
                        "spellEvent"
                    )

            end

            if not Event then

                error(
                    "No abilityEvent/spellEvent found"
                )

            end

            Event:FireServer()

        end)

    if not Success then

        warn(
            "[Replay] Skill error:",
            ErrorMessage
        )

        return false

    end

    return true
end

--====================================================
-- PATH CLEANUP
--====================================================

local function ClearPath()

    if PathBlockedConnection then

        PathBlockedConnection:Disconnect()
        PathBlockedConnection = nil

    end

    CurrentPath = nil
    CurrentWaypoints = nil
    CurrentWaypointIndex = 1

end

--====================================================
-- RESET STUCK
--====================================================

local function ResetStuck()

    if RootPart then
        LastCheckPosition = RootPart.Position
    else
        LastCheckPosition = nil
    end

    LastProgressTime = os.clock()

end

--====================================================
-- COMPUTE PATH
--====================================================

local function ComputePath(TargetPosition)

    if not RootPart or not Humanoid then
        return false
    end

    if os.clock() - LastPathCalculation <
        PATH_RECALCULATE_DELAY then

        return false
    end

    LastPathCalculation = os.clock()

    ClearPath()

    local Path =
        PathfindingService:CreatePath({

            AgentRadius = AGENT_RADIUS,
            AgentHeight = AGENT_HEIGHT,

            AgentCanJump = true,
            AgentCanClimb = true,

            WaypointSpacing =
                WAYPOINT_SPACING

        })

    local Success = pcall(function()

        Path:ComputeAsync(
            RootPart.Position,
            TargetPosition
        )

    end)

    if not Success then

        warn("[Replay] Path computation failed")

        return false
    end

    if Path.Status ~= Enum.PathStatus.Success then

        warn(
            "[Replay] No path:",
            Path.Status.Name
        )

        return false
    end

    local Waypoints =
        Path:GetWaypoints()

    if #Waypoints < 2 then
        return false
    end

    CurrentPath = Path
    CurrentWaypoints = Waypoints

    -- Skip waypoint 1 because it is our current position.
    CurrentWaypointIndex = 2

    PathStartedTime = os.clock()

    PathBlockedConnection =
        Path.Blocked:Connect(
            function(BlockedIndex)

                if BlockedIndex >=
                    CurrentWaypointIndex then

                    CurrentPath = nil
                    NeedNewPath = true

                end

            end
        )

    NeedNewPath = false

    return true
end

-- NeedNewPath is deliberately global state.
NeedNewPath = false

--====================================================
-- PATH TARGET
--====================================================

local function GetPathTarget(
    Movement,
    CurrentIndex
)

    if not Movement then
        return nil
    end

    local TargetIndex =
        math.min(
            CurrentIndex +
                PATH_LOOKAHEAD_POINTS,
            #Movement
        )

    local Point =
        Movement[TargetIndex]

    if Point then
        return Point.Position
    end

    return nil
end

--====================================================
-- FOLLOW PATH
--====================================================

local function UpdatePathMovement(
    FinalTarget
)

    if not CurrentWaypoints then
        return false
    end

    if not RootPart or not Humanoid then
        return false
    end

    -- Path was blocked.
    if NeedNewPath then
        return false
    end

    -- Path taking too long.
    if os.clock() - PathStartedTime >
        PATH_TIMEOUT then

        NeedNewPath = true

        return false
    end

    if CurrentWaypointIndex >
        #CurrentWaypoints then

        return true
    end

    local Waypoint =
        CurrentWaypoints[
            CurrentWaypointIndex
        ]

    if not Waypoint then
        return true
    end

    local Distance =
        (
            RootPart.Position -
            Waypoint.Position
        ).Magnitude

    if Distance <=
        WAYPOINT_REACHED_DISTANCE then

        CurrentWaypointIndex += 1

        if CurrentWaypointIndex >
            #CurrentWaypoints then

            return true
        end

        Waypoint =
            CurrentWaypoints[
                CurrentWaypointIndex
            ]

    end

    if Waypoint.Action ==
        Enum.PathWaypointAction.Jump then

        Humanoid.Jump = true

    end

    if os.clock() - LastMoveCommand >=
        MOVETO_REFRESH then

        Humanoid:MoveTo(
            Waypoint.Position
        )

        LastMoveCommand = os.clock()

    end

    -- If we reached the final target,
    -- pathfinding is no longer needed.
    if FinalTarget then

        local FinalDistance =
            (
                RootPart.Position -
                FinalTarget
            ).Magnitude

        if FinalDistance <=
            TARGET_REACHED_DISTANCE then

            return true

        end

    end

    return false
end

--====================================================
-- STUCK CHECK
--====================================================

local function CheckStuck(
    TargetPosition
)

    if not RootPart then
        return false
    end

    if not LastCheckPosition then

        ResetStuck()

        return false
    end

    local DistanceMoved =
        (
            RootPart.Position -
            LastCheckPosition
        ).Magnitude

    if DistanceMoved >=
        STUCK_MIN_MOVEMENT then

        LastCheckPosition =
            RootPart.Position

        LastProgressTime =
            os.clock()

        return false
    end

    if TargetPosition then

        local DistanceToTarget =
            (
                RootPart.Position -
                TargetPosition
            ).Magnitude

        if DistanceToTarget <=
            TARGET_REACHED_DISTANCE then

            ResetStuck()

            return false
        end

    end

    return
        os.clock() -
        LastProgressTime >=
        STUCK_TIME
end

--====================================================
-- START PATHFINDING
--====================================================

local function EnterPathfinding(
    Movement,
    CurrentIndex,
    NormalTarget
)

    if not RootPart then
        return
    end

    local PathTarget =
        GetPathTarget(
            Movement,
            CurrentIndex
        )

    if not PathTarget then
        PathTarget = NormalTarget
    end

    if not PathTarget then
        return
    end

    local Success =
        ComputePath(PathTarget)

    if Success then

        MovementMode =
            "Pathfinding"

        NeedNewPath = false

        ResetStuck()

        StatusLabel.Text =
            "Pathfinding around obstacle..."

    else

        -- Pathfinding couldn't find a route.
        -- Continue trying MoveTo rather than stopping.
        MovementMode =
            "MoveTo"

        ResetStuck()

    end

end

--====================================================
-- HYBRID MOVEMENT
--====================================================

local function UpdateMovement(
    TargetPosition,
    Movement,
    CurrentIndex
)

    if not IsReplaying then
        return
    end

    if not Humanoid or not RootPart then
        return
    end

    if not TargetPosition then
        return
    end

    --================================================
    -- PATHFINDING MODE
    --================================================

    if MovementMode ==
        "Pathfinding" then

        local Finished =
            UpdatePathMovement(
                TargetPosition
            )

        if Finished then

            ClearPath()

            MovementMode =
                "MoveTo"

            ResetStuck()

            Humanoid:MoveTo(
                TargetPosition
            )

            LastMoveCommand =
                os.clock()

            StatusLabel.Text =
                "Replaying..."

            return
        end

        -- If path became blocked,
        -- find another path.
        if NeedNewPath then

            local PathTarget =
                GetPathTarget(
                    Movement,
                    CurrentIndex
                )

            if PathTarget then

                local Success =
                    ComputePath(
                        PathTarget
                    )

                if Success then

                    NeedNewPath =
                        false

                    ResetStuck()

                    return

                end

            end

            -- Failed path calculation.
            -- Fall back to MoveTo.
            MovementMode =
                "MoveTo"

            ClearPath()

            ResetStuck()

            Humanoid:MoveTo(
                TargetPosition
            )

            LastMoveCommand =
                os.clock()

        end

        return
    end

    --================================================
    -- NORMAL MOVETO MODE
    --================================================

    MovementMode =
        "MoveTo"

    local Distance =
        (
            RootPart.Position -
            TargetPosition
        ).Magnitude

    if Distance <=
        TARGET_REACHED_DISTANCE then

        ResetStuck()

        return
    end

    if os.clock() -
        LastMoveCommand >=
        MOVETO_REFRESH then

        Humanoid:MoveTo(
            TargetPosition
        )

        LastMoveCommand =
            os.clock()

    end

    --================================================
    -- STUCK DETECTION
    --================================================

    if CheckStuck(
        TargetPosition
    ) then

        EnterPathfinding(
            Movement,
            CurrentIndex,
            TargetPosition
        )

    end

end

--====================================================
-- RECORDING
--====================================================

local function StartRecording()

    if IsRecording then
        return
    end

    if IsReplaying then

        StatusLabel.Text =
            "Stop the replay first"

        return
    end

    SetupCharacter()

    local Name =
        NameBox.Text

    if Name == "" then

        Name =
            "Recording " ..
            tostring(#Recordings + 1)

    end

    CurrentRecording = {

        Name = Name,

        StartTime =
            os.clock(),

        Duration = 0,

        Movement = {},

        Actions = {},

        QSkill =
            QSkillName,

        ESkill =
            ESkillName

    }

    IsRecording = true

    StatusLabel.Text =
        "Recording..."

    local StartClock =
        os.clock()

    if RootPart then

        table.insert(
            CurrentRecording.Movement,
            {

                Time = 0,

                Position =
                    RootPart.Position,

                CFrame =
                    RootPart.CFrame

            }
        )

    end

    RecordConnection =
        RunService.Heartbeat:Connect(
            function()

                if not IsRecording then
                    return
                end

                if not RootPart then
                    return
                end

                local Time =
                    os.clock() -
                    StartClock

                -- Only record at approximately
                -- RECORD_INTERVAL.
                local Movement =
                    CurrentRecording.Movement

                local Last =
                    Movement[#Movement]

                if Last and
                    Time - Last.Time <
                    RECORD_INTERVAL then

                    return
                end

                table.insert(
                    Movement,
                    {

                        Time = Time,

                        Position =
                            RootPart.Position,

                        CFrame =
                            RootPart.CFrame

                    }
                )

            end
        )

end

--====================================================
-- STOP RECORDING
--====================================================

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
            os.clock() -
            CurrentRecording.StartTime

        table.insert(
            Recordings,
            CurrentRecording
        )

        SelectedRecording =
            #Recordings

        RecordingDropdownButton.Text =
            CurrentRecording.Name

    end

    StatusLabel.Text =
        "Recording saved"

    CurrentRecording = nil

end

--====================================================
-- RECORD Q / E
--====================================================

UserInputService.InputBegan:Connect(
    function(Input, GameProcessed)

        if GameProcessed then
            return
        end

        if not IsRecording then
            return
        end

        if not CurrentRecording then
            return
        end

        if Input.KeyCode ==
            Enum.KeyCode.Q then

            table.insert(
                CurrentRecording.Actions,
                {

                    Time =
                        os.clock() -
                        CurrentRecording.StartTime,

                    ActionType =
                        "Skill",

                    Key = "q",

                    SkillName =
                        QSkillName

                }
            )

        elseif Input.KeyCode ==
            Enum.KeyCode.E then

            table.insert(
                CurrentRecording.Actions,
                {

                    Time =
                        os.clock() -
                        CurrentRecording.StartTime,

                    ActionType =
                        "Skill",

                    Key = "e",

                    SkillName =
                        ESkillName

                }
            )

        end

    end
)

--====================================================
-- REFRESH RECORDING LIST
--====================================================

local function RefreshRecordingList()

    for _, Child in
        ipairs(
            RecordingList:GetChildren()
        ) do

        if Child:IsA("TextButton") then
            Child:Destroy()
        end

    end

    local Y = 4

    for Index, Recording in
        ipairs(Recordings) do

        local B =
            Button(
                RecordingList,
                Recording.Name,
                UDim2.new(1, -8, 0, 29),
                UDim2.fromOffset(4, Y),
                INPUT
            )

        B.ZIndex = 51
        B.TextSize = 11
        B.TextXAlignment =
            Enum.TextXAlignment.Left

        local Padding =
            Instance.new("UIPadding")

        Padding.PaddingLeft =
            UDim.new(0, 8)

        Padding.Parent = B

        B.MouseButton1Click:Connect(
            function()

                SelectedRecording =
                    Index

                RecordingDropdownButton.Text =
                    Recording.Name

                RecordingList.Visible =
                    false

            end
        )

        Y += 32

    end

    RecordingList.CanvasSize =
        UDim2.fromOffset(
            0,
            math.max(Y, 80)
        )

end

RecordingDropdownButton.MouseButton1Click:Connect(
    function()

        RecordingList.Visible =
            not RecordingList.Visible

    end
)

--====================================================
-- MOVEMENT TARGET
--====================================================

local function GetMovementTarget(
    Movement,
    ReplayTime
)

    if not Movement
        or #Movement == 0 then

        return nil, 1
    end

    local Previous =
        Movement[1]

    local PreviousIndex = 1

    for Index = 2, #Movement do

        local Point =
            Movement[Index]

        if Point.Time >=
            ReplayTime then

            local TimeDifference =
                Point.Time -
                Previous.Time

            if TimeDifference <= 0 then

                return Point.Position,
                    Index

            end

            local Alpha =
                math.clamp(
                    (
                        ReplayTime -
                        Previous.Time
                    ) /
                    TimeDifference,

                    0,
                    1
                )

            return
                Previous.Position:Lerp(
                    Point.Position,
                    Alpha
                ),
                PreviousIndex

        end

        Previous =
            Point

        PreviousIndex =
            Index

    end

    return
        Previous.Position,
        PreviousIndex

end

--====================================================
-- REPLAY SKILLS
--====================================================

local function ReplaySkills(
    Recording,
    StartingTime
)

    if not Recording then
        return
    end

    local Actions =
        Recording.Actions

    if not Actions then
        return
    end

    local LastTime =
        StartingTime

    for _, Action in
        ipairs(Actions) do

        if not IsReplaying then
            break
        end

        if Action.Time <
            StartingTime then

            continue

        end

        local WaitTime =
            Action.Time -
            LastTime

        if WaitTime > 0 then

            task.wait(
                WaitTime
            )

        end

        if not IsReplaying then
            break
        end

        ReplaySkill(
            Action.Key,
            Action.SkillName
        )

        LastTime =
            Action.Time

    end

end

--====================================================
-- REPLAY MOVEMENT
--====================================================

local function ReplayMovement(
    Recording,
    StartingTime
)

    if not Recording then
        return
    end

    local Movement =
        Recording.Movement

    if not Movement
        or #Movement == 0 then

        return
    end

    MovementMode =
        "MoveTo"

    ClearPath()

    ResetStuck()

    ReplayStartClock =
        os.clock()

    while IsReplaying do

        if not Humanoid
            or not RootPart then

            task.wait(0.1)

            continue
        end

        local ReplayTime =
            StartingTime +
            (
                os.clock() -
                ReplayStartClock
            )

        -- IMPORTANT:
        -- Don't instantly finish just because
        -- the recording timer is over.
        --
        -- We still allow the character to reach
        -- the final recorded point.

        local FinalTime =
            Recording.Duration

        local TargetPosition,
            MovementIndex =
            GetMovementTarget(
                Movement,
                math.min(
                    ReplayTime,
                    FinalTime
                )
            )

        if TargetPosition then

            UpdateMovement(
                TargetPosition,
                Movement,
                MovementIndex
            )

        end

        if ReplayTime >= FinalTime then

            local FinalPoint =
                Movement[#Movement]

            if FinalPoint then

                local FinalDistance =
                    (
                        RootPart.Position -
                        FinalPoint.Position
                    ).Magnitude

                -- Only finish after the player
                -- actually reaches the final point.
                if FinalDistance <=
                    TARGET_REACHED_DISTANCE then

                    break
                end

            else

                break

            end

        end

        RunService.Heartbeat:Wait()

    end

end

--====================================================
-- STOP REPLAY
--====================================================

local function StopReplay()

    if not IsReplaying then
        return
    end

    IsReplaying = false

    ClearPath()

    MovementMode =
        "MoveTo"

    StatusLabel.Text =
        "Replay stopped"

end

--====================================================
-- START REPLAY
--====================================================

local function StartReplay(
    Recording
)

    if IsReplaying then
        return
    end

    if IsRecording then

        StatusLabel.Text =
            "Stop recording first"

        return
    end

    if not Recording then
        return
    end

    if not Recording.Movement
        or #Recording.Movement == 0 then

        StatusLabel.Text =
            "Recording has no movement"

        return
    end

    SetupCharacter()

    IsReplaying = true

    MovementMode =
        "MoveTo"

    ClearPath()

    ResetStuck()

    ReplayStartTime = 0

    StatusLabel.Text =
        "Replaying: " ..
        Recording.Name

    -- Movement
    task.spawn(
        function()

            ReplayMovement(
                Recording,
                0
            )

        end
    )

    -- Skills
    task.spawn(
        function()

            ReplaySkills(
                Recording,
                0
            )

        end
    )

    -- Monitor replay.
    task.spawn(
        function()

            while IsReplaying do

                task.wait(0.1)

            end

            ClearPath()

            MovementMode =
                "MoveTo"

            if StatusLabel.Text:find(
                "Replaying"
            ) then

                StatusLabel.Text =
                    "Replay finished"

            end

        end
    )

end

--====================================================
-- DEATH / RESPAWN
--====================================================

local DeathConnection

local function SetupDeathDetection()

    if DeathConnection then

        DeathConnection:Disconnect()
        DeathConnection = nil

    end

    if not Humanoid then
        return
    end

    DeathConnection =
        Humanoid.Died:Connect(
            function()

                if not IsReplaying then
                    return
                end

                StatusLabel.Text =
                    "Waiting for respawn..."

                ClearPath()

                task.spawn(
                    function()

                        local NewCharacter =
                            Player.CharacterAdded:Wait()

                        Character =
                            NewCharacter

                        Humanoid =
                            NewCharacter:
                            WaitForChild(
                                "Humanoid"
                            )

                        RootPart =
                            NewCharacter:
                            WaitForChild(
                                "HumanoidRootPart"
                            )

                        if not IsReplaying then
                            return
                        end

                        local Recording

                        if SelectedRecording then

                            Recording =
                                Recordings[
                                    SelectedRecording
                                ]

                        end

                        if not Recording then

                            IsReplaying =
                                false

                            return

                        end

                        -- Find nearest recorded point
                        -- to the respawn location.
                        local ClosestIndex = 1
                        local ClosestDistance =
                            math.huge

                        for Index, Point in
                            ipairs(
                                Recording.Movement
                            ) do

                            local Distance =
                                (
                                    RootPart.Position -
                                    Point.Position
                                ).Magnitude

                            if Distance <
                                ClosestDistance then

                                ClosestDistance =
                                    Distance

                                ClosestIndex =
                                    Index

                            end

                        end

                        local ResumePoint =
                            Recording.Movement[
                                ClosestIndex
                            ]

                        local ResumeTime =
                            0

                        if ResumePoint then

                            ResumeTime =
                                ResumePoint.Time

                        end

                        StatusLabel.Text =
                            "Resuming replay..."

                        ClearPath()

                        MovementMode =
                            "MoveTo"

                        ResetStuck()

                        -- Resume movement
                        task.spawn(
                            function()

                                ReplayMovement(
                                    Recording,
                                    ResumeTime
                                )

                            end
                        )

                        -- Resume skills
                        task.spawn(
                            function()

                                ReplaySkills(
                                    Recording,
                                    ResumeTime
                                )

                            end
                        )

                        SetupDeathDetection()

                    end
                )

            end
        )

end

SetupDeathDetection()

--====================================================
-- CHARACTER ADDED
--====================================================

Player.CharacterAdded:Connect(
    function(NewCharacter)

        Character =
            NewCharacter

        Humanoid =
            NewCharacter:
            WaitForChild(
                "Humanoid"
            )

        RootPart =
            NewCharacter:
            WaitForChild(
                "HumanoidRootPart"
            )

        if IsReplaying then

            ClearPath()

            MovementMode =
                "MoveTo"

            ResetStuck()

        end

        SetupDeathDetection()

    end
)

--====================================================
-- BUTTONS
--====================================================

RecordButton.MouseButton1Click:Connect(
    function()

        StartRecording()

    end
)

StopButton.MouseButton1Click:Connect(
    function()

        if IsRecording then

            StopRecording()

        elseif IsReplaying then

            StopReplay()

        end

    end
)

ReplayButton.MouseButton1Click:Connect(
    function()

        if IsRecording then

            StatusLabel.Text =
                "Stop recording first"

            return
        end

        if IsReplaying then

            StatusLabel.Text =
                "Already replaying"

            return
        end

        if not SelectedRecording then

            StatusLabel.Text =
                "Select a recording"

            return
        end

        local Recording =
            Recordings[
                SelectedRecording
            ]

        if Recording then

            StartReplay(
                Recording
            )

        end

    end
)

--====================================================
-- INITIALIZE
--====================================================

RefreshRecordingList()

StatusLabel.Text = "Idle"

print(
    "[Replay System]",
    VERSION,
    "loaded"
)

print(
    "[Replay System] Hybrid MoveTo + Pathfinding enabled"
)
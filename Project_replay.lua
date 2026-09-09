--// Replay System v1.7.0
--// Movement + Pathfinding + Skill Replay + Improved UI

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local Player = Players.LocalPlayer
local Backpack = Player:WaitForChild("Backpack")

local Remotes = ReplicatedStorage:WaitForChild("remotes")
local AbilityUsed = Remotes:WaitForChild("abilityUsed")

--------------------------------------------------
-- CONFIG
--------------------------------------------------

local VERSION = "v1.7.0"

local RECORD_INTERVAL = 0.05

local MOVETO_REFRESH = 0.10
local TARGET_REACHED_DISTANCE = 3

local STUCK_TIME = 0.85
local STUCK_MIN_MOVEMENT = 0.45

local PATH_LOOKAHEAD_POINTS = 15
local AGENT_RADIUS = 2
local AGENT_HEIGHT = 5
local WAYPOINT_SPACING = 3
local WAYPOINT_REACHED_DISTANCE = 2.5

local PATH_RECALCULATE_DELAY = 0.35
local PATH_TIMEOUT = 3

--------------------------------------------------
-- SKILL SETTINGS
--------------------------------------------------

local QSkillName = "Inner Focus"
local ESkillName = "Pulse Waves"

--------------------------------------------------
-- CHARACTER
--------------------------------------------------

local Character
local Humanoid
local RootPart

local function SetupCharacter(NewCharacter)
	Character = NewCharacter

	Humanoid = Character:WaitForChild("Humanoid")
	RootPart = Character:WaitForChild("HumanoidRootPart")
end

if Player.Character then
	SetupCharacter(Player.Character)
end

Player.CharacterAdded:Connect(function(NewCharacter)
	SetupCharacter(NewCharacter)
end)

--------------------------------------------------
-- STATE
--------------------------------------------------

local IsRecording = false
local IsReplaying = false

local CurrentRecording = nil

local Recordings = {}
local SelectedRecording = nil

local RecordingCounter = 0

local MovementMode = "MoveTo"

local CurrentTarget = nil

local LastMoveCommand = 0

local LastStuckCheck = 0
local LastStuckPosition = nil
local StuckStartTime = nil

local CurrentPath = nil
local CurrentWaypoints = {}
local CurrentWaypointIndex = 1
local PathBlockedConnection = nil
local PathStartedTime = 0
local LastPathCalculation = 0

local NeedNewPath = false

local ReplayStartTime = 0
local ReplayOffsetTime = 0

local ReplayMovementIndex = 1

local RespawnConnection = nil

--------------------------------------------------
-- SKILL FUNCTIONS
--------------------------------------------------

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

--------------------------------------------------
-- RECORDING
--------------------------------------------------

local function GetRecordingDuration(Recording)
	if not Recording then
		return 0
	end

	if Recording.Duration then
		return Recording.Duration
	end

	if Recording.Movement and #Recording.Movement > 0 then
		return Recording.Movement[#Recording.Movement].Time or 0
	end

	return 0
end

local function GetSkillCount(Recording)
	if not Recording or not Recording.Actions then
		return 0
	end

	return #Recording.Actions
end

local function StartRecording(Name)
	if IsRecording then
		return
	end

	if IsReplaying then
		return
	end

	if not Character or not RootPart or not Humanoid then
		return
	end

	RecordingCounter += 1

	if not Name or Name == "" then
		Name = "Recording " .. RecordingCounter
	end

	CurrentRecording = {
		Name = Name,
		Movement = {},
		Actions = {},
		StartTime = os.clock(),
		Duration = 0
	}

	IsRecording = true

	print("[Replay] Recording started:", Name)
end

local function StopRecording()
	if not IsRecording or not CurrentRecording then
		return
	end

	local Recording = CurrentRecording

	Recording.Duration = os.clock() - Recording.StartTime

	IsRecording = false

	if #Recording.Movement > 0 then
		table.insert(Recordings, Recording)
		SelectedRecording = Recording
	end

	CurrentRecording = nil

	print("[Replay] Recording stopped:", Recording.Name)
end

--------------------------------------------------
-- RECORD MOVEMENT
--------------------------------------------------

local LastRecordTime = 0

local function RecordMovement()
	if not IsRecording then
		return
	end

	if not CurrentRecording then
		return
	end

	if not RootPart then
		return
	end

	local Time = os.clock() - CurrentRecording.StartTime

	if Time - LastRecordTime < RECORD_INTERVAL then
		return
	end

	LastRecordTime = Time

	table.insert(CurrentRecording.Movement, {
		Time = Time,
		Position = RootPart.Position,
		CFrame = RootPart.CFrame
	})
end

--------------------------------------------------
-- RECORD INPUT
--------------------------------------------------

UserInputService.InputBegan:Connect(function(Input, GameProcessed)
	if GameProcessed then
		return
	end

	if not IsRecording then
		return
	end

	if Input.KeyCode == Enum.KeyCode.Q then

		table.insert(CurrentRecording.Actions, {
			Time = os.clock() - CurrentRecording.StartTime,
			ActionType = "Skill",
			Key = "q",
			SkillName = QSkillName
		})

	elseif Input.KeyCode == Enum.KeyCode.E then

		table.insert(CurrentRecording.Actions, {
			Time = os.clock() - CurrentRecording.StartTime,
			ActionType = "Skill",
			Key = "e",
			SkillName = ESkillName
		})

	end
end)

--------------------------------------------------
-- PATHFINDING
--------------------------------------------------

local function ClearPath()
	if PathBlockedConnection then
		PathBlockedConnection:Disconnect()
		PathBlockedConnection = nil
	end

	CurrentPath = nil
	CurrentWaypoints = {}
	CurrentWaypointIndex = 1
end

local function ComputePath(TargetPosition)
	if not RootPart then
		return false
	end

	local Now = os.clock()

	if Now - LastPathCalculation < PATH_RECALCULATE_DELAY then
		return false
	end

	LastPathCalculation = Now

	local Path = PathfindingService:CreatePath({
		AgentRadius = AGENT_RADIUS,
		AgentHeight = AGENT_HEIGHT,
		AgentCanJump = true,
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

	ClearPath()

	CurrentPath = Path
	CurrentWaypoints = Waypoints
	CurrentWaypointIndex = 2
	PathStartedTime = Now

	PathBlockedConnection = Path.Blocked:Connect(function(BlockedIndex)
		if BlockedIndex >= CurrentWaypointIndex then
			NeedNewPath = true
		end
	end)

	NeedNewPath = false

	return true
end

local function EnterPathfinding(TargetPosition)
	if not RootPart then
		return
	end

	local Success = ComputePath(TargetPosition)

	if Success then
		MovementMode = "Pathfinding"
		print("[Replay] Stuck detected -> Pathfinding")
	else
		MovementMode = "MoveTo"
	end
end

local function UpdatePathMovement()
	if MovementMode ~= "Pathfinding" then
		return
	end

	if not RootPart or not Humanoid then
		return
	end

	if not CurrentPath or #CurrentWaypoints == 0 then
		MovementMode = "MoveTo"
		return
	end

	if os.clock() - PathStartedTime > PATH_TIMEOUT then
		ClearPath()
		MovementMode = "MoveTo"
		return
	end

	if NeedNewPath then
		NeedNewPath = false

		if CurrentTarget then
			ComputePath(CurrentTarget)
		else
			MovementMode = "MoveTo"
		end

		return
	end

	local Waypoint = CurrentWaypoints[CurrentWaypointIndex]

	if not Waypoint then
		ClearPath()
		MovementMode = "MoveTo"

		return
	end

	local Distance = (RootPart.Position - Waypoint.Position).Magnitude

	if Distance <= WAYPOINT_REACHED_DISTANCE then
		CurrentWaypointIndex += 1

		Waypoint = CurrentWaypoints[CurrentWaypointIndex]

		if not Waypoint then
			ClearPath()
			MovementMode = "MoveTo"
			return
		end
	end

	if Waypoint.Action == Enum.PathWaypointAction.Jump then
		Humanoid.Jump = true
	end

	if os.clock() - LastMoveCommand >= MOVETO_REFRESH then
		Humanoid:MoveTo(Waypoint.Position)
		LastMoveCommand = os.clock()
	end
end

--------------------------------------------------
-- STUCK DETECTION
--------------------------------------------------

local function CheckStuck(TargetPosition)
	if not RootPart then
		return
	end

	if MovementMode == "Pathfinding" then
		return
	end

	local Now = os.clock()

	if Now - LastStuckCheck < 0.25 then
		return
	end

	LastStuckCheck = Now

	local CurrentPosition = RootPart.Position

	if not LastStuckPosition then
		LastStuckPosition = CurrentPosition
		StuckStartTime = Now
		return
	end

	local MovementDistance =
		(CurrentPosition - LastStuckPosition).Magnitude

	if MovementDistance >= STUCK_MIN_MOVEMENT then
		LastStuckPosition = CurrentPosition
		StuckStartTime = Now
		return
	end

	if StuckStartTime and Now - StuckStartTime >= STUCK_TIME then

		if TargetPosition then
			EnterPathfinding(TargetPosition)
		end

		LastStuckPosition = CurrentPosition
		StuckStartTime = Now
	end
end

--------------------------------------------------
-- MOVE TO
--------------------------------------------------

local function MoveToTarget(TargetPosition)
	if not Humanoid or not RootPart then
		return
	end

	CurrentTarget = TargetPosition

	if MovementMode == "Pathfinding" then
		UpdatePathMovement()
		return
	end

	local Distance =
		(RootPart.Position - TargetPosition).Magnitude

	if Distance <= TARGET_REACHED_DISTANCE then
		return
	end

	if os.clock() - LastMoveCommand >= MOVETO_REFRESH then
		Humanoid:MoveTo(TargetPosition)
		LastMoveCommand = os.clock()
	end

	CheckStuck(TargetPosition)
end

--------------------------------------------------
-- FIND NEAREST RECORDED POINT
--------------------------------------------------

local function FindNearestMovementIndex(Recording, Position)
	if not Recording or not Recording.Movement then
		return 1
	end

	local ClosestIndex = 1
	local ClosestDistance = math.huge

	for Index, Point in ipairs(Recording.Movement) do

		local Distance =
			(Point.Position - Position).Magnitude

		if Distance < ClosestDistance then
			ClosestDistance = Distance
			ClosestIndex = Index
		end
	end

	return ClosestIndex
end

--------------------------------------------------
-- REPLAY ACTIONS
--------------------------------------------------

local function ReplayActionsBetween(
	Recording,
	OldTime,
	NewTime
)
	if not Recording or not Recording.Actions then
		return
	end

	for _, Action in ipairs(Recording.Actions) do

		if Action.Time > OldTime
			and Action.Time <= NewTime then

			if Action.ActionType == "Skill" then
				ReplaySkill(
					Action.Key,
					Action.SkillName
				)
			end
		end
	end
end

--------------------------------------------------
-- REPLAY MOVEMENT
--------------------------------------------------

local function ReplayMovement(Recording)
	if not Recording then
		return
	end

	if not Recording.Movement
		or #Recording.Movement == 0 then
		return
	end

	IsReplaying = true

	MovementMode = "MoveTo"
	ClearPath()

	LastStuckPosition = nil
	StuckStartTime = nil

	local Movement = Recording.Movement

	local StartIndex = ReplayMovementIndex or 1

	if StartIndex < 1 then
		StartIndex = 1
	end

	if StartIndex > #Movement then
		StartIndex = #Movement
	end

	local StartTime =
		Movement[StartIndex].Time or 0

	local ReplayTime = StartTime

	local PreviousTime = StartTime

	local RealStart = os.clock()

	while IsReplaying do

		if not Character
			or not Humanoid
			or not RootPart
			or Humanoid.Health <= 0 then

			task.wait(0.1)
			continue
		end

		local CurrentRealTime =
			os.clock() - RealStart

		ReplayTime =
			StartTime + CurrentRealTime

		--------------------------------------------------
		-- FIND CURRENT MOVEMENT POINT
		--------------------------------------------------

		local Index = ReplayMovementIndex or StartIndex

		while Index < #Movement
			and Movement[Index + 1].Time <= ReplayTime do

			Index += 1
		end

		ReplayMovementIndex = Index

		local CurrentPoint = Movement[Index]
		local NextPoint = Movement[Index + 1]

		if CurrentPoint then

			local TargetPosition =
				CurrentPoint.Position

			if NextPoint then

				local SegmentStart =
					CurrentPoint.Time

				local SegmentEnd =
					NextPoint.Time

				local Alpha = 0

				if SegmentEnd > SegmentStart then
					Alpha =
						math.clamp(
							(ReplayTime - SegmentStart)
								/ (SegmentEnd - SegmentStart),
							0,
							1
						)
				end

				TargetPosition =
					CurrentPoint.Position:Lerp(
						NextPoint.Position,
						Alpha
					)
			end

			CurrentTarget = TargetPosition

			MoveToTarget(TargetPosition)
		end

		--------------------------------------------------
		-- REPLAY SKILLS
		--------------------------------------------------

		ReplayActionsBetween(
			Recording,
			PreviousTime,
			ReplayTime
		)

		PreviousTime = ReplayTime

		--------------------------------------------------
		-- FINISH CONDITION
		--------------------------------------------------

		local FinalPoint =
			Movement[#Movement]

		local FinalTime =
			FinalPoint.Time or 0

		if ReplayTime >= FinalTime then

			local FinalDistance =
				(RootPart.Position - FinalPoint.Position).Magnitude

			if FinalDistance <= TARGET_REACHED_DISTANCE then
				break
			end

			MoveToTarget(FinalPoint.Position)
		end

		task.wait()
	end

	if IsReplaying then
		IsReplaying = false
	end

	ClearPath()

	MovementMode = "MoveTo"
	CurrentTarget = nil

	print("[Replay] Finished:", Recording.Name)
end

--------------------------------------------------
-- START REPLAY
--------------------------------------------------

local function StartReplay()
	if IsRecording then
		return
	end

	if IsReplaying then
		return
	end

	if not SelectedRecording then
		warn("[Replay] No recording selected")
		return
	end

	if not SelectedRecording.Movement
		or #SelectedRecording.Movement == 0 then
		return
	end

	ReplayMovementIndex = 1

	task.spawn(function()
		ReplayMovement(SelectedRecording)
	end)
end

--------------------------------------------------
-- STOP REPLAY
--------------------------------------------------

local function StopReplay()
	if not IsReplaying then
		return
	end

	IsReplaying = false

	ClearPath()

	MovementMode = "MoveTo"
	CurrentTarget = nil

	print("[Replay] Replay stopped")
end

--------------------------------------------------
-- DEATH / RESPAWN RECOVERY
--------------------------------------------------

local function SetupDeathConnection()
	if not Humanoid then
		return
	end

	Humanoid.Died:Connect(function()

		if not IsReplaying then
			return
		end

		print("[Replay] Player died, waiting for respawn...")
	end)
end

local function SetupRespawnRecovery()
	Player.CharacterAdded:Connect(function(NewCharacter)

		SetupCharacter(NewCharacter)

		task.wait(1)

		SetupDeathConnection()

		if not IsReplaying then
			return
		end

		if not SelectedRecording then
			return
		end

		if not RootPart then
			return
		end

		local NearestIndex =
			FindNearestMovementIndex(
				SelectedRecording,
				RootPart.Position
			)

		ReplayMovementIndex = NearestIndex

		print(
			"[Replay] Resuming from recorded point:",
			NearestIndex
		)
	end)
end

if Humanoid then
	SetupDeathConnection()
end

SetupRespawnRecovery()

--------------------------------------------------
-- UI
--------------------------------------------------

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ReplaySystemUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = Player:WaitForChild("PlayerGui")

--------------------------------------------------
-- COLORS
--------------------------------------------------

local BG = Color3.fromRGB(18, 18, 21)
local PANEL = Color3.fromRGB(25, 25, 29)
local PANEL2 = Color3.fromRGB(32, 32, 37)
local INPUT = Color3.fromRGB(38, 38, 44)

local TEXT = Color3.fromRGB(240, 240, 245)
local SUBTEXT = Color3.fromRGB(155, 155, 165)

local GREEN = Color3.fromRGB(70, 170, 95)
local RED = Color3.fromRGB(185, 70, 70)
local BLUE = Color3.fromRGB(75, 105, 190)
local YELLOW = Color3.fromRGB(200, 170, 65)

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function AddCorner(Object, Radius)
	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, Radius or 8)
	Corner.Parent = Object
	return Corner
end

local function AddStroke(Object, Color, Transparency)
	local Stroke = Instance.new("UIStroke")
	Stroke.Color = Color
	Stroke.Transparency = Transparency or 0
	Stroke.Thickness = 1
	Stroke.Parent = Object
	return Stroke
end

local function CreateLabel(
	Parent,
	TextValue,
	Size,
	Position,
	TextSize,
	Color
)
	local Label = Instance.new("TextLabel")

	Label.BackgroundTransparency = 1
	Label.Size = Size
	Label.Position = Position

	Label.Text = TextValue
	Label.TextColor3 = Color or TEXT
	Label.TextSize = TextSize or 14
	Label.Font = Enum.Font.Gotham

	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.TextYAlignment = Enum.TextYAlignment.Center

	Label.Parent = Parent

	return Label
end

local function CreateButton(
	Parent,
	TextValue,
	Size,
	Position,
	Color
)
	local Button = Instance.new("TextButton")

	Button.Size = Size
	Button.Position = Position

	Button.BackgroundColor3 =
		Color or PANEL2

	Button.Text = TextValue
	Button.TextColor3 = TEXT

	Button.TextSize = 13
	Button.Font = Enum.Font.GothamMedium

	Button.AutoButtonColor = true

	Button.Parent = Parent

	AddCorner(Button, 7)

	return Button
end

--------------------------------------------------
-- MAIN WINDOW
--------------------------------------------------

local MainFrame = Instance.new("Frame")

MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.fromOffset(460, 650)
MainFrame.Position = UDim2.new(
	0.5,
	-230,
	0.5,
	-325
)

MainFrame.BackgroundColor3 = BG
MainFrame.Parent = ScreenGui

AddCorner(MainFrame, 12)
AddStroke(MainFrame, Color3.fromRGB(55, 55, 62), 0.25)

--------------------------------------------------
-- HEADER
--------------------------------------------------

local Header = Instance.new("Frame")

Header.Size = UDim2.new(1, 0, 0, 60)
Header.BackgroundColor3 = PANEL
Header.Parent = MainFrame

AddCorner(Header, 12)

local HeaderBottom = Instance.new("Frame")
HeaderBottom.Size = UDim2.new(1, 0, 0, 15)
HeaderBottom.Position = UDim2.new(0, 0, 1, -15)
HeaderBottom.BackgroundColor3 = PANEL
HeaderBottom.BorderSizePixel = 0
HeaderBottom.Parent = Header

--------------------------------------------------
-- TITLE
--------------------------------------------------

local Title = CreateLabel(
	Header,
	"Replay System",
	UDim2.fromOffset(180, 24),
	UDim2.fromOffset(16, 8),
	17,
	TEXT
)

Title.Font = Enum.Font.GothamBold

local VersionLabel = CreateLabel(
	Header,
	VERSION,
	UDim2.fromOffset(80, 18),
	UDim2.fromOffset(17, 33),
	10,
	SUBTEXT
)

--------------------------------------------------
-- STATUS BADGE
--------------------------------------------------

local StatusBadge = Instance.new("Frame")

StatusBadge.Size = UDim2.fromOffset(125, 32)
StatusBadge.Position = UDim2.new(1, -170, 0, 14)

StatusBadge.BackgroundColor3 = INPUT
StatusBadge.Parent = Header

AddCorner(StatusBadge, 16)

local StatusDot = Instance.new("Frame")

StatusDot.Size = UDim2.fromOffset(9, 9)
StatusDot.Position = UDim2.fromOffset(12, 11)

StatusDot.BackgroundColor3 = GREEN
StatusDot.Parent = StatusBadge

AddCorner(StatusDot, 9)

local StatusText = CreateLabel(
	StatusBadge,
	"READY",
	UDim2.new(1, -34, 1, 0),
	UDim2.fromOffset(30, 0),
	11,
	TEXT
)

StatusText.Font = Enum.Font.GothamBold

--------------------------------------------------
-- MINIMIZE
--------------------------------------------------

local MinimizeButton = CreateButton(
	Header,
	"—",
	UDim2.fromOffset(30, 30),
	UDim2.new(1, -40, 0, 15),
	PANEL2
)

MinimizeButton.TextSize = 18

local Minimized = false

MinimizeButton.MouseButton1Click:Connect(function()

	Minimized = not Minimized

	if Minimized then
		MainFrame.Size =
			UDim2.fromOffset(460, 60)
	else
		MainFrame.Size =
			UDim2.fromOffset(460, 650)
	end
end)

--------------------------------------------------
-- DRAGGING
--------------------------------------------------

local Dragging = false
local DragStart
local StartPosition

Header.InputBegan:Connect(function(Input)

	if Input.UserInputType == Enum.UserInputType.MouseButton1 then

		if Input.Target == MinimizeButton then
			return
		end

		Dragging = true

		DragStart = Input.Position
		StartPosition = MainFrame.Position
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

	local Delta =
		Input.Position - DragStart

	MainFrame.Position = UDim2.new(
		StartPosition.X.Scale,
		StartPosition.X.Offset + Delta.X,
		StartPosition.Y.Scale,
		StartPosition.Y.Offset + Delta.Y
	)
end)

--------------------------------------------------
-- CONTENT SCROLL
--------------------------------------------------

local Content = Instance.new("ScrollingFrame")

Content.Name = "Content"
Content.Size = UDim2.new(
	1,
	-20,
	1,
	-70
)

Content.Position = UDim2.fromOffset(10, 65)

Content.BackgroundTransparency = 1

Content.BorderSizePixel = 0

Content.ScrollBarThickness = 5
Content.ScrollBarImageTransparency = 0.35

Content.CanvasSize =
	UDim2.fromOffset(0, 0)

Content.Parent = MainFrame

local ContentLayout = Instance.new("UIListLayout")

ContentLayout.Padding =
	UDim.new(0, 10)

ContentLayout.SortOrder =
	Enum.SortOrder.LayoutOrder

ContentLayout.Parent = Content

local ContentPadding = Instance.new("UIPadding")

ContentPadding.PaddingLeft =
	UDim.new(0, 2)

ContentPadding.PaddingRight =
	UDim.new(0, 2)

ContentPadding.PaddingBottom =
	UDim.new(0, 12)

ContentPadding.Parent = Content

ContentLayout:GetPropertyChangedSignal(
	"AbsoluteContentSize"
):Connect(function()

	Content.CanvasSize =
		UDim2.fromOffset(
			0,
			ContentLayout.AbsoluteContentSize.Y + 15
		)
end)

--------------------------------------------------
-- RECORD SECTION
--------------------------------------------------

local RecordSection = Instance.new("Frame")

RecordSection.Size =
	UDim2.new(1, -4, 0, 150)

RecordSection.BackgroundColor3 = PANEL
RecordSection.Parent = Content

AddCorner(RecordSection, 10)

local RecordTitle = CreateLabel(
	RecordSection,
	"Record New",
	UDim2.new(1, -24, 0, 25),
	UDim2.fromOffset(12, 10),
	15,
	TEXT
)

RecordTitle.Font = Enum.Font.GothamBold

local RecordHint = CreateLabel(
	RecordSection,
	"Record your movement and Q / E skills.",
	UDim2.new(1, -24, 0, 18),
	UDim2.fromOffset(12, 34),
	11,
	SUBTEXT
)

--------------------------------------------------
-- NAME BOX
--------------------------------------------------

local NameBox = Instance.new("TextBox")

NameBox.Size =
	UDim2.new(1, -24, 0, 34)

NameBox.Position =
	UDim2.fromOffset(12, 58)

NameBox.BackgroundColor3 = INPUT

NameBox.PlaceholderText =
	"Recording name..."

NameBox.PlaceholderColor3 =
	SUBTEXT

NameBox.Text = ""

NameBox.TextColor3 = TEXT
NameBox.TextSize = 12

NameBox.Font = Enum.Font.Gotham

NameBox.ClearTextOnFocus = false

NameBox.Parent = RecordSection

AddCorner(NameBox, 7)

--------------------------------------------------
-- RECORD BUTTON
--------------------------------------------------

local RecordButton = CreateButton(
	RecordSection,
	"●  Start Recording",
	UDim2.new(0.5, -17, 0, 38),
	UDim2.fromOffset(12, 103),
	GREEN
)

--------------------------------------------------
-- STOP BUTTON
--------------------------------------------------

local StopButton = CreateButton(
	RecordSection,
	"■  Stop",
	UDim2.new(0.5, -17, 0, 38),
	UDim2.new(0.5, 5, 0, 103),
	RED
)

StopButton.AutoButtonColor = false
StopButton.BackgroundTransparency = 0.45

--------------------------------------------------
-- SKILLS SECTION
--------------------------------------------------

local SkillSection = Instance.new("Frame")

SkillSection.Size =
	UDim2.new(1, -4, 0, 130)

SkillSection.BackgroundColor3 = PANEL
SkillSection.Parent = Content

AddCorner(SkillSection, 10)

local SkillTitle = CreateLabel(
	SkillSection,
	"Skills",
	UDim2.new(1, -24, 0, 25),
	UDim2.fromOffset(12, 10),
	15,
	TEXT
)

SkillTitle.Font = Enum.Font.GothamBold

local SkillHint = CreateLabel(
	SkillSection,
	"Choose which skill is replayed for Q and E.",
	UDim2.new(1, -24, 0, 18),
	UDim2.fromOffset(12, 34),
	11,
	SUBTEXT
)

--------------------------------------------------
-- Q SELECTOR
--------------------------------------------------

local QLabel = CreateLabel(
	SkillSection,
	"Q Skill",
	UDim2.fromOffset(70, 34),
	UDim2.fromOffset(12, 60),
	12,
	SUBTEXT
)

local QButton = CreateButton(
	SkillSection,
	QSkillName,
	UDim2.new(0.5, -17, 0, 34),
	UDim2.fromOffset(82, 58),
	INPUT
)

--------------------------------------------------
-- E SELECTOR
--------------------------------------------------

local ELabel = CreateLabel(
	SkillSection,
	"E Skill",
	UDim2.fromOffset(70, 34),
	UDim2.new(0.5, 5, 0, 60),
	12,
	SUBTEXT
)

local EButton = CreateButton(
	SkillSection,
	ESkillName,
	UDim2.new(0.5, -17, 0, 34),
	UDim2.new(0.5, 75, 0, 58),
	INPUT
)

--------------------------------------------------
-- SKILL DROPDOWN
--------------------------------------------------

local SkillDropdown = Instance.new("Frame")

SkillDropdown.Size =
	UDim2.fromOffset(200, 0)

SkillDropdown.BackgroundColor3 =
	Color3.fromRGB(22, 22, 26)

SkillDropdown.Visible = false

SkillDropdown.ZIndex = 20

SkillDropdown.Parent = ScreenGui

AddCorner(SkillDropdown, 8)
AddStroke(SkillDropdown, Color3.fromRGB(60, 60, 70), 0.2)

local SkillDropdownList =
	Instance.new("ScrollingFrame")

SkillDropdownList.Size =
	UDim2.new(1, -8, 1, -8)

SkillDropdownList.Position =
	UDim2.fromOffset(4, 4)

SkillDropdownList.BackgroundTransparency = 1

SkillDropdownList.BorderSizePixel = 0

SkillDropdownList.ScrollBarThickness = 4

SkillDropdownList.CanvasSize =
	UDim2.fromOffset(0, 0)

SkillDropdownList.ZIndex = 21

SkillDropdownList.Parent = SkillDropdown

local SkillLayout =
	Instance.new("UIListLayout")

SkillLayout.Padding =
	UDim.new(0, 4)

SkillLayout.Parent =
	SkillDropdownList

local ChoosingSkill = nil

local function GetAvailableSkills()
	local Skills = {}

	local Seen = {}

	for _, Object in ipairs(Backpack:GetChildren()) do

		if Object:IsA("Tool") then

			local HasEvent =
				Object:FindFirstChild("abilityEvent")
				or Object:FindFirstChild("spellEvent")

			if HasEvent and not Seen[Object.Name] then

				Seen[Object.Name] = true

				table.insert(
					Skills,
					Object.Name
				)
			end
		end
	end

	if Character then

		for _, Object in ipairs(Character:GetChildren()) do

			if Object:IsA("Tool") then

				local HasEvent =
					Object:FindFirstChild("abilityEvent")
					or Object:FindFirstChild("spellEvent")

				if HasEvent and not Seen[Object.Name] then

					Seen[Object.Name] = true

					table.insert(
						Skills,
						Object.Name
					)
				end
			end
		end
	end

	table.sort(Skills)

	return Skills
end

local function OpenSkillDropdown(Button, Key)

	ChoosingSkill = Key

	for _, Child in ipairs(SkillDropdownList:GetChildren()) do

		if Child:IsA("TextButton") then
			Child:Destroy()
		end
	end

	local Skills = GetAvailableSkills()

	for _, SkillName in ipairs(Skills) do

		local Button2 = CreateButton(
			SkillDropdownList,
			SkillName,
			UDim2.new(1, 0, 0, 32),
			UDim2.fromOffset(0, 0),
			INPUT
		)

		Button2.ZIndex = 22

		Button2.MouseButton1Click:Connect(function()

			if ChoosingSkill == "Q" then
				QSkillName = SkillName
				QButton.Text = SkillName

			elseif ChoosingSkill == "E" then
				ESkillName = SkillName
				EButton.Text = SkillName
			end

			SkillDropdown.Visible = false
			ChoosingSkill = nil
		end)
	end

	local Count = math.max(#Skills, 1)

	local Height =
		math.min(Count * 36 + 8, 220)

	SkillDropdown.Size =
		UDim2.fromOffset(200, Height)

	local AbsolutePosition =
		Button.AbsolutePosition

	local AbsoluteSize =
		Button.AbsoluteSize

	SkillDropdown.Position =
		UDim2.fromOffset(
			AbsolutePosition.X,
			AbsolutePosition.Y + AbsoluteSize.Y + 5
		)

	SkillDropdown.Visible = true

	task.defer(function()

		SkillDropdownList.CanvasSize =
			UDim2.fromOffset(
				0,
				SkillLayout.AbsoluteContentSize.Y + 8
			)

	end)
end

QButton.MouseButton1Click:Connect(function()
	OpenSkillDropdown(QButton, "Q")
end)

EButton.MouseButton1Click:Connect(function()
	OpenSkillDropdown(EButton, "E")
end)

--------------------------------------------------
-- SAVED RECORDINGS SECTION
--------------------------------------------------

local SavedSection = Instance.new("Frame")

SavedSection.Size =
	UDim2.new(1, -4, 0, 310)

SavedSection.BackgroundColor3 = PANEL
SavedSection.Parent = Content

AddCorner(SavedSection, 10)

local SavedTitle = CreateLabel(
	SavedSection,
	"Saved Recordings",
	UDim2.new(1, -24, 0, 25),
	UDim2.fromOffset(12, 10),
	15,
	TEXT
)

SavedTitle.Font = Enum.Font.GothamBold

local SavedCount = CreateLabel(
	SavedSection,
	"0 recordings",
	UDim2.new(1, -24, 0, 18),
	UDim2.fromOffset(12, 35),
	11,
	SUBTEXT
)

--------------------------------------------------
-- SELECTED RECORDING
--------------------------------------------------

local SelectedLabel = CreateLabel(
	SavedSection,
	"Selected: None",
	UDim2.new(1, -24, 0, 20),
	UDim2.fromOffset(12, 56),
	12,
	TEXT
)

SelectedLabel.Font = Enum.Font.GothamMedium

--------------------------------------------------
-- RECORDING LIST
--------------------------------------------------

local RecordingList = Instance.new("ScrollingFrame")

RecordingList.Name = "RecordingList"

RecordingList.Size =
	UDim2.new(1, -24, 0, 185)

RecordingList.Position =
	UDim2.fromOffset(12, 82)

RecordingList.BackgroundColor3 =
	Color3.fromRGB(21, 21, 25)

RecordingList.BorderSizePixel = 0

RecordingList.ScrollBarThickness = 5

RecordingList.ScrollBarImageTransparency = 0.25

RecordingList.CanvasSize =
	UDim2.fromOffset(0, 0)

RecordingList.Parent = SavedSection

AddCorner(RecordingList, 8)

local RecordingListPadding =
	Instance.new("UIPadding")

RecordingListPadding.PaddingTop =
	UDim.new(0, 5)

RecordingListPadding.PaddingBottom =
	UDim.new(0, 5)

RecordingListPadding.PaddingLeft =
	UDim.new(0, 5)

RecordingListPadding.PaddingRight =
	UDim.new(0, 5)

RecordingListPadding.Parent =
	RecordingList

local RecordingLayout =
	Instance.new("UIListLayout")

RecordingLayout.Padding =
	UDim.new(0, 5)

RecordingLayout.SortOrder =
	Enum.SortOrder.LayoutOrder

RecordingLayout.Parent =
	RecordingList

--------------------------------------------------
-- RECORDING ROW
--------------------------------------------------

local function FormatTime(Time)
	Time = Time or 0

	if Time >= 60 then

		local Minutes =
			math.floor(Time / 60)

		local Seconds =
			Time - Minutes * 60

		return string.format(
			"%d:%05.2f",
			Minutes,
			Seconds
		)

	else

		return string.format(
			"%.2fs",
			Time
		)
	end
end

local function RefreshRecordingList()

	for _, Child in ipairs(
		RecordingList:GetChildren()
	) do

		if Child:IsA("Frame") then
			Child:Destroy()
		end
	end

	SavedCount.Text =
		tostring(#Recordings) ..
		(#Recordings == 1
			and " recording"
			or " recordings")

	if SelectedRecording then

		SelectedLabel.Text =
			"Selected: " ..
			SelectedRecording.Name

	else

		SelectedLabel.Text =
			"Selected: None"
	end

	for Index, Recording in ipairs(Recordings) do

		local IsSelected =
			Recording == SelectedRecording

		local Row = Instance.new("Frame")

		Row.Size =
			UDim2.new(1, 0, 0, 58)

		Row.BackgroundColor3 =
			IsSelected
			and Color3.fromRGB(45, 55, 75)
			or INPUT

		Row.Parent = RecordingList

		AddCorner(Row, 7)

		if IsSelected then
			AddStroke(Row, BLUE, 0.15)
		end

		--------------------------------------------------
		-- NUMBER
		--------------------------------------------------

		local NumberLabel = CreateLabel(
			Row,
			tostring(Index),
			UDim2.fromOffset(28, 58),
			UDim2.fromOffset(8, 0),
			12,
			SUBTEXT
		)

		NumberLabel.TextXAlignment =
			Enum.TextXAlignment.Center

		--------------------------------------------------
		-- NAME
		--------------------------------------------------

		local NameLabel = CreateLabel(
			Row,
			Recording.Name,
			UDim2.new(1, -145, 0, 25),
			UDim2.fromOffset(43, 6),
			13,
			TEXT
		)

		NameLabel.Font =
			Enum.Font.GothamMedium

		--------------------------------------------------
		-- INFO
		--------------------------------------------------

		local InfoLabel = CreateLabel(
			Row,
			string.format(
				"%s  •  %d skills",
				FormatTime(
					GetRecordingDuration(
						Recording
					)
				),
				GetSkillCount(Recording)
			),
			UDim2.new(1, -145, 0, 18),
			UDim2.fromOffset(43, 31),
			10,
			SUBTEXT
		)

		--------------------------------------------------
		-- SELECTED
		--------------------------------------------------

		if IsSelected then

			local Check = CreateLabel(
				Row,
				"✓",
				UDim2.fromOffset(45, 58),
				UDim2.new(1, -55, 0, 0),
				17,
				GREEN
			)

			Check.TextXAlignment =
				Enum.TextXAlignment.Center
		end

		--------------------------------------------------
		-- CLICK
		--------------------------------------------------

		local ClickButton = Instance.new(
			"TextButton"
		)

		ClickButton.Size =
			UDim2.new(1, 0, 1, 0)

		ClickButton.BackgroundTransparency = 1

		ClickButton.Text = ""

		ClickButton.ZIndex = 5

		ClickButton.Parent = Row

		ClickButton.MouseButton1Click:Connect(
			function()

				SelectedRecording =
					Recording

				RefreshRecordingList()
			end
		)
	end

	task.defer(function()

		RecordingList.CanvasSize =
			UDim2.fromOffset(
				0,
				RecordingLayout.AbsoluteContentSize.Y + 10
			)

	end)
end

--------------------------------------------------
-- REPLAY SECTION
--------------------------------------------------

local ReplaySection = Instance.new("Frame")

ReplaySection.Size =
	UDim2.new(1, -4, 0, 105)

ReplaySection.BackgroundColor3 = PANEL

ReplaySection.Parent = Content

AddCorner(ReplaySection, 10)

local ReplayTitle = CreateLabel(
	ReplaySection,
	"Replay",
	UDim2.new(1, -24, 0, 24),
	UDim2.fromOffset(12, 9),
	15,
	TEXT
)

ReplayTitle.Font =
	Enum.Font.GothamBold

local ReplayInfo = CreateLabel(
	ReplaySection,
	"No recording selected",
	UDim2.new(1, -24, 0, 20),
	UDim2.fromOffset(12, 34),
	11,
	SUBTEXT
)

local ReplayButton = CreateButton(
	ReplaySection,
	"▶  Replay Selected",
	UDim2.new(1, -24, 0, 38),
	UDim2.fromOffset(12, 60),
	BLUE
)

--------------------------------------------------
-- STATUS SECTION
--------------------------------------------------

local StatusSection = Instance.new("Frame")

StatusSection.Size =
	UDim2.new(1, -4, 0, 85)

StatusSection.BackgroundColor3 =
	Color3.fromRGB(22, 22, 26)

StatusSection.Parent = Content

AddCorner(StatusSection, 10)

local StatusSectionTitle = CreateLabel(
	StatusSection,
	"System Status",
	UDim2.fromOffset(130, 22),
	UDim2.fromOffset(12, 9),
	12,
	SUBTEXT
)

local StatusMain = CreateLabel(
	StatusSection,
	"Ready",
	UDim2.new(1, -24, 0, 25),
	UDim2.fromOffset(12, 29),
	15,
	TEXT
)

StatusMain.Font =
	Enum.Font.GothamMedium

local StatusDetails = CreateLabel(
	StatusSection,
	"",
	UDim2.new(1, -24, 0, 18),
	UDim2.fromOffset(12, 55),
	10,
	SUBTEXT
)

--------------------------------------------------
-- RECORDING INDICATOR ANIMATION
--------------------------------------------------

local RecordingIndicatorRunning = true

task.spawn(function()

	local Toggle = false

	while RecordingIndicatorRunning do

		if IsRecording then

			Toggle = not Toggle

			if Toggle then
				StatusDot.BackgroundTransparency = 0
			else
				StatusDot.BackgroundTransparency = 0.55
			end

			task.wait(0.5)

		else

			StatusDot.BackgroundTransparency = 0

			task.wait(0.2)
		end
	end
end)

--------------------------------------------------
-- UI STATE
--------------------------------------------------

local function UpdateUI()

	--------------------------------------------------
	-- RECORDING
	--------------------------------------------------

	if IsRecording then

		local Duration =
			CurrentRecording
			and (
				os.clock()
				- CurrentRecording.StartTime
			)
			or 0

		StatusBadge.BackgroundColor3 =
			Color3.fromRGB(75, 30, 30)

		StatusDot.BackgroundColor3 =
			RED

		StatusText.Text =
			"RECORDING"

		StatusMain.Text =
			"● Recording..."

		StatusMain.TextColor3 =
			RED

		StatusDetails.Text =
			string.format(
				"%s  •  %d movement points  •  %d skills",
				FormatTime(Duration),
				CurrentRecording
					and #CurrentRecording.Movement
					or 0,
				CurrentRecording
					and #CurrentRecording.Actions
					or 0
			)

		RecordButton.Text =
			"●  RECORDING"

		RecordButton.BackgroundColor3 =
			Color3.fromRGB(125, 45, 45)

		RecordButton.AutoButtonColor =
			false

		StopButton.BackgroundColor3 =
			RED

		StopButton.BackgroundTransparency =
			0

		StopButton.AutoButtonColor =
			true

		ReplayButton.Text =
			"▶  Replay Selected"

		ReplayButton.BackgroundColor3 =
			Color3.fromRGB(65, 65, 70)

		ReplayButton.AutoButtonColor =
			false

		--------------------------------------------------
		-- REPLAYING
		--------------------------------------------------

	elseif IsReplaying then

		StatusBadge.BackgroundColor3 =
			Color3.fromRGB(40, 45, 70)

		StatusDot.BackgroundColor3 =
			BLUE

		StatusText.Text =
			"REPLAYING"

		StatusMain.Text =
			"▶ Replaying..."

		StatusMain.TextColor3 =
			BLUE

		if SelectedRecording then

			StatusDetails.Text =
				"Playing: " ..
				SelectedRecording.Name

		else

			StatusDetails.Text = ""
		end

		RecordButton.Text =
			"●  Start Recording"

		RecordButton.BackgroundColor3 =
			Color3.fromRGB(65, 65, 70)

		RecordButton.AutoButtonColor =
			false

		StopButton.Text =
			"■  Stop Replay"

		StopButton.BackgroundColor3 =
			RED

		StopButton.BackgroundTransparency =
			0

		StopButton.AutoButtonColor =
			true

		ReplayButton.Text =
			"▶  REPLAYING..."

		ReplayButton.BackgroundColor3 =
			Color3.fromRGB(65, 65, 70)

		ReplayButton.AutoButtonColor =
			false

		--------------------------------------------------
		-- IDLE
		--------------------------------------------------

	else

		StatusBadge.BackgroundColor3 =
			INPUT

		StatusDot.BackgroundColor3 =
			GREEN

		StatusText.Text =
			"READY"

		StatusMain.Text =
			"Ready"

		StatusMain.TextColor3 =
			TEXT

		if SelectedRecording then

			StatusDetails.Text =
				string.format(
					"%s  •  %d skills",
					FormatTime(
						GetRecordingDuration(
							SelectedRecording
						)
					),
					GetSkillCount(
						SelectedRecording
					)
				)

		else

			StatusDetails.Text =
				"Create a recording to get started"
		end

		RecordButton.Text =
			"●  Start Recording"

		RecordButton.BackgroundColor3 =
			GREEN

		RecordButton.AutoButtonColor =
			true

		StopButton.Text =
			"■  Stop"

		StopButton.BackgroundColor3 =
			RED

		StopButton.BackgroundTransparency =
			0.45

		StopButton.AutoButtonColor =
			false

		if SelectedRecording then

			ReplayButton.Text =
				"▶  Replay: " ..
				SelectedRecording.Name

			ReplayButton.BackgroundColor3 =
				BLUE

			ReplayButton.AutoButtonColor =
				true

		else

			ReplayButton.Text =
				"▶  Select a recording"

			ReplayButton.BackgroundColor3 =
				Color3.fromRGB(65, 65, 70)

			ReplayButton.AutoButtonColor =
				false
		end
	end

	--------------------------------------------------
	-- SELECTED RECORDING INFO
	--------------------------------------------------

	if SelectedRecording then

		ReplayInfo.Text =
			string.format(
				"%s  •  %s  •  %d skills",
				SelectedRecording.Name,
				FormatTime(
					GetRecordingDuration(
						SelectedRecording
					)
				),
				GetSkillCount(
					SelectedRecording
				)
			)

	else

		ReplayInfo.Text =
			"No recording selected"
	end
end

--------------------------------------------------
-- BUTTON EVENTS
--------------------------------------------------

RecordButton.MouseButton1Click:Connect(function()

	if IsRecording or IsReplaying then
		return
	end

	local Name =
		NameBox.Text

	StartRecording(Name)

	NameBox.Text = ""

	RefreshRecordingList()
	UpdateUI()
end)

StopButton.MouseButton1Click:Connect(function()

	if IsRecording then

		StopRecording()

		RefreshRecordingList()
		UpdateUI()

		return
	end

	if IsReplaying then

		StopReplay()

		UpdateUI()

		return
	end
end)

ReplayButton.MouseButton1Click:Connect(function()

	if IsRecording then
		return
	end

	if IsReplaying then
		return
	end

	if not SelectedRecording then
		return
	end

	StartReplay()

	UpdateUI()
end)

--------------------------------------------------
-- LIVE RECORDING UI UPDATE
--------------------------------------------------

local LastUIUpdate = 0

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

RunService.Heartbeat:Connect(function()

	--------------------------------------------------
	-- RECORD
	--------------------------------------------------

	if IsRecording then
		RecordMovement()
	end

	--------------------------------------------------
	-- PATHFINDING
	--------------------------------------------------

	if IsReplaying
		and MovementMode == "Pathfinding" then

		UpdatePathMovement()
	end

	--------------------------------------------------
	-- UI
	--------------------------------------------------

	if os.clock() - LastUIUpdate >= 0.1 then

		LastUIUpdate = os.clock()

		UpdateUI()
	end
end)

--------------------------------------------------
-- INITIAL UI
--------------------------------------------------

RefreshRecordingList()
UpdateUI()

print(
	"[Replay System] Loaded " ..
	VERSION
)
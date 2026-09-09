--============================================================
-- REPLAY SYSTEM v1.1.0
-- Movement + Pathfinding + Death Resume + Q/E Skills
--
-- VERSION: 1.1.0
--
-- CHANGES:
-- • Fixed skill tool lookup to prioritize Backpack
-- • Supports abilityEvent and spellEvent automatically
-- • Q/E skill replay
-- • Reduced path recalculation to prevent movement pauses
-- • Smoother waypoint movement
-- • Death resume
-- • Version displayed in UI
--============================================================


--============================================================
-- SERVICES
--============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")


--============================================================
-- VERSION
--============================================================

local VERSION = "v1.1.0"


--============================================================
-- PLAYER
--============================================================

local Player = Players.LocalPlayer

local Remotes =
	ReplicatedStorage:WaitForChild("remotes")

local AbilityUsed =
	Remotes:WaitForChild("abilityUsed")


--============================================================
-- CHARACTER
--============================================================

local Character
local Humanoid
local RootPart


local function SetupCharacter(NewCharacter)

	Character = NewCharacter

	Humanoid =
		Character:WaitForChild("Humanoid")

	RootPart =
		Character:WaitForChild("HumanoidRootPart")

end


if Player.Character then
	SetupCharacter(Player.Character)
end


--============================================================
-- SETTINGS
--============================================================

local RECORD_INTERVAL = 0.1

-- Distance before considering a recorded point reached
local MOVEMENT_REACH_DISTANCE = 2.5

-- Path waypoint reach distance
local WAYPOINT_REACH_DISTANCE = 2.5

-- Only recreate path if destination changed this much
local PATH_TARGET_CHANGE = 10

-- How long the player has to be stuck before recalculating
local STUCK_TIME = 1.75

-- How far movement is allowed to continue without path recalculation
local MAX_DIRECT_DISTANCE = 8

-- Maximum distance allowed when resuming after death
local MAX_RESUME_DISTANCE = 150


--============================================================
-- STATES
--============================================================

local Recording = false
local Replaying = false

local CurrentRecording = nil
local SelectedRecording = nil

local Recordings = {}

local RecordStartTime = 0
local LastRecordTime = 0

local RecordConnection = nil
local ReplayConnection = nil

local DeathConnection = nil

local ResumeAfterDeath = false


--============================================================
-- REPLAY VARIABLES
--============================================================

local ReplayIndex = 1
local ReplayStartTime = 0
local ReplayInputIndex = 1
local ReplayTimeOffset = 0


--============================================================
-- PATH VARIABLES
--============================================================

local CurrentPath = nil
local CurrentPathIndex = 1

local LastPathTarget = nil

local LastPosition = nil
local LastMovementCheck = 0

local StuckTimer = 0

local PathComputing = false


--============================================================
-- UI
--============================================================

local ScreenGui =
	Instance.new("ScreenGui")

ScreenGui.Name = "ReplayUI"

ScreenGui.ResetOnSpawn = false

ScreenGui.Parent =
	Player:WaitForChild("PlayerGui")


--============================================================
-- MAIN FRAME
--============================================================

local MainFrame =
	Instance.new("Frame")

MainFrame.Name = "MainFrame"

MainFrame.Size =
	UDim2.new(0, 300, 0, 330)

MainFrame.Position =
	UDim2.new(0, 20, 0.5, -165)

MainFrame.BackgroundColor3 =
	Color3.fromRGB(25, 25, 25)

MainFrame.BorderSizePixel = 0

MainFrame.Parent = ScreenGui


local MainCorner =
	Instance.new("UICorner")

MainCorner.CornerRadius =
	UDim.new(0, 8)

MainCorner.Parent =
	MainFrame


--============================================================
-- HEADER
--============================================================

local Header =
	Instance.new("Frame")

Header.Name = "Header"

Header.Size =
	UDim2.new(1, 0, 0, 42)

Header.BackgroundColor3 =
	Color3.fromRGB(35, 35, 35)

Header.BorderSizePixel = 0

Header.Parent =
	MainFrame


local HeaderCorner =
	Instance.new("UICorner")

HeaderCorner.CornerRadius =
	UDim.new(0, 8)

HeaderCorner.Parent =
	Header


--============================================================
-- TITLE
--============================================================

local Title =
	Instance.new("TextLabel")

Title.Size =
	UDim2.new(1, -90, 1, 0)

Title.Position =
	UDim2.new(0, 12, 0, 0)

Title.BackgroundTransparency = 1

Title.Text =
	"Replay System"

Title.TextColor3 =
	Color3.fromRGB(255, 255, 255)

Title.TextSize = 18

Title.Font =
	Enum.Font.GothamBold

Title.TextXAlignment =
	Enum.TextXAlignment.Left

Title.Parent =
	Header


--============================================================
-- VERSION LABEL
--============================================================

local VersionLabel =
	Instance.new("TextLabel")

VersionLabel.Size =
	UDim2.new(0, 55, 1, 0)

VersionLabel.Position =
	UDim2.new(1, -90, 0, 0)

VersionLabel.BackgroundTransparency = 1

VersionLabel.Text =
	VERSION

VersionLabel.TextColor3 =
	Color3.fromRGB(140, 140, 140)

VersionLabel.TextSize = 11

VersionLabel.Font =
	Enum.Font.Gotham

VersionLabel.TextXAlignment =
	Enum.TextXAlignment.Right

VersionLabel.Parent =
	Header


--============================================================
-- MINIMIZE BUTTON
--============================================================

local MinimizeButton =
	Instance.new("TextButton")

MinimizeButton.Size =
	UDim2.new(0, 30, 0, 30)

MinimizeButton.Position =
	UDim2.new(1, -35, 0, 6)

MinimizeButton.BackgroundTransparency = 1

MinimizeButton.Text = "-"

MinimizeButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

MinimizeButton.TextSize = 22

MinimizeButton.Font =
	Enum.Font.GothamBold

MinimizeButton.Parent =
	Header


--============================================================
-- STATUS
--============================================================

local StatusLabel =
	Instance.new("TextLabel")

StatusLabel.Size =
	UDim2.new(1, -20, 0, 25)

StatusLabel.Position =
	UDim2.new(0, 10, 0, 50)

StatusLabel.BackgroundTransparency = 1

StatusLabel.Text =
	"Status: Idle"

StatusLabel.TextColor3 =
	Color3.fromRGB(200, 200, 200)

StatusLabel.TextSize = 14

StatusLabel.Font =
	Enum.Font.Gotham

StatusLabel.TextXAlignment =
	Enum.TextXAlignment.Left

StatusLabel.Parent =
	MainFrame


--============================================================
-- NAME BOX
--============================================================

local NameBox =
	Instance.new("TextBox")

NameBox.Size =
	UDim2.new(1, -20, 0, 35)

NameBox.Position =
	UDim2.new(0, 10, 0, 80)

NameBox.BackgroundColor3 =
	Color3.fromRGB(40, 40, 40)

NameBox.BorderSizePixel = 0

NameBox.PlaceholderText =
	"Recording name..."

NameBox.Text = ""

NameBox.TextColor3 =
	Color3.fromRGB(255, 255, 255)

NameBox.PlaceholderColor3 =
	Color3.fromRGB(150, 150, 150)

NameBox.TextSize = 14

NameBox.Font =
	Enum.Font.Gotham

NameBox.Parent =
	MainFrame


local NameCorner =
	Instance.new("UICorner")

NameCorner.CornerRadius =
	UDim.new(0, 6)

NameCorner.Parent =
	NameBox


--============================================================
-- RECORD BUTTON
--============================================================

local RecordButton =
	Instance.new("TextButton")

RecordButton.Size =
	UDim2.new(0.48, -5, 0, 35)

RecordButton.Position =
	UDim2.new(0, 10, 0, 125)

RecordButton.BackgroundColor3 =
	Color3.fromRGB(60, 120, 70)

RecordButton.BorderSizePixel = 0

RecordButton.Text =
	"Record"

RecordButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

RecordButton.TextSize = 14

RecordButton.Font =
	Enum.Font.GothamBold

RecordButton.Parent =
	MainFrame


local RecordCorner =
	Instance.new("UICorner")

RecordCorner.CornerRadius =
	UDim.new(0, 6)

RecordCorner.Parent =
	RecordButton


--============================================================
-- STOP BUTTON
--============================================================

local StopButton =
	Instance.new("TextButton")

StopButton.Size =
	UDim2.new(0.48, -5, 0, 35)

StopButton.Position =
	UDim2.new(0.52, 0, 0, 125)

StopButton.BackgroundColor3 =
	Color3.fromRGB(130, 60, 60)

StopButton.BorderSizePixel = 0

StopButton.Text =
	"Stop"

StopButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

StopButton.TextSize = 14

StopButton.Font =
	Enum.Font.GothamBold

StopButton.Parent =
	MainFrame


local StopCorner =
	Instance.new("UICorner")

StopCorner.CornerRadius =
	UDim.new(0, 6)

StopCorner.Parent =
	StopButton


--============================================================
-- REPLAY BUTTON
--============================================================

local ReplayButton =
	Instance.new("TextButton")

ReplayButton.Size =
	UDim2.new(1, -20, 0, 35)

ReplayButton.Position =
	UDim2.new(0, 10, 0, 170)

ReplayButton.BackgroundColor3 =
	Color3.fromRGB(65, 90, 150)

ReplayButton.BorderSizePixel = 0

ReplayButton.Text =
	"Replay Selected"

ReplayButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

ReplayButton.TextSize = 14

ReplayButton.Font =
	Enum.Font.GothamBold

ReplayButton.Parent =
	MainFrame


local ReplayCorner =
	Instance.new("UICorner")

ReplayCorner.CornerRadius =
	UDim.new(0, 6)

ReplayCorner.Parent =
	ReplayButton


--============================================================
-- DROPDOWN BUTTON
--============================================================

local DropdownButton =
	Instance.new("TextButton")

DropdownButton.Size =
	UDim2.new(1, -20, 0, 35)

DropdownButton.Position =
	UDim2.new(0, 10, 0, 215)

DropdownButton.BackgroundColor3 =
	Color3.fromRGB(40, 40, 40)

DropdownButton.BorderSizePixel = 0

DropdownButton.Text =
	"Select Recording ▼"

DropdownButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

DropdownButton.TextSize = 14

DropdownButton.Font =
	Enum.Font.Gotham

DropdownButton.Parent =
	MainFrame


local DropdownCorner =
	Instance.new("UICorner")

DropdownCorner.CornerRadius =
	UDim.new(0, 6)

DropdownCorner.Parent =
	DropdownButton


--============================================================
-- DROPDOWN
--============================================================

local DropdownFrame =
	Instance.new("ScrollingFrame")

DropdownFrame.Name =
	"Dropdown"

DropdownFrame.Size =
	UDim2.new(1, -20, 0, 75)

DropdownFrame.Position =
	UDim2.new(0, 10, 0, 255)

DropdownFrame.BackgroundColor3 =
	Color3.fromRGB(35, 35, 35)

DropdownFrame.BorderSizePixel = 0

DropdownFrame.ScrollBarThickness = 4

DropdownFrame.Visible = false

DropdownFrame.CanvasSize =
	UDim2.new(0, 0, 0, 0)

DropdownFrame.Parent =
	MainFrame


local DropdownLayout =
	Instance.new("UIListLayout")

DropdownLayout.Padding =
	UDim.new(0, 2)

DropdownLayout.Parent =
	DropdownFrame


--============================================================
-- MINIMIZE
--============================================================

local Minimized = false


MinimizeButton.MouseButton1Click:Connect(function()

	Minimized = not Minimized


	if Minimized then

		MainFrame.Size =
			UDim2.new(0, 300, 0, 42)

		for _, Child in ipairs(
			MainFrame:GetChildren()
		) do

			if Child ~= Header then
				Child.Visible = false
			end

		end

		MinimizeButton.Text = "+"

	else

		MainFrame.Size =
			UDim2.new(0, 300, 0, 330)

		for _, Child in ipairs(
			MainFrame:GetChildren()
		) do

			Child.Visible = true

		end

		MinimizeButton.Text = "-"

	end

end)


--============================================================
-- DRAGGING
--============================================================

local Dragging = false
local DragStart
local StartPosition


Header.InputBegan:Connect(function(Input)

	if Input.UserInputType ==
		Enum.UserInputType.MouseButton1 then

		Dragging = true

		DragStart =
			Input.Position

		StartPosition =
			MainFrame.Position

	end

end)


Header.InputEnded:Connect(function(Input)

	if Input.UserInputType ==
		Enum.UserInputType.MouseButton1 then

		Dragging = false

	end

end)


UserInputService.InputChanged:Connect(function(Input)

	if not Dragging then
		return
	end

	if Input.UserInputType ~=
		Enum.UserInputType.MouseMovement then

		return

	end


	local Delta =
		Input.Position - DragStart


	MainFrame.Position =
		UDim2.new(
			StartPosition.X.Scale,
			StartPosition.X.Offset + Delta.X,
			StartPosition.Y.Scale,
			StartPosition.Y.Offset + Delta.Y
		)

end)


--============================================================
-- FIND SKILL
-- IMPORTANT:
-- Your actual skill scripts use Backpack:WaitForChild()
-- so Backpack is checked FIRST.
--============================================================

local function FindSkillTool(ToolName)

	if not ToolName then
		return nil
	end


	local Backpack =
		Player:FindFirstChild("Backpack")


	------------------------------------------------------------
	-- BACKPACK FIRST
	------------------------------------------------------------

	if Backpack then

		local Tool =
			Backpack:FindFirstChild(ToolName)


		if Tool and Tool:IsA("Tool") then

			return Tool

		end

	end


	------------------------------------------------------------
	-- CHARACTER SECOND
	------------------------------------------------------------

	if Character then

		local Tool =
			Character:FindFirstChild(ToolName)


		if Tool and Tool:IsA("Tool") then

			return Tool

		end

	end


	return nil

end


--============================================================
-- WAIT FOR SKILL
--============================================================

local function WaitForSkillTool(ToolName, Timeout)

	Timeout =
		Timeout or 2


	local StartTime =
		os.clock()


	local Tool


	while os.clock() - StartTime < Timeout do

		Tool =
			FindSkillTool(ToolName)


		if Tool then
			return Tool
		end


		task.wait(0.03)

	end


	return nil

end


--============================================================
-- GET CURRENT SKILL
--============================================================

local function GetCurrentSkillTool()

	if not Character then
		return nil
	end


	------------------------------------------------------------
	-- Equipped tool is normally in Character
	------------------------------------------------------------

	for _, Child in ipairs(
		Character:GetChildren()
	) do

		if Child:IsA("Tool") then

			return Child

		end

	end


	return nil

end


--============================================================
-- RECORD SKILL
--============================================================

local function RecordSkill(Key)

	if not Recording then
		return
	end

	if not CurrentRecording then
		return
	end


	local Tool =
		GetCurrentSkillTool()


	if not Tool then

		warn(
			"[Replay] No skill tool equipped when",
			Key,
			"was pressed"
		)

		return

	end


	table.insert(
		CurrentRecording.Inputs,
		{

			Time =
				os.clock() -
				RecordStartTime,

			ActionType =
				"Skill",

			Key =
				Key,

			ToolName =
				Tool.Name

		}
	)


	print(
		"[Replay] Recorded skill:",
		Key,
		Tool.Name
	)

end


--============================================================
-- FIND SKILL EVENT
--============================================================

local function FindSkillEvent(SkillTool)

	if not SkillTool then
		return nil
	end


	------------------------------------------------------------
	-- Your provided skills:
	--
	-- Inner Focus -> abilityEvent
	-- Pulse Waves -> abilityEvent
	-- Whirlwind -> spellEvent
	------------------------------------------------------------


	local AbilityEvent =
		SkillTool:FindFirstChild(
			"abilityEvent"
		)


	if AbilityEvent and
		AbilityEvent:IsA("RemoteEvent") then

		return AbilityEvent

	end


	local SpellEvent =
		SkillTool:FindFirstChild(
			"spellEvent"
		)


	if SpellEvent and
		SpellEvent:IsA("RemoteEvent") then

		return SpellEvent

	end


	------------------------------------------------------------
	-- Extra fallback:
	-- Search descendants in case the event is nested.
	------------------------------------------------------------

	for _, Descendant in ipairs(
		SkillTool:GetDescendants()
	) do

		if Descendant:IsA("RemoteEvent") then

			if Descendant.Name ==
				"abilityEvent" then

				return Descendant

			end


			if Descendant.Name ==
				"spellEvent" then

				return Descendant

			end

		end

	end


	return nil

end


--============================================================
-- REPLAY SKILL
--============================================================

local function ReplaySkill(Key, ToolName)

	if not Key then
		return
	end

	if not ToolName then
		return
	end


	print(
		"[Replay] Attempting skill:",
		Key,
		ToolName
	)


	------------------------------------------------------------
	-- GET THE EXACT SKILL TOOL
	------------------------------------------------------------

	local SkillTool =
		WaitForSkillTool(
			ToolName,
			2
		)


	if not SkillTool then

		warn(
			"[Replay] Could not find skill:",
			ToolName
		)

		return

	end


	print(
		"[Replay] Found skill:",
		SkillTool:GetFullName()
	)


	------------------------------------------------------------
	-- FIND EVENT BEFORE FIRING
	------------------------------------------------------------

	local SkillEvent =
		FindSkillEvent(
			SkillTool
		)


	if not SkillEvent then

		warn(
			"[Replay] No abilityEvent/spellEvent found:",
			SkillTool:GetFullName()
		)

		return

	end


	print(
		"[Replay] Using event:",
		SkillEvent:GetFullName()
	)


	------------------------------------------------------------
	-- IMPORTANT:
	-- This matches your actual activation code:
	--
	-- abilityUsed:FireServer("q", tool)
	------------------------------------------------------------

	local Success, ErrorMessage =
		pcall(function()

			AbilityUsed:FireServer(
				Key,
				SkillTool
			)

		end)


	if not Success then

		warn(
			"[Replay] abilityUsed failed:",
			ErrorMessage
		)

		return

	end


	------------------------------------------------------------
	-- FIRE THE ACTUAL SKILL EVENT
	------------------------------------------------------------

	local EventSuccess,
		EventError =
		pcall(function()

			SkillEvent:FireServer()

		end)


	if not EventSuccess then

		warn(
			"[Replay] Skill event failed:",
			EventError
		)

		return

	end


	print(
		"[Replay] Skill fired successfully:",
		Key,
		ToolName
	)

end


--============================================================
-- RESET PATH
--============================================================

local function ResetPath()

	CurrentPath = nil

	CurrentPathIndex = 1

	LastPathTarget = nil

	StuckTimer = 0

	PathComputing = false

end


--============================================================
-- CREATE PATH
-- IMPORTANT:
-- This is NOT called every 0.5 seconds anymore.
--============================================================

local function CreatePathTo(TargetPosition)

	if not RootPart then
		return false
	end

	if not Humanoid then
		return false
	end

	if PathComputing then
		return false
	end


	PathComputing = true


	local Path =
		PathfindingService:CreatePath({

			AgentRadius = 2,

			AgentHeight = 5,

			AgentCanJump = true,

			AgentCanClimb = true,

			WaypointSpacing = 4

		})


	local Success =
		pcall(function()

			Path:ComputeAsync(
				RootPart.Position,
				TargetPosition
			)

		end)


	PathComputing = false


	if not Success then

		CurrentPath = nil

		return false

	end


	if Path.Status ~=
		Enum.PathStatus.Success then

		CurrentPath = nil

		return false

	end


	CurrentPath =
		Path:GetWaypoints()


	------------------------------------------------------------
	-- Usually waypoint 1 is current position.
	------------------------------------------------------------

	CurrentPathIndex = 2


	LastPathTarget =
		TargetPosition


	------------------------------------------------------------
	-- If there is only one waypoint, use direct movement.
	------------------------------------------------------------

	if not CurrentPath[CurrentPathIndex] then

		CurrentPathIndex = 1

	end


	return true

end


--============================================================
-- PATH BLOCKED
--============================================================

local function ConnectPathBlocked(Path)

	if not Path then
		return
	end


	Path.Blocked:Connect(function(BlockedIndex)

		if not Replaying then
			return
		end


		if BlockedIndex >=
			CurrentPathIndex then

			CurrentPath = nil

		end

	end)

end


--============================================================
-- MOVE TO TARGET
--============================================================

local function MoveToReplayPosition(TargetPosition)

	if not Humanoid then
		return false
	end

	if not RootPart then
		return false
	end


	local Distance =
		(
			RootPart.Position -
			TargetPosition
		).Magnitude


	------------------------------------------------------------
	-- TARGET REACHED
	------------------------------------------------------------

	if Distance <=
		MOVEMENT_REACH_DISTANCE then

		ResetPath()

		ReplayIndex += 1

		return true

	end


	------------------------------------------------------------
	-- STUCK DETECTION
	------------------------------------------------------------

	local Now =
		os.clock()


	if not LastPosition then

		LastPosition =
			RootPart.Position

		LastMovementCheck =
			Now

	else

		if Now -
			LastMovementCheck >=
			0.25 then

			local Moved =
				(
					RootPart.Position -
					LastPosition
				).Magnitude


			if Moved < 0.15 then

				StuckTimer +=
					Now -
					LastMovementCheck

			else

				StuckTimer = 0

			end


			LastPosition =
				RootPart.Position

			LastMovementCheck =
				Now

		end

	end


	------------------------------------------------------------
	-- FIRST PATH
	------------------------------------------------------------

	if not CurrentPath then

		local Created =
			CreatePathTo(
				TargetPosition
			)


		if Created then

			------------------------------------------------
			-- Continue below and immediately move.
			------------------------------------------------

		else

			------------------------------------------------
			-- If pathfinding fails, don't stop.
			-- Continue directly toward target.
			------------------------------------------------

			Humanoid:MoveTo(
				TargetPosition
			)

			return false

		end

	end


	------------------------------------------------------------
	-- RECREATE ONLY WHEN:
	--
	-- 1. Target moved significantly
	-- 2. Player is actually stuck
	------------------------------------------------------------

	if LastPathTarget then

		local TargetMoved =
			(
				TargetPosition -
				LastPathTarget
			).Magnitude


		if TargetMoved >
			PATH_TARGET_CHANGE then

			local Created =
				CreatePathTo(
					TargetPosition
				)

			if not Created then

				Humanoid:MoveTo(
					TargetPosition
				)

				return false

			end

		end

	end


	------------------------------------------------------------
	-- STUCK
	------------------------------------------------------------

	if StuckTimer >=
		STUCK_TIME then

		ResetPath()

		StuckTimer = 0


		local Created =
			CreatePathTo(
				TargetPosition
			)


		if not Created then

			Humanoid:MoveTo(
				TargetPosition
			)

			return false

		end

	end


	------------------------------------------------------------
	-- FOLLOW PATH
	------------------------------------------------------------

	if CurrentPath then

		local Waypoint =
			CurrentPath[
				CurrentPathIndex
			]


		if Waypoint then

			local WaypointDistance =
				(
					RootPart.Position -
					Waypoint.Position
				).Magnitude


			if WaypointDistance <=
				WAYPOINT_REACH_DISTANCE then

				CurrentPathIndex += 1

				Waypoint =
					CurrentPath[
						CurrentPathIndex
					]

			end


			if Waypoint then

				if Waypoint.Action ==
					Enum.PathWaypointAction.Jump then

					Humanoid.Jump = true

				end


				------------------------------------------------
				-- Keep MoveTo active continuously.
				------------------------------------------------

				Humanoid:MoveTo(
					Waypoint.Position
				)

				return false

			end

		end

	end


	------------------------------------------------------------
	-- PATH FINISHED
	------------------------------------------------------------

	Humanoid:MoveTo(
		TargetPosition
	)


	return false

end


--============================================================
-- FIND NEAREST RECORDED POINT
--============================================================

local function FindNearestMovementPoint(
	Recording
)

	if not Recording then
		return nil, math.huge
	end


	if not Recording.Movement then
		return nil, math.huge
	end


	if not RootPart then
		return nil, math.huge
	end


	local ClosestIndex = nil

	local ClosestDistance =
		math.huge


	for Index, Point in ipairs(
		Recording.Movement
	) do

		if Point.Position then

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

	end


	return ClosestIndex,
		ClosestDistance

end


--============================================================
-- STOP REPLAY
--============================================================

local function StopReplay()

	Replaying = false

	ResumeAfterDeath = false


	if ReplayConnection then

		ReplayConnection:Disconnect()

		ReplayConnection = nil

	end


	ResetPath()


	LastPosition = nil


	if Humanoid then

		Humanoid:Move(
			Vector3.zero,
			false
		)

	end


	StatusLabel.Text =
		"Status: Idle"

end


--============================================================
-- START REPLAY
--============================================================

local function StartReplay(
	Recording,
	StartIndex
)

	if not Recording then
		return
	end


	if not Recording.Movement then
		return
	end


	if #Recording.Movement == 0 then
		return
	end


	if Replaying then
		StopReplay()
	end


	Replaying = true


	ResumeAfterDeath = false


	ReplayIndex =
		StartIndex or 1


	ReplayStartTime =
		os.clock()


	ReplayTimeOffset = 0


	ReplayInputIndex = 1


	ResetPath()


	LastPosition = nil

	LastMovementCheck =
		os.clock()


	StuckTimer = 0


	------------------------------------------------------------
	-- RESUME TIMESTAMP
	------------------------------------------------------------

	local ResumeTime = 0


	if Recording.Movement[
		ReplayIndex
	] then

		ResumeTime =
			Recording.Movement[
				ReplayIndex
			].Time or 0

	end


	ReplayTimeOffset =
		ResumeTime


	------------------------------------------------------------
	-- FIND FIRST INPUT AFTER RESUME
	------------------------------------------------------------

	for Index, InputData in ipairs(
		Recording.Inputs
	) do

		if InputData.Time >=
			ResumeTime then

			ReplayInputIndex =
				Index

			break

		end

	end


	StatusLabel.Text =
		"Status: Replaying " ..
		Recording.Name


	------------------------------------------------------------
	-- REPLAY LOOP
	------------------------------------------------------------

	ReplayConnection =
		RunService.Heartbeat:Connect(
			function()

				if not Replaying then
					return
				end


				if not Character then
					return
				end


				if not Humanoid then
					return
				end


				if not RootPart then
					return
				end


				------------------------------------------------
				-- DEAD
				------------------------------------------------

				if Humanoid.Health <= 0 then

					ResumeAfterDeath = true


					if ReplayConnection then

						ReplayConnection:Disconnect()

						ReplayConnection = nil

					end


					Replaying = false


					StatusLabel.Text =
						"Status: Waiting for respawn..."


					return

				end


				------------------------------------------------
				-- CURRENT REPLAY TIME
				------------------------------------------------

				local ElapsedTime =
					(
						os.clock() -
						ReplayStartTime
					) +
					ReplayTimeOffset


				------------------------------------------------
				-- SKILLS
				------------------------------------------------

				while
					ReplayInputIndex <=
					#Recording.Inputs
				do

					local InputData =
						Recording.Inputs[
							ReplayInputIndex
						]


					if InputData.Time >
						ElapsedTime then

						break

					end


					if InputData.ActionType ==
						"Skill" then

						ReplaySkill(
							InputData.Key,
							InputData.ToolName
						)

					end


					ReplayInputIndex += 1

				end


				------------------------------------------------
				-- END
				------------------------------------------------

				if ReplayIndex >
					#Recording.Movement then

					StopReplay()

					return

				end


				------------------------------------------------
				-- CURRENT MOVEMENT
				------------------------------------------------

				local MovementData =
					Recording.Movement[
						ReplayIndex
					]


				if not MovementData then

					StopReplay()

					return

				end


				------------------------------------------------
				-- WAIT FOR TIMESTAMP
				------------------------------------------------

				if MovementData.Time >
					ElapsedTime then

					return

				end


				------------------------------------------------
				-- MOVE
				------------------------------------------------

				MoveToReplayPosition(
					MovementData.Position
				)

			end
		)

end


--============================================================
-- START RECORDING
--============================================================

local function StartRecording()

	if Recording then
		return
	end


	if Replaying then
		StopReplay()
	end


	if not Character then
		return
	end


	if not RootPart then
		return
	end


	local RecordingName =
		NameBox.Text


	if RecordingName == "" then

		RecordingName =
			"Recording " ..
			tostring(
				#Recordings + 1
			)

	end


	CurrentRecording = {

		Name =
			RecordingName,

		Version =
			VERSION,

		Movement = {},

		Inputs = {}

	}


	Recording = true


	RecordStartTime =
		os.clock()


	LastRecordTime = 0


	StatusLabel.Text =
		"Status: Recording..."


	------------------------------------------------------------
	-- MOVEMENT RECORDING
	------------------------------------------------------------

	RecordConnection =
		RunService.Heartbeat:Connect(
			function()

				if not Recording then
					return
				end


				if not RootPart then
					return
				end


				local Now =
					os.clock()


				local Elapsed =
					Now -
					RecordStartTime


				if Elapsed -
					LastRecordTime <
					RECORD_INTERVAL then

					return

				end


				LastRecordTime =
					Elapsed


				table.insert(
					CurrentRecording.Movement,
					{

						Time =
							Elapsed,

						Position =
							RootPart.Position,

						CFrame =
							RootPart.CFrame

					}
				)

			end
		)

end


--============================================================
-- STOP RECORDING
--============================================================

local function StopRecording()

	if not Recording then
		return
	end


	Recording = false


	if RecordConnection then

		RecordConnection:Disconnect()

		RecordConnection = nil

	end


	if CurrentRecording then

		table.insert(
			Recordings,
			CurrentRecording
		)


		SelectedRecording =
			CurrentRecording

	end


	StatusLabel.Text =
		"Status: Saved " ..
		(
			CurrentRecording
			and CurrentRecording.Name
			or ""
		)


	CurrentRecording = nil


	UpdateDropdown()

end


--============================================================
-- RECORD Q/E
--============================================================

UserInputService.InputBegan:Connect(
	function(
		Input,
		GameProcessed
	)

		if GameProcessed then
			return
		end


		if Input.KeyCode ==
			Enum.KeyCode.Q then

			RecordSkill("q")

		end


		if Input.KeyCode ==
			Enum.KeyCode.E then

			RecordSkill("e")

		end

	end
)


--============================================================
-- DROPDOWN UPDATE
--============================================================

function UpdateDropdown()

	for _, Child in ipairs(
		DropdownFrame:GetChildren()
	) do

		if Child:IsA("TextButton") then

			Child:Destroy()

		end

	end


	for _, Recording in ipairs(
		Recordings
	) do

		local Button =
			Instance.new("TextButton")


		Button.Size =
			UDim2.new(1, -5, 0, 30)


		Button.BackgroundColor3 =
			Color3.fromRGB(50, 50, 50)


		Button.BorderSizePixel = 0


		Button.Text =
			Recording.Name


		Button.TextColor3 =
			Color3.fromRGB(
				255,
				255,
				255
			)


		Button.TextSize = 13


		Button.Font =
			Enum.Font.Gotham


		Button.Parent =
			DropdownFrame


		local ButtonCorner =
			Instance.new("UICorner")


		ButtonCorner.CornerRadius =
			UDim.new(0, 5)


		ButtonCorner.Parent =
			Button


		Button.MouseButton1Click:Connect(
			function()

				SelectedRecording =
					Recording


				DropdownButton.Text =
					Recording.Name ..
					" ▼"


				DropdownFrame.Visible =
					false


				StatusLabel.Text =
					"Selected: " ..
					Recording.Name

			end
		)

	end


	DropdownFrame.CanvasSize =
		UDim2.new(
			0,
			0,
			0,
			DropdownLayout.AbsoluteContentSize.Y
		)

end


--============================================================
-- DROPDOWN
--============================================================

DropdownButton.MouseButton1Click:Connect(
	function()

		DropdownFrame.Visible =
			not DropdownFrame.Visible

	end
)


--============================================================
-- RECORD BUTTON
--============================================================

RecordButton.MouseButton1Click:Connect(
	function()

		StartRecording()

	end
)


--============================================================
-- STOP BUTTON
--============================================================

StopButton.MouseButton1Click:Connect(
	function()

		if Recording then

			StopRecording()

		elseif Replaying then

			StopReplay()

		end

	end
)


--============================================================
-- REPLAY BUTTON
--============================================================

ReplayButton.MouseButton1Click:Connect(
	function()

		if not SelectedRecording then

			StatusLabel.Text =
				"Status: No recording selected"

			return

		end


		if #SelectedRecording.Movement == 0 then

			StatusLabel.Text =
				"Status: Recording is empty"

			return

		end


		StartReplay(
			SelectedRecording,
			1
		)

	end
)


--============================================================
-- DEATH DETECTION
--============================================================

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

				if not Replaying then
					return
				end


				ResumeAfterDeath = true


				if ReplayConnection then

					ReplayConnection:Disconnect()

					ReplayConnection = nil

				end


				Replaying = false


				ResetPath()


				StatusLabel.Text =
					"Status: Waiting for respawn..."

			end
		)

end


--============================================================
-- CHARACTER RESPAWN
--============================================================

Player.CharacterAdded:Connect(
	function(NewCharacter)

		SetupCharacter(
			NewCharacter
		)


		SetupDeathDetection()


		if not ResumeAfterDeath then
			return
		end


		ResumeAfterDeath = false


		local RecordingToResume =
			SelectedRecording


		if not RecordingToResume then

			StatusLabel.Text =
				"Status: Idle"

			return

		end


		--------------------------------------------------------
		-- WAIT FOR CHARACTER TO FULLY LOAD
		--------------------------------------------------------

		task.wait(0.75)


		if not RootPart then
			return
		end


		--------------------------------------------------------
		-- FIND NEAREST PATH POINT
		--------------------------------------------------------

		local ClosestIndex,
			ClosestDistance =
			FindNearestMovementPoint(
				RecordingToResume
			)


		if not ClosestIndex then

			StatusLabel.Text =
				"Status: Could not resume"

			return

		end


		--------------------------------------------------------
		-- TOO FAR
		--------------------------------------------------------

		if ClosestDistance >
			MAX_RESUME_DISTANCE then

			StatusLabel.Text =
				"Status: Respawn too far from path"

			return

		end


		StatusLabel.Text =
			"Status: Resuming replay..."


		task.wait(0.25)


		--------------------------------------------------------
		-- RESUME
		--------------------------------------------------------

		StartReplay(
			RecordingToResume,
			ClosestIndex
		)

	end
)


--============================================================
-- INITIAL DEATH SETUP
--============================================================

if Humanoid then

	SetupDeathDetection()

end


--============================================================
-- INITIAL UI
--============================================================

UpdateDropdown()


StatusLabel.Text =
	"Status: Idle"


print(
	"Replay System loaded",
	VERSION
)
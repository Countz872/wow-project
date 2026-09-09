--============================================================
-- REPLAY SYSTEM v1.2.0
-- Movement + Pathfinding + Death Resume + Q/E Skills
--
-- VERSION: 1.2.0
--
-- SKILL FIXES:
-- • Records Q/E even when GameProcessed is true
-- • Does NOT require skills to be Tools
-- • Searches Backpack first
-- • Uses exact abilityUsed -> abilityEvent/spellEvent sequence
-- • Supports Inner Focus
-- • Supports Pulse Waves
-- • Supports Whirlwind
-- • Automatically supports future skills using the same system
--
-- MOVEMENT FIXES:
-- • Less path recalculation
-- • Smoother MoveTo
-- • Recalculates only when actually stuck
-- • No CFrame teleporting
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

local VERSION = "v1.2.0"


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

local MOVEMENT_REACH_DISTANCE = 2.5

local WAYPOINT_REACH_DISTANCE = 2.5

local PATH_TARGET_CHANGE = 10

local STUCK_TIME = 1.75

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

ScreenGui.Name =
	"ReplayUI"

ScreenGui.ResetOnSpawn =
	false

ScreenGui.Parent =
	Player:WaitForChild("PlayerGui")


--============================================================
-- MAIN FRAME
--============================================================

local MainFrame =
	Instance.new("Frame")

MainFrame.Name =
	"MainFrame"

MainFrame.Size =
	UDim2.new(0, 300, 0, 330)

MainFrame.Position =
	UDim2.new(0, 20, 0.5, -165)

MainFrame.BackgroundColor3 =
	Color3.fromRGB(25, 25, 25)

MainFrame.BorderSizePixel =
	0

MainFrame.Parent =
	ScreenGui


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

Header.Size =
	UDim2.new(1, 0, 0, 42)

Header.BackgroundColor3 =
	Color3.fromRGB(35, 35, 35)

Header.BorderSizePixel =
	0

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
	UDim2.new(1, -95, 1, 0)

Title.Position =
	UDim2.new(0, 12, 0, 0)

Title.BackgroundTransparency =
	1

Title.Text =
	"Replay System"

Title.TextColor3 =
	Color3.fromRGB(255, 255, 255)

Title.TextSize =
	18

Title.Font =
	Enum.Font.GothamBold

Title.TextXAlignment =
	Enum.TextXAlignment.Left

Title.Parent =
	Header


--============================================================
-- VERSION
--============================================================

local VersionLabel =
	Instance.new("TextLabel")

VersionLabel.Size =
	UDim2.new(0, 55, 1, 0)

VersionLabel.Position =
	UDim2.new(1, -90, 0, 0)

VersionLabel.BackgroundTransparency =
	1

VersionLabel.Text =
	VERSION

VersionLabel.TextColor3 =
	Color3.fromRGB(150, 150, 150)

VersionLabel.TextSize =
	11

VersionLabel.Font =
	Enum.Font.Gotham

VersionLabel.TextXAlignment =
	Enum.TextXAlignment.Right

VersionLabel.Parent =
	Header


--============================================================
-- MINIMIZE
--============================================================

local MinimizeButton =
	Instance.new("TextButton")

MinimizeButton.Size =
	UDim2.new(0, 30, 0, 30)

MinimizeButton.Position =
	UDim2.new(1, -35, 0, 6)

MinimizeButton.BackgroundTransparency =
	1

MinimizeButton.Text =
	"-"

MinimizeButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

MinimizeButton.TextSize =
	22

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

StatusLabel.BackgroundTransparency =
	1

StatusLabel.Text =
	"Status: Idle"

StatusLabel.TextColor3 =
	Color3.fromRGB(200, 200, 200)

StatusLabel.TextSize =
	14

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

NameBox.BorderSizePixel =
	0

NameBox.PlaceholderText =
	"Recording name..."

NameBox.Text =
	""

NameBox.TextColor3 =
	Color3.fromRGB(255, 255, 255)

NameBox.PlaceholderColor3 =
	Color3.fromRGB(150, 150, 150)

NameBox.TextSize =
	14

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

RecordButton.BorderSizePixel =
	0

RecordButton.Text =
	"Record"

RecordButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

RecordButton.TextSize =
	14

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

StopButton.BorderSizePixel =
	0

StopButton.Text =
	"Stop"

StopButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

StopButton.TextSize =
	14

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

ReplayButton.BorderSizePixel =
	0

ReplayButton.Text =
	"Replay Selected"

ReplayButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

ReplayButton.TextSize =
	14

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
-- DROPDOWN
--============================================================

local DropdownButton =
	Instance.new("TextButton")

DropdownButton.Size =
	UDim2.new(1, -20, 0, 35)

DropdownButton.Position =
	UDim2.new(0, 10, 0, 215)

DropdownButton.BackgroundColor3 =
	Color3.fromRGB(40, 40, 40)

DropdownButton.BorderSizePixel =
	0

DropdownButton.Text =
	"Select Recording ▼"

DropdownButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

DropdownButton.TextSize =
	14

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

DropdownFrame.BorderSizePixel =
	0

DropdownFrame.ScrollBarThickness =
	4

DropdownFrame.Visible =
	false

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
-- MINIMIZE BUTTON
--============================================================

local Minimized = false


MinimizeButton.MouseButton1Click:Connect(
	function()

		Minimized =
			not Minimized


		if Minimized then

			MainFrame.Size =
				UDim2.new(0, 300, 0, 42)


			for _, Child in ipairs(
				MainFrame:GetChildren()
			) do

				if Child ~= Header then

					Child.Visible =
						false

				end

			end


			MinimizeButton.Text =
				"+"


		else

			MainFrame.Size =
				UDim2.new(0, 300, 0, 330)


			for _, Child in ipairs(
				MainFrame:GetChildren()
			) do

				Child.Visible =
					true

			end


			MinimizeButton.Text =
				"-"

		end

	end
)


--============================================================
-- DRAGGING
--============================================================

local Dragging = false

local DragStart

local StartPosition


Header.InputBegan:Connect(
	function(Input)

		if Input.UserInputType ==
			Enum.UserInputType.MouseButton1 then

			Dragging = true

			DragStart =
				Input.Position

			StartPosition =
				MainFrame.Position

		end

	end
)


Header.InputEnded:Connect(
	function(Input)

		if Input.UserInputType ==
			Enum.UserInputType.MouseButton1 then

			Dragging = false

		end

	end
)


UserInputService.InputChanged:Connect(
	function(Input)

		if not Dragging then
			return
		end


		if Input.UserInputType ~=
			Enum.UserInputType.MouseMovement then

			return

		end


		local Delta =
			Input.Position -
			DragStart


		MainFrame.Position =
			UDim2.new(

				StartPosition.X.Scale,

				StartPosition.X.Offset +
					Delta.X,

				StartPosition.Y.Scale,

				StartPosition.Y.Offset +
					Delta.Y

			)

	end
)


--============================================================
-- FIND SKILL
--
-- IMPORTANT:
-- DO NOT require IsA("Tool").
--
-- Your supplied code does:
--
-- Backpack:WaitForChild("Inner Focus")
-- Backpack:WaitForChild("Pulse Waves")
--
-- So we simply find the object.
--============================================================

local function FindSkill(ToolName)

	if not ToolName then
		return nil
	end


	local Backpack =
		Player:FindFirstChild("Backpack")


	------------------------------------------------------------
	-- BACKPACK FIRST
	------------------------------------------------------------

	if Backpack then

		local Skill =
			Backpack:FindFirstChild(
				ToolName
			)


		if Skill then

			return Skill

		end

	end


	------------------------------------------------------------
	-- CHARACTER SECOND
	------------------------------------------------------------

	if Character then

		local Skill =
			Character:FindFirstChild(
				ToolName
			)


		if Skill then

			return Skill

		end

	end


	return nil

end


--============================================================
-- WAIT FOR SKILL
--============================================================

local function WaitForSkill(
	SkillName,
	Timeout
)

	Timeout =
		Timeout or 3


	local StartTime =
		os.clock()


	while
		os.clock() -
			StartTime <
			Timeout
	do

		local Skill =
			FindSkill(SkillName)


		if Skill then

			return Skill

		end


		task.wait(0.03)

	end


	return nil

end


--============================================================
-- GET ACTIVE SKILL
--
-- Q/E is recorded from the currently equipped object.
--============================================================

local function GetCurrentSkill()

	if not Character then
		return nil
	end


	------------------------------------------------------------
	-- First look for an equipped Tool
	------------------------------------------------------------

	for _, Object in ipairs(
		Character:GetChildren()
	) do

		if Object:IsA("Tool") then

			return Object

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


	local Skill =
		GetCurrentSkill()


	if not Skill then

		warn(
			"[Replay]",
			"Q/E pressed but no equipped skill was found"
		)

		return

	end


	local Time =
		os.clock() -
		RecordStartTime


	table.insert(
		CurrentRecording.Inputs,
		{

			Time =
				Time,

			ActionType =
				"Skill",

			Key =
				Key,

			ToolName =
				Skill.Name

		}
	)


	print(
		"[Replay] RECORDED SKILL:",
		Key,
		"->",
		Skill.Name
	)

end


--============================================================
-- FIND SKILL EVENT
--============================================================

local function FindSkillEvent(Skill)

	if not Skill then
		return nil
	end


	------------------------------------------------------------
	-- Direct abilityEvent
	------------------------------------------------------------

	local AbilityEvent =
		Skill:FindFirstChild(
			"abilityEvent"
		)


	if AbilityEvent then

		if AbilityEvent:IsA(
			"RemoteEvent"
		) then

			return AbilityEvent

		end

	end


	------------------------------------------------------------
	-- Direct spellEvent
	------------------------------------------------------------

	local SpellEvent =
		Skill:FindFirstChild(
			"spellEvent"
		)


	if SpellEvent then

		if SpellEvent:IsA(
			"RemoteEvent"
		) then

			return SpellEvent

		end

	end


	------------------------------------------------------------
	-- Search descendants
	------------------------------------------------------------

	for _, Object in ipairs(
		Skill:GetDescendants()
	) do

		if Object:IsA("RemoteEvent") then

			if Object.Name ==
				"abilityEvent" then

				return Object

			end


			if Object.Name ==
				"spellEvent" then

				return Object

			end

		end

	end


	return nil

end


--============================================================
-- REPLAY SKILL
--============================================================

local function ReplaySkill(
	Key,
	SkillName
)

	if not Key then
		return
	end


	if not SkillName then
		return
	end


	print(
		"[Replay] REPLAYING SKILL:",
		Key,
		"->",
		SkillName
	)


	------------------------------------------------------------
	-- EXACTLY FIND IT IN BACKPACK
	------------------------------------------------------------

	local Skill =
		WaitForSkill(
			SkillName,
			3
		)


	if not Skill then

		warn(
			"[Replay] Skill NOT FOUND:",
			SkillName
		)

		return

	end


	print(
		"[Replay] Found:",
		Skill:GetFullName()
	)


	------------------------------------------------------------
	-- FIND EVENT
	------------------------------------------------------------

	local SkillEvent =
		FindSkillEvent(Skill)


	if not SkillEvent then

		warn(
			"[Replay] No abilityEvent/spellEvent:",
			Skill:GetFullName()
		)

		return

	end


	print(
		"[Replay] Event:",
		SkillEvent:GetFullName()
	)


	------------------------------------------------------------
	-- STEP 1
	--
	-- EXACTLY MATCHES:
	--
	-- abilityUsed:FireServer("q", skill)
	------------------------------------------------------------

	local Success1,
		Error1 =
		pcall(
			function()

				AbilityUsed:FireServer(
					Key,
					Skill
				)

			end
		)


	if not Success1 then

		warn(
			"[Replay] abilityUsed ERROR:",
			Error1
		)

		return

	end


	------------------------------------------------------------
	-- STEP 2
	--
	-- EXACTLY MATCHES:
	--
	-- skill.abilityEvent:FireServer()
	--
	-- OR
	--
	-- skill.spellEvent:FireServer()
	------------------------------------------------------------

	local Success2,
		Error2 =
		pcall(
			function()

				SkillEvent:FireServer()

			end
		)


	if not Success2 then

		warn(
			"[Replay] Skill event ERROR:",
			Error2
		)

		return

	end


	print(
		"[Replay] SUCCESS:",
		Key,
		SkillName
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
--============================================================

local function CreatePathTo(
	TargetPosition
)

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
		pcall(
			function()

				Path:ComputeAsync(
					RootPart.Position,
					TargetPosition
				)

			end
		)


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


	CurrentPathIndex = 2


	LastPathTarget =
		TargetPosition


	if not CurrentPath[
		CurrentPathIndex
	] then

		CurrentPathIndex = 1

	end


	return true

end


--============================================================
-- MOVE
--============================================================

local function MoveToReplayPosition(
	TargetPosition
)

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
	-- REACHED
	------------------------------------------------------------

	if Distance <=
		MOVEMENT_REACH_DISTANCE then

		ResetPath()

		ReplayIndex += 1

		return true

	end


	------------------------------------------------------------
	-- STUCK CHECK
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
	-- CREATE INITIAL PATH
	------------------------------------------------------------

	if not CurrentPath then

		if not CreatePathTo(
			TargetPosition
		) then

			Humanoid:MoveTo(
				TargetPosition
			)

			return false

		end

	end


	------------------------------------------------------------
	-- ONLY RECALCULATE IF TARGET MOVED A LOT
	------------------------------------------------------------

	if LastPathTarget then

		local TargetMoved =
			(
				TargetPosition -
				LastPathTarget
			).Magnitude


		if TargetMoved >
			PATH_TARGET_CHANGE then

			CreatePathTo(
				TargetPosition
			)

		end

	end


	------------------------------------------------------------
	-- STUCK
	------------------------------------------------------------

	if StuckTimer >=
		STUCK_TIME then

		ResetPath()

		StuckTimer = 0


		CreatePathTo(
			TargetPosition
		)

	end


	------------------------------------------------------------
	-- FOLLOW WAYPOINT
	------------------------------------------------------------

	if CurrentPath then

		local Waypoint =
			CurrentPath[
				CurrentPathIndex
			]


		if Waypoint then

			local DistanceToWaypoint =
				(
					RootPart.Position -
					Waypoint.Position
				).Magnitude


			if DistanceToWaypoint <=
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


				Humanoid:MoveTo(
					Waypoint.Position
				)


				return false

			end

		end

	end


	------------------------------------------------------------
	-- FALLBACK
	------------------------------------------------------------

	Humanoid:MoveTo(
		TargetPosition
	)


	return false

end


--============================================================
-- FIND NEAREST POINT
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
	-- RESUME TIME
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
	-- FIND INPUT INDEX
	------------------------------------------------------------

	ReplayInputIndex = 1


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
				-- DEATH
				------------------------------------------------

				if Humanoid.Health <= 0 then

					ResumeAfterDeath = true

					Replaying = false


					if ReplayConnection then

						ReplayConnection:Disconnect()

						ReplayConnection = nil

					end


					StatusLabel.Text =
						"Status: Waiting for respawn..."


					return

				end


				------------------------------------------------
				-- TIME
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
				-- MOVEMENT
				------------------------------------------------

				local MovementData =
					Recording.Movement[
						ReplayIndex
					]


				if not MovementData then

					StopReplay()

					return

				end


				if MovementData.Time >
					ElapsedTime then

					return

				end


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


	print(
		"[Replay] RECORDING STARTED:",
		RecordingName
	)


	------------------------------------------------------------
	-- MOVEMENT
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


	print(
		"[Replay] RECORDING SAVED"
	)


	CurrentRecording = nil


	UpdateDropdown()

end


--============================================================
-- Q/E INPUT
--
-- IMPORTANT:
-- NO GameProcessed CHECK HERE.
--
-- This is intentional because your game's skill system
-- may mark Q/E as processed.
--============================================================

UserInputService.InputBegan:Connect(
	function(Input)

		if Input.KeyCode ==
			Enum.KeyCode.Q then

			RecordSkill("q")

		elseif Input.KeyCode ==
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
			UDim2.new(
				1,
				-5,
				0,
				30
			)


		Button.BackgroundColor3 =
			Color3.fromRGB(
				50,
				50,
				50
			)


		Button.BorderSizePixel =
			0


		Button.Text =
			Recording.Name


		Button.TextColor3 =
			Color3.fromRGB(
				255,
				255,
				255
			)


		Button.TextSize =
			13


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
-- DROPDOWN BUTTON
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


				Replaying = false


				if ReplayConnection then

					ReplayConnection:Disconnect()

					ReplayConnection = nil

				end


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


		task.wait(0.75)


		if not RootPart then
			return
		end


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


		if ClosestDistance >
			MAX_RESUME_DISTANCE then

			StatusLabel.Text =
				"Status: Respawn too far from path"

			return

		end


		StatusLabel.Text =
			"Status: Resuming replay..."


		task.wait(0.25)


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


--============================================================
-- LOADED
--============================================================

print(
	"===================================="
)

print(
	"Replay System",
	VERSION,
	"loaded"
)

print(
	"Skill replay: Q / E"
)

print(
	"===================================="
)
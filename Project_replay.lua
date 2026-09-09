--//========================================================
--// REPLAY SYSTEM
--// MOVEMENT + PATHFINDING + ATTACK + MULTIPLE SKILLS
--// NO TELEPORTING
--// SINGLE LOCAL SCRIPT
--//========================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local Player = Players.LocalPlayer

--========================================================
-- SETTINGS
--========================================================

local RECORD_INTERVAL = 0.1

local WAYPOINT_DISTANCE = 3
local PATH_POINT_DISTANCE = 3

local PATH_RECALCULATE_TIME = 0.5
local STUCK_TIME = 1.5

local MAX_RESUME_DISTANCE = 150

--========================================================
-- REMOTES
--========================================================

local Remotes =
	ReplicatedStorage:WaitForChild("remotes")

local WeaponUsed =
	Remotes:WaitForChild("weaponUsed")

local AbilityUsed =
	Remotes:WaitForChild("abilityUsed")

--========================================================
-- CHARACTER
--========================================================

local Character
local Humanoid
local RootPart

local DeathConnection

--========================================================
-- STATES
--========================================================

local Recording = false
local Replaying = false

local CurrentRecording = nil
local SelectedRecording = nil

local Recordings = {}

local RecordStartTime = 0
local LastRecordTime = 0

local RecordConnection = nil
local ReplayConnection = nil

local ResumeAfterDeath = false

--========================================================
-- REPLAY STATE
--========================================================

local ReplayIndex = 1
local ReplayStartTime = 0
local ReplayInputIndex = 1

--========================================================
-- PATHFINDING STATE
--========================================================

local CurrentPath = nil
local CurrentPathIndex = 1

local LastPathTarget = nil
local LastPathCalculation = 0

local LastPosition = nil
local LastMovementCheck = 0
local StuckTimer = 0

--========================================================
-- UI
--========================================================

local ScreenGui
local MainFrame
local StatusLabel
local NameBox
local DropdownButton
local DropdownList

--========================================================
-- STATUS
--========================================================

local function UpdateStatus(Text)

	if StatusLabel then
		StatusLabel.Text = Text
	end

end

--========================================================
-- RESET PATH
--========================================================

local function ResetPath()

	CurrentPath = nil
	CurrentPathIndex = 1

	LastPathTarget = nil
	LastPathCalculation = 0

	StuckTimer = 0

	if RootPart then
		LastPosition = RootPart.Position
	end

	LastMovementCheck = os.clock()

end

--========================================================
-- FIND TOOL
--========================================================

local function FindTool(ToolName)

	if not ToolName then
		return nil
	end

	local Tool

	-- First check equipped tools
	if Character then

		Tool =
			Character:FindFirstChild(
				ToolName
			)

		if Tool and Tool:IsA("Tool") then
			return Tool
		end

	end

	-- Then check Backpack
	local Backpack =
		Player:FindFirstChild(
			"Backpack"
		)

	if Backpack then

		Tool =
			Backpack:FindFirstChild(
				ToolName
			)

		if Tool and Tool:IsA("Tool") then
			return Tool
		end

	end

	return nil

end

--========================================================
-- GET CURRENT EQUIPPED TOOL
--========================================================

local function GetCurrentSkillTool()

	if not Character then
		return nil
	end

	for _, Child in
		ipairs(
			Character:GetChildren()
		)
	do

		if Child:IsA("Tool") then

			return Child

		end

	end

	return nil

end

--========================================================
-- CHARACTER SETUP
--========================================================

local function SetupCharacter(NewCharacter)

	Character = NewCharacter

	Humanoid =
		NewCharacter:WaitForChild(
			"Humanoid"
		)

	RootPart =
		NewCharacter:WaitForChild(
			"HumanoidRootPart"
		)

	ResetPath()

	if DeathConnection then

		DeathConnection:Disconnect()
		DeathConnection = nil

	end

	DeathConnection =
		Humanoid.Died:Connect(
			function()

				if not Replaying then
					return
				end

				print(
					"[Replay] Player died."
				)

				local RecordingToResume =
					SelectedRecording

				Replaying = false

				if ReplayConnection then

					ReplayConnection:Disconnect()
					ReplayConnection = nil

				end

				ResetPath()

				UpdateStatus(
					"Waiting for respawn..."
				)

				if not RecordingToResume then
					return
				end

				ResumeAfterDeath = true

				local NewChar =
					Player.CharacterAdded:Wait()

				Character = NewChar

				Humanoid =
					NewChar:WaitForChild(
						"Humanoid"
					)

				RootPart =
					NewChar:WaitForChild(
						"HumanoidRootPart"
					)

				task.wait(0.75)

				if not ResumeAfterDeath then
					return
				end

				ResumeAfterDeath = false

				--================================================
				-- FIND CLOSEST RECORDED POINT
				--================================================

				local ClosestIndex = 1
				local ClosestDistance = math.huge

				for Index, Point in
					ipairs(
						RecordingToResume.Movement
					)
				do

					local Distance =
						(
							RootPart.Position
							-
							Point.Position
						).Magnitude

					if Distance < ClosestDistance then

						ClosestDistance =
							Distance

						ClosestIndex =
							Index

					end

				end

				print(
					"[Replay] Closest path point:",
					ClosestIndex
				)

				print(
					"[Replay] Distance:",
					math.floor(
						ClosestDistance
					)
				)

				--================================================
				-- RESUME REPLAY
				--================================================

				if
					ClosestDistance
					<=
					MAX_RESUME_DISTANCE
				then

					StartReplay(
						RecordingToResume,
						ClosestIndex
					)

				else

					UpdateStatus(
						"Respawn too far from path"
					)

				end

			end
		)

end

--========================================================
-- INITIAL CHARACTER
--========================================================

if Player.Character then

	task.spawn(
		function()

			SetupCharacter(
				Player.Character
			)

		end
	)

end

Player.CharacterAdded:Connect(
	function(NewCharacter)

		SetupCharacter(
			NewCharacter
		)

	end
)

--========================================================
-- RECORD INPUT
--========================================================

local function RecordInput(
	Input,
	State
)

	if not Recording then
		return
	end

	if not CurrentRecording then
		return
	end

	local IsUseful = false

	--====================================================
	-- MOUSE
	--====================================================

	if
		Input.UserInputType
		==
		Enum.UserInputType.MouseButton1
	then

		IsUseful = true

	elseif
		Input.UserInputType
		==
		Enum.UserInputType.MouseButton2
	then

		IsUseful = true

	end

	--====================================================
	-- KEYBOARD
	--====================================================

	if
		Input.KeyCode == Enum.KeyCode.W
		or Input.KeyCode == Enum.KeyCode.A
		or Input.KeyCode == Enum.KeyCode.S
		or Input.KeyCode == Enum.KeyCode.D
		or Input.KeyCode == Enum.KeyCode.Q
		or Input.KeyCode == Enum.KeyCode.E
		or Input.KeyCode == Enum.KeyCode.Space
		or Input.KeyCode == Enum.KeyCode.LeftShift
		or Input.KeyCode == Enum.KeyCode.RightShift
		or Input.KeyCode == Enum.KeyCode.LeftControl
		or Input.KeyCode == Enum.KeyCode.RightControl
	then

		IsUseful = true

	end

	if not IsUseful then
		return
	end

	--====================================================
	-- GET EQUIPPED TOOL
	--====================================================

	local ToolName = nil

	local Tool =
		GetCurrentSkillTool()

	if Tool then

		ToolName =
			Tool.Name

	end

	--====================================================
	-- SAVE INPUT
	--====================================================

	table.insert(
		CurrentRecording.Inputs,
		{

			Time =
				os.clock()
				-
				RecordStartTime,

			KeyCode =
				Input.KeyCode,

			UserInputType =
				Input.UserInputType,

			State =
				State,

			-- This is the important part.
			-- We save which tool was equipped.
			ToolName =
				ToolName

		}
	)

	print(
		"[Replay Record]",
		Input.KeyCode,
		State,
		"Tool:",
		ToolName
	)

end

--========================================================
-- INPUT LISTENERS
--========================================================

UserInputService.InputBegan:Connect(
	function(Input)

		RecordInput(
			Input,
			"Began"
		)

	end
)

UserInputService.InputEnded:Connect(
	function(Input)

		RecordInput(
			Input,
			"Ended"
		)

	end
)

--========================================================
-- RECORD MOVEMENT
--========================================================

local function RecordSnapshot()

	if not Recording then
		return
	end

	if not CurrentRecording then
		return
	end

	if not RootPart then
		return
	end

	table.insert(
		CurrentRecording.Movement,
		{

			Time =
				os.clock()
				-
				RecordStartTime,

			Position =
				RootPart.Position,

			CFrame =
				RootPart.CFrame

		}
	)

end

--========================================================
-- START RECORDING
--========================================================

local function StartRecording()

	if Recording then
		return
	end

	if Replaying then

		UpdateStatus(
			"Stop replay first"
		)

		return

	end

	if not RootPart then

		UpdateStatus(
			"Character not ready"
		)

		return

	end

	Recording = true

	RecordStartTime =
		os.clock()

	LastRecordTime = 0

	CurrentRecording =
		{

			Name =
				"Recording "
				..
				(#Recordings + 1),

			Movement = {},

			Inputs = {},

			Duration = 0

		}

	RecordSnapshot()

	RecordConnection =
		RunService.Heartbeat:Connect(
			function()

				if not Recording then
					return
				end

				local Now =
					os.clock()

				if
					Now
					-
					LastRecordTime
					>=
					RECORD_INTERVAL
				then

					LastRecordTime =
						Now

					RecordSnapshot()

				end

			end
		)

	UpdateStatus(
		"Recording..."
	)

	print(
		"[Replay] Recording started."
	)

end

--========================================================
-- STOP RECORDING
--========================================================

local function StopRecording()

	if not Recording then
		return
	end

	Recording = false

	if RecordConnection then

		RecordConnection:Disconnect()
		RecordConnection = nil

	end

	if not CurrentRecording then
		return
	end

	if RootPart then

		table.insert(
			CurrentRecording.Movement,
			{

				Time =
					os.clock()
					-
					RecordStartTime,

				Position =
					RootPart.Position,

				CFrame =
					RootPart.CFrame

			}
		)

	end

	CurrentRecording.Duration =
		os.clock()
		-
		RecordStartTime

	local Name =
		NameBox.Text

	if Name == "" then

		Name =
			"Recording "
			..
			(#Recordings + 1)

	end

	CurrentRecording.Name =
		Name

	table.insert(
		Recordings,
		CurrentRecording
	)

	SelectedRecording =
		CurrentRecording

	UpdateDropdown()

	UpdateStatus(
		"Saved: "
		..
		CurrentRecording.Name
	)

	print(
		"[Replay] Saved:",
		CurrentRecording.Name
	)

	print(
		"[Replay] Movement points:",
		#CurrentRecording.Movement
	)

	print(
		"[Replay] Inputs:",
		#CurrentRecording.Inputs
	)

	CurrentRecording = nil

end

--========================================================
-- ATTACK
--========================================================

local function DoAttack()

	print(
		"[Replay] ATTACK"
	)

	-- weaponUsed
	pcall(
		function()

			WeaponUsed:FireServer()

		end
	)

	--====================================================
	-- SPIKED CLUB
	--====================================================

	local SpikedClub =
		FindTool(
			"Spiked Club"
		)

	if not SpikedClub then

		warn(
			"[Replay] Spiked Club not found."
		)

		return

	end

	local Swing =
		SpikedClub:FindFirstChild(
			"swing"
		)

	if Swing then

		pcall(
			function()

				Swing:FireServer()

			end
		)

		print(
			"[Replay] Spiked Club swing fired."
		)

	else

		warn(
			"[Replay] Spiked Club swing RemoteEvent not found."
		)

	end

end

--========================================================
-- USE ABILITY
--========================================================

local function DoAbility(
	Key,
	ToolName
)

	--====================================================
	-- FIND RECORDED TOOL
	--====================================================

	local SkillTool = nil

	if ToolName then

		SkillTool =
			FindTool(
				ToolName
			)

	end

	--====================================================
	-- FALLBACK TO CURRENT EQUIPPED TOOL
	--====================================================

	if not SkillTool then

		SkillTool =
			GetCurrentSkillTool()

	end

	if not SkillTool then

		warn(
			"[Replay] No skill tool found for:",
			Key,
			"Recorded tool:",
			ToolName
		)

		return

	end

	print(
		"[Replay] Using skill:",
		string.upper(Key),
		"Tool:",
		SkillTool.Name
	)

	--====================================================
	-- ABILITY USED
	--====================================================

	local AbilitySuccess =
		pcall(
			function()

				AbilityUsed:FireServer(
					Key,
					SkillTool
				)

			end
		)

	if not AbilitySuccess then

		warn(
			"[Replay] abilityUsed failed."
		)

	end

	--====================================================
	-- FIND SPELL EVENT
	--====================================================

	local SpellEvent =
		SkillTool:FindFirstChild(
			"spellEvent"
		)

	if SpellEvent then

		pcall(
			function()

				SpellEvent:FireServer()

			end
		)

		print(
			"[Replay] Fired spellEvent for:",
			SkillTool.Name
		)

	else

		warn(
			"[Replay] Tool does not contain spellEvent:",
			SkillTool.Name
		)

	end

end

--========================================================
-- EXECUTE RECORDED INPUT
--========================================================

local function ExecuteRecordedInput(
	InputData
)

	if InputData.State ~= "Began" then
		return
	end

	--====================================================
	-- LEFT CLICK
	--====================================================

	if
		InputData.UserInputType
		==
		Enum.UserInputType.MouseButton1
	then

		DoAttack()

		return

	end

	--====================================================
	-- Q
	--====================================================

	if
		InputData.KeyCode
		==
		Enum.KeyCode.Q
	then

		DoAbility(
			"q",
			InputData.ToolName
		)

		return

	end

	--====================================================
	-- E
	--====================================================

	if
		InputData.KeyCode
		==
		Enum.KeyCode.E
	then

		DoAbility(
			"e",
			InputData.ToolName
		)

		return

	end

	--====================================================
	-- SPACE
	--====================================================

	if
		InputData.KeyCode
		==
		Enum.KeyCode.Space
	then

		if Humanoid then

			Humanoid.Jump =
				true

		end

	end

end

--========================================================
-- CREATE PATH
--========================================================

local function CreatePathTo(
	TargetPosition
)

	if not RootPart then
		return false
	end

	if not Humanoid then
		return false
	end

	-- Prevent excessive path calculations
	if
		os.clock()
		-
		LastPathCalculation
		<
		PATH_RECALCULATE_TIME
	then

		return false

	end

	LastPathCalculation =
		os.clock()

	local Path =
		PathfindingService:CreatePath(
			{

				AgentRadius = 2,

				AgentHeight = 5,

				AgentCanJump = true,

				AgentCanClimb = true,

				WaypointSpacing = 3

			}
		)

	local Success, Error =
		pcall(
			function()

				Path:ComputeAsync(
					RootPart.Position,
					TargetPosition
				)

			end
		)

	if not Success then

		warn(
			"[Replay] Path calculation error:",
			Error
		)

		return false

	end

	if
		Path.Status
		~=
		Enum.PathStatus.Success
	then

		warn(
			"[Replay] No valid path found."
		)

		return false

	end

	local Waypoints =
		Path:GetWaypoints()

	if #Waypoints < 2 then

		return false

	end

	CurrentPath =
		Waypoints

	CurrentPathIndex =
		2

	LastPathTarget =
		TargetPosition

	print(
		"[Replay] Generated path with",
		#Waypoints,
		"waypoints."
	)

	return true

end

--========================================================
-- MOVE TO RECORDED POINT
--========================================================

local function MoveToRecordedPoint(
	TargetPosition
)

	if not Humanoid then
		return false
	end

	if not RootPart then
		return false
	end

	--====================================================
	-- DISTANCE TO TARGET
	--====================================================

	local Difference =
		TargetPosition
		-
		RootPart.Position

	local Horizontal =
		Vector3.new(
			Difference.X,
			0,
			Difference.Z
		)

	local Distance =
		Horizontal.Magnitude

	--====================================================
	-- TARGET REACHED
	--====================================================

	if Distance <= WAYPOINT_DISTANCE then

		ResetPath()

		return true

	end

	--====================================================
	-- STUCK CHECK
	--====================================================

	if LastPosition then

		local Movement =
			(
				RootPart.Position
				-
				LastPosition
			).Magnitude

		if
			os.clock()
			-
			LastMovementCheck
			>=
			0.25
		then

			if Movement < 0.15 then

				StuckTimer +=
					os.clock()
					-
					LastMovementCheck

			else

				StuckTimer = 0

			end

			LastPosition =
				RootPart.Position

			LastMovementCheck =
				os.clock()

		end

	end

	--====================================================
	-- PATH NEEDED?
	--====================================================

	local NeedPath = false

	if not CurrentPath then

		NeedPath = true

	elseif not LastPathTarget then

		NeedPath = true

	elseif
		(
			LastPathTarget
			-
			TargetPosition
		).Magnitude
		>
		5
	then

		NeedPath = true

	end

	if StuckTimer >= STUCK_TIME then

		print(
			"[Replay] Stuck. Recalculating path."
		)

		CurrentPath = nil
		CurrentPathIndex = 1

		NeedPath = true

		StuckTimer = 0

	end

	--====================================================
	-- CREATE PATH
	--====================================================

	if NeedPath then

		CreatePathTo(
			TargetPosition
		)

	end

	--====================================================
	-- FOLLOW PATH
	--====================================================

	if
		CurrentPath
		and
		CurrentPathIndex
		<=
		#CurrentPath
	then

		local Waypoint =
			CurrentPath[
				CurrentPathIndex
			]

		-- Jump if necessary
		if
			Waypoint.Action
			==
			Enum.PathWaypointAction.Jump
		then

			Humanoid.Jump =
				true

		end

		local WaypointDifference =
			Waypoint.Position
			-
			RootPart.Position

		local WaypointHorizontal =
			Vector3.new(
				WaypointDifference.X,
				0,
				WaypointDifference.Z
			)

		if
			WaypointHorizontal.Magnitude
			<=
			PATH_POINT_DISTANCE
		then

			CurrentPathIndex += 1

		else

			Humanoid:MoveTo(
				Waypoint.Position
			)

		end

	else

		--================================================
		-- FALLBACK TO NORMAL MOVEMENT
		--================================================

		Humanoid:MoveTo(
			Vector3.new(

				TargetPosition.X,

				RootPart.Position.Y,

				TargetPosition.Z

			)
		)

	end

	return false

end

--========================================================
-- START REPLAY
--========================================================

function StartReplay(
	RecordingToPlay,
	StartIndex
)

	if not RecordingToPlay then
		return
	end

	if
		#RecordingToPlay.Movement
		<
		2
	then

		UpdateStatus(
			"Recording too short"
		)

		return

	end

	if not Humanoid or not RootPart then

		UpdateStatus(
			"Character not ready"
		)

		return

	end

	if ReplayConnection then

		ReplayConnection:Disconnect()
		ReplayConnection = nil

	end

	Replaying = true

	SelectedRecording =
		RecordingToPlay

	ReplayIndex =
		StartIndex or 1

	ResetPath()

	local StartPoint =
		RecordingToPlay.Movement[
			ReplayIndex
		]

	if not StartPoint then

		Replaying = false

		return

	end

	--====================================================
	-- NO TELEPORT
	--====================================================

	ReplayStartTime =
		os.clock()
		-
		StartPoint.Time

	--====================================================
	-- FIND INPUT START
	--====================================================

	ReplayInputIndex = 1

	for Index, InputData in
		ipairs(
			RecordingToPlay.Inputs
		)
	do

		if
			InputData.Time
			>=
			StartPoint.Time
		then

			ReplayInputIndex =
				Index

			break

		end

	end

	--====================================================
	-- REPLAY LOOP
	--====================================================

	ReplayConnection =
		RunService.Heartbeat:Connect(
			function()

				if not Replaying then
					return
				end

				if not Humanoid then
					return
				end

				if not RootPart then
					return
				end

				--================================================
				-- REPLAY TIME
				--================================================

				local ReplayTime =
					os.clock()
					-
					ReplayStartTime

				--================================================
				-- REPLAY INPUTS
				--================================================

				while
					ReplayInputIndex
					<=
					#RecordingToPlay.Inputs
				do

					local InputData =
						RecordingToPlay.Inputs[
							ReplayInputIndex
						]

					if
						InputData.Time
						<=
						ReplayTime
					then

						ExecuteRecordedInput(
							InputData
						)

						ReplayInputIndex += 1

					else

						break

					end

				end

				--================================================
				-- MOVEMENT
				--================================================

				if
					ReplayIndex
					>
					#RecordingToPlay.Movement
				then

					StopReplay()

					return

				end

				local Point =
					RecordingToPlay.Movement[
						ReplayIndex
					]

				if not Point then

					StopReplay()

					return

				end

				local Reached =
					MoveToRecordedPoint(
						Point.Position
					)

				if Reached then

					ReplayIndex += 1

				end

			end
		)

	UpdateStatus(
		"Replaying: "
		..
		RecordingToPlay.Name
	)

	print(
		"[Replay] Started:"
		,
		RecordingToPlay.Name
	)

end

--========================================================
-- STOP REPLAY
--========================================================

function StopReplay()

	Replaying = false
	ResumeAfterDeath = false

	if ReplayConnection then

		ReplayConnection:Disconnect()
		ReplayConnection = nil

	end

	ResetPath()

	if Humanoid and RootPart then

		Humanoid:MoveTo(
			RootPart.Position
		)

	end

	UpdateStatus(
		"Replay stopped"
	)

	print(
		"[Replay] Stopped."
	)

end

--========================================================
-- CREATE UI
--========================================================

ScreenGui =
	Instance.new("ScreenGui")

ScreenGui.Name =
	"ReplayUI"

ScreenGui.ResetOnSpawn =
	false

ScreenGui.Parent =
	Player:WaitForChild(
		"PlayerGui"
	)

--========================================================
-- MAIN FRAME
--========================================================

MainFrame =
	Instance.new("Frame")

MainFrame.Size =
	UDim2.new(
		0,
		300,
		0,
		310
	)

MainFrame.Position =
	UDim2.new(
		0,
		20,
		0.5,
		-155
	)

MainFrame.BackgroundColor3 =
	Color3.fromRGB(
		25,
		25,
		25
	)

MainFrame.BorderSizePixel =
	0

MainFrame.Parent =
	ScreenGui

local MainCorner =
	Instance.new("UICorner")

MainCorner.CornerRadius =
	UDim.new(
		0,
		8
	)

MainCorner.Parent =
	MainFrame

--========================================================
-- HEADER
--========================================================

local Header =
	Instance.new("Frame")

Header.Size =
	UDim2.new(
		1,
		0,
		0,
		40
	)

Header.BackgroundColor3 =
	Color3.fromRGB(
		35,
		35,
		35
	)

Header.BorderSizePixel =
	0

Header.Parent =
	MainFrame

local Title =
	Instance.new("TextLabel")

Title.Size =
	UDim2.new(
		1,
		-50,
		1,
		0
	)

Title.Position =
	UDim2.new(
		0,
		10,
		0,
		0
	)

Title.BackgroundTransparency =
	1

Title.Text =
	"Replay System"

Title.TextColor3 =
	Color3.new(
		1,
		1,
		1
	)

Title.TextSize =
	17

Title.Font =
	Enum.Font.GothamBold

Title.TextXAlignment =
	Enum.TextXAlignment.Left

Title.Parent =
	Header

--========================================================
-- MINIMIZE
--========================================================

local Minimize =
	Instance.new("TextButton")

Minimize.Size =
	UDim2.new(
		0,
		35,
		0,
		30
	)

Minimize.Position =
	UDim2.new(
		1,
		-40,
		0,
		5
	)

Minimize.Text =
	"-"

Minimize.TextSize =
	22

Minimize.BackgroundTransparency =
	1

Minimize.TextColor3 =
	Color3.new(
		1,
		1,
		1
	)

Minimize.Parent =
	Header

--========================================================
-- STATUS
--========================================================

StatusLabel =
	Instance.new("TextLabel")

StatusLabel.Size =
	UDim2.new(
		1,
		-20,
		0,
		30
	)

StatusLabel.Position =
	UDim2.new(
		0,
		10,
		0,
		48
	)

StatusLabel.BackgroundTransparency =
	1

StatusLabel.Text =
	"Ready"

StatusLabel.TextColor3 =
	Color3.fromRGB(
		200,
		200,
		200
	)

StatusLabel.TextSize =
	14

StatusLabel.Font =
	Enum.Font.Gotham

StatusLabel.Parent =
	MainFrame

--========================================================
-- NAME BOX
--========================================================

NameBox =
	Instance.new("TextBox")

NameBox.Size =
	UDim2.new(
		1,
		-20,
		0,
		35
	)

NameBox.Position =
	UDim2.new(
		0,
		10,
		0,
		82
	)

NameBox.PlaceholderText =
	"Recording name"

NameBox.Text =
	""

NameBox.TextSize =
	14

NameBox.Font =
	Enum.Font.Gotham

NameBox.BackgroundColor3 =
	Color3.fromRGB(
		40,
		40,
		40
	)

NameBox.TextColor3 =
	Color3.new(
		1,
		1,
		1
	)

NameBox.Parent =
	MainFrame

local NameCorner =
	Instance.new("UICorner")

NameCorner.CornerRadius =
	UDim.new(
		0,
		6
	)

NameCorner.Parent =
	NameBox

--========================================================
-- BUTTON CREATOR
--========================================================

local function CreateButton(
	Text,
	Position,
	Size,
	Background
)

	local Button =
		Instance.new("TextButton")

	Button.Size =
		Size

	Button.Position =
		Position

	Button.Text =
		Text

	Button.TextSize =
		14

	Button.Font =
		Enum.Font.GothamBold

	Button.BackgroundColor3 =
		Background

	Button.TextColor3 =
		Color3.new(
			1,
			1,
			1
		)

	Button.Parent =
		MainFrame

	local ButtonCorner =
		Instance.new("UICorner")

	ButtonCorner.CornerRadius =
		UDim.new(
			0,
			6
		)

	ButtonCorner.Parent =
		Button

	return Button

end

--========================================================
-- BUTTONS
--========================================================

local RecordButton =
	CreateButton(
		"Record",
		UDim2.new(
			0,
			10,
			0,
			125
		),
		UDim2.new(
			0.31,
			-5,
			0,
			38
		),
		Color3.fromRGB(
			60,
			120,
			60
		)
	)

local StopButton =
	CreateButton(
		"Stop",
		UDim2.new(
			0.345,
			0,
			0,
			125
		),
		UDim2.new(
			0.31,
			0,
			0,
			38
		),
		Color3.fromRGB(
			130,
			60,
			60
		)
	)

local ReplayButton =
	CreateButton(
		"Replay",
		UDim2.new(
			0.69,
			0,
			0,
			125
		),
		UDim2.new(
			0.31,
			0,
			0,
			38
		),
		Color3.fromRGB(
			60,
			90,
			150
		)
	)

--========================================================
-- DROPDOWN
--========================================================

DropdownButton =
	Instance.new("TextButton")

DropdownButton.Size =
	UDim2.new(
		1,
		-20,
		0,
		35
	)

DropdownButton.Position =
	UDim2.new(
		0,
		10,
		0,
		175
	)

DropdownButton.Text =
	"No recording selected"

DropdownButton.TextSize =
	14

DropdownButton.Font =
	Enum.Font.Gotham

DropdownButton.BackgroundColor3 =
	Color3.fromRGB(
		40,
		40,
		40
	)

DropdownButton.TextColor3 =
	Color3.new(
		1,
		1,
		1
	)

DropdownButton.Parent =
	MainFrame

local DropdownCorner =
	Instance.new("UICorner")

DropdownCorner.CornerRadius =
	UDim.new(
		0,
		6
	)

DropdownCorner.Parent =
	DropdownButton

--========================================================
-- DROPDOWN LIST
--========================================================

DropdownList =
	Instance.new("ScrollingFrame")

DropdownList.Size =
	UDim2.new(
		1,
		-20,
		0,
		85
	)

DropdownList.Position =
	UDim2.new(
		0,
		10,
		0,
		215
	)

DropdownList.BackgroundColor3 =
	Color3.fromRGB(
		30,
		30,
		30
	)

DropdownList.BorderSizePixel =
	0

DropdownList.Visible =
	false

DropdownList.ScrollBarThickness =
	4

DropdownList.ZIndex =
	10

DropdownList.Parent =
	MainFrame

--========================================================
-- UPDATE DROPDOWN
--========================================================

function UpdateDropdown()

	for _, Child in
		ipairs(
			DropdownList:GetChildren()
		)
	do

		if Child:IsA("TextButton") then

			Child:Destroy()

		end

	end

	local Y = 0

	for _, Recording in
		ipairs(
			Recordings
		)
	do

		local Button =
			Instance.new("TextButton")

		Button.Size =
			UDim2.new(
				1,
				-5,
				0,
				30
			)

		Button.Position =
			UDim2.new(
				0,
				0,
				0,
				Y
			)

		Button.Text =
			Recording.Name

		Button.TextSize =
			13

		Button.Font =
			Enum.Font.Gotham

		Button.TextColor3 =
			Color3.new(
				1,
				1,
				1
			)

		Button.BackgroundColor3 =
			Color3.fromRGB(
				45,
				45,
				45
			)

		Button.ZIndex =
			11

		Button.Parent =
			DropdownList

		Button.MouseButton1Click:Connect(
			function()

				SelectedRecording =
					Recording

				DropdownButton.Text =
					Recording.Name

				DropdownList.Visible =
					false

				UpdateStatus(
					"Selected: "
					..
					Recording.Name
				)

			end
		)

		Y += 32

	end

	DropdownList.CanvasSize =
		UDim2.new(
			0,
			0,
			0,
			Y
		)

end

--========================================================
-- BUTTON EVENTS
--========================================================

RecordButton.MouseButton1Click:Connect(
	function()

		StartRecording()

	end
)

StopButton.MouseButton1Click:Connect(
	function()

		if Recording then

			StopRecording()

		elseif Replaying then

			StopReplay()

		end

	end
)

ReplayButton.MouseButton1Click:Connect(
	function()

		if Replaying then

			StopReplay()

			return

		end

		if not SelectedRecording then

			UpdateStatus(
				"Select a recording first"
			)

			return

		end

		DropdownList.Visible =
			false

		StartReplay(
			SelectedRecording,
			1
		)

	end
)

DropdownButton.MouseButton1Click:Connect(
	function()

		DropdownList.Visible =
			not DropdownList.Visible

	end
)

--========================================================
-- MINIMIZE
--========================================================

local Minimized = false

Minimize.MouseButton1Click:Connect(
	function()

		Minimized =
			not Minimized

		if Minimized then

			MainFrame.Size =
				UDim2.new(
					0,
					300,
					0,
					40
				)

			Minimize.Text =
				"+"

		else

			MainFrame.Size =
				UDim2.new(
					0,
					300,
					0,
					310
				)

			Minimize.Text =
				"-"

		end

	end
)

--========================================================
-- DRAGGING
--========================================================

local Dragging = false
local DragStart
local StartPosition

Header.InputBegan:Connect(
	function(Input)

		if
			Input.UserInputType
			==
			Enum.UserInputType.MouseButton1
		then

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

		if
			Input.UserInputType
			==
			Enum.UserInputType.MouseButton1
		then

			Dragging = false

		end

	end
)

UserInputService.InputChanged:Connect(
	function(Input)

		if not Dragging then
			return
		end

		if
			Input.UserInputType
			~=
			Enum.UserInputType.MouseMovement
		then

			return

		end

		local Delta =
			Input.Position
			-
			DragStart

		MainFrame.Position =
			UDim2.new(

				StartPosition.X.Scale,

				StartPosition.X.Offset
					+
					Delta.X,

				StartPosition.Y.Scale,

				StartPosition.Y.Offset
					+
					Delta.Y

			)

	end
)

--========================================================
-- LOADED
--========================================================

print("==========================================")
print("         REPLAY SYSTEM LOADED")
print("==========================================")
print("Movement       : Humanoid:MoveTo")
print("Pathfinding    : ENABLED")
print("Teleporting    : NONE")
print("Attack         : weaponUsed + Spiked Club")
print("Q/E            : Dynamic equipped skill")
print("Skill Tool     : Recorded")
print("Death Resume   : ENABLED")
print("==========================================")
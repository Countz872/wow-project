--==================================================
-- REPLAY SYSTEM
-- Movement + Pathfinding + Death Resume + Skills
--==================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local Player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("remotes")

local AbilityUsed = Remotes:WaitForChild("abilityUsed")


--==================================================
-- CHARACTER
--==================================================

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


--==================================================
-- SETTINGS
--==================================================

local RECORD_INTERVAL = 0.1

local PATH_POINT_DISTANCE = 3

local PATH_RECALCULATE_TIME = 0.5

local STUCK_TIME = 1.5

local MAX_RESUME_DISTANCE = 150


--==================================================
-- STATES
--==================================================

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


--==================================================
-- REPLAY STATE
--==================================================

local ReplayIndex = 1
local ReplayStartTime = 0
local ReplayInputIndex = 1


--==================================================
-- PATHFINDING STATE
--==================================================

local CurrentPath = nil
local CurrentPathIndex = 1

local LastPathTarget = nil
local LastPathCalculation = 0

local LastPosition = nil
local LastMovementCheck = 0

local StuckTimer = 0


--==================================================
-- UI
--==================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ReplayUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = Player:WaitForChild("PlayerGui")


local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 300, 0, 310)
MainFrame.Position = UDim2.new(0, 20, 0.5, -155)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui


local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = MainFrame


--==================================================
-- HEADER
--==================================================

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 40)
Header.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Header.BorderSizePixel = 0
Header.Parent = MainFrame


local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 8)
HeaderCorner.Parent = Header


local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -45, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Replay System"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header


local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Size = UDim2.new(0, 35, 0, 30)
MinimizeButton.Position = UDim2.new(1, -40, 0, 5)
MinimizeButton.BackgroundTransparency = 1
MinimizeButton.Text = "-"
MinimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeButton.TextSize = 22
MinimizeButton.Font = Enum.Font.GothamBold
MinimizeButton.Parent = Header


--==================================================
-- STATUS
--==================================================

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 25)
StatusLabel.Position = UDim2.new(0, 10, 0, 48)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Idle"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.TextSize = 14
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = MainFrame


--==================================================
-- NAME BOX
--==================================================

local NameBox = Instance.new("TextBox")
NameBox.Size = UDim2.new(1, -20, 0, 35)
NameBox.Position = UDim2.new(0, 10, 0, 78)
NameBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
NameBox.BorderSizePixel = 0
NameBox.PlaceholderText = "Recording name..."
NameBox.Text = ""
NameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
NameBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
NameBox.TextSize = 14
NameBox.Font = Enum.Font.Gotham
NameBox.Parent = MainFrame


local NameCorner = Instance.new("UICorner")
NameCorner.CornerRadius = UDim.new(0, 6)
NameCorner.Parent = NameBox


--==================================================
-- RECORD BUTTON
--==================================================

local RecordButton = Instance.new("TextButton")
RecordButton.Size = UDim2.new(0.48, -5, 0, 35)
RecordButton.Position = UDim2.new(0, 10, 0, 123)
RecordButton.BackgroundColor3 = Color3.fromRGB(60, 120, 70)
RecordButton.BorderSizePixel = 0
RecordButton.Text = "Record"
RecordButton.TextColor3 = Color3.fromRGB(255, 255, 255)
RecordButton.TextSize = 14
RecordButton.Font = Enum.Font.GothamBold
RecordButton.Parent = MainFrame


local RecordCorner = Instance.new("UICorner")
RecordCorner.CornerRadius = UDim.new(0, 6)
RecordCorner.Parent = RecordButton


--==================================================
-- STOP BUTTON
--==================================================

local StopButton = Instance.new("TextButton")
StopButton.Size = UDim2.new(0.48, -5, 0, 35)
StopButton.Position = UDim2.new(0.52, 0, 0, 123)
StopButton.BackgroundColor3 = Color3.fromRGB(130, 60, 60)
StopButton.BorderSizePixel = 0
StopButton.Text = "Stop"
StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
StopButton.TextSize = 14
StopButton.Font = Enum.Font.GothamBold
StopButton.Parent = MainFrame


local StopCorner = Instance.new("UICorner")
StopCorner.CornerRadius = UDim.new(0, 6)
StopCorner.Parent = StopButton


--==================================================
-- REPLAY BUTTON
--==================================================

local ReplayButton = Instance.new("TextButton")
ReplayButton.Size = UDim2.new(1, -20, 0, 35)
ReplayButton.Position = UDim2.new(0, 10, 0, 168)
ReplayButton.BackgroundColor3 = Color3.fromRGB(65, 90, 150)
ReplayButton.BorderSizePixel = 0
ReplayButton.Text = "Replay Selected"
ReplayButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ReplayButton.TextSize = 14
ReplayButton.Font = Enum.Font.GothamBold
ReplayButton.Parent = MainFrame


local ReplayCorner = Instance.new("UICorner")
ReplayCorner.CornerRadius = UDim.new(0, 6)
ReplayCorner.Parent = ReplayButton


--==================================================
-- DROPDOWN
--==================================================

local DropdownButton = Instance.new("TextButton")
DropdownButton.Size = UDim2.new(1, -20, 0, 35)
DropdownButton.Position = UDim2.new(0, 10, 0, 213)
DropdownButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
DropdownButton.BorderSizePixel = 0
DropdownButton.Text = "Select Recording ▼"
DropdownButton.TextColor3 = Color3.fromRGB(255, 255, 255)
DropdownButton.TextSize = 14
DropdownButton.Font = Enum.Font.Gotham
DropdownButton.Parent = MainFrame


local DropdownCorner = Instance.new("UICorner")
DropdownCorner.CornerRadius = UDim.new(0, 6)
DropdownCorner.Parent = DropdownButton


local DropdownFrame = Instance.new("ScrollingFrame")
DropdownFrame.Name = "Dropdown"
DropdownFrame.Size = UDim2.new(1, -20, 0, 75)
DropdownFrame.Position = UDim2.new(0, 10, 0, 253)
DropdownFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
DropdownFrame.BorderSizePixel = 0
DropdownFrame.ScrollBarThickness = 4
DropdownFrame.Visible = false
DropdownFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
DropdownFrame.Parent = MainFrame


local DropdownLayout = Instance.new("UIListLayout")
DropdownLayout.Padding = UDim.new(0, 2)
DropdownLayout.Parent = DropdownFrame


--==================================================
-- MINIMIZE
--==================================================

local Minimized = false

MinimizeButton.MouseButton1Click:Connect(function()

	Minimized = not Minimized

	if Minimized then

		MainFrame.Size = UDim2.new(0, 300, 0, 40)

		for _, Child in ipairs(MainFrame:GetChildren()) do
			if Child ~= Header then
				Child.Visible = false
			end
		end

		MinimizeButton.Text = "+"

	else

		MainFrame.Size = UDim2.new(0, 300, 0, 310)

		for _, Child in ipairs(MainFrame:GetChildren()) do
			Child.Visible = true
		end

		MinimizeButton.Text = "-"

	end

end)


--==================================================
-- DRAGGING
--==================================================

local Dragging = false
local DragStart
local StartPosition


Header.InputBegan:Connect(function(Input)

	if Input.UserInputType == Enum.UserInputType.MouseButton1 then

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

	local Delta = Input.Position - DragStart

	MainFrame.Position = UDim2.new(
		StartPosition.X.Scale,
		StartPosition.X.Offset + Delta.X,
		StartPosition.Y.Scale,
		StartPosition.Y.Offset + Delta.Y
	)

end)


--==================================================
-- FIND SKILL TOOL
--==================================================

local function FindSkillTool(ToolName)

	if not ToolName then
		return nil
	end


	-- Check character

	if Character then

		local Tool = Character:FindFirstChild(ToolName)

		if Tool and Tool:IsA("Tool") then
			return Tool
		end

	end


	-- Check backpack

	local Backpack = Player:FindFirstChild("Backpack")

	if Backpack then

		local Tool = Backpack:FindFirstChild(ToolName)

		if Tool and Tool:IsA("Tool") then
			return Tool
		end

	end


	return nil

end


--==================================================
-- GET CURRENT SKILL TOOL
--==================================================

local function GetCurrentSkillTool()

	if not Character then
		return nil
	end


	for _, Child in ipairs(Character:GetChildren()) do

		if Child:IsA("Tool") then
			return Child
		end

	end


	return nil

end


--==================================================
-- RECORD SKILL
--==================================================

local function RecordSkill(Key)

	if not Recording then
		return
	end

	if not CurrentRecording then
		return
	end


	local Tool = GetCurrentSkillTool()

	if not Tool then
		return
	end


	-- Only Q/E

	if Key ~= "q" and Key ~= "e" then
		return
	end


	table.insert(CurrentRecording.Inputs, {

		Time = os.clock() - RecordStartTime,

		ActionType = "Skill",

		Key = Key,

		ToolName = Tool.Name

	})

end


--==================================================
-- REPLAY SKILL
--==================================================

local function ReplaySkill(Key, ToolName)

	if not Key then
		return
	end

	if not ToolName then
		return
	end


	local SkillTool = FindSkillTool(ToolName)


	-- The skill might temporarily be moving
	-- between Backpack and Character.

	if not SkillTool then

		local Timeout = os.clock() + 2

		repeat

			task.wait(0.05)

			SkillTool = FindSkillTool(ToolName)

		until SkillTool or os.clock() >= Timeout

	end


	if not SkillTool then

		warn(
			"[Replay] Skill not found:",
			ToolName
		)

		return

	end


	--------------------------------------------------
	-- GLOBAL ABILITY REMOTE
	--------------------------------------------------

	AbilityUsed:FireServer(
		Key,
		SkillTool
	)


	--------------------------------------------------
	-- FIND THE SKILL'S EVENT
	--------------------------------------------------

	local SkillEvent = nil


	-- First try abilityEvent

	local AbilityEvent = SkillTool:FindFirstChild("abilityEvent")

	if AbilityEvent and AbilityEvent:IsA("RemoteEvent") then
		SkillEvent = AbilityEvent
	end


	-- Then try spellEvent

	if not SkillEvent then

		local SpellEvent = SkillTool:FindFirstChild("spellEvent")

		if SpellEvent and SpellEvent:IsA("RemoteEvent") then
			SkillEvent = SpellEvent
		end

	end


	--------------------------------------------------
	-- FIRE SKILL EVENT
	--------------------------------------------------

	if SkillEvent then

		SkillEvent:FireServer()

	else

		warn(
			"[Replay] No abilityEvent or spellEvent found for:",
			ToolName
		)

	end

end


--==================================================
-- CREATE PATH
--==================================================

local function CreatePathTo(TargetPosition)

	if not RootPart then
		return false
	end

	if not Humanoid then
		return false
	end


	local Path = PathfindingService:CreatePath({

		AgentRadius = 2,

		AgentHeight = 5,

		AgentCanJump = true,

		AgentCanClimb = true,

		WaypointSpacing = 3

	})


	local Success = pcall(function()

		Path:ComputeAsync(
			RootPart.Position,
			TargetPosition
		)

	end)


	if not Success then

		CurrentPath = nil

		return false

	end


	if Path.Status ~= Enum.PathStatus.Success then

		CurrentPath = nil

		return false

	end


	CurrentPath = Path:GetWaypoints()

	CurrentPathIndex = 2

	LastPathTarget = TargetPosition

	LastPathCalculation = os.clock()

	return true

end


--==================================================
-- RESET PATH
--==================================================

local function ResetPath()

	CurrentPath = nil

	CurrentPathIndex = 1

	LastPathTarget = nil

	LastPathCalculation = 0

	StuckTimer = 0

end


--==================================================
-- MOVE ALONG PATH
--==================================================

local function MoveToReplayPosition(TargetPosition)

	if not Humanoid or not RootPart then
		return
	end


	local Distance = (
		RootPart.Position - TargetPosition
	).Magnitude


	-- Reached target

	if Distance <= PATH_POINT_DISTANCE then

		ResetPath()

		ReplayIndex += 1

		return

	end


	--------------------------------------------------
	-- STUCK DETECTION
	--------------------------------------------------

	local Now = os.clock()


	if not LastPosition then

		LastPosition = RootPart.Position

		LastMovementCheck = Now

	else

		if Now - LastMovementCheck >= 0.25 then

			local MovementDistance = (
				RootPart.Position - LastPosition
			).Magnitude


			if MovementDistance < 0.25 then

				StuckTimer += Now - LastMovementCheck

			else

				StuckTimer = 0

			end


			LastPosition = RootPart.Position

			LastMovementCheck = Now

		end

	end


	--------------------------------------------------
	-- RECALCULATE PATH IF NEEDED
	--------------------------------------------------

	local NeedNewPath = false


	if not CurrentPath then

		NeedNewPath = true

	elseif not LastPathTarget then

		NeedNewPath = true

	elseif (
		TargetPosition - LastPathTarget
	).Magnitude > 5 then

		NeedNewPath = true

	elseif Now - LastPathCalculation >= PATH_RECALCULATE_TIME then

		NeedNewPath = true

	elseif StuckTimer >= STUCK_TIME then

		NeedNewPath = true

		StuckTimer = 0

	end


	if NeedNewPath then

		CreatePathTo(TargetPosition)

	end


	--------------------------------------------------
	-- FOLLOW PATH
	--------------------------------------------------

	if CurrentPath then

		local Waypoint = CurrentPath[CurrentPathIndex]


		if Waypoint then

			local WaypointDistance = (
				RootPart.Position -
				Waypoint.Position
			).Magnitude


			if WaypointDistance <= 2.5 then

				CurrentPathIndex += 1

				Waypoint = CurrentPath[CurrentPathIndex]

			end


			if Waypoint then

				if Waypoint.Action ==
					Enum.PathWaypointAction.Jump then

					Humanoid.Jump = true

				end


				Humanoid:MoveTo(
					Waypoint.Position
				)

				return

			end

		end

	end


	--------------------------------------------------
	-- FALLBACK
	--------------------------------------------------

	Humanoid:MoveTo(TargetPosition)

end


--==================================================
-- FIND NEAREST MOVEMENT POINT
--==================================================

local function FindNearestMovementPoint(Recording)

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
	local ClosestDistance = math.huge


	for Index, Point in ipairs(Recording.Movement) do

		if Point.Position then

			local Distance = (
				RootPart.Position -
				Point.Position
			).Magnitude


			if Distance < ClosestDistance then

				ClosestDistance = Distance

				ClosestIndex = Index

			end

		end

	end


	return ClosestIndex, ClosestDistance

end


--==================================================
-- STOP REPLAY
--==================================================

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


	StatusLabel.Text = "Status: Idle"

end


--==================================================
-- START REPLAY
--==================================================

local function StartReplay(Recording, StartIndex)

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


	ReplayIndex = StartIndex or 1

	ReplayInputIndex = 1

	ReplayStartTime = os.clock()


	ResetPath()


	LastPosition = nil

	LastMovementCheck = os.clock()

	StuckTimer = 0


	StatusLabel.Text =
		"Status: Replaying " ..
		Recording.Name


	--------------------------------------------------
	-- SKIP INPUTS BEFORE RESUME POINT
	--------------------------------------------------

	local StartTime = 0


	if Recording.Movement[ReplayIndex] then

		StartTime =
			Recording.Movement[ReplayIndex].Time or 0

	end


	for Index, InputData in ipairs(Recording.Inputs) do

		if InputData.Time >= StartTime then

			ReplayInputIndex = Index

			break

		end

	end


	--------------------------------------------------
	-- REPLAY LOOP
	--------------------------------------------------

	ReplayConnection = RunService.Heartbeat:Connect(function()

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


		--------------------------------------------------
		-- DEAD CHECK
		--------------------------------------------------

		if Humanoid.Health <= 0 then

			ResumeAfterDeath = true

			if ReplayConnection then

				ReplayConnection:Disconnect()

				ReplayConnection = nil

			end

			Replaying = false

			return

		end


		--------------------------------------------------
		-- CURRENT TIME
		--------------------------------------------------

		local ElapsedTime =
			(
				os.clock() -
				ReplayStartTime
			) + StartTime


		--------------------------------------------------
		-- REPLAY SKILLS
		--------------------------------------------------

		while
			ReplayInputIndex <=
			#Recording.Inputs
		do

			local InputData =
				Recording.Inputs[ReplayInputIndex]


			if InputData.Time > ElapsedTime then
				break
			end


			if InputData.ActionType == "Skill" then

				ReplaySkill(
					InputData.Key,
					InputData.ToolName
				)

			end


			ReplayInputIndex += 1

		end


		--------------------------------------------------
		-- FINISHED
		--------------------------------------------------

		if ReplayIndex > #Recording.Movement then

			StopReplay()

			return

		end


		--------------------------------------------------
		-- CURRENT MOVEMENT POINT
		--------------------------------------------------

		local MovementData =
			Recording.Movement[ReplayIndex]


		if not MovementData then

			StopReplay()

			return

		end


		--------------------------------------------------
		-- WAIT UNTIL TIMESTAMP
		--------------------------------------------------

		if MovementData.Time > ElapsedTime then
			return
		end


		--------------------------------------------------
		-- MOVE TO RECORDED POSITION
		--------------------------------------------------

		MoveToReplayPosition(
			MovementData.Position
		)

	end)

end


--==================================================
-- RECORDING
--==================================================

local function StartRecording()

	if Recording then
		return
	end


	if Replaying then
		StopReplay()
	end


	if not Character or not RootPart then
		return
	end


	local RecordingName =
		NameBox.Text


	if RecordingName == "" then

		RecordingName =
			"Recording " ..
			tostring(#Recordings + 1)

	end


	CurrentRecording = {

		Name = RecordingName,

		Movement = {},

		Inputs = {}

	}


	Recording = true

	RecordStartTime = os.clock()

	LastRecordTime = 0


	StatusLabel.Text =
		"Status: Recording..."


	--------------------------------------------------
	-- RECORD MOVEMENT
	--------------------------------------------------

	RecordConnection =
		RunService.Heartbeat:Connect(function()

			if not Recording then
				return
			end

			if not RootPart then
				return
			end


			local Now = os.clock()

			local Elapsed =
				Now - RecordStartTime


			if Elapsed - LastRecordTime <
				RECORD_INTERVAL then

				return

			end


			LastRecordTime = Elapsed


			local Position =
				RootPart.Position


			table.insert(
				CurrentRecording.Movement,
				{

					Time = Elapsed,

					Position = Position,

					CFrame = RootPart.CFrame

				}
			)

		end)

end


--==================================================
-- STOP RECORDING
--==================================================

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
		(CurrentRecording and CurrentRecording.Name or "")


	CurrentRecording = nil

	UpdateDropdown()

end


--==================================================
-- RECORD Q / E INPUT
--==================================================

UserInputService.InputBegan:Connect(function(
	Input,
	GameProcessed
)

	if GameProcessed then
		return
	end


	--------------------------------------------------
	-- RECORD Q
	--------------------------------------------------

	if Input.KeyCode == Enum.KeyCode.Q then

		RecordSkill("q")

	end


	--------------------------------------------------
	-- RECORD E
	--------------------------------------------------

	if Input.KeyCode == Enum.KeyCode.E then

		RecordSkill("e")

	end

end)


--==================================================
-- DROPDOWN UPDATE
--==================================================

function UpdateDropdown()

	for _, Child in ipairs(
		DropdownFrame:GetChildren()
	) do

		if Child:IsA("TextButton") then
			Child:Destroy()
		end

	end


	for Index, Recording in ipairs(Recordings) do

		local Button = Instance.new("TextButton")

		Button.Size =
			UDim2.new(1, -5, 0, 30)

		Button.BackgroundColor3 =
			Color3.fromRGB(50, 50, 50)

		Button.BorderSizePixel = 0

		Button.Text =
			Recording.Name

		Button.TextColor3 =
			Color3.fromRGB(255, 255, 255)

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


		Button.MouseButton1Click:Connect(function()

			SelectedRecording =
				Recording


			DropdownButton.Text =
				Recording.Name .. " ▼"


			DropdownFrame.Visible =
				false


			StatusLabel.Text =
				"Selected: " ..
				Recording.Name

		end)

	end


	DropdownFrame.CanvasSize =
		UDim2.new(
			0,
			0,
			0,
			DropdownLayout.AbsoluteContentSize.Y
		)

end


--==================================================
-- DROPDOWN BUTTON
--==================================================

DropdownButton.MouseButton1Click:Connect(function()

	DropdownFrame.Visible =
		not DropdownFrame.Visible

end)


--==================================================
-- RECORD BUTTON
--==================================================

RecordButton.MouseButton1Click:Connect(function()

	StartRecording()

end)


--==================================================
-- STOP BUTTON
--==================================================

StopButton.MouseButton1Click:Connect(function()

	if Recording then

		StopRecording()

	elseif Replaying then

		StopReplay()

	end

end)


--==================================================
-- REPLAY BUTTON
--==================================================

ReplayButton.MouseButton1Click:Connect(function()

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

end)


--==================================================
-- DEATH RESUME
--==================================================

local function SetupDeathDetection()

	if DeathConnection then

		DeathConnection:Disconnect()

		DeathConnection = nil

	end


	if not Humanoid then
		return
	end


	DeathConnection =
		Humanoid.Died:Connect(function()

			if not Replaying then
				return
			end


			ResumeAfterDeath = true


			if ReplayConnection then

				ReplayConnection:Disconnect()

				ReplayConnection = nil

			end


			Replaying = false


			StatusLabel.Text =
				"Status: Waiting for respawn..."

		end)

end


--==================================================
-- CHARACTER RESPAWN
--==================================================

Player.CharacterAdded:Connect(function(
	NewCharacter
)

	SetupCharacter(NewCharacter)

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


	--------------------------------------------------
	-- WAIT FOR CHARACTER
	--------------------------------------------------

	task.wait(0.75)


	if not RootPart then
		return
	end


	--------------------------------------------------
	-- FIND CLOSEST RECORDED POINT
	--------------------------------------------------

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


	--------------------------------------------------
	-- TOO FAR FROM RECORDED PATH
	--------------------------------------------------

	if ClosestDistance >
		MAX_RESUME_DISTANCE then

		StatusLabel.Text =
			"Status: Respawn too far from path"

		return

	end


	--------------------------------------------------
	-- RESUME WITHOUT TELEPORTING
	--------------------------------------------------

	StatusLabel.Text =
		"Status: Resuming replay..."


	task.wait(0.25)


	StartReplay(
		RecordingToResume,
		ClosestIndex
	)

end)


--==================================================
-- INITIAL DEATH DETECTION
--==================================================

if Humanoid then
	SetupDeathDetection()
end


--==================================================
-- INITIAL UI
--==================================================

UpdateDropdown()


StatusLabel.Text =
	"Status: Idle"
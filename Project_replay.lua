--// =========================================================
--// REPLAY SYSTEM v1.3.0
--// Movement + Skills
--// =========================================================

local VERSION = "v1.3.0"

--// SERVICES
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local Player = Players.LocalPlayer
local Backpack = Player:WaitForChild("Backpack")

local Remotes = ReplicatedStorage:WaitForChild("remotes")
local AbilityUsed = Remotes:WaitForChild("abilityUsed")

--// CHARACTER
local Character
local Humanoid
local RootPart

local function SetupCharacter(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid")
	RootPart = char:WaitForChild("HumanoidRootPart")
end

if Player.Character then
	SetupCharacter(Player.Character)
end

Player.CharacterAdded:Connect(function(char)
	SetupCharacter(char)
end)

--// =========================================================
--// SETTINGS
--// =========================================================

local RECORD_INTERVAL = 0.10
local MOVEMENT_REACH_DISTANCE = 2.5
local WAYPOINT_REACH_DISTANCE = 2.5

local PATH_TARGET_CHANGE = 10
local STUCK_TIME = 1.75

local MAX_RESUME_DISTANCE = 150

--// =========================================================
--// STATE
--// =========================================================

local Recordings = {}
local CurrentRecording = nil

local IsRecording = false
local IsReplaying = false
local ReplayThread = nil

local SelectedRecording = nil

--// Skill configuration
local QSkillName = "Inner Focus"
local ESkillName = "Pulse Waves"

--// =========================================================
--// GUI
--// =========================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ReplaySystem"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = Player:WaitForChild("PlayerGui")

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 390, 0, 500)
Main.Position = UDim2.new(0.5, -195, 0.5, -250)
Main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = Main

--// Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 45)
Header.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -90, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Replay System"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local VersionLabel = Instance.new("TextLabel")
VersionLabel.Size = UDim2.new(0, 70, 1, 0)
VersionLabel.Position = UDim2.new(1, -120, 0, 0)
VersionLabel.BackgroundTransparency = 1
VersionLabel.Text = VERSION
VersionLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
VersionLabel.TextSize = 12
VersionLabel.Font = Enum.Font.Gotham
VersionLabel.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.new(0, 35, 0, 35)
Minimize.Position = UDim2.new(1, -42, 0, 5)
Minimize.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
Minimize.Text = "-"
Minimize.TextColor3 = Color3.fromRGB(255, 255, 255)
Minimize.TextSize = 20
Minimize.Font = Enum.Font.GothamBold
Minimize.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 7)
MinCorner.Parent = Minimize

--// Content
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -20, 1, -55)
Content.Position = UDim2.new(0, 10, 0, 50)
Content.BackgroundTransparency = 1
Content.Parent = Main

--// =========================================================
--// HELPER UI FUNCTIONS
--// =========================================================

local function CreateLabel(text, y, height)
	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 0, height or 25)
	Label.Position = UDim2.new(0, 0, 0, y)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.TextColor3 = Color3.fromRGB(220, 220, 225)
	Label.TextSize = 13
	Label.Font = Enum.Font.Gotham
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Content
	return Label
end

local function CreateButton(text, y)
	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(1, 0, 0, 38)
	Button.Position = UDim2.new(0, 0, 0, y)
	Button.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	Button.Text = text
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.TextSize = 14
	Button.Font = Enum.Font.GothamBold
	Button.AutoButtonColor = true
	Button.Parent = Content

	local C = Instance.new("UICorner")
	C.CornerRadius = UDim.new(0, 7)
	C.Parent = Button

	return Button
end

--// =========================================================
--// SKILL DROPDOWNS
--// =========================================================

CreateLabel("Q Skill", 0, 22)

local QDropdown = Instance.new("TextButton")
QDropdown.Size = UDim2.new(1, 0, 0, 35)
QDropdown.Position = UDim2.new(0, 0, 0, 24)
QDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
QDropdown.Text = "Q: " .. QSkillName
QDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
QDropdown.TextSize = 13
QDropdown.Font = Enum.Font.Gotham
QDropdown.Parent = Content

local QCorner = Instance.new("UICorner")
QCorner.CornerRadius = UDim.new(0, 7)
QCorner.Parent = QDropdown

CreateLabel("E Skill", 65, 22)

local EDropdown = Instance.new("TextButton")
EDropdown.Size = UDim2.new(1, 0, 0, 35)
EDropdown.Position = UDim2.new(0, 0, 0, 89)
EDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
EDropdown.Text = "E: " .. ESkillName
EDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
EDropdown.TextSize = 13
EDropdown.Font = Enum.Font.Gotham
EDropdown.Parent = Content

local ECorner = Instance.new("UICorner")
ECorner.CornerRadius = UDim.new(0, 7)
ECorner.Parent = EDropdown

--// Dropdown container
local DropdownFrame = Instance.new("Frame")
DropdownFrame.Size = UDim2.new(1, 0, 0, 0)
DropdownFrame.Position = UDim2.new(0, 0, 0, 130)
DropdownFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
DropdownFrame.BorderSizePixel = 0
DropdownFrame.Visible = false
DropdownFrame.ZIndex = 20
DropdownFrame.Parent = Content

local DropdownLayout = Instance.new("UIListLayout")
DropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
DropdownLayout.Parent = DropdownFrame

local CurrentDropdownKey = nil

local function ClearDropdown()
	for _, child in ipairs(DropdownFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function GetSkillNames()
	local Names = {}

	for _, obj in ipairs(Backpack:GetChildren()) do
		if obj:FindFirstChild("abilityEvent") or obj:FindFirstChild("spellEvent") then
			table.insert(Names, obj.Name)
		end
	end

	-- Also check character
	if Character then
		for _, obj in ipairs(Character:GetChildren()) do
			if obj:FindFirstChild("abilityEvent") or obj:FindFirstChild("spellEvent") then
				if not table.find(Names, obj.Name) then
					table.insert(Names, obj.Name)
				end
			end
		end
	end

	table.sort(Names)

	return Names
end

local function OpenDropdown(Key)
	CurrentDropdownKey = Key
	ClearDropdown()

	local Names = GetSkillNames()

	if #Names == 0 then
		local Button = Instance.new("TextButton")
		Button.Size = UDim2.new(1, 0, 0, 30)
		Button.Text = "No skills found"
		Button.TextColor3 = Color3.fromRGB(200, 200, 200)
		Button.BackgroundTransparency = 1
		Button.ZIndex = 21
		Button.Parent = DropdownFrame
	else
		for _, SkillName in ipairs(Names) do
			local Button = Instance.new("TextButton")
			Button.Size = UDim2.new(1, 0, 0, 30)
			Button.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
			Button.Text = SkillName
			Button.TextColor3 = Color3.fromRGB(255, 255, 255)
			Button.TextSize = 13
			Button.Font = Enum.Font.Gotham
			Button.ZIndex = 21
			Button.Parent = DropdownFrame

			Button.MouseButton1Click:Connect(function()
				if CurrentDropdownKey == "Q" then
					QSkillName = SkillName
					QDropdown.Text = "Q: " .. SkillName
				else
					ESkillName = SkillName
					EDropdown.Text = "E: " .. SkillName
				end

				DropdownFrame.Visible = false
				DropdownFrame.Size = UDim2.new(1, 0, 0, 0)
			end)
		end
	end

	local Height = math.min(#Names * 30, 150)

	if #Names == 0 then
		Height = 30
	end

	DropdownFrame.Size = UDim2.new(1, 0, 0, Height)
	DropdownFrame.Visible = true
end

QDropdown.MouseButton1Click:Connect(function()
	if DropdownFrame.Visible and CurrentDropdownKey == "Q" then
		DropdownFrame.Visible = false
		DropdownFrame.Size = UDim2.new(1, 0, 0, 0)
	else
		OpenDropdown("Q")
	end
end)

EDropdown.MouseButton1Click:Connect(function()
	if DropdownFrame.Visible and CurrentDropdownKey == "E" then
		DropdownFrame.Visible = false
		DropdownFrame.Size = UDim2.new(1, 0, 0, 0)
	else
		OpenDropdown("E")
	end
end)

--// =========================================================
--// RECORDING UI
--// =========================================================

local RecordButton = CreateButton("● RECORD", 140)
local StopButton = CreateButton("■ STOP", 185)

local RecordingLabel = CreateLabel("Status: Idle", 230, 25)

local RecordingDropdown = Instance.new("TextButton")
RecordingDropdown.Size = UDim2.new(1, 0, 0, 35)
RecordingDropdown.Position = UDim2.new(0, 0, 0, 258)
RecordingDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
RecordingDropdown.Text = "Select Recording"
RecordingDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
RecordingDropdown.TextSize = 13
RecordingDropdown.Font = Enum.Font.Gotham
RecordingDropdown.Parent = Content

local RC = Instance.new("UICorner")
RC.CornerRadius = UDim.new(0, 7)
RC.Parent = RecordingDropdown

local ReplayButton = CreateButton("▶ REPLAY SELECTED", 303)

--// =========================================================
--// RECORDING FUNCTIONS
--// =========================================================

local function RecordSkill(Key)
	if not IsRecording or not CurrentRecording then
		return
	end

	local SkillName

	if Key == "q" then
		SkillName = QSkillName
	elseif Key == "e" then
		SkillName = ESkillName
	end

	if not SkillName or SkillName == "" then
		return
	end

	table.insert(CurrentRecording.Actions, {
		Time = os.clock() - CurrentRecording.StartTime,
		ActionType = "Skill",
		Key = Key,
		SkillName = SkillName
	})

	print("[Replay] RECORDED SKILL:", Key, "->", SkillName)
end

local function RecordMovement()
	if not IsRecording or not CurrentRecording then
		return
	end

	if not RootPart then
		return
	end

	table.insert(CurrentRecording.Movement, {
		Time = os.clock() - CurrentRecording.StartTime,
		CFrame = RootPart.CFrame
	})
end

--// =========================================================
--// INPUT RECORDING
--// =========================================================

UserInputService.InputBegan:Connect(function(Input)
	if Input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if Input.KeyCode == Enum.KeyCode.Q then
		RecordSkill("q")
	elseif Input.KeyCode == Enum.KeyCode.E then
		RecordSkill("e")
	end
end)

--// =========================================================
--// RECORD
--// =========================================================

local function StartRecording()
	if IsRecording or IsReplaying then
		return
	end

	CurrentRecording = {
		Name = "Recording " .. tostring(#Recordings + 1),
		StartTime = os.clock(),
		Movement = {},
		Actions = {}
	}

	IsRecording = true

	RecordingLabel.Text = "Status: Recording..."
	RecordButton.Text = "● RECORDING"

	print("[Replay] Recording started")
end

local function StopRecording()
	if not IsRecording then
		return
	end

	IsRecording = false

	if CurrentRecording then
		CurrentRecording.Duration = os.clock() - CurrentRecording.StartTime

		table.insert(Recordings, CurrentRecording)

		SelectedRecording = CurrentRecording

		RecordingLabel.Text =
			"Status: Saved " ..
			CurrentRecording.Name ..
			" (" ..
			string.format("%.1fs", CurrentRecording.Duration) ..
			")"

		CurrentRecording = nil
	end

	RecordButton.Text = "● RECORD"

	print("[Replay] Recording stopped")
end

RecordButton.MouseButton1Click:Connect(StartRecording)
StopButton.MouseButton1Click:Connect(StopRecording)

--// =========================================================
--// MOVEMENT RECORD LOOP
--// =========================================================

task.spawn(function()
	while true do
		if IsRecording then
			RecordMovement()
		end

		task.wait(RECORD_INTERVAL)
	end
end)

--// =========================================================
--// SKILL REPLAY
--// =========================================================

local function FindSkill(SkillName)
	-- Backpack first, exactly like your working scripts
	local Skill = Backpack:FindFirstChild(SkillName)

	if Skill then
		return Skill
	end

	-- Fallback to character
	if Character then
		Skill = Character:FindFirstChild(SkillName)

		if Skill then
			return Skill
		end
	end

	return nil
end

local function ReplaySkill(Key, SkillName)
	print("[Replay] Trying skill:", Key, SkillName)

	local Skill = FindSkill(SkillName)

	if not Skill then
		warn("[Replay] SKILL NOT FOUND:", SkillName)
		return false
	end

	print("[Replay] Found skill:", Skill:GetFullName())

	-- EXACTLY like your supplied working code
	local Success, ErrorMessage = pcall(function()

		AbilityUsed:FireServer(Key, Skill)

		local Event = Skill:FindFirstChild("abilityEvent")

		if not Event then
			Event = Skill:FindFirstChild("spellEvent")
		end

		if not Event then
			error("No abilityEvent or spellEvent found")
		end

		Event:FireServer()
	end)

	if not Success then
		warn("[Replay] Skill error:", ErrorMessage)
		return false
	end

	print("[Replay] SUCCESS:", Key, SkillName)

	return true
end

--// =========================================================
--// PATHFINDING
--// =========================================================

local function MoveToPosition(Position)
	if not Humanoid or not RootPart then
		return false
	end

	local Path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4
	})

	local Success = pcall(function()
		Path:ComputeAsync(RootPart.Position, Position)
	end)

	if not Success or Path.Status ~= Enum.PathStatus.Success then
		Humanoid:MoveTo(Position)

		local Start = os.clock()

		while os.clock() - Start < 3 do
			if not RootPart then
				return false
			end

			if (RootPart.Position - Position).Magnitude <= MOVEMENT_REACH_DISTANCE then
				return true
			end

			Humanoid:MoveTo(Position)

			task.wait(0.1)
		end

		return false
	end

	local Waypoints = Path:GetWaypoints()

	for _, Waypoint in ipairs(Waypoints) do
		if not IsReplaying then
			return false
		end

		if Waypoint.Action == Enum.PathWaypointAction.Jump then
			Humanoid.Jump = true
		end

		Humanoid:MoveTo(Waypoint.Position)

		local Start = os.clock()

		while os.clock() - Start < 4 do
			if not RootPart then
				return false
			end

			local Distance =
				(RootPart.Position - Waypoint.Position).Magnitude

			if Distance <= WAYPOINT_REACH_DISTANCE then
				break
			end

			Humanoid:MoveTo(Waypoint.Position)

			task.wait(0.08)
		end
	end

	return true
end

--// =========================================================
--// REPLAY MOVEMENT
--// =========================================================

local function ReplayMovement(Data, StartIndex)
	for i = StartIndex, #Data.Movement do
		if not IsReplaying then
			return
		end

		local Point = Data.Movement[i]

		if not RootPart then
			return
		end

		local Position = Point.CFrame.Position

		local Distance =
			(RootPart.Position - Position).Magnitude

		if Distance > 3 then
			MoveToPosition(Position)
		end

		if not RootPart then
			return
		end
	end
end

--// =========================================================
--// FIND NEAREST RECORDED POINT
--// =========================================================

local function FindNearestMovementPoint(Data)
	if not RootPart or #Data.Movement == 0 then
		return 1
	end

	local BestIndex = 1
	local BestDistance = math.huge

	for i, Point in ipairs(Data.Movement) do
		local Distance =
			(RootPart.Position - Point.CFrame.Position).Magnitude

		if Distance < BestDistance then
			BestDistance = Distance
			BestIndex = i
		end
	end

	if BestDistance <= MAX_RESUME_DISTANCE then
		return BestIndex
	end

	return 1
end

--// =========================================================
--// REPLAY
--// =========================================================

local function StartReplay(Data)
	if IsReplaying or IsRecording then
		return
	end

	if not Data then
		RecordingLabel.Text = "Status: No recording selected"
		return
	end

	IsReplaying = true

	RecordingLabel.Text = "Status: Replaying " .. Data.Name
	ReplayButton.Text = "■ STOP REPLAY"

	print("[Replay] Starting:", Data.Name)

	local StartIndex = FindNearestMovementPoint(Data)

	local StartTime = os.clock()

	local ActionIndex = 1
	local MovementIndex = StartIndex

	while IsReplaying do

		if not Character or not Humanoid or not RootPart then
			task.wait(0.2)
			continue
		end

		local Elapsed = os.clock() - StartTime

		--// Skills
		while ActionIndex <= #Data.Actions do
			local Action = Data.Actions[ActionIndex]

			if Action.Time > Elapsed then
				break
			end

			if Action.ActionType == "Skill" then
				ReplaySkill(
					Action.Key,
					Action.SkillName
				)
			end

			ActionIndex += 1
		end

		--// Movement
		while MovementIndex <= #Data.Movement do
			local Point = Data.Movement[MovementIndex]

			if Point.Time > Elapsed then
				break
			end

			local Position = Point.CFrame.Position

			if (RootPart.Position - Position).Magnitude > 3 then
				MoveToPosition(Position)
			end

			MovementIndex += 1
		end

		if ActionIndex > #Data.Actions
			and MovementIndex > #Data.Movement then
			break
		end

		task.wait(0.03)
	end

	IsReplaying = false

	RecordingLabel.Text = "Status: Replay finished"
	ReplayButton.Text = "▶ REPLAY SELECTED"

	print("[Replay] Finished")
end

ReplayButton.MouseButton1Click:Connect(function()
	if IsReplaying then
		IsReplaying = false
		return
	end

	StartReplay(SelectedRecording)
end)

--// =========================================================
--// RECORDING DROPDOWN
--// =========================================================

local RecordingList = Instance.new("Frame")
RecordingList.Size = UDim2.new(1, 0, 0, 0)
RecordingList.Position = UDim2.new(0, 0, 0, 294)
RecordingList.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
RecordingList.BorderSizePixel = 0
RecordingList.Visible = false
RecordingList.ZIndex = 30
RecordingList.Parent = Content

local RecordingLayout = Instance.new("UIListLayout")
RecordingLayout.Parent = RecordingList

local function RefreshRecordings()
	for _, child in ipairs(RecordingList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for i, Recording in ipairs(Recordings) do
		local Button = Instance.new("TextButton")

		Button.Size = UDim2.new(1, 0, 0, 32)
		Button.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
		Button.Text =
			Recording.Name ..
			" | " ..
			string.format("%.1fs", Recording.Duration or 0)

		Button.TextColor3 = Color3.fromRGB(255, 255, 255)
		Button.TextSize = 12
		Button.Font = Enum.Font.Gotham
		Button.ZIndex = 31
		Button.Parent = RecordingList

		Button.MouseButton1Click:Connect(function()
			SelectedRecording = Recording
			RecordingDropdown.Text = "Selected: " .. Recording.Name

			RecordingList.Visible = false
			RecordingList.Size = UDim2.new(1, 0, 0, 0)

			print("[Replay] Selected:", Recording.Name)
		end)
	end

	local Height = math.min(#Recordings * 32, 160)

	RecordingList.Size = UDim2.new(1, 0, 0, Height)
end

RecordingDropdown.MouseButton1Click:Connect(function()
	if RecordingList.Visible then
		RecordingList.Visible = false
		RecordingList.Size = UDim2.new(1, 0, 0, 0)
	else
		RefreshRecordings()
		RecordingList.Visible = true
	end
end)

--// =========================================================
--// DEATH RESUME
--// =========================================================

Player.CharacterAdded:Connect(function(NewCharacter)

	SetupCharacter(NewCharacter)

	if IsReplaying and SelectedRecording then

		task.wait(1)

		if not IsReplaying then
			return
		end

		local ResumeIndex =
			FindNearestMovementPoint(SelectedRecording)

		print(
			"[Replay] Respawn detected. Resuming at movement point:",
			ResumeIndex
		)

		-- Continue replay from the nearest path point.
		-- Do NOT teleport the player.

		task.spawn(function()
			ReplayMovement(
				SelectedRecording,
				ResumeIndex
			)
		end)
	end
end)

--// =========================================================
--// MINIMIZE
--// =========================================================

local Minimized = false

Minimize.MouseButton1Click:Connect(function()

	Minimized = not Minimized

	if Minimized then
		Content.Visible = false
		Main.Size = UDim2.new(0, 390, 0, 45)
		Minimize.Text = "+"
	else
		Content.Visible = true
		Main.Size = UDim2.new(0, 390, 0, 500)
		Minimize.Text = "-"
	end
end)

--// =========================================================
--// DRAG WINDOW
--// =========================================================

local Dragging = false
local DragStart
local StartPosition

Header.InputBegan:Connect(function(Input)

	if Input.UserInputType == Enum.UserInputType.MouseButton1 then

		Dragging = true
		DragStart = Input.Position
		StartPosition = Main.Position

		Input.Changed:Connect(function()

			if Input.UserInputState == Enum.UserInputState.End then
				Dragging = false
			end

		end)
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

	Main.Position =
		UDim2.new(
			StartPosition.X.Scale,
			StartPosition.X.Offset + Delta.X,
			StartPosition.Y.Scale,
			StartPosition.Y.Offset + Delta.Y
		)
end)

--// =========================================================
--// BACKPACK UPDATE
--// =========================================================

Backpack.ChildAdded:Connect(function()
	task.wait(0.1)

	if DropdownFrame.Visible then
		OpenDropdown(CurrentDropdownKey)
	end
end)

Backpack.ChildRemoved:Connect(function()
	task.wait(0.1)

	if DropdownFrame.Visible then
		OpenDropdown(CurrentDropdownKey)
	end
end)

print("====================================")
print("Replay System", VERSION, "loaded")
print("Q Skill:", QSkillName)
print("E Skill:", ESkillName)
print("====================================")
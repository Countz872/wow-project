--// =========================================================
--// REPLAY SYSTEM v1.4.0
--// Movement + Skills
--// =========================================================

local VERSION = "v1.4.0"

--// SERVICES
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local Backpack = Player:WaitForChild("Backpack")

local Remotes = ReplicatedStorage:WaitForChild("remotes")
local AbilityUsed = Remotes:WaitForChild("abilityUsed")

--// =========================================================
--// CHARACTER
--// =========================================================

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

-- How often movement gets recorded.
local RECORD_INTERVAL = 0.05

-- How far ahead the replay looks for its movement target.
local LOOK_AHEAD_DISTANCE = 1.5

-- Distance considered close enough to a movement point.
local MOVE_REACH_DISTANCE = 1.8

--// =========================================================
--// STATE
--// =========================================================

local Recordings = {}

local CurrentRecording = nil
local SelectedRecording = nil

local IsRecording = false
local IsReplaying = false

local ReplayToken = 0

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
Main.Size = UDim2.new(0, 400, 0, 570)
Main.Position = UDim2.new(0.5, -200, 0.5, -285)
Main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

--// =========================================================
--// HEADER
--// =========================================================

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 45)
Header.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
Header.BorderSizePixel = 0
Header.Active = true
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -150, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Replay System"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Active = false
Title.Parent = Header

local VersionLabel = Instance.new("TextLabel")
VersionLabel.Size = UDim2.new(0, 70, 1, 0)
VersionLabel.Position = UDim2.new(1, -115, 0, 0)
VersionLabel.BackgroundTransparency = 1
VersionLabel.Text = VERSION
VersionLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
VersionLabel.TextSize = 12
VersionLabel.Font = Enum.Font.Gotham
VersionLabel.Active = false
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

--// =========================================================
--// CONTENT
--// =========================================================

local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -55)
Content.Position = UDim2.new(0, 10, 0, 50)
Content.BackgroundTransparency = 1
Content.Parent = Main

--// =========================================================
--// UI HELPERS
--// =========================================================

local function CreateLabel(text, y, height)
	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 0, height or 22)
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

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 7)
	Corner.Parent = Button

	return Button
end

local function CreateTextBox(placeholder, y)
	local Box = Instance.new("TextBox")
	Box.Size = UDim2.new(1, 0, 0, 35)
	Box.Position = UDim2.new(0, 0, 0, y)
	Box.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
	Box.PlaceholderText = placeholder
	Box.PlaceholderColor3 = Color3.fromRGB(130, 130, 140)
	Box.Text = ""
	Box.TextColor3 = Color3.fromRGB(255, 255, 255)
	Box.TextSize = 13
	Box.Font = Enum.Font.Gotham
	Box.ClearTextOnFocus = false
	Box.Parent = Content

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 7)
	Corner.Parent = Box

	local Padding = Instance.new("UIPadding")
	Padding.PaddingLeft = UDim.new(0, 10)
	Padding.PaddingRight = UDim.new(0, 10)
	Padding.Parent = Box

	return Box
end

--// =========================================================
--// RECORDING NAME
--// =========================================================

CreateLabel("Recording Name", 0, 22)

local NameBox = CreateTextBox("Enter recording name...", 24)

--// =========================================================
--// Q / E SKILLS
--// =========================================================

CreateLabel("Q Skill", 68, 22)

local QDropdown = Instance.new("TextButton")
QDropdown.Size = UDim2.new(1, 0, 0, 35)
QDropdown.Position = UDim2.new(0, 0, 0, 92)
QDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
QDropdown.Text = "Q: " .. QSkillName
QDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
QDropdown.TextSize = 13
QDropdown.Font = Enum.Font.Gotham
QDropdown.Parent = Content

local QCorner = Instance.new("UICorner")
QCorner.CornerRadius = UDim.new(0, 7)
QCorner.Parent = QDropdown

CreateLabel("E Skill", 136, 22)

local EDropdown = Instance.new("TextButton")
EDropdown.Size = UDim2.new(1, 0, 0, 35)
EDropdown.Position = UDim2.new(0, 0, 0, 160)
EDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
EDropdown.Text = "E: " .. ESkillName
EDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
EDropdown.TextSize = 13
EDropdown.Font = Enum.Font.Gotham
EDropdown.Parent = Content

local ECorner = Instance.new("UICorner")
ECorner.CornerRadius = UDim.new(0, 7)
ECorner.Parent = EDropdown

--// =========================================================
--// SKILL DROPDOWN
--// =========================================================

local DropdownFrame = Instance.new("Frame")
DropdownFrame.Size = UDim2.new(1, 0, 0, 0)
DropdownFrame.Position = UDim2.new(0, 0, 0, 198)
DropdownFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
DropdownFrame.BorderSizePixel = 0
DropdownFrame.Visible = false
DropdownFrame.ZIndex = 50
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

	local function CheckContainer(Container)
		if not Container then
			return
		end

		for _, Object in ipairs(Container:GetChildren()) do
			if Object:FindFirstChild("abilityEvent")
				or Object:FindFirstChild("spellEvent") then

				if not table.find(Names, Object.Name) then
					table.insert(Names, Object.Name)
				end
			end
		end
	end

	CheckContainer(Backpack)
	CheckContainer(Character)

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
		Button.BackgroundTransparency = 1
		Button.Text = "No skills found"
		Button.TextColor3 = Color3.fromRGB(200, 200, 200)
		Button.TextSize = 12
		Button.ZIndex = 51
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
			Button.ZIndex = 51
			Button.Parent = DropdownFrame

			Button.MouseButton1Click:Connect(function()

				if CurrentDropdownKey == "Q" then
					QSkillName = SkillName
					QDropdown.Text = "Q: " .. SkillName
				elseif CurrentDropdownKey == "E" then
					ESkillName = SkillName
					EDropdown.Text = "E: " .. SkillName
				end

				DropdownFrame.Visible = false
				DropdownFrame.Size = UDim2.new(1, 0, 0, 0)

			end)
		end
	end

	local Height = math.min(math.max(#Names, 1) * 30, 180)

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
--// RECORDING CONTROLS
--// =========================================================

local RecordButton = CreateButton("● RECORD", 210)
local StopButton = CreateButton("■ STOP", 255)

local StatusLabel = CreateLabel("Status: Idle", 300, 25)

--// =========================================================
--// RECORDING SELECTION
--// =========================================================

local RecordingDropdown = Instance.new("TextButton")
RecordingDropdown.Size = UDim2.new(1, 0, 0, 35)
RecordingDropdown.Position = UDim2.new(0, 0, 0, 330)
RecordingDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 53)
RecordingDropdown.Text = "Select Recording"
RecordingDropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
RecordingDropdown.TextSize = 13
RecordingDropdown.Font = Enum.Font.Gotham
RecordingDropdown.Parent = Content

local RecordingCorner = Instance.new("UICorner")
RecordingCorner.CornerRadius = UDim.new(0, 7)
RecordingCorner.Parent = RecordingDropdown

local RecordingList = Instance.new("Frame")
RecordingList.Size = UDim2.new(1, 0, 0, 0)
RecordingList.Position = UDim2.new(0, 0, 0, 368)
RecordingList.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
RecordingList.BorderSizePixel = 0
RecordingList.Visible = false
RecordingList.ZIndex = 40
RecordingList.Parent = Content

local RecordingLayout = Instance.new("UIListLayout")
RecordingLayout.SortOrder = Enum.SortOrder.LayoutOrder
RecordingLayout.Parent = RecordingList

--// =========================================================
--// REPLAY BUTTON
--// =========================================================

local ReplayButton = CreateButton("▶ REPLAY SELECTED", 410)

--// =========================================================
--// RECORDING
--// =========================================================

local function StartRecording()

	if IsRecording then
		return
	end

	if IsReplaying then
		StatusLabel.Text = "Status: Stop replay first"
		return
	end

	local RecordingName = NameBox.Text

	if RecordingName == nil or RecordingName:gsub("%s+", "") == "" then
		RecordingName = "Recording " .. tostring(#Recordings + 1)
	end

	CurrentRecording = {
		Name = RecordingName,
		StartTime = os.clock(),
		Duration = 0,

		Movement = {},
		Actions = {}
	}

	IsRecording = true

	RecordButton.Text = "● RECORDING"
	StatusLabel.Text = "Status: Recording..."

	print("[Replay] Recording started:", RecordingName)

end

local function StopRecording()

	if not IsRecording then
		return
	end

	IsRecording = false

	if CurrentRecording then

		CurrentRecording.Duration =
			os.clock() - CurrentRecording.StartTime

		table.insert(Recordings, CurrentRecording)

		SelectedRecording = CurrentRecording

		RecordingDropdown.Text =
			"Selected: " .. CurrentRecording.Name

		StatusLabel.Text =
			"Saved: " ..
			CurrentRecording.Name ..
			" | " ..
			string.format("%.2fs", CurrentRecording.Duration)

		print(
			"[Replay] Saved:",
			CurrentRecording.Name,
			"Movement:",
			#CurrentRecording.Movement,
			"Actions:",
			#CurrentRecording.Actions
		)

		CurrentRecording = nil

	end

	RecordButton.Text = "● RECORD"

end

RecordButton.MouseButton1Click:Connect(StartRecording)
StopButton.MouseButton1Click:Connect(StopRecording)

--// =========================================================
--// MOVEMENT RECORDING
--// =========================================================

task.spawn(function()

	while true do

		if IsRecording
			and CurrentRecording
			and RootPart then

			table.insert(CurrentRecording.Movement, {

				Time = os.clock() - CurrentRecording.StartTime,

				Position = RootPart.Position,

				CFrame = RootPart.CFrame

			})

		end

		task.wait(RECORD_INTERVAL)

	end

end)

--// =========================================================
--// SKILL RECORDING
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

	if not SkillName then
		return
	end

	table.insert(CurrentRecording.Actions, {

		Time = os.clock() - CurrentRecording.StartTime,

		ActionType = "Skill",

		Key = Key,

		SkillName = SkillName

	})

	print(
		"[Replay] RECORDED:",
		Key,
		"->",
		SkillName
	)

end

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
--// FIND SKILL
--// =========================================================

local function FindSkill(SkillName)

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

--// =========================================================
--// REPLAY SKILL
--// =========================================================

local function ReplaySkill(Key, SkillName)

	print(
		"[Replay] SKILL:",
		Key,
		SkillName
	)

	local Skill = FindSkill(SkillName)

	if not Skill then

		warn(
			"[Replay] Skill not found:",
			SkillName
		)

		return false

	end

	local Success, ErrorMessage = pcall(function()

		-- EXACT SAME ORDER AS YOUR WORKING SCRIPT
		AbilityUsed:FireServer(
			Key,
			Skill
		)

		local Event =
			Skill:FindFirstChild("abilityEvent")

		if not Event then
			Event =
				Skill:FindFirstChild("spellEvent")
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

	print(
		"[Replay] SUCCESS:",
		Key,
		SkillName
	)

	return true

end

--// =========================================================
--// MOVEMENT REPLAY
--// =========================================================

local function GetMovementPoint(Data, Time)

	local Movement = Data.Movement

	if #Movement == 0 then
		return nil
	end

	-- Find the two points surrounding the current time.
	for i = 1, #Movement - 1 do

		local A = Movement[i]
		local B = Movement[i + 1]

		if Time >= A.Time and Time <= B.Time then

			local Difference = B.Time - A.Time

			local Alpha = 0

			if Difference > 0 then
				Alpha =
					(Time - A.Time) / Difference
			end

			Alpha = math.clamp(Alpha, 0, 1)

			return A, B, Alpha

		end

	end

	return Movement[#Movement], nil, 1

end

local function ReplayMovement(Data, ReplayStartTime)

	if not Humanoid or not RootPart then
		return
	end

	local Movement = Data.Movement

	if #Movement == 0 then
		return
	end

	while IsReplaying do

		if not Character
			or not Humanoid
			or not RootPart then

			task.wait(0.1)
			continue

		end

		local Elapsed =
			os.clock() - ReplayStartTime

		local A, B, Alpha =
			GetMovementPoint(Data, Elapsed)

		if not A then
			break
		end

		local TargetPosition

		if B then

			TargetPosition =
				A.Position:Lerp(
					B.Position,
					Alpha
				)

		else

			TargetPosition = A.Position

		end

		local Distance =
			(RootPart.Position - TargetPosition).Magnitude

		-- Only issue MoveTo when necessary.
		-- This prevents the constant stopping/stuttering.
		if Distance > MOVE_REACH_DISTANCE then

			Humanoid:MoveTo(TargetPosition)

		end

		RunService.Heartbeat:Wait()

	end

end

--// =========================================================
--// FIND RESUME POINT AFTER DEATH
--// =========================================================

local function FindNearestMovementIndex(Data)

	if not RootPart then
		return 1
	end

	if #Data.Movement == 0 then
		return 1
	end

	local BestIndex = 1
	local BestDistance = math.huge

	for i, Point in ipairs(Data.Movement) do

		local Distance =
			(RootPart.Position - Point.Position).Magnitude

		if Distance < BestDistance then

			BestDistance = Distance
			BestIndex = i

		end

	end

	return BestIndex

end

--// =========================================================
--// REPLAY
--// =========================================================

local function StartReplay(Data)

	if IsReplaying then
		return
	end

	if IsRecording then
		StatusLabel.Text = "Status: Stop recording first"
		return
	end

	if not Data then
		StatusLabel.Text = "Status: Select a recording"
		return
	end

	if #Data.Movement == 0 then
		StatusLabel.Text = "Status: Recording has no movement"
		return
	end

	IsReplaying = true

	ReplayToken += 1

	local MyToken = ReplayToken

	StatusLabel.Text =
		"Status: Replaying " .. Data.Name

	ReplayButton.Text = "■ STOP REPLAY"

	print(
		"[Replay] Starting:",
		Data.Name
	)

	--// Determine nearest recorded point
	local StartIndex =
		FindNearestMovementIndex(Data)

	-- Start replay timeline from that recorded point.
	local StartData =
		Data.Movement[StartIndex]

	local TimelineOffset =
		StartData.Time

	local ReplayStartTime =
		os.clock() - TimelineOffset

	--// =====================================================
	--// MOVEMENT THREAD
	--// =====================================================

	task.spawn(function()

		ReplayMovement(
			Data,
			ReplayStartTime
		)

	end)

	--// =====================================================
	--// SKILL TIMELINE
	--// =====================================================

	task.spawn(function()

		for _, Action in ipairs(Data.Actions) do

			if not IsReplaying
				or MyToken ~= ReplayToken then
				return
			end

			-- Don't replay actions before the resume point.
			if Action.Time < TimelineOffset then
				continue
			end

			local TargetTime =
				Action.Time - TimelineOffset

			local CurrentTime =
				os.clock() - ReplayStartTime

			local WaitTime =
				TargetTime - CurrentTime

			if WaitTime > 0 then
				task.wait(WaitTime)
			end

			if not IsReplaying
				or MyToken ~= ReplayToken then
				return
			end

			if Action.ActionType == "Skill" then

				ReplaySkill(
					Action.Key,
					Action.SkillName
				)

			end

		end

	end)

	--// =====================================================
	--// FINISH MONITOR
	--// =====================================================

	task.spawn(function()

		local Duration =
			Data.Duration - TimelineOffset

		if Duration > 0 then
			task.wait(Duration + 0.25)
		end

		if MyToken ~= ReplayToken then
			return
		end

		if IsReplaying then

			IsReplaying = false

			StatusLabel.Text =
				"Status: Replay finished"

			ReplayButton.Text =
				"▶ REPLAY SELECTED"

			print("[Replay] Finished")

		end

	end)

end

local function StopReplay()

	if not IsReplaying then
		return
	end

	IsReplaying = false

	ReplayToken += 1

	if Humanoid then
		Humanoid:Move(Vector3.zero)
	end

	StatusLabel.Text =
		"Status: Replay stopped"

	ReplayButton.Text =
		"▶ REPLAY SELECTED"

	print("[Replay] Stopped")

end

ReplayButton.MouseButton1Click:Connect(function()

	if IsReplaying then
		StopReplay()
	else
		StartReplay(SelectedRecording)
	end

end)

--// =========================================================
--// RECORDING LIST
--// =========================================================

local function RefreshRecordings()

	for _, Child in ipairs(RecordingList:GetChildren()) do

		if Child:IsA("TextButton") then
			Child:Destroy()
		end

	end

	for _, Recording in ipairs(Recordings) do

		local Button = Instance.new("TextButton")

		Button.Size =
			UDim2.new(1, 0, 0, 32)

		Button.BackgroundColor3 =
			Color3.fromRGB(45, 45, 53)

		Button.Text =
			Recording.Name ..
			" | " ..
			string.format(
				"%.1fs",
				Recording.Duration
			)

		Button.TextColor3 =
			Color3.fromRGB(255, 255, 255)

		Button.TextSize = 12
		Button.Font = Enum.Font.Gotham
		Button.ZIndex = 41
		Button.Parent = RecordingList

		Button.MouseButton1Click:Connect(function()

			SelectedRecording = Recording

			RecordingDropdown.Text =
				"Selected: " ..
				Recording.Name

			RecordingList.Visible = false
			RecordingList.Size =
				UDim2.new(1, 0, 0, 0)

		end)

	end

	local Height =
		math.min(#Recordings * 32, 160)

	RecordingList.Size =
		UDim2.new(1, 0, 0, Height)

end

RecordingDropdown.MouseButton1Click:Connect(function()

	if RecordingList.Visible then

		RecordingList.Visible = false
		RecordingList.Size =
			UDim2.new(1, 0, 0, 0)

	else

		RefreshRecordings()

		RecordingList.Visible = true

	end

end)

--// =========================================================
--// DEATH / RESPAWN
--// =========================================================

Player.CharacterAdded:Connect(function(NewCharacter)

	SetupCharacter(NewCharacter)

	if IsReplaying and SelectedRecording then

		task.wait(1)

		if not IsReplaying then
			return
		end

		print(
			"[Replay] Player respawned."
		)

		-- Find the closest point on the original route.
		local ResumeIndex =
			FindNearestMovementIndex(
				SelectedRecording
			)

		if SelectedRecording.Movement[ResumeIndex] then

			local ResumeTime =
				SelectedRecording
					.Movement[ResumeIndex]
					.Time

			-- Restart the movement timeline
			-- from the nearest point.
			task.spawn(function()

				ReplayMovement(
					SelectedRecording,
					os.clock() - ResumeTime
				)

			end)

		end

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

		Main.Size =
			UDim2.new(0, 400, 0, 45)

		Minimize.Text = "+"

	else

		Content.Visible = true

		Main.Size =
			UDim2.new(0, 400, 0, 570)

		Minimize.Text = "-"

	end

end)

--// =========================================================
--// DRAGGING
--// =========================================================

local Dragging = false
local DragInput = nil
local DragStart = nil
local StartPosition = nil

Header.InputBegan:Connect(function(Input)

	if Input.UserInputType ==
		Enum.UserInputType.MouseButton1
		or Input.UserInputType ==
		Enum.UserInputType.Touch then

		Dragging = true

		DragStart = Input.Position
		StartPosition = Main.Position

	end

end)

Header.InputEnded:Connect(function(Input)

	if Input.UserInputType ==
		Enum.UserInputType.MouseButton1
		or Input.UserInputType ==
		Enum.UserInputType.Touch then

		Dragging = false

	end

end)

Header.InputChanged:Connect(function(Input)

	if Input.UserInputType ==
		Enum.UserInputType.MouseMovement
		or Input.UserInputType ==
		Enum.UserInputType.Touch then

		DragInput = Input

	end

end)

UserInputService.InputChanged:Connect(function(Input)

	if not Dragging then
		return
	end

	if Input ~= DragInput then
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
--// BACKPACK UPDATES
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

--// =========================================================
--// DEBUG
--// =========================================================

print("========================================")
print("Replay System", VERSION, "loaded")
print("Q Skill:", QSkillName)
print("E Skill:", ESkillName)
print("========================================")
--// Replay System v2.8.0
--// Cloudflare D1 recording sync integration
--// Compact Mobile UI
--// Multiple Recordings + Mouse/Touch Dragging
--// Movement + Pathfinding + Skill Replay

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

--==================================================
-- DIRECT CLOUDFLARE CONFIG
--==================================================
-- This version talks to Cloudflare directly from the LocalScript.
-- This is convenient for testing, but the API key is visible to the client.
-- For a public game, use a server-side proxy instead.
local CLOUDFLARE_WORKER_URL = "https://project-replay.meijio12115.workers.dev"
local CLOUDFLARE_API_KEY = "ProjectReplay_2026_x8Kp92LmQ7vT4z"
local CLOUDFLARE_SAVE_PATH = "/api/replay/save"
local CLOUDFLARE_LOAD_PATH = "/api/replay/load"

-- Normalize the Worker URL so a trailing slash never creates //api/... URLs.
CLOUDFLARE_WORKER_URL = CLOUDFLARE_WORKER_URL:gsub("/+$", "")


local Player = Players.LocalPlayer
local Backpack = nil

local function GetBackpack()
	Backpack = Player:FindFirstChildOfClass("Backpack") or Player:FindFirstChild("Backpack")
	return Backpack
end

GetBackpack()

local Remotes = ReplicatedStorage:WaitForChild("remotes")
local AbilityUsed = Remotes:WaitForChild("abilityUsed")
local ChangeStartValue = Remotes:WaitForChild("changeStartValue")
local ReplayDungeon = Remotes:WaitForChild("replayDungeon")

--------------------------------------------------
-- DUNGEON AUTO SYSTEM
--------------------------------------------------

local AutoStart = true
local AutoReplay = true
local AutoSave = true

local LastAutoStartFire = 0
local LastAutoReplayKey = nil
local AUTO_START_COOLDOWN = 3
local DUNGEON_SCAN_INTERVAL = 0.35

local DungeonState = {
	dungeonStarted = nil,
	dungeonProgress = nil,
	dungeonFinished = nil,
	dungeonName = nil,
	hardcore = false,
	isHardcore = false,
	fightingBoss = false
}

local function ReadValueObject(Object)
	if not Object:IsA("ValueBase") then
		return nil
	end

	local Success, Value = pcall(function()
		return Object.Value
	end)

	return Success and Value or nil
end

local function FindDungeonField(FieldName)
	-- Exact locations discovered by DungeonStateFinder.
	local ExactObjects = {
		dungeonStarted = workspace:FindFirstChild("dungeonStarted"),
		dungeonProgress = workspace:FindFirstChild("dungeonProgress"),
		dungeonName = workspace:FindFirstChild("dungeonName"),
		hardcore = workspace:FindFirstChild("hardcore"),
		dungeonFinished = nil,
		fightingBoss = nil
	}

	local DungeonFolder = workspace:FindFirstChild("dungeon")
	local BossRoom = DungeonFolder and DungeonFolder:FindFirstChild("bossRoom")

	if BossRoom then
		ExactObjects.dungeonFinished = BossRoom:FindFirstChild("dungeonFinished")
		ExactObjects.fightingBoss = BossRoom:FindFirstChild("fightingBoss")
	end

	local Exact = ExactObjects[FieldName]

	if Exact then
		local Value = ReadValueObject(Exact)
		if Value ~= nil then
			return Value
		end

		local Success, Attribute = pcall(function()
			return Exact:GetAttribute(FieldName)
		end)

		if Success and Attribute ~= nil then
			return Attribute
		end
	end

	-- Fallback for recreated/moved replicated objects.
	local Containers = {
		workspace,
		Player,
		Player:FindFirstChild("PlayerGui"),
		Character,
		ReplicatedStorage
	}

	for _, Container in ipairs(Containers) do
		if Container then
			local Success, Attribute = pcall(function()
				return Container:GetAttribute(FieldName)
			end)

			if Success and Attribute ~= nil then
				return Attribute
			end

			local Direct = Container:FindFirstChild(FieldName, true)
			if Direct then
				local Value = ReadValueObject(Direct)
				if Value ~= nil then
					return Value
				end

				local AttributeSuccess, AttributeValue = pcall(function()
					return Direct:GetAttribute(FieldName)
				end)

				if AttributeSuccess and AttributeValue ~= nil then
					return AttributeValue
				end
			end
		end
	end

	return nil
end

local function GetDungeonState()
	local State = {}

	State.dungeonStarted = FindDungeonField("dungeonStarted")
	State.dungeonProgress = FindDungeonField("dungeonProgress")
	State.dungeonFinished = FindDungeonField("dungeonFinished")
	State.dungeonName = FindDungeonField("dungeonName")
	State.hardcore = FindDungeonField("hardcore")
	State.isHardcore = FindDungeonField("isHardcore")
	State.fightingBoss = FindDungeonField("fightingBoss")

	if State.hardcore == nil then
		State.hardcore = false
	end

	if State.isHardcore == nil then
		State.isHardcore = State.hardcore
	end

	if State.fightingBoss == nil then
		State.fightingBoss = true
	end

	DungeonState = State
	return State
end

local function FireAutoStart()
                AutoStartCompletedAt = os.clock()
	local Now = os.clock()

	if Now - LastAutoStartFire < AUTO_START_COOLDOWN then
		return
	end

	local Success, ErrorMessage = pcall(function()
		ChangeStartValue:FireServer()
	end)

	if Success then
		LastAutoStartFire = Now
		print("[Replay] Auto Start -> changeStartValue")
	else
		warn("[Replay] Auto Start error:", ErrorMessage)
	end
end

local function FireAutoReplay(State)
	local Progress = tostring(State.dungeonProgress or "")

	-- Only fire when the actual discovered Workspace.dungeonProgress says bossKilled.
	-- Reset the one-shot lock after progress changes so the same dungeon can replay again.
	if Progress ~= "bossKilled" then
		LastAutoReplayKey = nil
		return
	end

	local DungeonName = State.dungeonName
	if DungeonName == nil or tostring(DungeonName) == "" then
		warn("[Replay] bossKilled detected, but Workspace.dungeonName is empty.")
		return
	end

	DungeonName = tostring(DungeonName)

	local Hardcore = State.hardcore == true
	local ReplayKey = DungeonName .. "|bossKilled|" .. tostring(Hardcore)

	if LastAutoReplayKey == ReplayKey then
		return
	end

	local DungeonStarted = State.dungeonStarted
	if DungeonStarted == nil then DungeonStarted = true end

	local DungeonFinished = State.dungeonFinished
	if DungeonFinished == nil then DungeonFinished = true end

	local IsHardcore = State.isHardcore
	if IsHardcore == nil then IsHardcore = Hardcore end

	local FightingBoss = State.fightingBoss
	if FightingBoss == nil then FightingBoss = true end

	local Payload = {
		dungeonProgress = "bossKilled",
		dungeonStarted = DungeonStarted == true,
		dungeonFinished = DungeonFinished == true,
		hardcore = Hardcore,
		dungeonName = DungeonName,
		isHardcore = IsHardcore == true,
		fightingBoss = FightingBoss == true
	}

	print("[Replay] bossKilled detected!")
	print("[Replay] dungeonName:", DungeonName)
	print("[Replay] dungeonStarted:", DungeonStarted)
	print("[Replay] dungeonFinished:", DungeonFinished)
	print("[Replay] hardcore:", Hardcore)
	print("[Replay] fightingBoss:", FightingBoss)

	local Success, ErrorMessage = pcall(function()
		ReplayDungeon:FireServer(Payload)
	end)

	if Success then
		LastAutoReplayKey = ReplayKey
		print("[Replay] Auto Replay FIRED ->", DungeonName)
	else
		warn("[Replay] Auto Replay error:", ErrorMessage)
	end
end

--------------------------------------------------
-- CONFIG
--------------------------------------------------

local VERSION = "v2.7.0"

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
-- SKILLS
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

--------------------------------------------------
-- STATE
--------------------------------------------------

local IsRecording = false
local IsReplaying = false

local CurrentRecording = nil

-- IMPORTANT:
-- Every recording is stored separately in this table.
local Recordings = {}

local SelectedRecording = nil

--------------------------------------------------
-- CLOUDFLARE CLOUD SAVE
--------------------------------------------------

local CloudBusy = false
local CloudLoaded = false
local CloudLoadFailed = false
local CloudSavePending = false
local CloudStatus = "Cloud: not loaded"
local CloudUIRefresh = function() end

local function SerializeRecording(Recording)
	local Out = {
		Name = Recording.Name,
		Duration = Recording.Duration or 0,
		Movement = {},
		Actions = {},
	}

	for _, Point in ipairs(Recording.Movement or {}) do
		local P = Point.Position
		local C = Point.CFrame
		local components = nil
		if typeof(C) == "CFrame" then
			components = {C:GetComponents()}
		end
		table.insert(Out.Movement, {
			Time = Point.Time or 0,
			Position = {P.X, P.Y, P.Z},
			CFrame = components,
		})
	end

	for _, Action in ipairs(Recording.Actions or {}) do
		table.insert(Out.Actions, {
			Time = Action.Time or 0,
			ActionType = Action.ActionType or "Skill",
			Key = Action.Key,
			SkillName = Action.SkillName,
		})
	end

	return Out
end

local function DeserializeRecording(Recording)
	local Out = {
		Name = tostring(Recording.Name or "Recording"),
		Duration = tonumber(Recording.Duration) or 0,
		Movement = {},
		Actions = {},
	}

	for _, Point in ipairs(Recording.Movement or {}) do
		local pos = Point.Position or {0, 0, 0}
		local cf = Point.CFrame
		local position = Vector3.new(tonumber(pos[1]) or 0, tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
		local cframe = CFrame.new(position)
		if type(cf) == "table" and #cf >= 12 then
			local ok, value = pcall(function()
				return CFrame.new(table.unpack(cf, 1, 12))
			end)
			if ok then cframe = value end
		end
		table.insert(Out.Movement, {
			Time = tonumber(Point.Time) or 0,
			Position = position,
			CFrame = cframe,
		})
	end

	for _, Action in ipairs(Recording.Actions or {}) do
		table.insert(Out.Actions, {
			Time = tonumber(Action.Time) or 0,
			ActionType = Action.ActionType or "Skill",
			Key = Action.Key,
			SkillName = Action.SkillName,
		})
	end

	return Out
end

local function BuildCloudPayload()
	local Data = {
		recordings = {},
		settings = {
			autoStart = AutoStart,
			autoReplay = AutoReplay,
			autoSave = AutoSave,
			qSkill = QSkillName,
			eSkill = ESkillName,
		},
	}
	for _, Recording in ipairs(Recordings) do
		table.insert(Data.recordings, SerializeRecording(Recording))
	end
	return Data
end

local function GetRequestFunction()
	local candidates = {
		(typeof(request) == "function" and request) or nil,
		(typeof(http_request) == "function" and http_request) or nil,
		(typeof(syn) == "table" and typeof(syn.request) == "function" and syn.request) or nil,
		(typeof(http) == "table" and typeof(http.request) == "function" and http.request) or nil,
	}

	for _, fn in ipairs(candidates) do
		if fn then
			return fn
		end
	end

	return nil
end

local function CloudRequest(Method, Url, Body)
	if CLOUDFLARE_WORKER_URL == ""
		or CLOUDFLARE_WORKER_URL:find("YOUR%-SUBDOMAIN", 1, false)
		or CLOUDFLARE_WORKER_URL:find("YOUR%-WORKER", 1, false) then
		return false, "Set CLOUDFLARE_WORKER_URL to your real project-replay Worker URL"
	end

	if CLOUDFLARE_API_KEY == "" or CLOUDFLARE_API_KEY == "PUT_YOUR_API_KEY_HERE" then
		return false, "Set CLOUDFLARE_API_KEY first"
	end

	local requestFn = GetRequestFunction()
	if not requestFn then
		return false, "No client HTTP request function is available"
	end

	local headers = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Bearer " .. CLOUDFLARE_API_KEY,
		["X-API-Key"] = CLOUDFLARE_API_KEY,
	}

	local requestData = {
		Url = Url,
		Method = Method,
		Headers = headers,
		Body = Body,
		-- lowercase aliases help with some request implementations
		url = Url,
		method = Method,
		headers = headers,
		body = Body,
	}

	local ok, response = pcall(requestFn, requestData)
	if not ok then
		return false, tostring(response)
	end

	if not response then
		return false, "No response"
	end

	local statusCode = tonumber(response.StatusCode or response.Status or response.status_code or 0) or 0
	local responseBody = response.Body or response.body or ""

	if statusCode < 200 or statusCode >= 300 then
		return false, "HTTP " .. tostring(statusCode) .. ": " .. tostring(responseBody)
	end

	local decodeOk, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(responseBody)
	end)

	if not decodeOk then
		return false, "Invalid JSON response: " .. tostring(responseBody)
	end

	if decoded.success == false then
		return false, tostring(decoded.error or "Cloudflare returned an error")
	end

	return true, decoded
end

local function SaveCloud(force)
	if not AutoSave and not force then
		return
	end

	if CloudBusy then
		CloudSavePending = true
		return
	end

	CloudBusy = true
	CloudSavePending = false

	task.spawn(function()
		local HttpService = game:GetService("HttpService")
		local payload = BuildCloudPayload()
		local encoded

		local encodeOk, encodeResult = pcall(function()
			local requestPayload = {
				userId = tostring(Player.UserId),
				recordings = payload.recordings,
				settings = payload.settings,
			}
			return HttpService:JSONEncode(requestPayload)
		end)

		if not encodeOk then
			CloudStatus = "Cloud: encode failed"
			warn("[Replay] Cloud encode failed:", encodeResult)
			CloudBusy = false
			CloudUIRefresh()
			return
		end

		encoded = encodeResult

		local ok, result = CloudRequest(
			"POST",
			CLOUDFLARE_WORKER_URL .. CLOUDFLARE_SAVE_PATH,
			encoded
		)

		if ok and result and result.success then
			CloudStatus = "Cloud: saved"
			print("[Replay] Cloud save successful")
		else
			CloudStatus = "Cloud: save failed"
			warn("[Replay] Cloud save failed:", result)
		end

		CloudBusy = false
		CloudUIRefresh()

		-- If a recording/settings change happened while the previous request was
		-- in progress, immediately send the newest state too.
		if CloudSavePending then
			CloudSavePending = false
			SaveCloud(true)
		end
	end)
end

local function LoadCloud()
	if CloudBusy then return end
	CloudLoadFailed = false
	CloudLoaded = false
	CloudBusy = true

	task.spawn(function()
		local ok, result = CloudRequest(
			"GET",
			CLOUDFLARE_WORKER_URL .. CLOUDFLARE_LOAD_PATH .. "?userId=" .. tostring(Player.UserId),
			nil
		)

		if ok and result and result.success and result.found then
			Recordings = {}

			for _, Recording in ipairs(result.recordings or {}) do
				table.insert(Recordings, DeserializeRecording(Recording))
			end

			local settings = result.settings or {}
			if settings.qSkill then QSkillName = tostring(settings.qSkill) end
			if settings.eSkill then ESkillName = tostring(settings.eSkill) end
			if settings.autoStart ~= nil then AutoStart = settings.autoStart == true end
			if settings.autoReplay ~= nil then AutoReplay = settings.autoReplay == true end
			if settings.autoSave ~= nil then AutoSave = settings.autoSave == true end

			SelectedRecording = nil
			if #Recordings > 0 then
				SelectedRecording = Recordings[1]
			end

			CloudLoaded = true
			CloudLoadFailed = false
			CloudStatus = "Cloud: loaded " .. tostring(#Recordings) .. " recordings"
			CloudUIRefresh()
			print("[Replay] Cloud load successful:", #Recordings, "recordings")
		elseif ok and result and result.success and not result.found then
			Recordings = {}
			CloudLoaded = true
			CloudLoadFailed = false
			CloudStatus = "Cloud: no saved data"
			CloudUIRefresh()
			print("[Replay] No cloud replay data found for this player")
		else
			CloudLoadFailed = true
			CloudStatus = "Cloud: load failed - automation paused"
			warn("[Replay] Cloud load failed:", result)
		end

		CloudBusy = false
		CloudUIRefresh()
	end)
end


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

local ReplayMovementIndex = 1

local LastRecordTime = 0

-- Respawn/replay synchronization
local ReplayRespawnPending = false
local ReplayRespawnIndex = nil

--------------------------------------------------
-- SKILL FUNCTIONS
--------------------------------------------------

local function FindSkill(SkillName)

	if not SkillName then
		return nil
	end

	local CurrentBackpack = GetBackpack()

	local Skill = CurrentBackpack and CurrentBackpack:FindFirstChild(SkillName)

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

		local Event =
			Skill:FindFirstChild("abilityEvent")

		if not Event then
			Event =
				Skill:FindFirstChild("spellEvent")
		end

		if not Event then
			error("No abilityEvent/spellEvent found")
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

--------------------------------------------------
-- RECORDING INFO
--------------------------------------------------

local function GetRecordingDuration(Recording)

	if not Recording then
		return 0
	end

	if Recording.Duration then
		return Recording.Duration
	end

	if Recording.Movement
		and #Recording.Movement > 0 then

		return Recording.Movement[
			#Recording.Movement
		].Time or 0

	end

	return 0
end

local function GetSkillCount(Recording)

	if not Recording then
		return 0
	end

	if not Recording.Actions then
		return 0
	end

	return #Recording.Actions
end

--------------------------------------------------
-- START RECORDING
--------------------------------------------------

local function StartRecording(Name)

	if IsRecording then
		return
	end

	if IsReplaying then
		return
	end

	if not Character
		or not RootPart
		or not Humanoid then

		return
	end

	--------------------------------------------------
	-- CREATE A COMPLETELY NEW RECORDING
	--------------------------------------------------

	RecordingCounter += 1

	if not Name
		or Name:gsub("%s+", "") == "" then

		Name =
			"Recording "
			.. tostring(RecordingCounter)

	end

	CurrentRecording = {
		Name = Name,

		Movement = {},

		Actions = {},

		StartTime = os.clock(),

		Duration = 0
	}

	-- Reset recording timer
	LastRecordTime = 0

	-- Reset movement tracking
	LastStuckPosition = nil
	StuckStartTime = nil

	IsRecording = true

	print(
		"[Replay] START:",
		Name,
		"Total recordings:",
		#Recordings
	)

end

--------------------------------------------------
-- STOP RECORDING
--------------------------------------------------

local function StopRecording()

	if not IsRecording then
		return
	end

	if not CurrentRecording then

		IsRecording = false

		return
	end

	--------------------------------------------------
	-- SAVE THE CURRENT RECORDING
	--------------------------------------------------

	local FinishedRecording =
		CurrentRecording

	FinishedRecording.Duration =
		os.clock()
		- FinishedRecording.StartTime

	--------------------------------------------------
	-- IMPORTANT:
	-- INSERT THIS RECORDING INTO THE TABLE
	--------------------------------------------------

	if #FinishedRecording.Movement > 0 then

		table.insert(
			Recordings,
			FinishedRecording
		)

		-- Automatically select the newly-created recording
		SelectedRecording =
			FinishedRecording

		print(
			"[Replay] SAVED:",
			FinishedRecording.Name
		)

		print(
			"[Replay] Total recordings:",
			#Recordings
		)

	else

		warn(
			"[Replay] Recording contained no movement"
		)

	end

	--------------------------------------------------
	-- CLEAR CURRENT RECORDING
	--------------------------------------------------

	CurrentRecording = nil

	IsRecording = false

	-- Persist the newly completed recording.
	SaveCloud(false)

	LastRecordTime = 0

end

--------------------------------------------------
-- RECORD MOVEMENT
--------------------------------------------------

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

	local Now =
		os.clock()

	local Time =
		Now
		- CurrentRecording.StartTime

	if Time - LastRecordTime <
		RECORD_INTERVAL then

		return
	end

	LastRecordTime = Time

	table.insert(
		CurrentRecording.Movement,
		{
			Time = Time,

			Position =
				RootPart.Position,

			CFrame =
				RootPart.CFrame
		}
	)

end

--------------------------------------------------
-- RECORD Q / E
--------------------------------------------------

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
						os.clock()
						- CurrentRecording.StartTime,

					ActionType = "Skill",

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
						os.clock()
						- CurrentRecording.StartTime,

					ActionType = "Skill",

					Key = "e",

					SkillName =
						ESkillName
				}
			)

		end

	end
)

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

	local Now =
		os.clock()

	if Now - LastPathCalculation <
		PATH_RECALCULATE_DELAY then

		return false
	end

	LastPathCalculation = Now

	local Path =
		PathfindingService:CreatePath(
			{
				AgentRadius =
					AGENT_RADIUS,

				AgentHeight =
					AGENT_HEIGHT,

				AgentCanJump =
					true,

				WaypointSpacing =
					WAYPOINT_SPACING
			}
		)

	local Success =
		pcall(
			function()

				Path:ComputeAsync(
					RootPart.Position,
					TargetPosition
				)

			end
		)

	if not Success then
		return false
	end

	if Path.Status ~=
		Enum.PathStatus.Success then

		return false
	end

	local Waypoints =
		Path:GetWaypoints()

	if #Waypoints < 2 then
		return false
	end

	ClearPath()

	CurrentPath =
		Path

	CurrentWaypoints =
		Waypoints

	CurrentWaypointIndex =
		2

	PathStartedTime =
		Now

	PathBlockedConnection =
		Path.Blocked:Connect(
			function(BlockedIndex)

				if BlockedIndex >=
					CurrentWaypointIndex then

					NeedNewPath = true

				end

			end
		)

	NeedNewPath = false

	return true
end

local function EnterPathfinding(TargetPosition)

	if not RootPart then
		return
	end

	local Success =
		ComputePath(
			TargetPosition
		)

	if Success then

		MovementMode =
			"Pathfinding"

		print(
			"[Replay] MoveTo stuck -> Pathfinding"
		)

	else

		MovementMode =
			"MoveTo"

	end

end

local function UpdatePathMovement()

	if MovementMode ~=
		"Pathfinding" then

		return
	end

	if not RootPart
		or not Humanoid then

		return
	end

	if not CurrentPath
		or #CurrentWaypoints == 0 then

		MovementMode =
			"MoveTo"

		return
	end

	if os.clock() - PathStartedTime >
		PATH_TIMEOUT then

		ClearPath()

		MovementMode =
			"MoveTo"

		return
	end

	if NeedNewPath then

		NeedNewPath = false

		if CurrentTarget then

			ComputePath(
				CurrentTarget
			)

		else

			MovementMode =
				"MoveTo"

		end

		return
	end

	local Waypoint =
		CurrentWaypoints[
			CurrentWaypointIndex
		]

	if not Waypoint then

		ClearPath()

		MovementMode =
			"MoveTo"

		return
	end

	local Distance =
		(
			RootPart.Position
			- Waypoint.Position
		).Magnitude

	if Distance <=
		WAYPOINT_REACHED_DISTANCE then

		CurrentWaypointIndex += 1

		Waypoint =
			CurrentWaypoints[
				CurrentWaypointIndex
			]

		if not Waypoint then

			ClearPath()

			MovementMode =
				"MoveTo"

			return
		end

	end

	if Waypoint.Action ==
		Enum.PathWaypointAction.Jump then

		Humanoid.Jump = true

	end

	if os.clock()
		- LastMoveCommand >=
		MOVETO_REFRESH then

		Humanoid:MoveTo(
			Waypoint.Position
		)

		LastMoveCommand =
			os.clock()

	end

end

--------------------------------------------------
-- STUCK DETECTION
--------------------------------------------------

local function CheckStuck(TargetPosition)

	if not RootPart then
		return
	end

	if MovementMode ==
		"Pathfinding" then

		return
	end

	local Now =
		os.clock()

	if Now - LastStuckCheck <
		0.25 then

		return
	end

	LastStuckCheck =
		Now

	local CurrentPosition =
		RootPart.Position

	if not LastStuckPosition then

		LastStuckPosition =
			CurrentPosition

		StuckStartTime =
			Now

		return
	end

	local MovementDistance =
		(
			CurrentPosition
			- LastStuckPosition
		).Magnitude

	if MovementDistance >=
		STUCK_MIN_MOVEMENT then

		LastStuckPosition =
			CurrentPosition

		StuckStartTime =
			Now

		return
	end

	if StuckStartTime
		and Now - StuckStartTime >=
		STUCK_TIME then

		if TargetPosition then

			EnterPathfinding(
				TargetPosition
			)

		end

		LastStuckPosition =
			CurrentPosition

		StuckStartTime =
			Now

	end

end

--------------------------------------------------
-- MOVE TO
--------------------------------------------------

local function MoveToTarget(TargetPosition)

	if not Humanoid
		or not RootPart then

		return
	end

	CurrentTarget =
		TargetPosition

	if MovementMode ==
		"Pathfinding" then

		UpdatePathMovement()

		return
	end

	local Distance =
		(
			RootPart.Position
			- TargetPosition
		).Magnitude

	if Distance <=
		TARGET_REACHED_DISTANCE then

		return
	end

	if os.clock()
		- LastMoveCommand >=
		MOVETO_REFRESH then

		Humanoid:MoveTo(
			TargetPosition
		)

		LastMoveCommand =
			os.clock()

	end

	CheckStuck(
		TargetPosition
	)

end

--------------------------------------------------
-- FIND NEAREST RECORDED POINT
--------------------------------------------------

local function FindNearestMovementIndex(
	Recording,
	Position
)

	if not Recording
		or not Recording.Movement then

		return 1
	end

	local ClosestIndex = 1

	local ClosestDistance =
		math.huge

	for Index, Point in ipairs(
		Recording.Movement
	) do

		local Distance =
			(
				Point.Position
				- Position
			).Magnitude

		if Distance <
			ClosestDistance then

			ClosestDistance =
				Distance

			ClosestIndex =
				Index

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

	if not Recording
		or not Recording.Actions then

		return
	end

	for _, Action in ipairs(
		Recording.Actions
	) do

		if Action.Time > OldTime
			and Action.Time <= NewTime then

			if Action.ActionType ==
				"Skill" then

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

local function ReplayMovement(
	Recording
)

	if not Recording then
		return
	end

	if not Recording.Movement
		or #Recording.Movement == 0 then

		return
	end

	IsReplaying =
		true

	MovementMode =
		"MoveTo"

	ClearPath()

	LastStuckPosition =
		nil

	StuckStartTime =
		nil

	local Movement =
		Recording.Movement

	local StartIndex =
		ReplayMovementIndex or 1

	StartIndex =
		math.clamp(
			StartIndex,
			1,
			#Movement
		)

	local StartTime =
		Movement[
			StartIndex
		].Time or 0

	local ReplayTime =
		StartTime

	local PreviousTime =
		StartTime

	local RealStart =
		os.clock()

	while IsReplaying do

		if not Character
			or not Character.Parent
			or not Humanoid
			or not Humanoid.Parent
			or not RootPart
			or not RootPart.Parent
			or Humanoid.Health <= 0 then

			-- IMPORTANT: do not let replay time continue while dead.
			-- Otherwise all Q/E actions can be consumed before respawn.
			task.wait(0.1)
			continue
		end

		-- A new character has spawned. Resume the replay from the
		-- nearest recorded path point and reset the replay clock.
		if ReplayRespawnPending then
			local ResumeIndex = ReplayRespawnIndex

			if not ResumeIndex then
				ResumeIndex = FindNearestMovementIndex(
					Recording,
					RootPart.Position
				)
			end

			ResumeIndex = math.clamp(
				ResumeIndex,
				1,
				#Movement
			)

			ReplayMovementIndex = ResumeIndex

			StartTime = Movement[ResumeIndex].Time or 0
			ReplayTime = StartTime
			PreviousTime = StartTime
			RealStart = os.clock()

			ClearPath()
			MovementMode = "MoveTo"
			CurrentTarget = nil
			LastMoveCommand = 0
			LastStuckCheck = 0
			LastStuckPosition = RootPart.Position
			StuckStartTime = os.clock()

			ReplayRespawnPending = false
			ReplayRespawnIndex = nil

			print("[Replay] Respawned. Resuming from point:", ResumeIndex)
		end

		local CurrentRealTime =
			os.clock()
			- RealStart

		ReplayTime =
			StartTime
			+ CurrentRealTime

		local Index =
			ReplayMovementIndex
			or StartIndex

		while Index <
			#Movement
			and Movement[
				Index + 1
			].Time <= ReplayTime do

			Index += 1

		end

		ReplayMovementIndex =
			Index

		local CurrentPoint =
			Movement[Index]

		local NextPoint =
			Movement[Index + 1]

		if CurrentPoint then

			local TargetPosition =
				CurrentPoint.Position

			if NextPoint then

				local SegmentStart =
					CurrentPoint.Time

				local SegmentEnd =
					NextPoint.Time

				local Alpha = 0

				if SegmentEnd >
					SegmentStart then

					Alpha =
						math.clamp(
							(
								ReplayTime
								- SegmentStart
							)
							/
							(
								SegmentEnd
								- SegmentStart
							),
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

			MoveToTarget(
				TargetPosition
			)

		end

		ReplayActionsBetween(
			Recording,
			PreviousTime,
			ReplayTime
		)

		PreviousTime =
			ReplayTime

		local FinalPoint =
			Movement[
				#Movement
			]

		local FinalTime =
			FinalPoint.Time or 0

		if ReplayTime >=
			FinalTime then

			local FinalDistance =
				(
					RootPart.Position
					- FinalPoint.Position
				).Magnitude

			if FinalDistance <=
				TARGET_REACHED_DISTANCE then

				break

			end

			MoveToTarget(
				FinalPoint.Position
			)

		end

		task.wait()

	end

	IsReplaying =
		false

	ClearPath()

	MovementMode =
		"MoveTo"

	CurrentTarget =
		nil

	print(
		"[Replay] Finished:",
		Recording.Name
	)

end

--------------------------------------------------
-- START REPLAY
--------------------------------------------------

local function StartReplay()

	if IsRecording
		or IsReplaying then

		return
	end

	if not SelectedRecording then

		warn(
			"[Replay] No recording selected"
		)

		return
	end

	if not SelectedRecording.Movement
		or #SelectedRecording.Movement == 0 then

		return
	end

	ReplayMovementIndex =
		1

	task.spawn(
		function()

			ReplayMovement(
				SelectedRecording
			)

		end
	)

end

--------------------------------------------------
-- STOP REPLAY
--------------------------------------------------

local function StopReplay()

	if not IsReplaying then
		return
	end

	IsReplaying =
		false

	ClearPath()

	MovementMode =
		"MoveTo"

	CurrentTarget =
		nil

	print(
		"[Replay] Replay stopped"
	)

end

--------------------------------------------------
-- RESPAWN
--------------------------------------------------

Player.CharacterAdded:Connect(
	function(NewCharacter)

		-- Refresh every character reference. The old Humanoid/RootPart
		-- are destroyed when the player dies.
		SetupCharacter(
			NewCharacter
		)

		-- Backpack can be repopulated during respawn. Refresh it too.
		GetBackpack()

		if not IsReplaying then
			return
		end

		if not SelectedRecording then
			return
		end

		-- Wait for the new character and its skill tools to finish spawning.
		task.wait(0.75)

		if not RootPart or not RootPart.Parent then
			return
		end

		local NearestIndex =
			FindNearestMovementIndex(
				SelectedRecording,
				RootPart.Position
			)

		ReplayMovementIndex =
			NearestIndex

		ReplayRespawnIndex =
			NearestIndex

		ReplayRespawnPending = true

		print(
			"[Replay] Respawn detected. Resume point:",
			NearestIndex
		)

	end
)

--------------------------------------------------
-- UI
--------------------------------------------------

local ScreenGui =
	Instance.new("ScreenGui")

ScreenGui.Name =
	"ReplaySystemUI"

ScreenGui.ResetOnSpawn =
	false

ScreenGui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling

ScreenGui.Parent =
	Player:WaitForChild(
		"PlayerGui"
	)

--------------------------------------------------
-- COLORS
--------------------------------------------------

local BG =
	Color3.fromRGB(
		18,
		18,
		21
	)

local PANEL =
	Color3.fromRGB(
		25,
		25,
		29
	)

local PANEL2 =
	Color3.fromRGB(
		32,
		32,
		37
	)

local INPUT =
	Color3.fromRGB(
		38,
		38,
		44
	)

local TEXT =
	Color3.fromRGB(
		240,
		240,
		245
	)

local SUBTEXT =
	Color3.fromRGB(
		155,
		155,
		165
	)

local GREEN =
	Color3.fromRGB(
		70,
		170,
		95
	)

local RED =
	Color3.fromRGB(
		185,
		70,
		70
	)

local BLUE =
	Color3.fromRGB(
		75,
		105,
		190
	)

--------------------------------------------------
-- UI HELPERS
--------------------------------------------------

local function AddCorner(
	Object,
	Radius
)

	local Corner =
		Instance.new("UICorner")

	Corner.CornerRadius =
		UDim.new(
			0,
			Radius or 7
		)

	Corner.Parent =
		Object

end

local function AddStroke(
	Object,
	Color,
	Transparency
)

	local Stroke =
		Instance.new("UIStroke")

	Stroke.Color =
		Color

	Stroke.Transparency =
		Transparency or 0

	Stroke.Thickness =
		1

	Stroke.Parent =
		Object

end

local function CreateLabel(
	Parent,
	TextValue,
	Size,
	Position,
	TextSize,
	Color
)

	local Label =
		Instance.new(
			"TextLabel"
		)

	Label.BackgroundTransparency =
		1

	Label.Size =
		Size

	Label.Position =
		Position

	Label.Text =
		TextValue

	Label.TextColor3 =
		Color or TEXT

	Label.TextSize =
		TextSize or 12

	Label.Font =
		Enum.Font.Gotham

	Label.TextXAlignment =
		Enum.TextXAlignment.Left

	Label.TextYAlignment =
		Enum.TextYAlignment.Center

	Label.Parent =
		Parent

	return Label

end

local function CreateButton(
	Parent,
	TextValue,
	Size,
	Position,
	Color
)

	local Button =
		Instance.new(
			"TextButton"
		)

	Button.Size =
		Size

	Button.Position =
		Position

	Button.BackgroundColor3 =
		Color or PANEL2

	Button.Text =
		TextValue

	Button.TextColor3 =
		TEXT

	Button.TextSize =
		10

	Button.Font =
		Enum.Font.GothamMedium

	Button.AutoButtonColor =
		true

	Button.Parent =
		Parent

	AddCorner(
		Button,
		6
	)

	return Button

end

--------------------------------------------------
-- MAIN FRAME
--------------------------------------------------

local MainFrame =
	Instance.new("Frame")

MainFrame.Size =
	UDim2.fromOffset(
		335,
		520
	)

MainFrame.Position =
	UDim2.new(
		0.5,
		-167,
		0.5,
		-260
	)

MainFrame.BackgroundColor3 =
	BG

MainFrame.Parent =
	ScreenGui

AddCorner(
	MainFrame,
	10
)

AddStroke(
	MainFrame,
	Color3.fromRGB(
		55,
		55,
		62
	),
	0.25
)

--------------------------------------------------
-- HEADER
--------------------------------------------------

local Header =
	Instance.new("Frame")

Header.Size =
	UDim2.new(
		1,
		0,
		0,
		48
	)

Header.BackgroundColor3 =
	PANEL

Header.Parent =
	MainFrame

AddCorner(
	Header,
	10
)

local HeaderBottom =
	Instance.new("Frame")

HeaderBottom.Size =
	UDim2.new(
		1,
		0,
		0,
		10
	)

HeaderBottom.Position =
	UDim2.new(
		0,
		0,
		1,
		-10
	)

HeaderBottom.BackgroundColor3 =
	PANEL

HeaderBottom.BorderSizePixel =
	0

HeaderBottom.Parent =
	Header

--------------------------------------------------
-- TITLE
--------------------------------------------------

local Title =
	CreateLabel(
		Header,
		"Replay System",
		UDim2.fromOffset(
			130,
			20
		),
		UDim2.fromOffset(
			12,
			5
		),
		14,
		TEXT
	)

Title.Font =
	Enum.Font.GothamBold

local VersionLabel =
	CreateLabel(
		Header,
		VERSION,
		UDim2.fromOffset(
			70,
			14
		),
		UDim2.fromOffset(
			13,
			26
		),
		8,
		SUBTEXT
	)

--------------------------------------------------
-- STATUS BADGE
--------------------------------------------------

local StatusBadge =
	Instance.new("Frame")

StatusBadge.Size =
	UDim2.fromOffset(
		92,
		26
	)

StatusBadge.Position =
	UDim2.new(
		1,
		-128,
		0,
		11
	)

StatusBadge.BackgroundColor3 =
	INPUT

StatusBadge.Parent =
	Header

AddCorner(
	StatusBadge,
	13
)

local StatusDot =
	Instance.new("Frame")

StatusDot.Size =
	UDim2.fromOffset(
		7,
		7
	)

StatusDot.Position =
	UDim2.fromOffset(
		9,
		9
	)

StatusDot.BackgroundColor3 =
	GREEN

StatusDot.Parent =
	StatusBadge

AddCorner(
	StatusDot,
	8
)

local StatusText =
	CreateLabel(
		StatusBadge,
		"READY",
		UDim2.new(
			1,
			-28,
			1,
			0
		),
		UDim2.fromOffset(
			24,
			0
		),
		9,
		TEXT
	)

StatusText.Font =
	Enum.Font.GothamBold

--------------------------------------------------
-- MINIMIZE
--------------------------------------------------

local MinimizeButton =
	CreateButton(
		Header,
		"—",
		UDim2.fromOffset(
			25,
			25
		),
		UDim2.new(
			1,
			-32,
			0,
			11
		),
		PANEL2
	)

MinimizeButton.TextSize =
	15

local Minimized =
	false

MinimizeButton.MouseButton1Click:Connect(
	function()

		Minimized =
			not Minimized

		if Minimized then

			MainFrame.Size =
				UDim2.fromOffset(
					335,
					48
				)

		else

			MainFrame.Size =
				UDim2.fromOffset(
					335,
					520
				)

		end

	end
)

--------------------------------------------------
-- MOBILE + PC DRAGGING
--------------------------------------------------

-- Use a dedicated drag handle instead of Header.InputBegan.
-- Header.InputBegan + Input.Target is unreliable and InputObject
-- does not provide a dependable Target property for this use.
local DragHandle =
	Instance.new("Frame")

DragHandle.Name =
	"DragHandle"

DragHandle.Size =
	UDim2.new(
		1,
		-132,
		1,
		0
	)

DragHandle.Position =
	UDim2.fromOffset(
		0,
		0
	)

DragHandle.BackgroundTransparency =
	1

DragHandle.BorderSizePixel =
	0

DragHandle.Active =
	true

DragHandle.ZIndex =
	10

DragHandle.Parent =
	Header

-- Keep the title/version visible above the handle while still allowing
-- the transparent handle to receive input.
Title.ZIndex = 11
VersionLabel.ZIndex = 11

local Dragging = false
local DragStart = nil
local StartPosition = nil
local DragInput = nil

local function BeginDrag(Input)
	Dragging = true
	DragStart = Input.Position
	StartPosition = MainFrame.Position
	DragInput = Input
end

local function EndDrag(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1
		or Input.UserInputType == Enum.UserInputType.Touch then
		Dragging = false
		DragInput = nil
	end
end

local function UpdateDrag(Input)
	if not Dragging or not DragStart or not StartPosition then
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
end

DragHandle.InputBegan:Connect(
	function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch then
			BeginDrag(Input)

			Input.Changed:Connect(function()
				if Input.UserInputState == Enum.UserInputState.End then
					EndDrag(Input)
				end
			end)
		end
	end
)

DragHandle.InputChanged:Connect(
	function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseMovement
			or Input.UserInputType == Enum.UserInputType.Touch then
			DragInput = Input
		end
	end
)

-- Forward title/version touches to the same drag system.
-- This makes dragging reliable even when the text itself is the
-- topmost GUI object under the finger/cursor.
local function ConnectDragObject(Object)
	Object.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch then
			BeginDrag(Input)

			Input.Changed:Connect(function()
				if Input.UserInputState == Enum.UserInputState.End then
					EndDrag(Input)
				end
			end)
		end
	end)
end

ConnectDragObject(Title)
ConnectDragObject(VersionLabel)

UserInputService.InputChanged:Connect(
	function(Input)
		if not Dragging then
			return
		end

		if Input.UserInputType == Enum.UserInputType.MouseMovement
			or Input.UserInputType == Enum.UserInputType.Touch then
			if Input == DragInput
				or Input.UserInputType == Enum.UserInputType.MouseMovement
				then
				UpdateDrag(Input)
			end
		end
	end
)

UserInputService.InputEnded:Connect(
	function(Input)
		EndDrag(Input)
	end
)

--------------------------------------------------
-- CONTENT
--------------------------------------------------

local Content =
	Instance.new(
		"ScrollingFrame"
	)

Content.Size =
	UDim2.new(
		1,
		-14,
		1,
		-56
	)

Content.Position =
	UDim2.fromOffset(
		7,
		53
	)

Content.BackgroundTransparency =
	1

Content.BorderSizePixel =
	0

Content.ScrollBarThickness =
	4

Content.CanvasSize =
	UDim2.fromOffset(
		0,
		0
	)

Content.Parent =
	MainFrame

local ContentLayout =
	Instance.new(
		"UIListLayout"
	)

ContentLayout.Padding =
	UDim.new(
		0,
		7
	)

ContentLayout.SortOrder =
	Enum.SortOrder.LayoutOrder

ContentLayout.Parent =
	Content

ContentLayout:GetPropertyChangedSignal(
		"AbsoluteContentSize"
):Connect(
	function()

		Content.CanvasSize =
			UDim2.fromOffset(
				0,
				ContentLayout.AbsoluteContentSize.Y
				+ 10
			)

	end
)

--------------------------------------------------
-- RECORD SECTION
--------------------------------------------------

local RecordSection =
	Instance.new("Frame")

RecordSection.Size =
	UDim2.new(
		1,
		-2,
		0,
		125
	)

RecordSection.BackgroundColor3 =
	PANEL

RecordSection.Parent =
	Content

AddCorner(
	RecordSection,
	8
)

local RecordTitle =
	CreateLabel(
		RecordSection,
		"Record",
		UDim2.new(
			1,
			-20,
			0,
			20
		),
		UDim2.fromOffset(
			10,
			7
		),
		13,
		TEXT
	)

RecordTitle.Font =
	Enum.Font.GothamBold

local RecordHint =
	CreateLabel(
		RecordSection,
		"Movement + Q / E",
		UDim2.new(
			1,
			-20,
			0,
			16
		),
		UDim2.fromOffset(
			10,
			26
		),
		9,
		SUBTEXT
	)

local NameBox =
	Instance.new("TextBox")

NameBox.Size =
	UDim2.new(
		1,
		-20,
		0,
		29
	)

NameBox.Position =
	UDim2.fromOffset(
		10,
		46
	)

NameBox.BackgroundColor3 =
	INPUT

NameBox.PlaceholderText =
	"Recording name..."

NameBox.PlaceholderColor3 =
	SUBTEXT

NameBox.Text =
	""

NameBox.TextColor3 =
	TEXT

NameBox.TextSize =
	10

NameBox.Font =
	Enum.Font.Gotham

NameBox.ClearTextOnFocus =
	false

NameBox.Parent =
	RecordSection

AddCorner(
	NameBox,
	6
)

local RecordButton =
	CreateButton(
		RecordSection,
		"●  Record",
		UDim2.new(
			0.5,
			-13,
			0,
			32
		),
		UDim2.fromOffset(
			10,
			84
		),
		GREEN
	)

local StopButton =
	CreateButton(
		RecordSection,
		"■  Stop",
		UDim2.new(
			0.5,
			-13,
			0,
			32
		),
		UDim2.new(
			0.5,
			3,
			0,
			84
		),
		RED
	)

StopButton.AutoButtonColor =
	false

StopButton.BackgroundTransparency =
	0.45

--------------------------------------------------
-- SKILL SECTION
--------------------------------------------------

local SkillSection =
	Instance.new("Frame")

SkillSection.Size =
	UDim2.new(
		1,
		-2,
		0,
		100
	)

SkillSection.BackgroundColor3 =
	PANEL

SkillSection.Parent =
	Content

AddCorner(
	SkillSection,
	8
)

local SkillTitle =
	CreateLabel(
		SkillSection,
		"Skills",
		UDim2.new(
			1,
			-20,
			0,
			20
		),
		UDim2.fromOffset(
			10,
			7
		),
		13,
		TEXT
	)

SkillTitle.Font =
	Enum.Font.GothamBold

local QLabel =
	CreateLabel(
		SkillSection,
		"Q",
		UDim2.fromOffset(
			20,
			28
		),
		UDim2.fromOffset(
			10,
			38
		),
		11,
		SUBTEXT
	)

local QButton =
	CreateButton(
		SkillSection,
		QSkillName,
		UDim2.new(
			0.5,
			-18,
			0,
			29
		),
		UDim2.fromOffset(
			30,
			37
		),
		INPUT
	)

local ELabel =
	CreateLabel(
		SkillSection,
		"E",
		UDim2.fromOffset(
			20,
			28
		),
		UDim2.new(
			0.5,
			5,
			0,
			38
		),
		11,
		SUBTEXT
	)

local EButton =
	CreateButton(
		SkillSection,
		ESkillName,
		UDim2.new(
			0.5,
			-18,
			0,
			29
		),
		UDim2.new(
			0.5,
			25,
			0,
			37
		),
		INPUT
	)

--------------------------------------------------
-- SKILL DROPDOWN
--------------------------------------------------

local SkillDropdown =
	Instance.new("Frame")

SkillDropdown.Size =
	UDim2.fromOffset(
		170,
		0
	)

SkillDropdown.BackgroundColor3 =
	Color3.fromRGB(
		22,
		22,
		26
	)

SkillDropdown.Visible =
	false

SkillDropdown.ZIndex =
	20

SkillDropdown.Parent =
	ScreenGui

AddCorner(
	SkillDropdown,
	7
)

local SkillDropdownList =
	Instance.new(
		"ScrollingFrame"
	)

SkillDropdownList.Size =
	UDim2.new(
		1,
		-6,
		1,
		-6
	)

SkillDropdownList.Position =
	UDim2.fromOffset(
		3,
		3
	)

SkillDropdownList.BackgroundTransparency =
	1

SkillDropdownList.BorderSizePixel =
	0

SkillDropdownList.ScrollBarThickness =
	3

SkillDropdownList.ZIndex =
	21

SkillDropdownList.Parent =
	SkillDropdown

local SkillLayout =
	Instance.new(
		"UIListLayout"
	)

SkillLayout.Padding =
	UDim.new(
		0,
		3
	)

SkillLayout.Parent =
	SkillDropdownList

local ChoosingSkill =
	nil

local function GetAvailableSkills()

	local Skills = {}
	local Seen = {}

	local function CheckContainer(
		Container
	)

		if not Container then
			return
		end

		for _, Object in ipairs(
			Container:GetChildren()
		) do

			if Object:IsA("Tool") then

				local Event =
					Object:FindFirstChild(
						"abilityEvent"
					)
					or
					Object:FindFirstChild(
						"spellEvent"
					)

				if Event
					and not Seen[
						Object.Name
					] then

					Seen[
						Object.Name
					] = true

					table.insert(
						Skills,
						Object.Name
					)

				end

			end

		end

	end

	CheckContainer(
		Backpack
	)

	CheckContainer(
		Character
	)

	table.sort(
		Skills
	)

	return Skills

end

local function OpenSkillDropdown(
	Button,
	Key
)

	ChoosingSkill =
		Key

	for _, Child in ipairs(
		SkillDropdownList:GetChildren()
	) do

		if Child:IsA("TextButton") then
			Child:Destroy()
		end

	end

	local Skills =
		GetAvailableSkills()

	for _, SkillName in ipairs(
		Skills
	) do

		local Button2 =
			CreateButton(
				SkillDropdownList,
				SkillName,
				UDim2.new(
					1,
					0,
					0,
					28
				),
				UDim2.fromOffset(
					0,
					0
				),
				INPUT
			)

		Button2.ZIndex =
			22

		Button2.MouseButton1Click:Connect(
			function()

				if ChoosingSkill ==
					"Q" then

					QSkillName =
						SkillName

					QButton.Text =
						SkillName

				elseif ChoosingSkill ==
					"E" then

					ESkillName =
						SkillName

					EButton.Text =
						SkillName

				end

				SkillDropdown.Visible =
					false

				ChoosingSkill =
					nil

			end
		)

	end

	local Count =
		math.max(
			#Skills,
			1
		)

	local Height =
		math.min(
			Count * 31 + 6,
			180
		)

	SkillDropdown.Size =
		UDim2.fromOffset(
			170,
			Height
		)

	local Position =
		Button.AbsolutePosition

	local Size =
		Button.AbsoluteSize

	SkillDropdown.Position =
		UDim2.fromOffset(
			Position.X,
			Position.Y
			+ Size.Y
			+ 4
		)

	SkillDropdown.Visible =
		true

	task.defer(
		function()

			SkillDropdownList.CanvasSize =
				UDim2.fromOffset(
					0,
					SkillLayout.AbsoluteContentSize.Y
					+ 6
				)

		end
	)

end

QButton.MouseButton1Click:Connect(
	function()

		OpenSkillDropdown(
			QButton,
			"Q"
		)

	end
)

EButton.MouseButton1Click:Connect(
	function()

		OpenSkillDropdown(
			EButton,
			"E"
		)

	end
)

--------------------------------------------------
-- SAVED RECORDINGS
--------------------------------------------------

local SavedSection =
	Instance.new("Frame")

SavedSection.Size =
	UDim2.new(
		1,
		-2,
		0,
		245
	)

SavedSection.BackgroundColor3 =
	PANEL

SavedSection.Parent =
	Content

AddCorner(
	SavedSection,
	8
)

local SavedTitle =
	CreateLabel(
		SavedSection,
		"Saved Recordings",
		UDim2.new(
			1,
			-20,
			0,
			20
		),
		UDim2.fromOffset(
			10,
			7
		),
		13,
		TEXT
	)

SavedTitle.Font =
	Enum.Font.GothamBold

local SavedCount =
	CreateLabel(
		SavedSection,
		"0 recordings",
		UDim2.new(
			1,
			-20,
			0,
			16
		),
		UDim2.fromOffset(
			10,
			27
		),
		9,
		SUBTEXT
	)

local SelectedLabel =
	CreateLabel(
		SavedSection,
		"Selected: None",
		UDim2.new(
			1,
			-20,
			0,
			17
		),
		UDim2.fromOffset(
			10,
			44
		),
		10,
		TEXT
	)

SelectedLabel.Font =
	Enum.Font.GothamMedium

--------------------------------------------------
-- RECORDING LIST
--------------------------------------------------

local RecordingList =
	Instance.new(
		"ScrollingFrame"
	)

RecordingList.Size =
	UDim2.new(
		1,
		-20,
		0,
		155
	)

RecordingList.Position =
	UDim2.fromOffset(
		10,
		65
	)

RecordingList.BackgroundColor3 =
	Color3.fromRGB(
		21,
		21,
		25
	)

RecordingList.BorderSizePixel =
	0

RecordingList.ScrollBarThickness =
	4

RecordingList.CanvasSize =
	UDim2.fromOffset(
		0,
		0
	)

RecordingList.Parent =
	SavedSection

AddCorner(
	RecordingList,
	6
)

local RecordingPadding =
	Instance.new(
		"UIPadding"
	)

RecordingPadding.PaddingTop =
	UDim.new(
		0,
		4
	)

RecordingPadding.PaddingBottom =
	UDim.new(
		0,
		4
	)

RecordingPadding.PaddingLeft =
	UDim.new(
		0,
		4
	)

RecordingPadding.PaddingRight =
	UDim.new(
		0,
		4
	)

RecordingPadding.Parent =
	RecordingList

local RecordingLayout =
	Instance.new(
		"UIListLayout"
	)

RecordingLayout.Padding =
	UDim.new(
		0,
		4
	)

RecordingLayout.Parent =
	RecordingList

--------------------------------------------------
-- FORMAT TIME
--------------------------------------------------

local function FormatTime(Time)

	Time =
		Time or 0

	if Time >= 60 then

		local Minutes =
			math.floor(
				Time / 60
			)

		local Seconds =
			Time
			- Minutes * 60

		return string.format(
			"%d:%05.2f",
			Minutes,
			Seconds
		)

	end

	return string.format(
		"%.2fs",
		Time
	)

end

--------------------------------------------------
-- REFRESH RECORDING LIST
--------------------------------------------------

local function RefreshRecordingList()

	--------------------------------------------------
	-- REMOVE OLD ROWS
	--------------------------------------------------

	for _, Child in ipairs(
		RecordingList:GetChildren()
	) do

		if Child:IsA("Frame") then
			Child:Destroy()
		end

	end

	--------------------------------------------------
	-- COUNT
	--------------------------------------------------

	SavedCount.Text =
		tostring(
			#Recordings
		)
		..
		(
			#Recordings == 1
			and " recording"
			or " recordings"
		)

	--------------------------------------------------
	-- SELECTED
	--------------------------------------------------

	if SelectedRecording then

		SelectedLabel.Text =
			"Selected: "
			..
			SelectedRecording.Name

	else

		SelectedLabel.Text =
			"Selected: None"

	end

	--------------------------------------------------
	-- EMPTY STATE
	--------------------------------------------------

	if #Recordings == 0 then

		local Empty =
			CreateLabel(
				RecordingList,
				"No recordings yet",
				UDim2.new(
					1,
					-8,
					0,
					40
				),
				UDim2.fromOffset(
					4,
					4
				),
				10,
				SUBTEXT
			)

		Empty.TextXAlignment =
			Enum.TextXAlignment.Center

		return
	end

	--------------------------------------------------
	-- CREATE EVERY RECORDING
	--------------------------------------------------

	for Index, Recording in ipairs(
		Recordings
	) do

		local IsSelected =
			Recording ==
			SelectedRecording

		local Row =
			Instance.new(
				"Frame"
			)

		Row.Size =
			UDim2.new(
				1,
				0,
				0,
				44
			)

		Row.BackgroundColor3 =
			IsSelected
			and Color3.fromRGB(
				45,
				55,
				75
			)
			or INPUT

		Row.Parent =
			RecordingList

		AddCorner(
			Row,
			6
		)

		if IsSelected then

			AddStroke(
				Row,
				BLUE,
				0.1
			)

		end

		--------------------------------------------------
		-- NUMBER
		--------------------------------------------------

		local Number =
			CreateLabel(
				Row,
				tostring(Index),
				UDim2.fromOffset(
					25,
					44
				),
				UDim2.fromOffset(
					3,
					0
				),
				9,
				SUBTEXT
			)

		Number.TextXAlignment =
			Enum.TextXAlignment.Center

		--------------------------------------------------
		-- NAME
		--------------------------------------------------

		local Name =
			CreateLabel(
				Row,
				Recording.Name,
				UDim2.new(
					1,
					-100,
					0,
					20
				),
				UDim2.fromOffset(
					32,
					3
				),
				10,
				TEXT
			)

		Name.Font =
			Enum.Font.GothamMedium

		--------------------------------------------------
		-- INFO
		--------------------------------------------------

		local Info =
			CreateLabel(
				Row,
				string.format(
					"%s • %d skills",
					FormatTime(
						GetRecordingDuration(
							Recording
						)
					),
					GetSkillCount(
						Recording
					)
				),
				UDim2.new(
					1,
					-100,
					0,
					15
				),
				UDim2.fromOffset(
					32,
					23
				),
				8,
				SUBTEXT
			)

		--------------------------------------------------
		-- CHECK
		--------------------------------------------------

		if IsSelected then

			local Check =
				CreateLabel(
					Row,
					"✓",
					UDim2.fromOffset(
						30,
						44
					),
					UDim2.new(
						1,
						-37,
						0,
						0
					),
					14,
					GREEN
				)

			Check.TextXAlignment =
				Enum.TextXAlignment.Center

		end

		--------------------------------------------------
		-- CLICK
		--------------------------------------------------

		local Click =
			Instance.new(
				"TextButton"
			)

		Click.Size =
			UDim2.new(
				1,
				0,
				1,
				0
			)

		Click.BackgroundTransparency =
			1

		Click.Text =
			""

		Click.ZIndex =
			10

		Click.Parent =
			Row

		Click.MouseButton1Click:Connect(
			function()

				if IsRecording
					or IsReplaying then

					return
				end

				SelectedRecording =
					Recording

				RefreshRecordingList()

				UpdateUI()

			end
		)

	end

	task.defer(
		function()

			RecordingList.CanvasSize =
				UDim2.fromOffset(
					0,
					RecordingLayout.AbsoluteContentSize.Y
					+ 8
				)

		end
	)

end

--------------------------------------------------
-- REPLAY SECTION
--------------------------------------------------

local ReplaySection =
	Instance.new("Frame")

ReplaySection.Size =
	UDim2.new(
		1,
		-2,
		0,
		78
	)

ReplaySection.BackgroundColor3 =
	PANEL

ReplaySection.Parent =
	Content

AddCorner(
	ReplaySection,
	8
)

local ReplayTitle =
	CreateLabel(
		ReplaySection,
		"Replay",
		UDim2.fromOffset(
			100,
			18
		),
		UDim2.fromOffset(
			10,
			6
		),
		12,
		TEXT
	)

ReplayTitle.Font =
	Enum.Font.GothamBold

local ReplayInfo =
	CreateLabel(
		ReplaySection,
		"No recording selected",
		UDim2.new(
			1,
			-20,
			0,
			16
		),
		UDim2.fromOffset(
			10,
			23
		),
		9,
		SUBTEXT
	)

local ReplayButton =
	CreateButton(
		ReplaySection,
		"▶  Replay Selected",
		UDim2.new(
			1,
			-20,
			0,
			29
		),
		UDim2.fromOffset(
			10,
			44
		),
		BLUE
	)

--------------------------------------------------
-- DUNGEON AUTO SECTION
--------------------------------------------------

local DungeonSection = Instance.new("Frame")
DungeonSection.Size = UDim2.new(1, -2, 0, 155)
DungeonSection.BackgroundColor3 = PANEL
DungeonSection.LayoutOrder = 3
DungeonSection.Parent = Content
AddCorner(DungeonSection, 8)

local DungeonTitle = CreateLabel(
	DungeonSection,
	"Dungeon Automation",
	UDim2.new(1, -20, 0, 20),
	UDim2.fromOffset(10, 6),
	12,
	TEXT
)
DungeonTitle.Font = Enum.Font.GothamBold

local DungeonInfo = CreateLabel(
	DungeonSection,
	"Scanning dungeon state...",
	UDim2.new(1, -20, 0, 17),
	UDim2.fromOffset(10, 25),
	8,
	SUBTEXT
)

local AutoStartButton = CreateButton(
	DungeonSection,
	"Auto Start: ON",
	UDim2.new(0.5, -15, 0, 31),
	UDim2.fromOffset(10, 48),
	GREEN
)

local AutoReplayButton = CreateButton(
	DungeonSection,
	"Auto Replay: ON",
	UDim2.new(0.5, -15, 0, 31),
	UDim2.new(0.5, 5, 0, 48),
	GREEN
)

local function UpdateDungeonButtons()
	AutoStartButton.Text = AutoStart and "Auto Start: ON" or "Auto Start: OFF"
	AutoStartButton.BackgroundColor3 = AutoStart and GREEN or Color3.fromRGB(60, 60, 65)
	AutoReplayButton.Text = AutoReplay and "Auto Replay: ON" or "Auto Replay: OFF"
	AutoReplayButton.BackgroundColor3 = AutoReplay and GREEN or Color3.fromRGB(60, 60, 65)
end

AutoStartButton.MouseButton1Click:Connect(function()
	AutoStart = not AutoStart
	if AutoStart then
		LastAutoStartFire = 0
		FireAutoStart()
	end
	UpdateDungeonButtons()
	-- Settings must be cloud-persistent even when Cloud Auto Save is OFF.
	SaveCloud(true)
end)

AutoReplayButton.MouseButton1Click:Connect(function()
	AutoReplay = not AutoReplay
	if not AutoReplay then
		LastAutoReplayKey = nil
	end
	UpdateDungeonButtons()
	-- Settings must be cloud-persistent even when Cloud Auto Save is OFF.
	SaveCloud(true)
end)

local AutoSaveButton = CreateButton(
	DungeonSection,
	"Cloud Auto Save: ON",
	UDim2.new(0.5, -15, 0, 31),
	UDim2.fromOffset(10, 87),
	GREEN
)

local CloudLoadButton = CreateButton(
	DungeonSection,
	"Load Cloud",
	UDim2.new(0.5, -15, 0, 31),
	UDim2.new(0.5, 5, 0, 87),
	BLUE
)

local function UpdateCloudButtons()
	AutoSaveButton.Text = AutoSave and "Cloud Auto Save: ON" or "Cloud Auto Save: OFF"
	AutoSaveButton.BackgroundColor3 = AutoSave and GREEN or Color3.fromRGB(60, 60, 65)
end

AutoSaveButton.MouseButton1Click:Connect(function()
	AutoSave = not AutoSave
	UpdateCloudButtons()
	SaveCloud(true)
end)

CloudLoadButton.MouseButton1Click:Connect(function()
	LoadCloud()
end)

UpdateDungeonButtons()
UpdateCloudButtons()

-- Show cloud status using the existing status label once the UI is ready.
CloudUIRefresh = function()
	RefreshRecordingList()
	UpdateDungeonButtons()
	UpdateCloudButtons()
	UpdateUI()
end

-- Automatically restore cloud recordings/settings every time the script starts.
-- The dungeon automation loop is blocked until this finishes, so saved OFF
-- settings cannot be overwritten by the local defaults.
task.delay(0.25, function()
	if not CloudLoaded then
		LoadCloud()
	end
end)

--------------------------------------------------
-- STATUS
--------------------------------------------------

local StatusSection =
	Instance.new("Frame")

StatusSection.Size =
	UDim2.new(
		1,
		-2,
		0,
		65
	)

StatusSection.BackgroundColor3 =
	Color3.fromRGB(
		22,
		22,
		26
	)

StatusSection.Parent =
	Content

AddCorner(
	StatusSection,
	8
)

local StatusMain =
	CreateLabel(
		StatusSection,
		"Ready",
		UDim2.new(
			1,
			-20,
			0,
			20
		),
		UDim2.fromOffset(
			10,
			6
		),
		12,
		TEXT
	)

StatusMain.Font =
	Enum.Font.GothamMedium

local StatusDetails =
	CreateLabel(
		StatusSection,
		"Create a recording to get started",
		UDim2.new(
			1,
			-20,
			0,
			18
		),
		UDim2.fromOffset(
			10,
			28
		),
		8,
		SUBTEXT
	)

--------------------------------------------------
-- RECORDING INDICATOR
--------------------------------------------------

task.spawn(
	function()

		local Toggle =
			false

		while true do

			if IsRecording then

				Toggle =
					not Toggle

				StatusDot.BackgroundTransparency =
					Toggle
					and 0
					or 0.55

				task.wait(
					0.45
				)

			else

				StatusDot.BackgroundTransparency =
					0

				task.wait(
					0.2
				)

			end

		end

	end
)

--------------------------------------------------
-- UPDATE UI
--------------------------------------------------

function UpdateUI()

	if IsRecording then

		local Duration =
			CurrentRecording
			and (
				os.clock()
				- CurrentRecording.StartTime
			)
			or 0

		StatusBadge.BackgroundColor3 =
			Color3.fromRGB(
				75,
				30,
				30
			)

		StatusDot.BackgroundColor3 =
			RED

		StatusText.Text =
			"REC "
			..
			FormatTime(
				Duration
			)

		StatusMain.Text =
			"● Recording..."

		StatusMain.TextColor3 =
			RED

		StatusDetails.Text =
			string.format(
				"%d points • %d skills",
				CurrentRecording
					and #CurrentRecording.Movement
					or 0,

				CurrentRecording
					and #CurrentRecording.Actions
					or 0
			)

		RecordButton.Text =
			"●  Recording"

		RecordButton.BackgroundColor3 =
			Color3.fromRGB(
				125,
				45,
				45
			)

		RecordButton.AutoButtonColor =
			false

		StopButton.BackgroundColor3 =
			RED

		StopButton.BackgroundTransparency =
			0

		StopButton.AutoButtonColor =
			true

		ReplayButton.BackgroundColor3 =
			Color3.fromRGB(
				60,
				60,
				65
			)

		ReplayButton.AutoButtonColor =
			false

	elseif IsReplaying then

		StatusBadge.BackgroundColor3 =
			Color3.fromRGB(
				40,
				45,
				70
			)

		StatusDot.BackgroundColor3 =
			BLUE

		StatusText.Text =
			"PLAYING"

		StatusMain.Text =
			"▶ Replaying..."

		StatusMain.TextColor3 =
			BLUE

		if SelectedRecording then

			StatusDetails.Text =
				SelectedRecording.Name

		end

		RecordButton.BackgroundColor3 =
			Color3.fromRGB(
				60,
				60,
				65
			)

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
			"▶  Replaying..."

		ReplayButton.BackgroundColor3 =
			Color3.fromRGB(
				60,
				60,
				65
			)

		ReplayButton.AutoButtonColor =
			false

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
					"%s • %d skills",
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
			"●  Record"

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
				"▶  Replay: "
				..
				SelectedRecording.Name

			ReplayButton.BackgroundColor3 =
				BLUE

			ReplayButton.AutoButtonColor =
				true

		else

			ReplayButton.Text =
				"▶  Select a recording"

			ReplayButton.BackgroundColor3 =
				Color3.fromRGB(
					60,
					60,
					65
				)

			ReplayButton.AutoButtonColor =
				false

		end

	end

	if SelectedRecording then

		ReplayInfo.Text =
			string.format(
				"%s • %s • %d skills",

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
-- RECORD BUTTON
--------------------------------------------------

RecordButton.MouseButton1Click:Connect(
	function()

		if IsRecording
			or IsReplaying then

			return
		end

		local Name =
			NameBox.Text

		StartRecording(
			Name
		)

		NameBox.Text =
			""

		RefreshRecordingList()

		UpdateUI()

	end
)

--------------------------------------------------
-- STOP BUTTON
--------------------------------------------------

StopButton.MouseButton1Click:Connect(
	function()

		if IsRecording then

			StopRecording()

			-- THIS NOW REFRESHES EVERY TIME
			RefreshRecordingList()

			UpdateUI()

			return
		end

		if IsReplaying then

			StopReplay()

			UpdateUI()

			return
		end

	end
)

--------------------------------------------------
-- REPLAY BUTTON
--------------------------------------------------

ReplayButton.MouseButton1Click:Connect(
	function()

		if IsRecording
			or IsReplaying then

			return
		end

		if not SelectedRecording then
			return
		end

		StartReplay()

		UpdateUI()

	end
)

--------------------------------------------------
-- DUNGEON STATE SCANNER
--------------------------------------------------

task.spawn(function()
	while true do
		-- NEVER run auto-start/auto-replay until the cloud settings have loaded.
		-- This prevents the LocalScript defaults from firing before the saved
		-- Auto Start / Auto Replay values arrive from Cloudflare.
		if not CloudLoaded then
			task.wait(DUNGEON_SCAN_INTERVAL)
			continue
		end

		if CloudLoadFailed then
			task.wait(DUNGEON_SCAN_INTERVAL)
			continue
		end

		local State = GetDungeonState()

		local Name = State.dungeonName
		if Name == nil or tostring(Name) == "" then
			Name = "Unknown"
		end

		DungeonInfo.Text = string.format(
			"Name: %s  •  Progress: %s  •  Started: %s",
			tostring(Name),
			tostring(State.dungeonProgress or "unknown"),
			tostring(State.dungeonStarted == true)
		)

		if AutoStart and State.dungeonStarted ~= true then
			FireAutoStart()
		end

		if AutoReplay then
			FireAutoReplay(State)
		end

		task.wait(DUNGEON_SCAN_INTERVAL)
	end
end)

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

local LastUIUpdate =
	0

RunService.Heartbeat:Connect(
	function()

		if IsRecording then

			RecordMovement()

		end

		if IsReplaying
			and MovementMode ==
			"Pathfinding" then

			UpdatePathMovement()

		end

		if os.clock()
			- LastUIUpdate >=
			0.1 then

			LastUIUpdate =
				os.clock()

			UpdateUI()

		end

	end
)

--------------------------------------------------
-- INITIALIZE
--------------------------------------------------

RefreshRecordingList()

UpdateUI()

print(
	"[Replay System] Loaded "
	.. VERSION
)
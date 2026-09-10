--// Replay System v3.6.5 fix spawn
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

local Remotes = ReplicatedStorage:FindFirstChild("remotes")
local AbilityUsed = Remotes and Remotes:FindFirstChild("abilityUsed") or nil
local ChangeStartValue = Remotes and Remotes:FindFirstChild("changeStartValue") or nil
local ReplayDungeon = Remotes and Remotes:FindFirstChild("replayDungeon") or nil

-- Do not block UI creation if a remote is temporarily unavailable.
task.spawn(function()
	while not Remotes do
		Remotes = ReplicatedStorage:FindFirstChild("remotes")
		if Remotes then break end
		task.wait(0.5)
	end
	while Remotes and (not AbilityUsed or not ChangeStartValue or not ReplayDungeon) do
		AbilityUsed = AbilityUsed or Remotes:FindFirstChild("abilityUsed")
		ChangeStartValue = ChangeStartValue or Remotes:FindFirstChild("changeStartValue")
		ReplayDungeon = ReplayDungeon or Remotes:FindFirstChild("replayDungeon")
		if AbilityUsed and ChangeStartValue and ReplayDungeon then break end
		task.wait(0.5)
	end
end)

--------------------------------------------------
-- DUNGEON AUTO SYSTEM
--------------------------------------------------

local AutoStart = true
local AutoReplay = true
local AutoReplayRecording = true
local AutoReplayRecordingName = nil
local AutoSave = true
local RecordRespawns = true

local LastAutoStartFire = 0
local LastAutoReplayKey = nil
local AutoStartPending = false
local AutoReplayRecordingAt = nil
local AutoReplayRecordingRetryCount = 0
local AutoReplayRecordingDungeonKey = nil
local LastDungeonStartedState = nil
local DungeonStartCycle = 0
local AUTO_START_COOLDOWN = 3
local AUTO_REPLAY_RECORDING_DELAY = 6
local DUNGEON_SCAN_INTERVAL = 0.35

local HIGH_PING_THRESHOLD = 0.30
local NORMAL_PING_THRESHOLD = 0.18
local HIGH_PING_SERVER_REPLAY_DELAY = 15

local HighPingSince = nil
local HighPingServerReplayFired = false

local function GetCurrentPing()
	local Success, Ping = pcall(function()
		return Player:GetNetworkPing()
	end)

	if Success and type(Ping) == "number" then
		return Ping
	end

	return 0
end

local function IsPingHigh()
	return GetCurrentPing() >= HIGH_PING_THRESHOLD
end

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
	local Now = os.clock()

	if Now - LastAutoStartFire < AUTO_START_COOLDOWN then
		return
	end

	local Success, ErrorMessage = pcall(function()
		if not ChangeStartValue then
			error("changeStartValue remote is unavailable")
		end
		ChangeStartValue:FireServer()
	end)

	if Success then
		LastAutoStartFire = Now
		AutoStartPending = true

		-- Saved-recording Auto Replay is intentionally separate from the
		-- dungeon replayDungeon automation. It starts exactly 6 seconds
		-- after Auto Start successfully fires.
		if AutoReplayRecording then
			AutoReplayRecordingAt = Now + AUTO_REPLAY_RECORDING_DELAY
			AutoReplayRecordingRetryCount = 0
		end

		print("[Replay] Auto Start -> changeStartValue")
		if AutoReplayRecording then
			print("[Replay] Auto Replay Recording scheduled in 6 seconds")
		end
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
		if not ReplayDungeon then
			error("replayDungeon remote is unavailable")
		end
		ReplayDungeon:FireServer(Payload)
	end)

	if Success then
		LastAutoReplayKey = ReplayKey
		print("[Replay] Auto Replay FIRED ->", DungeonName)
	else
		warn("[Replay] Auto Replay error:", ErrorMessage)
	end
end

local function FireHighPingDungeonReplay(State)
	-- If ping stays bad for a long time before Auto Start can happen,
	-- use replayDungeon as a recovery/requeue attempt instead of waiting forever.
	local DungeonName = State.dungeonName
	if DungeonName == nil or tostring(DungeonName) == "" then
		warn("[Replay] High ping recovery: dungeonName is unavailable.")
		return
	end

	DungeonName = tostring(DungeonName)

	local Hardcore = State.hardcore == true
	local DungeonStarted = State.dungeonStarted
	if DungeonStarted == nil then DungeonStarted = false end

	local DungeonFinished = State.dungeonFinished
	if DungeonFinished == nil then DungeonFinished = false end

	local IsHardcore = State.isHardcore
	if IsHardcore == nil then IsHardcore = Hardcore end

	local FightingBoss = State.fightingBoss
	if FightingBoss == nil then FightingBoss = false end

	local Payload = {
		dungeonProgress = "bossKilled",
		dungeonStarted = DungeonStarted == true,
		dungeonFinished = DungeonFinished == true,
		hardcore = Hardcore,
		dungeonName = DungeonName,
		isHardcore = IsHardcore == true,
		fightingBoss = FightingBoss == true
	}

	local Success, ErrorMessage = pcall(function()
		if not ReplayDungeon then
			error("replayDungeon remote is unavailable")
		end
		ReplayDungeon:FireServer(Payload)
	end)

	if Success then
		HighPingServerReplayFired = true
		AutoStartPending = false
		AutoReplayRecordingAt = nil
		LastAutoReplayKey = nil
		print("[Replay] High ping persisted for " .. HIGH_PING_SERVER_REPLAY_DELAY .. "s -> replayDungeon:", DungeonName)
	else
		warn("[Replay] High ping recovery error:", ErrorMessage)
	end
end

--------------------------------------------------
-- CONFIG
--------------------------------------------------

local VERSION = "v3.6.6"

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

local IsRecording = false
local IsReplaying = false
local CurrentRecording = nil
local Recordings = {}
local SelectedRecording = nil

local ConnectedDeathHumanoid = nil

local function ConnectRespawnRecording(HumanoidToWatch)
	if not HumanoidToWatch or ConnectedDeathHumanoid == HumanoidToWatch then
		return
	end

	ConnectedDeathHumanoid = HumanoidToWatch

	HumanoidToWatch.Died:Connect(function()
		-- Capture the respawn at death time, not CharacterAdded time.
		-- CharacterAdded fires only after Roblox's respawn delay.
		if not IsRecording or not CurrentRecording or not RecordRespawns then
			return
		end

		local RespawnTime = os.clock() - CurrentRecording.StartTime
		table.insert(CurrentRecording.Actions, {
			Time = RespawnTime,
			ActionType = "Respawn"
		})

		print("[Replay] Recorded respawn at", RespawnTime)
	end)
end

local function SetupCharacter(NewCharacter)

	Character = NewCharacter

	Humanoid = Character:WaitForChild("Humanoid")
	RootPart = Character:WaitForChild("HumanoidRootPart")

	ConnectRespawnRecording(Humanoid)

end

if Player.Character then
	SetupCharacter(Player.Character)
end

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
		QSkillName = Recording.QSkillName,
		ESkillName = Recording.ESkillName,
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
		local AP = Action.Position
		table.insert(Out.Actions, {
			Time = Action.Time or 0,
			ActionType = Action.ActionType or "Skill",
			Key = Action.Key,
			SkillName = Action.SkillName,
			Position = AP and {AP.X, AP.Y, AP.Z} or nil,
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
		QSkillName = Recording.QSkillName and tostring(Recording.QSkillName) or nil,
		ESkillName = Recording.ESkillName and tostring(Recording.ESkillName) or nil,
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
		local ap = Action.Position
		local actionPosition = nil
		if type(ap) == "table" then
			actionPosition = Vector3.new(
				tonumber(ap[1]) or 0,
				tonumber(ap[2]) or 0,
				tonumber(ap[3]) or 0
			)
		end

		table.insert(Out.Actions, {
			Time = tonumber(Action.Time) or 0,
			ActionType = Action.ActionType or "Skill",
			Key = Action.Key,
			SkillName = Action.SkillName,
			Position = actionPosition,
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
			autoReplayRecording = AutoReplayRecording,
			autoReplayRecordingName = AutoReplayRecordingName,
			autoSave = AutoSave,
			recordRespawns = RecordRespawns,
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
			if settings.autoReplayRecording ~= nil then AutoReplayRecording = settings.autoReplayRecording == true end
			if settings.autoReplayRecordingName ~= nil and tostring(settings.autoReplayRecordingName) ~= "" then
				AutoReplayRecordingName = tostring(settings.autoReplayRecordingName)
			else
				AutoReplayRecordingName = nil
			end
			if settings.autoSave ~= nil then AutoSave = settings.autoSave == true end
		if settings.recordRespawns ~= nil then RecordRespawns = settings.recordRespawns == true end

			SelectedRecording = nil
			if #Recordings > 0 then
				SelectedRecording = Recordings[1]
			end

			-- Restore the exact recording assigned to Auto Replay Recording.
			if AutoReplayRecordingName then
				local FoundAutoReplayRecording = false
				for _, Recording in ipairs(Recordings) do
					if tostring(Recording.Name) == tostring(AutoReplayRecordingName) then
						AutoReplayRecordingName = Recording.Name
						FoundAutoReplayRecording = true
						break
					end
				end
				if not FoundAutoReplayRecording then
					AutoReplayRecordingName = nil
				end
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
local ReplayStartPositioning = false

local LastRecordTime = 0

-- Respawn/replay synchronization
local ReplayRespawnPending = false
local ReplayRespawnIndex = nil
-- Combined into a single table (instead of two separate top-level locals)
-- to stay under Luau's 200 local-register limit for the main chunk.
local ReplayState = {
	RespawnTime = nil,
	ActiveRecording = nil,

	-- While a character is dead, Roblox keeps it around (ragdolled) for a
	-- moment before the respawn actually happens. RecordMovement() has no
	-- way to know a death occurred, so it keeps sampling the corpse's
	-- frozen position during that window -- the recording ends up with a
	-- short run of movement points sitting at the death location before
	-- it jumps to the real post-respawn position. This tolerance is used
	-- to skip forward past that frozen cluster to the first point that
	-- matches where the replaying character actually is after respawning.
	PositionMatchDistance = 8,
}

-- Combines a time-based lookup (reliable, keeps the correct ordering
-- through multiple deaths) with a scoped, forward-only position check
-- (skips past any movement points frozen at the death location while the
-- character was waiting to respawn). Never searches backward, so it can
-- never rewind into an earlier point in the recording.
function ReplayState.FindResumeIndex(Recording, RespawnTime, CurrentPosition)

	if not Recording
		or not Recording.Movement
		or #Recording.Movement == 0 then

		return 1
	end

	local Movement = Recording.Movement

	local TimeIndex = nil

	if RespawnTime then
		for MovementIndex, Point in ipairs(Movement) do
			if (Point.Time or 0) >= RespawnTime then
				TimeIndex = MovementIndex
				break
			end
		end
	end

	TimeIndex = TimeIndex or 1

	if CurrentPosition then
		for MovementIndex = TimeIndex, #Movement do
			local Point = Movement[MovementIndex]

			if Point.Position
				and (Point.Position - CurrentPosition).Magnitude
					<= ReplayState.PositionMatchDistance then

				return MovementIndex
			end
		end
	end

	return TimeIndex

end

local RecordingRespawnPending = false

local SkillActionIndex = 1
local SKILL_POSITION_TOLERANCE = 3.5

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

		if not AbilityUsed then
			error("abilityUsed remote is unavailable")
		end
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

		QSkillName = QSkillName,
		ESkillName = ESkillName,

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

	-- Don't log movement while dead/ragdolled and waiting to respawn.
	-- Otherwise this keeps sampling the corpse's frozen position for the
	-- whole respawn delay, baking a "detour to the death spot" into the
	-- recording that replay would otherwise have to path through later.
	if not RootPart.Parent then
		return
	end

	if not Humanoid or Humanoid.Health <= 0 then
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

					Position = RootPart and RootPart.Position or nil,

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

					Position = RootPart and RootPart.Position or nil,

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

	for Index, Action in ipairs(
		Recording.Actions
	) do

		if not Action._Replayed
			and Action.Time <= NewTime then

			if Action.ActionType ==
				"Skill" then

				local ShouldFire = false

				-- New recordings store the exact position where the skill
				-- was pressed. Once replay reaches the recorded timestamp,
				-- wait until the character actually reaches that position.
				-- This prevents skills from firing early when movement is
				-- temporarily behind the replay clock.
				if Action.Position and RootPart then
					local Distance =
						(RootPart.Position - Action.Position).Magnitude

					ShouldFire =
						Distance <= SKILL_POSITION_TOLERANCE
				else
					-- Old cloud recordings do not have a position anchor,
					-- so they continue using the original time-based replay.
					ShouldFire = Action.Time > OldTime
				end
				if ShouldFire then

					local SavedSkillName = Action.SkillName

					if Action.Key == "q" and Recording.QSkillName then
						SavedSkillName = Recording.QSkillName
					elseif Action.Key == "e" and Recording.ESkillName then
						SavedSkillName = Recording.ESkillName
					end

					if ReplaySkill(
						Action.Key,
						SavedSkillName
					) then
						Action._Replayed = true
					end

				end

			elseif Action.ActionType == "Respawn"
				and Action.Time > OldTime
				and Action.Time <= NewTime
			then

				if Humanoid
					and Humanoid.Parent
					and Humanoid.Health > 0 then

					-- Remember the exact recorded death time. After the new
					-- character spawns, replay resumes AFTER this action instead
					-- of finding a nearby point that could be before the death.
					ReplayState.RespawnTime = Action.Time or 0

					pcall(function()
						Humanoid.Health = 0
					end)

					-- Mark it immediately so the same respawn action can never
					-- be fired again after CharacterAdded.
					Action._Replayed = true

				end

			end

		end

	end

end

--------------------------------------------------
-- REPLAY MOVEMENT
--------------------------------------------------

local function WaitForNormalPing()
	while IsReplaying and IsPingHigh() do
		task.wait(0.1)
	end
	return IsReplaying
end

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

	for _, Action in ipairs(Recording.Actions or {}) do
		Action._Replayed = nil
	end

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

	-- Tracks the replay clock as of the last frame the character was alive.
	-- Real (unscripted) deaths -- e.g. the bot actually dying in combat --
	-- never set ReplayState.RespawnTime via a recorded "Respawn" action, so
	-- without this, resume falls back to FindNearestMovementIndex, which is
	-- unreliable: Roblox always respawns at a fixed spawn point, not at the
	-- death location, so proximity search tends to snap back to whichever
	-- recorded point is nearest that spawn pad (often near the very start
	-- of the recording) instead of continuing where playback left off.
	local LastKnownReplayTime =
		StartTime

	while IsReplaying do

		-- High ping can make server movement/ability replication arrive late.
		-- Freeze the replay clock while latency is high so recorded actions are
		-- not consumed early. The replay resumes when ping returns to normal.
		if IsPingHigh() then
			local PingWaitStart = os.clock()
			print(string.format("[Replay] High ping (%.0f ms) - pausing replay", GetCurrentPing() * 1000))
			while IsReplaying and GetCurrentPing() >= NORMAL_PING_THRESHOLD do
				task.wait(0.1)
			end
			if not IsReplaying then
				break
			end
			RealStart += os.clock() - PingWaitStart
			print(string.format("[Replay] Ping normal (%.0f ms) - resuming replay", GetCurrentPing() * 1000))
		end

		if not Character
			or not Character.Parent
			or not Humanoid
			or not Humanoid.Parent
			or not RootPart
			or not RootPart.Parent
			or Humanoid.Health <= 0 then

			-- Record where we were in the recording at the moment of death,
			-- even if this death was not a scripted Respawn action (e.g. the
			-- bot actually died in combat). This guarantees CharacterAdded
			-- always has a reliable time-based resume point and never has to
			-- fall back to physical-proximity matching.
			if not ReplayState.RespawnTime then
				ReplayState.RespawnTime = LastKnownReplayTime
			end

			-- IMPORTANT: do not let replay time continue while dead.
			-- Otherwise all Q/E actions can be consumed before respawn.
			task.wait(0.1)
			continue
		end

		-- A new character has spawned. Resume the replay from the
		-- movement point AFTER the recorded respawn time. Do not use
		-- physical proximity here because the spawn location can be near
		-- an earlier point in the recording, which would replay the same
		-- Respawn action again and cause an infinite reset loop.
		if ReplayRespawnPending then
			local ResumeIndex = ReplayRespawnIndex

			-- The actual moment of death/respawn -- NOT the coarser resume
			-- movement point below -- is the correct cutoff for deciding
			-- which actions still need to be replayed. Movement points are
			-- only sampled periodically, so the nearest one at/after death
			-- can land noticeably later than the death itself. Any skill
			-- the original player cast in that gap (e.g. right after
			-- respawning, before the next movement sample) has a Time
			-- earlier than the movement point but is still owed a replay.
			local ActionResetAnchorTime = ReplayState.RespawnTime

			if not ResumeIndex and ReplayState.RespawnTime then
				ResumeIndex = ReplayState.FindResumeIndex(
					Recording,
					ReplayState.RespawnTime,
					RootPart.Position
				)
			end

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
			LastKnownReplayTime = StartTime
			RealStart = os.clock()

			ClearPath()
			MovementMode = "MoveTo"
			CurrentTarget = nil
			LastMoveCommand = 0
			LastStuckCheck = 0
			LastStuckPosition = RootPart.Position
			StuckStartTime = os.clock()

			-- Fall back to StartTime only if we never had a precise death
			-- time to begin with (e.g. FindNearestMovementIndex was used).
			ActionResetAnchorTime = ActionResetAnchorTime or StartTime

			for _, Action in ipairs(Recording.Actions or {}) do
				Action._Replayed = (Action.Time or 0) < ActionResetAnchorTime
			end

			ReplayRespawnPending = false
			ReplayRespawnIndex = nil
			ReplayState.RespawnTime = nil

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

		-- Character is alive and this frame completed normally, so this is
		-- a good known-safe point to resume from if death happens later.
		LastKnownReplayTime =
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

	ReplayState.ActiveRecording = nil
	ReplayRespawnPending = false
	ReplayRespawnIndex = nil
	ReplayState.RespawnTime = nil

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
-- WAIT FOR REPLAY START POSITION
--------------------------------------------------

local function WaitForReplayStartPosition(Recording)
	if not Recording
		or not Recording.Movement
		or #Recording.Movement == 0 then
		return false
	end

	local FirstPoint = Recording.Movement[1]
	if not FirstPoint or not FirstPoint.Position then
		return false
	end

	local TargetPosition = FirstPoint.Position
	local StartWait = os.clock()
	local LastDirectMove = 0
	local LastPathTry = 0
	local PositioningPath = nil
	local PositioningWaypoints = {}
	local PositioningWaypointIndex = 1

	while ReplayStartPositioning and os.clock() - StartWait < 30 do
		if not Character
			or not Character.Parent
			or not Humanoid
			or not Humanoid.Parent
			or not RootPart
			or not RootPart.Parent
			or Humanoid.Health <= 0 then
			task.wait(0.05)
			continue
		end

		local Distance = (RootPart.Position - TargetPosition).Magnitude
		if Distance <= TARGET_REACHED_DISTANCE then
			return true
		end

		if PositioningPath and PositioningWaypointIndex <= #PositioningWaypoints then
			local Waypoint = PositioningWaypoints[PositioningWaypointIndex]

			if (RootPart.Position - Waypoint.Position).Magnitude <= TARGET_REACHED_DISTANCE then
				PositioningWaypointIndex += 1
				Waypoint = PositioningWaypoints[PositioningWaypointIndex]
			end

			if Waypoint then
				if Waypoint.Action == Enum.PathWaypointAction.Jump then
					Humanoid.Jump = true
				end
				Humanoid:MoveTo(Waypoint.Position)
			end
		else
			PositioningPath = nil
			PositioningWaypoints = {}
			PositioningWaypointIndex = 1

			if os.clock() - LastPathTry >= PATH_RECALCULATE_DELAY then
				LastPathTry = os.clock()

				local Path = PathfindingService:CreatePath({
					AgentRadius = AGENT_RADIUS,
					AgentHeight = AGENT_HEIGHT,
					AgentCanJump = true,
					WaypointSpacing = WAYPOINT_SPACING
				})

				local Success = pcall(function()
					Path:ComputeAsync(RootPart.Position, TargetPosition)
				end)

				if Success and Path.Status == Enum.PathStatus.Success then
					local Waypoints = Path:GetWaypoints()
					if #Waypoints >= 2 then
						PositioningPath = Path
						PositioningWaypoints = Waypoints
						PositioningWaypointIndex = 2
					end
				end
			end

			if not PositioningPath and os.clock() - LastDirectMove >= MOVETO_REFRESH then
				Humanoid:MoveTo(TargetPosition)
				LastDirectMove = os.clock()
			end
		end

		task.wait()
	end

	return false
end

--------------------------------------------------
-- START REPLAY
--------------------------------------------------

local function StartReplay(RecordingOverride)

	if IsRecording
		or IsReplaying then

		return
	end

	local RecordingToPlay = RecordingOverride or SelectedRecording

	if not RecordingToPlay then

		warn(
			"[Replay] No recording selected"
		)

		return
	end

	if not RecordingToPlay.Movement
		or #RecordingToPlay.Movement == 0 then

		return
	end

	if ReplayStartPositioning then
		return
	end

	ReplayMovementIndex =
		1

	ReplayState.ActiveRecording = RecordingToPlay
	ReplayRespawnPending = false
	ReplayRespawnIndex = nil
	ReplayState.RespawnTime = nil

	ReplayStartPositioning = true

	task.spawn(function()
		local Ready = WaitForReplayStartPosition(RecordingToPlay)

		ReplayStartPositioning = false

		if not Ready then
			warn("[Replay] Could not reach the recording's first position")
			return
		end

		if IsRecording or IsReplaying then
			return
		end

		ReplayMovementIndex = 1
		ReplayMovement(RecordingToPlay)
	end)

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

	ReplayState.ActiveRecording = nil
	ReplayRespawnPending = false
	ReplayRespawnIndex = nil
	ReplayState.RespawnTime = nil

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

		RecordingRespawnPending = false

		if not IsReplaying then
			return
		end

		local ReplayRecording = ReplayState.ActiveRecording
		if not ReplayRecording then
			return
		end

		-- Wait for the new character and its skill tools to finish spawning.
		task.wait(0.75)

		if not RootPart or not RootPart.Parent then
			return
		end

		local ResumeIndex = nil

		if ReplayState.RespawnTime then
			ResumeIndex = ReplayState.FindResumeIndex(
				ReplayRecording,
				ReplayState.RespawnTime,
				RootPart.Position
			)
		end

		if not ResumeIndex then
			ResumeIndex = FindNearestMovementIndex(
				ReplayRecording,
				RootPart.Position
			)
		end

		ReplayMovementIndex = ResumeIndex
		ReplayRespawnIndex = ResumeIndex

		ReplayRespawnPending = true

		print(
			"[Replay] Respawn detected. Resume point:",
			ResumeIndex
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

-- Defensive UI settings: keep the replay panel visible even if another
-- PlayerGui is using a high DisplayOrder or the Roblox top-bar inset changes.
ScreenGui.Enabled = true
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999
ScreenGui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling

-- Scoped in a do...end block so PlayerGui/ExistingGui free their registers
-- immediately instead of staying live for the rest of the script (the UI
-- section below already uses close to Luau's 200 local-register limit).
do
	local PlayerGui = Player:WaitForChild("PlayerGui")

	-- Prevent duplicate copies of the UI from stacking when the script is
	-- re-executed without restarting the character.
	for _, ExistingGui in ipairs(PlayerGui:GetChildren()) do
		if ExistingGui ~= ScreenGui
			and ExistingGui:IsA("ScreenGui")
			and ExistingGui.Name == "ReplaySystemUI" then
			ExistingGui:Destroy()
		end
	end

	ScreenGui.Parent = PlayerGui
end

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
		0,
		18,
		0.5,
		-260
	)

MainFrame.BackgroundColor3 =
	BG
MainFrame.Visible = true
MainFrame.Active = true
MainFrame.ZIndex = 1

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
Content.Visible = true
Content.ZIndex = 2

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
		270
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
-- DELETE RECORDING CONFIRMATION
--------------------------------------------------

local UpdateAutoReplayCurrentButton
local RefreshAutoReplayDropdown

local DeleteConfirmFrame = Instance.new("Frame")
DeleteConfirmFrame.Size = UDim2.fromOffset(290, 145)
DeleteConfirmFrame.AnchorPoint = Vector2.new(0.5, 0.5)
DeleteConfirmFrame.Position = UDim2.fromScale(0.5, 0.5)
DeleteConfirmFrame.BackgroundColor3 = PANEL
DeleteConfirmFrame.BorderSizePixel = 0
DeleteConfirmFrame.Visible = false
DeleteConfirmFrame.ZIndex = 100
DeleteConfirmFrame.Parent = ScreenGui
AddCorner(DeleteConfirmFrame, 10)
AddStroke(DeleteConfirmFrame, RED, 0.15)

local DeleteConfirmTitle = CreateLabel(
	DeleteConfirmFrame,
	"Delete Recording?",
	UDim2.new(1, -24, 0, 24),
	UDim2.fromOffset(12, 12),
	14,
	TEXT
)
DeleteConfirmTitle.Font = Enum.Font.GothamBold
DeleteConfirmTitle.ZIndex = 101

local DeleteConfirmText = CreateLabel(
	DeleteConfirmFrame,
	"Are you sure you want to delete this recording?",
	UDim2.new(1, -24, 0, 42),
	UDim2.fromOffset(12, 40),
	9,
	SUBTEXT
)
DeleteConfirmText.TextWrapped = true
DeleteConfirmText.ZIndex = 101

local DeleteConfirmCancel = CreateButton(
	DeleteConfirmFrame,
	"Cancel",
	UDim2.fromOffset(124, 31),
	UDim2.fromOffset(12, 101),
	INPUT
)
DeleteConfirmCancel.ZIndex = 101

local DeleteConfirmYes = CreateButton(
	DeleteConfirmFrame,
	"Delete",
	UDim2.fromOffset(124, 31),
	UDim2.fromOffset(154, 101),
	RED
)
DeleteConfirmYes.ZIndex = 101

local PendingDeleteRecording = nil

local function CloseDeleteConfirmation()
	PendingDeleteRecording = nil
	DeleteConfirmFrame.Visible = false
end

local function OpenDeleteConfirmation(Recording)
	if not Recording then
		return
	end

	PendingDeleteRecording = Recording
	DeleteConfirmTitle.Text = "Delete Recording?"
	DeleteConfirmText.Text = 'Are you sure you want to delete "' .. tostring(Recording.Name) .. '"? This cannot be undone.'
	DeleteConfirmFrame.Visible = true
end

DeleteConfirmCancel.MouseButton1Click:Connect(CloseDeleteConfirmation)

DeleteConfirmYes.MouseButton1Click:Connect(function()
	local Recording = PendingDeleteRecording
	CloseDeleteConfirmation()

	if not Recording then
		return
	end

	for Index, SavedRecording in ipairs(Recordings) do
		if SavedRecording == Recording then
			table.remove(Recordings, Index)
			break
		end
	end

	-- Keep both recording selectors valid after deletion.
	if SelectedRecording == Recording then
		SelectedRecording = Recordings[1]
	end

	if AutoReplayRecordingName and tostring(AutoReplayRecordingName) == tostring(Recording.Name) then
		AutoReplayRecordingName = nil
		AutoReplayRecordingAt = nil
	end

	RefreshRecordingList()
	if RefreshAutoReplayDropdown then
		RefreshAutoReplayDropdown()
	end
	if UpdateAutoReplayCurrentButton then
		UpdateAutoReplayCurrentButton()
	end
	UpdateUI()

	-- Force the deletion to cloud immediately, even if Cloud Auto Save is OFF.
	SaveCloud(true)

	print("[Replay] Deleted recording:", tostring(Recording.Name))
end)

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
		-- DELETE
		--------------------------------------------------

		local DeleteButton = Instance.new("TextButton")
		DeleteButton.Size = UDim2.fromOffset(32, 32)
		DeleteButton.Position = UDim2.new(1, -37, 0, 6)
		DeleteButton.BackgroundColor3 = Color3.fromRGB(75, 35, 35)
		DeleteButton.TextColor3 = TEXT
		DeleteButton.Font = Enum.Font.GothamBold
		DeleteButton.TextSize = 12
		DeleteButton.Text = "×"
		DeleteButton.ZIndex = 11
		DeleteButton.Parent = Row
		AddCorner(DeleteButton, 5)

		DeleteButton.MouseButton1Click:Connect(function()
			if IsRecording or IsReplaying then
				return
			end
			OpenDeleteConfirmation(Recording)
		end)

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
				-42,
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
-- AUTO REPLAY RECORDING SELECTION
--------------------------------------------------

local AutoReplayCurrentButton = CreateButton(
	SavedSection,
	"Auto Replay: None",
	UDim2.new(1, -20, 0, 31),
	UDim2.fromOffset(10, 225),
	BLUE
)

local AutoReplayDropdown = Instance.new("Frame")
AutoReplayDropdown.Size = UDim2.new(1, -20, 0, 130)
AutoReplayDropdown.Position = UDim2.fromOffset(10, 259)
AutoReplayDropdown.BackgroundColor3 = Color3.fromRGB(25, 25, 29)
AutoReplayDropdown.Visible = false
AutoReplayDropdown.ZIndex = 50
AutoReplayDropdown.Parent = ScreenGui
AddCorner(AutoReplayDropdown, 6)
AddStroke(AutoReplayDropdown, BLUE, 0.2)

local AutoReplayDropdownList = Instance.new("ScrollingFrame")
AutoReplayDropdownList.Size = UDim2.new(1, -8, 1, -8)
AutoReplayDropdownList.Position = UDim2.fromOffset(4, 4)
AutoReplayDropdownList.BackgroundTransparency = 1
AutoReplayDropdownList.BorderSizePixel = 0
AutoReplayDropdownList.ScrollBarThickness = 3
AutoReplayDropdownList.CanvasSize = UDim2.fromOffset(0, 0)
AutoReplayDropdownList.ZIndex = 51
AutoReplayDropdownList.Parent = AutoReplayDropdown

local AutoReplayDropdownLayout = Instance.new("UIListLayout")
AutoReplayDropdownLayout.Padding = UDim.new(0, 4)
AutoReplayDropdownLayout.Parent = AutoReplayDropdownList

UpdateAutoReplayCurrentButton = function()
	if AutoReplayRecordingName and AutoReplayRecordingName ~= "" then
		AutoReplayCurrentButton.Text = "Auto Replay Current: " .. tostring(AutoReplayRecordingName)
	else
		AutoReplayCurrentButton.Text = "Auto Replay Current: None"
	end
end

RefreshAutoReplayDropdown = function()
	for _, Child in ipairs(AutoReplayDropdownList:GetChildren()) do
		if Child:IsA("TextButton") then
			Child:Destroy()
		end
	end

	local NoneButton = Instance.new("TextButton")
	NoneButton.Size = UDim2.new(1, -4, 0, 30)
	NoneButton.BackgroundColor3 = (AutoReplayRecordingName == nil) and Color3.fromRGB(45, 55, 75) or INPUT
	NoneButton.TextColor3 = TEXT
	NoneButton.Font = Enum.Font.GothamMedium
	NoneButton.TextSize = 9
	NoneButton.Text = "None (disable selected recording)"
	NoneButton.TextXAlignment = Enum.TextXAlignment.Left
	NoneButton.ZIndex = 52
	NoneButton.Parent = AutoReplayDropdownList
	AddCorner(NoneButton, 5)
	NoneButton.MouseButton1Click:Connect(function()
		AutoReplayRecordingName = nil
		AutoReplayDropdown.Visible = false
		UpdateAutoReplayCurrentButton()
		RefreshAutoReplayDropdown()
		SaveCloud(true)
	end)

	for _, Recording in ipairs(Recordings) do
		local Button = Instance.new("TextButton")
		Button.Size = UDim2.new(1, -4, 0, 30)
		Button.BackgroundColor3 = (Recording.Name == AutoReplayRecordingName) and Color3.fromRGB(45, 55, 75) or INPUT
		Button.TextColor3 = TEXT
		Button.Font = Enum.Font.GothamMedium
		Button.TextSize = 9
		Button.Text = Recording.Name
		Button.TextXAlignment = Enum.TextXAlignment.Left
		Button.ZIndex = 52
		Button.Parent = AutoReplayDropdownList
		AddCorner(Button, 5)

		Button.MouseButton1Click:Connect(function()
			AutoReplayRecordingName = Recording.Name
			AutoReplayDropdown.Visible = false
			UpdateAutoReplayCurrentButton()
			RefreshAutoReplayDropdown()
			SaveCloud(true)
		end)
	end

	task.defer(function()
		AutoReplayDropdownList.CanvasSize = UDim2.fromOffset(0, AutoReplayDropdownLayout.AbsoluteContentSize.Y + 6)
		if UpdateAutoReplayCurrentButton then
			UpdateAutoReplayCurrentButton()
		end
	end)
end

AutoReplayCurrentButton.MouseButton1Click:Connect(function()
	RefreshAutoReplayDropdown()
	if not AutoReplayDropdown.Visible then
		local Position = SavedSection.AbsolutePosition
		AutoReplayDropdown.Position = UDim2.fromOffset(Position.X + 10, Position.Y + 259)
	end
	AutoReplayDropdown.Visible = not AutoReplayDropdown.Visible
end)

UpdateAutoReplayCurrentButton()

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
DungeonSection.Size = UDim2.new(1, -2, 0, 233)
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

local AutoReplayRecordingButton

local function UpdateDungeonButtons()
	AutoStartButton.Text = AutoStart and "Auto Start: ON" or "Auto Start: OFF"
	AutoStartButton.BackgroundColor3 = AutoStart and GREEN or Color3.fromRGB(60, 60, 65)
	AutoReplayButton.Text = AutoReplay and "Dungeon Auto Replay: ON" or "Dungeon Auto Replay: OFF"
	AutoReplayButton.BackgroundColor3 = AutoReplay and GREEN or Color3.fromRGB(60, 60, 65)
	AutoReplayRecordingButton.Text = AutoReplayRecording and "Auto Replay Recording: ON" or "Auto Replay Recording: OFF"
	AutoReplayRecordingButton.BackgroundColor3 = AutoReplayRecording and GREEN or Color3.fromRGB(60, 60, 65)
end

AutoStartButton.MouseButton1Click:Connect(function()
	AutoStart = not AutoStart
	if AutoStart then
		LastAutoStartFire = 0
		AutoStartPending = false
		FireAutoStart()
	else
		AutoStartPending = false
		AutoReplayRecordingAt = nil
		AutoReplayRecordingRetryCount = 0
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

AutoReplayRecordingButton = CreateButton(
	DungeonSection,
	"Auto Replay Recording: ON",
	UDim2.new(0.5, -15, 0, 31),
	UDim2.fromOffset(10, 87),
	GREEN
)

AutoReplayRecordingButton.MouseButton1Click:Connect(function()
	AutoReplayRecording = not AutoReplayRecording
	if not AutoReplayRecording then
		AutoReplayRecordingAt = nil
		AutoReplayRecordingRetryCount = 0
		AutoReplayRecordingDungeonKey = nil
	end
	UpdateDungeonButtons()
	-- Persist this setting independently of the Cloud Auto Save toggle.
	SaveCloud(true)
end)

local AutoSaveButton = CreateButton(
	DungeonSection,
	"Cloud Auto Save: ON",
	UDim2.new(0.5, -15, 0, 31),
	UDim2.new(0.5, 5, 0, 87),
	GREEN
)

local RecordRespawnsButton = CreateButton(
	DungeonSection,
	"Record Respawns: ON",
	UDim2.new(0.5, -15, 0, 31),
	UDim2.fromOffset(10, 126),
	GREEN
)

RecordRespawnsButton.MouseButton1Click:Connect(function()
	RecordRespawns = not RecordRespawns
	RecordRespawnsButton.Text = RecordRespawns and "Record Respawns: ON" or "Record Respawns: OFF"
	RecordRespawnsButton.BackgroundColor3 = RecordRespawns and GREEN or Color3.fromRGB(60, 60, 65)
	SaveCloud(true)
end)

local CloudLoadButton = CreateButton(
	DungeonSection,
	"Load Cloud",
	UDim2.new(0.5, -15, 0, 31),
	UDim2.fromOffset(10, 165),
	BLUE
)

local function UpdateCloudButtons()
	AutoSaveButton.Text = AutoSave and "Cloud Auto Save: ON" or "Cloud Auto Save: OFF"
	AutoSaveButton.BackgroundColor3 = AutoSave and GREEN or Color3.fromRGB(60, 60, 65)
	RecordRespawnsButton.Text = RecordRespawns and "Record Respawns: ON" or "Record Respawns: OFF"
	RecordRespawnsButton.BackgroundColor3 = RecordRespawns and GREEN or Color3.fromRGB(60, 60, 65)
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
	-- Keep the Auto Replay Current label synchronized with the actual
	-- AutoReplayRecordingName value restored/used by the replay system.
	-- This is intentionally separate from the normal SelectedRecording UI.
	if UpdateAutoReplayCurrentButton then
		UpdateAutoReplayCurrentButton()
	end
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

		-- Track continuous high ping. If it remains high long enough,
		-- do not keep waiting for Auto Start; requeue the dungeon through
		-- replayDungeon so the game can move to another server.
		local CurrentPingHigh = IsPingHigh()
		if CurrentPingHigh then
			if not HighPingSince then
				HighPingSince = os.clock()
				HighPingServerReplayFired = false
				print("[Replay] High ping detected; waiting " .. HIGH_PING_SERVER_REPLAY_DELAY .. "s before recovery")
			end
		else
			if HighPingSince then
				HighPingSince = nil
				HighPingServerReplayFired = false
			end
		end

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

		-- Detect every dungeon start as a new cycle. The dungeon name alone is
		-- not enough because the same dungeon can be started repeatedly.
		local DungeonStartedNow = State.dungeonStarted == true
		if DungeonStartedNow and LastDungeonStartedState ~= true then
			DungeonStartCycle += 1
			AutoReplayRecordingDungeonKey = nil
			print("[Replay] New dungeon start cycle:", DungeonStartCycle)
		end
		LastDungeonStartedState = DungeonStartedNow

		if DungeonStartedNow then
			AutoStartPending = false

			-- Schedule even if another replay is currently running. The execution
			-- section below will wait until the character is free.
			if AutoReplayRecording then
				local DungeonKey = tostring(State.dungeonName or "Unknown") .. "#" .. tostring(DungeonStartCycle)
				if AutoReplayRecordingDungeonKey ~= DungeonKey and not AutoReplayRecordingAt then
					AutoReplayRecordingDungeonKey = DungeonKey
					AutoReplayRecordingAt = os.clock() + AUTO_REPLAY_RECORDING_DELAY
					AutoReplayRecordingRetryCount = 0
					print("[Replay] Dungeon started -> Auto Replay Recording scheduled in " .. AUTO_REPLAY_RECORDING_DELAY .. " seconds")
				end
			end
		else
			-- Clear the cycle lock when the dungeon ends so the next start can
			-- always schedule again, even for the same dungeon name.
			AutoReplayRecordingDungeonKey = nil
		end

		if CurrentPingHigh
			and HighPingSince
			and not HighPingServerReplayFired
			and os.clock() - HighPingSince >= HIGH_PING_SERVER_REPLAY_DELAY then
			FireHighPingDungeonReplay(State)
		end

		if AutoStart
			and State.dungeonStarted ~= true
			and not AutoStartPending
			and not CurrentPingHigh
			and not HighPingServerReplayFired then
			FireAutoStart()
		end

		if AutoReplay and not CurrentPingHigh then
			FireAutoReplay(State)
		end

		-- Separate feature: replay the selected saved recording 6 seconds
		-- after Auto Start. This never calls replayDungeon.
		if AutoReplayRecording and AutoReplayRecordingAt then
			local Now = os.clock()
			if Now >= AutoReplayRecordingAt then
				-- Never consume the pending auto replay just because the character is
				-- temporarily busy or ping is high. Keep retrying until the replay can
				-- actually be started.
				if not DungeonStartedNow then
					-- Auto Start can fire before the dungeon actually enters its
					-- started state. Never consume the recording replay early.
					-- Keep the timer alive until the dungeon is confirmed started.
					AutoReplayRecordingRetryCount += 1
					AutoReplayRecordingAt = Now + 0.5
				elseif IsPingHigh() then
					AutoReplayRecordingRetryCount += 1
					AutoReplayRecordingAt = Now + 0.5
				elseif IsReplaying or IsRecording or ReplayStartPositioning then
					AutoReplayRecordingRetryCount += 1
					AutoReplayRecordingAt = Now + 0.5
				else
					local RecordingToPlay = nil
					if AutoReplayRecordingName then
						for _, Recording in ipairs(Recordings) do
							if tostring(Recording.Name) == tostring(AutoReplayRecordingName) then
								RecordingToPlay = Recording
								break
							end
						end
					end

					if not RecordingToPlay and #Recordings > 0 then
						RecordingToPlay = Recordings[1]
						AutoReplayRecordingName = RecordingToPlay.Name
						UpdateAutoReplayCurrentButton()
					end

					if RecordingToPlay and RecordingToPlay.Movement and #RecordingToPlay.Movement > 0 then
						print("[Replay] Auto Replay Recording ->", tostring(RecordingToPlay.Name))
						StartReplay(RecordingToPlay)
						-- StartReplay may take a moment to position the character. The
						-- ReplayStartPositioning guard above prevents duplicate starts.
						AutoReplayRecordingAt = nil
						AutoReplayRecordingRetryCount = 0
					else
						warn("[Replay] Auto Replay Recording: no saved recording available")
						AutoReplayRecordingAt = nil
						AutoReplayRecordingRetryCount = 0
					end
				end
			end
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

-- Final UI visibility safeguard.
ScreenGui.Enabled = true
MainFrame.Visible = true
MainFrame.Active = true

RefreshRecordingList()
UpdateUI()

print(
	"[Replay System] Loaded "
	.. VERSION
)
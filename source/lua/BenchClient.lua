-- ======= Copyright (c) 2020, Unknown Worlds Entertainment, Inc. All rights reserved. =============
--
-- ns2-benchmark-mod/lua/BenchClient.lua
--
--    Created by:   Trevor Harris (trevor@naturalselection2.com)
--
--    Captures the camera path of a user, and writes it out to a file.
--
-- ========= For more information, visit us at http://www.unknownworlds.com ========================

Log("===================================================== BENCHMARK MOD =========================================")

Log("Loaded BenchClient.lua")
local benchmarkStatus = "ejected"

local kRecordingIconTexture = PrecacheAsset("ui/benchmark_recording_icon.dds")
local kPlayingIconTexture = PrecacheAsset("ui/benchmark_playing_icon.dds")
local kPausedIconTexture = PrecacheAsset("ui/benchmark_paused_icon.dds")
local kEjectedIconTexture = PrecacheAsset("ui/benchmark_ejected_icon.dds")

local kRecordingFPS = 60 -- even THIS is probably too high...
local kRecordingTimeInterval = 1.0 / kRecordingFPS
local kInitialReservationRecordingTime = 5 * 60 -- 5 minutes is probably very excessive...
local kstatusIconBaseScale = 0.75

local kBufferIdxTime = 1
local kBufferIdxPosition = 2
local kBufferIdxAngles = 3
local kBufferIdxFOV = 4

local kBenchmarkFileExt = ".ns2_benchmark"

Log("Added console command \"bench_record\"")
Event.Hook("Console_bench_record", function()
    Benchmark_BeginRecording()
end)

Log("Added console command \"bench_save\"")
Event.Hook("Console_bench_save", function(fileName, ...)
    
    local args = {...}
    if #args > 0 then
        Log("Error: file name cannot contain spaces!")
        return
    end
    
    if fileName == nil then
        Log("Usage: bench_save file-name-without-spaces-or-extension")
        return
    end
    
    Benchmark_SaveRecording(fileName)
end)

Log("Added console command \"bench_load\"")
Event.Hook("Console_bench_load", function(fileName, ...)
    
    local args = {...}
    if #args > 0 then
        Log("Error: file name cannot contain spaces!")
        return
    end
    
    if fileName == nil then
        Log("Usage: bench_load file-name-without-spaces-or-extension")
        return
    end
    
    Benchmark_LoadRecording(fileName)
end)

Log("Added console command \"bench_play\"")
Event.Hook("Console_bench_play", function()
    Benchmark_Play()
end)

Log("Added console command \"bench_stop\"")
Event.Hook("Console_bench_stop", function()

    if Benchmark_GetIsPlaying() then
        Benchmark_StopPlaying()
    elseif Benchmark_GetIsRecording() then
        Benchmark_EndRecording()
    end
    
end)

Log("Added console command \"bench_list\"")
Event.Hook("Console_bench_list", function()
    
    local localList, vanillaList = Benchmark_GetListsOfRecordingNames()
    if #localList == 0 and #vanillaList == 0 then
        Log("Found 0 recordings. :( ")
        return
    end
    
    local total = #localList + #vanillaList
    
    Log("Found %s recordings (%s local, %s vanilla)", total, #localList, #vanillaList)
    for i=1, #localList do
        Log("    %%appdata%%/Natural Selection 2/%s", localList[i])
    end
    for i=1, #vanillaList do
        Log("    <ns2 install>/ns2/%s", vanillaList[i])
    end
    
end)

local benchmarkData = {}
benchmarkData.minFPS = 99999
benchmarkData.maxFPS = 0
benchmarkData.avgFPS = 0
benchmarkData.totalFrameCount = 0
benchmarkData.playbackStartTime = 0
benchmarkData.playbackEndTime = 0
local lastFrameTime = -1
function BenchmarkData_RecordFrameTimeDelta()
    
    local now = Benchmark_GetTime()
    
    if lastFrameTime >= 0 then
        
        local deltaTime = now - lastFrameTime
        local fps = 1.0 / math.max(0.001, deltaTime)
    
        benchmarkData.totalFrameCount = benchmarkData.totalFrameCount + 1
        
        benchmarkData.minFPS = math.min(benchmarkData.minFPS, fps)
        benchmarkData.maxFPS = math.max(benchmarkData.maxFPS, fps)
        
        benchmarkData.playbackEndTime = Benchmark_GetTime()
        local totalTime = math.max(0, benchmarkData.playbackEndTime - benchmarkData.playbackStartTime)
        if totalTime > 0 then
            benchmarkData.avgFPS = benchmarkData.totalFrameCount / totalTime
        else
            benchmarkData.avgFPS = 0
        end
        
    end
    
    lastFrameTime = now
    
end

function BenchmarkData_BeginBenchmark()
    
    lastFrameTime = -1
    benchmarkData.minFPS = 99999
    benchmarkData.maxFPS = 0
    benchmarkData.avgFPS = 0
    benchmarkData.totalFrameCount = 0
    benchmarkData.playbackStartTime = Benchmark_GetTime()
    benchmarkData.playbackEndTime = 0
    
end

function BenchmarkData_GetData()
    
    return benchmarkData
    
end

function Benchmark_GetListsOfRecordingNames()
    
    local appDataRecordings = {}
    Shared.GetMatchingFileNames(string.format("config://*%s", kBenchmarkFileExt), true, appDataRecordings)
    
    local vanillaRecordings = {}
    Shared.GetMatchingFileNames(string.format("benchmarks/*%s", kBenchmarkFileExt), true, vanillaRecordings)
    
    return appDataRecordings, vanillaRecordings

end

function Benchmark_GetIsRecording()
    return benchmarkStatus == "recording"
end

function Benchmark_GetIsPlaying()
    return benchmarkStatus == "playing"
end

local buffer = {}
local function Buffer_Clear()
    buffer = {}
    buffer.currentRecordingIndex = 0 -- last index written (if playing back, this is the size)
    buffer.currentPlaybackIndex = 0
    Benchmark_SetStatus("ejected")
end

function Benchmark_HasRecordedData()
    return buffer.currentRecordingIndex > 0
end

local function Buffer_GetNewEmptyEntry()
    local newEntry = {}
    
    newEntry[kBufferIdxTime] = 0
    newEntry[kBufferIdxPosition] = Vector()
    newEntry[kBufferIdxAngles] = Angles()
    newEntry[kBufferIdxFOV] = 0
    
    return newEntry
end

local function Buffer_GetEntryAsListOfPrimitives(entry)
    
    local list = {}
    
    list[1] = entry[kBufferIdxTime]
    
    list[2] = entry[kBufferIdxPosition].x
    list[3] = entry[kBufferIdxPosition].y
    list[4] = entry[kBufferIdxPosition].z
    
    list[5] = entry[kBufferIdxAngles].pitch
    list[6] = entry[kBufferIdxAngles].yaw
    list[7] = entry[kBufferIdxAngles].roll
    
    list[8] = entry[kBufferIdxFOV]
    
    return list
    
end

local function Buffer_GetListOfPrimitivesAsBufferEntry(list)
    
    local entry = {}
    
    entry[kBufferIdxTime] = list[1]
    
    entry[kBufferIdxPosition] = Vector()
    entry[kBufferIdxPosition].x = list[2]
    entry[kBufferIdxPosition].y = list[3]
    entry[kBufferIdxPosition].z = list[4]
    
    entry[kBufferIdxAngles] = Angles()
    entry[kBufferIdxAngles].pitch = list[5]
    entry[kBufferIdxAngles].yaw   = list[6]
    entry[kBufferIdxAngles].roll  = list[7]
    
    entry[kBufferIdxFOV] = list[8]
    
    return entry
    
end

local function Buffer_AdvancePlaybackToNextEntry()
    buffer.currentPlaybackIndex = math.min(buffer.currentPlaybackIndex + 1, buffer.currentRecordingIndex)
end

local function Buffer_GetCurrentPlaybackEntry()
    return buffer[buffer.currentPlaybackIndex]
end

local function Buffer_GetPreviousPlaybackEntry()
    return buffer[math.max(1, buffer.currentPlaybackIndex - 1)]
end

local function Buffer_GetEntryTimestamp(entry)
    return entry[kBufferIdxTime]
end

local function Buffer_GetEntryPosition(entry)
    return entry[kBufferIdxPosition]
end

local function Buffer_GetEntryAngles(entry)
    return entry[kBufferIdxAngles]
end

local function Buffer_GetEntryFOV(entry)
    return entry[kBufferIdxFOV]
end

local function Buffer_GetIsPlaybackAtBeginning()
    return buffer.currentPlaybackIndex == 1
end

local function Buffer_GetIsPlaybackAtEnd()
    return buffer.currentPlaybackIndex >= buffer.currentRecordingIndex
end

local function Buffer_SetEntryTimestamp(entry, time)
    entry[kBufferIdxTime] = time
end

local function Buffer_SetEntryPosition(entry, position)
    entry[kBufferIdxPosition] = position
end

local function Buffer_SetEntryAngles(entry, angles)
    entry[kBufferIdxAngles] = angles
end

local function Buffer_SetEntryFOV(entry, fov)
    entry[kBufferIdxFOV] = fov
end

-- Can return nil on the first frame!!!
local function GetNewestBufferEntry()
    return buffer[buffer.currentRecordingIndex]
end

local function ResizeBuffer(newSize)
    
    newSize = math.max(16, newSize) -- enforce a minimum size... probably isn't needed, but just in case!
    
    if #buffer >= newSize then
        return -- don't ever shrink.
    end
    
    local oldSize = #buffer
    for i=oldSize + 1, newSize do
        buffer[i] = Buffer_GetNewEmptyEntry()
    end
    
end

local function Buffer_GetNextEntryForRecording()
    
    buffer.currentRecordingIndex = buffer.currentRecordingIndex + 1
    
    -- Resize the buffer if we're run out of space!
    if buffer.currentRecordingIndex > #buffer then
        Log("Warning!  Ran out of recording buffer space.  Resizing...")
        ResizeBuffer(#buffer * 2)
    end
    
    return (GetNewestBufferEntry())

end

local function SetupBufferForRecording()
    
    -- Try to get all of our GC hitches out of the way up front so they don't impact the
    -- benchmark.
    Buffer_Clear()
    ResizeBuffer(kRecordingFPS * kInitialReservationRecordingTime)
    
end

function Benchmark_GetStatus()
    return benchmarkStatus
end

function Benchmark_SetStatus(status)
    benchmarkStatus = status
    GetGlobalEventDispatcher():FireEvent("OnBenchmarkStatusChanged")
end

function Benchmark_GetPlaybackProgressFraction()
    if Benchmark_GetIsPlaying() then
        return (math.min(math.max(0, buffer.currentPlaybackIndex / math.max(1, buffer.currentRecordingIndex)), 1))
    else
        return 0
    end
end

local function FireProgressChangeEvent()
    GetGlobalEventDispatcher():FireEvent("OnBenchmarkProgressChanged")
end

local statusIcon = nil
function Benchmark_CreateStatusIcon()
    
    if statusIcon ~= nil then
        return -- already created
    end
    
    statusIcon = CreateGUIObject("statusIcon", GUIObject, nil)
    statusIcon:AlignTopRight()
    statusIcon:SetPosition(-64, 64, 0)
    statusIcon:SetTexture(kEjectedIconTexture)
    statusIcon:SetSizeFromTexture()
    statusIcon:SetColor(1, 1, 1, 1)
    
    -- Make it scale with screen resolution
    local function UpdateScale(self)
        local scale = kstatusIconBaseScale * Client.GetScreenHeight() / 1080
        self:SetScale(scale, scale)
    end
    UpdateScale(statusIcon)
    statusIcon:HookEvent(GetGlobalEventDispatcher(), "OnResolutionChanged", UpdateScale)
    
    -- Update icon whenever benchmark status changes.
    local function UpdateStatus(self)
        local status = Benchmark_GetStatus()
        if status == "recording" then
            statusIcon:SetTexture(kRecordingIconTexture)
        elseif status == "playing" then
            statusIcon:SetTexture(kPlayingIconTexture)
        elseif status == "ejected" then
            statusIcon:SetTexture(kEjectedIconTexture)
        elseif status == "paused" then
            statusIcon:SetTexture(kPausedIconTexture)
        end
    end
    UpdateStatus(statusIcon)
    statusIcon:HookEvent(GetGlobalEventDispatcher(), "OnBenchmarkStatusChanged", UpdateStatus)
    
end

local playbackBar = nil
function Benchmark_CreatePlaybackBar()
    
    if playbackBar ~= nil then
        return
    end
    
    playbackBar = CreateGUIObject("barBackground", GUIObject, nil)
    playbackBar:SetSize(1000, 50)
    playbackBar:AlignTop()
    playbackBar:SetColor(0, 0, 0, 0.75)
    
    -- Scale and position based on resolution.
    local function UpdateLayout(self)
        local scale = Client.GetScreenHeight() / 900
        self:SetScale(scale, scale)
        self:SetPosition(0, scale * 60)
    end
    UpdateLayout(playbackBar)
    playbackBar:HookEvent(GetGlobalEventDispatcher(), "OnResolutionChanged", UpdateLayout)
    
    local progressBar = CreateGUIObject("progressBar", GUIObject, playbackBar)
    progressBar:SetColor(1, 1, 1, 1)
    progressBar:SetSize(10, 50)
    
    -- Position progress bar based on playback fraction.
    local function UpdateProgress(self)
        local progress = Benchmark_GetPlaybackProgressFraction()
        self:SetHotSpot(progress, 0.5)
        self:SetAnchor(progress, 0.5)
    end
    UpdateProgress(progressBar)
    progressBar:HookEvent(GetGlobalEventDispatcher(), "OnBenchmarkProgressChanged", UpdateProgress)
    
end

function Benchmark_DestroyPlaybackBar()
    
    if playbackBar == nil then
        return
    end
    
    playbackBar:Destroy()
    playbackBar = nil
    
end

function Benchmark_DestroyStatusIcon()

    if statusIcon == nil then
        return -- already doesn't exist
    end
    
    statusIcon:Destroy()
    statusIcon = nil

end

function Benchmark_GetTime()
    return (Shared.GetSystemTimeReal())
end

local recordingStartTime = 0
function Benchmark_BeginRecording()
    
    if Benchmark_GetIsRecording() then
        Log("Benchmark is already recording!")
        return
    end
    
    SetupBufferForRecording()
    recordingStartTime = Benchmark_GetTime()
    Benchmark_SetStatus("recording")
    Benchmark_DestroyResults()
    
    Log("Beginning recording...")
    
end

function Benchmark_EndRecording()
    
    if not Benchmark_GetIsRecording() then
        Log("Benchmark was not recording!")
        return
    end
    
    Benchmark_SetStatus("paused")
    
    Log("Recording ended.")
    
end

function Benchmark_SaveRecording(fileName)
    
    if Benchmark_GetIsRecording() then
        Log("Error: Cannot save while recording.")
        return
    end
    
    if Benchmark_GetIsPlaying() then
        Log("Error: Cannot save while playing.")
        return
    end
    
    if not Benchmark_HasRecordedData() then
        Log("Error: No recorded data to save.")
        return
    end
    
    -- Need to unpack the data into a regular table (no c types, json doesn't know how to deal with
    -- these!)
    local output = {}
    for i=1, buffer.currentRecordingIndex do
        output[i] = Buffer_GetEntryAsListOfPrimitives(buffer[i])
    end
    
    local realFileName = "config://"..fileName..kBenchmarkFileExt
    local writingFile = io.open(realFileName, "w+")
    writingFile:write(json.encode(output))
    io.close(writingFile)
    Log("Benchmark recording saved to \"%s\".", realFileName)

end

function Benchmark_LoadRecording(fileName)
    
    if Benchmark_GetIsRecording() then
        Log("Error: Cannot load while recording.")
        return
    end
    
    if Benchmark_GetIsPlaying() then
        Log("Error: Cannot load while playing.")
        return
    end
    
    -- Try to load from a special game directory (eg for benchmarks that ship with the game).
    local realFileName = "game://benchmarks/"..fileName..kBenchmarkFileExt
    if not GetFileExists(realFileName) then
        realFileName = "config://"..fileName..kBenchmarkFileExt
        if not GetFileExists(realFileName) then
            Log("Error: Cannot find benchmark file \"%s\".", fileName)
            return
        end
    end
    
    local readingFile = io.open(realFileName, "r")
    if readingFile == nil then
        -- Unable to open it.  Spark has already printed an error message about this.
        return
    end
    
    local decoded, _, errStr = json.decode(readingFile:read("*all"))
    io.close(readingFile)
    if errStr then
        Log("Error when reading file: \"%s\"", errStr)
        return
    end
    
    -- Unpack the buffer
    Buffer_Clear()
    buffer.currentRecordingIndex = #decoded
    for i=1, #decoded do
        buffer[i] = Buffer_GetListOfPrimitivesAsBufferEntry(decoded[i])
    end
    Log("Benchmark recording loaded from \"%s\".", fileName)
    
end

function Benchmark_RecordFrame(time)
    
    local lastEntry = GetNewestBufferEntry()
    local lastRecordedFrameTime = lastEntry and Buffer_GetEntryTimestamp(lastEntry) or -999
    if time - lastRecordedFrameTime < kRecordingTimeInterval then
        return -- not enough time has passed yet to record another frame
    end
    
    local player = Client.GetLocalPlayer()
    if player == nil then
        Log("Warning!  Got nil player when recording frame!")
        return
    end
    
    local cameraCoords = player.GetCameraViewCoords and player:GetCameraViewCoords(true)
    if cameraCoords == nil then
        Log("Warning!  Unable to get camera view coords when recording frame!")
        return
    end
    
    local angles = Angles()
    angles:BuildFromCoords(cameraCoords)
    
    local bufferEntry = Buffer_GetNextEntryForRecording()
    Buffer_SetEntryTimestamp(bufferEntry, time)
    Buffer_SetEntryPosition(bufferEntry, cameraCoords.origin)
    Buffer_SetEntryAngles(bufferEntry, angles)
    Buffer_SetEntryFOV(bufferEntry, Client.GetEffectiveFov(player))
    
end

local overrideFOV = 1
local old_Client_GetEffectiveFov = Client.GetEffectiveFov
function Client.GetEffectiveFov(player)
    
    if Benchmark_GetIsPlaying() then
        return overrideFOV
    end
    
    return (old_Client_GetEffectiveFov(player))
    
end

local playbackStartTime = 0
local lerpedPosition = Vector()
local lerpedAngles = Angles()
function Benchmark_GetPlaybackFrameCameraCoords(time)
    
    -- Find the buffer entries that bracket the current timestamp.  This just means we advance until
    -- we find a timestamp that's ahead of our current time.  Then we just use this entry and the
    -- previous one.
    while Buffer_GetEntryTimestamp(Buffer_GetCurrentPlaybackEntry()) < time and
          not Buffer_GetIsPlaybackAtEnd() do
        
        Buffer_AdvancePlaybackToNextEntry()
    end
    
    FireProgressChangeEvent()
    
    local leftEntry = Buffer_GetPreviousPlaybackEntry()
    local rightEntry = Buffer_GetCurrentPlaybackEntry()
    
    local leftTime = Buffer_GetEntryTimestamp(leftEntry)
    local rightTime = Buffer_GetEntryTimestamp(rightEntry)
    
    if leftTime > rightTime then
        Log("Warning!  Unordered timestamps! (Timestamps were %s and %s).", leftTime, rightTime)
        leftTime = rightTime
    end
    
    if (time < leftTime or time > rightTime) and
       not Buffer_GetIsPlaybackAtBeginning() and
       not Buffer_GetIsPlaybackAtEnd() then
       
        Log("time was outside the bracket! (time=%s, leftTime=%s, rightTime=%s)", time, leftTime, rightTime)
        time = math.max(math.min(time, rightTime), leftTime)
    end
    
    local timeFrac = math.min(math.max((time - leftTime) / (rightTime - leftTime), 0.0), 1.0)
    
    local leftPos = Buffer_GetEntryPosition(leftEntry)
    local rightPos = Buffer_GetEntryPosition(rightEntry)
    local leftAngles = Buffer_GetEntryAngles(leftEntry)
    local rightAngles = Buffer_GetEntryAngles(rightEntry)
    local leftFOV = Buffer_GetEntryFOV(leftEntry)
    local rightFOV = Buffer_GetEntryFOV(rightEntry)
    
    if timeFrac == 0 then
        local newCameraCoords = leftAngles:GetCoords()
        newCameraCoords.origin = leftPos
        overrideFOV = leftFOV
        return newCameraCoords
    
    elseif timeFrac == 1 then
        local newCameraCoords = rightAngles:GetCoords()
        newCameraCoords.origin = rightPos
        overrideFOV = rightFOV
        return newCameraCoords, rightFOV
        
    end
    
    -- Don't create a new Vector object.  Trying to prevent any garbage from being created.
    lerpedPosition.x = leftPos.x * (1.0 - timeFrac) + rightPos.x * timeFrac
    lerpedPosition.y = leftPos.y * (1.0 - timeFrac) + rightPos.y * timeFrac
    lerpedPosition.z = leftPos.z * (1.0 - timeFrac) + rightPos.z * timeFrac
    
    -- Can't really get around garbage creation here... :(
    lerpedAngles = Angles.Lerp(leftAngles, rightAngles, timeFrac)
    
    -- Set the FOV to be picked up again by Client.GetEffectiveFov()
    overrideFOV = leftFOV * (1.0 - timeFrac) + rightFOV * timeFrac
    
    local newCameraCoords = lerpedAngles:GetCoords()
    newCameraCoords.origin = lerpedPosition
    
    return newCameraCoords
    
end

function Benchmark_GetCameraViewCoordsOverride(player, cameraCoords)
    
    if Benchmark_GetIsPlaying() then
        return (Benchmark_GetPlaybackFrameCameraCoords(Benchmark_GetTime() - playbackStartTime))
    end
    
end

function Benchmark_Play()
    
    if Benchmark_GetIsRecording() then
        Log("Cannot playback while recording.")
        return
    end
    
    if not Benchmark_HasRecordedData() then
        Log("No recorded data to playback.")
        return
    end
    
    Log("Playing back the buffered camera move")
    
    Benchmark_SetStatus("playing")
    playbackStartTime = Benchmark_GetTime()
    buffer.currentPlaybackIndex = 1
    FireProgressChangeEvent()
    BenchmarkData_BeginBenchmark()
    Benchmark_DestroyResults() -- Hide results from last test, if any
    Shared.ConsoleCommand("maxfps 1000") -- so we don't get capped off
    
end

function Benchmark_StopPlaying()
    
    if not Benchmark_GetIsPlaying() then
        Log("Wasn't playing-back!")
        return
    end
    
    Log("Playback stopped.")
    Benchmark_SetStatus("paused")
    
end

local resultsRootObj = nil
function Benchmark_DisplayResults()

    local resultsTbl = BenchmarkData_GetData()

    if resultsRootObj == nil then
        
        -- Create backgroundObj to hold it all
        resultsRootObj = CreateGUIObject("resultsBack", GUIObject, nil)
        resultsRootObj:SetSize(1600, 900)
        resultsRootObj:AlignTop()
        local function UpdateRootScale(self)
            local scale = Client.GetScreenHeight() / 900
            self:SetScale(scale, scale)
        end
        UpdateRootScale(resultsRootObj)
        resultsRootObj:HookEvent(GetGlobalEventDispatcher(), "OnResolutionChanged", UpdateRootScale)
        
        -- Create title
        local titleObj = CreateGUIObject("titleObj", GUIText, resultsRootObj)
        titleObj:SetFontFamily("MicrogrammaBold")
        titleObj:SetFontSize(46)
        titleObj:SetColor(1, 1, 1, 1)
        titleObj:SetDropShadowEnabled(true)
        titleObj:SetText("Results")
        titleObj:AlignTop()
        titleObj:SetPosition(0, 146)
        
        -- Create results paragraph text
        local resultsTextObj = CreateGUIObject("resultsTextObj", GUIParagraph, resultsRootObj)
        resultsTextObj:SetFontFamily("MicrogrammaBold")
        resultsTextObj:SetFontSize(30)
        resultsTextObj:SetColor(1, 1, 1, 1)
        resultsTextObj:SetDropShadowEnabled(true)
        resultsTextObj:SetJustification(GUIItem.Align_Min)
        resultsTextObj:AlignTop()
        resultsTextObj:SetPosition(0, 256)
        resultsRootObj.resultsTextObj = resultsTextObj
        
    end
    
    local resultsStr = string.format("Minimum FPS: %.1f\nMaximum FPS: %.1f\nAverage FPS: %.1f", resultsTbl.minFPS, resultsTbl.maxFPS, resultsTbl.avgFPS)
    local resultsLineList = string.Explode(resultsStr, "\n")
    for i=1, #resultsLineList do
        Log(resultsLineList[i])
    end
    
    local resultsTextObj = resultsRootObj.resultsTextObj
    resultsTextObj:SetText(resultsStr)

end


function Benchmark_DestroyResults()

    if resultsRootObj == nil then
        return
    end
    
    resultsRootObj:Destroy()
    resultsRootObj = nil

end

local function SetupPlaybackBar()
    
    -- Set it up so the playback bar will be created when we start playback, and destroyed when we
    -- end playback.
    
    local function UpdatePlaybackBarLifetime()
    
        -- Only show the playback bar when we are playing-back!
        -- (These are safe to call multiple times.  There won't be more than one playback bar.)
        if Benchmark_GetStatus() == "playing" then
            Benchmark_CreatePlaybackBar()
        else
            Benchmark_DestroyPlaybackBar()
        end
        
    end
    UpdatePlaybackBarLifetime()
    local ged = GetGlobalEventDispatcher()
    ged:HookEvent(ged, "OnBenchmarkStatusChanged", UpdatePlaybackBarLifetime)
    
end

Event.Hook("UpdateRender", function()
    
    if Benchmark_GetIsRecording() then
        Benchmark_RecordFrame(Benchmark_GetTime() - recordingStartTime)
    end
    
    if Benchmark_GetIsPlaying() then
        if Buffer_GetIsPlaybackAtEnd() then
            Benchmark_StopPlaying()
            Benchmark_DisplayResults()
        else
            BenchmarkData_RecordFrameTimeDelta()
        end
    end
end)

Event.Hook("LoadComplete", function()
    
    Benchmark_CreateStatusIcon()
    SetupPlaybackBar()
    
end)

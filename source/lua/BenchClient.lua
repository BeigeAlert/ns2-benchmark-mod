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
local isRecording = false
local isPlaying = false

local kRecordingIconTexture = PrecacheAsset("ui/benchmark_recording_icon.dds")

local kRecordingFPS = 60 -- even THIS is probably too high...
local kRecordingTimeInterval = 1.0 / kRecordingFPS
local kInitialReservationRecordingTime = 5 * 60 -- 5 minutes is probably very excessive...
local kRecordingIconBaseScale = 0.75

local kBufferIdxTime = 1
local kBufferIdxPosition = 2
local kBufferIdxAngles = 3

Log("Added console command \"bench_record_start\"")
Event.Hook("Console_bench_record_start", function()
    Benchmark_BeginRecording()
end)

Log("Added console command \"bench_record_stop\"")
Event.Hook("Console_bench_record_stop", function()
    Benchmark_EndRecording()
end)

Log("Added console command \"bench_record_save\"")
Event.Hook("Console_bench_record_save", function(fileName, ...)
    
    local args = {...}
    if #args > 0 then
        Log("Error: file name cannot contain spaces!")
        return
    end
    
    if fileName == nil then
        Log("Usage: bench_record_save file-name-without-spaces-or-extension")
        return
    end
    
    Benchmark_SaveRecording(fileName)
end)

Log("Added console command \"bench_play\"")
Event.Hook("Console_bench_play", function()
    Benchmark_Play()
end)

Log("Added console command \"bench_stop\"")
Event.Hook("Console_bench_stop", function()
    Benchmark_StopPlaying()
end)

function Benchmark_GetIsRecording()
    return isRecording == true
end

function Benchmark_GetIsPlaying()
    return isPlaying == true
end

local buffer = {}
local function ClearBuffer()
    buffer = {}
    buffer.currentRecordingIndex = 0 -- last index written (if playing back, this is the size)
    buffer.currentPlaybackIndex = 0
end

function Benchmark_HasRecordedData()
    return buffer.currentRecordingIndex > 0
end

local function GetNewEmptyBufferEntry()
    local newEntry = {}
    
    newEntry[kBufferIdxTime] = 0
    newEntry[kBufferIdxPosition] = Vector()
    newEntry[kBufferIdxAngles] = Angles()
    
    return newEntry
end

local function GetBufferEntryAsListOfPrimitives(entry)
    
    local list = {}
    
    list[1] = entry[kBufferIdxTime]
    
    list[2] = entry[kBufferIdxPosition].x
    list[3] = entry[kBufferIdxPosition].y
    list[4] = entry[kBufferIdxPosition].z
    
    list[5] = entry[kBufferIdxAngles].pitch
    list[6] = entry[kBufferIdxAngles].yaw
    list[7] = entry[kBufferIdxAngles].roll
    
    return list
    
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
        buffer[i] = GetNewEmptyBufferEntry()
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
    ClearBuffer()
    ResizeBuffer(kRecordingFPS * kInitialReservationRecordingTime)
    
end

local recordingIcon = nil
local function CreateRecordingIcon()
    
    if recordingIcon ~= nil then
        return -- already created
    end
    
    recordingIcon = CreateGUIObject("RecordingIcon", GUIObject, nil)
    recordingIcon:AlignTopRight()
    recordingIcon:SetPosition(-64, 64, 0)
    recordingIcon:SetTexture(kRecordingIconTexture)
    recordingIcon:SetSizeFromTexture()
    recordingIcon:SetColor(1, 1, 1, 1)
    
    -- Make it scale with screen resolution
    local function UpdateScale(self)
        local scale = kRecordingIconBaseScale * Client.GetScreenHeight() / 1080
        self:SetScale(scale, scale)
    end
    UpdateScale(recordingIcon)
    recordingIcon:HookEvent(GetGlobalEventDispatcher(), "OnResolutionChanged", UpdateScale)
    
    -- Make it blink on and off every second
    recordingIcon:AnimateProperty("Visible", nil,
    {
        func = function(obj, time, params, currentValue, startValue, endValue, startTime)
            return time % 1.5 <= 0.75, false
        end,
    })
    
end

local function DestroyRecordingIcon()

    if recordingIcon == nil then
        return -- already doesn't exist
    end
    
    recordingIcon:Destroy()
    recordingIcon = nil

end

local function GetTimeForBenchmark()
    return (Shared.GetSystemTimeReal())
end

local recordingStartTime = 0
function Benchmark_BeginRecording()
    
    if Benchmark_GetIsRecording() then
        Log("Benchmark is already recording!")
        return
    end
    
    CreateRecordingIcon()
    SetupBufferForRecording()
    recordingStartTime = GetTimeForBenchmark()
    isRecording = true
    
    Log("Beginning recording...")
    
end

function Benchmark_EndRecording()
    
    if not Benchmark_GetIsRecording() then
        Log("Benchmark was not recording!")
        return
    end
    
    DestroyRecordingIcon()
    isRecording = false
    
    Log("Recording ended.")
    
end

function Benchmark_SaveRecording(fileName)
    
    if Benchmark_GetIsRecording() then
        Log("Error: Cannot save while recording.")
        return
    end
    
    -- Need to unpack the data into a regular table (no c types, json doesn't know how to deal with
    -- these!)
    local output = {}
    for i=1, buffer.currentRecordingIndex do
        output[i] = GetBufferEntryAsListOfPrimitives(buffer[i])
    end
    
    local realFileName = "config://"..fileName..".ns2_benchmark"
    local writingFile = io.open(realFileName, "w+")
    writingFile:write(json.encode(output))
    io.close(writingFile)
    Log("Benchmark recording saved to \"%s\".", realFileName)

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
    
end

local playbackStartTime = 0
local serverNeedsPositionUpdate = false
local lerpedPosition = Vector()
local lerpedAngles = Angles()
local debugFrameNumber = 0
function Benchmark_GetPlaybackFrameCameraCoords(time)
    
    -- Find the buffer entries that bracket the current timestamp.  This just means we advance until
    -- we find a timestamp that's ahead of our current time.  Then we just use this entry and the
    -- previous one.
    while Buffer_GetEntryTimestamp(Buffer_GetCurrentPlaybackEntry()) < time and
          not Buffer_GetIsPlaybackAtEnd() do
        
        Buffer_AdvancePlaybackToNextEntry()
        serverNeedsPositionUpdate = true -- probably have a different position now
    end
    
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
    
    if timeFrac == 0 then
        local newCameraCoords = leftAngles:GetCoords()
        newCameraCoords.origin = leftPos
        return newCameraCoords
    
    elseif timeFrac == 1 then
        local newCameraCoords = rightAngles:GetCoords()
        newCameraCoords.origin = rightPos
        return newCameraCoords
        
    end
    
    -- Don't create a new Vector object.  Trying to prevent any garbage from being created.
    lerpedPosition.x = leftPos.x * (1.0 - timeFrac) + rightPos.x * timeFrac
    lerpedPosition.y = leftPos.y * (1.0 - timeFrac) + rightPos.y * timeFrac
    lerpedPosition.z = leftPos.z * (1.0 - timeFrac) + rightPos.z * timeFrac
    
    -- Can't really get around garbage creation here... :(
    lerpedAngles = Angles.Lerp(leftAngles, rightAngles, timeFrac)
    
    local newCameraCoords = lerpedAngles:GetCoords()
    newCameraCoords.origin = lerpedPosition
    
    -- DEBUG
    debugFrameNumber = debugFrameNumber + 1
    Log("==============================================================")
    Log("    frameNumber = %s", debugFrameNumber)
    Log("    currentPlaybackIndex = %s", buffer.currentPlaybackIndex)
    Log("    time = %s", time)
    Log("    timeFrac = %s", timeFrac)
    Log("    leftTime = %s", leftTime)
    Log("    rightTime = %s", rightTime)
    Log("    rightTime - leftTime = %s", rightTime - leftTime)
    Log("    leftPos = %s", string.format("{%.4f, %.4f, %.4f}", leftPos.x, leftPos.y, leftPos.z))
    Log("    rightPos = %s", string.format("{%.4f, %.4f, %.4f}", rightPos.x, rightPos.y, rightPos.z))
    Log("    lerpedPosition = %s", string.format("{%.4f, %.4f, %.4f}", lerpedPosition.x, lerpedPosition.y, lerpedPosition.z))
    
    return newCameraCoords
    
end

function Benchmark_GetCameraViewCoordsOverride(player, cameraCoords)
    
    if Benchmark_GetIsPlaying() then
        return (Benchmark_GetPlaybackFrameCameraCoords(GetTimeForBenchmark() - playbackStartTime))
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
    
    isPlaying = true
    playbackStartTime = GetTimeForBenchmark()
    buffer.currentPlaybackIndex = 1
    debugFrameNumber = 0
    
end

function Benchmark_StopPlaying()
    
    if not Benchmark_GetIsPlaying() then
        Log("Wasn't playing-back!")
        return
    end
    
    Log("Playback stopped.")
    isPlaying = false
    
end

Event.Hook("UpdateRender", function()
    
    if Benchmark_GetIsRecording() then
        Benchmark_RecordFrame(GetTimeForBenchmark() - recordingStartTime)
    end
    
end)

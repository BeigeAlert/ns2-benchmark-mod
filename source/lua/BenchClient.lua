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

local kRecordingIconTexture = PrecacheAsset("ui/benchmark_recording_icon.dds")

local kRecordingFPS = 60 -- even THIS is probably too high...
local kRecordingTimeInterval = 1.0 / kRecordingFPS
local kInitialReservationRecordingTime = 5 * 60 -- 5 minutes is probably very excessive...
local kRecordingIconBaseScale = 2

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

function Benchmark_GetIsRecording()
    return isRecording == true
end

local buffer = {}
local function ClearBuffer()
    buffer = {}
    buffer.currentIndex = 0 -- last index written
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

local function SetBufferEntry_Timestamp(entry, time)
    entry[kBufferIdxTime] = time
end

local function SetBufferEntry_Position(entry, position)
    entry[kBufferIdxPosition] = position
end

local function SetBufferEntry_Angles(entry, angles)
    entry[kBufferIdxAngles] = angles
end

-- Can return nil on the first frame!!!
local function GetNewestBufferEntry()
    return buffer[buffer.currentIndex]
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

local function GetNextBufferEntryForWriting()
    
    buffer.currentIndex = buffer.currentIndex + 1
    
    -- Resize the buffer if we're run out of space!
    if buffer.currentIndex > #buffer then
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
            return time % 2 == 0, false
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

local recordingStartTimeReal = 0
function Benchmark_BeginRecording()
    
    if Benchmark_GetIsRecording() then
        Log("Benchmark is already recording!")
        return
    end
    
    CreateRecordingIcon()
    SetupBufferForRecording()
    recordingStartTimeReal = Shared.GetSystemTimeReal()
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
    for i=1, buffer.currentIndex do
        output[i] = GetBufferEntryAsListOfPrimitives(buffer[i])
    end
    
    local realFileName = "config://"..fileName..".ns2_benchmark"
    local writingFile = io.open(realFileName, "w+")
    writingFile:write(json.encode(output))
    io.close(writingFile)
    Log("Benchmark recording saved to \"%s\".", realFileName)

end

function Benchmark_Update(time)
    
    if not Benchmark_GetIsRecording() then
        return
    end
    
    local lastEntry = GetNewestBufferEntry()
    local lastRecordedFrameTime = lastEntry and lastEntry.timestamp or -999
    if time - lastRecordedFrameTime < kRecordingTimeInterval then
        return -- not enough time has passed yet to record another frame
    end
    
    local player = Client.GetLocalPlayer()
    if player == nil then
        Log("Warning!  Got nil player while recording!")
        return
    end
    
    if player.GetCameraViewCoords == nil then
        Log("Warning!  Got player without a CameraHolderMixin while recording!")
        return
    end
    
    local viewCoords = player:GetCameraViewCoords(true)
    local angles = Angles()
    angles:BuildFromCoords(viewCoords)
    
    local bufferEntry = GetNextBufferEntryForWriting()
    SetBufferEntry_Timestamp(bufferEntry, time)
    SetBufferEntry_Position(bufferEntry, viewCoords.origin)
    SetBufferEntry_Angles(bufferEntry, angles)
    
end

Event.Hook("UpdateRender", function()
    Benchmark_Update(Shared.GetSystemTimeReal() - recordingStartTimeReal)
end)

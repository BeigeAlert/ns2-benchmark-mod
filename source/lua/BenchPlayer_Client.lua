
local stupidBullshitHack = false -- See note in BenchCameraHolderMixin.lua
function Benchmark_SetGetCameraViewCoordsForRenderingIncoming(forRendering)
    stupidBullshitHack = forRendering
end

local old_Player_GetCameraViewCoordsOverride = Player.GetCameraViewCoordsOverride
function Player:GetCameraViewCoordsOverride(cameraCoords)
    
    if stupidBullshitHack then
        local result = Benchmark_GetCameraViewCoordsOverride(self, cameraCoords)
        if result ~= nil then
            return result
        end
    end
    
    return (old_Player_GetCameraViewCoordsOverride(self, cameraCoords))

end
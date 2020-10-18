local old_Player_GetCameraViewCoordsOverride = Player.GetCameraViewCoordsOverride
function Player:GetCameraViewCoordsOverride(cameraCoords)
    
    local result = Benchmark_GetCameraViewCoordsOverride(self, cameraCoords)
    if result ~= nil then
        return result
    end
    
    return (old_Player_GetCameraViewCoordsOverride(self, cameraCoords))

end
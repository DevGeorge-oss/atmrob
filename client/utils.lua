--[[
    CLIENT UTILS v1.0.0
    ─────────────────────────────────────────────────────────────
    Rope texture management helpers.
    GTA requires rope textures to be loaded before any rope
    can be created. We load on demand and unload when no ropes
    are active to keep memory clean.
    ─────────────────────────────────────────────────────────────
]]

Utils = {}

-- Load rope textures if not already loaded.
-- Blocks until textures are ready before returning.
function Utils.EnsureRopeTexturesLoaded()
    if not RopeAreTexturesLoaded() then
        RopeLoadTextures()
        while not RopeAreTexturesLoaded() do
            Wait(0)
        end
    end
end

-- Unload rope textures only when there are zero active ropes.
-- Call this after deleting a rope, not before.
function Utils.CleanupRopeTexturesIfUnused()
    local ropes = GetAllRopes()
    if type(ropes) == 'table' and #ropes == 0 then
        RopeUnloadTextures()
    end
end

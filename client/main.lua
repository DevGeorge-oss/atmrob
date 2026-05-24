--[[
    atmrob — ATM Robbery
    Author:  DevGbag
    GitHub:  https://github.com/DevGbag
    Org:     https://github.com/DevGeorge-oss
    License: MIT
]]

--[[
    CLIENT MAIN — ATM ROBBERY
    ─────────────────────────────────────────────────────────────
    TWO METHODS:

    HACK (standalone):
      Needs pl_hackingdevice.
      Progress bar → skillcheck minigame → single cash pile.

    DRILL + ROPE (combined, sequential):
      Needs pl_drill + pl_rope (both checked server-side).
      Step 1: Drill skillcheck (easy)
      Step 2: Drilling progress bar
      Step 3: Rope attaches automatically — player attaches
              other end to a nearby vehicle
      Step 4: Vehicle drives, rope pulls ATM loose
      Step 5: Rob detached ATM → single cash pile

    ROPE PHYSICS APPROACH:
      We work directly on the world ATM prop — no spawning copies.
      The world prop is set dynamic and frozen in place.
      When the vehicle has driven far enough, we unfreeze the ATM
      and apply a velocity impulse in the pull direction.
      The ATM physically moves as a dynamic object from that point.

    CASH PILES:
      Always ONE pile per robbery.
      Single pickup = single server event = single log line.
    ─────────────────────────────────────────────────────────────
]]

-- ── State ─────────────────────────────────────────────────────
local ropeAttachedATMs = {}   -- keyed by atmNetId

-- ── ATM model cash eject offsets ──────────────────────────────
local atmOffsets = {
    ['prop_atm_01']     = vector3( 0.072237, 0.50293, 0.779063),
    ['prop_atm_02']     = vector3( 0.01,     0.11,    0.92),
    ['prop_atm_03']     = vector3(-0.14,    -0.01,    0.88),
    ['prop_fleeca_atm'] = vector3( 0.127,    1.2,     1.0),
}

-- Only these ATM models support rope (they are standalone props)
local ropeCompatibleModels = {
    prop_fleeca_atm = true,
    prop_atm_02     = true,
    prop_atm_03     = true,
}

-- ── Helpers ───────────────────────────────────────────────────
local function GetModelName(hash)
    for name in pairs(atmOffsets) do
        if GetHashKey(name) == hash then return name end
    end
    return nil
end

local function Notify(msg, ntype)
    lib.notify({
        title       = 'ATM Robbery',
        description = msg,
        type        = ntype or 'inform',
        duration    = 4000,
    })
end

local function LoadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do Wait(0) end
    end
end

local function EnsureModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelValid(hash) then return false end
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) do
            Wait(0); t = t + 1
            if t > 200 then return false end
        end
    end
    return true
end

-- Request network control of an entity with a timeout
local function RequestControl(entity, ms)
    ms = ms or 1000
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local w = 0
    while not NetworkHasControlOfEntity(entity) and w < ms do
        Wait(50); w = w + 50
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

-- ── canInteract guard ─────────────────────────────────────────
--[[
    Prevents hack/drill options showing on an ATM that is
    currently in a rope state, or already robbed.
]]
local function CanInteract(entity)
    for _, st in pairs(ropeAttachedATMs) do
        local ent = NetworkGetEntityFromNetworkId(st.atmNetId)
        if ent ~= 0 and ent == entity then return false end
    end
    return true
end

-- ── Server validation ─────────────────────────────────────────
local function TryStartRobbery(method, coords, entity)
    NetworkRegisterEntityAsNetworked(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId == 0 then
        Notify(Locale('failed_robbery'), 'error')
        return false
    end

    local ok, reason = lib.callback.await('atmrob:server:startRobbery', false, method, coords, netId)
    if ok then return true end

    local msgs = {
        police   = Locale('not_enough_police'),
        cooldown = Locale('wait_robbery'),
        item     = method == 'drillrope' and Locale('no_items_drillrope') or 'You need a hacking device.',
    }
    Notify(msgs[reason] or Locale('failed_robbery'), 'error')
    return false
end

local function SendDispatch(method)
    TriggerServerEvent('atmrob:server:sendDispatch', method)
end

-- ── Register ATM model targets ────────────────────────────────
for _, model in ipairs(Config.AtmModels) do

    if Config.EnableHacking then
        exports.sleepless_interact:addModel(model, {
            label       = Locale('hack_atm_label'),
            name        = 'hack_' .. model,
            icon        = 'laptop-code',
            distance    = 2.0,
            canInteract = function(entity) return CanInteract(entity) end,
            onSelect    = function(data) TriggerEvent('atmrob:client:startHack', data.entity) end,
        })
    end

    if Config.EnableDrillRope and ropeCompatibleModels[model] then
        exports.sleepless_interact:addModel(model, {
            label       = Locale('drill_atm_label'),
            name        = 'drillrope_' .. model,
            icon        = 'screwdriver-wrench',
            distance    = 2.0,
            canInteract = function(entity) return CanInteract(entity) end,
            onSelect    = function(data) TriggerEvent('atmrob:client:startDrillRope', data.entity) end,
        })
    end
end

-- ── HACK ──────────────────────────────────────────────────────
AddEventHandler('atmrob:client:startHack', function(entity)
    if not entity or not DoesEntityExist(entity) then return end
    local coords = GetEntityCoords(entity)
    local ped    = PlayerPedId()

    if not IsPedHeadingTowardsPosition(ped, coords.x, coords.y, coords.z, 10.0) then
        TaskTurnPedToFaceCoord(ped, coords.x, coords.y, coords.z, 1500)
        Wait(1500)
    end

    if not TryStartRobbery('hack', coords, entity) then return end
    Wait(500)
    if Config.Police.notify then SendDispatch('hack') end

    lib.progressBar({
        duration     = Config.Hack.InitialDuration,
        label        = Locale('initializing_hack'),
        useWhileDead = false,
        canCancel    = false,
        disable      = { car = true, move = true, combat = true },
        anim         = { dict = 'missheist_jewel@hacking', clip = 'hack_loop' },
    })

    local success = lib.skillCheck(
        Config.Hack.Minigame.difficulty,
        Config.Hack.Minigame.inputs
    )

    if success then
        TriggerServerEvent('atmrob:server:hackSuccess')
        SpawnSingleCashPile(Config.Hack.Reward.cashModel, coords, GetEntityModel(entity), 'hack')
    else
        TriggerServerEvent('atmrob:server:robberyFailed', 'hack')
        Notify(Locale('failed_robbery'), 'error')
    end
end)

-- ── DRILL + ROPE ──────────────────────────────────────────────
AddEventHandler('atmrob:client:startDrillRope', function(entity)
    if not entity or not DoesEntityExist(entity) then return end
    local coords = GetEntityCoords(entity)
    local model  = GetEntityModel(entity)
    local ped    = PlayerPedId()

    if not IsPedHeadingTowardsPosition(ped, coords.x, coords.y, coords.z, 10.0) then
        TaskTurnPedToFaceCoord(ped, coords.x, coords.y, coords.z, 1500)
        Wait(1500)
    end

    if not TryStartRobbery('drillrope', coords, entity) then return end
    Wait(500)
    if Config.Police.notify then SendDispatch('drillrope') end

    -- Step 1: Drill skillcheck
    local drillOk = lib.skillCheck(
        Config.Drill.Minigame.difficulty,
        Config.Drill.Minigame.inputs
    )

    if not drillOk then
        TriggerServerEvent('atmrob:server:robberyFailed', 'drillrope')
        Notify(Locale('failed_robbery'), 'error')
        return
    end

    -- Step 2: Drilling progress bar
    lib.progressBar({
        duration     = Config.Drill.Duration,
        label        = Locale('drilling_atm'),
        useWhileDead = false,
        canCancel    = false,
        disable      = { car = true, move = true, combat = true },
        anim         = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
    })

    -- Recheck entity still exists after progress bar
    if not DoesEntityExist(entity) then
        Notify(Locale('failed_robbery'), 'error')
        return
    end

    -- Step 3: Begin rope phase automatically
    StartRopePhase(entity, coords, model)
end)

-- ── ROPE PHASE ────────────────────────────────────────────────
--[[
    We work directly on the world ATM prop.
    Key sequence:
    1. Request network control so we own the entity
    2. SetEntityDynamic(true) — allows physics to act on it
    3. SetEntityHasGravity(false) — stops it falling immediately
    4. FreezeEntityPosition(true) — holds it in place visually
       while the rope is being attached to a vehicle
    5. When vehicle has moved far enough (MonitorVehicleMovement),
       the server broadcasts detachATM to all clients
    6. In detachATM: unfreeze + apply velocity impulse in pull direction
       The ATM then physically slides/tumbles on the ground
]]
function StartRopePhase(atmEntity, atmCoords, atmModel)
    -- Request and confirm control before ANY physics changes
    -- Without confirmed ownership, SetEntityHasGravity has no effect
    local hasControl = RequestControl(atmEntity, 3000)
    if not hasControl then
        Notify(Locale('failed_robbery'), 'error')
        return
    end

    SetEntityDynamic(atmEntity, true)
    SetEntityHasGravity(atmEntity, false)
    SetEntityCollision(atmEntity, true, true)
    SetEntityVelocity(atmEntity, 0.0, 0.0, 0.0)
    SetEntityAngularVelocity(atmEntity, 0.0, 0.0, 0.0)
    FreezeEntityPosition(atmEntity, true)

    -- Wait two frames to ensure physics state is fully applied
    -- before handing off to the zeroing thread
    Wait(0)
    Wait(0)

    NetworkRegisterEntityAsNetworked(atmEntity)
    local atmNetId = NetworkGetNetworkIdFromEntity(atmEntity)

    ropeAttachedATMs[atmNetId] = {
        atmNetId        = atmNetId,
        model           = atmModel,
        wallCoords      = atmCoords,
        wallHeading     = GetEntityHeading(atmEntity),
        ropeAttached    = false,
        detached        = false,
    }

    CreateThread(function()
        local firstTick = true
        while ropeAttachedATMs[atmNetId] and not ropeAttachedATMs[atmNetId].detached do
            Wait(0)
            local ent = NetworkGetEntityFromNetworkId(atmNetId)
            if ent == 0 or not DoesEntityExist(ent) then break end
            if firstTick then
                FreezeEntityPosition(ent, false)
                firstTick = false
            end
            SetEntityVelocity(ent, 0.0, 0.0, 0.0)
            SetEntityAngularVelocity(ent, 0.0, 0.0, 0.0)
            -- Force heading to stay fixed while rope is attached
            SetEntityRotation(ent, 0.0, 0.0, GetEntityHeading(ent), 2, true)
        end
    end)

    Notify(Locale('rope_attached'), 'success')
    AddVehicleRopeTargets(atmNetId, atmEntity)
end

-- ── Vehicle rope targets ──────────────────────────────────────
function AddVehicleRopeTargets(atmNetId, atmEntity)
    local atmCoords = GetEntityCoords(atmEntity)
    for _, vehicle in pairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(atmCoords - GetEntityCoords(vehicle)) <= 20.0 then
            local vehNetId = NetworkGetNetworkIdFromEntity(vehicle)
            exports.sleepless_interact:addEntity(vehNetId, {
                label    = Locale('attach_rope_to_vehicle'),
                name     = 'attach_rope_' .. atmNetId,
                icon     = 'link',
                distance = 3.0,
                onSelect = function(data)
                    AttachRopeToVehicle(atmNetId, data.entity, vehNetId)
                end,
            })
            local st = ropeAttachedATMs[atmNetId]
            if st then
                st.targetedVehicles = st.targetedVehicles or {}
                table.insert(st.targetedVehicles, vehNetId)
            end
        end
    end
end

function RemoveVehicleRopeTargets(atmNetId)
    local st = ropeAttachedATMs[atmNetId]
    if not st or not st.targetedVehicles then return end
    for _, vehNetId in pairs(st.targetedVehicles) do
        exports.sleepless_interact:removeEntity(vehNetId, 'attach_rope_' .. atmNetId)
    end
    st.targetedVehicles = nil
end

function AttachRopeToVehicle(atmNetId, vehicle, vehicleNetId)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    local st = ropeAttachedATMs[atmNetId]
    if not st or st.ropeAttached then return end

    st.ropeAttached = true
    st.vehicleNetId = vehicleNetId

    TriggerServerEvent('atmrob:server:attachVehicle', {
        atmNetId     = atmNetId,
        vehicleNetId = vehicleNetId,
    })

    Notify(Locale('rope_vehicle_attached'), 'success')
    RemoveVehicleRopeTargets(atmNetId)
    MonitorVehicleMovement(atmNetId)
end

-- ── Vehicle movement monitor ──────────────────────────────────
--[[
    Runs every 100ms while rope is attached.
    Tracks how far the vehicle has moved from its initial position.
    When RequiredDistance is reached, fires requestDetach on server.
    Server validates and broadcasts detachATM to all clients.
]]
function MonitorVehicleMovement(atmNetId)
    CreateThread(function()
        local st = ropeAttachedATMs[atmNetId]
        if not st or not st.vehicleNetId then return end

        local atmEntity = NetworkGetEntityFromNetworkId(atmNetId)
        local vehicle   = NetworkGetEntityFromNetworkId(st.vehicleNetId)
        if atmEntity == 0 or vehicle == 0 then return end

        local initVehCoords = GetEntityCoords(vehicle)

        while ropeAttachedATMs[atmNetId]
            and ropeAttachedATMs[atmNetId].ropeAttached
            and not ropeAttachedATMs[atmNetId].detached
        do
            Wait(100)
            vehicle = NetworkGetEntityFromNetworkId(st.vehicleNetId)
            if vehicle == 0 then break end

            local curVehCoords = GetEntityCoords(vehicle)
            local vehDist      = #(curVehCoords - initVehCoords)
            local ropeLen      = #(curVehCoords - GetEntityCoords(
                NetworkGetEntityFromNetworkId(atmNetId)
            ))

            -- Rope snapped — too far
            if ropeLen > Config.RopeRobbery.MaxRopeLength then
                Notify(Locale('rope_robbery_failed'), 'error')
                ropeAttachedATMs[atmNetId] = nil
                break
            end

            -- Vehicle has moved far enough — trigger detach
            if vehDist >= Config.RopeRobbery.RequiredDistance then
                TriggerServerEvent('atmrob:server:requestDetach', {
                    atmNetId     = atmNetId,
                    vehicleNetId = st.vehicleNetId,
                })
                break
            end
        end
    end)
end

-- ── Rope create (broadcast to all clients) ────────────────────
RegisterNetEvent('atmrob:client:createRope', function(payload)
    if type(payload) ~= 'table' or not payload.atmNetId or not payload.vehicleNetId then return end

    local atmEntity = NetworkGetEntityFromNetworkId(payload.atmNetId)
    local vehicle   = NetworkGetEntityFromNetworkId(payload.vehicleNetId)
    if atmEntity == 0 or vehicle == 0 then return end

    -- Don't create a second rope if one already exists for this ATM
    if ropeAttachedATMs[payload.atmNetId] and ropeAttachedATMs[payload.atmNetId].rope then return end

    local atmFwd   = GetEntityForwardVector(atmEntity)
    local atmPt    = GetEntityCoords(atmEntity) + (atmFwd * 0.5) + vector3(0, 0, 0.0)
    local vehPt    = GetOffsetFromEntityInWorldCoords(vehicle, 0, -2.0, 0.5)
    local ropeLen  = #(atmPt - vehPt)

    Utils.EnsureRopeTexturesLoaded()

    local rope = AddRope(
        atmPt.x, atmPt.y, atmPt.z,
        0.0, 0.0, 0.0,
        ropeLen, 0, ropeLen,
        ropeLen * 0.8, 1.0,
        false, true, false, 1.0, true
    )

    if not DoesRopeExist(rope) then
        Utils.CleanupRopeTexturesIfUnused()
        return
    end

    AttachEntitiesToRope(
        rope, atmEntity, vehicle,
        atmPt.x, atmPt.y, atmPt.z - 0.2,
        vehPt.x, vehPt.y, vehPt.z - 0.2,
        ropeLen, false, false, '', ''
    )

    ropeAttachedATMs[payload.atmNetId] = ropeAttachedATMs[payload.atmNetId] or {}
    local st        = ropeAttachedATMs[payload.atmNetId]
    st.atmNetId     = payload.atmNetId
    st.vehicleNetId = payload.vehicleNetId
    st.rope         = rope
    st.ropeAttached = true
    st.detached     = st.detached or false
end)

-- ── Detach ATM (broadcast to all clients) ────────────────────
--[[
    This is the moment the ATM physically separates from the wall.
    We unfreeze it and apply a velocity in the vehicle's pull direction.
    The ATM slides/tumbles on the ground from this point.

    Velocity formula: normalised direction * force
    We use a moderate forward force and NO negative Z — the ATM
    should slide along the ground, not be launched downward.
    Gravity (re-enabled here) will handle the downward component.
]]
RegisterNetEvent('atmrob:client:detachATM', function(payload)
    local atmEntity = NetworkGetEntityFromNetworkId(payload.atmNetId)
    local vehicle   = NetworkGetEntityFromNetworkId(payload.vehicleNetId)
    if atmEntity == 0 then return end

    -- Mark detached so the velocity-zeroing thread stops
    ropeAttachedATMs[payload.atmNetId]              = ropeAttachedATMs[payload.atmNetId] or {}
    ropeAttachedATMs[payload.atmNetId].detached     = true
    ropeAttachedATMs[payload.atmNetId].ropeAttached = false

    -- Wait for zeroing thread to fully exit before applying impulse
    Wait(150)

    RequestControl(atmEntity, 500)
    local atmCoords = GetEntityCoords(atmEntity)

    -- Re-enable gravity so ATM falls naturally after being pulled
    SetEntityHasGravity(atmEntity, true)

    -- Apply pull impulse in vehicle's direction
    if vehicle ~= 0 then
        local vehCoords = GetEntityCoords(vehicle)
        local dir = vehCoords - atmCoords
        local len = #dir
        if len > 0 then
            dir = dir / len
            SetEntityVelocity(atmEntity, dir.x * 6.0, dir.y * 6.0, 1.5)
        end
    end

    SetEntityAngularVelocity(atmEntity, 1.5, 1.5, 3.0)

    Notify(Locale('atm_detached'), 'success')

    --[[
        Use addCoords instead of addEntity.
        The ATM entity may lose stable network registration after being
        physically moved. addCoords is purely position-based and doesn't
        depend on entity network state at all.
        We wait 2 seconds for the ATM to land, then sample its position.
    ]]
    local atmNetId = payload.atmNetId
    CreateThread(function()
        Wait(2000)

        local ent = NetworkGetEntityFromNetworkId(atmNetId)
        if ent == 0 or not DoesEntityExist(ent) then return end

        local landedCoords = GetEntityCoords(ent)
        local coordId = exports.sleepless_interact:addCoords(landedCoords, {
            label    = Locale('rob_detached_atm'),
            name     = 'rob_detached',
            icon     = 'money-bill-wave',
            distance = 2.0,
            onSelect = function(data)
                -- Remove coord interact and rob the ATM
                exports.sleepless_interact:removeCoords(coordId)
                RobDetachedATM(ent, atmCoords, GetEntityModel(ent), atmNetId)
            end,
        })
    end)
end)

-- ── Rope cleanup (broadcast to all clients) ───────────────────
RegisterNetEvent('atmrob:client:cleanupRope', function(payload)
    if type(payload) ~= 'table' or not payload.atmNetId then return end
    local st = ropeAttachedATMs[payload.atmNetId]
    if st and st.rope and DoesRopeExist(st.rope) then DeleteRope(st.rope) end
    ropeAttachedATMs[payload.atmNetId] = nil
    Utils.CleanupRopeTexturesIfUnused()
end)

-- ── Rob detached ATM ─────────────────────────────────────────
function RobDetachedATM(entity, atmCoords, atmModel, atmNetId)
    if not entity or not DoesEntityExist(entity) then return end
    local st = ropeAttachedATMs[atmNetId]

    if st and st.rope and DoesRopeExist(st.rope) then DeleteRope(st.rope) end

    -- Store wall data before clearing state
    local wallCoords  = st and st.wallCoords
    local wallHeading = st and st.wallHeading
    local wallModel   = st and st.model

    -- Get where the ATM landed and its model before deleting it
    local landedCoords = GetEntityCoords(entity)
    local landedModel  = GetEntityModel(entity)
    local modelName    = GetModelName(landedModel) or 'prop_fleeca_atm'

    ropeAttachedATMs[atmNetId] = nil
    Utils.CleanupRopeTexturesIfUnused()
    DeleteEntity(entity)

    SpawnSingleCashPile(
        Config.RopeReward.cashModel,
        landedCoords,
        landedModel,
        'drillrope',
        wallCoords,
        wallHeading,
        wallModel or modelName
    )
end

-- ── Single cash pile ─────────────────────────────────────────
--[[
    One pile per robbery. Single server event on pickup.
]]
function SpawnSingleCashPile(cashModel, atmCoords, atmModelHash, method, wallCoords, wallHeading, wallModel)
    if not cashModel or cashModel == '' then return end
    if not EnsureModel(cashModel) then return end

    local modelName = atmModelHash and atmModelHash ~= 0 and GetModelName(atmModelHash) or nil
    local offset    = (modelName and atmOffsets[modelName]) or vector3(0, 0, 0.5)
    local dropPos   = atmCoords + offset

    local cash = CreateObject(GetHashKey(cashModel), dropPos.x, dropPos.y, dropPos.z, true, true, true)
    SetEntityVelocity(cash, 0.0, 0.0, 0.3)

    local cashNetId = NetworkGetNetworkIdFromEntity(cash)

    exports.sleepless_interact:addEntity(cashNetId, {
        label    = Locale('pick_up_cash'),
        name     = 'pickup_cash',
        icon     = 'money-bill-wave',
        distance = Config.CashProp.pickupDistance,
        onSelect = function(data)
            PickupCash(data.entity, cashNetId, method, wallCoords, wallHeading, wallModel)
        end,
    })
end

function PickupCash(entity, cashNetId, method, wallCoords, wallHeading, wallModel)
    if not DoesEntityExist(entity) then return end
    LoadAnimDict('pickup_object')
    TaskPlayAnim(PlayerPedId(), 'pickup_object', 'pickup_low', 8.0, -8.0, -1, 48, 0, false, false, false)
    Wait(1000)
    if DoesEntityExist(entity) then
        exports.sleepless_interact:removeEntity(cashNetId)
        DeleteEntity(entity)
        TriggerServerEvent('atmrob:server:cashPickedUp', method)

        -- Respawn ATM at original wall position
        -- This ensures the world looks correct for all players
        -- without waiting for GTA streaming to restream the area
        if wallCoords and wallHeading and wallModel and wallModel ~= 0 then
            local hash = type(wallModel) == 'number' and wallModel or GetHashKey(wallModel)
            if hash ~= 0 and IsModelValid(hash) then
                RequestModel(hash)
                while not HasModelLoaded(hash) do Wait(0) end
                local newAtm = CreateObject(hash, wallCoords.x, wallCoords.y, wallCoords.z, false, false, false)
                SetEntityHeading(newAtm, wallHeading)
                SetEntityDynamic(newAtm, false)
                FreezeEntityPosition(newAtm, true)
                SetModelAsNoLongerNeeded(hash)
            end
        end
    end
    ClearPedTasks(PlayerPedId())
end

-- ── Client notification relay ─────────────────────────────────
RegisterNetEvent('atmrob:client:notify')
AddEventHandler('atmrob:client:notify', function(msg, ntype)
    Notify(msg, ntype)
end)

-- ── Resource stop cleanup ─────────────────────────────────────
--[[
    On resource stop, restore any ATMs we modified back to their
    default static state so they appear correctly for other players.
    GTA's world streaming system will handle natural respawning.
    We do NOT delete world ATM props — that causes them to disappear
    permanently until the area is restreamed.
]]
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, st in pairs(ropeAttachedATMs) do
        if st.rope and DoesRopeExist(st.rope) then DeleteRope(st.rope) end
        local ent = NetworkGetEntityFromNetworkId(st.atmNetId)
        if ent ~= 0 and DoesEntityExist(ent) then
            FreezeEntityPosition(ent, false)
            SetEntityHasGravity(ent, true)
            SetEntityDynamic(ent, false)
        end
    end
    ropeAttachedATMs = {}
    Utils.CleanupRopeTexturesIfUnused()
end)

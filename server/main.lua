--[[
    atmrob — ATM Robbery
    Author:  DevGbag
    GitHub:  https://github.com/DevGbag
    Org:     https://github.com/DevGeorge-oss
    License: MIT
]]

--[[
    SERVER MAIN — ATM ROBBERY
    ─────────────────────────────────────────────────────────────
    All qbx_core interactions use direct exports per docs:
    https://docs.qbox.re/resources/qbx_core/exports/server

    Key exports used:
      exports.qbx_core:AddMoney(source, moneyType, amount, reason)
      exports.qbx_core:GetDutyCountJob(job) -> count, players[]
      exports.qbx_core:Notify(source, text, type, duration)

    ox_inventory:
      exports.ox_inventory:RemoveItem(source, item, count)
    ─────────────────────────────────────────────────────────────
]]

local lastRobberyTime = 0
local robberyState    = {}

-- ── Money ─────────────────────────────────────────────────────
local function AddMoney(src, moneyType, amount)
    return exports.qbx_core:AddMoney(src, moneyType, amount, 'ATM Robbery')
end

-- ── Inventory ─────────────────────────────────────────────────
local function RemoveItem(src, item, amount)
    return exports.ox_inventory:RemoveItem(src, item, amount)
end

-- ── Notifications ─────────────────────────────────────────────
local function NotifyPlayer(src, message, ntype)
    exports.qbx_core:Notify(src, message, ntype or 'inform', 4000)
end

-- ── Exploit logging ───────────────────────────────────────────
local function LogExploit(src, msg)
    local name = GetPlayerName(src) or 'Unknown'
    local ids  = GetPlayerIdentifiers(src)
    print(('^1[atmrob:exploit] ^7%s (%s): %s'):format(name, ids and ids[1] or '?', msg))
end

-- ── Police ────────────────────────────────────────────────────
--[[
    GetDutyCountJob(job) returns:
      count   — number of on-duty players in that job
      players — array of their server IDs
    We sum across all configured police jobs.
]]
local function HasEnoughPolice()
    if Config.Police.required == 0 then return true end
    local total = 0
    for _, job in pairs(Config.Police.Job) do
        local count = exports.qbx_core:GetDutyCountJob(job)
        total = total + (count or 0)
    end
    return total >= Config.Police.required
end

local function GetPolicePlayers()
    local result = {}
    for _, job in pairs(Config.Police.Job) do
        local _, players = exports.qbx_core:GetDutyCountJob(job)
        if type(players) == 'table' then
            for _, pid in pairs(players) do
                result[#result + 1] = pid
            end
        end
    end
    return result
end

-- ── Cooldown ──────────────────────────────────────────────────
local function CheckCooldown()
    if lastRobberyTime == 0 then return true end
    return os.time() - lastRobberyTime >= Config.CooldownTimer
end

-- ── Validation helpers ────────────────────────────────────────
local function NormalizeCoords(c)
    if type(c) ~= 'vector3' and type(c) ~= 'vector4' and type(c) ~= 'table' then return nil end
    if type(c.x) ~= 'number' or type(c.y) ~= 'number' or type(c.z) ~= 'number' then return nil end
    return vector3(c.x, c.y, c.z)
end

local function PlayerNearCoords(src, coords, dist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= dist
end

local function GetNetEntity(netId)
    if type(netId) ~= 'number' then return nil end
    local e = NetworkGetEntityFromNetworkId(netId)
    return (e and e ~= 0 and DoesEntityExist(e)) and e or nil
end

local function IsStateExpired(state)
    return not state or not state.time or os.time() - state.time > 300
end

-- ── Reward by method ─────────────────────────────────────────
local function GetReward(method)
    if method == 'hack'      then return Config.Hack.Reward.moneyType,   Config.Hack.Reward.amount   end
    if method == 'drillrope' then return Config.RopeReward.moneyType,    Config.RopeReward.amount    end
end

-- ── Start robbery callback ────────────────────────────────────
lib.callback.register('atmrob:server:startRobbery', function(src, method, atmCoords, atmNetId)
    local coords = NormalizeCoords(atmCoords)
    if not coords then LogExploit(src, 'invalid coords'); return false, 'invalid' end

    if method ~= 'hack' and method ~= 'drillrope' then
        LogExploit(src, 'invalid method: ' .. tostring(method))
        return false, 'invalid'
    end

    if method == 'hack'      and not Config.EnableHacking   then return false, 'disabled' end
    if method == 'drillrope' and not Config.EnableDrillRope then return false, 'disabled' end

    if not PlayerNearCoords(src, coords, 5.0) then
        LogExploit(src, 'too far from ATM')
        return false, 'too_far'
    end

    if not HasEnoughPolice() then return false, 'police'   end
    if not CheckCooldown()   then return false, 'cooldown' end

    -- Item removal
    if method == 'hack' then
        if not RemoveItem(src, Config.HackingItem, 1) then
            return false, 'item'
        end
    elseif method == 'drillrope' then
        local drillOk = RemoveItem(src, Config.DrillItem, 1)
        if not drillOk then return false, 'item' end
        local ropeOk = RemoveItem(src, Config.RopeItem, 1)
        if not ropeOk then
            exports.ox_inventory:AddItem(src, Config.DrillItem, 1)
            return false, 'item'
        end
    end

    lastRobberyTime = os.time()

    robberyState[src] = {
        method    = method,
        atmCoords = coords,
        atmNetId  = atmNetId,
        time      = os.time(),
    }

    return true
end)

-- ── Hack success ─────────────────────────────────────────────
RegisterNetEvent('atmrob:server:hackSuccess')
AddEventHandler('atmrob:server:hackSuccess', function()
    local src   = source
    local state = robberyState[src]

    if not state or state.method ~= 'hack' then
        LogExploit(src, 'hack success without valid state')
        return
    end

    if IsStateExpired(state) or not PlayerNearCoords(src, state.atmCoords, 5.0) then
        robberyState[src] = nil
        LogExploit(src, 'hack success state expired or too far')
        return
    end

    -- Minimum time: progress bar + at least 3s for minigame
    local minTime = math.ceil(Config.Hack.InitialDuration / 1000) + 3
    if os.time() - state.time < minTime then
        robberyState[src] = nil
        LogExploit(src, 'hack completed impossibly fast')
        return
    end
end)

-- ── Cash picked up ───────────────────────────────────────────
RegisterNetEvent('atmrob:server:cashPickedUp')
AddEventHandler('atmrob:server:cashPickedUp', function(method)
    local src   = source
    local state = robberyState[src]

    if not state or state.method ~= method then
        LogExploit(src, 'cash pickup with mismatched state')
        return
    end

    if IsStateExpired(state) then
        robberyState[src] = nil
        LogExploit(src, 'cash pickup state expired')
        return
    end

    if not PlayerNearCoords(src, state.atmCoords, 15.0) then
        robberyState[src] = nil
        LogExploit(src, 'cash pickup too far from ATM')
        return
    end

    local moneyType, amount = GetReward(method)
    if not moneyType then robberyState[src] = nil; return end

    local ok = AddMoney(src, moneyType, amount)
    if not ok then
        print(('^1[atmrob] AddMoney failed for player %s — check moneyType "%s" is valid^7'):format(src, moneyType))
    end

    print(('^2[atmrob] %s collected $%d (%s) via %s^7'):format(
        GetPlayerName(src) or 'Unknown', amount, moneyType, method
    ))

    NotifyPlayer(src, ('You collected $%d'):format(amount), 'success')
    robberyState[src] = nil
end)

-- ── Robbery failed ────────────────────────────────────────────
RegisterNetEvent('atmrob:server:robberyFailed')
AddEventHandler('atmrob:server:robberyFailed', function()
    robberyState[source] = nil
end)

-- ── Dispatch ─────────────────────────────────────────────────
RegisterNetEvent('atmrob:server:sendDispatch')
AddEventHandler('atmrob:server:sendDispatch', function(method)
    local msg = method == 'drillrope'
        and Locale('dispatch_drillrope')
        or  Locale('dispatch_hack')

    for _, pid in pairs(GetPolicePlayers()) do
        NotifyPlayer(pid, msg, 'warning')
    end
end)

-- ── Rope: attach vehicle ──────────────────────────────────────
RegisterNetEvent('atmrob:server:attachVehicle')
AddEventHandler('atmrob:server:attachVehicle', function(payload)
    local src   = source
    local state = robberyState[src]

    if type(payload) ~= 'table' or not payload.atmNetId or not payload.vehicleNetId then return end

    if not state or state.method ~= 'drillrope' or IsStateExpired(state) then
        LogExploit(src, 'rope attach without valid drillrope state')
        return
    end

    local atmEnt = GetNetEntity(payload.atmNetId)
    local vehEnt = GetNetEntity(payload.vehicleNetId)
    if not atmEnt or not vehEnt then
        LogExploit(src, 'rope attach with invalid entities')
        return
    end

    local atmCoords = GetEntityCoords(atmEnt)
    local vehCoords = GetEntityCoords(vehEnt)

    if not PlayerNearCoords(src, atmCoords, 10.0) then
        LogExploit(src, 'player too far from ATM on rope attach')
        return
    end

    if #(vehCoords - atmCoords) > 25.0 then
        LogExploit(src, 'vehicle too far from ATM for rope attach')
        return
    end

    state.atmNetId             = payload.atmNetId
    state.vehicleNetId         = payload.vehicleNetId
    state.initialVehicleCoords = vehCoords
    state.time                 = os.time()
    robberyState[src]          = state

    TriggerClientEvent('atmrob:client:createRope', -1, {
        atmNetId     = payload.atmNetId,
        vehicleNetId = payload.vehicleNetId,
    })
end)

-- ── Rope: request detach ──────────────────────────────────────
RegisterNetEvent('atmrob:server:requestDetach')
AddEventHandler('atmrob:server:requestDetach', function(payload)
    local src   = source
    local state = robberyState[src]

    if type(payload) ~= 'table' or not payload.atmNetId or not payload.vehicleNetId then return end

    if not state or state.method ~= 'drillrope'
        or state.atmNetId     ~= payload.atmNetId
        or state.vehicleNetId ~= payload.vehicleNetId
    then
        LogExploit(src, 'detach request with invalid state')
        return
    end

    local vehEnt = GetNetEntity(payload.vehicleNetId)
    if not vehEnt then return end

    local vehDist = #(GetEntityCoords(vehEnt) - state.initialVehicleCoords)
    if vehDist < 0.5 then
        LogExploit(src, 'detach requested before vehicle moved')
        return
    end

    state.detached    = true
    robberyState[src] = state

    TriggerClientEvent('atmrob:client:detachATM', -1, {
        atmNetId     = payload.atmNetId,
        vehicleNetId = payload.vehicleNetId,
    })
end)

-- ── Disconnect cleanup ────────────────────────────────────────
AddEventHandler('playerDropped', function()
    robberyState[source] = nil
end)

-- ── Startup ──────────────────────────────────────────────────
AddEventHandler('onServerResourceStart', function(name)
    if name ~= GetCurrentResourceName() then return end
    if Config.DebugPrints then
        print('^2[atmrob] Server started^7')
        print('^2[atmrob] qbx_core:  ' .. (GetResourceState('qbx_core')    == 'started' and '^2ok^7' or '^1MISSING^7'))
        print('^2[atmrob] ox_inventory: ' .. (GetResourceState('ox_inventory') == 'started' and '^2ok^7' or '^1MISSING^7'))
    end
end)

Config = {}

--[[
    CONFIG — ATM ROBBERY
    ─────────────────────────────────────────────────────────────
    Shared between client and server. Pure data only.

    METHODS:
      hack      — standalone, solo. Progress bar + skillcheck.
                  Reward: single cash pile.

      drillrope — two step combined method.
                  Step 1: drill skillcheck (easy)
                  Step 2: rope attaches automatically
                  Step 3: attach to vehicle, drive to pull ATM
                  Step 4: rob detached ATM
                  Reward: single cash pile, higher value.

    ITEMS:
      Acquisition method left to the server — no shop in this script.
      Item names must match ox_inventory registration exactly.

    MONEY:
      Uses exports.qbx_core:AddMoney(source, moneyType, amount, reason)
      Valid moneyType: 'cash' | 'bank' | 'crypto'
]]

Config.DebugPrints = true
Config.Locale      = 'en'

-- ── Items ──────────────────────────────────────────────────────
Config.HackingItem = 'pl_hackingdevice'
Config.DrillItem   = 'pl_drill'
Config.RopeItem    = 'pl_rope'

-- ── Methods ────────────────────────────────────────────────────
Config.EnableHacking   = true
Config.EnableDrillRope = true

-- ── ATM models ─────────────────────────────────────────────────
Config.AtmModels = {
    'prop_fleeca_atm',
    'prop_atm_01',
    'prop_atm_02',
    'prop_atm_03',
}

-- ── Rope physics ───────────────────────────────────────────────
Config.RopeRobbery = {
    RequiredDistance = 2.0,    -- metres vehicle must travel to trigger detach
    MaxRopeLength    = 25.0,   -- rope snaps beyond this distance
}

-- ── Hack ───────────────────────────────────────────────────────
Config.Hack = {
    InitialDuration = 2000,    -- progress bar before skillcheck (ms)
    Minigame = {
        difficulty = { 'medium', 'hard', 'hard' },
        inputs     = { 'w', 'a', 's', 'd' },
    },
    Reward = {
        moneyType = 'cash',    -- 'cash' | 'bank' | 'crypto'
        amount    = 1000,
        cashModel = 'prop_anim_cash_pile_01',
    },
}

-- ── Drill ──────────────────────────────────────────────────────
Config.Drill = {
    Duration = 5000,           -- drilling progress bar (ms)
    Minigame = {
        difficulty = { 'meduim', 'hard', 'hard' },
        inputs     = { 'w', 'a', 's', 'd' },
    },
}

-- ── Rope reward ────────────────────────────────────────────────
Config.RopeReward = {
    moneyType = 'cash',        -- 'cash' | 'bank' | 'crypto'
    amount    = 2000,
    cashModel = 'hei_prop_heist_cash_pile',
}

-- ── Cash prop ──────────────────────────────────────────────────
Config.CashProp = {
    pickupDistance = 1.5,
    ejectForce     = 2.0,
}

-- ── Cooldown ───────────────────────────────────────────────────
Config.CooldownTimer = 60      -- seconds between robberies server-wide

-- ── Police ─────────────────────────────────────────────────────
Config.Police = {
    notify   = true,
    required = 0,              -- 0 = always allowed
    Job      = { 'police' },
}

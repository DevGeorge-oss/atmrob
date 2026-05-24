--[[
    LOCALE SYSTEM
    ─────────────────────────────────────────────────────────────
    Locale() is a shared helper used on both client and server.
    It reads from the JSON file matching Config.Locale.
    e.g. Config.Locale = 'en' loads locales/en.json

    Usage anywhere:
        Locale('hack_atm_label')  →  "Hack ATM"
    ─────────────────────────────────────────────────────────────
]]

LocalLang = {}

local function LoadLocale(lang)
    local file = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(lang))
    if file then
        LocalLang = json.decode(file)
    else
        print(('[atmrob] Locale file not found for language: %s — falling back to en'):format(lang))
        local fallback = LoadResourceFile(GetCurrentResourceName(), 'locales/en.json')
        if fallback then LocalLang = json.decode(fallback) end
    end
end

function Locale(key)
    return LocalLang[key] or ('[MISSING LOCALE: %s]'):format(key)
end

LoadLocale(Config.Locale)

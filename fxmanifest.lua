fx_version 'cerulean'
lua54 'yes'
game 'gta5'

name        'atmrob'
author      'DevGbag'
description 'ATM Robbery — Qbox / ox_inventory / sleepless_interact'
version     '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'locales/locale.lua',
}

client_scripts {
    '@sleepless_interact/init.lua',
    'client/utils.lua',
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'ox_inventory',
    'sleepless_interact',
}

-- Popcorn debug metadata
set 'popcorn_items'    'pl_hackingdevice,pl_drill,pl_rope'

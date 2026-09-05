--[[ FX Information ]] --
fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'

--[[ Resource Information ]] --
name 'altv_ox_props'
version '1.0.0'
license 'proprietary'
author 'Ethan Kerdelhue'
description 'Per-set, FiveM/ox-lib prop placement and marking with an in-game gizmo editor'
repository 'https://github.com/ethanke/altv_ox_props'

--[[ Manifest ]] --
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/dataview.lua',
    'client/main.lua',
    'client/editor.lua',
    'client/menu.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/storage.lua',
    'server/validation.lua',
    'server/main.lua',
}

files {
    'config.lua',
    'locales/*.json',
    'data/catalog.lua',
    'web/index.html',
    'web/app.js',
    'web/catalog.js',
    'web/preview.js',
    'web/style.css',
}

ui_page 'web/index.html'

dependencies {
    'ox_lib',
    'oxmysql',
}

ox_libs {
    'locale',
}

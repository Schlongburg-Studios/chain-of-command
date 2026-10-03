fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cmd_chain'
description 'Chain of Command: departments, ranks, divisions, callsigns and permissions for QBCore and Qbox'
version '1.1.0'
license 'MIT'

dependencies {
    'ox_lib',
    'oxmysql',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'bridge/qbx.lua', -- checked first: Qbox also provides 'qb-core'
    'bridge/qb.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/audit.lua',
    'server/main.lua',
    'server/api.lua',
}

client_scripts {
    'client/main.lua',
}

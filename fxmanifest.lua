fx_version "cerulean"
game "gta5"
author "Malizniak - 17Movement"
lua54 "yes"
version "3.0.27"

shared_script "Config.lua"

client_scripts {
    "client/target.lua",
    "client/functions.lua",
    "client/client.lua",
}

server_scripts {
    "server/functions.lua",
    "server/server.lua",
}

ui_page "web/driver.html"
files {
    "web/**/*.**",
    "web/*.**",
    "stream/*.**",
}

escrow_ignore {
    "Config.lua",
    "client/target.lua",
    "client/functions.lua",
    "server/functions.lua",
    "stream/*.**",
}

data_file 'VEHICLE_METADATA_FILE'    'stream/vehicles.meta'
data_file 'CARCOLS_FILE'             'stream/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE'   'stream/carvariations.meta'

dependency '/assetpacks'
-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local _, _, _, interface = GetBuildInfo()
ML.IsForever = type(interface) == "number" and interface >= 16000 and interface < 17000
ML.CatalogAddon = ML.IsForever and "MobLog_ForeverDB" or "MobLog_TrinityDB"
ML.ClientCapitals = ML.IsForever and {
    [1453] = true, -- Stormwind
    [1454] = true, -- Orgrimmar
    [1455] = true, -- Ironforge
    [1456] = true, -- Thunder Bluff
    [1457] = true, -- Darnassus
    [1458] = true, -- Undercity
} or nil

function ML.CatalogMatchesClient(data)
    if not data then return false end
    return ML.IsForever == (data.client == "forever")
end

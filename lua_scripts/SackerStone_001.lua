-- SackerStone_001.lua

-- ***********************TODO***************************
-- Add ability to manually set balance
-- Add ability to add location to favorite
-- Add ability to adjust color rarity drop rates
-- Add ability to change profession cap
-- **************************************************


local SRC = "SackerStone"
local ITEM_ID = 69000
local XP_MULT_DEF = 1
local XP_MULT_ID = 1
local TELE_PAGE_ID = 2
local TELE_PAGE_DEF = 1
local TELE_SEARCH_ID = 3
local TELE_SEARCH_DEF = ""
local TELE_RESULTS_ID = 4
local TELE_RESULTS_DEF = {}
local TELE_PAGE_SIZE = 20

local SACKER_SEARCH_CREATE = "CREATE TABLE IF NOT EXISTS `mod_sacker_searches` ( `guid` INT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Global Unique Identifier',	`account` INT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Account Identifier',	`page` INT UNSIGNED NOT NULL DEFAULT '1' COMMENT 'Search Page',	`search` VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'Search Query' COLLATE 'utf8mb4_general_ci',	`xp` FLOAT UNSIGNED NULL DEFAULT '1' COMMENT 'XP Rate',	PRIMARY KEY (`guid`) USING BTREE,	INDEX `account` (`account`) USING BTREE)COLLATE='utf8mb4_general_ci'ENGINE=InnoDB;"
local XP_GET_QUERY = "SELECT xp FROM mod_sacker_searches WHERE guid = ?;"
local XP_SET_QUERY = "INSERT INTO mod_sacker_searches (guid, xp) VALUES (?, ?) ON DUPLICATE KEY UPDATE xp = VALUES(xp);"

local TELE_MAP_QUERY = "SELECT id, name, COUNT(*) OVER() AS total FROM game_tele WHERE name LIKE ? LIMIT ? OFFSET ?;"
local TELE_GET_QUERY = "SELECT page, search FROM mod_sacker_searches WHERE guid = ?;"
local TELE_SET_QUERY = "INSERT INTO mod_sacker_searches (guid, page, search) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE page = VALUES(page), search = VALUES(search);"
local REQUEST_MAP = {}
local NextQueryID

do
    local query_id = 0

    NextQueryID = function()
        query_id = query_id + 1
        return query_id
    end
end
function CreateSQLRequest(player_guid_low, req_id, page, search, prepared_stmt, exec_func)
    -- Execute query with given function
    REQUEST_MAP[player_guid_low] = {
        request_id = req_id,
        sql = prepared_stmt,
        results = {},
        page = page,
        search = search
    }
    for i, v in pairs(REQUEST_MAP) do
        --print(v.request_id, v.sql)
        end
    exec_func(prepared_stmt)
    -- Return request
    return REQUEST_MAP[player_guid_low]
end
--[[
Sender:
1 = Sacker Menu
2 = XP Menu
3 = Teleport Menu
4 = Money Select Menu
5 = Money Menu
]]

local BUILD_MAP = {}
local SELECT_MAP = {}
local TELE_RESULTS = {}
local XP_MAP = {0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 5, 10, 100}

-- **************************************************

local function sql_value(v)
    if v == nil then
        return "NULL"
    end
    local t = type(v)
    if t == "boolean" then
        return v and "1" or "0"
    elseif t == "number" then
        return tostring(v)
    elseif t == "string" then
        return "'" .. tostring(v):gsub("'", "''") .. "'"
    else
        error("Unable to prepare type: ".. tostring(t))
    end
end

local function PrepareSQL(query, params)
    print("Preparing SQL: "..query)
    print("With params:")
    for i, v in ipairs(params) do
        print(i, v, sql_value(v))
        query = query:gsub("%?", sql_value(v), 1)
        ----print("Result: "..query)
    end
    print("Prepared SQL: "..query)
    return query
end

-- **************************************************

local function Filter(list, predicate)
    local matches = {}
    for key, value in pairs(list) do
        if predicate(value) then matches[#matches+1] = {key, value} end
    end
    return matches
end

local function Split(str, indexes)
    if #indexes == 0 then return {str} end
    local split = {}
    local start = 1
    for i, idx in ipairs(indexes) do
        if i ~= #indexes then
            -- there is another delimiter, get substring to next delimiter
            split[#split+1] = string.sub(str, start, indexes[i+1])
            -- set start to next delimiter+1
            start = indexes[i+1]+1
        else
            -- Last delimiter, go to end of str
            split[#split+1] = string.sub(str, start)
        end
    end
    return split
end

-- **************************************************

local function PaginateList(list, page, count)
    -- Check if page is out of bounds
    if #list == 0 or count > #list then
        -- Page size is larger than data set. Send single page.
        return {items = list, total_pages = 1, page = 1}
    end
    -- Use ciel because if we have a partial page, round up to a whole page.
    local total_pages = math.ceil(#list/count)
    local start_idx = ((page-1) * count)+1
    if page < 1 or start_idx > #list then
        -- Page index is out of bounds, return nil
        return nil
    end
    -- check if end idx is out of bounds
    local end_idx = math.min(start_idx + count - 1, #list)
    return {
        items = {table.unpack(list, start_idx, end_idx)},
        total_pages = total_pages,
        page = page
    }
end

-- **************************************************

local function SetPlayerTeleSearch(player, page, search)
    -- make sure page is never less than 1
    if page < 1 then
        page = 1
    end
    local player_guid = player:GetGUID()
    -- Prepare SQL query (!NOT COMPLETELY SAFE!)
    local prepared = PrepareSQL(TELE_SET_QUERY, {player:GetGUIDLow(), page, search})
    player:SendBroadcastMessage("Updating tele search...")
    local query = CharDBQueryAsync(prepared, function(Q)
        -- get ref to player
        local player = GetPlayerByGUID(player_guid)
        player:SendBroadcastMessage("Updated tele search.")
    end)
end

local function GetPlayerTeleSearch(player, delegate)
    -- Prepare SQL query (!NOT COMPLETELY SAFE!)
    local prepared = PrepareSQL(TELE_GET_QUERY, {player:GetGUIDLow()})
    player:SendBroadcastMessage("Getting tele search...")
    local query = CharDBQueryAsync(prepared, delegate)
end

local function SetPlayerXPRate(player_guid, new_xp_mult)
    --print("Setting XP...")
    -- Prepare SQL query (!NOT COMPLETELY SAFE!)
    local player = GetPlayerByGUID(player_guid)
    local prepared = PrepareSQL(XP_SET_QUERY, {player:GetGUIDLow(), new_xp_mult})
    player:SendBroadcastMessage("Updating xp rate...")
    local Q = CharDBQuery(prepared)
    player:SendBroadcastMessage("Updated xp rate.")
    -- Refresh player reference due to invalidation (db is long running request)
    player = GetPlayerByGUID(player_guid)
end

local function GetPlayerXPRate(player, delegate)
    -- Prepare SQL query (!NOT COMPLETELY SAFE!)
    local prepared = PrepareSQL(XP_GET_QUERY, {player:GetGUIDLow()})
    local Q = CharDBQuery(prepared)
    local rate = nil
    if Q then
        repeat
            rate = Q:GetFloat(0)
        until not Q:NextRow()
    else
        player:SendBroadcastMessage("Could not get xp rate.")
    end
    return rate
end

-- **************************************************

local function HandleCharCreate(event, player)
    if player:IsBot() then return end
    SetPlayerTeleSearch(player, TELE_PAGE_DEF, TELE_SEARCH_DEF)
end

local function HandleLogin(event, player)
    if player:IsBot() then return end
    -- Set player XP Rate
    local rate = GetPlayerXPRate(player)
    local rate_str = string.format("%.2f", rate)
    if rate then
        player:SendBroadcastMessage("Your XP rate is "..rate_str)
        player:SendNotification("XP: "..rate_str.."x")
    end
end

local function HandleXP(event, player, amount, victim, source)
    if player:IsBot() then return amount end
    local rate = GetPlayerXPRate(player)
    if rate then
        return amount * rate
    else
        return amount
    end
end

-- **************************************************

local function BuildSackerMenu(player, item)
    --print("Building Sacker Menu")
    -- sender is the menu selection was made on
    -- intid is the item selected
    player:GossipClearMenu() -- Clear any previous menus
    -- Add gossip options
    player:GossipMenuAddItem(0, "XP Menu", 1, 2)
    player:GossipMenuAddItem(0, "Teleport Menu", 1, 3)
    player:GossipMenuAddItem(0, "Money Menu", 1, 4)
    player:GossipMenuAddItem(3, "Debug", 1, 5)
    -- 153 npc text: Heya champ/girl, whats shakin?
    player:GossipSendMenu(153, item)
end

local function HandleSackerSelection(event, player, object, sender, intid, code)
    BUILD_MAP[intid](player, object)
end


local function BuildXPMenu(player, item)
    --print("Building XP Menu")
    player:GossipClearMenu()
    local player_guid = player:GetGUID()
    local item_guid = item:GetGUID()
    -- get player xp rate
    local rate = GetPlayerXPRate(player)
    local rate_str = string.format("%.2f", rate)
    if rate ~= nil then
        player:SendBroadcastMessage("Your XP rate is "..rate_str)
        player:SendNotification("XP: "..rate_str)
        player:GossipMenuAddItem(3, "XP Modifier: "..rate_str.."x", 2, 12, true)
    else
        player:SendNotification("Could not get xp rate.")
    end
    player:GossipMenuAddItem(3, "0.25x XP",    2, 1)
    player:GossipMenuAddItem(3, "0.50x XP",    2, 2)
    player:GossipMenuAddItem(3, "0.75x XP",    2, 3)
    player:GossipMenuAddItem(3, "1x XP",       2, 4)
    player:GossipMenuAddItem(3, "1.5x XP",     2, 5)
    player:GossipMenuAddItem(3, "2x XP",       2, 6)
    player:GossipMenuAddItem(3, "3x XP",       2, 7)
    player:GossipMenuAddItem(3, "4x XP",       2, 8)
    player:GossipMenuAddItem(3, "5x XP",       2, 9)
    player:GossipMenuAddItem(3, "10x XP",      2,10)
    player:GossipMenuAddItem(3, "100x XP",     2,11)
    player:GossipMenuAddItem(0, "Back",         1,1) -- Takes you back to Sacker Menu
    player:GossipSendMenu(2606, item)
end

local function HandleXPSelection(event, player, object, sender, intid, code)
    local player_guid = player:GetGUID()
    local player_guid_low = player:GetGUIDLow()
    rate = XP_MAP[intid]
    if intid == 12 then
        -- validate input
        -- check if code is number
        local parsed_float = tonumber(code)
        if parsed_float ~= nil then
           parsed_float = math.abs(parsed_float)
        end
        if parsed_float ~= nil then
            -- player entered valid number
            rate = parsed_float
        else
            player:SendNotification("Invalid XP Rate: "..code)
            BuildXPMenu(player, object)
            return
        end
    end
    SetPlayerXPRate(player_guid, rate)
    BuildXPMenu(player, object)
end

local function SearchTeleport(player_guid, item_guid, page, search)
    --print("Searching teleports...")
    -- Get reference to player
    local player = GetPlayerByGUID(player_guid)
    local player_guid_low = player:GetGUIDLow()
    -- Prepare SQL queries (!NOT COMPLETELY SAFE!)
    local search_like = "%%"..search.."%%"
    local prepared_paginate = PrepareSQL(TELE_MAP_QUERY, {search_like, TELE_PAGE_SIZE, (page-1)*TELE_PAGE_SIZE})
    -- create request_id
    local req_id = NextQueryID()
    --print("Getting search results...")
    -- create request
    local request = CreateSQLRequest(
        player:GetGUIDLow(),
        req_id,
        page,
        search,
        prepared_paginate,
        function(prepared_stmt)
            --print("Executing SQL...")
            WorldDBQueryAsync(prepared_stmt, function(Q)
                -- get request state
                local request = REQUEST_MAP[player_guid_low]
                local player = GetPlayerByGUID(player_guid)
                -- Get reference to item
                local item = player:GetItemByGUID(item_guid)
                -- Build menu
                player:GossipClearMenu()
                player:GossipMenuAddItem(4, "Clear Search", 3, ITEM_ID+5)
                player:GossipMenuAddItem(4, "Search: "..(request.search), 3, ITEM_ID, true)
                player:GossipMenuAddItem(4, "Page: "..(request.page),     3, ITEM_ID+1, true)
                if Q ~= nil then
                    --print("Got Query")

                    -- verify state before creating menu
                    if request == nil then
                        print("Request cancelled.")
                        BuildSackerMenu(player, item)
                        return
                    end
                    if not player:IsInWorld() or request.request_id == nil or request.request_id ~= req_id then
                        print("Cancelling request "..request.request_id.." for player "..player:GetName())
                        -- cancel request
                        request = nil
                        REQUEST_MAP[player_guid_low] = nil
                        BuildSackerMenu(player, item)
                        return
                    end

                    repeat
                        request.results[#(request.results)+1] = {id = Q:GetUInt32(0), name = Q:GetString(1), count = Q:GetUInt32(2)}
                    until not Q:NextRow()
                    --print("Got search results!")
                    local total_pages = 1
                    if #(request.results) > 0 then
                        total_pages = math.ceil((request.results)[1].count/TELE_PAGE_SIZE)
                    end
                    player:GossipMenuAddItem(4, "Total Pages: "..total_pages, 3, ITEM_ID+1, true)

                    for i, result in ipairs(request.results) do
                        player:GossipMenuAddItem(2, result.name, 3, i)
                    end
                    -- Add page forward and backward
                    if page > 1 then
                        -- can go backward
                        player:GossipMenuAddItem(3, "Page "..(page-1), 3, ITEM_ID+2)
                    end
                    if page < total_pages then
                        -- can go forward
                        player:GossipMenuAddItem(3, "Page "..(page+1), 3, ITEM_ID+3)
                    end
                else
                    --print("No results or query error")
                    player:GossipMenuAddItem(2, "No search results. Try a different search.", 3, ITEM_ID+4)
                end
                --print("Sending Teleport Menu...")
                player:GossipMenuAddItem(0, "Back", 1, 1) -- Takes you back to Sacker Menu
                player:GossipSendMenu(5421, item)
            end)
        end
    )
end

local function BuildTeleportMenu(player, item)
    --print("Getting Player Search...")
    local player_guid = player:GetGUID()
    local item_guid = item:GetGUID()
    -- sender is the menu/layer that the selection was made on
    -- intid is the item selected
    -- Make SQL query to game_tele with pagination
    -- Get current search
    GetPlayerTeleSearch(player, function(Q)
        -- get reference to player by GUID
        local player = GetPlayerByGUID(player_guid)
        -- get reference to item
        local item = player:GetItemByGUID(item_guid)
        if Q ~= nil then
            local page, search = nil, nil
            repeat
                page, search = Q:GetUInt32(0), Q:GetString(1)
            until not Q:NextRow()
            if page == nil or search == nil then
                -- Could not get search
                player:SendNotification("Could not get player search. Using defaults.")
                page, search = 1, ""
            else
                --print("Got player search")
            end
            SearchTeleport(player_guid, item_guid, page, search)
        else
            player:SendNotification("Could not search teleport locations.")
            BuildSackerMenu(player, item)
        end
    end)
end

local function HandleTeleportSelection(event, player, object, sender, intid, code)
    local request = REQUEST_MAP[player:GetGUIDLow()]
    if intid >= ITEM_ID then
        if request == nil or request.request_id == nil then
            player:SendNotification("Search request was cancelled.")
            BuildTeleportMenu(player, object)
        end
        -- user clicked on page button or search
        if intid == ITEM_ID then
            -- user clicked on search
            SetPlayerTeleSearch(player, 1, code)
        elseif intid == ITEM_ID+1 then
            -- user clicked on page index
            -- check if code is number
            local parsed_int = tonumber(code)
            if parsed_int ~= nil then
                parsed_int = math.abs(math.floor(parsed_int))
            end
            if parsed_int ~= nil then
                -- ensure page is at least 1
                if parsed_int < 1 then
                    parsed_int = 1
                end
                -- player entered valid number
                SetPlayerTeleSearch(player, parsed_int, request.search)
            else
                player:SendNotification("Invalid Page Number: "..code)
            end
        elseif intid == ITEM_ID+2 then
            -- user clicked on page backward
            SetPlayerTeleSearch(player, request.page-1, request.search)
        elseif intid == ITEM_ID+3 then
            -- user clicked on page forward
            SetPlayerTeleSearch(player, request.page+1, request.search)
        elseif intid == ITEM_ID+4 then
            -- user clicked on no result message.
        elseif intid == ITEM_ID+5 then
            -- user wants to clear their search
            print("Clearing player search")
            SetPlayerTeleSearch(player, 1, "")
        end
        BuildTeleportMenu(player, object)
    elseif player:IsInCombat() then
        player:SendNotification("You cannot teleport right now.")
        player:GossipComplete()
    else
        -- get teleport name
        player:TeleportTo(request.results[intid].name)
        player:GossipComplete()
    end
end

local function BuildMoneyMenu(player, item)
    --print("Building Money Menu")
    player:GossipClearMenu()
    -- sender is the menu/layer that the selection was made on
    -- intid is the item selected
    player:GossipMenuAddItem(1, "Balance (Copper): "..player:GetCoinage(), 4, 0)
    player:GossipMenuAddItem(1, "Copper",   4, 1, true)
    player:GossipMenuAddItem(1, "Silver",   4, 100, true)
    player:GossipMenuAddItem(6, "Gold",     4, 10000, true)
    player:GossipMenuAddItem(0, "Back",     1, 1) -- Takes you back to Sacker Menu
    player:GossipSendMenu(737, item)
    player:SendNotification("Balance: "..player:GetCoinage())
    player:SendNotification("When clicking on a currency, enter how much you want. Use whole numbers only. Negative numbers will subtract the amount.")
end

local function HandleMoneySelection(event, player, object, sender, intid, code)
    local balance = player:GetCoinage()
    if intid ~= 0 then
        local parsed_int = tonumber(code)
        if parsed_int ~= nil then
            parsed_int = math.floor(parsed_int) * intid
        end
        if parsed_int ~= nil then
            -- tell player before balance
            player:SendBroadcastMessage("Balance Before: "..balance)
            player:SendBroadcastMessage("Transaction: "..parsed_int)
            local new_balance = balance + parsed_int
            -- check player balance
            if new_balance < 0 then
                -- The end balance would put the player in negative. Just set it to 0 instead.
                player:ModifyMoney(-balance)
                new_balance = 0
            else
                player:ModifyMoney(parsed_int)
            end
            player:SendBroadcastMessage("Balance After: "..new_balance)
        else
            player:SendNotification("Invalid number: "..code)
        end
    end
    BuildMoneyMenu(player, object)
end


local function BuildDebugMenu(player, item)
    --print("Building Debug Menu")
    player:GossipClearMenu()
    -- sender is the menu/layer that the selection was made on
    -- intid is the item selected
    player:GossipMenuAddItem(3, "Reset Own Settings", 5, 1)
    if player:IsGM() then
        player:GossipMenuAddItem(3, "Clear Request Map",   5, 2)
    end
    player:GossipMenuAddItem(0, "Back",     1, 1) -- Takes you back to Sacker Menu
    player:GossipSendMenu(7397, item)
end

local function HandleDebugSelection(event, player, object, sender, intid, code)
    if intid == 1 then
        -- reset player's settings to defaults
        HandleCharCreate(1, player)
        SetPlayerXPRate(player:GetGUID(), 1)
        player:SendNotification("Your search & XP settings have been reset.")
    elseif intid == 2 then
        -- Clear request map
        print("Clearing request map...")
        REQUEST_MAP = {}
        player:SendNotification("Request Map cleared.")
    end
    BuildDebugMenu(player, object)
end

local function ShowSackerMenu(event, player, item, target)
    BUILD_MAP[1](player, item, target)
end

local function SackerMenuSelect(event, player, object, sender, intid, code)
    SELECT_MAP[sender](event, player, object, sender, intid, code)
end


print("Loading Sacker Stone Menu...")
-- Create DB table to store player searches, favorites, and XP modifier
local prepared_create = PrepareSQL(SACKER_SEARCH_CREATE, {})
CharDBQueryAsync(prepared_create, function(Q)
    -- Set up Build Map
    BUILD_MAP[1] = BuildSackerMenu
    BUILD_MAP[2] = BuildXPMenu
    BUILD_MAP[3] = BuildTeleportMenu
    BUILD_MAP[4] = BuildMoneyMenu
    BUILD_MAP[5] = BuildDebugMenu

    -- Set up Select Map
    SELECT_MAP[1] = HandleSackerSelection
    SELECT_MAP[2] = HandleXPSelection
    SELECT_MAP[3] = HandleTeleportSelection
    SELECT_MAP[4] = HandleMoneySelection
    SELECT_MAP[5] = HandleDebugSelection

    -- Register events for the stone
    RegisterItemEvent(ITEM_ID, 2, ShowSackerMenu)
    RegisterItemGossipEvent(ITEM_ID, 2, SackerMenuSelect)

    -- Register character create event to set default search
    RegisterPlayerEvent(1, HandleCharCreate)
    -- Register login event to set XP rate on login
    RegisterPlayerEvent(3, HandleLogin)
    -- Regsiter XP Gain Handler
    RegisterPlayerEvent(12, HandleXP)
    print("Sacker Stone Menu loaded.")
    --print(PrepareSQL(TELE_SET_QUERY, {1004, 1, ""}))
end)

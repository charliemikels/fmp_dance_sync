vanilla_model.ALL:setVisible(false)

local max_distance_to_be_near = 32

local model_name = "Dance Test"

-- a set of overrides for animations found that match.
local dance_metadata = {    ---@type {[string]: {name:string, beats_per_loop:integer}}
    ["animation.model.dance.head_bop"]  = { name = "Head Bop",  beats_per_loop = 2 },
    ["animation.model.dance.smug"]      = { name = "Smug",      beats_per_loop = 2 },
    ["animation.model.dance.pikudance"] = { name = "Pikudance", beats_per_loop = 16}, -- kinda intended to be 32 I think.
}

keybinds:newKeybind(
    "Scroll dance list faster",
    keybinds:getVanillaKey("key.sprint")
)

local actions = {}  ---@type {[string]: Action}

local dance_action_wheel_page = action_wheel:newPage()
local previous_action_wheel_page = nil  ---@type Page?

actions.enter_dance_menu = action_wheel:newAction()
    :title("Dances")
    :item("minecraft:echo_shard")
    :onLeftClick(function()
        previous_action_wheel_page = action_wheel:getCurrentPage()
        action_wheel:setPage(dance_action_wheel_page)
    end)

actions.exit_dace_wheel_page = action_wheel:newAction()
    :title("Back")
    :item("minecraft:arrow")
    :onLeftClick(function()
        action_wheel:setPage(previous_action_wheel_page)
        previous_action_wheel_page = nil
    end)
dance_action_wheel_page:setAction(1, actions.exit_dace_wheel_page)

local host_selected_fmp_avatar_uuid = nil     ---@type UUID?
local host_selected_fmp_song_uuid = nil       ---@type UUID?
local host_selected_animation_multiplier = 1 ---@type number

local dances                      = {}  ---@type {[string]: {name: string, animation:Animation, beats_per_loop:integer}}
local sorted_dance_keys           = {}  ---@type string[]

local playing_dance_animation_key = nil ---@type string?
local targeted_animation_multiplier = 1 ---@type number
local targeted_avatar_uuid        = nil ---@type UUID?
local targeted_song_uuid          = nil ---@type UUID?

local timeframe_of_last_metronome_data = nil ---@type number?

---@return boolean
local function unsafe_targeted_song_is_valid()
    return world.avatarVars()[targeted_avatar_uuid]["TL_FMP_exported_song_info_api"].get_all_playing_song_uuids_and_positions()[targeted_song_uuid] ~= nil
end

---@return boolean
local function targeted_song_is_valid()
    local success, result = pcall(unsafe_targeted_song_is_valid)
    return (success and result)
end

---@return boolean
local function unsafe_targeted_avatar_is_valid()
    return targeted_avatar_uuid and type(world.avatarVars()[targeted_avatar_uuid]["TL_FMP_exported_song_info_api"].get_all_playing_song_uuids_and_positions) == "function"
end

---@return boolean
local function targeted_avatar_is_valid()
    local success, result = pcall(unsafe_targeted_avatar_is_valid)
    return (success and result)
end

local sync_event_loop_function_name = "TL_FMP_Watcher__"..client.intUUIDToString(client.generateUUID())
local sync_event = events.TICK
local function sync_event_loop_function()
    if not playing_dance_animation_key
        -- or (dances[playing_dance_animation_key] and dances[playing_dance_animation_key].animation:getPlayState() ~= "PLAYING")
    then
        if host:isHost() then print("Killing dance loop because dance is invalid or has stopped.") end
        sync_event:remove(sync_event_loop_function)
        return

    elseif not (targeted_avatar_uuid and targeted_avatar_is_valid()) then
        -- targeted_avatar_uuid is invalid. kill loop and set to nil for next time.
        if host:isHost() then print("Killing loop because target avatar is invalid.") end
        targeted_avatar_uuid = nil
        sync_event:remove(sync_event_loop_function)
        return

    else
        local music_api = world.avatarVars()[targeted_avatar_uuid]["TL_FMP_exported_song_info_api"] ---@type SongPlayerExportedInfoApi

        if targeted_song_uuid and not targeted_song_is_valid() then
            -- last time, we thought the song was valid. But it is not. unset it.
            if host:isHost() then print("song is now invalid. waiting for targeted avatar to play something new.") end
            targeted_song_uuid = nil
        end

        if not targeted_song_uuid then -- Look for new song in avatar
            local all_songs_from_targeted_avatar = music_api.get_all_playing_song_uuids_and_positions()

            local target_position = player:getPos()
            local distance_of_nearest_squared = math.huge
            local current_nearest_song_uuid = nil

            for test_song_uuid, test_song_position in pairs(all_songs_from_targeted_avatar) do
                local distance_squared_to_test_song = (test_song_position - target_position):lengthSquared()
                if distance_squared_to_test_song < distance_of_nearest_squared then
                    current_nearest_song_uuid = test_song_uuid
                    distance_of_nearest_squared = distance_squared_to_test_song
                end
            end

            if current_nearest_song_uuid then
                if host:isHost() then print("new song found. syncing to that.") end
            end

            targeted_song_uuid = current_nearest_song_uuid
        end

        if targeted_song_uuid then
            local current_metronome_data = music_api.get_metronome_info(targeted_song_uuid)
            local current_animation = dances[playing_dance_animation_key].animation
            local num_beats_in_current_animation = dances[playing_dance_animation_key].beats_per_loop

            current_animation:setSpeed(
                (current_animation:getLength() * 1000 )     -- scale to milliseconds
                / num_beats_in_current_animation            -- get length of beat in animation
                / current_metronome_data.duration_of_beat   -- get multiplier to bring animation time into song time
                * targeted_animation_multiplier             -- manual adjustment from UI
            )

            -- In a perfect world, we would only need to do set time whenever the metronome actually changes.
            -- But... precision errors are sometimes a thing. So manually set the time every tick anyways.
            current_animation:setTime(
                current_metronome_data.get_current_beat()
                    * targeted_animation_multiplier     -- manual adjustment from UI
                    % num_beats_in_current_animation    -- clamp to animation's beat range
                    / num_beats_in_current_animation    -- convert to a "progress through animation"
                    * current_animation:getLength()     -- scale back up to a set time
            )

        end
    end
end

local function start_sync_event_loop()
    if host:isHost() then print("Starting dance sync loop") end
    sync_event:register(sync_event_loop_function, sync_event_loop_function_name)
end

local dance_selector_state = {
    hover_index = 1,    ---@type integer
    selected_id = nil   ---@type integer?
}
local num_songs_to_display_in_selector = 16
---@param dance_selector_action Action
local function create_title_text_for_dance_selector(dance_selector_action)
    local title_text = "Select dance\n"

    if not next(sorted_dance_keys) then
        title_text = title_text .. "No dances found"
    else

        -- get index range
        local start_index = dance_selector_state.hover_index - math.floor(num_songs_to_display_in_selector / 2)
        local end_index = start_index + num_songs_to_display_in_selector

        -- Don't over-scroll if near the start or end of the list
        if start_index < 1 then
            start_index = 1
            end_index = math.min(#sorted_dance_keys, num_songs_to_display_in_selector +1)
        elseif end_index > #sorted_dance_keys then
            end_index = #sorted_dance_keys
            start_index = math.max(end_index - num_songs_to_display_in_selector ,1)
        end

        for index = start_index, end_index do
            local this_row_dance_id = sorted_dance_keys[index]
            local this_row_dance = dances[this_row_dance_id]

            local this_row_string = "\n"
                .. (index == dance_selector_state.hover_index and "→" or "  ")
                .. (playing_dance_animation_key and this_row_dance_id == playing_dance_animation_key and "♬" or "  ")
                .. this_row_dance.name

            title_text = title_text .. this_row_string
        end

        if playing_dance_animation_key then
            title_text = title_text .. "\n\nCurrent Dance: " .. playing_dance_animation_key
        end
        -- title_text = title_text .. "\n" .. "dances found";
    end

    dance_selector_action:title(title_text)
end

---Main throughway to sync updates to listeners. if animation_key is nil, dance will stopped.
---@param animation_key UUID?
---@param fmp_avatar_uuid UUID?
---@param playing_song_uuid UUID?
---@param multiplier number -- How much faster the animation should play than usual.
function pings.sync_dance(animation_key, fmp_avatar_uuid, playing_song_uuid, multiplier)
    targeted_avatar_uuid = fmp_avatar_uuid
    targeted_song_uuid = playing_song_uuid

    targeted_animation_multiplier = (multiplier and multiplier or 1)

    if (not animation_key) or (not dances[animation_key]) then -- animation is unset or invalid. Clean up state
        -- stop_metronome_events()
        if playing_dance_animation_key then
            dances[playing_dance_animation_key].animation:setSpeed(nil)
            dances[playing_dance_animation_key].animation:stop()
        end
        playing_dance_animation_key = nil

    else
        if playing_dance_animation_key then -- this ping is doing an update. no need to do a full reinitialize
            dances[playing_dance_animation_key].animation:setSpeed(nil) -- reset just in case that if we later play this animation without syncing to an FMP
            dances[playing_dance_animation_key].animation:stop()
        end

        playing_dance_animation_key = animation_key
        dances[playing_dance_animation_key].animation:play()
        dances[playing_dance_animation_key].animation:setSpeed(targeted_animation_multiplier)
    end

    if targeted_avatar_uuid and sync_event:getRegisteredCount(sync_event_loop_function_name) < 1 then
        start_sync_event_loop()
    end

    if host:isHost() then create_title_text_for_dance_selector(actions.select_dance_action) end
end

actions.select_dance_action = action_wheel:newAction()
    :item("minecraft:purple_dye")
    :onLeftClick(function(this)
        if playing_dance_animation_key and playing_dance_animation_key == sorted_dance_keys[dance_selector_state.hover_index] then
            pings.sync_dance(nil, nil, nil, 1)  -- stop dance that's already playing
        else
            pings.sync_dance(sorted_dance_keys[dance_selector_state.hover_index], host_selected_fmp_avatar_uuid, host_selected_fmp_song_uuid, host_selected_animation_multiplier)
        end

        create_title_text_for_dance_selector(this)
    end)
    :onScroll(function(scroll_direction, this)
        if not next(dances) then return end

        local natural_scroll = false
        local scroll_amount = keybinds:getKeybinds()["Scroll dance list faster"]:isPressed() and 20 or 1
        dance_selector_state.hover_index = dance_selector_state.hover_index + scroll_amount * scroll_direction * (natural_scroll and 1 or -1)

        -- Scroll wrap
        if dance_selector_state.hover_index > #sorted_dance_keys then dance_selector_state.hover_index = 1 end
        if dance_selector_state.hover_index < 1 then dance_selector_state.hover_index = #sorted_dance_keys end

        create_title_text_for_dance_selector(this)
    end)
dance_action_wheel_page:setAction(4, actions.select_dance_action)

---@param avatar_uuid UUID?
---@param song_uuid UUID?
local function host_select_avatar_and_song(avatar_uuid, song_uuid)
    host_selected_fmp_avatar_uuid = avatar_uuid
    host_selected_fmp_song_uuid = song_uuid

    if playing_dance_animation_key then
        pings.sync_dance(playing_dance_animation_key, host_selected_fmp_avatar_uuid, host_selected_fmp_song_uuid, host_selected_animation_multiplier)
    end
    -- TODO: see if animation is playing, and if so, send new sync data. Otherwise just set for next song selection.
end

actions.sync_dance_with_nearest_music = action_wheel:newAction()
    :title("Sync dance with nearest player\nRight click to remove sync.")
    :item("minecraft:clock")
    :setToggled(false)
    :onLeftClick(function(this)
        -- check for nearest FMP avatar with song. If none found, print error.

        -- Unlike the passive song viewer, we don't actually need to constantly search. We can just re-scan everyone once on demand.

        local avatar_of_closest_song_so_far = nil
        local closest_song_so_far = nil
        local closest_song_position = nil
        local squared_distance_of_closest_song_so_far = math.huge

        for avatar_uuid, avatar_vars in pairs(world.avatarVars()) do
            if avatar_vars["TL_FMP_exported_song_info_api"] and type(avatar_vars["TL_FMP_exported_song_info_api"].get_all_playing_song_uuids_and_positions) == "function" then
                local detected_fmp_avatar_vars = avatar_vars["TL_FMP_exported_song_info_api"] ---@type SongPlayerExportedInfoApi
                for song_uuid, song_position in pairs(detected_fmp_avatar_vars.get_all_playing_song_uuids_and_positions()) do
                    local test_distance = (player:getPos() - song_position):lengthSquared()
                    if test_distance < squared_distance_of_closest_song_so_far then
                        avatar_of_closest_song_so_far = avatar_uuid
                        closest_song_so_far = song_uuid
                        closest_song_position = song_position
                        squared_distance_of_closest_song_so_far = test_distance
                    end
                end
            end
        end

        if avatar_of_closest_song_so_far and closest_song_so_far then
            host_select_avatar_and_song(avatar_of_closest_song_so_far, closest_song_so_far)
            this:setToggled(true)
            print("Targeted song at ".. tostring(closest_song_position))
        else
            print("no new nearby song.")
        end

    end)
    :onRightClick(function(this)
        host_select_avatar_and_song(nil, nil)
        this:setToggled(false)
        print("removing sync target.")
    end)
dance_action_wheel_page:setAction(2, actions.sync_dance_with_nearest_music)


local starting_index = 0    -- What's THIS‽ Index by Zero! In **MY** Lua code? It's more likely than you think.
local possible_multipliers = {[0] = 1, 2, 3, 4, 6, 8}
for i = 1, #possible_multipliers, 1 do possible_multipliers[ -i ] = 1/possible_multipliers[i] end  -- fill table with reciprocal values.


local function adjust_speed_title_string_getter()
    return (
        "Adjust speed\nLeft Click to speed up\nRight Click to slow down\n\n"
        .. "Current speed multiplier: "
        .. (host_selected_animation_multiplier >= 1
            and tostring(host_selected_animation_multiplier)
            or ("1/"..tostring(1/host_selected_animation_multiplier))
        )
    )
end

---@param action Action
---@param direction 1|-1
local function adjust_speed_action_click_function(action, direction)
    local new_index = starting_index + direction
    if possible_multipliers[new_index] then
        host_selected_animation_multiplier = possible_multipliers[new_index]
        starting_index = new_index
        if playing_dance_animation_key then -- we're playing a song right now, Update speed now.
            pings.sync_dance(playing_dance_animation_key, host_selected_fmp_avatar_uuid, host_selected_fmp_song_uuid, host_selected_animation_multiplier )
        end
    else
        print("Reached ".. (direction > 0 and "fastest" or "slowest") .." speed.")
    end
    action:title(adjust_speed_title_string_getter())
end

actions.adjust_speed_action = action_wheel:newAction()
    :title(adjust_speed_title_string_getter())
    :item("minecraft:feather")
    :onLeftClick(function(this)  adjust_speed_action_click_function(this, 1) end)
    :onRightClick(function(this) adjust_speed_action_click_function(this, -1) end)
dance_action_wheel_page:setAction(3, actions.adjust_speed_action)





events.ENTITY_INIT:register(function()
    -- print(animations:getAnimations())
    for i, animation in pairs(animations:getAnimations()) do
        local name = animation:getName()
        if string.find(name, ".dance.") then
            local this_dance_metadata = dance_metadata[name] or {}

            dances[name] = {
                animation = animation,
                name = (this_dance_metadata.name or name),
                beats_per_loop = (this_dance_metadata.beats_per_loop or 2)
            }
            table.insert(sorted_dance_keys, name)
        end
    end

    if next(sorted_dance_keys) then
        table.sort(sorted_dance_keys)
    end

    create_title_text_for_dance_selector(actions.select_dance_action)
end)


return actions.enter_dance_menu

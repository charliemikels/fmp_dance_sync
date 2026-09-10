vanilla_model.ALL:setVisible(false)

local max_distance_to_be_near = 32

local model_name = "Dance Test"

-- a set of overrides for animations found that match.
local dance_metadata = {
    ["animation.model.dance.head_bop"] = { name = "Head Bop", item = "minecraft:player_head", beats_per_loop = 2 },
    ["animation.model.dance.smug"] = { name = "Smug", item = "minecraft:purple_dye", beats_per_loop = 2},
}

keybinds:newKeybind(
    "Scroll dance list faster",
    keybinds:getVanillaKey("key.sprint")
)

local actions = {}


local dance_action_wheel_page = action_wheel:newPage()
local previous_action_wheel_page = nil

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


local nearest_fmp_avatar_uuid = nil     ---@type UUID?
local nearest_fmp_song_uuid = nil       ---@type UUID?


local function pingless_remove_sync_to_fmp()
    nearest_fmp_avatar_uuid = nil
    nearest_fmp_song_uuid = nil
    actions.sync_dance_with_nearest_music:setToggled(false)

    -- TODO: add stop event loop logic
end
function pings.remove_sync_to_fmp() pingless_remove_sync_to_fmp() end


local function pingless_sync_to_fmp(avatar_uuid, song_uuid)
    if not (avatar_uuid and song_uuid) then
        pingless_remove_sync_to_fmp()
    else
        nearest_fmp_avatar_uuid = avatar_uuid
        nearest_fmp_song_uuid = song_uuid
        actions.sync_dance_with_nearest_music:setToggled(true)

        -- TODO: check if these are valid avatars and songs. they may be valid for host, but not for us.

        -- TODO: add event loop starting logic.
    end
end
function pings.sync_to_fmp(avatar_uuid, song_uuid) pingless_sync_to_fmp(avatar_uuid, song_uuid) end

local dances = {}

local sorted_dance_keys = {}

local dance_state = nil --{
--     animation = nil,
--     song_avatar_id = nil,
--     playing_song_id = nil,
-- }

local dance_selector_state = {
    hover_index = 1,  ---@type integer
    selected_id = nil   ---@type integer?
}


local num_songs_to_display_in_selector = 16
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
                .. (dance_state and this_row_dance_id == dance_state.animation_key and "♬" or "  ")
                .. this_row_dance.name

            title_text = title_text .. this_row_string
        end

        if dance_state then
            title_text = title_text .. "\n\nCurrent Dance: " .. dance_state.animation_key
        end
        -- title_text = title_text .. "\n" .. "dances found";
    end

    dance_selector_action:title(title_text)
end


actions.select_dance_action = action_wheel:newAction()
    :item("minecraft:purple_dye")
    :onLeftClick(function(this)
        print("clicked")
        print(dances[sorted_dance_keys[dance_selector_state.hover_index]])

        if dance_state and dance_state.animation_key == sorted_dance_keys[dance_selector_state.hover_index] then
            pings.set_dance(nil, nil, nil)  -- stop dance that's already playing
        else
            -- TODO: Get sync info from the sync action
            pings.set_dance(sorted_dance_keys[dance_selector_state.hover_index], nil, nil)
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

actions.sync_dance_with_nearest_music = action_wheel:newAction()
    :title("Sync dance with nearest player")
    :item("minecraft:clock")
    :setToggled(false)
    :onLeftClick(function(this)
        -- check for nearest FMP avatar with song. If none found, print error.

        -- Unlike the passive song viewer, we don't actually need to constantly search. We can just re-scan everyone once on demand.

        local avatar_of_closest_song_so_far = nil
        local closest_song_so_far = nil
        local closest_song_position = nil
        local squared_distance_of_closest_song_so_far = math.huge
            --     (nearest_fmp_avatar_uuid and nearest_fmp_song_uuid)
            -- and (   world.avatarVars()[nearest_fmp_avatar_uuid]
            --     and world.avatarVars()[nearest_fmp_avatar_uuid]["TL_FMP_exported_song_info_api"]
            --     and (
            --         (   world.avatarVars()[nearest_fmp_avatar_uuid]["TL_FMP_exported_song_info_api"].get_song_position(nearest_fmp_song_uuid)
            --             - player:getPos()
            --         ):lengthSquared()
            --     )
            -- )
            -- or math.huge
        -- print(squared_distance_of_closest_song_so_far)

        for avatar_uuid, avatar_vars in pairs(world.avatarVars()) do
            if avatar_vars["TL_FMP_exported_song_info_api"] and type(avatar_vars["TL_FMP_exported_song_info_api"].get_all_playing_song_uuids_and_positions) == "function" then
                for song_uuid, song_position in pairs(avatar_vars["TL_FMP_exported_song_info_api"].get_all_playing_song_uuids_and_positions()) do
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
            pings.sync_to_fmp(avatar_of_closest_song_so_far, closest_song_so_far)
            print("Targeted song at ".. tostring(closest_song_position) .. "\n (".. math.floor(math.sqrt(squared_distance_of_closest_song_so_far)) .. " blocks away)\n",avatar_of_closest_song_so_far, closest_song_so_far)
        else
            print("no nearby song. (right click to remove selection)")
        end



    end)
    :onRightClick(function(this)
        -- check for nearest FMP avatar with song. If none found, print error.
        -- Right click to unset sync.
        pings.remove_sync_to_fmp()
        print("removing sync target.")
    end)
dance_action_wheel_page:setAction(2, actions.sync_dance_with_nearest_music)

actions.adjust_speed_action = action_wheel:newAction()
    :title("Adjust speed\nLeft Click to double\nRight Click to half")
    :item("minecraft:feather")
dance_action_wheel_page:setAction(3, actions.adjust_speed_action)







local function start_metronome_events() end

local function stop_metronome_events() end

local known_avatars_with_tl_fmp = {}    ---@type table<UUID, {update_loop_fn: function?, music_api: SongPlayerExportedInfoApi}>
local last_checked_uuid = nil


local function has_api_changed(our_reference, external_api)
    return our_reference.music_api.time_player_initialized() ~= external_api.time_player_initialized()
end

local function register_new_song(avatar_uuid, song_uuid)
    local _ = known_avatars_with_tl_fmp[avatar_uuid].music_api
    print("\nFound playing song:\n",avatar_uuid, song_uuid)
end

---@param avatar_uuid UUID
---@param exported_info_api SongPlayerExportedInfoApi
local function register_new_known_music_avatar(avatar_uuid, exported_info_api)
    print("found avatar with TL_FMP", avatar_uuid)

    known_avatars_with_tl_fmp[avatar_uuid] = {}
    known_avatars_with_tl_fmp[avatar_uuid].music_api = exported_info_api

    local song_uuids_and_pos = exported_info_api.get_all_playing_song_uuids_and_positions() ---@type table<UUID, Vector3>
    for song_uuid, pos in pairs(song_uuids_and_pos) do register_new_song(avatar_uuid, song_uuid) end


    -- exported_info_api.add_song_start_callback(function(song_uuid)
    --     register_new_song(avatar_uuid, song_uuid)
    -- end)
end

local function unregister_previously_known_player_avatar(avatar_uuid)
    known_avatars_with_tl_fmp[avatar_uuid] = nil
    -- TODO: stop any animations relying on this avatar
end

-- local function check_next_avatar_for_song_player()
--     local fmp_avatar_uuid, this_avatar_vars = next(world.avatarVars(), world.avatarVars()[last_checked_uuid] and last_checked_uuid or nil)
--     last_checked_uuid = fmp_avatar_uuid
--     if fmp_avatar_uuid == nil then return end

--     if this_avatar_vars["TL_FMP_exported_song_info_api"] and not known_avatars_with_tl_fmp[fmp_avatar_uuid] then -- first time seeing this avatar with vars for TL_FMP
--         register_new_known_music_avatar(fmp_avatar_uuid, this_avatar_vars["TL_FMP_exported_song_info_api"])
--         return
--     end

--     local success, result = pcall(has_api_changed, known_avatars_with_tl_fmp[fmp_avatar_uuid], this_avatar_vars["TL_FMP_exported_song_info_api"])
--     if success and result then  -- Avatar was once valid and is not any more.
--         unregister_previously_known_player_avatar(fmp_avatar_uuid)
--     end
-- end
-- events.TICK:register(check_next_avatar_for_song_player)







-- events.TICK:register(function() -- passively find avatars with TL_FMP

--     -- check all avatars

--     local avatar_uuid, avatar_vars = next_world_var()
--     detect_and_record_new_fmp_avatars(avatar_uuid, avatar_vars)
--     detect_and_remove_now_invalid_fmp_avatars(avatar_uuid, avatar_vars)

--     -- specifically re-check the avatars we know have FMP
--     local fmp_avatar_uuid, fmp_exported_api = next_known_fmp_avatar()
--     local this_avatar_is_playing_at_least_one_song = fmp_exported_api and next(fmp_exported_api:get_all_playing_song_uuids_and_positions()) ~= nil
--     if this_avatar_is_playing_at_least_one_song then
--         if display_loop_event:getRegisteredCount(display_loop_name) < 1 then -- start display event if it's not running yet.
--             display_loop_event:register(display_loop, display_loop_name)
--         end

--         local success, current_nearest_song_position = pcall(function() return apis_for_known_fmp_avatars[nearest_song_avatar_uuid].get_song_position(nearest_song_uuid) end)
--         local current_song_distance_to_player = success and current_nearest_song_position
--             and (client:getCameraPos() - current_nearest_song_position):lengthSquared()
--             or math.huge -- set distance to beat.

--         for test_song_uuid, test_song_position in pairs(apis_for_known_fmp_avatars[fmp_avatar_uuid]:get_all_playing_song_uuids_and_positions()) do
--             local test_song_distance_to_camera = (client:getCameraPos() - test_song_position):lengthSquared()
--             if test_song_distance_to_camera < current_song_distance_to_player then
--                 current_song_distance_to_player = test_song_distance_to_camera
--                 nearest_song_avatar_uuid = fmp_avatar_uuid
--                 nearest_song_uuid = test_song_uuid
--             end
--         end
--     end
-- end)




function pings.set_dance(animation_key, song_avatar_id, playing_song_id)
    if (not animation_key) or (not dances[animation_key]) then -- animation is unset or invalid. Clean up state
        stop_metronome_events()
        if dance_state and dance_state.animation then dance_state.animation:stop() end
        dance_state = nil

    elseif dance_state then -- this ping is doing an update. no need to do a full reinitialize
        dance_state.animation:stop()

        dance_state.animation_key = animation_key
        dance_state.animation = dances[animation_key].animation

        dance_state.animation:play()

    else    -- Set and start dance.
        dance_state = {
            animation_key = animation_key,
            animation = dances[animation_key].animation,
            song_avatar_id = nil,
            playing_song_id = nil,
        }

        start_metronome_events()
        dance_state.animation:play()
    end

    if host:isHost() then create_title_text_for_dance_selector(actions.select_dance_action) end
end

events.ENTITY_INIT:register(function()
    -- print(animations:getAnimations())
    for i, animation in pairs(animations:getAnimations()) do
        local name = animation:getName()
        if string.find(name, ".dance.") then
            local this_dance_metadata = dance_metadata[name] or {}

            dances[name] = {
                animation = animation,
                name = (this_dance_metadata.name or name)
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

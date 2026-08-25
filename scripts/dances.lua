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




local dance_action_wheel_page = action_wheel:newPage()
local previous_action_wheel_page = nil

local enter_dance_menu = action_wheel:newAction()
    :title("Dances")
    :item("minecraft:echo_shard")
    :onLeftClick(function()
        previous_action_wheel_page = action_wheel:getCurrentPage()
        action_wheel:setPage(dance_action_wheel_page)
    end)

local exit_dace_wheel_page = action_wheel:newAction()
    :title("Back")
    :item("minecraft:arrow")
    :onLeftClick(function()
        action_wheel:setPage(previous_action_wheel_page)
        previous_action_wheel_page = nil
    end)
dance_action_wheel_page:setAction(1, exit_dace_wheel_page)



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
        -- title_text = title_text .. "\ndances found";
    end

    dance_selector_action:title(title_text)
end


local select_dance_action = action_wheel:newAction()
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
dance_action_wheel_page:setAction(4, select_dance_action)

local sync_dance_with_nearest_music = action_wheel:newAction()
    :title("Sync dance with nearest player")
    :item("minecraft:clock")
dance_action_wheel_page:setAction(2, sync_dance_with_nearest_music)

local adjust_speed_action = action_wheel:newAction()
    :title("Adjust speed\nLeft Click to double\nRight Click to half")
    :item("minecraft:feather")
dance_action_wheel_page:setAction(3, adjust_speed_action)







local function start_metronome_events() end

local function stop_metronome_events() end


local known_avatars_with_tl_fmp = {}    ---@type table<UUID, SongPlayerExportedInfoApi>
local last_checked_uuid = nil


local function has_api_changed(our_reference, external_api)
    return our_reference.time_player_initialized() ~= external_api.time_player_initialized()
end


---@param avatar_uuid UUID
---@param exported_info_api SongPlayerExportedInfoApi
local function register_new_known_music_avatar(avatar_uuid, exported_info_api)
    print("found avatar with player", avatar_uuid)
    -- print("found TL_FMP avatar: "..fmp_avatar_uuid)

    -- new_found_api.add_song_start_callback(function(song_uuid)
    --     host:setActionbar("Song: "..new_found_api.get_song_name(song_uuid), true)

    --     local bpm_print_update_loop_name = "TEST_FISH_FISH_TEST!!"
    --     local last_beat = -1
    --     -- new_found_api.add_song_metronome_update_callback(song_uuid, function(metronome_info)
    --     --     events.TICK:remove(bpm_print_update_loop_name)

    --     --     events.TICK:register(
    --     --         function ()
    --     --             local this_beat = math.floor(metronome_info.get_current_beat() )

    --     --             local current_beat_printable = math.floor(metronome_info.get_current_measure() +1) .. " . " .. math.floor(metronome_info.get_current_beat_in_measure()+1) .. "  |  " .. string.format("%.3f", metronome_info.get_current_beat())

    --     --             if last_beat ~= this_beat then
    --     --                 last_beat = this_beat

    --     --                 if math.floor(metronome_info.get_current_beat_in_measure()) == 0 then
    --     --                     host:setActionbar("▊▊▊▊▊▊▊▊▊▊▊▊▊ ".. current_beat_printable .." ▊▊▊▊▊▊▊▊▊▊▊▊▊")
    --     --                 else
    --     --                     host:setActionbar("▊ ".. current_beat_printable .." ▊")
    --     --                 end

    --     --             else
    --     --                 host:setActionbar(current_beat_printable)
    --     --             end

    --     --         end,
    --     --         bpm_print_update_loop_name
    --     --     )

    --     -- end)


    --     new_found_api.add_song_stop_callback(song_uuid, function()
    --         -- print("Song ended")
    --         events.TICK:remove(bpm_print_update_loop_name)
    --     end)


    -- end)

    known_avatars_with_tl_fmp[avatar_uuid] = exported_info_api
end

local function unregister_once_known_player_avatar(avatar_uuid)
    known_avatars_with_tl_fmp[avatar_uuid] = nil
    -- TODO: stop any animations relying on this avatar
end

local function check_next_avatar_for_song_player()
    local fmp_avatar_uuid, this_avatar_vars = next(world.avatarVars(), last_checked_uuid)
    last_checked_uuid = fmp_avatar_uuid
    if fmp_avatar_uuid == nil then return end

    if this_avatar_vars["TL_FMP_exported_song_info_api"] and not known_avatars_with_tl_fmp[fmp_avatar_uuid] then -- first time seeing this avatar with vars for TL_FMP
        register_new_known_music_avatar(fmp_avatar_uuid, this_avatar_vars["TL_FMP_exported_song_info_api"])
        return
    end

    local success, result = pcall(has_api_changed, known_avatars_with_tl_fmp[fmp_avatar_uuid], this_avatar_vars["TL_FMP_exported_song_info_api"])
    if success and result then  -- Avatar was once valid and is not any more.
        unregister_once_known_player_avatar(fmp_avatar_uuid)
    end
end
events.TICK:register(check_next_avatar_for_song_player)

function pings.set_dance(animation_key, song_avatar_id, playing_song_id)
    if (not animation_key) or (not dances[animation_key]) then -- animation is unset or invalid. Clean up state
        stop_metronome_events()
        if dance_state and dance_state.animation then dance_state.animation:stop() end
        dance_state = nil

    elseif dance_state then -- this ping is doing an update. no need to do a full reinitilize
        dance_state.animation:stop()

        dance_state.animation_key = animation_key
        dance_state.animation = dances[animation_key].animation

        dance_state.animation:play()

    else --
        dance_state = {
            animation_key = animation_key,
            animation = dances[animation_key].animation,
            song_avatar_id = nil,
            playing_song_id = nil,
        }

        start_metronome_events()
        dance_state.animation:play()
    end

    if host:isHost() then create_title_text_for_dance_selector(select_dance_action) end
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

    create_title_text_for_dance_selector(select_dance_action)
end)


return enter_dance_menu

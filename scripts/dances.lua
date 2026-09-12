vanilla_model.ALL:setVisible(false)

local max_distance_to_be_near = 32

local model_name = "Dance Test"

-- a set of overrides for animations found that match.
local dance_metadata = {    ---@type {[string]: {name:string, beats_per_loop:number}}
    ["animation.model.dance.head_bop"] = { name = "Head Bop", beats_per_loop = 2 },
    ["animation.model.dance.smug"] = { name = "Smug", beats_per_loop = 2},
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

local dances = {}               ---@type {[string]: {name: string, animation:Animation}}
local sorted_dance_keys = {}    ---@type string[]
local playing_dance_animation_key = nil ---@type string?
local targeted_avatar_uuid = nil    ---@type UUID?
local targeted_song_uuid = nil      ---@type UUID?


local dance_selector_state = {
    hover_index = 1,    ---@type integer
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


function pings.sync_dance(animation_key, fmp_avatar_uuid, playing_song_uuid)
    targeted_avatar_uuid = fmp_avatar_uuid
    targeted_song_uuid = playing_song_uuid

    if (not animation_key) or (not dances[animation_key]) then -- animation is unset or invalid. Clean up state
        -- stop_metronome_events()
        if playing_dance_animation_key then dances[playing_dance_animation_key].animation:stop() end
        playing_dance_animation_key = nil

    elseif playing_dance_animation_key then -- this ping is doing an update. no need to do a full reinitialize
        dances[playing_dance_animation_key].animation:stop()
        playing_dance_animation_key = animation_key
        dances[playing_dance_animation_key].animation:play()

    else    -- Set and start dance.
        playing_dance_animation_key = animation_key
        dances[playing_dance_animation_key].animation:play()
    end

    if host:isHost() then create_title_text_for_dance_selector(actions.select_dance_action) end
end

actions.select_dance_action = action_wheel:newAction()
    :item("minecraft:purple_dye")
    :onLeftClick(function(this)
        print("clicked")
        print(dances[sorted_dance_keys[dance_selector_state.hover_index]])

        if playing_dance_animation_key and playing_dance_animation_key == sorted_dance_keys[dance_selector_state.hover_index] then
            pings.sync_dance(nil, nil, nil)  -- stop dance that's already playing
        else
            -- TODO: Get sync info from the sync action
            pings.sync_dance(sorted_dance_keys[dance_selector_state.hover_index], nil, nil)
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
            host_select_avatar_and_song(avatar_of_closest_song_so_far, closest_song_so_far)
            this:setToggled(true)
            print("Targeted song at ".. tostring(closest_song_position) .. "\n (".. math.floor(math.sqrt(squared_distance_of_closest_song_so_far)) .. " blocks away)\n",avatar_of_closest_song_so_far, closest_song_so_far)
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

actions.adjust_speed_action = action_wheel:newAction()
    :title("Adjust speed\nLeft Click to double\nRight Click to half")
    :item("minecraft:feather")
    :onLeftClick(function(this) print(" -- TODO: actions.adjust_speed_action ")end)
dance_action_wheel_page:setAction(3, actions.adjust_speed_action)





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

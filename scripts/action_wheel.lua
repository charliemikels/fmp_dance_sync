local root_action_wheel_page = action_wheel:newPage()
action_wheel:setPage(root_action_wheel_page)

local dances_action = require("./dances")
root_action_wheel_page:setAction(-1, dances_action)

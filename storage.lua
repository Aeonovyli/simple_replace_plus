local function get_save_path(param)
    local world_path = minetest.get_worldpath()
    local dir_path = world_path .. "/simple_replace_data"
    minetest.mkdir(dir_path)
    return dir_path .. "/" .. param .. ".txt"
end

local srp_pos1 = {}
local srp_pos2 = {}
local srp_undo_history = {}

local old_pos1 = minetest.registered_chatcommands["pos1"].func
minetest.registered_chatcommands["pos1"].func = function(name, param)
    local status, msg = old_pos1(name, param)
    local p = minetest.get_player_by_name(name)
    if status and p then
        srp_pos1[name] = vector.round(p:get_pos())
    end
    return status, msg
end

local old_pos2 = minetest.registered_chatcommands["pos2"].func
minetest.registered_chatcommands["pos2"].func = function(name, param)
    local status, msg = old_pos2(name, param)
    local p = minetest.get_player_by_name(name)
    if status and p then
        srp_pos2[name] = vector.round(p:get_pos())
    end
    return status, msg
end

local old_undo = minetest.registered_chatcommands["undo"].func
minetest.registered_chatcommands["undo"].func = function(name, param)
    local local_history = srp_undo_history[name]
    if local_history and #local_history > 0 then
        local action = table.remove(local_history)
        local vm = minetest.get_voxel_manip()
        local minp, maxp = vm:read_from_map(action.p1, action.p2)
        local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()
        local param2 = vm:get_param2_data()
        for idx = 1, #action.indices do
            local i = action.indices[idx]
            data[i] = action.old_nodes[idx]
            if param2 and action.old_param2[idx] then param2[i] = action.old_param2[idx] end
        end
        vm:set_data(data)
        if param2 then vm:set_param2_data(param2) end
        vm:write_to_map()
        return true, "Loaded structural changes are reverted."
    end
    return old_undo(name, param)
end

local function get_bounds(name)
    local p1 = srp_pos1[name]
    local p2 = srp_pos2[name]
    if not p1 or not p2 then return nil end
    return {
        min = {x = math.min(p1.x, p2.x), y = math.min(p1.y, p2.y), z = math.min(p1.z, p2.z)},
        max = {x = math.max(p1.x, p2.x), y = math.max(p1.y, p2.y), z = math.max(p1.z, p2.z)},
        origin = p1
    }
end

minetest.register_chatcommand("save", {
    privs = {server = true},
    params = "<slot_name>",
    description = "Save structural contents inside selected nodes to persistent database",
    func = function(name, param)
        if param == "" then return false, "Usage: /save <slot_name>" end
        local bounds = get_bounds(name)
        if not bounds then return false, "You must set both pos1 and pos2 first!" end

        local schematic = {}
        local index = 1
        for x = bounds.min.x, bounds.max.x do
            for y = bounds.min.y, bounds.max.y do
                for z = bounds.min.z, bounds.max.z do
                    local pos = {x = x, y = y, z = z}
                    local node = minetest.get_node(pos)
                    local meta = minetest.get_meta(pos):to_table()
                    schematic[index] = {
                        off = {x = x - bounds.origin.x, y = y - bounds.origin.y, z = z - bounds.origin.z},
                        node = node,
                        meta = meta
                    }
                    index = index + 1
                end
            end
        end

        local file_path = get_save_path(param)
        local file = io.open(file_path, "w")
        if not file then return false, "Failed to write file at: " .. file_path end
        file:write(minetest.serialize(schematic))
        file:close()

        return true, "Successfully saved " .. (#schematic) .. " nodes to structural slot: " .. param
    end
})

minetest.register_chatcommand("load", {
    privs = {server = true},
    params = "<slot_name>",
    description = "Load persistent slot structural configurations onto current pos1 position",
    func = function(name, param)
        if param == "" then return false, "Usage: /load <slot_name>" end

        local file_path = get_save_path(param)
        local file = io.open(file_path, "r")
        if not file then return false, "Slot structural layout matching '" .. param .. "' not found." end
        local raw_data = file:read("*all")
        file:close()

        local schematic = minetest.deserialize(raw_data)
        if not schematic or type(schematic) ~= "table" or #schematic == 0 then return false, "Corrupted dataset block inside storage configurations." end

        local anchor = srp_pos1[name]
        if not anchor then return false, "You must set /pos1 to serve as the structural anchor coordinate layout position." end

        if schematic[1] and schematic[1].offset then
            return false, "This blueprint file requires format conversion. Please create a new /save first."
        end

        local min_offset = {x = math.huge, y = math.huge, z = math.huge}
        local max_offset = {x = -math.huge, y = -math.huge, z = -math.huge}
        for _, entry in ipairs(schematic) do
            min_offset.x = math.min(min_offset.x, entry.off.x)
            min_offset.y = math.min(min_offset.y, entry.off.y)
            min_offset.z = math.min(min_offset.z, entry.off.z)
            max_offset.x = math.max(max_offset.x, entry.off.x)
            max_offset.y = math.max(max_offset.y, entry.off.y)
            max_offset.z = math.max(max_offset.z, entry.off.z)
        end

        local p1 = {x = anchor.x + min_offset.x, y = anchor.y + min_offset.y, z = anchor.z + min_offset.z}
        local p2 = {x = anchor.x + max_offset.x, y = anchor.y + max_offset.y, z = anchor.z + max_offset.z}

        local sort_p1 = {x = math.min(p1.x, p2.x), y = math.min(p1.y, p2.y), z = math.min(p1.z, p2.z)}
        local sort_p2 = {x = math.max(p1.x, p2.x), y = math.max(p1.y, p2.y), z = math.max(p1.z, p2.z)}

        local vm = minetest.get_voxel_manip()
        local minp, maxp = vm:read_from_map(sort_p1, sort_p2)
        local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()
        local param2 = vm:get_param2_data()

        local indices = {}
        local old_nodes = {}
        local old_param2 = {}

        for idx, entry in ipairs(schematic) do
            local tx = anchor.x + entry.off.x
            local ty = anchor.y + entry.off.y
            local tz = anchor.z + entry.off.z
            local i = area:index(tx, ty, tz)

            indices[idx] = i
            old_nodes[idx] = data[i]
            old_param2[idx] = param2[i]

            data[i] = minetest.get_content_id(entry.node.name)
            param2[i] = entry.node.param2 or 0
        end

        vm:set_data(data)
        vm:set_param2_data(param2)
        vm:write_to_map()

        for _, entry in ipairs(schematic) do
            if entry.meta then
                local tx = anchor.x + entry.off.x
                local ty = anchor.y + entry.off.y
                local tz = anchor.z + entry.off.z
                minetest.get_meta({x=tx, y=ty, z=tz}):from_table(entry.meta)
            end
        end

        srp_undo_history[name] = srp_undo_history[name] or {}
        table.insert(srp_undo_history[name], {
            p1 = sort_p1,
            p2 = sort_p2,
            indices = indices,
            old_nodes = old_nodes,
            old_param2 = old_param2
        })

        if #srp_undo_history[name] > 64 then
            table.remove(srp_undo_history[name], 1)
        end

        return true, "Successfully loaded layout slot configuration: " .. param
    end
})

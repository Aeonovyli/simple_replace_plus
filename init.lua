local fill={}
local pos1={}
local pos2={}
local airfill={}
local selected_node={}
local delete_mode={}
local undo_stack = {}
local redo_stack = {}
local MAX_HISTORY = 64

local function sort_pos(p1,p2)
 return {
  x=math.min(p1.x,p2.x),
  y=math.min(p1.y,p2.y),
  z=math.min(p1.z,p2.z)
 },{
  x=math.max(p1.x,p2.x),
  y=math.max(p1.y,p2.y),
  z=math.max(p1.z,p2.z)
 }
end

local function replace_area(name, p1, p2, filter, newnode)
    local vm = minetest.get_voxel_manip()
    local minp, maxp = vm:read_from_map(p1, p2)
    local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
    local data = vm:get_data()
    local cid_new = minetest.get_content_id(newnode)
    local indices = {}
    local old_nodes = {}
    local new_nodes = {}
    for z = p1.z, p2.z do
        for y = p1.y, p2.y do
            for x = p1.x, p2.x do
                local i = area:index(x, y, z)
                local old = data[i]
                if filter(old) then
                    indices[#indices+1] = i
                    old_nodes[#old_nodes+1] = old
                    data[i] = cid_new
                    new_nodes[#new_nodes+1] = cid_new
                end
            end
        end
    end
    vm:set_data(data)
    vm:write_to_map()
    undo_stack[name] = undo_stack[name] or {}
    redo_stack[name] = {}
    undo_stack[name][#undo_stack[name]+1] = {
        p1 = vector.new(p1),
        p2 = vector.new(p2),
        indices = indices,
        old_nodes = old_nodes,
        new_nodes = new_nodes
    }
    if #undo_stack[name] > MAX_HISTORY then
        table.remove(undo_stack[name], 1)
    end
end

minetest.register_chatcommand("pos1",{
 privs={server=true},
 func=function(name)
  local p=minetest.get_player_by_name(name)
  if not p then return end
  pos1[name]=vector.round(p:get_pos())
  return true,"Position 1 set to "..minetest.pos_to_string(pos1[name])
 end
})

minetest.register_chatcommand("pos2",{
 privs={server=true},
 func=function(name)
  local p=minetest.get_player_by_name(name)
  if not p then return end
  pos2[name]=vector.round(p:get_pos())
  return true,"Position 2 set to "..minetest.pos_to_string(pos2[name])
 end
})

minetest.register_chatcommand("setnode",{
 privs={server=true},
 func=function(name)
  local p=minetest.get_player_by_name(name)
  if not p then return end
  local item=p:get_wielded_item()
  if item:is_empty() then return false,"Hold a node in your hand." end
  local n=item:get_name()
  if not minetest.registered_nodes[n] then return false,"That item is not a placeable node." end
  selected_node[name]=n
  return true,"Selected node: "..selected_node[name]
 end
})

minetest.register_chatcommand("fill",{
 description="Fill selected area",
 privs={server=true},
 func=function(name)
  if not pos1[name] or not pos2[name] then return false,"Set pos1 and pos2 first." end
  if not selected_node[name] then return false,"Use /setnode first." end
  local p1,p2=sort_pos(pos1[name],pos2[name])
  local function filter(cid)
   local n=minetest.get_name_from_content_id(cid)
   return n~="air" and not n:find("water")
  end
  replace_area(name, p1, p2, filter, selected_node[name])
  fill[name]=true
  return true,"Filled area with "..selected_node[name]
 end
})

minetest.register_chatcommand("airfill",{
 description="Fill selected area, including air",
 privs={server=true},
 func=function(name)
  if not pos1[name] or not pos2[name] then return false,"Set pos1 and pos2 first." end
  if not selected_node[name] then return false,"Use /setnode first." end
  local p1,p2=sort_pos(pos1[name],pos2[name])
  local function filter(cid)
   return true
  end
  replace_area(name, p1, p2, filter, selected_node[name])
  airfill[name]=true
  return true,"Filled area with "..selected_node[name]
 end
})

minetest.register_chatcommand("delete", {
    description = "Delete all blocks within pos1 and pos2",
    privs = {server = true},
    func = function(name)
        if not pos1[name] or not pos2[name] then return false, "Set pos1 and pos2 first." end
        local p1, p2 = sort_pos(pos1[name], pos2[name])
        local function filter(cid)
            local n = minetest.get_name_from_content_id(cid)
            return n ~= "air" and not n:find("water")
        end
        replace_area(name, p1, p2, filter, "air")
        delete_mode[name] = true
        return true, "Deleted nodes within the selected area"
    end
})

minetest.register_chatcommand("undo", {
    privs = {server = true},
    func = function(name)
        local stack = undo_stack[name]
        if not stack or #stack == 0 then
            return false, "Nothing to undo."
        end
        local action = table.remove(stack)
        redo_stack[name] = redo_stack[name] or {}
        redo_stack[name][#redo_stack[name]+1] = action
        local vm = minetest.get_voxel_manip()
        local minp, maxp = vm:read_from_map(action.p1, action.p2)
        local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()
        for idx = 1, #action.indices do
            local i = action.indices[idx]
            data[i] = action.old_nodes[idx]
        end
        vm:set_data(data)
        vm:write_to_map()
        return true, "Nodes changed are reverted."
    end
})
minetest.register_chatcommand("redo", {
    privs = {server = true},
    func = function(name)
        local stack = redo_stack[name]
        if not stack or #stack == 0 then
            return false, "Nothing to redo."
        end
        local action = table.remove(stack)
        undo_stack[name] = undo_stack[name] or {}
        undo_stack[name][#undo_stack[name]+1] = action
        local vm = minetest.get_voxel_manip()
        local minp, maxp = vm:read_from_map(action.p1, action.p2)
        local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()
        for idx = 1, #action.indices do
            local i = action.indices[idx]
            data[i] = action.new_nodes[idx]
        end
        vm:set_data(data)
        vm:write_to_map()
        return true, "Action redone."
    end
})

local fill={}
local pos1={}
local pos2={}
local airfill={}
local selected_node={}
local delete_mode={}
local undo_stack = {}
local redo_stack = {}
local waterfill = {}
local waterdelete = {}
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
 params="<node_name>",
 description="Select a node to replace with.",
 func=function(name,param)
  local p=minetest.get_player_by_name(name)
  if not p then return false,"Player not found." end
  if param=="" then return false,"Specify a node." end
  if not minetest.registered_nodes[param] then return false,"Not a registered node." end
  selected_node[name]=param
  return true,"Selected node: "..param
 end
})

minetest.register_chatcommand("fill",{
 privs={server=true},
 params="<from> <to>",
 description="Fill selected area",
 func=function(name,param)
  if not pos1[name] or not pos2[name] then return false,"Set pos1 and pos2 first." end
  local a,b=param:match("([^ ]+) ([^ ]+)")
  local from,to
  if a and b then
   if not minetest.registered_nodes[a] then return false,"Not a registered node: "..a end
   if not minetest.registered_nodes[b] then return false,"Not a registered node: "..b end
   from=a
   to=b
  elseif param~="" then
   if not minetest.registered_nodes[param] then return false,"Not a registered node: "..param end
   selected_node[name]=param
   from="*"
   to=param
  else
   if not selected_node[name] then return false,"Use /setnode first." end
   from="*"
   to=selected_node[name]
  end
  local p1,p2=sort_pos(pos1[name],pos2[name])
  local function filter(cid)
   if from=="*" then
    local n=minetest.get_name_from_content_id(cid)
    return n~="air" and not n:find("water")
   end
   return minetest.get_name_from_content_id(cid)==from
  end
  replace_area(name,p1,p2,filter,to)
  fill[name]=true
  return true,"Filled area with "..to
 end
})

minetest.register_chatcommand("airfill",{
 privs={server=true},
 params="<from> <to>",
 description="Fill selected area, including air",
 func=function(name,param)
  if not pos1[name] or not pos2[name] then return false,"Set pos1 and pos2 first." end
  local a,b=param:match("([^ ]+) ([^ ]+)")
  local from,to
  if a and b then
   if not minetest.registered_nodes[a] then return false,"Not a registered node: "..a end
   if not minetest.registered_nodes[b] then return false,"Not a registered node: "..b end
   from=a
   to=b
  elseif param~="" then
   if not minetest.registered_nodes[param] then return false,"Not a registered node: "..param end
   selected_node[name]=param
   from="*"
   to=param
  else
   if not selected_node[name] then return false,"Use /setnode first." end
   from="*"
   to=selected_node[name]
  end
  local p1,p2=sort_pos(pos1[name],pos2[name])
  local function filter(cid)
   return true
  end
  replace_area(name,p1,p2,filter,to)
  airfill[name]=true
  return true,"Filled area with "..to
 end
})

minetest.register_chatcommand("delete",{
 privs={server=true},
 params="<node_name>",
 description="Delete blocks within pos1 and pos2",
 func=function(name,param)
  if not pos1[name] or not pos2[name] then return false,"Set pos1 and pos2 first." end
  local p1,p2=sort_pos(pos1[name],pos2[name])
  if param~="" then
   if not minetest.registered_nodes[param] then return false,"Not a registered node." end
   local target=param
   local function filter(cid)
    return minetest.get_name_from_content_id(cid)==target
   end
   replace_area(name,p1,p2,filter,"air")
   delete_mode[name]=true
   return true,"Deleted "..target.." within the selected area"
  end
  local function filter(cid)
   local n=minetest.get_name_from_content_id(cid)
   return n~="air" and not n:find("water")
  end
  replace_area(name,p1,p2,filter,"air")
  delete_mode[name]=true
  return true,"Deleted nodes within the selected area"
 end
})

minetest.register_chatcommand("undo",{
 privs={server=true},
 func=function(name)
  local stack=undo_stack[name]
  if not stack or #stack==0 then return false,"Nothing to undo." end
  local action=table.remove(stack)
  redo_stack[name]=redo_stack[name] or {}
  redo_stack[name][#redo_stack[name]+1]=action
  local vm=minetest.get_voxel_manip()
  local minp,maxp=vm:read_from_map(action.p1,action.p2)
  local area=VoxelArea:new({MinEdge=minp,MaxEdge=maxp})
  local data=vm:get_data()
  for idx=1,#action.indices do
   local i=action.indices[idx]
   data[i]=action.old_nodes[idx]
  end
  vm:set_data(data)
  vm:write_to_map()
  return true,"Nodes changed are reverted."
 end
})

minetest.register_chatcommand("redo",{
 privs={server=true},
 func=function(name)
  local stack=redo_stack[name]
  if not stack or #stack==0 then return false,"Nothing to redo." end
  local action=table.remove(stack)
  undo_stack[name]=undo_stack[name] or {}
  undo_stack[name][#undo_stack[name]+1]=action
  local vm=minetest.get_voxel_manip()
  local minp,maxp=vm:read_from_map(action.p1,action.p2)
  local area=VoxelArea:new({MinEdge=minp,MaxEdge=maxp})
  local data=vm:get_data()
  for idx=1,#action.indices do
   local i=action.indices[idx]
   data[i]=action.new_nodes[idx]
  end
  vm:set_data(data)
  vm:write_to_map()
  return true,"Action redone."
 end
})


minetest.register_chatcommand("undo",{
 privs={server=true},
 func=function(name)
  local stack=undo_stack[name]
  if not stack or #stack==0 then return false,"Nothing to undo." end
  local action=table.remove(stack)
  redo_stack[name]=redo_stack[name] or {}
  redo_stack[name][#redo_stack[name]+1]=action
  local vm=minetest.get_voxel_manip()
  local minp,maxp=vm:read_from_map(action.p1,action.p2)
  local area=VoxelArea:new({MinEdge=minp,MaxEdge=maxp})
  local data=vm:get_data()
  for idx=1,#action.indices do
   local i=action.indices[idx]
   data[i]=action.old_nodes[idx]
  end
  vm:set_data(data)
  vm:write_to_map()
  return true,"Nodes changed are reverted."
 end
})

minetest.register_chatcommand("redo",{
 privs={server=true},
 func=function(name)
  local stack=redo_stack[name]
  if not stack or #stack==0 then return false,"Nothing to redo." end
  local action=table.remove(stack)
  undo_stack[name]=undo_stack[name] or {}
  undo_stack[name][#undo_stack[name]+1]=action
  local vm=minetest.get_voxel_manip()
  local minp,maxp=vm:read_from_map(action.p1,action.p2)
  local area=VoxelArea:new({MinEdge=minp,MaxEdge=maxp})
  local data=vm:get_data()
  for idx=1,#action.indices do
   local i=action.indices[idx]
   data[i]=action.new_nodes[idx]
  end
  vm:set_data(data)
  vm:write_to_map()
  return true,"Action redone."
 end
})

minetest.register_chatcommand("waterdelete", {
    description = "Delete all liquids within pos1 and pos2",
    privs = {server = true},
    func = function(name)
        if not pos1[name] or not pos2[name] then return false, "Set pos1 and pos2 first." end
        local p1, p2 = sort_pos(pos1[name], pos2[name])
        local function filter(cid)
            local n = minetest.get_name_from_content_id(cid)
            local def = minetest.registered_nodes[n]
            return def and def.liquidtype and def.liquidtype ~= "none"
        end
        replace_area(name, p1, p2, filter, "air")
        return true, "Deleted all liquids within the selected area"
    end
})

minetest.register_chatcommand("waterfill", {
    description = "Fill selected area, replacing only liquids",
    privs = {server = true},
    func = function(name)
        if not pos1[name] or not pos2[name] then return false, "Set pos1 and pos2 first." end
        if not selected_node[name] then return false, "Use /setnode first." end
        local p1, p2 = sort_pos(pos1[name], pos2[name])
        local function filter(cid)
            local n = minetest.get_name_from_content_id(cid)
            local def = minetest.registered_nodes[n]
            return def and def.liquidtype and def.liquidtype ~= "none"
        end
        replace_area(name, p1, p2, filter, selected_node[name])
        return true, "Replaced all liquids with " .. selected_node[name]
    end
})

minetest.register_chatcommand("copy", {
    privs = {server = true},
    func = function(name)
        if not pos1[name] or not pos2[name] then return false, "Set /pos1 and /pos2 first." end
        local p = minetest.get_player_by_name(name)
        if not p then return false, "Player not found." end
        local p1, p2 = sort_pos(pos1[name], pos2[name])
        local origin_pos = pos1[name]
        local vm = minetest.get_voxel_manip()
        local minp, maxp = vm:read_from_map(p1, p2)
        local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()
        local param1 = vm:get_light_data()
        local param2 = vm:get_param2_data()
        local nodes_list = {}
        local count = 0
        for z = p1.z, p2.z do
            for y = p1.y, p2.y do
                for x = p1.x, p2.x do
                    local i = area:index(x, y, z)
                    count = count + 1
                    nodes_list[count] = {
                        offset = vector.new(x - origin_pos.x, y - origin_pos.y, z - origin_pos.z),
                        data = data[i],
                        param1 = param1[i],
                        param2 = param2[i]
                    }
                end
            end
        end
        fill[name] = nodes_list
        return true, "Copied " .. count .. " nodes to structural clipboard."
    end
})

minetest.register_chatcommand("paste", {
    privs = {server = true},
    func = function(name)
        local nodes_list = fill[name]
        if not nodes_list or type(nodes_list) ~= "table" or #nodes_list == 0 then
            return false, "Clipboard is empty. Run /copy first."
        end
        local p = minetest.get_player_by_name(name)
        if not p then return false, "Player not found." end
        local player_pos = vector.round(p:get_pos())
        local min_offset = vector.new(math.huge, math.huge, math.huge)
        local max_offset = vector.new(-math.huge, -math.huge, -math.huge)
        for _, entry in ipairs(nodes_list) do
            min_offset.x = math.min(min_offset.x, entry.offset.x)
            min_offset.y = math.min(min_offset.y, entry.offset.y)
            min_offset.z = math.min(min_offset.z, entry.offset.z)
            max_offset.x = math.max(max_offset.x, entry.offset.x)
            max_offset.y = math.max(max_offset.y, entry.offset.y)
            max_offset.z = math.max(max_offset.z, entry.offset.z)
        end
        local p1 = vector.add(player_pos, min_offset)
        local p2 = vector.add(player_pos, max_offset)
        local vm = minetest.get_voxel_manip()
        local minp, maxp = vm:read_from_map(p1, p2)
        local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()
        local param1 = vm:get_light_data()
        local param2 = vm:get_param2_data()
        local indices = {}
        local old_nodes = {}
        local old_param1 = {}
        local old_param2 = {}
        local new_nodes = {}
        local new_param1 = {}
        local new_param2 = {}
        for idx, entry in ipairs(nodes_list) do
            local absolute_pos = vector.add(player_pos, entry.offset)
            local i = area:index(absolute_pos.x, absolute_pos.y, absolute_pos.z)
            indices[idx] = i
            old_nodes[idx] = data[i]
            old_param1[idx] = param1[i]
            old_param2[idx] = param2[i]
            data[i] = entry.data
            param1[i] = entry.param1
            param2[i] = entry.param2
            new_nodes[idx] = entry.data
            new_param1[idx] = entry.param1
            new_param2[idx] = entry.param2
        end
        vm:set_data(data)
        vm:set_light_data(param1)
        vm:set_param2_data(param2)
        vm:write_to_map()
        undo_stack[name] = undo_stack[name] or {}
        redo_stack[name] = {}
        table.insert(undo_stack[name], {
            action_type = "paste",
            p1 = p1,
            p2 = p2,
            indices = indices,
            old_nodes = old_nodes,
            old_param1 = old_param1,
            old_param2 = old_param2,
            new_nodes = new_nodes,
            new_param1 = new_param1,
            new_param2 = new_param2
        })
        if #undo_stack[name] > MAX_HISTORY then
            table.remove(undo_stack[name], 1)
        end
        return true, "Successfully pasted " .. #nodes_list .. " nodes relative to your location."
    end
})

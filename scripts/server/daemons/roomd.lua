--roomd.lua
--Created by wugd
--负责房间相关的功能模块

--创建模块声明
module("ROOM_D",package.seeall)

--场景列表
local room_list  = {}
local room_table = {}
local freq_table = {}

local all_room_details = {}

--定义内部接口，按照字母顺序排序
local function clear_doing_enter_room(entity)
    if entity:is_user() then
        entity:delete_temp("doing_enter_room")
    end
end

--定义公共接口，按照字母顺序排序

-- 广播消息
function broadcast_message(room_name, msg, ...)
    -- 取得该房间编号对应的房间对象
    local room = room_list[room_name]
    if not room then
        return
    end

    -- 广播消息
    room:broadcast_message(msg, ...)
end

--创建全部场景
function create_allroom(filename)
    room_table = IMPORT_D.readcsv_to_tables(filename)
    for k, v in pairs(room_table) do
        create_room(v)
    end
end

-- 获取csv表信息
function get_room_table()
    return room_table
end

--创建一个场景
function create_room(roomdata)
    local room_class = _G[roomdata.room_class]
    assert(room_class ~= nil, "场景配置必须存在")
    local room = clone_object(room_class, roomdata)
    assert(room_list[room:get_room_name()] == nil, "重复配置房间")
    room_list[room:get_room_name()] = room
    REDIS_D.add_subscribe_channel(room:get_listen_channel())
    return room
end

function enter_room(entity, room_name)
    
end

--获取房间对象
function get_room_list()
    return room_list
end

function get_room(room_name)
    return room_list[room_name]
end

--离开一个场景
function leave_room(entity, room_name)
    local room = room_list[room_name]

    if room then
        room:entity_leave(entity)
    end

    -- 删除玩家的位置信息
    entity:delete_temp("room")
end

-- 根据rid获取room_name
function get_room_name_by_rid(rid)
    local rid_ob = find_object_by_rid(rid)
    if not is_object(rid_ob) then
        return
    end
    return (rid_ob:query_temp("room"))
end

-- 获取某个房间玩家列表
function get_room_entity_list(room_name)
    local peo_list = {}
    local room = room_list[room_name]
    if room then
        local room_peoples = room:get_room_entity()
        local user
        local find_object_by_rid = find_object_by_rid
        local name, account, result
        local query_func
        for rid, info in pairs(room_peoples) do

            if info.ob_type == OB_TYPE_USER then
                user = find_object_by_rid(rid)
                if is_object(user) then
                    if not query_func then
                        query_func = user.query
                    end

                    name    = query_func(user, "name")
                    account = query_func(user, "account")
                    level   = query_func(user, "level")
                    result  = {
                        rid     = rid,
                        name = name,
                        account = account,
                        level = level
                    }

                    peo_list[#peo_list+1] = result
                else
                    room_peoples[rid] = nil
                end
            end
        end
    end

    return {
        ret         = #peo_list,
        result_list = peo_list,
    }
end

function update_room_entity(room_name, rid, pkg_info)

    local room = room_list[room_name]

    if not room then
        return
    end

    room:update_entity(rid, pkg_info)
end

function get_detail_room(room_name)
    local room = all_room_details[room_name or ""]
    if not room then
        return
    end

    if os.time() - (room.time or 0) > 180 then
        all_room_details[room_name] = nil
        room = nil
    end

    return room
end

function redis_room_detail(detail)
    trace("redis_room_detail = %o", detail)
    for name,value in pairs(detail) do
        value["time"] = os.time()
        all_room_details[name] = value
    end
end

function redis_dispatch_message(room_name, user_rid, msg_buf)
    local room = room_list[room_name]
    if not is_object(room) then
        LOG.err("房间'%s'信息不存在", room_name)
        return
    end
    local net_msg = pack_raw_message(msg_buf)
    if not net_msg then
        LOG.err("发送给房间:'%s',用户:'%s',消息失败", room_name, user_rid)
        return
    end

    local name, args = net_msg:msg_to_table()
    if name and args then
        --TODO
    end
    del_message(net_msg)
end

function room_detail_update(detail)

end

local function logic_cmd_room_message(user, buffer)
    trace("receiver logic_cmd_room_message")
    local room_name = user:query_temp("room_name")
    if sizeof(room_name) == 0 then
        return
    end

    INTERNAL_COMM_D.send_room_raw_message(room_name, get_ob_rid(user), buffer)
end

local function publish_room_detail()
    trace("publish_room_detail!!!")
    local result = {}
    for room_name,room in pairs(room_list) do
        local room_entity = room:get_room_entity()
        result[room_name] = { amount = sizeof(room_entity), game_type = room:get_game_type() }
    end
    REDIS_D.run_publish(SUBSCRIBE_ROOM_DETAIL_RECEIVE, encode_json(result))
end

-- 模块的入口执行
function create()
    if ENABLE_ROOM then
        create_allroom("data/txt/room.txt")
    end
    
    register_msg_filter("cmd_room_message", logic_cmd_room_message)

    if SERVER_TYPE == SERVER_LOGIC or STANDALONE then
        REDIS_D.add_subscribe_channel(SUBSCRIBE_ROOM_DETAIL_RECEIVE)
    end
end

local function init()
    if ENABLE_ROOM then
        publish_room_detail()
        set_timer(60000, publish_room_detail, nil, true)
    end
end

create()
register_post_init(init)
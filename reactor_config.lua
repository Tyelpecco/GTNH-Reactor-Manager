-- reactor_config.lua
local sides = require("sides") -- 导入sides模块，用于定义方向常量

local GLOBAL_REDSTONE_IO_UUID = "3bf97ebb-19b3-4bc9-a297-57d52b57e37a"

-- 全局方向配置
local global_directions = {
    coolant_buffer_side = sides.north,    -- 冷却单元缓存区在转运器的北面
    fuel_rod_supply_side = sides.south,   -- 燃料棒补充方向在转运器的南面
    reactor_internal_side = sides.down,   -- 反应堆本体在转运器的下面 (通常是这样)
    waste_output_side = sides.up,         -- 废弃物（过热单元/枯竭燃料棒）输出方向在转运器的上面
    redstone_input_side = sides.top       -- 红石输入信号从顶部接收
}

local reactors = 
{
    {
        id = "reactor1",
        chamber_uuid = "fad193d2-33a1-4f67-a309-b8302be800e9",
        transposer_uuid = "383d43ea-70f6-498b-ba8a-92364f2d07fd",
        enabled = true
    },
    {
        id = "reactor2",
        chamber_uuid = "723b22e4-013e-4ae1-a16c-067c7b4d26b1",
        transposer_uuid = "3af13fc2-7a4f-488d-8ceb-f97fb094c320",
        enabled = true
    },
    {
        id = "reactor3",
        chamber_uuid = "cdfb71f1-c7e7-443d-aed3-bcc90a5db3de",
        transposer_uuid = "909d0dbd-837a-4710-af8c-97386354cb8d",
        enabled = true
    },
    {
        id = "reactor4",
        chamber_uuid = "db90ae76-a1c1-4ef8-9e6f-0aaa92348478",
        transposer_uuid = "87de836d-c58b-47c7-9886-df30ac047497",
        enabled = true
    }
}

return {
    redstone_io_uuid = GLOBAL_REDSTONE_IO_UUID,
    directions = global_directions, -- 添加方向配置
    reactors = reactors
}

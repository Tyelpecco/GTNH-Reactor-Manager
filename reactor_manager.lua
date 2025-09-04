local component = require("component")
local sides = require("sides")
local term = require("term")

-- 安全加载配置文件
local function loadConfig()
    local ok, config = pcall(require, "reactor_config")
    if not ok then
        print("配置文件加载失败: "..tostring(config))
        return {}
    end
    return config
end

-- 获取组件代理的安全方法
local function getComponentProxy(uuid)
    if not uuid or uuid == "" then return nil end
    local ok, proxy = pcall(component.proxy, uuid)
    return ok and proxy or nil
end

-- 检测冷却单元是否过热 (damage>=90)
local function isItemDamaged(slotStack)
    return slotStack and 
           slotStack.damage >= 90 and 
           slotStack.name == "gregtech:gt.360k_Helium_Coolantcell"
end

--检测燃料棒是否枯竭
local function isItemDepleted(slotStack)
    return slotStack and 
           slotStack.name == "IC2:reactorUraniumQuaddepleted"
end

-- 移动物品
local function transferItem(transposer, slot, source, sink)
    local success, result = pcall(transposer.transferItem, 
        source, -- 来源方向
        sink,   -- 目标方向
        1,      -- 转移数量
        slot    -- 来源槽位
    )
    
    if not success then
        print("转移错误: "..tostring(result))
        return false
    end
    
    return result -- 返回boolean表示是否成功
end

-- 处理单个反应堆的物品
local function processReactorItems(reactor)
    if not reactor.enabled then
        print(reactor.id.." 已禁用，跳过处理")
        return 0
    end
    
    if not reactor.transposer then
        print(reactor.id.." 缺少转运器")
        return 0
    end
    
    local transposer = reactor.transposer
    local damagedMovedCount = 0
    local depletedMovedCount = 0
    
    for slot = 1, 54 do  -- 固定54格
        local success, stack = pcall(transposer.getStackInSlot, sides.down, slot)
        
        if success then
            if stack then  -- 只有在成功且有物品时才检查
                if isItemDamaged(stack) then
                    print("发现过热冷却单元: "..(stack.label or "未知物品").." (槽位 "..slot..")")
                    if transferItem(transposer, slot, sides.down, sides.up) then
                        transferItem(transposer, slot, sides.front, sides.down)  --补充冷却单元
                        damagedMovedCount = damagedMovedCount + 1
                    end
                elseif isItemDepleted(stack) then
                    print("发现枯竭燃料棒: "..(stack.label or "未知物品").." (槽位 "..slot..")")
                    if transferItem(transposer, slot, sides.down, sides.up) then
                        depletedMovedCount = depletedMovedCount + 1
                    end
                end
            end
        else  -- 直接处理错误情况
            print(reactor.id.." 槽位 "..slot.." 错误: "..tostring(stack))
        end
    end
    
    print(reactor.id..": 移动了 "..damagedMovedCount.." 个冷却单元")
    print(reactor.id..": 移动了 "..depletedMovedCount.." 个枯竭燃料棒")
    return damagedMovedCount + depletedMovedCount
end

-- 主函数
local function main()
    -- 加载配置
    local config = loadConfig()
    
    if #config == 0 then
        print("未找到有效的反应堆配置")
        return
    end
    
    -- 初始化反应堆组件
    local reactors = {}
    for i, entry in ipairs(config) do
        reactors[i] = {
            id = entry.id,
            chamber = getComponentProxy(entry.chamber_uuid),
            transposer = getComponentProxy(entry.transposer_uuid),
            enabled = entry.enabled
        }
    end
    
    -- 处理所有反应堆
    local totalMoved = 0
    
    while(true) do
        totalMoved = 0
        for _, reactor in ipairs(reactors) do
            if reactor.chamber and reactor.transposer then
                print("处理反应堆: "..reactor.id)
                totalMoved = totalMoved + processReactorItems(reactor)
            else
                print("跳过不完整的反应堆: "..reactor.id)
            end
        end
        
        print("所有反应堆处理完成，共移动 "..totalMoved.." 个物品")
        os.sleep(2)
        term.clear()
    end
end

-- 启动程序
main()

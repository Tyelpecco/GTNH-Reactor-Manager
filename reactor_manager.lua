local component = require("component")
local sides = require("sides")
local term = require("term")
local event = require("event")

-- 定义日志颜色
local COLOR_RED = "\027[1;31m"
local COLOR_YELLOW = "\027[1;33m"
local COLOR_GREEN = "\027[1;32m"
local COLOR_BLUE = "\027[1;34m"
local COLOR_RESET = "\027[0m"

-- 全局方向变量（将在 loadConfig 后设置）
local configDirections = {}

--- 从 reactor_config.lua 文件加载反应堆配置。
--- @return table config 配置表，其中包含全局红石IO UUID、各方向配置和每个反应堆的ID、腔室UUID、转运器UUID和启用状态。
local function loadConfig()
    local ok, config = pcall(require, "reactor_config")
    if not ok then
        print(COLOR_RED.."配置文件加载失败: "..tostring(config)..COLOR_RESET)
        return { reactors = {}, directions = {} }
    end
    
    local loadedConfig = config.reactors or config
    local redstoneUuid = config.redstone_io_uuid or nil
    local directions = config.directions or {} 
    
    local clonedReactors = {}
    for i, entry in ipairs(loadedConfig) do
        clonedReactors[i] = {
            id = entry.id,
            chamber_uuid = entry.chamber_uuid,
            transposer_uuid = entry.transposer_uuid,
            enabled = entry.enabled 
        }
    end
    return {
        redstone_io_uuid = redstoneUuid,
        directions = directions, 
        reactors = clonedReactors
    }
end

--- 通过UUID获取组件的代理对象。
--- @param string uuid 组件的通用唯一标识符。
--- @return table|nil proxy 如果成功，返回组件的代理对象；否则返回nil。
local function getComponentProxy(uuid)
    if not uuid or uuid == "" then return nil end
    local ok, proxy = pcall(component.proxy, uuid)
    return ok and proxy or nil
end

--- 检查物品堆栈是否是过热的氦冷却单元。
--- 过热的定义是损坏值(damage)大于等于70，且物品名称匹配"gregtech:gt.360k_Helium_Coolantcell"。
--- @param table slotStack 物品堆栈对象，可能包含name和damage字段。
--- @return boolean isDamaged 如果物品是过热的指定冷却单元，返回true；否则返回false。
local function isItemDamaged(slotStack)
    return slotStack and
           slotStack.damage >= 70 and
           slotStack.name == "gregtech:gt.360k_Helium_Coolantcell"
end

--- 检查物品堆栈是否是枯竭的铀燃料棒。
--- 枯竭的定义是物品名称匹配"IC2:reactorUraniumQuaddepleted"。
--- @param table slotStack 物品堆栈对象，可能包含name字段。
--- @return boolean isDepleted 如果物品是枯竭的指定燃料棒，返回true；否则返回false。
local function isItemDepleted(slotStack)
    return slotStack and
           slotStack.name == "IC2:reactorUraniumQuaddepleted"
end

--- 使用转运器移动物品。
--- @param table transposer 转运器组件代理。
--- @param number slot 来源容器的槽位索引。
--- @param number source 物品来源方向 (sides常量)。
--- @param number sink 物品目标方向 (sides常量)。
--- @param number|nil count 要移动的物品数量，默认为1。
--- @return boolean isSuccess 如果移动成功，返回true；否则返回false。
local function transferItem(transposer, slot, source, sink, count)
    count = count or 1
    local success, result = pcall(transposer.transferItem,
        source, 
        sink,   
        count,  
        slot    
    )

    if not success then
        print(COLOR_RED.."转移错误: "..tostring(result)..COLOR_RESET)
        return false
    end

    return result
end

--- 设置反应堆腔室的活跃（开/关）状态。
--- @param table chamber 反应堆腔室组件代理。
--- @param boolean isActive 期望的反应堆状态，true为开机，false为关机。
--- @param string reactorId 反应堆的标识符，用于日志输出。
--- @return boolean isSuccess 如果设置操作成功，返回true；否则返回false。
local function setReactorActive(chamber, isActive, reactorId)
    local ok, status = pcall(chamber.setActive, isActive)
    if not ok then
        print(COLOR_RED..reactorId.." 设置活跃状态失败: "..tostring(status)..COLOR_RESET)
        return false
    end
    print(COLOR_BLUE..reactorId.." 已".. (isActive and "尝试开机" or "关机") ..COLOR_RESET)
    return true
end

--- 检查指定方向的冷却单元缓存区是否已满（54格）。
--- @param table transposer 转运器组件代理。
--- @param number bufferSide 冷却单元缓存区的方向。
--- @return boolean isFull 如果缓存区所有预期槽位都被填充，返回true；否则返回false。
local function isCoolantBufferFull(transposer, bufferSide)
    local assumedMaxSlots = 54 
    local filledSlots = 0
    local ok, size = pcall(transposer.getInventorySize, bufferSide)

    if not ok or not size then
        print(COLOR_RED.."无法获取冷却单元缓存区大小 ("..tostring(bufferSide).."). 假定未满。"..COLOR_RESET)
        return false
    end

    if size ~= assumedMaxSlots then
        print(COLOR_YELLOW.."警告: 冷却单元缓存区实际大小("..size..")与预期("..assumedMaxSlots..")不符。继续按预期大小检查。"..COLOR_RESET)
    end
    
    for slot = 1, assumedMaxSlots do
        local success, stack = pcall(transposer.getStackInSlot, bufferSide, slot)
        if success and stack then
            filledSlots = filledSlots + 1
        end
    end
    return filledSlots >= assumedMaxSlots
end

--- 处理单个反应堆的物品管理和状态控制逻辑。
--- 包括冷却单元检查、更换，燃料棒检查、更换，以及温度监控。
--- 会更新 reactor.requiresAttention 字段。
--- @param table reactor 包含反应堆ID、腔室代理、转运器代理、启用状态和报警状态的表。
--- @return nil
local function processReactor(reactor)
    local chamber = reactor.chamber
    local transposer = reactor.transposer
    local reactorId = reactor.id

    -- 从全局配置中获取方向
    local coolantBufferSide = configDirections.coolant_buffer_side
    local fuelRodSupplySide = configDirections.fuel_rod_supply_side
    local reactorInternalSide = configDirections.reactor_internal_side
    local wasteOutputSide = configDirections.waste_output_side

    reactor.requiresAttention = false

    if not reactor.enabled then
        print(reactorId.." 已禁用，即将尝试关机并跳过处理。")
        setReactorActive(chamber, false, reactorId)
        return
    end

    if not chamber or not transposer then
        print(COLOR_RED.."跳过不完整的反应堆配置: "..reactorId.." (缺少腔室或转运器)"..COLOR_RESET)
        if chamber then
            setReactorActive(chamber, false, reactorId)
        end
        return
    end

    print(COLOR_BLUE..reactorId..": 检查冷却元件缓存区 ("..tostring(coolantBufferSide)..", 预期54格)..."..COLOR_RESET)
    if not isCoolantBufferFull(transposer, coolantBufferSide) then
        print(COLOR_RED..reactorId..": 报警！冷却单元缓存区（"..tostring(coolantBufferSide).."方向）未满54格。请补充！反应堆将尝试关机。"..COLOR_RESET)
        setReactorActive(chamber, false, reactorId)
        reactor.requiresAttention = true
        return
    end

    print(COLOR_BLUE..reactorId..": 检查反应堆内部冷却单元是否过热 ("..tostring(reactorInternalSide)..", 预期54格)..."..COLOR_RESET)
    local damagedCoolantCellsFound = 0
    local damagedCoolantCellsReplaced = 0
    local coolantsReplacementFailure = false

    for slot = 1, 54 do -- 反应堆本体固定54格
        local success, stack = pcall(transposer.getStackInSlot, reactorInternalSide, slot)

        if success then
            if stack and isItemDamaged(stack) then
                print(COLOR_YELLOW.."发现过热冷却单元: "..(stack.label or "未知物品").." (槽位 "..slot..")"..COLOR_RESET)
                damagedCoolantCellsFound = damagedCoolantCellsFound + 1

                setReactorActive(chamber, false, reactorId)

                if transferItem(transposer, slot, reactorInternalSide, wasteOutputSide) then -- 移出过热单元到废弃物容器
                    print(COLOR_GREEN.."已移出过热冷却单元。尝试补充新的..."..COLOR_RESET)
                    if transferItem(transposer, slot, coolantBufferSide, reactorInternalSide) then -- 补充冷却单元到相同槽位，从缓存区
                        print(COLOR_GREEN.."已补充新的冷却单元。"..COLOR_RESET)
                        damagedCoolantCellsReplaced = damagedCoolantCellsReplaced + 1
                    else
                        print(COLOR_RED.."警告: 无法补充新的冷却单元到槽位 "..slot.."。请检查"..tostring(coolantBufferSide).."方向容器！"..COLOR_RESET)
                        coolantsReplacementFailure = true
                    end
                else
                    print(COLOR_RED.."错误: 无法移出过热冷却单元到槽位 "..slot.."。请检查"..tostring(wasteOutputSide).."方向容器！"..COLOR_RESET)
                    coolantsReplacementFailure = true
                end
            end
        else
            print(COLOR_RED..reactorId.." 获取槽位 "..slot.." 错误: "..tostring(stack)..COLOR_RESET)
        end
    end

    if damagedCoolantCellsFound > 0 then
        if coolantsReplacementFailure then
            print(COLOR_RED..reactorId..": 报警！冷却单元更换失败。保持关机！请手动检查并排除故障！"..COLOR_RESET)
            setReactorActive(chamber, false, reactorId)
            reactor.requiresAttention = true
            return
        else
            print(COLOR_GREEN..reactorId..": 成功更换 "..damagedCoolantCellsReplaced.." 个过热冷却单元。"..COLOR_RESET)
        end
    end

    if damagedCoolantCellsReplaced > 0 then
        os.sleep(0.5)
    end

    print(COLOR_BLUE..reactorId..": 检查反应堆内部燃料棒是否枯竭 ("..tostring(reactorInternalSide)..", 预期54格)..."..COLOR_RESET)
    local depletedFuelRodsFound = 0
    local newFuelRodsAdded = 0
    local fuelReplacementFailure = false

    for slot = 1, 54 do -- 反应堆本体固定54格
        local success, stack = pcall(transposer.getStackInSlot, reactorInternalSide, slot)
        if success then
            if stack and isItemDepleted(stack) then
                print(COLOR_YELLOW.."发现枯竭燃料棒: "..(stack.label or "未知物品").." (槽位 "..slot..")"..COLOR_RESET)
                depletedFuelRodsFound = depletedFuelRodsFound + 1

                setReactorActive(chamber, false, reactorId)

                if transferItem(transposer, slot, reactorInternalSide, wasteOutputSide) then -- 移出枯竭燃料棒到废弃物容器
                    print(COLOR_GREEN.."已移出枯竭燃料棒。尝试补充新的..."..COLOR_RESET)
                    -- 从 fuelRodSupplySide 方向的第二个槽位（实际存储）补充新的燃料棒到反应堆
                    if transferItem(transposer, 2, fuelRodSupplySide, reactorInternalSide) then 
                        print(COLOR_GREEN.."已补充新的燃料棒。"..COLOR_RESET)
                        newFuelRodsAdded = newFuelRodsAdded + 1
                    else
                        print(COLOR_RED.."警告: 无法补充新的燃料棒到槽位 "..slot.."。请检查"..tostring(fuelRodSupplySide).."方向容器（单槽，实际物品在槽位2）！"..COLOR_RESET)
                        fuelReplacementFailure = true
                    end
                else
                    print(COLOR_RED.."错误: 无法移出枯竭燃料棒到槽位 "..slot.."。请检查"..tostring(wasteOutputSide).."方向容器！"..COLOR_RESET)
                    fuelReplacementFailure = true
                end
            end
        end
    end

    if depletedFuelRodsFound > 0 then
        if fuelReplacementFailure then
            print(COLOR_RED..reactorId..": 报警！燃料棒更换失败。保持关机！请手动检查并排除故障！"..COLOR_RESET)
            setReactorActive(chamber, false, reactorId)
            reactor.requiresAttention = true
            return
        else
            print(COLOR_GREEN..reactorId..": 成功更换 "..newFuelRodsAdded.." 个枯竭燃料棒。"..COLOR_RESET)
        end
    end

    if newFuelRodsAdded > 0 then
        os.sleep(0.5)
    end

    print(COLOR_BLUE..reactorId..": 检查反应堆温度..."..COLOR_RESET)
    local okHeat, currentHeat = pcall(chamber.getHeat)
    local okMaxHeat, maxHeat = pcall(chamber.getMaxHeat)

    if not okHeat or not okMaxHeat or not currentHeat or not maxHeat or maxHeat == 0 then
        print(COLOR_RED..reactorId..": 无法获取反应堆温度信息。报警并尝试关机！"..COLOR_RESET)
        setReactorActive(chamber, false, reactorId)
        reactor.requiresAttention = true
        return
    end

    local heatPercentage = (currentHeat / maxHeat) * 100
    print(reactorId..": 当前温度: "..string.format("%.2f%%", heatPercentage).." ("..currentHeat.."/"..maxHeat..")")

    if heatPercentage >= 20 then
        print(COLOR_RED..reactorId..": 报警！反应堆温度过高 ("..string.format("%.2f%%", heatPercentage).."%)。尝试关机并等待降温指示，请立即手动干预！"..COLOR_RESET)
        setReactorActive(chamber, false, reactorId)
        reactor.requiresAttention = true
        return
    else
        reactor.requiresAttention = false
    end

    print(COLOR_GREEN..reactorId..": 所有检查通过。尝试开机中..."..COLOR_RESET)
    setReactorActive(chamber, true, reactorId)
end

--- 初始化反应堆管理器。
--- 加载配置，创建组件代理，并进行初步检查。
--- @return table|nil 初始化成功时返回包含 reactors 和 redstoneIo 的表，否则返回 nil。
local function initializeManager()
    local loadedConfig = loadConfig()
    local reactorConfigs = loadedConfig.reactors
    local redstoneIoUuid = loadedConfig.redstone_io_uuid
    configDirections = loadedConfig.directions -- 将加载的方向配置赋值给全局变量

    if #reactorConfigs == 0 then
        print(COLOR_RED.."未找到有效的反应堆配置。脚本退出。"..COLOR_RESET)
        return nil
    end
    
    -- 检查是否所有必要的方向都已配置
    if not configDirections.coolant_buffer_side or 
       not configDirections.fuel_rod_supply_side or 
       not configDirections.reactor_internal_side or 
       not configDirections.waste_output_side or
       not configDirections.redstone_input_side then -- 添加红石输入方向检查
        print(COLOR_RED.."错误: 配置文件中缺少关键方向配置 (coolant_buffer_side, fuel_rod_supply_side, reactor_internal_side, waste_output_side, redstone_input_side)。脚本退出。"..COLOR_RESET)
        return nil
    end

    local reactors = {}
    for i, entry in ipairs(reactorConfigs) do
        reactors[i] = {
            id = entry.id,
            chamber = getComponentProxy(entry.chamber_uuid),
            transposer = getComponentProxy(entry.transposer_uuid),
            enabled = entry.enabled,
            requiresAttention = false
        }
    end

    local redstoneIo = getComponentProxy(redstoneIoUuid)
    if not redstoneIo then
        print(COLOR_RED.."错误: 未找到红石IO组件或UUID配置不正确。请检查UUID: "..tostring(redstoneIoUuid)..COLOR_RESET)
        print(COLOR_RED.."脚本无法启动，因为红石控制是强制性的。"..COLOR_RESET)
        return nil
    end

    print(COLOR_GREEN.."反应堆管理器初始化完成。"..COLOR_RESET)
    return {
        reactors = reactors,
        redstoneIo = redstoneIo
    }
end


--- 脚本的主执行函数。
--- 负责加载配置，初始化反应堆对象，并进入无限循环，定期处理所有启用的反应堆。
--- 根据反应堆的报警状态调整检查周期。
--- @return nil
local function main()
    local initData = initializeManager()
    if not initData then
        return -- 初始化失败，脚本退出
    end

    local reactors = initData.reactors
    local redstoneIo = initData.redstoneIo

    print(COLOR_GREEN.."反应堆管理器启动。"..COLOR_RESET)
    while true do
        term.clear()
        term.setCursor(1,1)
        print("======== 反应堆管理系统 ========")
        -- Step 1: 读取红石控制信号并更新所有反应堆的全局启用状态
        local globalEnable = false
        local rsInput = redstoneIo.getInput(configDirections.redstone_input_side) -- 使用配置的方向
        if rsInput > 0 then 
            globalEnable = true
            print(COLOR_GREEN.."红石信号: 启用所有反应堆。"..COLOR_RESET)
        else
            print(COLOR_YELLOW.."红石信号: 禁用所有反应堆。"..COLOR_RESET)
        end
        local anyReactorNeedsAttention = false
        
        for _, reactor in ipairs(reactors) do
            reactor.enabled = globalEnable 
            print(COLOR_BLUE.."\n--- 处理反应堆: "..reactor.id.." ---"..COLOR_RESET)
            processReactor(reactor)
            if reactor.requiresAttention then
                anyReactorNeedsAttention = true
            end
        end
        print("\n======== 所有反应堆处理完成 ========")
        if anyReactorNeedsAttention then
            print(COLOR_RED.."重要提醒: 有反应堆当前处于异常状态或需要手动干预，请查看上方日志！"..COLOR_RESET)
            event.pull(5, "timer") 
        else
            print(COLOR_GREEN.."所有反应堆状态良好。下一次检查在2秒后..."..COLOR_RESET)
            os.sleep(2) 
        end
    end
end

-- 启动主函数
main()

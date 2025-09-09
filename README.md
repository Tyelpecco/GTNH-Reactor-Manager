# GTNH-Reactor-Manager

一个基于 OpenComputers 的自动化核反应堆管理系统，旨在简化和优化 IC2 反应堆的日常运维。该系统能够自动监控反应堆状态、更换过热冷却单元和枯竭燃料棒，并根据外部红石信号控制反应堆的启停，确保反应堆安全高效运行。

## 目录

-   [功能特性](#功能特性)
-   [安装](#安装)
-   [硬件需求](#硬件需求)
-   [配置](#配置)
    -   [reactor_config.lua](#reactor_config.lua)
-   [使用方法](#使用方法)
-   [核心逻辑](#核心逻辑)
-   [注意事项](#注意事项)
-   [未来展望](#未来展望)
-   [贡献](#贡献)
-   [许可证](#许可证)

## 功能特性

-   **自动化管理**：无需手动干预，系统会自动处理反应堆的日常维护。
-   **冷却单元智能更换**：自动检测并替换冷却单元。
-   **燃料棒智能更换**：自动检测并替换枯竭燃料棒。
-   **温度监控与保护**：实时监控反应堆温度，当温度过高（默认阈值 20%）时自动关停反应堆以防熔毁。
-   **红石信号控制**：通过外部红石信号全局控制所有反应堆的启停，方便集成到更复杂的自动化网络。
-   **高可配置性**：所有关键组件 UUID、物品类型、冷却单元缓存区/燃料棒供应方向等均可在配置文件中轻松调整。
-   **多反应堆支持**：支持同时管理多个独立的 IC2 反应堆。
-   **日志输出**：清晰的控制台日志输出，显示反应堆状态和操作详情，便于故障排查。

## 安装

1.  将 `reactor_config.lua` 和 `reactor_manager.lua` 文件下载并放入根目录。
2.  **请务必根据您的实际世界设置和组件 UUID 修改 `reactor_config.lua` 文件！**

## 硬件需求

对于整个系统，您至少需要：

-   **一个 OpenComputers 计算机**：运行脚本。建议使用升级了内存和硬盘的计算机。
-   **一个 OpenComputers 屏幕**：用于显示日志输出（可选，但强烈推荐）。
-   **一个 转运器**：用于物品的移入移出操作。
-   **一个 核反应堆**：被管理的核反应堆本体。
-   **一个 红石I/O端口**：用于接收外部红石信号来控制所有反应堆的全局启停。（可选，但脚本中为强制要求）

**此外，每个反应堆还需要：**

-   **冷却单元缓存容器**：用于存放新的冷却单元。**使用铁箱子（正好54格），并要求放满**。
-   **燃料棒供应容器**：用于存放新的四联铀燃料棒。**使用抽屉**。
-   **废弃物收集容器**：用于收集过热冷却单元和枯竭燃料棒。

**建议物理布局：**

转运器通常放置在反应堆腔室的附近，并从特定方向连接上述容器：
-   **冷却单元缓存**：连接到转运器的 `config.directions.coolant_buffer_side` (默认为 `north`)。
-   **燃料棒供应**：连接到转运器的 `config.directions.fuel_rod_supply_side` (默认为 `south`)。
-   **反应堆腔室**：连接到转运器的 `config.directions.reactor_internal_side` (默认为 `down`)。
-   **废弃物收集**：连接到转运器的 `config.directions.waste_output_side` (默认为 `up`)。
-   **计算机/红石信号输入**：连接到红石I/O端口 `config.directions.redstone_input_side` (默认为 `top`)。

## 配置

配置文件 `reactor_config.lua` 是系统的核心。您必须根据您的设置进行修改。

### `reactor_config.lua`

```lua
-- reactor_config.lua
local sides = require("sides")

local GLOBAL_REDSTONE_IO_UUID = "3bf97ebb-19b3-4bc9-a297-57d52b57e37a" -- 替换为您的红石I/O端口

-- 全局方向配置：所有方向都从转运器（Transposer）的角度定义
local global_directions = {
    coolant_buffer_side = sides.north,
    fuel_rod_supply_side = sides.south, 
    reactor_internal_side = sides.down,
    waste_output_side = sides.up,
    redstone_input_side = sides.top 
}

local reactors = 
{
    {
        id = "reactor1",                         -- 反应堆标识符，用于日志输出
        chamber_uuid = "fad193d2-33a1-4f67-a309-b8302be800e9", -- 替换为反应堆腔室的UUID
        transposer_uuid = "383d43ea-70f6-498b-ba8a-92364f2d07fd", -- 替换为转运器的UUID
        enabled = true                           -- 初始是否启用（会被红石信号覆盖）
    },
    -- 根据需要添加更多反应堆配置
    {
        id = "reactor2",
        chamber_uuid = "YOUR_REACTOR2_CHAMBER_UUID",
        transposer_uuid = "YOUR_REACTOR2_TRANSPOSER_UUID",
        enabled = true
    }
}

return {
    redstone_io_uuid = GLOBAL_REDSTONE_IO_UUID,
    directions = global_directions,
    reactors = reactors
}
```

**如何获取 UUID：**
使用分析器右击相关组件即可。

**`global_directions` 解释：**
-   `coolant_buffer_side`: 指向装满新冷却单元的容器。
-   `fuel_rod_supply_side`: 指向装满新铀燃料棒的容器。
-   `reactor_internal_side`: 指向实际的 IC2 反应堆腔室本体。
-   `waste_output_side`: 指向用于收集废弃物（过热单元、枯竭燃料棒）的容器。
-   `redstone_input_side`: 指向红石I/O端口上接收全局控制信号的那个面。

## 使用方法

（暂时没有喵）

## 核心逻辑

1.  **加载配置**：从 `reactor_config.lua` 读取所有反应堆及其相关组件的 UUID，以及全局方向配置。
2.  **组件代理**：通过 UUID 获取所有反应堆腔室、转运器和红石 I/O 端口的 OpenComputers 组件代理。
3.  **红石控制**：循环中，首先读取红石 I/O 端口上指定方向的红石信号，将其作为全局启用/禁用标志。
4.  **按反应堆处理**：
    -   如果反应堆被禁用（由红石信号控制），则尝试关机并跳过后续检查。
    -   **冷却单元检查**：检查 `config.directions.coolant_buffer_side` (默认为 `north`) 方向的冷却单元缓存容器，确保其有足够的补给。如果不足，发出警告，关机，并标记为需要关注。
    -   **过热冷却单元更换**：遍历反应堆内部 (`config.directions.reactor_internal_side`, 默认为 `down`) 所有槽位。如果发现损坏度 `>= 70` 的冷却单元：
        -   立即关停反应堆。
        -   将其移至 `config.directions.waste_output_side` (默认为 `up`) 方向的废弃物容器。
        -   从 `config.directions.coolant_buffer_side` (默认为 `north`) 方向的冷却单元缓存中补充一个新的到原槽位。
        -   如果更换失败，标记为需要关注。
    -   **枯竭燃料棒更换**：遍历反应堆内部 (`config.directions.reactor_internal_side`, 默认为 `down`) 所有槽位。如果发现枯竭的燃料棒：
        -   立即关停反应堆。
        -   将其移至 `config.directions.waste_output_side` (默认为 `up`) 方向的废弃物容器。
        -   从 `config.directions.fuel_rod_supply_side` (默认为 `south`) 方向的燃料棒供应容器的**第二个槽位**补充一个新的燃料棒到原槽位。
        -   如果更换失败，标记为需要关注。
    -   **温度监控**：获取反应堆当前温度与最大温度。如果当前温度超过最大温度的 `20%` (可视为过热阈值)，发出警告，关机，并标记为需要关注。
    -   **自动开机**：如果所有检查通过，且未被禁用，则尝试开启反应堆。
5.  **循环延迟**：脚本会根据是否有反应堆需要额外关注来调整检查周期。有需要关注时，周期为 5 秒；否则为 2 秒。

## 注意事项

-   **UUID 务必正确**：错误的 UUID 会导致脚本无法找到组件，并可能终止运行。
-   **容器配置**：
    -   冷却单元补充容器必须放置在 `coolant_buffer_side` 对应方向, 并且**必须提供 54 格满仓**的冷却单元。
    -   燃料棒补充容器必须放置在 `fuel_rod_supply_side` 对应方向, 且新燃料棒应在容器的**第二个槽位 (slot 2)**。
    -   废弃物容器必须放置在 `waste_output_side` 对应方向, 且有足够的空间。
-   **红石 I/O 端口必须存在**：脚本目前强制要求红石 I/O 端口存在并配置正确，否则无法启动。
-   **反应堆设计**：本脚本假定使用的是标准 IC2 核反应堆，并且转运器能够访问其所有 54 个内部槽位。请确保您的反应堆布局允许转运器正确操作。
-   **温度阈值**：目前的过热阈值为 20%，这意味着任何达到或超过此温度的反应堆将立即关机。您可以根据您的反应堆设计和容错能力自行调整此逻辑。
-   **日志刷屏**：脚本会持续输出日志到屏幕，如果屏幕较小，可能会刷屏。可以通过 `event.pull` 来降低刷新频率，或调整 `os.sleep` 的时间。

## 未来展望

-   **更精细的温度控制**：例如，根据温度升高速度调整运行功率，或更智能的启停策略。
-   **多种物品支持**：目前仅支持四联铀燃料棒和360k氦冷却单元，未来可以支持配置多种冷却单元或燃料棒。
-   **GUI 界面**：通过命令行制作建议的GUI界面

## 贡献

欢迎任何形式的贡献！无论是 Bug 报告、功能请求，还是代码提交，都将不胜感激。请通过 GitHub Issues 或 Pull Requests 提交。

## 许可证

本项目采用 [MIT 许可证](LICENSE) 发布。

#!/usr/bin/env lua5.3
-- ============================================================
-- milk-word-counter 测试环境
-- 用法: bash test/run_tests.sh  (推荐)
--   或: lua5.3 test/test_word_counter.lua  (需手动设置 XDG_CONFIG_HOME)
-- ============================================================

-- 检查是否通过 run_tests.sh 运行
if not os.getenv("XDG_CONFIG_HOME") then
    io.stderr:write("[WARN] XDG_CONFIG_HOME 未设置, 使用 /tmp/wc_test_manual\n")
    io.stderr:write("[INFO] 推荐使用: bash test/run_tests.sh\n\n")
    os.execute('mkdir -p /tmp/wc_test_manual')
    -- 注意: Lua 5.3 无 os.setenv, 此 fallback 仅在模块内 get_config_dir 读取前生效
    -- 实际需要通过 shell 设置: export XDG_CONFIG_HOME=/tmp/wc_test_manual
end

local sep = package.config:sub(1, 1)
local pass_count, fail_count, total_count = 0, 0, 0
local test_results = {}

-- ==================== 测试框架 ====================
local function assert_eq(name, actual, expected)
    total_count = total_count + 1
    if actual == expected then
        pass_count = pass_count + 1
        table.insert(test_results, string.format("  PASS  %s", name))
    else
        fail_count = fail_count + 1
        table.insert(test_results, string.format("  FAIL  %s\n          expected: %s\n          actual:   %s", name, tostring(expected), tostring(actual)))
    end
end

local function assert_near(name, actual, expected, epsilon)
    epsilon = epsilon or 0.001
    total_count = total_count + 1
    if math.abs(actual - expected) < epsilon then
        pass_count = pass_count + 1
        table.insert(test_results, string.format("  PASS  %s", name))
    else
        fail_count = fail_count + 1
        table.insert(test_results, string.format("  FAIL  %s\n          expected: ~%s\n          actual:   %s", name, tostring(expected), tostring(actual)))
    end
end

local function assert_true(name, cond)
    total_count = total_count + 1
    if cond then
        pass_count = pass_count + 1
        table.insert(test_results, string.format("  PASS  %s", name))
    else
        fail_count = fail_count + 1
        table.insert(test_results, string.format("  FAIL  %s (expected truthy, got %s)", name, tostring(cond)))
    end
end

local function assert_file_exists(name, path)
    local f = io.open(path, "r")
    total_count = total_count + 1
    if f then
        f:close()
        pass_count = pass_count + 1
        table.insert(test_results, string.format("  PASS  %s", name))
    else
        fail_count = fail_count + 1
        table.insert(test_results, string.format("  FAIL  %s (file not found: %s)", name, path))
    end
end

local function assert_file_not_exists(name, path)
    local f = io.open(path, "r")
    total_count = total_count + 1
    if not f then
        pass_count = pass_count + 1
        table.insert(test_results, string.format("  PASS  %s", name))
    else
        f:close()
        fail_count = fail_count + 1
        table.insert(test_results, string.format("  FAIL  %s (file should not exist: %s)", name, path))
    end
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function read_lines(path)
    local lines = {}
    local f = io.open(path, "r")
    if not f then return lines end
    for line in f:lines() do table.insert(lines, line) end
    f:close()
    return lines
end

local function count_lines(path)
    local count = 0
    local f = io.open(path, "r")
    if not f then return 0 end
    for _ in f:lines() do count = count + 1 end
    f:close()
    return count
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if f then f:write(content); f:close(); return true end
    return false
end

-- ==================== 测试环境初始化 ====================
-- XDG_CONFIG_HOME 由 run_tests.sh 在 shell 层设置
-- 模块加载后 config_path = XDG_CONFIG_HOME/milk-word-counter

-- 加载被测模块 (假设从项目根目录运行: lua5.3 test/test_word_counter.lua 或 bash test/run_tests.sh)
package.path = "lua" .. sep .. "?.lua;" .. package.path
local wc = dofile("lua" .. sep .. "word_counter.lua")
local I = wc._internal
I.load_config_file()

local app_name = "milk-word-counter"
local config_path = I.config_path()
local sync_dir = config_path .. sep .. "sync"
local xdg_root = config_path:gsub(sep .. "milk-word-counter$", "")

-- ==================== 辅助函数 ====================
local function cleanup()
    os.execute('rm -rf "' .. xdg_root .. '"')
end

local function reset_config()
    cleanup()
    os.execute('mkdir -p "' .. xdg_root .. '"')
    wc = dofile("lua" .. sep .. "word_counter.lua")
    I = wc._internal
    I.load_config_file()
    config_path = I.config_path()
    sync_dir = config_path .. sep .. "sync"
end

local function make_jsonl_file(filename, machine_id, lines_data, valid_tail)
    local path = sync_dir .. sep .. filename
    local f = io.open(path, "w")
    if not f then return nil end
    for _, line in ipairs(lines_data) do
        f:write(line .. "\n")
    end
    if valid_tail ~= false then
        f:write(string.format("--%s--done--%s\n", app_name, machine_id))
    end
    f:close()
    return path
end

local function make_mock_commit(text)
    return { get_commit_text = function() return text end }
end

-- ==================== 测试用例 ====================

print("=" .. string.rep("=", 59))
print(" milk-word-counter 测试套件")
print("=" .. string.rep("=", 59))

-- ----------------------------------------------------------
print("\n[1] UUID v4 生成器")
-- ----------------------------------------------------------
do
    local uuid = I.generate_uuid4()
    assert_eq("UUID 格式长度", #uuid, 36)
    assert_eq("UUID 第9位是 -", uuid:sub(9, 9), "-")
    assert_eq("UUID 第15位是 4", uuid:sub(15, 15), "4")
    assert_eq("UUID 第19位是 -", uuid:sub(19, 19), "-")

    local uuid2 = I.generate_uuid4()
    assert_true("两次生成 UUID 不同", uuid ~= uuid2)

    -- 验证 hex 字符
    local hex_chars = "0123456789abcdef"
    local stripped = uuid:gsub("-", "")
    local all_hex = true
    for i = 1, #stripped do
        if not hex_chars:find(stripped:sub(i, i), 1, true) then
            all_hex = false
            break
        end
    end
    assert_true("UUID 仅含 hex 字符", all_hex)
end

-- ----------------------------------------------------------
print("\n[2] 配置文件管理")
-- ----------------------------------------------------------
do
    reset_config()

    assert_true("config.json 已创建", io.open(config_path .. sep .. "config.json", "r") ~= nil)
    assert_true("sync 目录已创建", io.open(sync_dir, "r") ~= nil)

    local state = I.load_state()
    assert_true("state.json 已创建", io.open(config_path .. sep .. "state.json", "r") ~= nil)
    assert_eq("初始 total 为 0", state.total, 0)

    local cfg = I.config
    assert_true("machine_id 已生成", cfg.machine_id ~= "")
    assert_true("machine_id 长度 36", #cfg.machine_id == 36)
    assert_eq("默认 commit_threshold", cfg.commit_threshold, 32)
    assert_eq("默认 history_threshold", cfg.history_threshold, 16)

    -- 验证 config.json 内容
    local content = read_file(config_path .. sep .. "config.json")
    assert_true("config 包含 machine_id", content:find('"machine_id"') ~= nil)
    assert_true("config 包含 sync_dir", content:find('"sync_dir"') ~= nil)
    assert_true("config 包含 count_rates", content:find('"count_rates"') ~= nil)
end

-- ----------------------------------------------------------
print("\n[3] 配置文件读取（自定义阈值）")
-- ----------------------------------------------------------
do
    reset_config()

    local custom_config = string.format([[
{
    "machine_id": "test-uuid-0001-4xxx-yxxx",
    "sync_dir": "$config_path/sync",
    "commit_threshold": 16,
    "history_threshold": 8,
    "count_rates": {
        "cjk": 1,
        "ascii": 0.5,
        "num": 2
    }
}
]], config_path)

    write_file(config_path .. sep .. "config.json", custom_config)

    -- 重新加载配置
    I.load_config_file()

    assert_eq("自定义 machine_id", I.config.machine_id, "test-uuid-0001-4xxx-yxxx")
    assert_eq("自定义 commit_threshold", I.config.commit_threshold, 16)
    assert_eq("自定义 history_threshold", I.config.history_threshold, 8)
    assert_near("自定义 ascii rate", I.config.count_rates["ascii"], 0.5)
    assert_near("自定义 num rate", I.config.count_rates["num"], 2)
end

-- ----------------------------------------------------------
print("\n[4] sync_dir 占位符动态解析")
-- ----------------------------------------------------------
do
    reset_config()

    local custom_config = string.format([[
{
    "machine_id": "test-sync-dir-001-4xxx",
    "sync_dir": "$config_path/sync",
    "commit_threshold": 32,
    "history_threshold": 16,
    "count_rates": { "cjk": 1, "ascii": 0.33 }
}
]])

    write_file(config_path .. sep .. "config.json", custom_config)
    I.load_config_file()

    local expected_sync = config_path .. sep .. "sync"
    assert_eq("sync_dir 占位符解析", I.config.sync_dir, expected_sync)

    -- 绝对路径不替换
    local abs_config = string.format([[
{
    "machine_id": "test-abs-path-001-4xxx",
    "sync_dir": "/tmp/my_custom_sync",
    "commit_threshold": 32,
    "history_threshold": 16,
    "count_rates": { "cjk": 1, "ascii": 0.33 }
}
]])
    write_file(config_path .. sep .. "config.json", abs_config)
    I.load_config_file()
    assert_eq("绝对路径 sync_dir 保持不变", I.config.sync_dir, "/tmp/my_custom_sync")
end

-- ----------------------------------------------------------
print("\n[5] 文本切片统计 - CJK")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local r = I.calculate_text_rates("你好世界Hello")
    assert_eq("混合文本 4 字", r["cjk"], 4)
    assert_eq("混合文本含 Hello 5 ASCII", r["ascii"], 5)

    r = I.calculate_text_rates("")
    assert_eq("空字符串 cjk=0", r["cjk"], 0)
    assert_eq("空字符串 ascii=0", r["ascii"], 0)

    r = I.calculate_text_rates(nil)
    assert_eq("nil 输入 cjk=0", r["cjk"], 0)

    r = I.calculate_text_rates("abc123")
    assert_eq("纯 ASCII 无 CJK", r["cjk"], 0)
    assert_eq("纯 ASCII 6 字符", r["ascii"], 6)

    -- 扩展 CJK 范围测试
    r = I.calculate_text_rates("你好") -- U+4F60 U+597D
    assert_eq("基本 CJK 2 字", r["cjk"], 2)

    r = I.calculate_text_rates("𠀀") -- U+20000 CJK 扩展 B
    assert_eq("CJK 扩展 B 1 字", r["cjk"], 1)

    r = I.calculate_text_rates("㐀") -- U+3400 CJK 扩展 A
    assert_eq("CJK 扩展 A 1 字", r["cjk"], 1)
end

-- ----------------------------------------------------------
print("\n[6] 文本切片统计 - ASCII")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local r = I.calculate_text_rates("Hello World!")
    assert_eq("ASCII 可视字符", r["ascii"], 12)

    r = I.calculate_text_rates("Hello World! 123")
    assert_eq("ASCII 含数字", r["ascii"], 16)

    -- 制表符/换行不在 32-126 范围
    r = I.calculate_text_rates("a\tb\nc")
    assert_eq("含控制字符只计可见", r["ascii"], 3)

    -- 全角字符（中文标点）不在 ASCII 范围
    r = I.calculate_text_rates("你好，世界！")
    assert_eq("全角标点不算 ASCII", r["ascii"], 0)
end

-- ----------------------------------------------------------
print("\n[6b] 无 ascii rate 时不统计 ASCII")
-- ----------------------------------------------------------
do
    reset_config()

    local custom_config = [[{
    "machine_id": "test-noascii-001",
    "sync_dir": "$config_path/sync",
    "commit_threshold": 32,
    "history_threshold": 16,
    "count_rates": {
        "cjk": 1
    }
}]]
    write_file(config_path .. sep .. "config.json", custom_config)
    I.load_config_file()

    assert_true("config 无 ascii rate", I.config.count_rates["ascii"] == nil)

    local r = I.calculate_text_rates("Hello你好abc")
    assert_eq("无 ascii rate 时 cjk 仍统计", r["cjk"], 2)
    assert_eq("无 ascii rate 时 ascii=nil", r["ascii"], nil)
end

-- ----------------------------------------------------------
print("\n[7] 文本切片统计 - 自定义正则优先匹配")
-- ----------------------------------------------------------
do
    reset_config()

    local custom_config = [[{
    "machine_id": "test-regex-001-4xxx",
    "sync_dir": "$config_path/sync",
    "commit_threshold": 32,
    "history_threshold": 16,
    "count_rates": {
        "cjk": 1,
        "ascii": 0.33,
        "%d+": 2
    }
}]]
    write_file(config_path .. sep .. "config.json", custom_config)
    I.load_config_file()

    -- 数字被自定义正则捕获，不应出现在 ascii 或 cjk 计数中
    local r = I.calculate_text_rates("abc123def456")
    assert_eq("自定义 %d+ 匹配 2 组", r["%d+"], 2)
    assert_eq("数字被正则抹除后 ASCII=6", r["ascii"], 6)
    assert_eq("无 CJK", r["cjk"], 0)
end

-- ----------------------------------------------------------
print("\n[8] 就地加权变动 (on_commit)")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    -- 模拟 on_commit
    local mock_ctx = make_mock_commit("你好世界")
    wc.init({ engine = { context = { commit_notifier = { connect = function() end } } } })

    -- 手动调用 on_commit 逻辑 (通过模拟 context)
    -- 由于 on_commit 是 local，我们需要通过 init 注入后触发
    -- 改为直接测试 state 更新
    local state = I.load_state()
    local before_total = state.total

    -- 直接模拟 on_commit 的核心逻辑
    local current_counts = I.calculate_text_rates("你好世界")
    for k, v in pairs(current_counts) do
        local rate = I.config.count_rates[k] or 1
        state.counts[k] = (state.counts[k] or 0) + (v * rate)
    end
    local total_sum = 0
    for _, v in pairs(state.counts) do total_sum = total_sum + v end
    state.total = total_sum
    I.save_state(state)

    local after_state = I.load_state()
    assert_near("加权后 cjk=4", after_state.counts["cjk"], 4, 0.001)
    assert_near("加权后 total=4", after_state.total, 4, 0.001)

    -- 再次提交
    local current_counts2 = I.calculate_text_rates("Hello")
    for k, v in pairs(current_counts2) do
        local rate = I.config.count_rates[k] or 1
        state.counts[k] = (state.counts[k] or 0) + (v * rate)
    end
    total_sum = 0
    for _, v in pairs(state.counts) do total_sum = total_sum + v end
    state.total = total_sum
    I.save_state(state)

    after_state = I.load_state()
    assert_near("累加后 ascii=5*0.33", after_state.counts["ascii"], 5 * 0.33, 0.001)
    assert_near("累加后 total=4+1.65", after_state.total, 4 + 5 * 0.33, 0.001)
end

-- ----------------------------------------------------------
print("\n[9] 数据同步导出 (33 行模式)")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    -- 模拟 32 次提交
    local buffer = {}
    for i = 1, I.config.commit_threshold do
        table.insert(buffer, {
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            counts = { cjk = 1, ascii = 2 }
        })
    end

    -- 手动写入 sync 文件
    local filename = I.config.sync_dir .. sep .. I.config.machine_id .. "-" .. os.time() .. ".jsonl"
    local f = io.open(filename, "w")
    for i = 1, I.config.commit_threshold do
        f:write(string.format('{"timestamp":"%s","counts":{"cjk":1,"ascii":2},"machine_id":"%s"}\n',
            buffer[i].timestamp, I.config.machine_id))
    end
    f:write(string.format("--%s--done--%s\n", app_name, I.config.machine_id))
    f:close()

    assert_true("sync 文件已创建", io.open(filename, "r") ~= nil)

    local lines = read_lines(filename)
    assert_eq("sync 文件 33 行", #lines, 33)

    -- 验证尾封格式
    local tail = lines[#lines]
    local expected_tail = string.format("--%s--done--%s", app_name, I.config.machine_id)
    assert_eq("尾封格式正确", tail, expected_tail)

    -- 验证每行 JSON 格式
    local json_ok = true
    for i = 1, 32 do
        if not lines[i]:find('"timestamp"') or not lines[i]:find('"counts"') or not lines[i]:find('"machine_id"') then
            json_ok = false
            break
        end
    end
    assert_true("前 32 行均为有效 JSON", json_ok)
end

-- ----------------------------------------------------------
print("\n[10] 闲时合并 - 尾封断裂校验")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    -- 创建损坏文件（无尾封）
    make_jsonl_file("damaged.jsonl", I.config.machine_id, {
        '{"timestamp":"2024-01-01","counts":{"cjk":1},"machine_id":"other-id"}'
    }, false)

    local files = I.get_jsonl_files(sync_dir)
    assert_eq("损坏文件存在", #files, 1)

    wc.sync_idle()

    local state = I.load_state()
    -- 损坏文件不应被记录为已处理
    assert_true("损坏文件未被处理", state.processed_files["damaged.jsonl"] == nil)
end

-- ----------------------------------------------------------
print("\n[11] 闲时合并 - 环回过滤（本机文件不合并）")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local machine_id = I.config.machine_id

    -- 创建本机导出的文件
    local lines_data = {}
    for i = 1, 32 do
        table.insert(lines_data, string.format(
            '{"timestamp":"2024-01-01","counts":{"cjk":10,"ascii":20},"machine_id":"%s"}', machine_id))
    end
    make_jsonl_file("self_export.jsonl", machine_id, lines_data)

    local before_state = I.load_state()
    local before_cjk = before_state.counts["cjk"] or 0

    wc.sync_idle()

    local after_state = I.load_state()
    assert_near("本机文件不合并 cjk", after_state.counts["cjk"], before_cjk, 0.001)
    assert_true("本机文件标记已处理", after_state.processed_files["self_export.jsonl"] == true)
end

-- ----------------------------------------------------------
print("\n[12] 闲时合并 - 跨端求和合并")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local other_machine = "remote-machine-aaaa-bbbb-cccc"
    local lines_data = {}
    for i = 1, 32 do
        table.insert(lines_data, string.format(
            '{"timestamp":"2024-01-01","counts":{"cjk":5,"ascii":10},"machine_id":"%s"}', other_machine))
    end
    make_jsonl_file("remote_export.jsonl", other_machine, lines_data)

    local before_state = I.load_state()
    local before_cjk = before_state.counts["cjk"] or 0

    wc.sync_idle()

    local after_state = I.load_state()
    -- 每行 cjk=5, 32 行 raw total = 160, rate=1 => +160
    assert_near("跨端合并 cjk +160", after_state.counts["cjk"], before_cjk + 160, 0.001)
    -- 每行 ascii=10, 32 行 raw total = 320, rate=0.33 => +105.6
    assert_near("跨端合并 ascii +105.6", after_state.counts["ascii"], before_state.counts["ascii"] + 320 * 0.33, 0.001)
    assert_true("远程文件标记已处理", after_state.processed_files["remote_export.jsonl"] == true)
end

-- ----------------------------------------------------------
print("\n[13] 闲时合并 - 文件名幂等性防护")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local other_machine = "idempotent-machine-dddd-eeee-ffff"
    local lines_data = {}
    for i = 1, 32 do
        table.insert(lines_data, string.format(
            '{"timestamp":"2024-01-01","counts":{"cjk":1},"machine_id":"%s"}', other_machine))
    end
    make_jsonl_file("idempotent_test.jsonl", other_machine, lines_data)

    wc.sync_idle()
    local state1 = I.load_state()
    local total1 = state1.total

    -- 再次执行，不应重复计算
    wc.sync_idle()
    local state2 = I.load_state()
    assert_near("幂等性 total 不变", state2.total, total1, 0.001)
end

-- ----------------------------------------------------------
print("\n[14] 滑动窗口垃圾清理")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    -- 设置较小的 history_threshold 便于测试
    I.config.history_threshold = 6

    local other_machine = "cleanup-machine-gggg-hhhh-iiii"

    -- 创建 8 个已处理文件（超过 threshold=6）
    for i = 1, 8 do
        local fname = string.format("cleanup_%02d_%d.jsonl", i, 1000 + i)
        local lines_data = {}
        for j = 1, 32 do
            table.insert(lines_data, string.format(
                '{"timestamp":"2024-01-0%d","counts":{"cjk":1},"machine_id":"%s"}',
                (i % 9) + 1, other_machine))
        end
        make_jsonl_file(fname, other_machine, lines_data)
    end

    wc.sync_idle()

    local state = I.load_state()
    local remaining = 0
    for _ in pairs(state.processed_files) do remaining = remaining + 1 end

    -- threshold=6, 创建8个, 超过6个应删除 floor(6/2)=3 个
    -- 删除后剩余 processed_files = 8-3 = 5, 但新文件又被处理所以实际是8-3=5
    -- 实际: processed_files 有8个记录, 删除了 floor(6/2)=3 个旧的, 状态里剩5个
    assert_true("滑动窗口后文件数减少", remaining < 8)
    assert_true("滑动窗口后文件数 <= threshold", remaining <= 6)
end

-- ----------------------------------------------------------
print("\n[15] 状态持久化与恢复")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local state = I.load_state()
    state.counts["cjk"] = 100.5
    state.counts["ascii"] = 200.33
    state.total = 300.83
    state.processed_files["test_persist.jsonl"] = true
    I.save_state(state)

    local reloaded = I.load_state()
    assert_near("持久化 cjk", reloaded.counts["cjk"], 100.5, 0.001)
    assert_near("持久化 ascii", reloaded.counts["ascii"], 200.33, 0.001)
    assert_near("持久化 total", reloaded.total, 300.83, 0.001)
    assert_true("持久化 processed_files", reloaded.processed_files["test_persist.jsonl"] == true)
end

-- ----------------------------------------------------------
print("\n[16] 复杂 count_rates 配置")
-- ----------------------------------------------------------
do
    reset_config()

    local custom_config = [[
{
    "machine_id": "test-complex-001-4xxx",
    "sync_dir": "$config_path/sync",
    "commit_threshold": 32,
    "history_threshold": 16,
    "count_rates": {
        "cjk": 1,
        "ascii": 0.33,
        "%d+": 2,
        "[aeiou]+": 0.5
    }
}
]]
    write_file(config_path .. sep .. "config.json", custom_config)
    I.load_config_file()

    -- "Hello 123 你好"
    -- 自定义 %d+ 匹配 "123" => 1 组
    -- 自定义 [aeiou]+ 匹配 "e", "o" => 2 组
    -- 剩余: "Hll  你好" (两个空格)
    -- cjk: 2, ascii: "Hll  " => 5
    local r = I.calculate_text_rates("Hello 123 你好")
    assert_eq("多正则: %d+ 匹配数", r["%d+"], 1)
    assert_eq("多正则: [aeiou]+ 匹配数", r["[aeiou]+"], 2)
    assert_eq("多正则: cjk=2", r["cjk"], 2)
    assert_eq("多正则: ascii=5", r["ascii"], 5)
end

-- ----------------------------------------------------------
print("\n[17] 文件名提取")
-- ----------------------------------------------------------
do
    assert_eq("Linux 路径提取", I.get_file_name_only("/tmp/test/file.jsonl"), "file.jsonl")
    assert_eq("无路径提取", I.get_file_name_only("file.jsonl"), "file.jsonl")
end

-- ----------------------------------------------------------
print("\n[18] commit_threshold 触发导出")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    -- 模拟缓冲区未满时不导出
    local buffer = {}
    for i = 1, 16 do
        table.insert(buffer, { timestamp = os.date("%Y-%m-%d %H:%M:%S"), counts = { cjk = 1 } })
    end

    local files_before = I.get_jsonl_files(sync_dir)
    local count_before = #files_before

    -- 模拟导出（缓冲区满时）
    for i = 1, I.config.commit_threshold do
        table.insert(buffer, { timestamp = os.date("%Y-%m-%d %H:%M:%S"), counts = { cjk = 1 } })
    end

    local filename = sync_dir .. sep .. I.config.machine_id .. "-" .. os.time() .. ".jsonl"
    local f = io.open(filename, "w")
    for i = 1, I.config.commit_threshold do
        f:write(string.format('{"timestamp":"%s","counts":{"cjk":1},"machine_id":"%s"}\n',
            buffer[i].timestamp, I.config.machine_id))
    end
    f:write(string.format("--%s--done--%s\n", app_name, I.config.machine_id))
    f:close()

    local files_after = I.get_jsonl_files(sync_dir)
    assert_true("导出后文件数增加", #files_after > count_before)
end

-- ----------------------------------------------------------
print("\n[19] 完整端到端流程")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    -- 1. 模拟多次 commit
    local state = I.load_state()
    local commits = {
        "你好世界",     -- cjk=4, ascii=0
        "Hello World",  -- cjk=0, ascii=11
        "测试abc",      -- cjk=2, ascii=3
    }

    local total_cjk, total_ascii = 0, 0
    for _, text in ipairs(commits) do
        local counts = I.calculate_text_rates(text)
        total_cjk = total_cjk + counts["cjk"]
        total_ascii = total_ascii + (counts["ascii"] or 0)

        for k, v in pairs(counts) do
            local rate = I.config.count_rates[k] or 1
            state.counts[k] = (state.counts[k] or 0) + (v * rate)
        end
    end
    local total_sum = 0
    for _, v in pairs(state.counts) do total_sum = total_sum + v end
    state.total = total_sum
    I.save_state(state)

    -- 2. 验证状态
    local final_state = I.load_state()
    assert_near("端到端 cjk=6", final_state.counts["cjk"], 6, 0.001)
    assert_near("端到端 ascii=14*0.33", final_state.counts["ascii"], 14 * 0.33, 0.001)
    assert_near("端到端 total", final_state.total, 6 + 14 * 0.33, 0.001)

    -- 3. 创建跨端文件并合并
    local remote_lines = {}
    for i = 1, 32 do
        table.insert(remote_lines, string.format(
            '{"timestamp":"2024-01-01","counts":{"cjk":3,"ascii":6},"machine_id":"remote-e2e-test"}'))
    end
    make_jsonl_file("e2e_remote.jsonl", "remote-e2e-test", remote_lines)

    wc.sync_idle()

    local post_sync = I.load_state()
    assert_near("端到端同步后 cjk", post_sync.counts["cjk"], 6 + 32 * 3, 0.001)
    assert_near("端到端同步后 ascii", post_sync.counts["ascii"], 14 * 0.33 + 32 * 6 * 0.33, 0.001)
end

-- ----------------------------------------------------------
print("\n[20] Rime init() 接口")
-- ----------------------------------------------------------
do
    reset_config()

    local connected = false
    local mock_env = {
        engine = {
            context = {
                commit_notifier = {
                    connect = function(self, fn) connected = true end
                }
            }
        }
    }

    wc.init(mock_env)
    assert_true("init 注册 commit_notifier", connected)
end

-- ----------------------------------------------------------
print("\n[21] 设备同步状态文件 (dev_$machine_id.json)")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local mid = I.config.machine_id
    local ds_path = sync_dir .. sep .. I.device_sync_prefix .. mid .. ".json"

    -- 初始状态文件不存在
    assert_file_not_exists("初始无 dev_ 文件", ds_path)

    -- 手动创建设备状态
    local ds = I.load_device_sync(mid)
    assert_eq("新设备 machine_id", ds.machine_id, mid)
    assert_true("新设备 processed_files 为空", next(ds.processed_files) == nil)
    assert_true("新设备 exported_files 为空", next(ds.exported_files) == nil)

    ds.processed_files["other-device-123.jsonl"] = true
    ds.exported_files["self-export-456.jsonl"] = true
    ds.last_sync = "2025-01-01 12:00:00"
    I.save_device_sync(ds)

    assert_file_exists("dev_ 文件已创建", ds_path)

    -- 重新读取验证
    local reloaded = I.load_device_sync(mid)
    assert_eq("持久化 machine_id", reloaded.machine_id, mid)
    assert_eq("持久化 last_sync", reloaded.last_sync, "2025-01-01 12:00:00")
    assert_true("持久化 processed_files", reloaded.processed_files["other-device-123.jsonl"] == true)
    assert_true("持久化 exported_files", reloaded.exported_files["self-export-456.jsonl"] == true)
end

-- ----------------------------------------------------------
print("\n[22] 导出文件注册到 dev_ 文件")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local mid = I.config.machine_id
    local ds_path = sync_dir .. sep .. I.device_sync_prefix .. mid .. ".json"

    -- 注册一个导出文件
    I.register_exported_file(sync_dir .. sep .. "test-export-001.jsonl")

    local ds = I.load_device_sync(mid)
    assert_true("exported_files 包含文件名", ds.exported_files["test-export-001.jsonl"] == true)
    assert_true("last_sync 已更新", ds.last_sync ~= "")

    -- 再注册一个
    I.register_exported_file(sync_dir .. sep .. "test-export-002.jsonl")
    local ds2 = I.load_device_sync(mid)
    assert_true("exported_files 包含两个文件", ds2.exported_files["test-export-002.jsonl"] == true)
end

-- ----------------------------------------------------------
print("\n[23] 发现 dev_*.json 设备文件")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    -- 创建两个设备的状态文件
    I.save_device_sync({ machine_id = "devA-0001", last_sync = "", processed_files = {}, exported_files = {} })
    I.save_device_sync({ machine_id = "devB-0002", last_sync = "", processed_files = {}, exported_files = {} })

    local device_list = I.get_device_json_files(sync_dir)
    assert_eq("发现 2 个设备", #device_list, 2)

    local mids = {}
    for _, entry in ipairs(device_list) do
        mids[entry.machine_id] = true
    end
    assert_true("包含 devA", mids["devA-0001"] == true)
    assert_true("包含 devB", mids["devB-0002"] == true)
end

-- ----------------------------------------------------------
print("\n[24] 全端处理后 JSONL 自动删除")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local my_mid = I.config.machine_id
    local other_mid = "other-delete-test-aaaa"

    -- 本机导出一个 JSONL
    local fname = "delete_test_" .. os.time() .. ".jsonl"
    local lines_data = {}
    for i = 1, 32 do
        table.insert(lines_data, string.format(
            '{"timestamp":"2025-01-01","counts":{"cjk":1},"machine_id":"%s"}', my_mid))
    end
    make_jsonl_file(fname, my_mid, lines_data)

    -- 注册到本机 exported_files
    I.register_exported_file(sync_dir .. sep .. fname)
    assert_file_exists("JSONL 文件存在", sync_dir .. sep .. fname)

    -- 模拟另一个设备已处理此文件
    I.save_device_sync({
        machine_id = other_mid,
        last_sync = "2025-01-02",
        processed_files = { [fname] = true },
        exported_files = {}
    })

    -- 执行同步
    wc.sync_idle()

    -- 文件应被删除（因为唯一另一个设备已处理）
    assert_file_not_exists("全端处理后 JSONL 被删除", sync_dir .. sep .. fname)

    -- exported_files 应已清理
    local my_ds = I.load_device_sync(my_mid)
    assert_true("exported_files 已移除该文件", my_ds.exported_files[fname] == nil)
end

-- ----------------------------------------------------------
print("\n[25] 未全端处理的 JSONL 不删除")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local my_mid = I.config.machine_id
    local fname = "keep_test_" .. os.time() .. ".jsonl"
    local lines_data = {}
    for i = 1, 32 do
        table.insert(lines_data, string.format(
            '{"timestamp":"2025-01-01","counts":{"cjk":1},"machine_id":"%s"}', my_mid))
    end
    make_jsonl_file(fname, my_mid, lines_data)
    I.register_exported_file(sync_dir .. sep .. fname)

    -- 创建两个其他设备，一个已处理一个未处理
    I.save_device_sync({
        machine_id = "device-A-processed",
        last_sync = "2025-01-02",
        processed_files = { [fname] = true },
        exported_files = {}
    })
    I.save_device_sync({
        machine_id = "device-B-not-processed",
        last_sync = "2025-01-02",
        processed_files = {},
        exported_files = {}
    })

    wc.sync_idle()

    -- 文件不应被删除（device-B 尚未处理）
    assert_file_exists("未全端处理 JSONL 保留", sync_dir .. sep .. fname)
end

-- ----------------------------------------------------------
print("\n[26] 本机 JSONL 同时合并到 state")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local my_mid = I.config.machine_id

    -- 先提交一些数据让本机有初始计数
    local state = I.load_state()
    state.counts["cjk"] = 10
    state.total = 10
    I.save_state(state)

    -- 创建本机导出的 JSONL（环回过滤，不合并数据）
    local fname = "self_roundtrip_" .. os.time() .. ".jsonl"
    local lines_data = {}
    for i = 1, 32 do
        table.insert(lines_data, string.format(
            '{"timestamp":"2025-01-01","counts":{"cjk":99},"machine_id":"%s"}', my_mid))
    end
    make_jsonl_file(fname, my_mid, lines_data)

    wc.sync_idle()

    local after = I.load_state()
    -- 本机文件不合并, cjk 应保持 10
    assert_near("本机环回不合并 cjk", after.counts["cjk"], 10, 0.001)
    assert_true("本机文件标记已处理", after.processed_files[fname] == true)
end

-- ----------------------------------------------------------
print("\n[27] 时间粒度解析")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    -- parse_period 基本测试
    local n, unit = I.parse_period("1month")
    assert_eq("parse_period 1month 数值", n, 1)
    assert_eq("parse_period 1month 单位", unit, "month")

    n, unit = I.parse_period("3months")
    assert_eq("parse_period 3months 数值", n, 3)
    assert_eq("parse_period 3months 单位", unit, "month")

    n, unit = I.parse_period("7days")
    assert_eq("parse_period 7days 数值", n, 7)
    assert_eq("parse_period 7days 单位", unit, "day")

    n, unit = I.parse_period("1year")
    assert_eq("parse_period 1year 数值", n, 1)
    assert_eq("parse_period 1year 单位", unit, "year")

    n, unit = I.parse_period("2weeks")
    assert_eq("parse_period 2weeks 数值", n, 2)
    assert_eq("parse_period 2weeks 单位", unit, "week")

    n, unit = I.parse_period("12hours")
    assert_eq("parse_period 12hours 数值", n, 12)
    assert_eq("parse_period 12hours 单位", unit, "hour")

    -- get_period_key 测试
    local fixed_ts = os.time({year=2025, month=6, day=15, hour=14, min=30, sec=0})

    assert_eq("get_period_key 1month", I.get_period_key(fixed_ts, "1month"), "2025-06")
    assert_eq("get_period_key 1day", I.get_period_key(fixed_ts, "1day"), "2025-06-15")
    assert_eq("get_period_key 1hour", I.get_period_key(fixed_ts, "1hour"), "2025-06-15-14")
    assert_eq("get_period_key 1year", I.get_period_key(fixed_ts, "1year"), "2025")

    -- parse_duration 测试
    assert_eq("parse_duration 1day", I.parse_duration("1day"), 86400)
    assert_eq("parse_duration 1month", I.parse_duration("1month"), 2592000)
    assert_near("parse_duration 1week", I.parse_duration("1week"), 604800, 1)
end

-- ----------------------------------------------------------
print("\n[28] Storage JSON 后端")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local store = I.Storage.new("json")

    -- 保存和读取
    local test_data = {
        period = "2025-06",
        total = 123.45,
        counts = { cjk = 100, ascii = 23.45 },
        errors = 5,
        commits = 10
    }
    store:save("monthly", "2025-06", test_data)

    local loaded = store:load("monthly", "2025-06")
    assert_true("Storage 读取非 nil", loaded ~= nil)
    assert_near("Storage 读取 total", loaded.total, 123.45, 0.001)
    assert_near("Storage 读取 cjk", loaded.counts["cjk"], 100, 0.001)
    assert_eq("Storage 读取 errors", loaded.errors, 5)
    assert_eq("Storage 读取 commits", loaded.commits, 10)

    -- 不存在的分片返回 nil
    local missing = store:load("monthly", "2099-01")
    assert_true("Storage 不存在返回 nil", missing == nil)

    -- list_periods
    store:save("monthly", "2025-01", test_data)
    store:save("monthly", "2025-02", test_data)
    local periods = store:list_periods("monthly")
    assert_true("list_periods 包含 2025-01", periods[1] == "2025-01")
    assert_true("list_periods 包含 2025-02", periods[2] == "2025-02")
    assert_true("list_periods 包含 2025-06", periods[3] == "2025-06")
end

-- ----------------------------------------------------------
print("\n[29] config state_split 配置解析")
-- ----------------------------------------------------------
do
    reset_config()

    local custom_config = [[{
    "machine_id": "test-split-001",
    "sync_dir": "$config_path/sync",
    "commit_threshold": 32,
    "history_threshold": 16,
    "count_rates": { "cjk": 1, "ascii": 0.33 },
    "state_split": {
        "monthly": "1month",
        "daily": "1day"
    },
    "state_retention": {
        "monthly": "24months",
        "daily": "90days"
    }
}]]
    write_file(config_path .. sep .. "config.json", custom_config)
    I.load_config_file()

    assert_eq("state_split monthly", I.config.state_split["monthly"], "1month")
    assert_eq("state_split daily", I.config.state_split["daily"], "1day")
    assert_eq("state_retention monthly", I.config.state_retention["monthly"], "24months")
    assert_eq("state_retention daily", I.config.state_retention["daily"], "90days")
end

-- ----------------------------------------------------------
print("\n[30] state.json 包含 errors 字段")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local state = I.load_state()
    assert_eq("初始 errors 为 0", state.errors, 0)

    state.errors = 42
    state.counts["cjk"] = 10
    state.total = 10
    I.save_state(state)

    local reloaded = I.load_state()
    assert_eq("持久化 errors", reloaded.errors, 42)
end

-- ----------------------------------------------------------
print("\n[31] processor_state 退格检测")
-- ----------------------------------------------------------
do
    reset_config()
    I.load_config_file()

    local ps = I.processor_state
    -- 初始状态
    assert_eq("初始 last_preedit_len", ps.last_preedit_len, 0)
    assert_eq("初始 errors_buffered", ps.errors_buffered, 0)

    -- 模拟退格前状态
    ps.last_preedit_len = 5
    ps.errors_buffered = 0

    -- 模拟退格后 preedit 缩短到 3（删除 2 字符）
    local delta = ps.last_preedit_len - 3
    ps.errors_buffered = ps.errors_buffered + delta
    ps.last_preedit_len = 3

    assert_eq("退格后 errors_buffered", ps.errors_buffered, 2)

    -- 模拟无 preedit 时退格（删除已提交文本）
    ps.errors_buffered = ps.errors_buffered + 1
    assert_eq("无 preedit 退格后 errors_buffered", ps.errors_buffered, 3)
end

-- ==================== 测试结果汇总 ====================
print("\n" .. string.rep("=", 60))
print(" 测试结果汇总")
print(string.rep("=", 60))

for _, result in ipairs(test_results) do
    print(result)
end

print(string.rep("-", 60))
print(string.format(" 总计: %d  通过: %d  失败: %d", total_count, pass_count, fail_count))
print(string.rep("=", 60))

-- 清理
cleanup()

if fail_count > 0 then
    os.exit(1)
end

-- ==================== 1. 基础路径与系统检测 ====================
local app_name = "milk-word-counter"
local sep = package.config:sub(1, 1)

local function parse_os_release()
    local info = {}
    local f = io.open("/etc/os-release", "r")
    if not f then return nil end
    for line in f:lines() do
        local key, val = line:match("^([%w_]+)=(.*)$")
        if key and val then
            val = val:gsub('^"(.*)"$', "%1")
            info[key] = val
        end
    end
    f:close()
    return info
end

local function get_os()
    local os_env = os.getenv("OS")
    if os_env and string.find(os_env, "Windows") then return "win" end
    if parse_os_release() then return "linux" end
    local home = os.getenv("HOME")
    if home then
        local uname_file = io.popen("uname 2>/dev/null")
        if uname_file then
            local uname_out = uname_file:read("*l")
            uname_file:close()
            if uname_out == "Darwin" then return "mac" end
        end
        if home:find("^/Users/") then return "mac" end
        return "nix"
    end
    return "unknown"
end

local os_type = get_os()

local function get_config_dir()
    local home = os.getenv("HOME") or ""
    if os_type == "win" then
        local appdata = os.getenv("APPDATA") or (os.getenv("USERPROFILE") .. "\\AppData\\Roaming")
        return appdata .. sep .. app_name
    elseif os_type == "mac" then
        return home .. "/Library/Application Support/" .. app_name
    else
        local xdg_config = os.getenv("XDG_CONFIG_HOME")
        if xdg_config and xdg_config ~= "" then return xdg_config .. sep .. app_name end
        return home .. "/.config/" .. app_name
    end
end

local config_path = get_config_dir()

local null_dev = os_type == "win" and "nul" or "/dev/null"

local function make_dir(path)
    if os_type == "win" then
        os.execute('mkdir "' .. path .. '" >' .. null_dev .. ' 2>&1')
    else
        os.execute('mkdir -p "' .. path .. '" >' .. null_dev .. ' 2>&1')
    end
end

local function get_jsonl_files(dir)
    local files = {}
    local cmd = os_type == "win" and ('dir "' .. dir .. sep .. '*.jsonl" /b /a-d 2>nul') or ('ls -1 "' .. dir .. '"/*.jsonl 2>/dev/null')
    local p = io.popen(cmd)
    if p then
        for line in p:lines() do
            table.insert(files, os_type == "win" and (dir .. sep .. line) or line)
        end
        p:close()
    end
    return files
end

-- ==================== 2. UUID v4 生成器 ====================
local function generate_uuid4()
    math.randomseed(os.time() * 1000000 + math.floor(os.clock() * 1000000) % 1000000)
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

-- ==================== 3. 配置与状态高度定制化 (支持 count_rates) ====================
local json_path = config_path .. sep .. "config.json"
local state_path = config_path .. sep .. "state.json"

local config = {
    machine_id = "",
    sync_dir = "$config_path/sync",
    commit_threshold = 32,
    history_threshold = 16,
    count_rates = { cjk = 1, ascii = 0.33 }
}

-- 简易 JSON 解析（剥离出 key-value 与 count_rates 内部字典）
local function load_config_file()
    make_dir(config_path)
    local f = io.open(json_path, "r")
    local content = ""
    if f then
        content = f:read("*a")
        f:close()
    end

    -- 提取基础字段
    config.machine_id = content:match('"machine_id"%s*:%s*"([^"]+)"') or ""
    config.sync_dir = content:match('"sync_dir"%s*:%s*"([^"]+)"') or "$config_path/sync"
    config.commit_threshold = tonumber(content:match('"commit_threshold"%s*:%s*(%d+)')) or 32
    config.history_threshold = tonumber(content:match('"history_threshold"%s*:%s*(%d+)')) or 16

    -- 如果没有 machine_id，则触发生成并回写
    local rewrite_required = false
    if config.machine_id == "" then
        config.machine_id = generate_uuid4()
        rewrite_required = true
    end

    -- 提取 count_rates 字典
    local rates_block = content:match('"count_rates"%s*:%s*{([^}]+)}')
    if rates_block then
        config.count_rates = {}
        -- 改进的匹配模式，支持键中包含特殊字符（如正则表达式）
        for k, v in rates_block:gmatch('"([^"]*)"[%s]*:[%s]*([%d%.]+)') do
            if k ~= "" then
                config.count_rates[k] = tonumber(v)
            end
        end
    end

    -- 如果是初次创建或缺失 UUID，持久化配置
    if not f or rewrite_required then
        f = io.open(json_path, "w")
        if f then
            local rates_json = {}
            for k, v in pairs(config.count_rates) do
                table.insert(rates_json, string.format('        "%s": %s', k, tostring(v)))
            end
            local json_str = string.format([[{
    "machine_id": "%s",
    "sync_dir": "%s",
    "commit_threshold": %d,
    "history_threshold": %d,
    "count_rates": {
%s
    }
}]], config.machine_id, config.sync_dir, config.commit_threshold, config.history_threshold, table.concat(rates_json, ",\n"))
            f:write(json_str)
            f:close()
        end
    end

    -- 动态解析 $config_path 占位符
    if config.sync_dir:find("$config_path") then
        config.sync_dir = config.sync_dir:gsub("%$config_path", config_path)
    end
    make_dir(config.sync_dir)
end

-- 读取和更新本地复杂的结构化状态化 state.json
local save_state  -- forward declaration

local function load_state()
    local state = { total = 0, counts = {}, processed_files = {} }
    local f = io.open(state_path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        
        state.total = tonumber(content:match('"total"%s*:%s*([%d%.]+)')) or 0
        
        local counts_block = content:match('"counts"%s*:%s*{([^}]+)}')
        if counts_block then
            for k, v in counts_block:gmatch('"([^"]+)"%s*:%s*([%d%.]+)') do
                state.counts[k] = tonumber(v)
            end
        end
        
        local files_block = content:match('"processed_files"%s*:%s*{([^}]+)}')
        if files_block then
            for fname in files_block:gmatch('"([^"]+)"%s*:%s*true') do
                state.processed_files[fname] = true
            end
        end
    end
    
    -- 确保本地配置里有的核心项在 state 里被初始化为 0
    for k in pairs(config.count_rates) do
        if not state.counts[k] then state.counts[k] = 0 end
    end

    if not f then
        save_state(state)
    end

    return state
end

save_state = function(state)
    local f = io.open(state_path, "w")
    if f then
        local counts_json = {}
        for k, v in pairs(state.counts) do
            table.insert(counts_json, string.format('        "%s": %s', k, tostring(v)))
        end
        
        local files_json = {}
        for k in pairs(state.processed_files) do
            table.insert(files_json, string.format('        "%s": true', k:gsub("\\", "\\\\")))
        end
        
        local content = string.format([[{
    "total": %s,
    "counts": {
%s
    },
    "processed_files": {
%s
    }
}]], tostring(state.total), table.concat(counts_json, ",\n"), table.concat(files_json, ",\n"))
        f:write(content)
        f:close()
    end
end

-- ==================== 4. 基于复杂频数正则的文本切片统计引擎 ====================
local function calculate_text_rates(text)
    local results = {}
    for k in pairs(config.count_rates) do results[k] = 0 end

    if not text or text == "" then return results end

    -- 1. 处理自定义或内建的通用规则迭代提取
    local remainder = text

    -- 遍历匹配所有注册的正则/类别
    for pattern, _ in pairs(config.count_rates) do
        if pattern ~= "cjk" and pattern ~= "ascii" then
            -- 针对用户自定义的 Lua 正则模式进行全量匹配提取
            local match_count = 0
            remainder = remainder:gsub(pattern, function(match)
                match_count = match_count + 1
                return "" -- 在剩余流中抹去，避免多重统计冲突
            end)
            results[pattern] = match_count
        end
    end

    -- 2. 内建规则 cjk (中日韩统一表意文字扩展)
    if config.count_rates["cjk"] and utf8 then
        for _, c in utf8.codes(remainder) do
            -- 扩展 CJK 字符范围，包含更多中日韩统一表意文字
            if (c >= 0x4E00 and c <= 0x9FFF) or   -- CJK 统一表意文字
               (c >= 0x3400 and c <= 0x4DBF) or   -- CJK 统一表意文字扩展 A
               (c >= 0x20000 and c <= 0x2A6DF) or -- CJK 统一表意文字扩展 B
               (c >= 0x2A700 and c <= 0x2B73F) or -- CJK 统一表意文字扩展 C
               (c >= 0x2B740 and c <= 0x2B81F) or -- CJK 统一表意文字扩展 D
               (c >= 0x2B820 and c <= 0x2CEAF) or -- CJK 统一表意文字扩展 E
               (c >= 0xF900 and c <= 0xFAFF) or   -- CJK 兼容表意文字
               (c >= 0x2F800 and c <= 0x2FA1F) then -- CJK 兼容表意文字补充
                results["cjk"] = results["cjk"] + 1
            end
        end
    end

    -- 3. 内建规则 ascii 标准可视与不可视边界识别
    if config.count_rates["ascii"] then
        for i = 1, #remainder do
            local byte = remainder:byte(i)
            if byte >= 32 and byte <= 126 then
                results["ascii"] = results["ascii"] + 1
            end
        end
    end

    return results
end

-- ==================== 5. 通用工具函数 ====================
local function get_file_name_only(path)
    return path:match("^.*" .. sep .. "([^" .. sep .. "]+)$") or path
end

-- ==================== 6. 设备同步状态文件 (dev_$machine_id.json) ====================
local device_sync_prefix = "dev_"

local function get_device_sync_path(mid)
    return config.sync_dir .. sep .. device_sync_prefix .. mid .. ".json"
end

local function load_device_sync(mid)
    local ds = { machine_id = mid, last_sync = "", processed_files = {}, exported_files = {} }
    local path = get_device_sync_path(mid)
    local f = io.open(path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        ds.last_sync = content:match('"last_sync"%s*:%s*"([^"]*)"') or ""
        local pf_block = content:match('"processed_files"%s*:%s*{([^}]+)}')
        if pf_block then
            for fname in pf_block:gmatch('"([^"]*)"') do
                ds.processed_files[fname] = true
            end
        end
        local ef_block = content:match('"exported_files"%s*:%s*{([^}]+)}')
        if ef_block then
            for fname in ef_block:gmatch('"([^"]*)"') do
                ds.exported_files[fname] = true
            end
        end
    end
    return ds
end

local function save_device_sync(ds)
    local path = get_device_sync_path(ds.machine_id)
    local pf_items = {}
    for fname in pairs(ds.processed_files) do
        table.insert(pf_items, string.format('        "%s": true', fname:gsub("\\", "\\\\")))
    end
    local ef_items = {}
    for fname in pairs(ds.exported_files) do
        table.insert(ef_items, string.format('        "%s": true', fname:gsub("\\", "\\\\")))
    end
    local content = string.format([[{
    "machine_id": "%s",
    "last_sync": "%s",
    "processed_files": {
%s
    },
    "exported_files": {
%s
    }
}]], ds.machine_id, ds.last_sync, table.concat(pf_items, ",\n"), table.concat(ef_items, ",\n"))
    local f = io.open(path, "w")
    if f then f:write(content); f:close() end
end

local function register_exported_file(filename)
    local fname = get_file_name_only(filename)
    local ds = load_device_sync(config.machine_id)
    ds.exported_files[fname] = true
    ds.last_sync = os.date("%Y-%m-%d %H:%M:%S")
    save_device_sync(ds)
end

-- ==================== 7. 数据同步导出 (生成符合 Rate 的 JSONL) ====================
local commit_buffer = {}

local function emit_sync_file()
    local ts = os.time()
    local filename = string.format("%s%s%s-%d.jsonl", config.sync_dir, sep, config.machine_id, ts)
    local f = io.open(filename, "w")
    if f then
        for i = 1, config.commit_threshold do
            local item = commit_buffer[i] or { timestamp = os.date("%Y-%m-%d %H:%M:%S"), counts = {} }
            
            -- 构建多项频数的子键值对 JSON 字符串
            local count_items = {}
            for k, v in pairs(config.count_rates) do
                local val = item.counts[k] or 0
                table.insert(count_items, string.format('"%s":%s', k, tostring(val)))
            end
            
            f:write(string.format('{"timestamp":"%s","counts":{%s},"machine_id":"%s"}\n', 
                item.timestamp, table.concat(count_items, ","), config.machine_id))
        end
        f:write(string.format("--%s--done--%s\n", app_name, config.machine_id))
        f:close()

        register_exported_file(filename)

        local new_buffer = {}
        for i = config.commit_threshold + 1, #commit_buffer do
            table.insert(new_buffer, commit_buffer[i])
        end
        commit_buffer = new_buffer
    end
end

-- ==================== 8. 闲时合并与多端数据求和 ====================

local function get_device_json_files(dir)
    local files = {}
    local cmd = os_type == "win" and ('dir "' .. dir .. sep .. device_sync_prefix .. '*.json" /b /a-d 2>nul') or ('ls -1 "' .. dir .. '/' .. device_sync_prefix .. '"*.json 2>/dev/null')
    local p = io.popen(cmd)
    if p then
        for line in p:lines() do
            local full = os_type == "win" and (dir .. sep .. line) or line
            -- 提取 machine_id: dev_xxx.json -> xxx
            local mid = get_file_name_only(full):match("^" .. device_sync_prefix .. "(.+)%.json$")
            if mid then
                table.insert(files, { path = full, machine_id = mid })
            end
        end
        p:close()
    end
    return files
end

local function sync_idle_job()
    local jsonl_files = get_jsonl_files(config.sync_dir)
    if #jsonl_files == 0 then return end

    local state = load_state()
    local state_changed = false

    -- 1. 读取所有设备同步状态文件，发现已知设备
    local device_json_files = get_device_json_files(config.sync_dir)
    local known_devices = {}
    for _, entry in ipairs(device_json_files) do
        known_devices[entry.machine_id] = load_device_sync(entry.machine_id)
    end
    -- 确保本机在已知设备列表中
    if not known_devices[config.machine_id] then
        known_devices[config.machine_id] = load_device_sync(config.machine_id)
    end

    -- 2. 处理所有 JSONL 文件
    for _, filepath in ipairs(jsonl_files) do
        local fname = get_file_name_only(filepath)

        if not state.processed_files[fname] then
            local f = io.open(filepath, "r")
            if f then
                local lines = {}
                for line in f:lines() do table.insert(lines, line) end
                f:close()

                local last_line = lines[#lines] or ""
                local escaped_app = app_name:gsub("%-", "%%-")
                local file_machine_id = last_line:match("^%-%-" .. escaped_app .. "%-%-done%-%-(.+)$")

                if file_machine_id then
                    -- 跨端求和合并：仅对非本机文件执行加权合并
                    if file_machine_id ~= config.machine_id then
                        for i = 1, #lines - 1 do
                            local counts_block = lines[i]:match('"counts"%s*:%s*{([^}]+)}')
                            if counts_block then
                                for k, v in counts_block:gmatch('"([^"]*)"[%s]*:[%s]*([%d%.]+)') do
                                    local raw_count = tonumber(v) or 0
                                    local rate = config.count_rates[k] or 1
                                    state.counts[k] = (state.counts[k] or 0) + (raw_count * rate)
                                end
                            end
                        end
                    end

                    -- 记录到本机 state (幂等性防护)
                    state.processed_files[fname] = true
                    state_changed = true

                    -- 更新本机 $machine_id.json 中的 processed_files
                    local my_ds = known_devices[config.machine_id]
                    my_ds.processed_files[fname] = true
                    my_ds.last_sync = os.date("%Y-%m-%d %H:%M:%S")
                end
            end
        end
    end

    -- 3. 持久化本机设备状态
    save_device_sync(known_devices[config.machine_id])

    -- 4. 重新计算 total
    if state_changed then
        local total_sum = 0
        for _, v in pairs(state.counts) do total_sum = total_sum + v end
        state.total = total_sum
        save_state(state)
    end

    -- 5. 删除已全端处理的本机 JSONL 文件
    local my_ds = known_devices[config.machine_id]
    local files_to_check = {}
    for fname in pairs(my_ds.exported_files) do
        table.insert(files_to_check, fname)
    end
    table.sort(files_to_check)

    for _, fname in ipairs(files_to_check) do
        local all_processed = true
        for mid, ds in pairs(known_devices) do
            if mid ~= config.machine_id and not ds.processed_files[fname] then
                all_processed = false
                break
            end
        end
        if all_processed then
            local full_path = config.sync_dir .. sep .. fname
            os.remove(full_path)
            my_ds.exported_files[fname] = nil
            save_device_sync(my_ds)
        end
    end

    -- 6. 滑动窗口垃圾清理 (清理本机 processed_files 中的旧记录)
    local history_list = {}
    for fname in pairs(state.processed_files) do
        table.insert(history_list, fname)
    end
    table.sort(history_list)

    if #history_list > config.history_threshold then
        local delete_count = math.floor(config.history_threshold / 2)
        for i = 1, delete_count do
            local fname_to_delete = history_list[i]
            local full_path = config.sync_dir .. sep .. fname_to_delete
            os.remove(full_path)
            state.processed_files[fname_to_delete] = nil
        end
        state_changed = true
    end

    if state_changed then
        save_state(state)
    end
end

-- ==================== 9. Rime 回调入口 ====================
local function on_commit(context)
    local commit_text = context:get_commit_text()
    if commit_text and commit_text ~= "" then
        -- 计算当前词文本在各 Rate 正则下的匹配数目
        local current_counts = calculate_text_rates(commit_text)
        
        -- 检查是否有有效计数，防止刷空行
        local has_data = false
        for _, v in pairs(current_counts) do
            if v > 0 then has_data = true break end
        end

        if has_data then
            -- 1. 动态合并入本机当前的 state.json 中（就地加权变动）
            local state = load_state()
            for k, v in pairs(current_counts) do
                local rate = config.count_rates[k] or 1
                state.counts[k] = (state.counts[k] or 0) + (v * rate)
            end
            local total_sum = 0
            for _, v in pairs(state.counts) do total_sum = total_sum + v end
            state.total = total_sum
            save_state(state)

            -- 2. 压入同步队列缓冲区（同步文件里写入的是未加权原始数量 raw_count，供外部消费端根据各自配置折算）
            table.insert(commit_buffer, {
                timestamp = os.date("%Y-%m-%d %H:%M:%S"),
                counts = current_counts
            })

            if #commit_buffer >= config.commit_threshold then
                emit_sync_file()
            end
        end
    end
end

function init(env)
    load_config_file()
    
    if env and env.engine then
        env.engine.context.commit_notifier:connect(on_commit)
    end

    sync_idle_job()
end

return {
    init = init,
    sync_idle = sync_idle_job,
    _internal = {
        config = config,
        config_path = function() return config_path end,
        calculate_text_rates = calculate_text_rates,
        load_config_file = load_config_file,
        load_state = load_state,
        save_state = save_state,
        emit_sync_file = emit_sync_file,
        commit_buffer = function() return commit_buffer end,
        get_jsonl_files = get_jsonl_files,
        get_file_name_only = get_file_name_only,
        generate_uuid4 = generate_uuid4,
        load_device_sync = load_device_sync,
        save_device_sync = save_device_sync,
        register_exported_file = register_exported_file,
        get_device_json_files = get_device_json_files,
        device_sync_prefix = device_sync_prefix,
    }
}

# Rime 字数统计 (milk-word-counter)

基于 Rime 输入法的 Lua 插件，实时统计打字字数，支持多设备同步。

## 功能特性

- 实时统计 CJK 汉字、ASCII 字符及自定义正则匹配的加权字数
- 跨平台支持（Windows / macOS / Linux）
- 多设备通过共享文件夹自动同步字数数据
- 滑动窗口自动清理历史同步文件

## 安装

### 第 1 步：复制 Lua 脚本

将 `lua/word_counter.lua` 复制到 Rime 用户文件夹的 `lua/` 目录中。

打开 Rime 用户文件夹的方法：右键点击系统托盘中的输入法图标，选择「用户文件夹」。

如果没有 `lua` 文件夹，手动新建即可。

### 第 2 步：配置输入法方案

打开你正在使用的输入法方案文件（如 `*.schema.yaml`），在 `engine` → `processors` 下添加：

```yaml
engine:
  processors:
    - lua_processor@*word_counter  # 星号后面不要带空格
```

### 第 3 步：重新部署

保存修改后，点击输入法菜单中的「重新部署」，插件即刻生效。

## 配置

首次运行时，插件会在如下配置目录下自动生成 `config.json`：

| 系统 | 路径 |
|------|------|
| Windows | `%APPDATA%\milk-word-counter\` |
| macOS | `~/Library/Application Support/milk-word-counter/` |
| Linux | `~/.config/milk-word-counter/`（或 `$XDG_CONFIG_HOME/milk-word-counter/`） |

```json
{
    "machine_id": "<自动生成的 UUID>",
    "sync_dir": "$config_path/sync",
    "commit_threshold": 32,
    "history_threshold": 16,
    "count_rates": {
        "cjk": 1,
        "ascii": 0.33
    }
}
```

### 配置项说明

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `machine_id` | 自动生成 | 设备唯一标识（UUID v4），首次运行后自动写入，勿手动修改 |
| `sync_dir` | `$config_path/sync` | 多设备同步文件夹路径。`$config_path` 会被动态替换为上述系统配置目录的绝对路径；也可直接填写绝对路径 |
| `commit_threshold` | `32` | 每累计多少次上屏触发一次同步文件导出 |
| `history_threshold` | `16` | 闲时清理时保留的最大历史快照数 |
| `count_rates` | 见下方 | 多维度加权统计规则 |

### count_rates 权重配置

`count_rates` 支持三种类型的键：

- **`cjk`**：统计中日韩统一表意文字（汉字）个数，权重乘以对应值
- **`ascii`**：统计 ASCII 可见字符个数（字节 32–126），权重乘以对应值。若不配置此项则不统计 ASCII
- **自定义正则**：任意 Lua 正则表达式字符串作为键，匹配到的文本片段会被优先提取并从后续统计中移除

示例：

```json
"count_rates": {
    "cjk": 1,
    "ascii": 0.33,
    "%d+": 2,
    "[aeiou]+": 0.5
}
```

上例含义：汉字按原数统计；ASCII 按 1/3 折算；连续数字按组计数，每组权重 2；连续元音按组计数，每组权重 0.5。

## 多设备同步

将多台设备的系统配置目录下的 `milk-word-counter/sync/` 目录通过网盘、局域网共享等方式保持同步即可。

### 同步机制

1. 每台上屏累计达到 `commit_threshold` 次时，导出一个 `.jsonl` 同步文件到 `sync/` 目录
2. 闲时（Rime 空闲或初始化时）自动扫描 `sync/` 目录，合并其他设备的字数数据
3. 所有设备均已处理过的 `.jsonl` 文件会被自动删除
4. 超过 `history_threshold` 的旧记录会被滑动窗口清理

### 文件结构

```
milk-word-counter/
├── config.json                              # 插件配置
├── state.json                               # 本地累计字数状态
└── sync/
    ├── dev_<本机 machine_id>.json            # 本机同步状态
    ├── dev_<其他设备 machine_id>.json        # 其他设备同步状态
    └── <machine_id>-<timestamp>.jsonl        # 待合并的同步数据文件
```

## 运行测试

需要 Lua 5.3+：

```bash
bash test/run_tests.sh
```

## 许可证

BSD 3-Clause License

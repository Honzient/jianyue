# 交接与验收

接手后先从 [README](../README.md) 构建一次调试 HAP，再按本文验收书架、阅读器和书源页。代码入口和存储结构可从[应用架构](ARCHITECTURE.md)定位。

## 项目基线

| 项目 | 当前配置 |
| --- | --- |
| 应用与本地版本 | 简阅 0.5.0，`versionCode` 500 |
| 包名 | `dev.yuejian.reader`，沿用首版身份以支持覆盖升级 |
| 应用模型 | HarmonyOS Stage，`entry` 模块和 `EntryAbility` |
| SDK | 编译和目标版本 26.0.0，最低兼容 5.0.5(17) |
| 源码 | WSL2 项目根目录下的 `entry/src/main/ets`，应用代码使用 ArkTS `.ets` |
| 本地数据 | `yuejian.db`，数据库版本 3，小说原文和网络正文存于应用沙箱 |
| 书源格式 | [Legado 3.0 BookSource JSON Schema](../schemas/legado-3.0-book-source.schema.json) |
| 本轮范围 | 本地阅读与按需书源；不加入云端同步、账号和新阅读格式 |

当前工作站的仓库位于 WSL2 的 `~/projects/jianyue`。交接到不同机器时，以接收方的克隆目录为准。用 `git status --short --branch` 核对工作树，再通过[开发与调试](DEVELOPMENT.md)检查工具链和调试设备。

## 验收顺序

| 流程 | 操作与预期 |
| --- | --- |
| 构建和启动 | 在 WSL2 构建 `entry`，向明确选中的模拟器安装 HAP，启动后显示简阅书架。 |
| 本地优先与按需书源 | 冷启动只读取本地书架，不等待书源。首次进入「搜书」或「书源」显示「正在加载书源」，完成后显示内容。重复切换不重复读取；导入、启停或刷新书源后列表更新，旧请求结果不会覆盖新结果。 |
| 书架查找 | 书架有书时点「查找」，输入书名片段过滤；「清除」恢复全部；无匹配显示空结果；「继续阅读」和「整理」仍可用。 |
| TXT 和续读 | 导入带章节的 TXT，验证目录和上下章。滚到有辨识度的段落后调整字号、重启，再点继续阅读，核对回到该段。 |
| 目录筛选 | 阅读器点「目录」，输入标题片段或纯数字章序筛选。保留原章序和虚拟列表滚动；清除后恢复全部，无匹配显示提示。目录打开、筛选、清除和关闭不改变继续阅读位置。 |
| 详情直接进目录 | 在有阅读进度的书上，从详情点「查看目录」。目录定位到保存章节并显示「上次读到」，正文尚未加载且进度不变；点保存章节从保存偏移继续，点其他章节从章首开始。 |
| 阅读位置恢复 | 滚到有辨识度的段落后调整字号、行距、日夜并开关面板，再退出阅读器并重启应用；点「继续阅读」应回到同一章和接近原段落。 |
| 批量导入 | 导入下方生成的 348 条 JSON。首次应新增 348 条，重复导入应更新 348 条，格式错误为 0 条。 |
| 查找与筛选 | 在书源页输入名称、分组或网址关键字，核对结果数量。切到待检查应显示样本，切到可搜索时，应只显示有兼容搜索规则的条目。 |
| 规则与缓存 | 用自建或已获授权的测试源依次运行四阶段测试。打开并缓存一章，再断开测试站，核对已读章节可离线打开。 |
| 书源诊断与日志 | 先检查一条缺规则的来源，再联网测试正常来源和返回 HTTP 503 的来源。重启后复查记录并核对导出的文本文件。 |
| 覆盖升级 | 用同包名和同签名更新测试设备，复查已有书架、阅读进度和已停用书源。新增书籍验证变量和章节地址可读回。 |

真机验证单独记录安装版本、应用启动和实际完成的功能验证。解锁设备后再启动应用。

含空章节的 UTF-8 和带 BOM 的 UTF-16 样本可用于复查新书首次导入，以及立即退出后最近阅读是否更新。覆盖升级实测范围见 [0.5.0 版本记录](../versions/0.5.0.md)。

## 0.5.0 调试 ID

设备验收和 UI 自动化可使用以下稳定 ID。

| 界面 | 调试 ID |
| --- | --- |
| 搜书书源加载覆盖层 | `sources-loading`，失败重试 `sources-loading-retry` |
| 书架查找 | `shelf-find`、`shelf-keyword`、`shelf-clear-keyword`、`shelf-filtered-count`、`shelf-empty-result`、`shelf-clear-filter` |
| 阅读器目录筛选 | `directory-keyword`、`directory-clear-keyword`、`directory-filtered-count`、`directory-empty` |
| 直接进目录的上次章节标记 | `directory-current` |

## 离线批量验收样本

在 WSL2 指定一个可从 Windows 访问的临时目录后执行。样本故意只含书源信息，每条带一段注释，使文件超过单次读取块的大小。

```bash
: "${JIANYUE_HAP_STAGE:?请设置 Windows 可写目录的 WSL 路径}"
mkdir -p "$JIANYUE_HAP_STAGE"
python3 - "$JIANYUE_HAP_STAGE/jianyue-bulk-smoke.json" <<'PY'
import json
import sys
from pathlib import Path

sources = [
    {
        'bookSourceName': f'Bulk QA {index:03d}',
        'bookSourceUrl': f'https://fixture.invalid/{index}',
        'bookSourceGroup': 'Bulk QA',
        'bookSourceType': 0,
        'enabled': False,
        'bookSourceComment': 'x' * 960
    }
    for index in range(1, 349)
]
output = Path(sys.argv[1])
output.write_text(json.dumps(sources, ensure_ascii=False), encoding='utf-8')
print(output.stat().st_size)
PY
```

把文件放入测试设备的可选文件目录，在简阅中通过「书源 → 导入 JSON」选择它。用 `Bulk QA` 或 `fixture.invalid` 可定位这批样本。

## 排障入口

- HDC 没有列出可用设备时，请核对 DevEco 安装目录、模拟器运行状态和 USB 调试授权。 [开发与调试](DEVELOPMENT.md)
- JSON 能入库但搜索失败时，从书源卡片提示和四阶段诊断定位请求或字段。 [书源格式与排障](BOOK_SOURCES.md)
- 库初始化或升级后状态异常时，先记录 HAP 版本、设备版本与错误信息，再查看 `LibraryStore.ets` 的迁移事务。 [应用架构](ARCHITECTURE.md)
- 交接新包时，在独立的版本目录记录功能、数据影响、验收设备和结果。 [版本目录](../versions/README.md)

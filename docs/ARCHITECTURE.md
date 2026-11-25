# 应用架构

简阅采用 HarmonyOS Stage 模型。`EntryAbility` 装载 `Index`，页面通过 `NavPathStack` 进入小说详情、阅读器或书源测试。书架和阅读器复用同一个本地仓库处理 TXT 和网络书籍。

## 代码入口

| 目录 | 职责 |
| --- | --- |
| [`entryability/`](../entry/src/main/ets/entryability) | 应用入口、窗口主题和进入后台时保存阅读位置 |
| [`pages/`](../entry/src/main/ets/pages) 与 [`ui/`](../entry/src/main/ets/ui) | 书架、搜书、书源、详情、阅读和书源测试的交互 |
| [`model/`](../entry/src/main/ets/model) | 书籍章节、阅读位置及 Legado 3.0 JSON 字段类型 |
| [`service/`](../entry/src/main/ets/service) | 组织本地导入、网络查找、诊断和缓存策略 |
| [`storage/`](../entry/src/main/ets/storage) 与 [`novel/`](../entry/src/main/ets/novel) | 事务、沙箱文件、字符编码、TXT 分章、阅读块和目录筛选 |
| [`source/`](../entry/src/main/ets/source) | 书源规则、HTTP 请求、HTML、CSS、XPath、JSONPath 和分页 |

## 本地小说

TXT 由系统文件选择器提供读取权限。`NovelFiles` 在关闭文件描述符前完成全部异步分块读取。`TextNovel` 负责解码、识别章节标题和拆分阅读块。原始 TXT 存入沙箱，正文写入同目录的 UTF-8 `text.txt`，章节表以字节偏移和长度读取正文。

应用启动时 `Index` 只加载本地书架和续读进度；书源记录在首次进入「搜书」或「书源」页时按需读取和校验，之后的切换复用已加载结果。书架可按书名查找，查找只作用于当前列表，不改变续读和整理状态。

阅读进度独立保存章节 ID 和章内文本偏移。`ReaderLibrary` 合并滚动和明确点章产生的位置更新，离开页面或应用进入后台时保存待写位置。打开目录、筛选、清除和关闭目录不写进度，只有点章或实际滚动正文才更新。切换字号、行距或面板后按块位置恢复，重进应用时按保存的章节 ID 与偏移恢复；晚到的异步结果或滚动回调不得覆盖当前位置。

阅读器目录支持按标题或纯数字章序筛选，保留原章序和虚拟列表。从详情直接查看目录时只读取保存位置并标记保存章节，不加载正文或改写进度。

## 书源请求与正文

导入的 JSON 先在 `LegadoBookSource.ets` 校验结构，然后按 `bookSourceUrl` 入库。`BookSource` 从存储的文档提取执行各阶段所需的规则。书源页基于已加载记录做本地查找和状态筛选。导入结果页仅接收计数和格式错误，清单由数据库加载。

书架启动阶段不读取书源；首次进入搜书或书源页才加载书源并校验规则。加载中显示提示，重复切换复用结果，导入、启停或刷新后重新读取并忽略过期批次的结果。

书源诊断按搜索、详情、目录和正文独立检查必需规则。可执行的来源可以继续运行一次独立的联网测试。

搜书流程使用 `OnlineNovels` 与 `SiteReader` 查询已启用且搜索规则兼容的来源。`SiteReader` 发起 HTTP 请求，提取详情、目录和正文，并处理分页。阅读服务先读取已缓存正文，再请求缺失内容。已读网络章节存于沙箱的 `online_chapters`。

详情、目录和正文的地址可以包含静态请求选项。地址和选项规范化后用于书籍及章节身份，POST 到同一接口的不同条目可以共存。`@put` 和 `@get` 使用独立的书籍变量作用域，选中的书籍随元数据保存变量，供刷新目录和阅读使用。

`LegadoRules` 组合字段、文本转换和变量。`CssRules` 共用 HTML 节点树执行 CSS、旧式节点语法和基础 XPath，`JsonPath` 执行 JSON 路径。请求选项和固定表达式作为数据解析。字段选取、树遍历、正文及正则输入都有大小限制。

## 响应处理与本地日志

`SiteReader` 在识别信息类型和字符编码之前，从 RCP 的响应头中选择有效的 `Content-Type`。响应头可为字符串或字符串数组。`HtmlDocument` 只在属性值开头进入引号状态，忽略属性值结束后多余的引号，继续扫描后续标记。

`SourceLog` 按批次短 ID 记录请求、HTTP 状态、编码、提取数量和失败阶段。记录通过串行队列写入沙箱 `files/diagnostics`，`source.log` 超过 256 KiB 时轮转为 `source.previous.log`。日志独立于书架数据库。应避免将搜索词、请求参数、授权值或响应正文传入日志。日志页显示最近 120 条，导出从保留的两个文件读取快照。

## 数据库与迁移

`LibraryStore` 使用关系型数据库 `yuejian.db`。应用沙箱和覆盖安装数据由包名 `dev.yuejian.reader` 标识。

| 表 | 主要数据 |
| --- | --- |
| `books` | 书籍元数据、来源、书籍变量及书架状态 |
| `chapters` | 目录、章序、线上地址和本地正文的字节范围 |
| `positions` | 章节 ID、章内偏移和更新时间 |
| `book_sources` | `bookSourceUrl` 主键及带原字段的 JSON 文档 |
| `reader_style` | 字号、行距和日夜主题 |

数据库版本 1 使用 `sources` 表。升级到版本 2 时在事务中将旧 JSON 和实际启停状态迁移到 `book_sources`，事务提交后更新数据库版本。版本 3 给 books 增加 rule_values 列，以空变量初始化已有书籍。重复打开数据库会检查列是否已经存在。应用版本和数据库版本分别记录。涉及持久化结构变更时，同步更新迁移逻辑和[版本记录](../versions/README.md)。

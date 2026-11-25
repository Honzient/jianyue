# 书源格式与排障

简阅使用 Legado 3.0 的书源 JSON 结构。`bookSourceUrl` 标识书源，`bookSourceName` 提供名称。导入会保存原字段和扩展字段。书源诊断按搜索、详情、目录和正文检查所需的规则。 [Legado BookSource 字段定义](https://github.com/LegadoTeam/legado/blob/master/app/src/main/java/io/legado/app/data/entities/BookSource.kt)

## 导入与检查

- 在「书源 → 导入 JSON」选择一个书源对象或书源对象数组。单次最多 16 MB、6000 条。同一个 `bookSourceUrl` 更新当前记录。
- 导入结果显示新增、更新、格式错误和文件内重复数。书源页分别显示已保存数、已有搜索配置的条目数、规则可执行数和已启用的可执行数。
- 按名称、分组或网址查找来源。空格分隔的多个词需全部匹配。
- 「待检查」优先显示已填写搜索配置的条目。点卡片上的「检查」查看本地规则问题。点「测试」查看四个阶段的规则状态，并可用已知能搜到的关键词发起联网测试。

条目只有名称或网址时也可导入。获得搜索能力还需要 `searchUrl` 和 `ruleSearch`。规则可执行表示简阅可以尝试请求，站点是否在线、是否有该书及响应能否匹配可通过联网测试核对。

## 模型字段

| 字段 | 用途 |
| --- | --- |
| `bookSourceUrl`、`bookSourceName` | 必要的书源标识与名称 |
| `enabled`、`bookSourceGroup` | 启停状态与分组 |
| `searchUrl`、`ruleSearch` | 搜索请求、结果列表、书名和详情链接 |
| `ruleBookInfo` | 详情上下文、书名作者简介，以及目录链接 |
| `ruleToc` | 章节列表、章名、链接及目录分页地址 |
| `ruleContent` | 正文提取、正文清理及下一页链接 |

[书源 JSON Schema](../schemas/legado-3.0-book-source.schema.json)给出了字段类型和可选规则组。字段调整需同步检查 ArkTS 模型、JSON Schema 和既有书源数据。

## 规则兼容范围

| 类型 | 支持的常见形式 |
| --- | --- |
| 请求 | HTTP(S) GET、表单 POST 和 JSON POST。搜索及阅读链接可附带静态请求选项，支持单引号、无引号键和尾逗号。关键词支持 UTF-8、GBK、GB2312 和 GB18030。 |
| 搜索模板 | `{{key}}`、`{{page}}`、`{{page-1}}`、`{{(page-1)*10}}`。当前发送第一页。JSON 对象中未加引号的关键词和页码会分别序列化为字符串和数字。 |
| HTML | CSS 属性、父子、兄弟及常见位置条件。支持 `tag/class/id/children/text`、`a.0`、`li!0`、`tag.li[-1:0]`、`tag.li[!0,-1]`。 |
| XPath | 子节点和后代、元素属性、`text()`、位置、属性等值和 `contains(@attr, '值')`。 |
| JSONPath | 属性、通配符、递归属性、并列下标、数组切片和简单属性条件。 |
| 模板与变量 | `{{$.id}}`、`{$.id}`、`{{baseUrl}}`、静态的 `baseUrl.replace`、`@put:{变量:规则}` 和 `@get:{变量}`。书籍变量可以从搜索传到阅读。 |
| 排序与组合 | 搜索列表和目录可用 `-` 倒序。`\|\|` 选首个有结果的分支，`&&` 合并，`%%` 交错合并。组合从高到低为 `%%`、`&&`、`\|\|`。 |
| 文本处理 | `##正则##替换`、带 `###` 的首个匹配提取、捕获组和常见量词，以及 `ruleContent.replaceRegex`。识别已有规则中的固定拼接、百分号编码、Base64 解码与静态替换表达式，由 ArkTS 执行对应操作。 |

规则语义参考安卓版 Legado，诊断流程参考跨平台 Reader。 [Legado 规则解释器](https://github.com/LegadoTeam/legado/blob/master/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt) · [Legado 请求解释器](https://github.com/LegadoTeam/legado/blob/master/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt) · [Reader](https://github.com/hadc188/reader)

需要通用脚本运行时、WebView 渲染或登录凭据的规则会显示相应字段或选项。正则和解析节点有执行边界，正文清理遇到复杂规则或输入过长时会在本地日志说明。

## POST 搜索和详情示例

示例域名用于说明配置形状。实际书源需按目标站点的请求和返回格式配置。

```json
{
  "bookSourceName": "示例小说站",
  "bookSourceUrl": "https://novels.example",
  "bookSourceType": 0,
  "enabled": true,
  "searchUrl": "/search,{\"method\":\"POST\",\"body\":{\"key\":{{key}},\"page\":{{page}}}}",
  "ruleSearch": {
    "bookList": "$..results[1:]",
    "name": "$.title@put:{bookId:$.id}",
    "author": "$.author",
    "bookUrl": "/book,{\"method\":\"POST\",\"body\":\"id={{$.id}}\"}",
    "checkKeyWord": "示例"
  },
  "ruleBookInfo": {
    "name": "$.title",
    "tocUrl": "/chapters?bookId=@get:{bookId}"
  },
  "ruleToc": {
    "chapterList": "$.chapters[*]",
    "chapterName": "$.title",
    "chapterUrl": "$.url",
    "nextTocUrl": "$.next"
  },
  "ruleContent": {
    "content": "$.body",
    "replaceRegex": "##广告文字",
    "nextContentUrl": "$.next"
  }
}
```

## 本地日志

在「书源 → 日志」查看最新记录。测试后点「刷新」查看本次记录，点「导出日志」可通过系统文件选择器保存为文本。记录按 UTC 时间和批次 ID 关联。

| 日志信息 | 如何定位 |
| --- | --- |
| `搜索/兼容性` | 查看指向的字段，并在卡片的「检查」页核对规则。 |
| `搜索/请求` 或 `搜索/HTTP` | 根据错误码或 HTTP 状态检查域名、连接、超时及站点响应。 |
| HTTP 200 且 `候选 0` | 查看响应是 HTML 还是 JSON，核对 `ruleSearch.bookList`。 |
| 有候选且缺书名或链接 | 核对 `ruleSearch.name` 或 `ruleSearch.bookUrl`。 |
| `正文/清理` | 核对 `ruleContent.replaceRegex`。 |

日志记录书源名称、站点来源、状态码、耗时和数量。搜索词、请求参数、凭据和响应正文留在请求与解析流程中。

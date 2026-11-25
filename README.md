# 简阅

简阅是 HarmonyOS 原生的文字小说阅读器。应用使用 ArkTS 和 ArkUI，源码、依赖安装和构建在 Ubuntu WSL2 中维护，运行由 HarmonyOS 模拟器或真机验证。

当前版本为 [0.5.0](versions/0.5.0.md)，默认构建目标是 `entry` 模块。

## 功能

- **本地小说**支持导入 TXT、自动分章、目录跳转、纵向阅读和续读。阅读器可调整字号、行距及日夜主题，目录可按标题或章序筛选；书架可按书名查找。阅读位置按章节 ID 和文本偏移保存，调整设置或重开应用后可继续阅读。
- **网络小说**支持搜索已启用且规则兼容的书源、查看详情与目录、收藏到书架和缓存已读章节。启动时先加载本地书架，书源在首次进入搜书或书源时按需加载并校验。
- **书源管理**支持 Legado 3.0 JSON 单条或批量导入、启停、移除、按名称分组或网址查找，以及分阶段检查规则和测试站点响应。可在应用内查看并导出本地诊断日志。

## 快速构建

在已配置命令行工具的 WSL2 中进入项目根目录。

```bash
source ~/.config/harmonyos/env.sh
cd ~/projects/jianyue
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

模拟器调试包位于 `entry/build/default/outputs/default/entry-default-unsigned.hap`。运行、USB 安装和签名流程见[开发与调试](docs/DEVELOPMENT.md)。

## 项目文档

| 文档 | 接手时可查到的信息 |
| --- | --- |
| [交接与验收](docs/HANDOFF.md) | 项目基线、验收步骤、复现用书源样本和排障顺序 |
| [开发与调试](docs/DEVELOPMENT.md) | WSL2 环境、构建、模拟器部署和真机签名 |
| [应用架构](docs/ARCHITECTURE.md) | 入口、模块职责、存储与迁移 |
| [书源格式与排障](docs/BOOK_SOURCES.md) | Legado 数据结构、规则兼容范围、书源示例 |
| [ArkTS 开发约定](AGENTS.md) | 应用语言、代码约束和开发分工 |
| [版本记录](versions/README.md) | 按版本保存的变更、数据影响与验收结果 |

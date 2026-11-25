# 简阅项目约定

## HarmonyOS 与 ArkTS

- 这是 HarmonyOS 原生 Stage 应用。应用界面、领域逻辑、存储、书源解析与应用测试一律使用 ArkTS，源码扩展名为 `.ets`。ArkTS 是独立语言，不能按 JavaScript 或 TypeScript 的语法和运行时假设来编写。
- 查阅 HarmonyOS SDK 的真实 ArkTS、ArkUI 声明，以 Hvigor 编译和模拟器行为为准。模型与回调参数使用显式的类、接口及类型。类字段在类体声明并由构造函数赋值，禁止 `constructor(public …)` 一类参数属性。避免 `any`、`unknown`、结构兼容假设、动态扩展属性、JS 脚本运行和跳过类型检查的注解。外部 JSON 仅在输入边界校验并转换为 ArkTS 类型。
- Hvigor 要求使用 `hvigorfile.ts` 作为构建入口。该文件只保留华为标准构建插件配置。项目业务源码无 `.js` 或 `.ts`。
- 以 Legado 3.0 的 BookSource JSON 字段作为书源数据模型，保留未知字段。导入先验证 JSON 数据结构，规则执行沿用 ArkTS 声明式解析器及 README 约定。

## 开发位置

- 在 Ubuntu WSL2 的 Linux 文件系统中维护源码和 Git，运行 `ohpm` 与 `hvigorw`。需要时先执行 `source ~/.config/harmonyos/env.sh`。
- Windows DevEco 模拟器提供运行设备，从 WSL2 使用 `hdc-win` 安装并读取日志。
- Windows 侧控制命令使用 PowerShell。只在已确认进入 WSL2 的终端中使用 Bash 语法。

## 文档与版本记录

- 开发交接从 README 和 docs/HANDOFF.md 开始。应用结构、调试流程和书源变化更新到对应文档。
- 版本变更在 versions 目录按版本记录。验收范围按实际运行的设备与结果填写。

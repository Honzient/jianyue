# 开发与调试

源码、依赖与产物构建放在 Ubuntu WSL2。Windows 上的 DevEco Studio 提供模拟器和 USB 设备连接。当前工作站通过 WSL 的 `hdc-win` 调用 Windows `hdc.exe`。

## 开发环境

| 工具 | 当前构建环境 |
| --- | --- |
| DevEco Studio | 26.0.0.865，Windows |
| Linux Command Line Tools | 26.0.0.865，内含 HarmonyOS SDK 26.0.0 |
| Node.js | 24.14.1，命令行工具配套版本 |
| JDK | OpenJDK 21 |
| Hvigor / OHPM | 6.26.9 / 26.0.0.630 |
| 真机连接 | DevEco SDK 中的 Windows HDC |

已有环境运行 `source ~/.config/harmonyos/env.sh`。新工作站先配置 JDK 与 Linux Command Line Tools，再将 Linux 版 HarmonyOS SDK 目录配置到 `DEVECO_SDK_HOME`，把工具包的 `bin` 和配套 Node.js 加入 `PATH`。 [华为命令行构建](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-command-line-building-app/)

```bash
source ~/.config/harmonyos/env.sh
command -v hvigorw ohpm node java hdc-win
hvigorw -v
ohpm -v
node --version
java -version
```

## 构建调试包

```bash
cd ~/projects/jianyue
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

`AppScope/app.json5` 提供应用版本和包名，`build-profile.json5` 提供产品名与 SDK 配置，`entry/src/main/module.json5` 提供模块及 Ability 信息。`hvigorfile.ts` 负责装载标准构建插件。

调试 HAP 默认输出到 `entry/build/default/outputs/default/entry-default-unsigned.hap`。遇到增量缓存异常时，可在实验目录先执行 `hvigorw clean --no-daemon`，再构建。构建日志中优先检查首个 `Error Message` 及对应 `.ets` 行号。

## Windows 设备桥接

在 WSL2 执行 `hdc-win list targets -v`，获取当前连接的设备。典型组合是本机 TCP 模拟器和 USB 真机，向设备发送命令时显式传入 `-t`。

新工作站可在 WSL2 创建一个 `hdc-win` 包装脚本，替换最后一行的 DevEco 安装路径并赋予执行权限。对应的 Windows 可执行文件位于 DevEco Studio 下的 `sdk/default/openharmony/toolchains/hdc.exe`。

```bash
#!/usr/bin/env bash
exec '/mnt/d/Dev/Tools/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe' "$@"
```

## 模拟器安装

在 Windows 的 DevEco Studio 设备管理器启动手机模拟器。此工作站的 Mate 90 Pro 模拟器使用 `127.0.0.1:15826`，执行前以实际 HDC 列表为准。

把 `JIANYUE_HAP_STAGE` 设置为一个 Windows 可写目录在 WSL 中的路径。HDC 客户端是 Windows 程序，安装参数使用 `wslpath -w` 转换后的路径。

例如，可以将 `export JIANYUE_HAP_STAGE='/mnt/c/Users/你的用户名/Documents/jianyue-debug'` 中的用户名换成当前 Windows 用户。

```bash
cd ~/projects/jianyue
source ~/.config/harmonyos/env.sh
: "${JIANYUE_HAP_STAGE:?请设置 Windows 可写目录的 WSL 路径}"
hdc-win list targets -v
emulator='127.0.0.1:15826'
mkdir -p "$JIANYUE_HAP_STAGE"
cp entry/build/default/outputs/default/entry-default-unsigned.hap "$JIANYUE_HAP_STAGE/jianyue-debug.hap"
hdc-win -t "$emulator" app install -r "$(wslpath -w "$JIANYUE_HAP_STAGE/jianyue-debug.hap")"
hdc-win -t "$emulator" shell aa start -a EntryAbility -b dev.yuejian.reader -m entry
hdc-win -t "$emulator" shell hilog -x -T Jianyue
```

应用内的「书源 → 日志」保留书源请求与解析记录，可刷新或导出。`hilog -x -T Jianyue` 可查看进程级日志，例如沙箱写入异常。

## 真机签名与升级

1. 解锁真机，连接 USB 并确认设备端调试授权。用 `hdc-win list targets -v` 核对 USB 设备。
2. 在 DevEco Studio 的项目结构中为 `dev.yuejian.reader` 生成调试签名，核对 Profile 匹配当前设备并处于有效期。 [华为自动签名](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing-auto/)
3. 在临时构建副本的 `build-profile.json5` 应用 `signingConfigs`，把 `default` 产品的 `signingConfig` 连接到签名项。证书、密钥库和 Profile 路径需可从 WSL 访问，应用源码仍在 WSL 构建。
4. 把生成的 `entry-default-signed.hap` 复制到 Windows 可读的暂存目录。
5. 把实际 USB 设备标识写入 `usb`，再执行覆盖安装和版本核对。

```bash
: "${usb:?请先设置为 HDC 列表核对过的 USB 设备标识}"
: "${JIANYUE_HAP_STAGE:?请设置 Windows 可写目录的 WSL 路径}"
signed_hap="$JIANYUE_HAP_STAGE/entry-default-signed.hap"
test -s "$signed_hap"
hdc-win -t "$usb" app install -r "$(wslpath -w "$signed_hap")"
hdc-win -t "$usb" shell bm dump -n dev.yuejian.reader
hdc-win -t "$usb" shell aa start -a EntryAbility -b dev.yuejian.reader -m entry
```

仓库的 `build-profile.json5` 保存默认的无签名模板。签名配置和密钥材料由本机 DevEco 管理。覆盖升级需使用匹配的包名与签名身份。

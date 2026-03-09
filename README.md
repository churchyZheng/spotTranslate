# spotTranslate

`spotTranslate` 是一个运行在 macOS 15+ 的菜单栏小工具。当你打开 Spotlight 并输入多词短语或句子时，它会在 Spotlight 下方显示一个悬浮翻译卡片。

## 为什么不是直接改 Spotlight 结果行

Apple 没有公开 API 允许第三方应用把“任意 Spotlight 查询词”直接替换成原生结果行，所以这里采用的是可稳定落地的方式：

- 监听 Spotlight 输入框内容
- 检测到是短语/句子后调用系统 `Translation` framework
- 在 Spotlight 下方显示非侵入式翻译浮层

实际效果接近目标用法：打开 Spotlight，输入 `how are you`，会看到浮层显示 `你好吗`。

## 构建

```bash
swift test
./scripts/build_app.sh
```

## 安装到固定位置

建议不要直接长期运行 `build/` 目录里的 `.app`。因为每次重新构建后，macOS 可能把它视为新的应用实例，之前授予的“辅助功能”权限会失效。

推荐安装到 `~/Applications`：

```bash
./scripts/install_app.sh
```

## 运行

```bash
open ./build/SpotSentenceTranslate.app
```

首次启动需要做两件事：

1. 给应用授予“辅助功能”权限，因为它需要读取 Spotlight 输入框内容。
2. 如果系统还没安装对应语言包，首次翻译时允许系统下载翻译资源。

如果在“辅助功能”列表里找不到应用：

1. 点击 `+`
2. 按 `Command + Shift + G`
3. 输入 `~/Applications/SpotSentenceTranslate.app`
4. 添加后打开右侧开关

## 使用方式

1. 启动应用后，菜单栏会出现一个 `译` 图标。
2. 打开 Spotlight。
3. 输入多词英文短语、英文句子，或较长中文短语。
4. 翻译结果会显示在 Spotlight 下方。

## 已实现的行为

- 单个英文单词默认不拦截，避免和 Spotlight 自带的词典/翻译结果冲突。
- 多词英文输入默认翻译为简体中文。
- 中文短语默认翻译为英文。
- 结果使用系统 `Translation` framework，优先走本机能力。

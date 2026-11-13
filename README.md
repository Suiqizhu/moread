# 墨读 moread

一个用 Flutter 写的安卓本地阅读器：干干净净的排版，只读你自己放进来的书，不联网、不登录、没有广告。

![icon](android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png)

## 功能

**书架**
- 导入本地 `TXT` / `EPUB`（系统文件选择器，Android 13+ 无需存储权限，支持多选批量导入）
- 「继续阅读」卡片直达上次进度；网格按最近阅读 / 导入时间 / 书名排序
- 搜索书名或作者；长按进入多选，批量删除
- 正文、章节表、封面都复制进应用私有目录，原文件删了也不影响阅读

**解析**
- TXT：UTF-8 / GBK / UTF-16LE 自动识别（中文小说 GBK 很常见），按「第 X 章 / 楔子 / 番外 / Chapter N」切章；识别不到就整本当一章
- EPUB：解压 → `container.xml` → OPF 的 manifest/spine，按 spine 顺序抽正文（去脚本/样式、`<br>` 转行、实体解码），章节标题取 `h1~h3`，封面取 `cover-image`
- 书名/作者：EPUB 读 OPF 元数据；TXT 从文件名拆（`书名 作者：某某.txt`）

**阅读器**
- 用 `TextPainter` 真实排版结果分页，不会出现半个字被切掉
- 左右 30% 点击翻页、中间呼出菜单；章节末尾自动进下一章，翻页有触感反馈
- 目录抽屉自动定位当前章；底部滑块按页拖进度
- 全书搜索：输入防抖 + 后台 isolate 扫描，点结果直接跳到那一句
- 书签：添加 / 移除当前页，列表跳转
- 字号（14–32）、行距（1.3–2.4）、字体（系统/宋体/黑体）、6 套配色（纸白/月白/青竹/暖沙/深夜/纯黑）
- 进度防抖保存，退出、切后台都会立即落盘；阅读时保持屏幕常亮（原生 FLAG_KEEP_SCREEN_ON）
- 沉浸式全屏，状态栏图标跟随配色切换

**隐私**：不申请网络权限，书和进度只存在 `/data/data/com.moread.moread/files/moread/`。

## 目录

```
lib/
├─ main.dart                    应用入口、主题、中文本地化
├─ models/book.dart             Book / Chapter（含 JSON 序列化）
├─ services/
│  ├─ library.dart              书库索引 + 进度持久化（合并写盘）
│  ├─ parser.dart               TXT/EPUB 解析（纯 Dart，可单测）
│  ├─ importer.dart             导入流程：isolate 解析 → 落盘 → 入书架
│  ├─ book_search.dart          全文搜索（纯 Dart，可单测）
│  └─ pagination.dart           TextPainter 分页
├─ screens/
│  ├─ shelf_screen.dart         书架、搜索、排序、多选删除
│  └─ reader_screen.dart        阅读器：翻页、菜单、目录、搜索、书签
├─ widgets/
│  ├─ book_cover.dart           封面（按显示尺寸解码）
│  └─ reader_sheets.dart        目录 / 搜索 / 书签面板
└─ theme/reader_theme.dart      配色与阅读设置（持久化）
tool/
├─ selftest.dart                解析逻辑自测（dart run tool/selftest.dart）
├─ make_fixtures.py             生成测试用的 TXT/GBK/EPUB
└─ gen_icon.py                  生成启动图标
test/
├─ widget_test.dart             分页与序列化测试
└─ fixtures/                    解析自测用的样本（UTF-8 TXT / GBK TXT / EPUB）
.github/workflows/android.yml   CI：分析 + 测试 + 打包 APK
```

## 构建

需要 Flutter ≥ 3.38（Dart ≥ 3.10）、JDK 17、Android SDK。已在 Flutter 3.50 / AGP 9.3.1 上通过静态分析。

```bash
flutter pub get
flutter analyze
dart run tool/selftest.dart        # 解析 / 搜索 / 书签自测，36 项
flutter test                       # 分页与序列化测试
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`：

- `app-arm64-v8a-release.apk` —— 现在绝大多数手机装这个
- `app-armeabi-v7a-release.apk` —— 老一点的 32 位设备
- `app-x86_64-release.apk` —— 模拟器

> 仓库自带的 `android/app/build.gradle.kts` 用 debug 签名打 release 包，方便直接安装；要上架请换成自己的 keystore。

### 用 GitHub Actions 出包

把项目推到 GitHub，`.github/workflows/android.yml` 会在每次 push 时构建并上传 APK：

```bash
git init && git add . && git commit -m "moread"
git remote add origin <你的仓库>
git push -u origin main
```

然后在仓库的 **Actions → build-apk → Artifacts** 里下载 `moread-apk`。

## 实现备注

- **分页**：把整章文本交给 `TextPainter` 排版，用 `computeLineMetrics()` 累加行高找出本页能放下的最后一行，从下一行行首切页；每次只测 8000 个字符，长章节也不会卡。
- **进度**：存的是「章节序号 + 章节内字符偏移」，所以换字号、换行距之后能落回差不多同一段文字，而不是跳到上一页开头。
- **书库索引**：`library.json` 只存元数据，章节表单独放 `books/<id>.chapters.json`，翻页写进度时不用重写大文件。
- **性能**：翻页只改内存、最多 3 秒合并写一次盘；阅读时不会通知书架重建；解析在独立 isolate；封面按显示宽度解码；书架用 sliver 网格按需构建。
- **字体**：`serif` / `sans-serif` 用系统字体族，中文由 Android 的 Noto Serif/Sans CJK 兜底，不额外打包字体（安装包小）。

## 已知限制

- 暂不支持 PDF、MOBI/AZW3、带复杂排版的图文 EPUB（图片会被忽略，只抽文字）
- 没有笔记和 TTS 朗读
- 竖排/双栏、CSS 样式还原都还没做

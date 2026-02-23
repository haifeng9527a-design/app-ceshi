# Windows 端构建说明

在 Windows 上执行 `flutter run -d windows` 时，可能遇到两类错误，按下面步骤处理即可。

---

## 1. 缺少 atlbase.h（flutter_local_notifications_windows）

**报错示例：**
```text
error C1083: 无法打开包括文件: "atlbase.h": No such file or directory
[flutter_local_notifications_windows\plugin.cpp]
```

**原因：** 未安装 Visual Studio 的 ATL（Active Template Library）组件。

**解决：**

1. 打开 **Visual Studio Installer**
2. 对已安装的「Visual Studio 2022」或「Build Tools」点 **修改**
3. 在 **单个组件** 里勾选：
   - **用于最新 v143 生成工具的 C++ ATL (x86和x64)**
   - 或英文：**C++ ATL for latest v143 build tools (x86 & x64)**
4. 安装完成后重新执行：
   ```powershell
   cd d:\teacher_hub\app
   flutter clean
   flutter pub get
   flutter run -d windows
   ```

---

## 2. Firebase 链接错误（LNK2019：__std_remove_8 / __std_search_1 等）

**报错示例：**
```text
error LNK2019: 无法解析的外部符号 __std_remove_8
error LNK2019: 无法解析的外部符号 __std_find_last_of_trivial_pos_1
error LNK2019: 无法解析的外部符号 __std_search_1
fatal error LNK1120: 3 个无法解析的外部命令
```

**原因：** Firebase C++ SDK 与当前 MSVC 标准库版本不匹配（FlutterFire 已知问题）。

**建议步骤：**

1. **使用 Visual Studio 2022 且版本尽量新**
   - `flutter doctor -v` 里 Windows 开发应显示基于 **Visual Studio 2022**（或 17.x），不要用很老的 VS 2017/2019。
   - 在 [Flutter 文档](https://docs.flutter.dev/get-started/install/windows#windows-requirements) 查看当前推荐的 VS 版本。

2. **用「VS 开发者命令提示」再跑 Flutter**
   - 开始菜单打开 **“Developer Command Prompt for VS 2022”** 或 **“x64 Native Tools Command Prompt for VS 2022”**
   - 在该终端中执行：
     ```powershell
     cd d:\teacher_hub\app
     flutter clean
     flutter pub get
     flutter run -d windows
     ```
   - 可避免环境混用导致的工具链不一致。

3. **若仍失败，可尝试降级 firebase_core（最后手段）**
   - 此类问题在 [firebase/flutterfire#11212](https://github.com/firebase/flutterfire/issues/11212)、[#10992](https://github.com/firebase/flutterfire/issues/10992) 等 issue 有讨论；新版 C++ SDK 与部分 MSVC 工具链不兼容。
   - 有用户通过将 `firebase_core` 降级到 3.12 之前的版本暂时规避，需同步调整 `firebase_auth`、`firebase_messaging` 等版本以保持兼容，可能影响功能，仅作权宜之计。

---

## 快速检查清单

- [ ] 已安装 **“用于最新 v143 生成工具的 C++ ATL”**
- [ ] 使用 **Visual Studio 2022**（或当前 Flutter 文档推荐的版本）
- [ ] 在 **Developer Command Prompt for VS 2022** 中执行 `flutter run -d windows`
- [ ] 若刚改过环境，先执行 `flutter clean` 再构建

完成上述步骤后，再执行：

```powershell
cd d:\teacher_hub\app
flutter run -d windows
```

若仍有新的报错，把完整构建输出（含最后几十行）保存下来便于排查。

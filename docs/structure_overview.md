项目目录说明（安卓 / PC / 后台）

一、主要目录
- app/                          Flutter 主工程（APP + PC/Web 端入口）
- app/lib/                      业务代码（APP UI / 后台 UI / 共享逻辑）
- app/android/                  Android 原生工程（安卓相关配置）
- app/ios/                      iOS 原生工程
- app/windows/                  Windows 桌面工程（PC 端）
- app/web/                      Web 工程（浏览器端）
- app/macos/                    macOS 桌面工程
- app/linux/                    Linux 桌面工程
- app/supabase/                 Supabase 后端（数据库/函数/配置）
- docs/                         项目文档与 SQL 脚本

二、安卓相关
- app/android/                  Android Manifest、Gradle、权限、推送配置
- app/build/                    构建产物（安卓/桌面打包产物）

三、PC 端相关
- app/windows/                  Windows 桌面端工程
- app/web/                      Web 端工程（我们目前用于 PC 后台）

四、后台相关
- app/lib/features/admin/       后台 UI（PC/Web）
  - admin_home_page.dart        后台框架（导航 + 入口）
  - admin_teacher_panel.dart    交易员审核/资料管理模块
- app/supabase/                 后端服务
  - functions/send_push/        推送函数（FCM / 个推）
- docs/*.sql                    后台数据表和权限脚本

五、APP 主体相关
- app/lib/features/messages/    聊天、好友、系统通知
- app/lib/features/profile/     “我的”页面
- app/lib/features/teachers/    交易员中心、交易员主页
- app/lib/features/home/        首页/关注页

六、常用入口文件
- app/lib/main.dart             Flutter 入口
- app/lib/app.dart              App 根组件（主题、路由）
- app/pubspec.yaml              依赖与资源配置

七、你最常用的文件（我们改动最多）
- app/lib/features/admin/       后台
- app/lib/features/teachers/    交易员相关
- app/lib/features/messages/    聊天相关
- app/lib/core/notification_service.dart  推送
- app/supabase/functions/send_push/index.ts  推送函数

# 个推华为厂商通道配置（来电推送必读）

华为手机在**退出应用**后收不到来电推送，需开通**华为厂商通道**，由华为系统推送送达。

## 1. 华为 AppGallery Connect 配置

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
2. 创建/选择应用，包名需与 `com.example.teacher_hub` 一致
3. **项目设置 > 增长 > 推送服务**：开通推送
4. **项目设置 > 常规**：填写 SHA256 证书指纹
5. 获取 **AppID** 和 **AppSecret**（推送服务 > 应用信息）

## 2. 个推开发者中心配置

1. 登录 [个推开发者中心](https://dev.getui.com/)
2. 选择对应应用 > **配置管理**
3. **华为辅助推送**：填写华为 AppID、AppSecret、应用包名
4. 若未开通多厂商推送，需联系个推客服开通

## 3. 验证

配置完成后，退出应用（划掉或切后台），用另一台设备发起语音通话，应能收到来电通知。

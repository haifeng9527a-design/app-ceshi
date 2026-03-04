// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '金融培训机构';

  @override
  String get adminTitle => '后台管理';

  @override
  String get navHome => '首页';

  @override
  String get navMainPage => '主页';

  @override
  String get navMarket => '行情';

  @override
  String get navWatchlist => '自选';

  @override
  String get navMessages => '消息';

  @override
  String get navRankings => '排行榜';

  @override
  String get navFollow => '关注';

  @override
  String get navProfile => '我的';

  @override
  String get navSettings => '设置';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonRetry => '重试';

  @override
  String get commonConfirm => '确定';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonLoading => '加载中…';

  @override
  String get commonNoData => '暂无数据';

  @override
  String get commonUser => '用户';

  @override
  String get commonOther => '对方';

  @override
  String get commonFriend => '好友';

  @override
  String get commonMe => '我';

  @override
  String get commonCopy => '复制';

  @override
  String get commonForward => '转发';

  @override
  String get commonReply => '回复';

  @override
  String get commonImage => '图片';

  @override
  String get commonVideo => '视频';

  @override
  String get commonFile => '文件';

  @override
  String get commonCopied => '已复制';

  @override
  String get commonKnowIt => '知道了';

  @override
  String get commonGoToSettings => '去设置';

  @override
  String get commonGoToEnable => '去开启';

  @override
  String get authLoginOrRegister => '登录/注册';

  @override
  String get authLogin => '登录';

  @override
  String get authLoginHint => '使用邮箱或第三方账号登录';

  @override
  String get authRegisterHint => '创建账号并验证邮箱';

  @override
  String get authNameHint => '请输入昵称';

  @override
  String get authEmailHint => '请输入邮箱';

  @override
  String get authPasswordHint => '请输入密码';

  @override
  String get authConfirmPasswordHint => '请再次输入密码';

  @override
  String get authPleaseConfigureFirebase => '请先配置 Firebase（添加配置文件）';

  @override
  String get authPleaseFillEmailAndPassword => '请先填写邮箱和密码';

  @override
  String get authAccountOrPasswordWrong => '账号或密码错误';

  @override
  String get authEnterAccount => '请输入账号';

  @override
  String get authEnterPassword => '请输入密码';

  @override
  String get authAccount => '账号';

  @override
  String get authPassword => '密码';

  @override
  String get authPleaseLoginToManage => '请登录后管理后台';

  @override
  String get authEnterAdminAccount => '请输入管理员账号';

  @override
  String get authEnterPasswordHint => '请输入密码';

  @override
  String get profileMy => '我的';

  @override
  String get profileEditSignature => '编辑个性签名';

  @override
  String get profileSignatureHint => '写点什么吧…';

  @override
  String get profileAvatarUploadFailedNoSupabase => '头像上传失败：未配置 Supabase';

  @override
  String get profileAvatarUpdated => '头像已更新';

  @override
  String get profileAvatarUploadFailed => '头像上传失败';

  @override
  String get profileSignatureUpdated => '签名已更新';

  @override
  String get profileSignatureUpdateFailed => '签名更新失败';

  @override
  String get profileAdmin => '管理员';

  @override
  String get profileVip => '会员';

  @override
  String get profileTeacher => '交易员';

  @override
  String get profileNormalUser => '普通用户';

  @override
  String get profileStudentAccount => '学员账号';

  @override
  String get profileNotLoggedIn => '未登录';

  @override
  String get profileBecomeTeacher => '成为交易员';

  @override
  String get profileLoginToSubmit => '登录后可提交资料';

  @override
  String get profileFirebaseNotConfigured => '尚未配置 Firebase，登录与消息功能暂不可用。';

  @override
  String get profileNotificationNotEnabled => '通知未开启，可能收不到新消息提醒';

  @override
  String get profileAccountId => '账号ID';

  @override
  String profileAccountIdValue(String id) {
    return '账号ID $id';
  }

  @override
  String get profileAccountIdDash => '账号ID --';

  @override
  String get profileLazySignature => '这个人很懒，什么都没写';

  @override
  String get profileTeacherCenter => '交易员中心';

  @override
  String get profileManageStrategyAndRecords => '管理策略与交易记录';

  @override
  String get profileSubmitProfileAndPublish => '提交资料，发布策略与交易记录';

  @override
  String get profileMyFollowing => '我的关注';

  @override
  String get profileAdminPc => '后台管理（PC）';

  @override
  String get profilePushNotificationGuide => '收不到推送？';

  @override
  String get profileNotificationGuideSubtitle => '查看通知与自启动设置说明';

  @override
  String get profileEnsureReceiveMessages => '确保收到新消息';

  @override
  String get profileNotificationPermissionGuide =>
      '1. 请允许本应用的「通知」和「后台运行」权限。\n\n2. 华为/荣耀用户：若后台收不到消息，请到\n   设置 → 应用 → Tongxin\n   开启「自启动」，并在「手动管理」中允许后台活动。\n\n3. 华为/荣耀用户：若来电时没有弹出接听界面（只在通知栏看到），请到\n   设置 → 应用 → Tongxin → 权限\n   开启「后台弹窗」或「悬浮窗」，以便在桌面/其他 App 时也能弹出通话窗口。\n\n4. 若需要桌面图标显示未读数字，请到\n   设置 → 应用 → Tongxin → 通知管理\n   开启「桌面角标」。';

  @override
  String get profileIncomingCallFullScreen => '来电全屏接听';

  @override
  String get profileIncomingCallFullScreenSubtitle =>
      '后台或锁屏时直接弹出接听界面（Android 14+ 需开启全屏意图）';

  @override
  String get profileFullScreenIntentEnabled => '已开启，来电时将全屏弹出';

  @override
  String get profileCurrentNotLoggedIn => '当前未登录';

  @override
  String get profileLogout => '退出登录';

  @override
  String get profileLoggedIn => '已登录';

  @override
  String get profileReRequestPermission => '重新请求权限';

  @override
  String get profileHelp => '帮助';

  @override
  String get profileHelpTitle => '帮助与说明';

  @override
  String get profileTraderFriends => '交易员好友';

  @override
  String get profileTraderFriendsSubtitle => '我关注的交易员';

  @override
  String get profileAccountDeletion => '账号注销';

  @override
  String get profileAccountDeletionConfirm => '注销后账号将被永久删除，无法恢复。确定继续？';

  @override
  String get profileDeletionSuccess => '账号已注销';

  @override
  String get profilePrivacyPolicy => '隐私政策';

  @override
  String get profilePrivacyPolicySubtitle => '查看隐私政策与用户协议';

  @override
  String get profileReport => '举报';

  @override
  String get profileReportSubtitle => '举报违规内容或用户';

  @override
  String get profilePrivacyPolicyContent =>
      '本应用尊重并保护用户隐私。我们收集的信息仅用于提供和改进服务。详细条款请参阅应用商店或官网的完整隐私政策。';

  @override
  String get profileReportContent => '如有违规内容或用户，请通过应用内反馈或联系客服举报。我们会尽快处理。';

  @override
  String get reportPageTitle => '举报用户';

  @override
  String get reportTargetUser => '被举报用户';

  @override
  String get reportTargetUserHint => '输入账号ID或邮箱搜索';

  @override
  String get reportReason => '举报原因';

  @override
  String get reportReasonHarassment => '骚扰';

  @override
  String get reportReasonSpam => '广告/垃圾信息';

  @override
  String get reportReasonFraud => '欺诈';

  @override
  String get reportReasonInappropriate => '不当言论';

  @override
  String get reportReasonOther => '其他';

  @override
  String get reportContent => '详细说明';

  @override
  String get reportContentHint => '请描述具体情况（选填）';

  @override
  String get reportScreenshots => '截图证据';

  @override
  String get reportScreenshotsMax => '最多5张';

  @override
  String get reportSubmit => '提交举报';

  @override
  String get reportSuccess => '举报已提交，我们会尽快处理';

  @override
  String get reportFailed => '提交失败';

  @override
  String get reportPleaseSelectUser => '请先搜索并选择被举报用户';

  @override
  String get reportPleaseSelectReason => '请选择举报原因';

  @override
  String get featuredTrader => '交易员';

  @override
  String get featuredMentor => '导师';

  @override
  String get featuredNoTodayStrategy => '暂无今日策略';

  @override
  String get featuredNoTeacherInfo => '暂无交易员信息';

  @override
  String get featuredLoadFailedRetry => '加载失败，请重试';

  @override
  String get featuredServiceNotReady => '服务未就绪';

  @override
  String get featuredNoFollowingOrRanking => '暂无关注或排名数据';

  @override
  String get featuredNetworkRestricted => '网络连接被限制，请检查网络或在本机终端运行应用后重试';

  @override
  String get featuredNotStartedInvestment => '你还没有开启自己的投资之旅';

  @override
  String get featuredPnlOverview => '盈亏概览';

  @override
  String get featuredTodayStrategy => '今日交易策略';

  @override
  String get featuredViewAllStrategies => '查看全部交易策略';

  @override
  String get featuredCurrentPositions => '目前持仓';

  @override
  String get featuredHistoryPositions => '历史持仓';

  @override
  String get featuredWins => '胜场';

  @override
  String get featuredLosses => '败场';

  @override
  String get featuredWinRate => '胜率';

  @override
  String get featuredPositionPnl => '持仓盈亏';

  @override
  String get featuredYearPnl => '年度盈亏';

  @override
  String get featuredTotalPnl => '总盈亏';

  @override
  String get featuredCoreStrategy => '核心策略';

  @override
  String get featuredCollapse => '收起';

  @override
  String featuredExpandReplies(int count) {
    return '展开 $count 条回复';
  }

  @override
  String get featuredLoginBeforeForward => '请先登录后再转发';

  @override
  String get featuredViewFullStrategy => '点击查看完整投资策略';

  @override
  String get featuredHideComments => '隐藏评论';

  @override
  String get featuredViewComments => '查看评论';

  @override
  String get featuredForwardTooltip => '转发';

  @override
  String get featuredNoComments => '暂无评论';

  @override
  String get featuredForwarded => '已转发';

  @override
  String get featuredForwardFailed => '转发失败';

  @override
  String featuredForwardFailedWithMessage(String message) {
    return '转发失败: $message';
  }

  @override
  String get featuredForwardTo => '转发到';

  @override
  String get featuredNoConversationAddFriend => '暂无会话，请先添加好友或加入群聊';

  @override
  String get featuredLoginBeforeComment => '请先登录后再发表评论';

  @override
  String get featuredCommentPublished => '评论已发表';

  @override
  String get featuredCommentPublishFailed => '发表失败';

  @override
  String featuredCommentPublishFailedWithMessage(String message) {
    return '发表失败: $message';
  }

  @override
  String featuredCommentsCount(int count) {
    return '$count条评论';
  }

  @override
  String get featuredCommentHint => '写下你的评论…';

  @override
  String get featuredPublishing => '发表中…';

  @override
  String get featuredPublish => '发表';

  @override
  String get featuredBuy => '买入';

  @override
  String get featuredCost => '成本';

  @override
  String get featuredQuantity => '数量';

  @override
  String get featuredSell => '卖出';

  @override
  String get featuredSellPrice => '卖出价';

  @override
  String get featuredCurrentPrice => '现价';

  @override
  String get featuredFloatingPnl => '浮动盈亏';

  @override
  String get featuredCurrentPositionPnl => '目前持仓盈亏';

  @override
  String get featuredCurrentPosition => '目前持仓';

  @override
  String get featuredBuyTime => '买入时间';

  @override
  String get featuredBuyShares => '买入股数';

  @override
  String get featuredBuyPrice => '买入价格';

  @override
  String get featuredPositionCost => '持仓成本';

  @override
  String get featuredPositionPnlRatio => '持仓盈亏比例';

  @override
  String get featuredProfitRatio => '盈利比例';

  @override
  String get featuredPnlAmount => '盈亏金额';

  @override
  String get featuredShares => '股数';

  @override
  String get featuredPrice => '价格';

  @override
  String get featuredMonthTotalPnl => '本月总盈亏';

  @override
  String get featuredPositionPnlAmount => '持仓盈亏金额';

  @override
  String get featuredTodayStrategyTab => '今日策略';

  @override
  String get featuredPositionTab => '持仓';

  @override
  String get featuredHistoryTab => '历史';

  @override
  String get tradingApple => '苹果';

  @override
  String get tradingMicrosoft => '微软';

  @override
  String get tradingGoogle => '谷歌';

  @override
  String get tradingAmazon => '亚马逊';

  @override
  String get tradingTesla => '特斯拉';

  @override
  String get tradingStock => '股票';

  @override
  String get tradingForex => '外汇';

  @override
  String get tradingCrypto => '加密货币';

  @override
  String get tradingQuoteRefreshFailed => '行情刷新失败';

  @override
  String get tradingSearchAndSelectFirst => '请先搜索并选择标的';

  @override
  String get tradingOrderSubmitted => '已提交（模拟，接口待接入）';

  @override
  String get tradingVolume => '成交量';

  @override
  String get tradingSelectGainersOrSearch => '选择上方涨幅榜或搜索标的';

  @override
  String get tradingViewRealtimeQuote => '查看实时行情与图表';

  @override
  String get tradingGainersList => '涨幅榜';

  @override
  String get tradingUpdateTime => '更新';

  @override
  String tradingUpdateTimeValue(String time) {
    return '更新 $time';
  }

  @override
  String get tradingConfigurePolygonApiKey => '请配置 POLYGON_API_KEY';

  @override
  String get tradingStockCodeOrName => '股票代码或名称';

  @override
  String get tradingForexCodeExample => '外汇代码如 EUR/USD';

  @override
  String get tradingCryptoExample => '加密货币如 BTC、ETH';

  @override
  String get tradingIntraday => '分时';

  @override
  String get tradingNoChartData => '暂无图表数据';

  @override
  String get tradingBuy => '买入';

  @override
  String get tradingSell => '卖出';

  @override
  String get tradingLimitOrder => '限价';

  @override
  String get tradingMarketOrder => '市价';

  @override
  String get tradingPriceLabel => '价格';

  @override
  String get tradingQuantityLabel => '数量';

  @override
  String get tradingEnterValidQuantity => '请输入有效数量（大于 0）';

  @override
  String get tradingEnterValidPriceForLimit => '限价单请输入有效价格（大于 0）';

  @override
  String get tradingConfirmBuy => '确认买入';

  @override
  String get tradingConfirmSell => '确认卖出';

  @override
  String get tradingNoData => '暂无数据';

  @override
  String tradingBuySellSubmitted(String action, String symbol) {
    return '$action $symbol 已提交（模拟，接口待接入）';
  }

  @override
  String get callCallerCancelled => '对方已取消';

  @override
  String get callVideoCall => '视频通话';

  @override
  String get callVoiceCall => '语音通话';

  @override
  String get callInviteVideoCall => '邀请你视频通话';

  @override
  String get callInviteVoiceCall => '邀请你语音通话';

  @override
  String get callDecline => '拒绝';

  @override
  String get callAnswer => '接听';

  @override
  String callInviteCallBody(String name, String type) {
    return '$name 邀请你$type通话';
  }

  @override
  String get messagesNoMatchingMembers => '暂无匹配成员';

  @override
  String get messagesNotFriendCannotSend => '已不是好友，无法发送';

  @override
  String get messagesRecordingTooShort => '录音时间太短';

  @override
  String get messagesGrantMicPermission => '请授予麦克风权限';

  @override
  String get messagesNoSupabaseCannotSendMedia => '未配置 Supabase，无法发送媒体';

  @override
  String get messagesFileEmptyCannotSend => '文件为空，无法发送';

  @override
  String get messagesSendFailed => '发送失败';

  @override
  String get messagesCannotReadFile => '无法读取该文件';

  @override
  String get messagesSelectFileFailed => '选择文件失败';

  @override
  String get messagesForwardInDevelopment => '转发功能正在开发中';

  @override
  String get messagesRecall => '撤回';

  @override
  String get messagesRecallMessage => '撤回消息';

  @override
  String get messagesConfirmRecallMessage => '确定撤回这条消息吗？';

  @override
  String get messagesRecalled => '已撤回';

  @override
  String get messagesRecallFailed => '撤回失败';

  @override
  String get messagesAlbum => '相册';

  @override
  String get messagesCamera => '拍摄';

  @override
  String get messagesFileLabel => '文件';

  @override
  String get messagesCallLabel => '通话';

  @override
  String get messagesTakePhoto => '拍照';

  @override
  String get messagesTakeVideo => '拍视频';

  @override
  String get messagesVoiceCall => '语音通话';

  @override
  String get messagesVideoCall => '视频通话';

  @override
  String get messagesNoAgoraCannotCall => '未配置 Agora，无法发起通话';

  @override
  String get messagesNeedMicForCall => '需要麦克风权限才能通话，请先开启';

  @override
  String get messagesNeedCameraForVideo => '需要相机权限才能视频通话，请先开启';

  @override
  String get messagesGroupSettings => '群设置';

  @override
  String get messagesSetRemark => '设置备注';

  @override
  String get messagesPinConversation => '置顶会话';

  @override
  String get messagesClearChatHistory => '清空聊天记录';

  @override
  String get messagesImage => '图片';

  @override
  String get messagesVideo => '视频';

  @override
  String get messagesReply => '回复';

  @override
  String get messagesCopy => '复制';

  @override
  String get messagesForward => '转发';

  @override
  String get messagesCopied => '已复制';

  @override
  String get messagesNoFriendCannotSend => '已不是好友，无法发送';

  @override
  String get messagesSendFailedPrefix => '发送失败';

  @override
  String get messagesFileSendFailedPrefix => '文件发送失败';

  @override
  String get messagesRecallFailedPrefix => '撤回失败';

  @override
  String get messagesViewProfile => '查看个人资料';

  @override
  String get messagesRemarkHint => '输入备注名';

  @override
  String get messagesConfirmClearChat => '确定清空本会话的所有聊天记录吗？此操作不可恢复。';

  @override
  String get messagesClear => '清空';

  @override
  String get messagesGroupAnnouncement => '群公告';

  @override
  String get messagesInputHint => '输入消息';

  @override
  String get messagesSend => '发送';

  @override
  String get messagesOpening => '正在打开…';

  @override
  String get messagesCannotOpenFile => '无法打开该文件';

  @override
  String get messagesFileExpiredOrMissing => '文件已过期或不存在，请让对方重新发送';

  @override
  String get messagesUseCompatiblePlayer => '使用兼容播放器';

  @override
  String get marketNoData => '暂无数据';

  @override
  String tradingQuoteRefreshFailedWithError(String error) {
    return '行情刷新失败: $error';
  }

  @override
  String get tradingKline => 'K线';

  @override
  String get teachersConfirmRiskPrompt => '请确认已阅读风险提示';

  @override
  String get teachersProfileSubmitted => '资料已提交';

  @override
  String get teachersSaveFailed => '保存失败';

  @override
  String get teachersPhotoUploaded => '资料照片已上传';

  @override
  String get teachersUploadFailed => '上传失败';

  @override
  String get teachersPublishStrategy => '发布策略';

  @override
  String get teachersTitleLabel => '标题';

  @override
  String get teachersStrategyContent => '策略内容';

  @override
  String get teachersImages => '配图';

  @override
  String get teachersAddImage => '添加图片';

  @override
  String get teachersStrategyImage => '配图';

  @override
  String get teachersFillStrategyTitle => '请填写策略标题';

  @override
  String get teachersPublish => '发布';

  @override
  String get teachersStrategyPublished => '策略已发布，将显示在关注页「今日交易策略」';

  @override
  String get teachersPublishFailed => '发布失败';

  @override
  String get teachersUploadTradeRecord => '上传交易记录';

  @override
  String get teachersVarietyLabel => '品种';

  @override
  String get teachersDirectionLabel => '方向（买/卖）';

  @override
  String get teachersPnlLabel => '盈亏';

  @override
  String get teachersNoScreenshotSelected => '未选择截图';

  @override
  String get teachersSelectScreenshot => '选择截图';

  @override
  String get teachersTradeRecordSaved => '交易记录已保存';

  @override
  String get teachersTeacherCenter => '交易员中心';

  @override
  String get teachersPleaseLoginFirst => '请先登录';

  @override
  String get teachersStrategyTab => '策略';

  @override
  String get teachersQuoteAndTradeTab => '行情与交易';

  @override
  String get teachersOrderTab => '委托';

  @override
  String get teachersHistoryOrderTab => '历史委托';

  @override
  String get teachersFillsAndPositionsTab => '成交与持仓';

  @override
  String get teachersBasicInfo => '基本信息';

  @override
  String get teachersNoNicknameSet => '未设置昵称';

  @override
  String get teachersAvatarNicknameHint => '头像/昵称与账号资料保持一致';

  @override
  String get teachersRealNameRequired => '真实姓名（必填）';

  @override
  String get teachersProfessionalTitle => '专业职称/头衔';

  @override
  String get teachersOrgCompany => '所在机构/公司';

  @override
  String get teachersCountryRegion => '国家/地区';

  @override
  String get teachersYearsExperience => '从业年限';

  @override
  String get teachersYearsAbove20 => '20 年以上';

  @override
  String teachersYearsFormat(int n) {
    return '$n 年';
  }

  @override
  String get teachersTradingBackground => '交易背景';

  @override
  String get teachersMainMarketLabel => '主要市场（股票/期权/期货/外汇/加密）';

  @override
  String get teachersMainVariety => '主要交易品种/行业';

  @override
  String get teachersRiskPreference => '风险偏好';

  @override
  String get teachersExpertiseVariety => '擅长品种（逗号分隔）';

  @override
  String get teachersQualificationCompliance => '资质与合规（可选）';

  @override
  String get teachersQualificationCert => '资质/证书（如 CFA/Series 7/Series 65）';

  @override
  String get teachersBrokerLabel => '合作券商/交易平台';

  @override
  String get teachersPerformanceIntro => '业绩与简介';

  @override
  String get teachersPerformanceLabel => '业绩说明（如近一年收益/最大回撤）';

  @override
  String get teachersIdVerification => '身份核验（建议上传）';

  @override
  String get teachersCountryOptions =>
      '美国, 中国, 中国香港, 新加坡, 英国, 加拿大, 澳大利亚, 日本, 韩国, 德国, 法国, 阿联酋, 其他';

  @override
  String get teachersCityLabel => '城市';

  @override
  String get teachersTradingStyle => '交易风格';

  @override
  String get strategiesFullStrategy => '完整投资策略';

  @override
  String get strategiesPageTitle => '交易策略节目';

  @override
  String get strategiesTodayStrategies => '今日投资策略';

  @override
  String get strategiesHistoryStrategies => '历史投资策略';

  @override
  String get strategiesNoHistory => '暂无历史策略';

  @override
  String get featuredNoStrategyContent => '暂无策略内容';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageChinese => '简体中文';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get messagesLoginToUseChat => '登录后使用聊天功能';

  @override
  String get messagesLoginMethods => '支持邮箱、Google、Apple 登录';

  @override
  String get messagesAddFriend => '添加好友';

  @override
  String get addFriendScanQr => '扫码添加';

  @override
  String get addFriendMyQrCode => '我的二维码';

  @override
  String get addFriendHintEmail => '请输入对方注册邮箱';

  @override
  String get addFriendHintId => '请输入对方账号 ID';

  @override
  String get commonAdd => '添加';

  @override
  String get featuredFollowTrader => '关注交易员';

  @override
  String get promoEnterSelectTrader => '进入选择交易员';

  @override
  String get messagesCreateGroup => '创建群聊';

  @override
  String get messagesSystemNotifications => '系统消息';

  @override
  String get messagesSearchConversations => '搜索会话';

  @override
  String get messagesSearchFriends => '搜索好友';

  @override
  String get messagesRecentChats => '最近会话';

  @override
  String get messagesFriendList => '好友列表';

  @override
  String get messagesFirebaseNotConfigured => '未配置 Firebase';

  @override
  String get messagesAddConfigFirst => '请先添加配置文件后再使用消息功能';

  @override
  String get messagesSupabaseNotConfigured => '未配置 Supabase';

  @override
  String get messagesConfigureSupabase =>
      '请配置 SUPABASE_URL / SUPABASE_ANON_KEY';

  @override
  String get messagesApiNotConfigured => '未配置后端 API';

  @override
  String get messagesConfigureApi => '请配置 TONGXIN_API_URL 并确保后端已启动';

  @override
  String get marketTitle => '市场';

  @override
  String get marketTabHome => '首页';

  @override
  String get marketTabUsStock => '美股';

  @override
  String get marketTabForex => '外汇';

  @override
  String get marketTabCrypto => '加密货币';

  @override
  String get marketMajorIndexes => 'Major Indexes';

  @override
  String get marketTopMovers => 'Top Movers';

  @override
  String get marketGainers => 'Gainers';

  @override
  String get marketLosers => 'Losers';

  @override
  String get marketSearchSymbols => 'Search symbols';

  @override
  String get marketGainersList => '涨幅榜';

  @override
  String get marketLosersList => '跌幅榜';

  @override
  String get marketNoForexData => '暂无外汇数据';

  @override
  String get marketLoadingUsStockList => '正在加载全量美股列表…';

  @override
  String get marketLoadingQuote => '正在加载行情…';

  @override
  String get marketNoUsStockList => '暂无美股列表';

  @override
  String get marketStockOrCryptoSearch => '股票或加密货币名称、代码';

  @override
  String get rankingsPromo1Title => '跟对导师，收益可见';

  @override
  String get rankingsPromo1Subtitle => '策略透明 · 实盘可跟 · 每月收益一目了然';

  @override
  String get rankingsPromo2Title => '真人实盘，有据可查';

  @override
  String get rankingsPromo2Subtitle => '实名认证导师 · 胜率与盈亏全程可追踪';

  @override
  String get rankingsPromo3Title => '每月榜单，谁在领跑';

  @override
  String get rankingsPromo3Subtitle => '本月收益排行 · 一键关注 · 跟单不迷路';

  @override
  String get rankingsLearnMore => '了解更多';

  @override
  String get rankingsMentorVerified => '导师实名认证';

  @override
  String get rankingsStrategyTraceable => '策略与收益可追踪';

  @override
  String get rankingsCommunitySupport => '学员互动与社群支持';

  @override
  String get rankingsMonthProfitRank => '本月收益排行榜';

  @override
  String get rankingsRealtimeTransparent => '实时 · 透明';

  @override
  String get teachersNoStrategy => '暂无策略';

  @override
  String get marketIndexDowJones => '道琼斯';

  @override
  String get marketIndexNasdaq => '纳斯达克';

  @override
  String get marketIndexSp500 => '标普500';

  @override
  String get marketAll => '全部';

  @override
  String get marketNoWatchlist => '暂无自选';

  @override
  String get marketAddWatchlistHint => '在搜索或详情页可添加自选';

  @override
  String get marketGoAdd => '去添加';

  @override
  String get marketThreeIndices => '三大指数';

  @override
  String get marketWatchlist => '自选';

  @override
  String get marketMockDataHint => '当前为模拟数据。配置 TWELVE_DATA_API_KEY 后可显示真实行情。';

  @override
  String get marketNoDataConfigHint => '暂无数据，请配置 TWELVE_DATA_API_KEY 或稍后重试';

  @override
  String get marketGlobalIndices => '环球指数';

  @override
  String get marketNews => '资讯';

  @override
  String marketQuoteLoadFailed(String error) {
    return '报价拉取失败：$error';
  }

  @override
  String get marketConnectFailed =>
      '无法连接行情服务，请确认后端已启动（如 http://localhost:3000）';

  @override
  String get marketStockQuoteCacheEmpty =>
      'stock_quote_cache 表暂无数据，请确认后端已配置并实时更新该表';

  @override
  String get marketCsvHeader => '代码,名称,涨跌幅,最新价,涨跌额,今开,昨收,最高,最低,成交量';

  @override
  String get marketMockDataPcHint =>
      '当前为模拟数据，仅作界面展示。配置 POLYGON_API_KEY 后可显示真实行情。';

  @override
  String get marketExportCsv => '导出 CSV';

  @override
  String get marketHotNews => '热点解读';

  @override
  String get marketSubscribeTopic => '订阅专题';

  @override
  String get marketTradableCoins => '可交易币种';

  @override
  String get marketMarketCap => '市值';

  @override
  String get marketTopGainers => '领涨榜';

  @override
  String get marketTopLosers => '领跌榜';

  @override
  String get authEmail => '邮箱';

  @override
  String get authThirdPartyLogin => '第三方登录';

  @override
  String get authGoogleLogin => 'Google 登录';

  @override
  String get authAppleLogin => 'Apple 登录';

  @override
  String get authRegisterAndSendEmail => '注册并发送验证邮件';

  @override
  String get authConfirmPassword => '确认密码';

  @override
  String get authRegister => '注册';

  @override
  String get authName => '姓名';

  @override
  String get authSendVerificationEmail => '发送验证邮件';

  @override
  String authSendVerificationEmailCooldown(int seconds) {
    return '发送验证邮件（${seconds}s）';
  }

  @override
  String get authFirebaseConfigHint =>
      '尚未配置 Firebase，请先添加配置文件（google-services.json / GoogleService-Info.plist）。';

  @override
  String get authVerificationSent => '已发送验证邮件，请验证后再登录';

  @override
  String get authFillNameEmailPassword => '请先填写姓名、邮箱和两次密码';

  @override
  String get authPasswordMismatch => '两次密码不一致';

  @override
  String get authPasswordMinLength => '密码至少 6 位';

  @override
  String authResendCooldown(int seconds) {
    return '请稍后再试（${seconds}s）';
  }

  @override
  String get authVerificationEmailSent => '验证邮件已发送，请检查邮箱';

  @override
  String get authMacosUseEmailOrGoogle => 'macOS 端请使用邮箱或 Google 登录。';

  @override
  String get authWebAppleLimited => 'Web 端 Apple 登录受限，请使用邮箱或 Google。';

  @override
  String get teachersNoRecord => '暂无交易记录';

  @override
  String get teachersUploadRecord => '上传记录';

  @override
  String get teachersOffline => '下架';

  @override
  String get teachersOnline => '上架';

  @override
  String teachersFrozenOrBlocked(String status) {
    return '您当前处于$status状态，无法上传交易记录';
  }

  @override
  String get teachersFrozen => '冻结';

  @override
  String get teachersBlocked => '封禁';

  @override
  String get teachersReviewRequired => '审核通过后开放交易记录上传';

  @override
  String get teachersConfirmRiskAck => '请确认已阅读风险提示';

  @override
  String get teachersRecordSaved => '交易记录已保存';

  @override
  String get teachersTradeRecordSymbol => '品种';

  @override
  String get teachersTradeRecordSide => '方向（买/卖）';

  @override
  String get teachersTradeRecordPnl => '盈亏';

  @override
  String get teachersUploadQualification => '上传资质照片';

  @override
  String get teachersUploadIdPhoto => '上传证件照';

  @override
  String get teachersUploadCertification => '上传资质证明';

  @override
  String get teachersRiskAckTitle => '我已阅读并同意风险提示';

  @override
  String get teachersPreviewHomepage => '预览主页';

  @override
  String get marketMore => '更多';

  @override
  String get marketMajorIndices => '主要指数';

  @override
  String get marketGainersLosers => '涨跌榜';

  @override
  String get marketCrypto => '加密货币';

  @override
  String get marketName => '名称';

  @override
  String get marketLatestPrice => '最新价';

  @override
  String get marketChangePct => '涨跌幅';

  @override
  String get marketChangeAmount => '涨跌额';

  @override
  String get marketOpen => '今开';

  @override
  String get marketPrevClose => '昨收';

  @override
  String get marketHigh => '最高';

  @override
  String get marketLow => '最低';

  @override
  String get marketVolume => '成交量';

  @override
  String get marketTurnover => '成交额';

  @override
  String get marketCode => '代码';

  @override
  String get marketChange => '涨跌额';

  @override
  String get marketHeatmap => '市场热度 Heatmap';

  @override
  String get marketTradeSubcategory => '交易子类';

  @override
  String get marketHot => '热门';

  @override
  String get marketGoSearch => '去搜索';

  @override
  String get tradingRecords => '交易记录';

  @override
  String get tradingBuyApiPending => '买入功能待接入行情 API';

  @override
  String get tradingSellApiPending => '卖出功能待接入行情 API';

  @override
  String get tradingRecordAdded => '已添加一条交易记录';

  @override
  String get tradingDeleteRecord => '删除记录';

  @override
  String get tradingConfirmDeleteRecord => '确定删除这条交易记录？';

  @override
  String get tradingDelete => '删除';

  @override
  String get tradingFillSymbol => '请填写股票代码';

  @override
  String get tradingFillPriceQty => '请填写有效的价格与数量';

  @override
  String get tradingSymbolHint => '输入股票代码或名称';

  @override
  String get tradingSymbolLabel => '标的';

  @override
  String get orderClear => '清除';

  @override
  String orderConfirmCancel(String symbol, String action) {
    return '确定要撤销 $symbol 的$action委托吗？';
  }

  @override
  String get orderCancelSuccess => '已撤单（模拟）';

  @override
  String get orderCancelBuy => '买入';

  @override
  String get orderCancelSell => '卖出';

  @override
  String get chartVolume => '量';

  @override
  String get chartPrevClose => '昨收线';

  @override
  String get chartOverlay => '主图叠加';

  @override
  String get chartSubIndicator => '副图指标';

  @override
  String get chartCurrentValue => '当前数值';

  @override
  String get chartYes => '有';

  @override
  String get chartNo => '无';

  @override
  String get chartBackToLatest => '回最新';

  @override
  String get commonOpening => '正在打开…';

  @override
  String get commonFeatureDeveloping => '功能正在开发中';

  @override
  String get teachersNoTeachers => '暂无交易员';

  @override
  String get teachersTeacherHomepage => '交易员主页';

  @override
  String get teachersBecomeTeacher => '成为交易员';

  @override
  String get teachersHomepage => '主页';

  @override
  String get teachersNoTeacherInfo => '暂无交易员信息';

  @override
  String get teachersNone => '暂无';

  @override
  String get callOtherCancelled => '对方已取消';

  @override
  String get callOtherRejected => '对方已拒绝';

  @override
  String get callOtherHangup => '对方已挂断';

  @override
  String get callPleaseHangup => '请点击挂断按钮结束通话';

  @override
  String get callHangup => '挂断';

  @override
  String get callWaiting => '等待对方接听...';

  @override
  String get callJoinFailed => '加入通话失败';

  @override
  String get callFlipCamera => '翻转';

  @override
  String get callSpeaker => '扬声器';

  @override
  String get callEarpiece => '听筒';

  @override
  String get callCheckNetwork => '若听不到声音请检查网络';

  @override
  String get callMute => '静音';

  @override
  String get callUnmute => '取消静音';

  @override
  String get notificationFullScreenHint => '请在设置页开启「全屏 intent」开关';

  @override
  String get notificationNotEnabled => '通知未开启';

  @override
  String get notificationGoToAuth => '去授权';

  @override
  String get notificationGoToSettings => '去设置';

  @override
  String get appDownloadComing => '下载地址敬请期待';

  @override
  String get appDownloadOpenFailed => '无法打开下载页';

  @override
  String get chatFileExpired => '文件已过期或不存在，请让对方重新发送';

  @override
  String searchAddedToWatchlist(String symbol) {
    return '已添加 $symbol 到自选';
  }

  @override
  String marketCopyCsvSuccess(int count) {
    return '已复制 $count 条到剪贴板（CSV）';
  }

  @override
  String get msgFriendRequestAccepted => '已通过，已添加为好友';

  @override
  String get msgAcceptFailed => '通过失败';

  @override
  String get msgRejectFailed => '拒绝失败';

  @override
  String get msgSystemNotificationsEmptyHint => '好友申请、通过/拒绝记录会显示在这里';

  @override
  String get msgNoSystemNotifications => '暂无系统消息';

  @override
  String get msgPendingOther => '待对方处理';

  @override
  String get msgRequestAddYou => '请求添加你为好友';

  @override
  String get msgAccepted => '已通过';

  @override
  String get msgRejected => '已拒绝';

  @override
  String get msgYouRequestAddFriend => '你请求添加 Ta 为好友';

  @override
  String get msgAcceptShort => '通过';

  @override
  String get msgFriendRequestRejected => '已拒绝好友申请';

  @override
  String get msgOpenChatFailed => '打开私聊失败，请重试';

  @override
  String get msgOpenChatFailedPrefix => '打开私聊失败';

  @override
  String msgConfirmDeleteFriend(String name) {
    return '确定删除 $name 吗？';
  }

  @override
  String get msgFriendDeleted => '好友已删除';

  @override
  String get msgFriendRequestSent => '已发送好友申请';

  @override
  String get msgSendMessage => '发消息';

  @override
  String get profilePersonalInfo => '个人资料';

  @override
  String get profileItsYou => '这是你自己';

  @override
  String get msgSelectGroup => '请从左侧选择用户';

  @override
  String groupConfirmTransfer(String name) {
    return '确定将群主转让给 $name？转让后您将变为管理员。';
  }

  @override
  String get groupTransferSuccess => '已转让群主';

  @override
  String get groupMemberRemoved => '已移出群聊';

  @override
  String get groupRemove => '移除（踢出群聊）';

  @override
  String get groupTransferOwner => '转让群主';

  @override
  String get groupSetAdmin => '设为管理员';

  @override
  String get groupUnsetAdmin => '取消管理员';

  @override
  String groupConfirmCount(int count) {
    return '确定($count)';
  }

  @override
  String get groupSelectFriends => '选择好友';

  @override
  String get pcSearchHint => '搜索…';

  @override
  String get orderNoHistory => '暂无历史委托';

  @override
  String get orderDate => '日期';

  @override
  String get orderPrice => '委托价';

  @override
  String get orderFilled => '已成交';

  @override
  String get orderSimulated => '（模拟数据）';

  @override
  String get orderStatusPending => '待成交';

  @override
  String get orderStatusPartial => '部分成交';

  @override
  String get orderStatusCancelled => '已撤单';

  @override
  String get orderStatusRejected => '已拒绝';

  @override
  String get tradesFillsRecord => '成交记录';

  @override
  String get tradesCurrentPositions => '当前持仓';

  @override
  String get tradesNoFills => '暂无成交记录';

  @override
  String get tradesNoPosition => '暂无持仓';

  @override
  String get tradesLoadPositionsFailed => '加载持仓失败';

  @override
  String get tradesPositionShares => '持仓';

  @override
  String get tradesPnl => '盈亏';

  @override
  String tradesQuickSellPending(String symbol) {
    return '快捷卖出 $symbol（待接入）';
  }

  @override
  String tradesSellPending(String symbol) {
    return '卖出 $symbol（待接入）';
  }

  @override
  String get teachersProfileTitle => '交易员资料';

  @override
  String get teachersPersonalIntro => '个人介绍';

  @override
  String get teachersExpertiseProducts => '擅长品种';

  @override
  String get teachersStrategySection => '交易策略';

  @override
  String get teachersNoPublicStrategy => '暂无公开策略';

  @override
  String get teachersEnterStrategyCenter => '进入交易策略中心';

  @override
  String teachersFollowingCount(int count) {
    return '关注 $count';
  }

  @override
  String get teachersSignatureLabel => '个性签名';

  @override
  String get teachersLicenseNoLabel => '执照/注册编号';

  @override
  String get teachersMainMarket => '主要市场';

  @override
  String get teachersTradingStyleShort => '交易风格';

  @override
  String get teachersRecordAndEarnings => '战绩与收益';

  @override
  String get teachersTotalEarnings => '总收益';

  @override
  String get teachersMonthlyEarnings => '月收益';

  @override
  String get teachersRatingLabel => '评分';

  @override
  String get teachersPerformanceSection => '战绩表现';

  @override
  String get teachersIntroSection => '个人介绍';

  @override
  String get teachersLatestArticles => '最新文章';

  @override
  String get teachersRecentSchedule => '近期行程';

  @override
  String get msgGroupChat => '群聊';

  @override
  String msgGroupChatN(int n) {
    return '群聊($n人)';
  }

  @override
  String get msgViewTraderProfile => '查看交易员资料';

  @override
  String msgExitedGroup(String name) {
    return '$name 退出了群聊';
  }

  @override
  String msgJoinedGroup(String name) {
    return '$name 加入了群聊';
  }

  @override
  String get msgAddFriend => '加好友';

  @override
  String get msgAlreadyFriends => '你们已是好友';

  @override
  String get msgAlreadyPending => '已发送过申请，请等待对方处理';

  @override
  String get msgAddFriendFailed => '加好友失败';

  @override
  String get msgMePrefix => '我: ';

  @override
  String get msgDraft => '草稿：';

  @override
  String get msgOpenChatFromList => '打开私聊失败，请从消息列表进入';

  @override
  String get teachersMyTradeRecords => '我的交易记录';

  @override
  String get teachersNoTradeRecords => '暂无交易记录';

  @override
  String get teachersNoIntro => '暂无介绍';

  @override
  String get msgPrivateChat => '私聊';

  @override
  String get groupCreateGroup => '创建群聊';

  @override
  String get groupCreateFailed => '创建失败';

  @override
  String get groupCreateGroupHint => '不填则显示为「群聊(n人)」';

  @override
  String get groupCreateGroupButton => '创建群聊';

  @override
  String groupCreateGroupButtonN(int n) {
    return '创建群聊($n人)';
  }

  @override
  String get groupGroupNameLabel => '群名称（可选）';

  @override
  String get groupNoFriendsHint => '暂无好友，请先添加好友';

  @override
  String get groupSelectAtLeastOne => '请至少选择一位好友';

  @override
  String get groupLeaveConfirm => '确定退出该群聊？';

  @override
  String get groupLeaveSuccess => '已退出群聊';

  @override
  String get groupDismissConfirm => '确定解散该群聊？所有成员将退出，聊天记录将无法恢复。';

  @override
  String get groupDismissSuccess => '群聊已解散';

  @override
  String get groupRemoveConfirm => '确定将该成员移出群聊？';

  @override
  String get groupSettingsTitle => '群设置';

  @override
  String get groupGroupName => '群名称';

  @override
  String get groupAnnouncement => '群公告';

  @override
  String get groupMute => '消息免打扰';

  @override
  String get groupInviteMembers => '邀请新成员';

  @override
  String get groupInviteLink => '群邀请链接';

  @override
  String groupMembersCount(int count) {
    return '群成员 ($count)';
  }

  @override
  String get groupLeave => '退出群聊';

  @override
  String get groupDismiss => '解散群聊';

  @override
  String get groupRemoveMember => '移除成员';

  @override
  String get groupRemoveAction => '移除';

  @override
  String groupSetAdminConfirm(String name) {
    return '确定将 $name 设为管理员？';
  }

  @override
  String groupUnsetAdminConfirm(String name) {
    return '确定取消 $name 的管理员身份？';
  }

  @override
  String get groupSaveFailed => '保存失败';

  @override
  String get groupLeaveFailed => '退出失败';

  @override
  String get groupDismissFailed => '解散失败';

  @override
  String get groupOperationFailed => '操作失败';

  @override
  String get groupJoinLoginFirst => '请先登录后再加入群聊';

  @override
  String get groupJoinTitle => '加入群聊';

  @override
  String get groupJoinConfirm => '确定要加入该群聊吗？';

  @override
  String get groupJoinSuccess => '已加入群聊，请在消息列表查看';

  @override
  String get groupJoinFailed => '加入失败';

  @override
  String get commonNone => '暂无';

  @override
  String get commonLeave => '退出';

  @override
  String get commonDismiss => '解散';

  @override
  String get commonSuccess => '成功';

  @override
  String get chatNoMatchingMembers => '暂无匹配成员';

  @override
  String get chatNotFriendCannotSend => '已不是好友，无法发送';

  @override
  String get chatRecordingTooShort => '录音时间太短';

  @override
  String get chatGrantMicPermission => '请授予麦克风权限';

  @override
  String get chatNoSupabaseCannotSendMedia => '未配置 Supabase，无法发送媒体';

  @override
  String get chatFileEmptyCannotSend => '文件为空，无法发送';

  @override
  String get chatSendFailedPrefix => '发送失败';

  @override
  String get chatCannotReadFile => '无法读取该文件';

  @override
  String get chatSelectFileFailed => '选择文件失败';

  @override
  String get chatForwardInDevelopment => '转发功能正在开发中';

  @override
  String get chatRecalled => '已撤回';

  @override
  String get chatRecallFailedPrefix => '撤回失败';

  @override
  String get chatCallLabel => '通话';

  @override
  String get chatFileSendFailedPrefix => '文件发送失败';

  @override
  String get chatRemarkSaved => '备注已保存';

  @override
  String get chatUnpinned => '已取消置顶';

  @override
  String get chatPinned => '已置顶会话';

  @override
  String get chatHistoryCleared => '已清空聊天记录';

  @override
  String get chatClearFailedPrefix => '清空失败';

  @override
  String get chatJustNow => '刚刚';

  @override
  String get chatToday => '今天';

  @override
  String get chatYesterday => '昨天';

  @override
  String get chatUnknown => '未知';

  @override
  String get chatLastOnline => '最后上线：';

  @override
  String get chatNoNetworkNoCache => '无网络，暂无本地缓存';

  @override
  String get chatNoMessagesYet => '还没有聊天记录';

  @override
  String get chatRecordingReleaseToSend => '录音中…松开发送';

  @override
  String get chatKeyboard => '键盘';

  @override
  String get chatVoice => '语音';

  @override
  String get chatHoldToSpeak => '按住 说话';

  @override
  String get chatReleaseToSend => '松开发送';

  @override
  String get chatAnswered => '已接听';

  @override
  String get chatDeclined => '已拒绝';

  @override
  String get chatCancelled => '已取消';

  @override
  String get chatMissed => '未接听';

  @override
  String get chatVoiceCall => '语音通话';

  @override
  String get chatVideoCall => '视频通话';

  @override
  String chatMeStatus(String status) {
    return '我 · $status';
  }

  @override
  String chatOtherStatus(String status) {
    return '对方 · $status';
  }

  @override
  String get chatOpening => '正在打开…';

  @override
  String get chatCannotOpenFile => '无法打开该文件';

  @override
  String get chatVideoLoadFailedPrefix => '视频加载失败';

  @override
  String chatMinutesAgo(int count) {
    return '$count分钟前';
  }

  @override
  String chatTodayAt(String time) {
    return '今天 $time';
  }

  @override
  String chatYesterdayAt(String time) {
    return '昨天 $time';
  }

  @override
  String chatDaysAgo(int count) {
    return '$count天前';
  }

  @override
  String chatDateMonthDay(int month, int day, String time) {
    return '$month月$day日 $time';
  }

  @override
  String chatDateFull(int year, int month, int day) {
    return '$year年$month月$day日';
  }

  @override
  String get chatLastOnlineLabel => '最后上线：';

  @override
  String get chatWebRecordingNotSupported => 'Web 暂不支持录音';

  @override
  String get chatWebFileNotSupported => 'Web 暂不支持发送文件';

  @override
  String get chatFileExpiredOrNotExist => '文件已过期或不存在，请让对方重新发送';

  @override
  String get chatTypeImage => '[图片]';

  @override
  String get chatTypeVideo => '[视频]';

  @override
  String get chatTypeAudio => '[语音]';

  @override
  String get chatTypeFile => '[文件]';

  @override
  String get chatTeacherCard => '[交易员名片]';

  @override
  String get groupInviteFriends => '邀请好友进群';

  @override
  String get groupInviteFriendHint => '好友打开链接或扫描二维码即可申请加入';

  @override
  String groupInviteFriendHintWithName(String name) {
    return '好友打开链接或扫描二维码即可申请加入「$name」';
  }

  @override
  String get groupCopyInviteLink => '复制邀请链接';

  @override
  String groupClickLinkToJoin(String link) {
    return '点击此链接加入群：$link';
  }

  @override
  String get groupLinkCopied => '链接已复制，好友点击链接即可加入群';

  @override
  String get groupQrInvite => '二维码邀请';

  @override
  String get groupQrCopied => '扫码加入群';

  @override
  String get groupAppNotInstalled => '未安装 App？前往下载';

  @override
  String get groupAppNotInstalledSubtitle => '好友未安装时可引导其下载';

  @override
  String groupScanToJoin(String name) {
    return '扫码加入「$name」';
  }

  @override
  String get groupScanWithApp => '好友使用本 App 扫一扫即可进群';

  @override
  String get groupClose => '关闭';

  @override
  String get groupOwner => '群主';

  @override
  String get groupNoFriendsToInvite => '没有可邀请的好友';

  @override
  String groupInvitedCount(int count) {
    return '已邀请 $count 人';
  }

  @override
  String get groupInviteFailedPrefix => '邀请失败';

  @override
  String get groupEditName => '修改群名称';

  @override
  String get groupNameHint => '群名称';

  @override
  String get groupNameUpdated => '群名称已更新';

  @override
  String get groupMuteOn => '已开启消息免打扰';

  @override
  String get groupMuteOff => '已关闭消息免打扰';

  @override
  String get groupNoSupabaseUpload => '未配置 Supabase，无法上传';

  @override
  String get groupAvatarUpdated => '群头像已更新';

  @override
  String get groupUploadFailedPrefix => '上传失败';

  @override
  String get groupShortLabel => '群';

  @override
  String get groupEditAnnouncement => '群公告';

  @override
  String get groupAnnouncementHint => '输入群公告';

  @override
  String get groupAnnouncementUpdated => '群公告已更新';

  @override
  String get groupLoadFailedPrefix => '加载失败';

  @override
  String get groupLoadError => '无法加载群信息';

  @override
  String get groupInviteNewMembers => '邀请新成员';

  @override
  String groupConfirmCountShort(int count) {
    return '确定($count)';
  }

  @override
  String groupMemberListTitle(int count) {
    return '群成员 ($count)';
  }

  @override
  String get groupRoleOwner => '群主';

  @override
  String get groupRoleAdmin => '管理员';

  @override
  String get groupMemberHint => '点击右侧 ⋮ 可移出、转让群主、设管理员';

  @override
  String get ordersConfirmCancel => '确认撤单';

  @override
  String get ordersTodayOrders => '当日委托';

  @override
  String get ordersNoTodayOrders => '暂无当日委托';

  @override
  String get ordersOrderPrice => '委托价';

  @override
  String get ordersQuantity => '数量';

  @override
  String get ordersFilled => '已成交';

  @override
  String get ordersCancelOrder => '撤单';

  @override
  String get ordersStatusPending => '待成交';

  @override
  String get ordersStatusPartial => '部分成交';

  @override
  String get ordersStatusFilled => '已成交';

  @override
  String get ordersStatusCancelled => '已撤单';

  @override
  String get ordersStatusRejected => '已拒绝';

  @override
  String get ordersBuy => '买入';

  @override
  String get ordersSell => '卖出';

  @override
  String get ordersMarket => '市价';

  @override
  String get marketGainersLosersTitle => '涨跌榜';

  @override
  String get marketThreeIndicesLabel => '三大指数';

  @override
  String get marketNameLabel => '名称';

  @override
  String get msgNewFriendRequest => '你有一条新的好友申请';

  @override
  String msgNewFriendRequests(int count) {
    return '你有 $count 条新的好友申请';
  }

  @override
  String get msgNoNicknameSet => '未设置昵称';

  @override
  String get msgSearchHint => '搜索好友/备注/账号ID';

  @override
  String get msgShowBlacklist => '显示黑名单';

  @override
  String get msgHideBlacklist => '隐藏黑名单';

  @override
  String get msgBlacklist => '黑名单';

  @override
  String get msgBlocked => '已拉黑';

  @override
  String get msgRemoveFromBlacklist => '移出黑名单';

  @override
  String get msgAddToBlacklist => '加入黑名单';

  @override
  String get msgDeleteFriend => '删除好友';

  @override
  String get msgSetRemark => '设置备注名';

  @override
  String get msgRemarkHint => '输入备注名';

  @override
  String get msgNoConversations => '暂无会话';

  @override
  String get msgNoMatchingConversations => '未找到匹配的会话';

  @override
  String get msgFriendRequest => '好友申请';

  @override
  String get msgNoFriends => '暂无好友';

  @override
  String get msgOnline => '在线';

  @override
  String get msgOffline => '离线';

  @override
  String get msgFeatureDeveloping => '功能正在开发中';

  @override
  String get msgUnpin => '取消置顶';

  @override
  String get msgPin => '置顶';

  @override
  String get msgDeleteConversation => '删除会话';

  @override
  String msgDeleteFriendConfirm(String name) {
    return '确定删除 $name 吗？';
  }

  @override
  String get msgDelete => '删除';

  @override
  String get msgSelectConversation => '选择会话开始聊天';

  @override
  String get msgClickLeftToOpen => '在左侧点击任一会话即可打开';

  @override
  String get msgMore => '更多';

  @override
  String get msgDecline => '拒绝';

  @override
  String get msgAccept => '同意';

  @override
  String get msgOperationFailed => '操作失败';

  @override
  String get msgSearchFailed => '搜索失败';

  @override
  String get msgSendFailed => '发送失败';

  @override
  String get msgAcceptFriendSuccess => '已同意好友申请';

  @override
  String get msgRejectFriendSuccess => '已拒绝好友申请';

  @override
  String get tradingCurrentPositions => '当前持仓';

  @override
  String get tradingMyRecords => '我的交易记录';

  @override
  String get tradingNoRecordsAdd => '暂无记录，点击右下角 + 添加';

  @override
  String get tradingRealtimeQuote => '实时行情';

  @override
  String get tradingCurrentPrice => '当前价';

  @override
  String get tradingChangePct => '涨跌幅';

  @override
  String get tradingAddRecord => '添加交易记录';

  @override
  String get tradingStockCode => '股票代码';

  @override
  String get tradingStockName => '股票名称';

  @override
  String get tradingBuyTime => '买入时机';

  @override
  String get tradingBuyPrice => '买入价格';

  @override
  String get tradingBuyQty => '买入数量';

  @override
  String get tradingSellTime => '卖出时间';

  @override
  String get tradingSellPrice => '卖出价格';

  @override
  String get tradingSellQty => '卖出数量';

  @override
  String get tradingCost => '成本';

  @override
  String get tradingCurrentPriceLabel => '现价';

  @override
  String get tradingHintStockCode => '如 600519';

  @override
  String get tradingHintStockName => '选填，如 贵州茅台';

  @override
  String get tradingQty => '数量';

  @override
  String get tradingPnl => '盈亏';

  @override
  String get tradingHintYuan => '元';

  @override
  String get tradingHintShares => '股/手';

  @override
  String get searchUsStock => '美股';

  @override
  String get searchCrypto => '加密货币';

  @override
  String get searchForex => '外汇';

  @override
  String get searchIndex => '指数';

  @override
  String get searchHint => '股票或加密货币名称、代码';

  @override
  String get searchInputHint => '输入股票或加密货币名称、代码搜索';

  @override
  String searchNotFound(String query) {
    return '未找到「$query」相关标的';
  }

  @override
  String get searchAddWatchlist => '加自选';

  @override
  String get commonUnknown => '未知';

  @override
  String get commonUserInitial => '用';

  @override
  String get groupNewMember => '新成员';

  @override
  String get groupSomeUser => '某用户';

  @override
  String get commonListSeparator => '、';

  @override
  String get watchlistTitle => '自选';

  @override
  String get watchlistAdd => '添加';

  @override
  String get watchlistRemove => '移除自选';

  @override
  String get marketIndexDow => '道琼斯';

  @override
  String get marketRequestTimeout => '首页行情请求超时';

  @override
  String get chartNoData => '暂无数据';

  @override
  String get chartLoading => '加载中…';

  @override
  String get chartPreMarket => '未开市';

  @override
  String get chartClosed => '已收盘';

  @override
  String get chartIntraday => '盘中';

  @override
  String get chartPrice => '价';

  @override
  String get chartAvg => '均';

  @override
  String get chartChangeShort => '涨';

  @override
  String get chartVol => '量';

  @override
  String get chartTurnover => '额';

  @override
  String get chartFetching => '正在拉取数据…';

  @override
  String chartFetchingWithLabel(String label) {
    return '正在拉取$label数据…';
  }

  @override
  String get chartTimeshareLabel => '分时';

  @override
  String get chartKlineLabel => 'K线';

  @override
  String get chartChangePercent => '涨跌幅';

  @override
  String get chartEmptyHint => '分时与 K 线数据暂时无法加载，请稍后重试或检查数据源配置';

  @override
  String get chartNoIntradayData => '暂无分时数据';

  @override
  String get chartNoKlineData => '暂无K线数据';

  @override
  String get chartRetry => '重试';

  @override
  String get chartSwitchDataSource => '切换数据源';

  @override
  String get chartPriceOpen => '今开';

  @override
  String get chartPriceHigh => '最高';

  @override
  String get chartPriceLow => '最低';

  @override
  String get chartPricePrevClose => '昨收';

  @override
  String get chartPriceTotalTurnover => '总成交';

  @override
  String get chartPriceTurnoverRate => '换手率';

  @override
  String get chartPriceAmplitude => '振幅';

  @override
  String get chartStatsOpen => '开';

  @override
  String get chartStatsHigh => '高';

  @override
  String get chartStatsLow => '低';

  @override
  String get chartStatsClose => '收';

  @override
  String get chartStatsPrevClose => '昨收';

  @override
  String get chartStatsChange => '涨跌';

  @override
  String get chartStatsChangePct => '涨跌幅';

  @override
  String get chartStatsAmplitude => '振幅';

  @override
  String get chartStatsAvgPrice => '均价';

  @override
  String get chartStatsVolume => '成交量';

  @override
  String get chartStatsTurnover => '成交额';

  @override
  String get chartStatsDividendYield => '股息率';

  @override
  String get chartStatsTurnoverRate => '换手率';

  @override
  String get chartStatsPeTtm => '市盈率TTM';

  @override
  String get chartOrderBookSell => '卖一';

  @override
  String get chartOrderBookQty => '数量';

  @override
  String get chartOrderBookBuy => '买一';

  @override
  String get chartTabOrderBook => '盘口';

  @override
  String get chartTabIndicator => '指标';

  @override
  String get chartTabCapital => '资金';

  @override
  String get chartTabNews => '新闻';

  @override
  String get chartTabAnnouncement => '公告';

  @override
  String get chartIndicatorNone => '无';

  @override
  String get chartIndicatorYes => '有';

  @override
  String get chartIndicatorNo => '无';

  @override
  String get chartPrevCloseLine => '昨收线';

  @override
  String get chartMainOverlay => '主图叠加';

  @override
  String get chartQuoteLoadFailed => '加载失败';

  @override
  String get chartClickToClose => '点击图表关闭';

  @override
  String get chartMockDataHint => '模拟数据，仅作展示';

  @override
  String get chartCompanyActions => '公司行动';

  @override
  String get chartDividends => '分红';

  @override
  String get chartSplits => '拆股';

  @override
  String get chartQuoteRefreshHint => '每秒更新报价，图表每10秒刷新';

  @override
  String get chartOhlcHint => '下方为当日开、高、低、收等行情';

  @override
  String chartRequestFailed(String error) {
    return '请求失败: $error';
  }

  @override
  String get chartClickRetry => '点击刷新重试';

  @override
  String get chartNoDataTroubleshoot =>
      '若仍无数据：请确认后端已启动；真机/模拟器将 .env 中 TONGXIN_API_URL 改为本机 IP';

  @override
  String get chartNoChartData => '暂无图表数据';

  @override
  String get chartWeekK => '周K';

  @override
  String get chartMonthK => '月K';

  @override
  String get chartYearK => '年K';

  @override
  String get chart1Min => '1分';

  @override
  String get chart5Min => '5分';

  @override
  String get chart15Min => '15分';

  @override
  String get chart30Min => '30分';

  @override
  String get chart1min => '1分';

  @override
  String get chart5min => '5分';

  @override
  String get chart15min => '15分';

  @override
  String get chart30min => '30分';

  @override
  String get chartDayK => '日K';

  @override
  String get chartTimeshare => '分时';

  @override
  String get promoTitle => '金融培训机构\n专注实盘与策略落地';

  @override
  String get promoSubtitle => '资深导师带你建立策略体系，从认知到执行全面提升。';

  @override
  String get promoFeature1 => '导师认证与战绩公示';

  @override
  String get promoFeature2 => '每日策略与持仓跟踪';

  @override
  String get promoFeature3 => '同学互助与社群交流';

  @override
  String get promoCarouselTitle => '教学特色';

  @override
  String get promoSlide1Title => '量化与风控';

  @override
  String get promoSlide1Subtitle => '策略复盘 + 风控模型 + 实盘跟踪';

  @override
  String get promoSlide2Title => '资产配置';

  @override
  String get promoSlide2Subtitle => '多维度资产组合，稳健增值';

  @override
  String get promoSlide3Title => '导师陪跑';

  @override
  String get promoSlide3Subtitle => '每日策略解读与实操指导';

  @override
  String get promoBrand => '金融培训机构';

  @override
  String get notifChannelChat => '消息通知';

  @override
  String get notifChannelCall => '来电';

  @override
  String get notifOther => '对方';

  @override
  String notifInviteCall(String name, String type) {
    return '$name 邀请你$type通话';
  }

  @override
  String get notifVideoCall => '视频';

  @override
  String get notifVoiceCall => '语音';

  @override
  String get notifNewMessage => '新消息';

  @override
  String get notifNewMessageBody => '你收到一条新消息';

  @override
  String get notifFullScreenIntentHint => '请在设置页开启「全屏 intent」开关';

  @override
  String get notifNotEnabled => '通知未开启';

  @override
  String get notifPermissionDenied =>
      '您已拒绝通知权限，将无法收到新消息提醒。可点击「去授权」再次请求，或到系统设置中开启。';

  @override
  String get notifGoAuthorize => '去授权';

  @override
  String get notifGoSettings => '去设置';

  @override
  String get restrictStatusNormal => '账号状态：正常';

  @override
  String restrictBannedUntil(String date) {
    return '账号已封禁至 $date';
  }

  @override
  String restrictFrozenUntil(String date) {
    return '账号已冻结至 $date';
  }

  @override
  String get restrictLogin => '账号状态：已限制登录';

  @override
  String get restrictSendMessage => '账号状态：已限制发消息';

  @override
  String get restrictAddFriend => '账号状态：已禁止加好友';

  @override
  String get restrictJoinGroup => '账号状态：已禁止加入群聊';

  @override
  String get restrictCreateGroup => '账号状态：已禁止建群';

  @override
  String get adminOverview => '总览';

  @override
  String get adminUserManagement => '用户管理';

  @override
  String get adminTeacherReview => '交易员审核';

  @override
  String get adminSystemMessages => '系统消息';

  @override
  String get adminReports => '举报与审核';

  @override
  String get adminSettings => '系统设置';

  @override
  String get adminKeyMetrics => '关键指标与系统状态';

  @override
  String get adminTeachersTotal => '交易员总数';

  @override
  String get adminPending => '待审核';

  @override
  String get adminApproved => '已通过';

  @override
  String get adminRejected => '已驳回';

  @override
  String get adminFrozen => '已冻结';

  @override
  String get adminBlocked => '已封禁';

  @override
  String get adminSaved => '已保存';

  @override
  String get adminSaveFailed => '保存失败';

  @override
  String get adminUserProfile => '用户资料';

  @override
  String get adminRestrictAndBan => '限制与封禁';

  @override
  String adminBanUntil(String date) {
    return '封禁至 $date';
  }

  @override
  String adminFrozenUntil(String date) {
    return '冻结至 $date';
  }

  @override
  String get adminBan => '封禁';

  @override
  String get adminFreeze => '冻结';

  @override
  String get adminRestrictHint => '权限开关（开启即禁止该用户对应行为）';

  @override
  String get adminRestrictLogin => '限制登录';

  @override
  String get adminRestrictLoginSub => '禁止该账号登录';

  @override
  String get adminRestrictSendMessage => '限制发消息';

  @override
  String get adminRestrictAddFriend => '禁止加好友';

  @override
  String get adminRestrictJoinGroup => '禁止加入群聊';

  @override
  String get adminRestrictCreateGroup => '禁止建群';

  @override
  String get adminBanDuration => '封禁时长';

  @override
  String get adminFrozenDuration => '冻结时长';

  @override
  String get adminDays7 => '7 天';

  @override
  String get adminDays30 => '30 天';

  @override
  String get adminDays90 => '90 天';

  @override
  String get adminPermanent => '永久';

  @override
  String get adminSelectUser => '请从左侧选择用户';

  @override
  String get adminNoUserData => '暂无用户数据';

  @override
  String adminUsersCount(int count) {
    return '共 $count 人';
  }

  @override
  String get adminRefresh => '刷新';

  @override
  String get adminPlaceholderHint => '此模块已搭好框架，下一步接入数据与操作逻辑。';

  @override
  String get adminSystemMessagesDesc => '编辑系统公告、推送通知、运营消息模板。';

  @override
  String get adminReportsDesc => '处理用户举报、内容风控、违规记录。';

  @override
  String get adminSettingsDesc => '运营开关、基础配置、版本策略。';

  @override
  String get adminSystemMessagesHint => '建议接入 messages 与推送函数 send_push。';

  @override
  String get adminNickname => '昵称';

  @override
  String get adminShortId => '短号';

  @override
  String get adminRole => '角色';

  @override
  String get adminUserId => '用户 ID';

  @override
  String get adminSignature => '个性签名';

  @override
  String get adminProfileSaved => '资料已保存';

  @override
  String adminStatusUpdated(String label) {
    return '状态已更新为：$label';
  }

  @override
  String get adminUpdateFailed => '更新失败';

  @override
  String get adminSelectTeacher => '请选择交易员';

  @override
  String get adminPerformanceLabel => '业绩说明';

  @override
  String get adminIdPhotoLabel => '证件与资质照片';

  @override
  String get adminReviewCredentials => '审核资料（证件与资质）';

  @override
  String get adminSaveProfile => '保存资料';

  @override
  String get adminAddStrategy => '新增策略';

  @override
  String get adminAddTradeRecord => '新增交易记录';

  @override
  String get adminAddCurrentPosition => '新增当前持仓';

  @override
  String get adminAddHistoryPosition => '新增历史持仓';

  @override
  String get adminAddComment => '新增评论';

  @override
  String get adminAddArticle => '新增文章';

  @override
  String get adminAddSchedule => '新增日程';

  @override
  String get adminNotUploaded => '未上传';

  @override
  String get adminApprove => '审核通过';

  @override
  String get adminReject => '驳回';

  @override
  String get adminUnfreeze => '解除冻结';

  @override
  String get adminUnblock => '解除封禁';

  @override
  String get adminRevertToPending => '改为待审核';

  @override
  String get adminNotifyTraderResult => '交易员申请结果';

  @override
  String get adminNotifyRejected => '您的交易员申请已被驳回，可修改后重新提交。';

  @override
  String get adminNotifyApproved => '恭喜，您的交易员申请已通过，可以发布策略与交易记录。';

  @override
  String get adminNotifyBlocked => '您的交易员账号已被封禁，如有疑问请联系客服。';

  @override
  String get adminNotifyFrozen => '您的交易员账号已被冻结，冻结期内无法发布内容。';

  @override
  String get adminAll => '全部';

  @override
  String get adminPendingJustApplied => '待审核（刚刚申请）';

  @override
  String get adminAllTeachers => '全部交易员';

  @override
  String adminTeachersCount(int count) {
    return '共 $count 人';
  }

  @override
  String get adminRefreshList => '刷新列表';

  @override
  String get adminFilterByStatus => '按状态筛选';

  @override
  String get adminNoTeachersData => '暂无交易员数据';

  @override
  String get adminNoMatchingData => '暂无符合条件的数据';

  @override
  String get adminConfirmTableData => '请确认 teacher_profiles 表已有数据';

  @override
  String get adminTrySwitchAll => '可尝试切换「全部」查看';

  @override
  String get adminActionsByStatus => '操作（根据当前状态）';

  @override
  String get adminBasicInfo => '基础信息';

  @override
  String get adminDisplayName => '展示名';

  @override
  String get adminRealName => '真实姓名';

  @override
  String get adminTitlePosition => '职位/称号';

  @override
  String get adminOrg => '机构';

  @override
  String get adminBio => '个人简介';

  @override
  String get adminTags => '标签(逗号分隔)';

  @override
  String get adminLicenseNo => '执照/注册编号';

  @override
  String get adminCertifications => '资质/证书';

  @override
  String get adminMarkets => '主要市场';

  @override
  String get adminStyle => '交易风格';

  @override
  String get adminBroker => '合作券商/交易平台';

  @override
  String get adminCountry => '国家/地区';

  @override
  String get adminCity => '城市';

  @override
  String get adminYearsExperience => '从业年限';

  @override
  String get adminIdPhoto => '证件照';

  @override
  String get adminLicensePhoto => '资质证明';

  @override
  String get adminCertificationPhoto => '资质照片';

  @override
  String get adminPerformanceSection => '战绩与盈亏';

  @override
  String get adminWins => '胜场';

  @override
  String get adminLosses => '败场';

  @override
  String get adminRating => '评分';

  @override
  String get adminTodayStrategy => '今日策略';

  @override
  String get adminPnlCurrent => '本周总盈亏';

  @override
  String get adminPnlMonth => '年度盈亏';

  @override
  String get adminPnlYear => '总盈亏';

  @override
  String get adminPnlTotal => '累计盈亏';

  @override
  String get adminContentManagement => '内容管理';

  @override
  String get adminReviewActions => '审核操作（刚刚申请）';

  @override
  String get adminReviewActionsShort => '审核操作';

  @override
  String get adminDispose => '处置';

  @override
  String get adminConfirmReject => '确定驳回该申请？';

  @override
  String get adminConfirmBlock => '确定封禁该交易员？封禁后其主页将不在公域展示。';

  @override
  String adminFrozenUntilLabel(String date) {
    return '冻结至：$date';
  }

  @override
  String get adminConfirmUnfreeze => '确定解除冻结？';

  @override
  String get adminConfirmUnblock => '确定解除封禁？';

  @override
  String get adminRevertToPendingConfirm => '确定改为待审核？';

  @override
  String get adminSelectFreezeDuration => '请选择冻结时长：';

  @override
  String get adminFreezeDuration => '冻结时长';

  @override
  String get adminLoadFailed => '加载失败';

  @override
  String get adminTeacherDefault => '交易员';

  @override
  String get adminCurrentStatus => '当前状态：';

  @override
  String get adminFormLabelTitle => '标题';

  @override
  String get adminFormLabelSummary => '摘要';

  @override
  String get adminFormLabelContent => '内容';

  @override
  String get adminFormLabelAsset => '品种';

  @override
  String get adminFormLabelBuyTime => '买入时间(YYYY-MM-DD)';

  @override
  String get adminFormLabelBuyShares => '买入数量';

  @override
  String get adminFormLabelBuyPrice => '买入价';

  @override
  String get adminFormLabelSellTime => '卖出时间(YYYY-MM-DD)';

  @override
  String get adminFormLabelSellShares => '卖出数量';

  @override
  String get adminFormLabelSellPrice => '卖出价';

  @override
  String get adminFormLabelPnlRatio => '收益率%';

  @override
  String get adminFormLabelPnlAmount => '盈亏金额';

  @override
  String get adminFormLabelCostPrice => '成本价';

  @override
  String get adminFormLabelCurrentPrice => '现价';

  @override
  String get adminFormLabelFloatingPnl => '浮动盈亏';

  @override
  String get adminFormLabelUserName => '用户昵称';

  @override
  String get adminFormLabelLocation => '地点';

  @override
  String get adminFormLabelTime => '时间(YYYY-MM-DD)';

  @override
  String get adminFormLabelTimeSchedule => '时间(YYYY-MM-DD HH:MM)';

  @override
  String get adminFormLabelSellTimeHistory => '卖出时间(YYYY-MM-DD)';

  @override
  String get adminFormLabelSellPriceHistory => '卖出价格';

  @override
  String adminUnknownStatus(String raw) {
    return '未知状态: $raw，请检查数据库 status 字段是否为 pending/approved/rejected/frozen/blocked';
  }

  @override
  String get roleNormal => '普通用户';

  @override
  String get roleTrader => '交易员';

  @override
  String get roleAdmin => '管理员';

  @override
  String get roleVip => '会员';

  @override
  String get pcHome => '首页';

  @override
  String get pcNotify => '通知';

  @override
  String get pcGreetingHello => '你好';

  @override
  String get pcGreetingMorning => '上午好';

  @override
  String get pcGreetingAfternoon => '下午好';

  @override
  String get pcGreetingEvening => '晚上好';

  @override
  String get pcWelcomeBack => '欢迎回来，这是你的工作台概览';

  @override
  String get pcFollow => '关注';

  @override
  String get pcFollowSubtitle => '已关注标的';

  @override
  String get pcTodayChat => '今日会话';

  @override
  String get pcMessageCount => '消息数';

  @override
  String get pcWatchlist => '自选';

  @override
  String get pcWatchlistSubtitle => '自选标的';

  @override
  String get pcRanking => '排名';

  @override
  String get pcRankingSubtitle => '当前排名';

  @override
  String get pcMarket => '行情';

  @override
  String get pcMarketSubtitle => '查看市场与指数';

  @override
  String get pcManageWatchlist => '管理自选标的';

  @override
  String get pcMessages => '消息';

  @override
  String get pcMessagesSubtitle => '会话与好友';

  @override
  String get pcLeaderboard => '排行榜';

  @override
  String get pcLeaderboardSubtitle => '查看排名';

  @override
  String get pcQuickEntry => '快捷入口';

  @override
  String get pcEnter => '进入';

  @override
  String get networkNoConnection => '无网络连接，请检查网络后重试';

  @override
  String get networkTryAgain => '网络异常，请稍后重试';

  @override
  String get networkAuthExpired => '登录已过期或无效，请重新登录';

  @override
  String get networkPermissionDenied => '权限不足或操作被拒绝，请检查登录状态';

  @override
  String get adminReportReporter => '举报人';

  @override
  String get adminReportReported => '被举报人';

  @override
  String get adminReportNoData => '暂无举报记录';

  @override
  String get adminReportNotes => '管理员备注';

  @override
  String get profileCsWorkbench => '客服工作台';

  @override
  String get profileCsWorkbenchSubtitle => '查看并回复用户消息';

  @override
  String get adminCsConfig => '客服配置';

  @override
  String get adminCsSystemAccount => '系统客服账号';

  @override
  String get adminCsSystemAccountHint => '用户添加的好友、消息接收方，需从用户列表选择';

  @override
  String get adminCsAvatarUrl => '客服固定头像';

  @override
  String get adminCsStaff => '客服人员';

  @override
  String get adminCsStaffHint => '登录后可见「客服工作台」，可回复用户消息';

  @override
  String get adminSelectAsSystemCs => '设为系统客服';

  @override
  String get adminAddAsCsStaff => '设为客服人员';

  @override
  String get adminRemoveCsStaff => '移除客服身份';

  @override
  String get adminCsNotConfigured => '未配置';

  @override
  String get adminCsUploadAvatar => '上传头像';

  @override
  String get adminCsWelcomeMessage => '自动欢迎语';

  @override
  String get adminCsWelcomeMessageHint => '用户首次联系客服时自动发送，留空则不发送';

  @override
  String get adminCsBroadcast => '群发消息';

  @override
  String get adminCsBroadcastHint => '以系统客服身份向所有已添加客服的用户发送';

  @override
  String get adminCsBroadcastSend => '发送群发消息';

  @override
  String adminCsBroadcastSuccess(Object count) {
    return '已向 $count 个用户发送';
  }

  @override
  String get adminCsBroadcastEmpty => '消息不能为空';
}

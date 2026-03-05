import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'金融培训机构'**
  String get appTitle;

  /// No description provided for @adminTitle.
  ///
  /// In zh, this message translates to:
  /// **'后台管理'**
  String get adminTitle;

  /// No description provided for @navHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get navHome;

  /// No description provided for @navMainPage.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get navMainPage;

  /// No description provided for @navMarket.
  ///
  /// In zh, this message translates to:
  /// **'行情'**
  String get navMarket;

  /// No description provided for @navWatchlist.
  ///
  /// In zh, this message translates to:
  /// **'自选'**
  String get navWatchlist;

  /// No description provided for @navMessages.
  ///
  /// In zh, this message translates to:
  /// **'消息'**
  String get navMessages;

  /// No description provided for @navRankings.
  ///
  /// In zh, this message translates to:
  /// **'排行榜'**
  String get navRankings;

  /// No description provided for @navFollow.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get navFollow;

  /// No description provided for @navProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get navProfile;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get commonConfirm;

  /// No description provided for @commonSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get commonSearch;

  /// No description provided for @commonLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中…'**
  String get commonLoading;

  /// No description provided for @commonNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get commonNoData;

  /// No description provided for @commonUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get commonUser;

  /// No description provided for @commonOther.
  ///
  /// In zh, this message translates to:
  /// **'对方'**
  String get commonOther;

  /// No description provided for @commonFriend.
  ///
  /// In zh, this message translates to:
  /// **'好友'**
  String get commonFriend;

  /// No description provided for @commonMe.
  ///
  /// In zh, this message translates to:
  /// **'我'**
  String get commonMe;

  /// No description provided for @commonCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get commonCopy;

  /// No description provided for @commonForward.
  ///
  /// In zh, this message translates to:
  /// **'转发'**
  String get commonForward;

  /// No description provided for @commonReply.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get commonReply;

  /// No description provided for @commonImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get commonImage;

  /// No description provided for @commonVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get commonVideo;

  /// No description provided for @commonFile.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get commonFile;

  /// No description provided for @commonCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get commonCopied;

  /// No description provided for @commonKnowIt.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get commonKnowIt;

  /// No description provided for @commonGoToSettings.
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get commonGoToSettings;

  /// No description provided for @commonGoToEnable.
  ///
  /// In zh, this message translates to:
  /// **'去开启'**
  String get commonGoToEnable;

  /// No description provided for @authLoginOrRegister.
  ///
  /// In zh, this message translates to:
  /// **'登录/注册'**
  String get authLoginOrRegister;

  /// No description provided for @authLogin.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get authLogin;

  /// No description provided for @authLoginHint.
  ///
  /// In zh, this message translates to:
  /// **'使用邮箱或第三方账号登录'**
  String get authLoginHint;

  /// No description provided for @authRegisterHint.
  ///
  /// In zh, this message translates to:
  /// **'创建账号并验证邮箱'**
  String get authRegisterHint;

  /// No description provided for @authNameHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入昵称'**
  String get authNameHint;

  /// No description provided for @authEmailHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入邮箱'**
  String get authEmailHint;

  /// No description provided for @authPasswordHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get authPasswordHint;

  /// No description provided for @authConfirmPasswordHint.
  ///
  /// In zh, this message translates to:
  /// **'请再次输入密码'**
  String get authConfirmPasswordHint;

  /// No description provided for @authPleaseConfigureFirebase.
  ///
  /// In zh, this message translates to:
  /// **'请先配置 Firebase（添加配置文件）'**
  String get authPleaseConfigureFirebase;

  /// No description provided for @authPleaseFillEmailAndPassword.
  ///
  /// In zh, this message translates to:
  /// **'请先填写邮箱和密码'**
  String get authPleaseFillEmailAndPassword;

  /// No description provided for @authAccountOrPasswordWrong.
  ///
  /// In zh, this message translates to:
  /// **'账号或密码错误'**
  String get authAccountOrPasswordWrong;

  /// No description provided for @authEnterAccount.
  ///
  /// In zh, this message translates to:
  /// **'请输入账号'**
  String get authEnterAccount;

  /// No description provided for @authEnterPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get authEnterPassword;

  /// No description provided for @authAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get authAccount;

  /// No description provided for @authPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get authPassword;

  /// No description provided for @authPleaseLoginToManage.
  ///
  /// In zh, this message translates to:
  /// **'请登录后管理后台'**
  String get authPleaseLoginToManage;

  /// No description provided for @authEnterAdminAccount.
  ///
  /// In zh, this message translates to:
  /// **'请输入管理员账号'**
  String get authEnterAdminAccount;

  /// No description provided for @authEnterPasswordHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get authEnterPasswordHint;

  /// No description provided for @profileMy.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get profileMy;

  /// No description provided for @profileEditSignature.
  ///
  /// In zh, this message translates to:
  /// **'编辑个性签名'**
  String get profileEditSignature;

  /// No description provided for @profileSignatureHint.
  ///
  /// In zh, this message translates to:
  /// **'写点什么吧…'**
  String get profileSignatureHint;

  /// No description provided for @profileAvatarUploadFailedNoSupabase.
  ///
  /// In zh, this message translates to:
  /// **'头像上传失败：未配置 Supabase'**
  String get profileAvatarUploadFailedNoSupabase;

  /// No description provided for @profileAvatarUpdated.
  ///
  /// In zh, this message translates to:
  /// **'头像已更新'**
  String get profileAvatarUpdated;

  /// No description provided for @profileAvatarUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'头像上传失败'**
  String get profileAvatarUploadFailed;

  /// No description provided for @profileSignatureUpdated.
  ///
  /// In zh, this message translates to:
  /// **'签名已更新'**
  String get profileSignatureUpdated;

  /// No description provided for @profileSignatureUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'签名更新失败'**
  String get profileSignatureUpdateFailed;

  /// No description provided for @profileAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get profileAdmin;

  /// No description provided for @profileVip.
  ///
  /// In zh, this message translates to:
  /// **'会员'**
  String get profileVip;

  /// No description provided for @profileTeacher.
  ///
  /// In zh, this message translates to:
  /// **'交易员'**
  String get profileTeacher;

  /// No description provided for @profileNormalUser.
  ///
  /// In zh, this message translates to:
  /// **'普通用户'**
  String get profileNormalUser;

  /// No description provided for @profileStudentAccount.
  ///
  /// In zh, this message translates to:
  /// **'学员账号'**
  String get profileStudentAccount;

  /// No description provided for @profileNotLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get profileNotLoggedIn;

  /// No description provided for @profileBecomeTeacher.
  ///
  /// In zh, this message translates to:
  /// **'成为交易员'**
  String get profileBecomeTeacher;

  /// No description provided for @profileLoginToSubmit.
  ///
  /// In zh, this message translates to:
  /// **'登录后可提交资料'**
  String get profileLoginToSubmit;

  /// No description provided for @profileFirebaseNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置 Firebase，登录与消息功能暂不可用。'**
  String get profileFirebaseNotConfigured;

  /// No description provided for @profileNotificationNotEnabled.
  ///
  /// In zh, this message translates to:
  /// **'通知未开启，可能收不到新消息提醒'**
  String get profileNotificationNotEnabled;

  /// No description provided for @profileAccountId.
  ///
  /// In zh, this message translates to:
  /// **'账号ID'**
  String get profileAccountId;

  /// No description provided for @profileAccountIdValue.
  ///
  /// In zh, this message translates to:
  /// **'账号ID {id}'**
  String profileAccountIdValue(String id);

  /// No description provided for @profileAccountIdDash.
  ///
  /// In zh, this message translates to:
  /// **'账号ID --'**
  String get profileAccountIdDash;

  /// No description provided for @profileLazySignature.
  ///
  /// In zh, this message translates to:
  /// **'这个人很懒，什么都没写'**
  String get profileLazySignature;

  /// No description provided for @profileTeacherCenter.
  ///
  /// In zh, this message translates to:
  /// **'交易员中心'**
  String get profileTeacherCenter;

  /// No description provided for @profileManageStrategyAndRecords.
  ///
  /// In zh, this message translates to:
  /// **'管理策略与交易记录'**
  String get profileManageStrategyAndRecords;

  /// No description provided for @profileSubmitProfileAndPublish.
  ///
  /// In zh, this message translates to:
  /// **'提交资料，发布策略与交易记录'**
  String get profileSubmitProfileAndPublish;

  /// No description provided for @profileMyFollowing.
  ///
  /// In zh, this message translates to:
  /// **'我的关注'**
  String get profileMyFollowing;

  /// No description provided for @profileAdminPc.
  ///
  /// In zh, this message translates to:
  /// **'后台管理（PC）'**
  String get profileAdminPc;

  /// No description provided for @profilePushNotificationGuide.
  ///
  /// In zh, this message translates to:
  /// **'收不到推送？'**
  String get profilePushNotificationGuide;

  /// No description provided for @profileNotificationGuideSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看通知与自启动设置说明'**
  String get profileNotificationGuideSubtitle;

  /// No description provided for @profileEnsureReceiveMessages.
  ///
  /// In zh, this message translates to:
  /// **'确保收到新消息'**
  String get profileEnsureReceiveMessages;

  /// No description provided for @profileNotificationPermissionGuide.
  ///
  /// In zh, this message translates to:
  /// **'1. 请允许本应用的「通知」和「后台运行」权限。\n\n2. 华为/荣耀用户：若后台收不到消息，请到\n   设置 → 应用 → Tongxin\n   开启「自启动」，并在「手动管理」中允许后台活动。\n\n3. 华为/荣耀用户：若来电时没有弹出接听界面（只在通知栏看到），请到\n   设置 → 应用 → Tongxin → 权限\n   开启「后台弹窗」或「悬浮窗」，以便在桌面/其他 App 时也能弹出通话窗口。\n\n4. 若需要桌面图标显示未读数字，请到\n   设置 → 应用 → Tongxin → 通知管理\n   开启「桌面角标」。'**
  String get profileNotificationPermissionGuide;

  /// No description provided for @profileIncomingCallFullScreen.
  ///
  /// In zh, this message translates to:
  /// **'来电全屏接听'**
  String get profileIncomingCallFullScreen;

  /// No description provided for @profileIncomingCallFullScreenSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'后台或锁屏时直接弹出接听界面（Android 14+ 需开启全屏意图）'**
  String get profileIncomingCallFullScreenSubtitle;

  /// No description provided for @profileFullScreenIntentEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启，来电时将全屏弹出'**
  String get profileFullScreenIntentEnabled;

  /// No description provided for @profileCurrentNotLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'当前未登录'**
  String get profileCurrentNotLoggedIn;

  /// No description provided for @profileLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get profileLogout;

  /// No description provided for @profileLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'已登录'**
  String get profileLoggedIn;

  /// No description provided for @profileReRequestPermission.
  ///
  /// In zh, this message translates to:
  /// **'重新请求权限'**
  String get profileReRequestPermission;

  /// No description provided for @profileHelp.
  ///
  /// In zh, this message translates to:
  /// **'帮助'**
  String get profileHelp;

  /// No description provided for @profileHelpTitle.
  ///
  /// In zh, this message translates to:
  /// **'帮助与说明'**
  String get profileHelpTitle;

  /// No description provided for @profileTraderFriends.
  ///
  /// In zh, this message translates to:
  /// **'交易员好友'**
  String get profileTraderFriends;

  /// No description provided for @profileTraderFriendsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'我关注的交易员'**
  String get profileTraderFriendsSubtitle;

  /// No description provided for @profileAccountDeletion.
  ///
  /// In zh, this message translates to:
  /// **'账号注销'**
  String get profileAccountDeletion;

  /// No description provided for @profileAccountDeletionConfirm.
  ///
  /// In zh, this message translates to:
  /// **'注销后账号将被永久删除，无法恢复。确定继续？'**
  String get profileAccountDeletionConfirm;

  /// No description provided for @profileDeletionSuccess.
  ///
  /// In zh, this message translates to:
  /// **'账号已注销'**
  String get profileDeletionSuccess;

  /// No description provided for @profilePrivacyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策'**
  String get profilePrivacyPolicy;

  /// No description provided for @profilePrivacyPolicySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看隐私政策与用户协议'**
  String get profilePrivacyPolicySubtitle;

  /// No description provided for @profileReport.
  ///
  /// In zh, this message translates to:
  /// **'举报'**
  String get profileReport;

  /// No description provided for @profileReportSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'举报违规内容或用户'**
  String get profileReportSubtitle;

  /// No description provided for @profilePrivacyPolicyContent.
  ///
  /// In zh, this message translates to:
  /// **'本应用尊重并保护用户隐私。我们收集的信息仅用于提供和改进服务。详细条款请参阅应用商店或官网的完整隐私政策。'**
  String get profilePrivacyPolicyContent;

  /// No description provided for @profileReportContent.
  ///
  /// In zh, this message translates to:
  /// **'如有违规内容或用户，请通过应用内反馈或联系客服举报。我们会尽快处理。'**
  String get profileReportContent;

  /// No description provided for @reportPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'举报用户'**
  String get reportPageTitle;

  /// No description provided for @reportTargetUser.
  ///
  /// In zh, this message translates to:
  /// **'被举报用户'**
  String get reportTargetUser;

  /// No description provided for @reportTargetUserHint.
  ///
  /// In zh, this message translates to:
  /// **'输入账号ID或邮箱搜索'**
  String get reportTargetUserHint;

  /// No description provided for @reportReason.
  ///
  /// In zh, this message translates to:
  /// **'举报原因'**
  String get reportReason;

  /// No description provided for @reportReasonHarassment.
  ///
  /// In zh, this message translates to:
  /// **'骚扰'**
  String get reportReasonHarassment;

  /// No description provided for @reportReasonSpam.
  ///
  /// In zh, this message translates to:
  /// **'广告/垃圾信息'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonFraud.
  ///
  /// In zh, this message translates to:
  /// **'欺诈'**
  String get reportReasonFraud;

  /// No description provided for @reportReasonInappropriate.
  ///
  /// In zh, this message translates to:
  /// **'不当言论'**
  String get reportReasonInappropriate;

  /// No description provided for @reportReasonOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get reportReasonOther;

  /// No description provided for @reportContent.
  ///
  /// In zh, this message translates to:
  /// **'详细说明'**
  String get reportContent;

  /// No description provided for @reportContentHint.
  ///
  /// In zh, this message translates to:
  /// **'请描述具体情况（选填）'**
  String get reportContentHint;

  /// No description provided for @reportScreenshots.
  ///
  /// In zh, this message translates to:
  /// **'截图证据'**
  String get reportScreenshots;

  /// No description provided for @reportScreenshotsMax.
  ///
  /// In zh, this message translates to:
  /// **'最多5张'**
  String get reportScreenshotsMax;

  /// No description provided for @reportSubmit.
  ///
  /// In zh, this message translates to:
  /// **'提交举报'**
  String get reportSubmit;

  /// No description provided for @reportSuccess.
  ///
  /// In zh, this message translates to:
  /// **'举报已提交，我们会尽快处理'**
  String get reportSuccess;

  /// No description provided for @reportFailed.
  ///
  /// In zh, this message translates to:
  /// **'提交失败'**
  String get reportFailed;

  /// No description provided for @reportPleaseSelectUser.
  ///
  /// In zh, this message translates to:
  /// **'请先搜索并选择被举报用户'**
  String get reportPleaseSelectUser;

  /// No description provided for @reportPleaseSelectReason.
  ///
  /// In zh, this message translates to:
  /// **'请选择举报原因'**
  String get reportPleaseSelectReason;

  /// No description provided for @featuredTrader.
  ///
  /// In zh, this message translates to:
  /// **'交易员'**
  String get featuredTrader;

  /// No description provided for @featuredMentor.
  ///
  /// In zh, this message translates to:
  /// **'导师'**
  String get featuredMentor;

  /// No description provided for @featuredNoTodayStrategy.
  ///
  /// In zh, this message translates to:
  /// **'暂无今日策略'**
  String get featuredNoTodayStrategy;

  /// No description provided for @featuredNoTeacherInfo.
  ///
  /// In zh, this message translates to:
  /// **'暂无交易员信息'**
  String get featuredNoTeacherInfo;

  /// No description provided for @featuredLoadFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'加载失败，请重试'**
  String get featuredLoadFailedRetry;

  /// No description provided for @featuredServiceNotReady.
  ///
  /// In zh, this message translates to:
  /// **'服务未就绪'**
  String get featuredServiceNotReady;

  /// No description provided for @featuredNoFollowingOrRanking.
  ///
  /// In zh, this message translates to:
  /// **'暂无关注或排名数据'**
  String get featuredNoFollowingOrRanking;

  /// No description provided for @featuredNetworkRestricted.
  ///
  /// In zh, this message translates to:
  /// **'网络连接被限制，请检查网络或在本机终端运行应用后重试'**
  String get featuredNetworkRestricted;

  /// No description provided for @featuredNotStartedInvestment.
  ///
  /// In zh, this message translates to:
  /// **'你还没有开启自己的投资之旅'**
  String get featuredNotStartedInvestment;

  /// No description provided for @featuredPnlOverview.
  ///
  /// In zh, this message translates to:
  /// **'盈亏概览'**
  String get featuredPnlOverview;

  /// No description provided for @featuredTodayStrategy.
  ///
  /// In zh, this message translates to:
  /// **'今日交易策略'**
  String get featuredTodayStrategy;

  /// No description provided for @featuredViewAllStrategies.
  ///
  /// In zh, this message translates to:
  /// **'查看全部交易策略'**
  String get featuredViewAllStrategies;

  /// No description provided for @featuredCurrentPositions.
  ///
  /// In zh, this message translates to:
  /// **'目前持仓'**
  String get featuredCurrentPositions;

  /// No description provided for @featuredHistoryPositions.
  ///
  /// In zh, this message translates to:
  /// **'历史持仓'**
  String get featuredHistoryPositions;

  /// No description provided for @featuredWins.
  ///
  /// In zh, this message translates to:
  /// **'胜场'**
  String get featuredWins;

  /// No description provided for @featuredLosses.
  ///
  /// In zh, this message translates to:
  /// **'败场'**
  String get featuredLosses;

  /// No description provided for @featuredWinRate.
  ///
  /// In zh, this message translates to:
  /// **'胜率'**
  String get featuredWinRate;

  /// No description provided for @featuredPositionPnl.
  ///
  /// In zh, this message translates to:
  /// **'持仓盈亏'**
  String get featuredPositionPnl;

  /// No description provided for @featuredYearPnl.
  ///
  /// In zh, this message translates to:
  /// **'年度盈亏'**
  String get featuredYearPnl;

  /// No description provided for @featuredTotalPnl.
  ///
  /// In zh, this message translates to:
  /// **'总盈亏'**
  String get featuredTotalPnl;

  /// No description provided for @featuredCoreStrategy.
  ///
  /// In zh, this message translates to:
  /// **'核心策略'**
  String get featuredCoreStrategy;

  /// No description provided for @featuredCollapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get featuredCollapse;

  /// No description provided for @featuredExpandReplies.
  ///
  /// In zh, this message translates to:
  /// **'展开 {count} 条回复'**
  String featuredExpandReplies(int count);

  /// No description provided for @featuredLoginBeforeForward.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再转发'**
  String get featuredLoginBeforeForward;

  /// No description provided for @featuredViewFullStrategy.
  ///
  /// In zh, this message translates to:
  /// **'点击查看完整投资策略'**
  String get featuredViewFullStrategy;

  /// No description provided for @featuredHideComments.
  ///
  /// In zh, this message translates to:
  /// **'隐藏评论'**
  String get featuredHideComments;

  /// No description provided for @featuredViewComments.
  ///
  /// In zh, this message translates to:
  /// **'查看评论'**
  String get featuredViewComments;

  /// No description provided for @featuredForwardTooltip.
  ///
  /// In zh, this message translates to:
  /// **'转发'**
  String get featuredForwardTooltip;

  /// No description provided for @featuredNoComments.
  ///
  /// In zh, this message translates to:
  /// **'暂无评论'**
  String get featuredNoComments;

  /// No description provided for @featuredForwarded.
  ///
  /// In zh, this message translates to:
  /// **'已转发'**
  String get featuredForwarded;

  /// No description provided for @featuredForwardFailed.
  ///
  /// In zh, this message translates to:
  /// **'转发失败'**
  String get featuredForwardFailed;

  /// No description provided for @featuredForwardFailedWithMessage.
  ///
  /// In zh, this message translates to:
  /// **'转发失败: {message}'**
  String featuredForwardFailedWithMessage(String message);

  /// No description provided for @featuredForwardTo.
  ///
  /// In zh, this message translates to:
  /// **'转发到'**
  String get featuredForwardTo;

  /// No description provided for @featuredNoConversationAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'暂无会话，请先添加好友或加入群聊'**
  String get featuredNoConversationAddFriend;

  /// No description provided for @featuredLoginBeforeComment.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再发表评论'**
  String get featuredLoginBeforeComment;

  /// No description provided for @featuredCommentPublished.
  ///
  /// In zh, this message translates to:
  /// **'评论已发表'**
  String get featuredCommentPublished;

  /// No description provided for @featuredCommentPublishFailed.
  ///
  /// In zh, this message translates to:
  /// **'发表失败'**
  String get featuredCommentPublishFailed;

  /// No description provided for @featuredCommentPublishFailedWithMessage.
  ///
  /// In zh, this message translates to:
  /// **'发表失败: {message}'**
  String featuredCommentPublishFailedWithMessage(String message);

  /// No description provided for @featuredCommentsCount.
  ///
  /// In zh, this message translates to:
  /// **'{count}条评论'**
  String featuredCommentsCount(int count);

  /// No description provided for @featuredCommentHint.
  ///
  /// In zh, this message translates to:
  /// **'写下你的评论…'**
  String get featuredCommentHint;

  /// No description provided for @featuredPublishing.
  ///
  /// In zh, this message translates to:
  /// **'发表中…'**
  String get featuredPublishing;

  /// No description provided for @featuredPublish.
  ///
  /// In zh, this message translates to:
  /// **'发表'**
  String get featuredPublish;

  /// No description provided for @featuredBuy.
  ///
  /// In zh, this message translates to:
  /// **'买入'**
  String get featuredBuy;

  /// No description provided for @featuredCost.
  ///
  /// In zh, this message translates to:
  /// **'成本'**
  String get featuredCost;

  /// No description provided for @featuredQuantity.
  ///
  /// In zh, this message translates to:
  /// **'数量'**
  String get featuredQuantity;

  /// No description provided for @featuredSell.
  ///
  /// In zh, this message translates to:
  /// **'卖出'**
  String get featuredSell;

  /// No description provided for @featuredSellPrice.
  ///
  /// In zh, this message translates to:
  /// **'卖出价'**
  String get featuredSellPrice;

  /// No description provided for @featuredCurrentPrice.
  ///
  /// In zh, this message translates to:
  /// **'现价'**
  String get featuredCurrentPrice;

  /// No description provided for @featuredFloatingPnl.
  ///
  /// In zh, this message translates to:
  /// **'浮动盈亏'**
  String get featuredFloatingPnl;

  /// No description provided for @featuredCurrentPositionPnl.
  ///
  /// In zh, this message translates to:
  /// **'目前持仓盈亏'**
  String get featuredCurrentPositionPnl;

  /// No description provided for @featuredCurrentPosition.
  ///
  /// In zh, this message translates to:
  /// **'目前持仓'**
  String get featuredCurrentPosition;

  /// No description provided for @featuredBuyTime.
  ///
  /// In zh, this message translates to:
  /// **'买入时间'**
  String get featuredBuyTime;

  /// No description provided for @featuredBuyShares.
  ///
  /// In zh, this message translates to:
  /// **'买入股数'**
  String get featuredBuyShares;

  /// No description provided for @featuredBuyPrice.
  ///
  /// In zh, this message translates to:
  /// **'买入价格'**
  String get featuredBuyPrice;

  /// No description provided for @featuredPositionCost.
  ///
  /// In zh, this message translates to:
  /// **'持仓成本'**
  String get featuredPositionCost;

  /// No description provided for @featuredPositionPnlRatio.
  ///
  /// In zh, this message translates to:
  /// **'持仓盈亏比例'**
  String get featuredPositionPnlRatio;

  /// No description provided for @featuredProfitRatio.
  ///
  /// In zh, this message translates to:
  /// **'盈利比例'**
  String get featuredProfitRatio;

  /// No description provided for @featuredPnlAmount.
  ///
  /// In zh, this message translates to:
  /// **'盈亏金额'**
  String get featuredPnlAmount;

  /// No description provided for @featuredShares.
  ///
  /// In zh, this message translates to:
  /// **'股数'**
  String get featuredShares;

  /// No description provided for @featuredPrice.
  ///
  /// In zh, this message translates to:
  /// **'价格'**
  String get featuredPrice;

  /// No description provided for @featuredMonthTotalPnl.
  ///
  /// In zh, this message translates to:
  /// **'本月总盈亏'**
  String get featuredMonthTotalPnl;

  /// No description provided for @featuredPositionPnlAmount.
  ///
  /// In zh, this message translates to:
  /// **'持仓盈亏金额'**
  String get featuredPositionPnlAmount;

  /// No description provided for @featuredTodayStrategyTab.
  ///
  /// In zh, this message translates to:
  /// **'今日策略'**
  String get featuredTodayStrategyTab;

  /// No description provided for @featuredPositionTab.
  ///
  /// In zh, this message translates to:
  /// **'持仓'**
  String get featuredPositionTab;

  /// No description provided for @featuredHistoryTab.
  ///
  /// In zh, this message translates to:
  /// **'历史'**
  String get featuredHistoryTab;

  /// No description provided for @tradingApple.
  ///
  /// In zh, this message translates to:
  /// **'苹果'**
  String get tradingApple;

  /// No description provided for @tradingMicrosoft.
  ///
  /// In zh, this message translates to:
  /// **'微软'**
  String get tradingMicrosoft;

  /// No description provided for @tradingGoogle.
  ///
  /// In zh, this message translates to:
  /// **'谷歌'**
  String get tradingGoogle;

  /// No description provided for @tradingAmazon.
  ///
  /// In zh, this message translates to:
  /// **'亚马逊'**
  String get tradingAmazon;

  /// No description provided for @tradingTesla.
  ///
  /// In zh, this message translates to:
  /// **'特斯拉'**
  String get tradingTesla;

  /// No description provided for @tradingStock.
  ///
  /// In zh, this message translates to:
  /// **'股票'**
  String get tradingStock;

  /// No description provided for @tradingForex.
  ///
  /// In zh, this message translates to:
  /// **'外汇'**
  String get tradingForex;

  /// No description provided for @tradingCrypto.
  ///
  /// In zh, this message translates to:
  /// **'加密货币'**
  String get tradingCrypto;

  /// No description provided for @tradingQuoteRefreshFailed.
  ///
  /// In zh, this message translates to:
  /// **'行情刷新失败'**
  String get tradingQuoteRefreshFailed;

  /// No description provided for @tradingSearchAndSelectFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先搜索并选择标的'**
  String get tradingSearchAndSelectFirst;

  /// No description provided for @tradingOrderSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'已提交（模拟，接口待接入）'**
  String get tradingOrderSubmitted;

  /// No description provided for @tradingVolume.
  ///
  /// In zh, this message translates to:
  /// **'成交量'**
  String get tradingVolume;

  /// No description provided for @tradingSelectGainersOrSearch.
  ///
  /// In zh, this message translates to:
  /// **'选择上方涨幅榜或搜索标的'**
  String get tradingSelectGainersOrSearch;

  /// No description provided for @tradingViewRealtimeQuote.
  ///
  /// In zh, this message translates to:
  /// **'查看实时行情与图表'**
  String get tradingViewRealtimeQuote;

  /// No description provided for @tradingGainersList.
  ///
  /// In zh, this message translates to:
  /// **'涨幅榜'**
  String get tradingGainersList;

  /// No description provided for @tradingUpdateTime.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get tradingUpdateTime;

  /// No description provided for @tradingUpdateTimeValue.
  ///
  /// In zh, this message translates to:
  /// **'更新 {time}'**
  String tradingUpdateTimeValue(String time);

  /// No description provided for @tradingConfigurePolygonApiKey.
  ///
  /// In zh, this message translates to:
  /// **'请配置 POLYGON_API_KEY'**
  String get tradingConfigurePolygonApiKey;

  /// No description provided for @tradingStockCodeOrName.
  ///
  /// In zh, this message translates to:
  /// **'股票代码或名称'**
  String get tradingStockCodeOrName;

  /// No description provided for @tradingForexCodeExample.
  ///
  /// In zh, this message translates to:
  /// **'外汇代码如 EUR/USD'**
  String get tradingForexCodeExample;

  /// No description provided for @tradingCryptoExample.
  ///
  /// In zh, this message translates to:
  /// **'加密货币如 BTC、ETH'**
  String get tradingCryptoExample;

  /// No description provided for @tradingIntraday.
  ///
  /// In zh, this message translates to:
  /// **'分时'**
  String get tradingIntraday;

  /// No description provided for @tradingNoChartData.
  ///
  /// In zh, this message translates to:
  /// **'暂无图表数据'**
  String get tradingNoChartData;

  /// No description provided for @tradingBuy.
  ///
  /// In zh, this message translates to:
  /// **'买入'**
  String get tradingBuy;

  /// No description provided for @tradingSell.
  ///
  /// In zh, this message translates to:
  /// **'卖出'**
  String get tradingSell;

  /// No description provided for @tradingLimitOrder.
  ///
  /// In zh, this message translates to:
  /// **'限价'**
  String get tradingLimitOrder;

  /// No description provided for @tradingMarketOrder.
  ///
  /// In zh, this message translates to:
  /// **'市价'**
  String get tradingMarketOrder;

  /// No description provided for @tradingPriceLabel.
  ///
  /// In zh, this message translates to:
  /// **'价格'**
  String get tradingPriceLabel;

  /// No description provided for @tradingQuantityLabel.
  ///
  /// In zh, this message translates to:
  /// **'数量'**
  String get tradingQuantityLabel;

  /// No description provided for @tradingEnterValidQuantity.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效数量（大于 0）'**
  String get tradingEnterValidQuantity;

  /// No description provided for @tradingEnterValidPriceForLimit.
  ///
  /// In zh, this message translates to:
  /// **'限价单请输入有效价格（大于 0）'**
  String get tradingEnterValidPriceForLimit;

  /// No description provided for @tradingConfirmBuy.
  ///
  /// In zh, this message translates to:
  /// **'确认买入'**
  String get tradingConfirmBuy;

  /// No description provided for @tradingConfirmSell.
  ///
  /// In zh, this message translates to:
  /// **'确认卖出'**
  String get tradingConfirmSell;

  /// No description provided for @tradingNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get tradingNoData;

  /// No description provided for @tradingBuySellSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'{action} {symbol} 已提交（模拟，接口待接入）'**
  String tradingBuySellSubmitted(String action, String symbol);

  /// No description provided for @callCallerCancelled.
  ///
  /// In zh, this message translates to:
  /// **'对方已取消'**
  String get callCallerCancelled;

  /// No description provided for @callVideoCall.
  ///
  /// In zh, this message translates to:
  /// **'视频通话'**
  String get callVideoCall;

  /// No description provided for @callVoiceCall.
  ///
  /// In zh, this message translates to:
  /// **'语音通话'**
  String get callVoiceCall;

  /// No description provided for @callInviteVideoCall.
  ///
  /// In zh, this message translates to:
  /// **'邀请你视频通话'**
  String get callInviteVideoCall;

  /// No description provided for @callInviteVoiceCall.
  ///
  /// In zh, this message translates to:
  /// **'邀请你语音通话'**
  String get callInviteVoiceCall;

  /// No description provided for @callDecline.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get callDecline;

  /// No description provided for @callAnswer.
  ///
  /// In zh, this message translates to:
  /// **'接听'**
  String get callAnswer;

  /// No description provided for @callInviteCallBody.
  ///
  /// In zh, this message translates to:
  /// **'{name} 邀请你{type}通话'**
  String callInviteCallBody(String name, String type);

  /// No description provided for @messagesNoMatchingMembers.
  ///
  /// In zh, this message translates to:
  /// **'暂无匹配成员'**
  String get messagesNoMatchingMembers;

  /// No description provided for @messagesNotFriendCannotSend.
  ///
  /// In zh, this message translates to:
  /// **'已不是好友，无法发送'**
  String get messagesNotFriendCannotSend;

  /// No description provided for @messagesRecordingTooShort.
  ///
  /// In zh, this message translates to:
  /// **'录音时间太短'**
  String get messagesRecordingTooShort;

  /// No description provided for @messagesGrantMicPermission.
  ///
  /// In zh, this message translates to:
  /// **'请授予麦克风权限'**
  String get messagesGrantMicPermission;

  /// No description provided for @messagesNoSupabaseCannotSendMedia.
  ///
  /// In zh, this message translates to:
  /// **'未配置 Supabase，无法发送媒体'**
  String get messagesNoSupabaseCannotSendMedia;

  /// No description provided for @messagesFileEmptyCannotSend.
  ///
  /// In zh, this message translates to:
  /// **'文件为空，无法发送'**
  String get messagesFileEmptyCannotSend;

  /// No description provided for @messagesSendFailed.
  ///
  /// In zh, this message translates to:
  /// **'发送失败'**
  String get messagesSendFailed;

  /// No description provided for @messagesCannotReadFile.
  ///
  /// In zh, this message translates to:
  /// **'无法读取该文件'**
  String get messagesCannotReadFile;

  /// No description provided for @messagesSelectFileFailed.
  ///
  /// In zh, this message translates to:
  /// **'选择文件失败'**
  String get messagesSelectFileFailed;

  /// No description provided for @messagesForwardInDevelopment.
  ///
  /// In zh, this message translates to:
  /// **'转发功能正在开发中'**
  String get messagesForwardInDevelopment;

  /// No description provided for @messagesRecall.
  ///
  /// In zh, this message translates to:
  /// **'撤回'**
  String get messagesRecall;

  /// No description provided for @messagesRecallMessage.
  ///
  /// In zh, this message translates to:
  /// **'撤回消息'**
  String get messagesRecallMessage;

  /// No description provided for @messagesConfirmRecallMessage.
  ///
  /// In zh, this message translates to:
  /// **'确定撤回这条消息吗？'**
  String get messagesConfirmRecallMessage;

  /// No description provided for @messagesRecalled.
  ///
  /// In zh, this message translates to:
  /// **'已撤回'**
  String get messagesRecalled;

  /// No description provided for @messagesRecallFailed.
  ///
  /// In zh, this message translates to:
  /// **'撤回失败'**
  String get messagesRecallFailed;

  /// No description provided for @messagesAlbum.
  ///
  /// In zh, this message translates to:
  /// **'相册'**
  String get messagesAlbum;

  /// No description provided for @messagesCamera.
  ///
  /// In zh, this message translates to:
  /// **'拍摄'**
  String get messagesCamera;

  /// No description provided for @messagesFileLabel.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get messagesFileLabel;

  /// No description provided for @messagesCallLabel.
  ///
  /// In zh, this message translates to:
  /// **'通话'**
  String get messagesCallLabel;

  /// No description provided for @messagesTakePhoto.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get messagesTakePhoto;

  /// No description provided for @messagesTakeVideo.
  ///
  /// In zh, this message translates to:
  /// **'拍视频'**
  String get messagesTakeVideo;

  /// No description provided for @messagesVoiceCall.
  ///
  /// In zh, this message translates to:
  /// **'语音通话'**
  String get messagesVoiceCall;

  /// No description provided for @messagesVideoCall.
  ///
  /// In zh, this message translates to:
  /// **'视频通话'**
  String get messagesVideoCall;

  /// No description provided for @messagesNoAgoraCannotCall.
  ///
  /// In zh, this message translates to:
  /// **'未配置 Agora，无法发起通话'**
  String get messagesNoAgoraCannotCall;

  /// No description provided for @messagesNeedMicForCall.
  ///
  /// In zh, this message translates to:
  /// **'需要麦克风权限才能通话，请先开启'**
  String get messagesNeedMicForCall;

  /// No description provided for @messagesNeedCameraForVideo.
  ///
  /// In zh, this message translates to:
  /// **'需要相机权限才能视频通话，请先开启'**
  String get messagesNeedCameraForVideo;

  /// No description provided for @messagesGroupSettings.
  ///
  /// In zh, this message translates to:
  /// **'群设置'**
  String get messagesGroupSettings;

  /// No description provided for @messagesSetRemark.
  ///
  /// In zh, this message translates to:
  /// **'设置备注'**
  String get messagesSetRemark;

  /// No description provided for @messagesPinConversation.
  ///
  /// In zh, this message translates to:
  /// **'置顶会话'**
  String get messagesPinConversation;

  /// No description provided for @messagesClearChatHistory.
  ///
  /// In zh, this message translates to:
  /// **'清空聊天记录'**
  String get messagesClearChatHistory;

  /// No description provided for @messagesImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get messagesImage;

  /// No description provided for @messagesVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get messagesVideo;

  /// No description provided for @messagesReply.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get messagesReply;

  /// No description provided for @messagesCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get messagesCopy;

  /// No description provided for @messagesForward.
  ///
  /// In zh, this message translates to:
  /// **'转发'**
  String get messagesForward;

  /// No description provided for @messagesCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get messagesCopied;

  /// No description provided for @messagesNoFriendCannotSend.
  ///
  /// In zh, this message translates to:
  /// **'已不是好友，无法发送'**
  String get messagesNoFriendCannotSend;

  /// No description provided for @messagesSendFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'发送失败'**
  String get messagesSendFailedPrefix;

  /// No description provided for @messagesFileSendFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'文件发送失败'**
  String get messagesFileSendFailedPrefix;

  /// No description provided for @messagesRecallFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'撤回失败'**
  String get messagesRecallFailedPrefix;

  /// No description provided for @messagesViewProfile.
  ///
  /// In zh, this message translates to:
  /// **'查看个人资料'**
  String get messagesViewProfile;

  /// No description provided for @messagesRemarkHint.
  ///
  /// In zh, this message translates to:
  /// **'输入备注名'**
  String get messagesRemarkHint;

  /// No description provided for @messagesConfirmClearChat.
  ///
  /// In zh, this message translates to:
  /// **'确定清空本会话的所有聊天记录吗？此操作不可恢复。'**
  String get messagesConfirmClearChat;

  /// No description provided for @messagesClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get messagesClear;

  /// No description provided for @messagesGroupAnnouncement.
  ///
  /// In zh, this message translates to:
  /// **'群公告'**
  String get messagesGroupAnnouncement;

  /// No description provided for @messagesInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入消息'**
  String get messagesInputHint;

  /// No description provided for @messagesSend.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get messagesSend;

  /// No description provided for @messagesOpening.
  ///
  /// In zh, this message translates to:
  /// **'正在打开…'**
  String get messagesOpening;

  /// No description provided for @messagesCannotOpenFile.
  ///
  /// In zh, this message translates to:
  /// **'无法打开该文件'**
  String get messagesCannotOpenFile;

  /// No description provided for @messagesFileExpiredOrMissing.
  ///
  /// In zh, this message translates to:
  /// **'文件已过期或不存在，请让对方重新发送'**
  String get messagesFileExpiredOrMissing;

  /// No description provided for @messagesUseCompatiblePlayer.
  ///
  /// In zh, this message translates to:
  /// **'使用兼容播放器'**
  String get messagesUseCompatiblePlayer;

  /// No description provided for @marketNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get marketNoData;

  /// No description provided for @tradingQuoteRefreshFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'行情刷新失败: {error}'**
  String tradingQuoteRefreshFailedWithError(String error);

  /// No description provided for @tradingKline.
  ///
  /// In zh, this message translates to:
  /// **'K线'**
  String get tradingKline;

  /// No description provided for @teachersConfirmRiskPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请确认已阅读风险提示'**
  String get teachersConfirmRiskPrompt;

  /// No description provided for @teachersProfileSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'资料已提交'**
  String get teachersProfileSubmitted;

  /// No description provided for @teachersSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get teachersSaveFailed;

  /// No description provided for @teachersPhotoUploaded.
  ///
  /// In zh, this message translates to:
  /// **'资料照片已上传'**
  String get teachersPhotoUploaded;

  /// No description provided for @teachersUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'上传失败'**
  String get teachersUploadFailed;

  /// No description provided for @teachersPublishStrategy.
  ///
  /// In zh, this message translates to:
  /// **'发布策略'**
  String get teachersPublishStrategy;

  /// No description provided for @teachersTitleLabel.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get teachersTitleLabel;

  /// No description provided for @teachersStrategyContent.
  ///
  /// In zh, this message translates to:
  /// **'策略内容'**
  String get teachersStrategyContent;

  /// No description provided for @teachersImages.
  ///
  /// In zh, this message translates to:
  /// **'配图'**
  String get teachersImages;

  /// No description provided for @teachersAddImage.
  ///
  /// In zh, this message translates to:
  /// **'添加图片'**
  String get teachersAddImage;

  /// No description provided for @teachersStrategyImage.
  ///
  /// In zh, this message translates to:
  /// **'配图'**
  String get teachersStrategyImage;

  /// No description provided for @teachersFillStrategyTitle.
  ///
  /// In zh, this message translates to:
  /// **'请填写策略标题'**
  String get teachersFillStrategyTitle;

  /// No description provided for @teachersPublish.
  ///
  /// In zh, this message translates to:
  /// **'发布'**
  String get teachersPublish;

  /// No description provided for @teachersStrategyPublished.
  ///
  /// In zh, this message translates to:
  /// **'策略已发布，将显示在关注页「今日交易策略」'**
  String get teachersStrategyPublished;

  /// No description provided for @teachersPublishFailed.
  ///
  /// In zh, this message translates to:
  /// **'发布失败'**
  String get teachersPublishFailed;

  /// No description provided for @teachersUploadTradeRecord.
  ///
  /// In zh, this message translates to:
  /// **'上传交易记录'**
  String get teachersUploadTradeRecord;

  /// No description provided for @teachersVarietyLabel.
  ///
  /// In zh, this message translates to:
  /// **'品种'**
  String get teachersVarietyLabel;

  /// No description provided for @teachersDirectionLabel.
  ///
  /// In zh, this message translates to:
  /// **'方向（买/卖）'**
  String get teachersDirectionLabel;

  /// No description provided for @teachersPnlLabel.
  ///
  /// In zh, this message translates to:
  /// **'盈亏'**
  String get teachersPnlLabel;

  /// No description provided for @teachersNoScreenshotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择截图'**
  String get teachersNoScreenshotSelected;

  /// No description provided for @teachersSelectScreenshot.
  ///
  /// In zh, this message translates to:
  /// **'选择截图'**
  String get teachersSelectScreenshot;

  /// No description provided for @teachersTradeRecordSaved.
  ///
  /// In zh, this message translates to:
  /// **'交易记录已保存'**
  String get teachersTradeRecordSaved;

  /// No description provided for @teachersTeacherCenter.
  ///
  /// In zh, this message translates to:
  /// **'交易员中心'**
  String get teachersTeacherCenter;

  /// No description provided for @teachersPleaseLoginFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先登录'**
  String get teachersPleaseLoginFirst;

  /// No description provided for @teachersStrategyTab.
  ///
  /// In zh, this message translates to:
  /// **'策略'**
  String get teachersStrategyTab;

  /// No description provided for @teachersQuoteAndTradeTab.
  ///
  /// In zh, this message translates to:
  /// **'行情与交易'**
  String get teachersQuoteAndTradeTab;

  /// No description provided for @teachersOrderTab.
  ///
  /// In zh, this message translates to:
  /// **'委托'**
  String get teachersOrderTab;

  /// No description provided for @teachersHistoryOrderTab.
  ///
  /// In zh, this message translates to:
  /// **'历史委托'**
  String get teachersHistoryOrderTab;

  /// No description provided for @teachersFillsAndPositionsTab.
  ///
  /// In zh, this message translates to:
  /// **'成交与持仓'**
  String get teachersFillsAndPositionsTab;

  /// No description provided for @teachersBasicInfo.
  ///
  /// In zh, this message translates to:
  /// **'基本信息'**
  String get teachersBasicInfo;

  /// No description provided for @teachersNoNicknameSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置昵称'**
  String get teachersNoNicknameSet;

  /// No description provided for @teachersAvatarNicknameHint.
  ///
  /// In zh, this message translates to:
  /// **'头像/昵称与账号资料保持一致'**
  String get teachersAvatarNicknameHint;

  /// No description provided for @teachersRealNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'真实姓名（必填）'**
  String get teachersRealNameRequired;

  /// No description provided for @teachersProfessionalTitle.
  ///
  /// In zh, this message translates to:
  /// **'专业职称/头衔'**
  String get teachersProfessionalTitle;

  /// No description provided for @teachersOrgCompany.
  ///
  /// In zh, this message translates to:
  /// **'所在机构/公司'**
  String get teachersOrgCompany;

  /// No description provided for @teachersCountryRegion.
  ///
  /// In zh, this message translates to:
  /// **'国家/地区'**
  String get teachersCountryRegion;

  /// No description provided for @teachersYearsExperience.
  ///
  /// In zh, this message translates to:
  /// **'从业年限'**
  String get teachersYearsExperience;

  /// No description provided for @teachersYearsAbove20.
  ///
  /// In zh, this message translates to:
  /// **'20 年以上'**
  String get teachersYearsAbove20;

  /// No description provided for @teachersYearsFormat.
  ///
  /// In zh, this message translates to:
  /// **'{n} 年'**
  String teachersYearsFormat(int n);

  /// No description provided for @teachersTradingBackground.
  ///
  /// In zh, this message translates to:
  /// **'交易背景'**
  String get teachersTradingBackground;

  /// No description provided for @teachersMainMarketLabel.
  ///
  /// In zh, this message translates to:
  /// **'主要市场（股票/期权/期货/外汇/加密）'**
  String get teachersMainMarketLabel;

  /// No description provided for @teachersMainVariety.
  ///
  /// In zh, this message translates to:
  /// **'主要交易品种/行业'**
  String get teachersMainVariety;

  /// No description provided for @teachersRiskPreference.
  ///
  /// In zh, this message translates to:
  /// **'风险偏好'**
  String get teachersRiskPreference;

  /// No description provided for @teachersExpertiseVariety.
  ///
  /// In zh, this message translates to:
  /// **'擅长品种（逗号分隔）'**
  String get teachersExpertiseVariety;

  /// No description provided for @teachersQualificationCompliance.
  ///
  /// In zh, this message translates to:
  /// **'资质与合规（可选）'**
  String get teachersQualificationCompliance;

  /// No description provided for @teachersQualificationCert.
  ///
  /// In zh, this message translates to:
  /// **'资质/证书（如 CFA/Series 7/Series 65）'**
  String get teachersQualificationCert;

  /// No description provided for @teachersBrokerLabel.
  ///
  /// In zh, this message translates to:
  /// **'合作券商/交易平台'**
  String get teachersBrokerLabel;

  /// No description provided for @teachersPerformanceIntro.
  ///
  /// In zh, this message translates to:
  /// **'业绩与简介'**
  String get teachersPerformanceIntro;

  /// No description provided for @teachersPerformanceLabel.
  ///
  /// In zh, this message translates to:
  /// **'业绩说明（如近一年收益/最大回撤）'**
  String get teachersPerformanceLabel;

  /// No description provided for @teachersIdVerification.
  ///
  /// In zh, this message translates to:
  /// **'身份核验（建议上传）'**
  String get teachersIdVerification;

  /// No description provided for @teachersCountryOptions.
  ///
  /// In zh, this message translates to:
  /// **'美国, 中国, 中国香港, 新加坡, 英国, 加拿大, 澳大利亚, 日本, 韩国, 德国, 法国, 阿联酋, 其他'**
  String get teachersCountryOptions;

  /// No description provided for @teachersCityLabel.
  ///
  /// In zh, this message translates to:
  /// **'城市'**
  String get teachersCityLabel;

  /// No description provided for @teachersTradingStyle.
  ///
  /// In zh, this message translates to:
  /// **'交易风格'**
  String get teachersTradingStyle;

  /// No description provided for @strategiesFullStrategy.
  ///
  /// In zh, this message translates to:
  /// **'完整投资策略'**
  String get strategiesFullStrategy;

  /// No description provided for @strategiesPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'交易策略节目'**
  String get strategiesPageTitle;

  /// No description provided for @strategiesTodayStrategies.
  ///
  /// In zh, this message translates to:
  /// **'今日投资策略'**
  String get strategiesTodayStrategies;

  /// No description provided for @strategiesHistoryStrategies.
  ///
  /// In zh, this message translates to:
  /// **'历史投资策略'**
  String get strategiesHistoryStrategies;

  /// No description provided for @strategiesNoHistory.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史策略'**
  String get strategiesNoHistory;

  /// No description provided for @featuredNoStrategyContent.
  ///
  /// In zh, this message translates to:
  /// **'暂无策略内容'**
  String get featuredNoStrategyContent;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageChinese.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageChinese;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @messagesLoginToUseChat.
  ///
  /// In zh, this message translates to:
  /// **'登录后使用聊天功能'**
  String get messagesLoginToUseChat;

  /// No description provided for @messagesLoginMethods.
  ///
  /// In zh, this message translates to:
  /// **'支持邮箱、Google、Apple 登录'**
  String get messagesLoginMethods;

  /// No description provided for @messagesAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'添加好友'**
  String get messagesAddFriend;

  /// No description provided for @addFriendScanQr.
  ///
  /// In zh, this message translates to:
  /// **'扫码添加'**
  String get addFriendScanQr;

  /// No description provided for @addFriendMyQrCode.
  ///
  /// In zh, this message translates to:
  /// **'我的二维码'**
  String get addFriendMyQrCode;

  /// No description provided for @addFriendTabEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get addFriendTabEmail;

  /// No description provided for @addFriendTabAccountId.
  ///
  /// In zh, this message translates to:
  /// **'账号ID'**
  String get addFriendTabAccountId;

  /// No description provided for @addFriendTabQrCode.
  ///
  /// In zh, this message translates to:
  /// **'二维码'**
  String get addFriendTabQrCode;

  /// No description provided for @addFriendHintEmail.
  ///
  /// In zh, this message translates to:
  /// **'请输入对方注册邮箱'**
  String get addFriendHintEmail;

  /// No description provided for @addFriendHintId.
  ///
  /// In zh, this message translates to:
  /// **'请输入对方账号 ID'**
  String get addFriendHintId;

  /// No description provided for @addFriendLabelTargetEmail.
  ///
  /// In zh, this message translates to:
  /// **'对方邮箱'**
  String get addFriendLabelTargetEmail;

  /// No description provided for @addFriendLabelAccountIdRule.
  ///
  /// In zh, this message translates to:
  /// **'账号 ID（6-9位数字）'**
  String get addFriendLabelAccountIdRule;

  /// No description provided for @addFriendEnterEmail.
  ///
  /// In zh, this message translates to:
  /// **'请输入邮箱'**
  String get addFriendEnterEmail;

  /// No description provided for @addFriendEnterAccountId.
  ///
  /// In zh, this message translates to:
  /// **'请输入账号ID'**
  String get addFriendEnterAccountId;

  /// No description provided for @addFriendUserNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到该用户'**
  String get addFriendUserNotFound;

  /// No description provided for @addFriendRequestSent.
  ///
  /// In zh, this message translates to:
  /// **'好友申请已发送'**
  String get addFriendRequestSent;

  /// No description provided for @addFriendAlreadyFriends.
  ///
  /// In zh, this message translates to:
  /// **'你们已是好友'**
  String get addFriendAlreadyFriends;

  /// No description provided for @addFriendAlreadyPending.
  ///
  /// In zh, this message translates to:
  /// **'已发送过申请，请等待对方处理'**
  String get addFriendAlreadyPending;

  /// No description provided for @commonGenerating.
  ///
  /// In zh, this message translates to:
  /// **'生成中...'**
  String get commonGenerating;

  /// No description provided for @addFriendAccountIdGenerating.
  ///
  /// In zh, this message translates to:
  /// **'账号ID：生成中...'**
  String get addFriendAccountIdGenerating;

  /// No description provided for @addFriendAccountIdValue.
  ///
  /// In zh, this message translates to:
  /// **'账号ID：{id}'**
  String addFriendAccountIdValue(String id);

  /// No description provided for @commonAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get commonAdd;

  /// No description provided for @featuredFollowTrader.
  ///
  /// In zh, this message translates to:
  /// **'关注交易员'**
  String get featuredFollowTrader;

  /// No description provided for @promoEnterSelectTrader.
  ///
  /// In zh, this message translates to:
  /// **'进入选择交易员'**
  String get promoEnterSelectTrader;

  /// No description provided for @messagesCreateGroup.
  ///
  /// In zh, this message translates to:
  /// **'创建群聊'**
  String get messagesCreateGroup;

  /// No description provided for @messagesSystemNotifications.
  ///
  /// In zh, this message translates to:
  /// **'系统消息'**
  String get messagesSystemNotifications;

  /// No description provided for @messagesSearchConversations.
  ///
  /// In zh, this message translates to:
  /// **'搜索会话'**
  String get messagesSearchConversations;

  /// No description provided for @messagesSearchFriends.
  ///
  /// In zh, this message translates to:
  /// **'搜索好友'**
  String get messagesSearchFriends;

  /// No description provided for @messagesRecentChats.
  ///
  /// In zh, this message translates to:
  /// **'最近会话'**
  String get messagesRecentChats;

  /// No description provided for @messagesFriendList.
  ///
  /// In zh, this message translates to:
  /// **'好友列表'**
  String get messagesFriendList;

  /// No description provided for @messagesFirebaseNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置 Firebase'**
  String get messagesFirebaseNotConfigured;

  /// No description provided for @messagesAddConfigFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先添加配置文件后再使用消息功能'**
  String get messagesAddConfigFirst;

  /// No description provided for @messagesSupabaseNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置 Supabase'**
  String get messagesSupabaseNotConfigured;

  /// No description provided for @messagesConfigureSupabase.
  ///
  /// In zh, this message translates to:
  /// **'请配置 SUPABASE_URL / SUPABASE_ANON_KEY'**
  String get messagesConfigureSupabase;

  /// No description provided for @messagesApiNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置后端 API'**
  String get messagesApiNotConfigured;

  /// No description provided for @messagesConfigureApi.
  ///
  /// In zh, this message translates to:
  /// **'请配置 TONGXIN_API_URL 并确保后端已启动'**
  String get messagesConfigureApi;

  /// No description provided for @marketTitle.
  ///
  /// In zh, this message translates to:
  /// **'市场'**
  String get marketTitle;

  /// No description provided for @marketTabHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get marketTabHome;

  /// No description provided for @marketTabUsStock.
  ///
  /// In zh, this message translates to:
  /// **'美股'**
  String get marketTabUsStock;

  /// No description provided for @marketTabForex.
  ///
  /// In zh, this message translates to:
  /// **'外汇'**
  String get marketTabForex;

  /// No description provided for @marketTabCrypto.
  ///
  /// In zh, this message translates to:
  /// **'加密货币'**
  String get marketTabCrypto;

  /// No description provided for @marketMajorIndexes.
  ///
  /// In zh, this message translates to:
  /// **'Major Indexes'**
  String get marketMajorIndexes;

  /// No description provided for @marketTopMovers.
  ///
  /// In zh, this message translates to:
  /// **'Top Movers'**
  String get marketTopMovers;

  /// No description provided for @marketGainers.
  ///
  /// In zh, this message translates to:
  /// **'Gainers'**
  String get marketGainers;

  /// No description provided for @marketLosers.
  ///
  /// In zh, this message translates to:
  /// **'Losers'**
  String get marketLosers;

  /// No description provided for @marketSearchSymbols.
  ///
  /// In zh, this message translates to:
  /// **'Search symbols'**
  String get marketSearchSymbols;

  /// No description provided for @marketGainersList.
  ///
  /// In zh, this message translates to:
  /// **'涨幅榜'**
  String get marketGainersList;

  /// No description provided for @marketLosersList.
  ///
  /// In zh, this message translates to:
  /// **'跌幅榜'**
  String get marketLosersList;

  /// No description provided for @marketNoForexData.
  ///
  /// In zh, this message translates to:
  /// **'暂无外汇数据'**
  String get marketNoForexData;

  /// No description provided for @marketLoadingUsStockList.
  ///
  /// In zh, this message translates to:
  /// **'正在加载全量美股列表…'**
  String get marketLoadingUsStockList;

  /// No description provided for @marketLoadingQuote.
  ///
  /// In zh, this message translates to:
  /// **'正在加载行情…'**
  String get marketLoadingQuote;

  /// No description provided for @marketNoUsStockList.
  ///
  /// In zh, this message translates to:
  /// **'暂无美股列表'**
  String get marketNoUsStockList;

  /// No description provided for @marketStockOrCryptoSearch.
  ///
  /// In zh, this message translates to:
  /// **'股票或加密货币名称、代码'**
  String get marketStockOrCryptoSearch;

  /// No description provided for @rankingsPromo1Title.
  ///
  /// In zh, this message translates to:
  /// **'跟对导师，收益可见'**
  String get rankingsPromo1Title;

  /// No description provided for @rankingsPromo1Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'策略透明 · 实盘可跟 · 每月收益一目了然'**
  String get rankingsPromo1Subtitle;

  /// No description provided for @rankingsPromo2Title.
  ///
  /// In zh, this message translates to:
  /// **'真人实盘，有据可查'**
  String get rankingsPromo2Title;

  /// No description provided for @rankingsPromo2Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'实名认证导师 · 胜率与盈亏全程可追踪'**
  String get rankingsPromo2Subtitle;

  /// No description provided for @rankingsPromo3Title.
  ///
  /// In zh, this message translates to:
  /// **'每月榜单，谁在领跑'**
  String get rankingsPromo3Title;

  /// No description provided for @rankingsPromo3Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'本月收益排行 · 一键关注 · 跟单不迷路'**
  String get rankingsPromo3Subtitle;

  /// No description provided for @rankingsLearnMore.
  ///
  /// In zh, this message translates to:
  /// **'了解更多'**
  String get rankingsLearnMore;

  /// No description provided for @rankingsMentorVerified.
  ///
  /// In zh, this message translates to:
  /// **'导师实名认证'**
  String get rankingsMentorVerified;

  /// No description provided for @rankingsStrategyTraceable.
  ///
  /// In zh, this message translates to:
  /// **'策略与收益可追踪'**
  String get rankingsStrategyTraceable;

  /// No description provided for @rankingsCommunitySupport.
  ///
  /// In zh, this message translates to:
  /// **'学员互动与社群支持'**
  String get rankingsCommunitySupport;

  /// No description provided for @rankingsMonthProfitRank.
  ///
  /// In zh, this message translates to:
  /// **'本月收益排行榜'**
  String get rankingsMonthProfitRank;

  /// No description provided for @rankingsRealtimeTransparent.
  ///
  /// In zh, this message translates to:
  /// **'实时 · 透明'**
  String get rankingsRealtimeTransparent;

  /// No description provided for @teachersNoStrategy.
  ///
  /// In zh, this message translates to:
  /// **'暂无策略'**
  String get teachersNoStrategy;

  /// No description provided for @marketIndexDowJones.
  ///
  /// In zh, this message translates to:
  /// **'道琼斯'**
  String get marketIndexDowJones;

  /// No description provided for @marketIndexNasdaq.
  ///
  /// In zh, this message translates to:
  /// **'纳斯达克'**
  String get marketIndexNasdaq;

  /// No description provided for @marketIndexSp500.
  ///
  /// In zh, this message translates to:
  /// **'标普500'**
  String get marketIndexSp500;

  /// No description provided for @marketAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get marketAll;

  /// No description provided for @marketNoWatchlist.
  ///
  /// In zh, this message translates to:
  /// **'暂无自选'**
  String get marketNoWatchlist;

  /// No description provided for @marketAddWatchlistHint.
  ///
  /// In zh, this message translates to:
  /// **'在搜索或详情页可添加自选'**
  String get marketAddWatchlistHint;

  /// No description provided for @marketGoAdd.
  ///
  /// In zh, this message translates to:
  /// **'去添加'**
  String get marketGoAdd;

  /// No description provided for @marketThreeIndices.
  ///
  /// In zh, this message translates to:
  /// **'三大指数'**
  String get marketThreeIndices;

  /// No description provided for @marketWatchlist.
  ///
  /// In zh, this message translates to:
  /// **'自选'**
  String get marketWatchlist;

  /// No description provided for @marketMockDataHint.
  ///
  /// In zh, this message translates to:
  /// **'当前为模拟数据。配置 TWELVE_DATA_API_KEY 后可显示真实行情。'**
  String get marketMockDataHint;

  /// No description provided for @marketNoDataConfigHint.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据，请配置 TWELVE_DATA_API_KEY 或稍后重试'**
  String get marketNoDataConfigHint;

  /// No description provided for @marketGlobalIndices.
  ///
  /// In zh, this message translates to:
  /// **'环球指数'**
  String get marketGlobalIndices;

  /// No description provided for @marketNews.
  ///
  /// In zh, this message translates to:
  /// **'资讯'**
  String get marketNews;

  /// No description provided for @marketQuoteLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'报价拉取失败：{error}'**
  String marketQuoteLoadFailed(String error);

  /// No description provided for @marketConnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法连接行情服务，请确认后端已启动（如 http://localhost:3000）'**
  String get marketConnectFailed;

  /// No description provided for @marketStockQuoteCacheEmpty.
  ///
  /// In zh, this message translates to:
  /// **'stock_quote_cache 表暂无数据，请确认后端已配置并实时更新该表'**
  String get marketStockQuoteCacheEmpty;

  /// No description provided for @marketCsvHeader.
  ///
  /// In zh, this message translates to:
  /// **'代码,名称,涨跌幅,最新价,涨跌额,今开,昨收,最高,最低,成交量'**
  String get marketCsvHeader;

  /// No description provided for @marketMockDataPcHint.
  ///
  /// In zh, this message translates to:
  /// **'当前为模拟数据，仅作界面展示。配置 POLYGON_API_KEY 后可显示真实行情。'**
  String get marketMockDataPcHint;

  /// No description provided for @marketExportCsv.
  ///
  /// In zh, this message translates to:
  /// **'导出 CSV'**
  String get marketExportCsv;

  /// No description provided for @marketHotNews.
  ///
  /// In zh, this message translates to:
  /// **'热点解读'**
  String get marketHotNews;

  /// No description provided for @marketSubscribeTopic.
  ///
  /// In zh, this message translates to:
  /// **'订阅专题'**
  String get marketSubscribeTopic;

  /// No description provided for @marketTradableCoins.
  ///
  /// In zh, this message translates to:
  /// **'可交易币种'**
  String get marketTradableCoins;

  /// No description provided for @marketMarketCap.
  ///
  /// In zh, this message translates to:
  /// **'市值'**
  String get marketMarketCap;

  /// No description provided for @marketTopGainers.
  ///
  /// In zh, this message translates to:
  /// **'领涨榜'**
  String get marketTopGainers;

  /// No description provided for @marketTopLosers.
  ///
  /// In zh, this message translates to:
  /// **'领跌榜'**
  String get marketTopLosers;

  /// No description provided for @authEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get authEmail;

  /// No description provided for @authThirdPartyLogin.
  ///
  /// In zh, this message translates to:
  /// **'第三方登录'**
  String get authThirdPartyLogin;

  /// No description provided for @authGoogleLogin.
  ///
  /// In zh, this message translates to:
  /// **'Google 登录'**
  String get authGoogleLogin;

  /// No description provided for @authAppleLogin.
  ///
  /// In zh, this message translates to:
  /// **'Apple 登录'**
  String get authAppleLogin;

  /// No description provided for @authRegisterAndSendEmail.
  ///
  /// In zh, this message translates to:
  /// **'注册并发送验证邮件'**
  String get authRegisterAndSendEmail;

  /// No description provided for @authConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'确认密码'**
  String get authConfirmPassword;

  /// No description provided for @authRegister.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get authRegister;

  /// No description provided for @authName.
  ///
  /// In zh, this message translates to:
  /// **'姓名'**
  String get authName;

  /// No description provided for @authSendVerificationEmail.
  ///
  /// In zh, this message translates to:
  /// **'发送验证邮件'**
  String get authSendVerificationEmail;

  /// No description provided for @authSendVerificationEmailCooldown.
  ///
  /// In zh, this message translates to:
  /// **'发送验证邮件（{seconds}s）'**
  String authSendVerificationEmailCooldown(int seconds);

  /// No description provided for @authFirebaseConfigHint.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置 Firebase，请先添加配置文件（google-services.json / GoogleService-Info.plist）。'**
  String get authFirebaseConfigHint;

  /// No description provided for @authVerificationSent.
  ///
  /// In zh, this message translates to:
  /// **'已发送验证邮件，请验证后再登录'**
  String get authVerificationSent;

  /// No description provided for @authFillNameEmailPassword.
  ///
  /// In zh, this message translates to:
  /// **'请先填写姓名、邮箱和两次密码'**
  String get authFillNameEmailPassword;

  /// No description provided for @authPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次密码不一致'**
  String get authPasswordMismatch;

  /// No description provided for @authPasswordMinLength.
  ///
  /// In zh, this message translates to:
  /// **'密码至少 6 位'**
  String get authPasswordMinLength;

  /// No description provided for @authResendCooldown.
  ///
  /// In zh, this message translates to:
  /// **'请稍后再试（{seconds}s）'**
  String authResendCooldown(int seconds);

  /// No description provided for @authVerificationEmailSent.
  ///
  /// In zh, this message translates to:
  /// **'验证邮件已发送，请检查邮箱'**
  String get authVerificationEmailSent;

  /// No description provided for @authMacosUseEmailOrGoogle.
  ///
  /// In zh, this message translates to:
  /// **'macOS 端请使用邮箱或 Google 登录。'**
  String get authMacosUseEmailOrGoogle;

  /// No description provided for @authWebAppleLimited.
  ///
  /// In zh, this message translates to:
  /// **'Web 端 Apple 登录受限，请使用邮箱或 Google。'**
  String get authWebAppleLimited;

  /// No description provided for @teachersNoRecord.
  ///
  /// In zh, this message translates to:
  /// **'暂无交易记录'**
  String get teachersNoRecord;

  /// No description provided for @teachersUploadRecord.
  ///
  /// In zh, this message translates to:
  /// **'上传记录'**
  String get teachersUploadRecord;

  /// No description provided for @teachersOffline.
  ///
  /// In zh, this message translates to:
  /// **'下架'**
  String get teachersOffline;

  /// No description provided for @teachersOnline.
  ///
  /// In zh, this message translates to:
  /// **'上架'**
  String get teachersOnline;

  /// No description provided for @teachersFrozenOrBlocked.
  ///
  /// In zh, this message translates to:
  /// **'您当前处于{status}状态，无法上传交易记录'**
  String teachersFrozenOrBlocked(String status);

  /// No description provided for @teachersFrozen.
  ///
  /// In zh, this message translates to:
  /// **'冻结'**
  String get teachersFrozen;

  /// No description provided for @teachersBlocked.
  ///
  /// In zh, this message translates to:
  /// **'封禁'**
  String get teachersBlocked;

  /// No description provided for @teachersReviewRequired.
  ///
  /// In zh, this message translates to:
  /// **'审核通过后开放交易记录上传'**
  String get teachersReviewRequired;

  /// No description provided for @teachersConfirmRiskAck.
  ///
  /// In zh, this message translates to:
  /// **'请确认已阅读风险提示'**
  String get teachersConfirmRiskAck;

  /// No description provided for @teachersRecordSaved.
  ///
  /// In zh, this message translates to:
  /// **'交易记录已保存'**
  String get teachersRecordSaved;

  /// No description provided for @teachersTradeRecordSymbol.
  ///
  /// In zh, this message translates to:
  /// **'品种'**
  String get teachersTradeRecordSymbol;

  /// No description provided for @teachersTradeRecordSide.
  ///
  /// In zh, this message translates to:
  /// **'方向（买/卖）'**
  String get teachersTradeRecordSide;

  /// No description provided for @teachersTradeRecordPnl.
  ///
  /// In zh, this message translates to:
  /// **'盈亏'**
  String get teachersTradeRecordPnl;

  /// No description provided for @teachersUploadQualification.
  ///
  /// In zh, this message translates to:
  /// **'上传资质照片'**
  String get teachersUploadQualification;

  /// No description provided for @teachersUploadIdPhoto.
  ///
  /// In zh, this message translates to:
  /// **'上传证件照'**
  String get teachersUploadIdPhoto;

  /// No description provided for @teachersUploadCertification.
  ///
  /// In zh, this message translates to:
  /// **'上传资质证明'**
  String get teachersUploadCertification;

  /// No description provided for @teachersRiskAckTitle.
  ///
  /// In zh, this message translates to:
  /// **'我已阅读并同意风险提示'**
  String get teachersRiskAckTitle;

  /// No description provided for @teachersPreviewHomepage.
  ///
  /// In zh, this message translates to:
  /// **'预览主页'**
  String get teachersPreviewHomepage;

  /// No description provided for @marketMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get marketMore;

  /// No description provided for @marketMajorIndices.
  ///
  /// In zh, this message translates to:
  /// **'主要指数'**
  String get marketMajorIndices;

  /// No description provided for @marketGainersLosers.
  ///
  /// In zh, this message translates to:
  /// **'涨跌榜'**
  String get marketGainersLosers;

  /// No description provided for @marketCrypto.
  ///
  /// In zh, this message translates to:
  /// **'加密货币'**
  String get marketCrypto;

  /// No description provided for @marketName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get marketName;

  /// No description provided for @marketLatestPrice.
  ///
  /// In zh, this message translates to:
  /// **'最新价'**
  String get marketLatestPrice;

  /// No description provided for @marketChangePct.
  ///
  /// In zh, this message translates to:
  /// **'涨跌幅'**
  String get marketChangePct;

  /// No description provided for @marketChangeAmount.
  ///
  /// In zh, this message translates to:
  /// **'涨跌额'**
  String get marketChangeAmount;

  /// No description provided for @marketOpen.
  ///
  /// In zh, this message translates to:
  /// **'今开'**
  String get marketOpen;

  /// No description provided for @marketPrevClose.
  ///
  /// In zh, this message translates to:
  /// **'昨收'**
  String get marketPrevClose;

  /// No description provided for @marketHigh.
  ///
  /// In zh, this message translates to:
  /// **'最高'**
  String get marketHigh;

  /// No description provided for @marketLow.
  ///
  /// In zh, this message translates to:
  /// **'最低'**
  String get marketLow;

  /// No description provided for @marketVolume.
  ///
  /// In zh, this message translates to:
  /// **'成交量'**
  String get marketVolume;

  /// No description provided for @marketTurnover.
  ///
  /// In zh, this message translates to:
  /// **'成交额'**
  String get marketTurnover;

  /// No description provided for @marketCode.
  ///
  /// In zh, this message translates to:
  /// **'代码'**
  String get marketCode;

  /// No description provided for @marketChange.
  ///
  /// In zh, this message translates to:
  /// **'涨跌额'**
  String get marketChange;

  /// No description provided for @marketHeatmap.
  ///
  /// In zh, this message translates to:
  /// **'市场热度 Heatmap'**
  String get marketHeatmap;

  /// No description provided for @marketTradeSubcategory.
  ///
  /// In zh, this message translates to:
  /// **'交易子类'**
  String get marketTradeSubcategory;

  /// No description provided for @marketHot.
  ///
  /// In zh, this message translates to:
  /// **'热门'**
  String get marketHot;

  /// No description provided for @marketGoSearch.
  ///
  /// In zh, this message translates to:
  /// **'去搜索'**
  String get marketGoSearch;

  /// No description provided for @tradingRecords.
  ///
  /// In zh, this message translates to:
  /// **'交易记录'**
  String get tradingRecords;

  /// No description provided for @tradingBuyApiPending.
  ///
  /// In zh, this message translates to:
  /// **'买入功能待接入行情 API'**
  String get tradingBuyApiPending;

  /// No description provided for @tradingSellApiPending.
  ///
  /// In zh, this message translates to:
  /// **'卖出功能待接入行情 API'**
  String get tradingSellApiPending;

  /// No description provided for @tradingRecordAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加一条交易记录'**
  String get tradingRecordAdded;

  /// No description provided for @tradingDeleteRecord.
  ///
  /// In zh, this message translates to:
  /// **'删除记录'**
  String get tradingDeleteRecord;

  /// No description provided for @tradingConfirmDeleteRecord.
  ///
  /// In zh, this message translates to:
  /// **'确定删除这条交易记录？'**
  String get tradingConfirmDeleteRecord;

  /// No description provided for @tradingDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get tradingDelete;

  /// No description provided for @tradingFillSymbol.
  ///
  /// In zh, this message translates to:
  /// **'请填写股票代码'**
  String get tradingFillSymbol;

  /// No description provided for @tradingFillPriceQty.
  ///
  /// In zh, this message translates to:
  /// **'请填写有效的价格与数量'**
  String get tradingFillPriceQty;

  /// No description provided for @tradingSymbolHint.
  ///
  /// In zh, this message translates to:
  /// **'输入股票代码或名称'**
  String get tradingSymbolHint;

  /// No description provided for @tradingSymbolLabel.
  ///
  /// In zh, this message translates to:
  /// **'标的'**
  String get tradingSymbolLabel;

  /// No description provided for @orderClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get orderClear;

  /// No description provided for @orderConfirmCancel.
  ///
  /// In zh, this message translates to:
  /// **'确定要撤销 {symbol} 的{action}委托吗？'**
  String orderConfirmCancel(String symbol, String action);

  /// No description provided for @orderCancelSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已撤单（模拟）'**
  String get orderCancelSuccess;

  /// No description provided for @orderCancelBuy.
  ///
  /// In zh, this message translates to:
  /// **'买入'**
  String get orderCancelBuy;

  /// No description provided for @orderCancelSell.
  ///
  /// In zh, this message translates to:
  /// **'卖出'**
  String get orderCancelSell;

  /// No description provided for @chartVolume.
  ///
  /// In zh, this message translates to:
  /// **'量'**
  String get chartVolume;

  /// No description provided for @chartPrevClose.
  ///
  /// In zh, this message translates to:
  /// **'昨收线'**
  String get chartPrevClose;

  /// No description provided for @chartOverlay.
  ///
  /// In zh, this message translates to:
  /// **'主图叠加'**
  String get chartOverlay;

  /// No description provided for @chartSubIndicator.
  ///
  /// In zh, this message translates to:
  /// **'副图指标'**
  String get chartSubIndicator;

  /// No description provided for @chartCurrentValue.
  ///
  /// In zh, this message translates to:
  /// **'当前数值'**
  String get chartCurrentValue;

  /// No description provided for @chartYes.
  ///
  /// In zh, this message translates to:
  /// **'有'**
  String get chartYes;

  /// No description provided for @chartNo.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get chartNo;

  /// No description provided for @chartBackToLatest.
  ///
  /// In zh, this message translates to:
  /// **'回最新'**
  String get chartBackToLatest;

  /// No description provided for @commonOpening.
  ///
  /// In zh, this message translates to:
  /// **'正在打开…'**
  String get commonOpening;

  /// No description provided for @commonFeatureDeveloping.
  ///
  /// In zh, this message translates to:
  /// **'功能正在开发中'**
  String get commonFeatureDeveloping;

  /// No description provided for @teachersNoTeachers.
  ///
  /// In zh, this message translates to:
  /// **'暂无交易员'**
  String get teachersNoTeachers;

  /// No description provided for @teachersTeacherHomepage.
  ///
  /// In zh, this message translates to:
  /// **'交易员主页'**
  String get teachersTeacherHomepage;

  /// No description provided for @teachersBecomeTeacher.
  ///
  /// In zh, this message translates to:
  /// **'成为交易员'**
  String get teachersBecomeTeacher;

  /// No description provided for @teachersHomepage.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get teachersHomepage;

  /// No description provided for @teachersNoTeacherInfo.
  ///
  /// In zh, this message translates to:
  /// **'暂无交易员信息'**
  String get teachersNoTeacherInfo;

  /// No description provided for @teachersNone.
  ///
  /// In zh, this message translates to:
  /// **'暂无'**
  String get teachersNone;

  /// No description provided for @callOtherCancelled.
  ///
  /// In zh, this message translates to:
  /// **'对方已取消'**
  String get callOtherCancelled;

  /// No description provided for @callOtherRejected.
  ///
  /// In zh, this message translates to:
  /// **'对方已拒绝'**
  String get callOtherRejected;

  /// No description provided for @callOtherHangup.
  ///
  /// In zh, this message translates to:
  /// **'对方已挂断'**
  String get callOtherHangup;

  /// No description provided for @callPleaseHangup.
  ///
  /// In zh, this message translates to:
  /// **'请点击挂断按钮结束通话'**
  String get callPleaseHangup;

  /// No description provided for @callHangup.
  ///
  /// In zh, this message translates to:
  /// **'挂断'**
  String get callHangup;

  /// No description provided for @callWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待对方接听...'**
  String get callWaiting;

  /// No description provided for @callJoinFailed.
  ///
  /// In zh, this message translates to:
  /// **'加入通话失败'**
  String get callJoinFailed;

  /// No description provided for @callFlipCamera.
  ///
  /// In zh, this message translates to:
  /// **'翻转'**
  String get callFlipCamera;

  /// No description provided for @callSpeaker.
  ///
  /// In zh, this message translates to:
  /// **'扬声器'**
  String get callSpeaker;

  /// No description provided for @callEarpiece.
  ///
  /// In zh, this message translates to:
  /// **'听筒'**
  String get callEarpiece;

  /// No description provided for @callCheckNetwork.
  ///
  /// In zh, this message translates to:
  /// **'若听不到声音请检查网络'**
  String get callCheckNetwork;

  /// No description provided for @callMute.
  ///
  /// In zh, this message translates to:
  /// **'静音'**
  String get callMute;

  /// No description provided for @callUnmute.
  ///
  /// In zh, this message translates to:
  /// **'取消静音'**
  String get callUnmute;

  /// No description provided for @notificationFullScreenHint.
  ///
  /// In zh, this message translates to:
  /// **'请在设置页开启「全屏 intent」开关'**
  String get notificationFullScreenHint;

  /// No description provided for @notificationNotEnabled.
  ///
  /// In zh, this message translates to:
  /// **'通知未开启'**
  String get notificationNotEnabled;

  /// No description provided for @notificationGoToAuth.
  ///
  /// In zh, this message translates to:
  /// **'去授权'**
  String get notificationGoToAuth;

  /// No description provided for @notificationGoToSettings.
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get notificationGoToSettings;

  /// No description provided for @appDownloadComing.
  ///
  /// In zh, this message translates to:
  /// **'下载地址敬请期待'**
  String get appDownloadComing;

  /// No description provided for @appDownloadOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开下载页'**
  String get appDownloadOpenFailed;

  /// No description provided for @chatFileExpired.
  ///
  /// In zh, this message translates to:
  /// **'文件已过期或不存在，请让对方重新发送'**
  String get chatFileExpired;

  /// No description provided for @searchAddedToWatchlist.
  ///
  /// In zh, this message translates to:
  /// **'已添加 {symbol} 到自选'**
  String searchAddedToWatchlist(String symbol);

  /// No description provided for @marketCopyCsvSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已复制 {count} 条到剪贴板（CSV）'**
  String marketCopyCsvSuccess(int count);

  /// No description provided for @msgFriendRequestAccepted.
  ///
  /// In zh, this message translates to:
  /// **'已通过，已添加为好友'**
  String get msgFriendRequestAccepted;

  /// No description provided for @msgAcceptFailed.
  ///
  /// In zh, this message translates to:
  /// **'通过失败'**
  String get msgAcceptFailed;

  /// No description provided for @msgRejectFailed.
  ///
  /// In zh, this message translates to:
  /// **'拒绝失败'**
  String get msgRejectFailed;

  /// No description provided for @msgSystemNotificationsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'好友申请、通过/拒绝记录会显示在这里'**
  String get msgSystemNotificationsEmptyHint;

  /// No description provided for @msgNoSystemNotifications.
  ///
  /// In zh, this message translates to:
  /// **'暂无系统消息'**
  String get msgNoSystemNotifications;

  /// No description provided for @msgPendingOther.
  ///
  /// In zh, this message translates to:
  /// **'待对方处理'**
  String get msgPendingOther;

  /// No description provided for @msgRequestAddYou.
  ///
  /// In zh, this message translates to:
  /// **'请求添加你为好友'**
  String get msgRequestAddYou;

  /// No description provided for @msgAccepted.
  ///
  /// In zh, this message translates to:
  /// **'已通过'**
  String get msgAccepted;

  /// No description provided for @msgRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get msgRejected;

  /// No description provided for @msgYouRequestAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'你请求添加 Ta 为好友'**
  String get msgYouRequestAddFriend;

  /// No description provided for @msgAcceptShort.
  ///
  /// In zh, this message translates to:
  /// **'通过'**
  String get msgAcceptShort;

  /// No description provided for @msgFriendRequestRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝好友申请'**
  String get msgFriendRequestRejected;

  /// No description provided for @msgOpenChatFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开私聊失败，请重试'**
  String get msgOpenChatFailed;

  /// No description provided for @msgOpenChatFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'打开私聊失败'**
  String get msgOpenChatFailedPrefix;

  /// No description provided for @msgConfirmDeleteFriend.
  ///
  /// In zh, this message translates to:
  /// **'确定删除 {name} 吗？'**
  String msgConfirmDeleteFriend(String name);

  /// No description provided for @msgFriendDeleted.
  ///
  /// In zh, this message translates to:
  /// **'好友已删除'**
  String get msgFriendDeleted;

  /// No description provided for @msgFriendRequestSent.
  ///
  /// In zh, this message translates to:
  /// **'已发送好友申请'**
  String get msgFriendRequestSent;

  /// No description provided for @msgSendMessage.
  ///
  /// In zh, this message translates to:
  /// **'发消息'**
  String get msgSendMessage;

  /// No description provided for @profilePersonalInfo.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get profilePersonalInfo;

  /// No description provided for @profileItsYou.
  ///
  /// In zh, this message translates to:
  /// **'这是你自己'**
  String get profileItsYou;

  /// No description provided for @msgSelectGroup.
  ///
  /// In zh, this message translates to:
  /// **'请从左侧选择用户'**
  String get msgSelectGroup;

  /// No description provided for @groupConfirmTransfer.
  ///
  /// In zh, this message translates to:
  /// **'确定将群主转让给 {name}？转让后您将变为管理员。'**
  String groupConfirmTransfer(String name);

  /// No description provided for @groupTransferSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已转让群主'**
  String get groupTransferSuccess;

  /// No description provided for @groupMemberRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移出群聊'**
  String get groupMemberRemoved;

  /// No description provided for @groupRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除（踢出群聊）'**
  String get groupRemove;

  /// No description provided for @groupTransferOwner.
  ///
  /// In zh, this message translates to:
  /// **'转让群主'**
  String get groupTransferOwner;

  /// No description provided for @groupSetAdmin.
  ///
  /// In zh, this message translates to:
  /// **'设为管理员'**
  String get groupSetAdmin;

  /// No description provided for @groupUnsetAdmin.
  ///
  /// In zh, this message translates to:
  /// **'取消管理员'**
  String get groupUnsetAdmin;

  /// No description provided for @groupConfirmCount.
  ///
  /// In zh, this message translates to:
  /// **'确定({count})'**
  String groupConfirmCount(int count);

  /// No description provided for @groupSelectFriends.
  ///
  /// In zh, this message translates to:
  /// **'选择好友'**
  String get groupSelectFriends;

  /// No description provided for @pcSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索…'**
  String get pcSearchHint;

  /// No description provided for @orderNoHistory.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史委托'**
  String get orderNoHistory;

  /// No description provided for @orderDate.
  ///
  /// In zh, this message translates to:
  /// **'日期'**
  String get orderDate;

  /// No description provided for @orderPrice.
  ///
  /// In zh, this message translates to:
  /// **'委托价'**
  String get orderPrice;

  /// No description provided for @orderFilled.
  ///
  /// In zh, this message translates to:
  /// **'已成交'**
  String get orderFilled;

  /// No description provided for @orderSimulated.
  ///
  /// In zh, this message translates to:
  /// **'（模拟数据）'**
  String get orderSimulated;

  /// No description provided for @orderStatusPending.
  ///
  /// In zh, this message translates to:
  /// **'待成交'**
  String get orderStatusPending;

  /// No description provided for @orderStatusPartial.
  ///
  /// In zh, this message translates to:
  /// **'部分成交'**
  String get orderStatusPartial;

  /// No description provided for @orderStatusCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已撤单'**
  String get orderStatusCancelled;

  /// No description provided for @orderStatusRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get orderStatusRejected;

  /// No description provided for @tradesFillsRecord.
  ///
  /// In zh, this message translates to:
  /// **'成交记录'**
  String get tradesFillsRecord;

  /// No description provided for @tradesCurrentPositions.
  ///
  /// In zh, this message translates to:
  /// **'当前持仓'**
  String get tradesCurrentPositions;

  /// No description provided for @tradesNoFills.
  ///
  /// In zh, this message translates to:
  /// **'暂无成交记录'**
  String get tradesNoFills;

  /// No description provided for @tradesNoPosition.
  ///
  /// In zh, this message translates to:
  /// **'暂无持仓'**
  String get tradesNoPosition;

  /// No description provided for @tradesLoadPositionsFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载持仓失败'**
  String get tradesLoadPositionsFailed;

  /// No description provided for @tradesPositionShares.
  ///
  /// In zh, this message translates to:
  /// **'持仓'**
  String get tradesPositionShares;

  /// No description provided for @tradesPnl.
  ///
  /// In zh, this message translates to:
  /// **'盈亏'**
  String get tradesPnl;

  /// No description provided for @tradesQuickSellPending.
  ///
  /// In zh, this message translates to:
  /// **'快捷卖出 {symbol}（待接入）'**
  String tradesQuickSellPending(String symbol);

  /// No description provided for @tradesSellPending.
  ///
  /// In zh, this message translates to:
  /// **'卖出 {symbol}（待接入）'**
  String tradesSellPending(String symbol);

  /// No description provided for @teachersProfileTitle.
  ///
  /// In zh, this message translates to:
  /// **'交易员资料'**
  String get teachersProfileTitle;

  /// No description provided for @teachersPersonalIntro.
  ///
  /// In zh, this message translates to:
  /// **'个人介绍'**
  String get teachersPersonalIntro;

  /// No description provided for @teachersExpertiseProducts.
  ///
  /// In zh, this message translates to:
  /// **'擅长品种'**
  String get teachersExpertiseProducts;

  /// No description provided for @teachersStrategySection.
  ///
  /// In zh, this message translates to:
  /// **'交易策略'**
  String get teachersStrategySection;

  /// No description provided for @teachersNoPublicStrategy.
  ///
  /// In zh, this message translates to:
  /// **'暂无公开策略'**
  String get teachersNoPublicStrategy;

  /// No description provided for @teachersEnterStrategyCenter.
  ///
  /// In zh, this message translates to:
  /// **'进入交易策略中心'**
  String get teachersEnterStrategyCenter;

  /// No description provided for @teachersFollowingCount.
  ///
  /// In zh, this message translates to:
  /// **'关注 {count}'**
  String teachersFollowingCount(int count);

  /// No description provided for @teachersSignatureLabel.
  ///
  /// In zh, this message translates to:
  /// **'个性签名'**
  String get teachersSignatureLabel;

  /// No description provided for @teachersLicenseNoLabel.
  ///
  /// In zh, this message translates to:
  /// **'执照/注册编号'**
  String get teachersLicenseNoLabel;

  /// No description provided for @teachersMainMarket.
  ///
  /// In zh, this message translates to:
  /// **'主要市场'**
  String get teachersMainMarket;

  /// No description provided for @teachersTradingStyleShort.
  ///
  /// In zh, this message translates to:
  /// **'交易风格'**
  String get teachersTradingStyleShort;

  /// No description provided for @teachersRecordAndEarnings.
  ///
  /// In zh, this message translates to:
  /// **'战绩与收益'**
  String get teachersRecordAndEarnings;

  /// No description provided for @teachersTotalEarnings.
  ///
  /// In zh, this message translates to:
  /// **'总收益'**
  String get teachersTotalEarnings;

  /// No description provided for @teachersMonthlyEarnings.
  ///
  /// In zh, this message translates to:
  /// **'月收益'**
  String get teachersMonthlyEarnings;

  /// No description provided for @teachersRatingLabel.
  ///
  /// In zh, this message translates to:
  /// **'评分'**
  String get teachersRatingLabel;

  /// No description provided for @teachersPerformanceSection.
  ///
  /// In zh, this message translates to:
  /// **'战绩表现'**
  String get teachersPerformanceSection;

  /// No description provided for @teachersIntroSection.
  ///
  /// In zh, this message translates to:
  /// **'个人介绍'**
  String get teachersIntroSection;

  /// No description provided for @teachersLatestArticles.
  ///
  /// In zh, this message translates to:
  /// **'最新文章'**
  String get teachersLatestArticles;

  /// No description provided for @teachersRecentSchedule.
  ///
  /// In zh, this message translates to:
  /// **'近期行程'**
  String get teachersRecentSchedule;

  /// No description provided for @msgGroupChat.
  ///
  /// In zh, this message translates to:
  /// **'群聊'**
  String get msgGroupChat;

  /// No description provided for @msgGroupChatN.
  ///
  /// In zh, this message translates to:
  /// **'群聊({n}人)'**
  String msgGroupChatN(int n);

  /// No description provided for @msgViewTraderProfile.
  ///
  /// In zh, this message translates to:
  /// **'查看交易员资料'**
  String get msgViewTraderProfile;

  /// No description provided for @msgExitedGroup.
  ///
  /// In zh, this message translates to:
  /// **'{name} 退出了群聊'**
  String msgExitedGroup(String name);

  /// No description provided for @msgJoinedGroup.
  ///
  /// In zh, this message translates to:
  /// **'{name} 加入了群聊'**
  String msgJoinedGroup(String name);

  /// No description provided for @msgAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'加好友'**
  String get msgAddFriend;

  /// No description provided for @msgAlreadyFriends.
  ///
  /// In zh, this message translates to:
  /// **'你们已是好友'**
  String get msgAlreadyFriends;

  /// No description provided for @msgAlreadyPending.
  ///
  /// In zh, this message translates to:
  /// **'已发送过申请，请等待对方处理'**
  String get msgAlreadyPending;

  /// No description provided for @msgAddFriendFailed.
  ///
  /// In zh, this message translates to:
  /// **'加好友失败'**
  String get msgAddFriendFailed;

  /// No description provided for @msgMePrefix.
  ///
  /// In zh, this message translates to:
  /// **'我: '**
  String get msgMePrefix;

  /// No description provided for @msgDraft.
  ///
  /// In zh, this message translates to:
  /// **'草稿：'**
  String get msgDraft;

  /// No description provided for @msgOpenChatFromList.
  ///
  /// In zh, this message translates to:
  /// **'打开私聊失败，请从消息列表进入'**
  String get msgOpenChatFromList;

  /// No description provided for @teachersMyTradeRecords.
  ///
  /// In zh, this message translates to:
  /// **'我的交易记录'**
  String get teachersMyTradeRecords;

  /// No description provided for @teachersNoTradeRecords.
  ///
  /// In zh, this message translates to:
  /// **'暂无交易记录'**
  String get teachersNoTradeRecords;

  /// No description provided for @teachersNoIntro.
  ///
  /// In zh, this message translates to:
  /// **'暂无介绍'**
  String get teachersNoIntro;

  /// No description provided for @msgPrivateChat.
  ///
  /// In zh, this message translates to:
  /// **'私聊'**
  String get msgPrivateChat;

  /// No description provided for @groupCreateGroup.
  ///
  /// In zh, this message translates to:
  /// **'创建群聊'**
  String get groupCreateGroup;

  /// No description provided for @groupCreateFailed.
  ///
  /// In zh, this message translates to:
  /// **'创建失败'**
  String get groupCreateFailed;

  /// No description provided for @groupCreateGroupHint.
  ///
  /// In zh, this message translates to:
  /// **'不填则显示为「群聊(n人)」'**
  String get groupCreateGroupHint;

  /// No description provided for @groupCreateGroupButton.
  ///
  /// In zh, this message translates to:
  /// **'创建群聊'**
  String get groupCreateGroupButton;

  /// No description provided for @groupCreateGroupButtonN.
  ///
  /// In zh, this message translates to:
  /// **'创建群聊({n}人)'**
  String groupCreateGroupButtonN(int n);

  /// No description provided for @groupGroupNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'群名称（可选）'**
  String get groupGroupNameLabel;

  /// No description provided for @groupNoFriendsHint.
  ///
  /// In zh, this message translates to:
  /// **'暂无好友，请先添加好友'**
  String get groupNoFriendsHint;

  /// No description provided for @groupSelectAtLeastOne.
  ///
  /// In zh, this message translates to:
  /// **'请至少选择一位好友'**
  String get groupSelectAtLeastOne;

  /// No description provided for @groupLeaveConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定退出该群聊？'**
  String get groupLeaveConfirm;

  /// No description provided for @groupLeaveSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已退出群聊'**
  String get groupLeaveSuccess;

  /// No description provided for @groupDismissConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定解散该群聊？所有成员将退出，聊天记录将无法恢复。'**
  String get groupDismissConfirm;

  /// No description provided for @groupDismissSuccess.
  ///
  /// In zh, this message translates to:
  /// **'群聊已解散'**
  String get groupDismissSuccess;

  /// No description provided for @groupRemoveConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定将该成员移出群聊？'**
  String get groupRemoveConfirm;

  /// No description provided for @groupSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'群设置'**
  String get groupSettingsTitle;

  /// No description provided for @groupGroupName.
  ///
  /// In zh, this message translates to:
  /// **'群名称'**
  String get groupGroupName;

  /// No description provided for @groupAnnouncement.
  ///
  /// In zh, this message translates to:
  /// **'群公告'**
  String get groupAnnouncement;

  /// No description provided for @groupMute.
  ///
  /// In zh, this message translates to:
  /// **'消息免打扰'**
  String get groupMute;

  /// No description provided for @groupInviteMembers.
  ///
  /// In zh, this message translates to:
  /// **'邀请新成员'**
  String get groupInviteMembers;

  /// No description provided for @groupInviteLink.
  ///
  /// In zh, this message translates to:
  /// **'群邀请链接'**
  String get groupInviteLink;

  /// No description provided for @groupMembersCount.
  ///
  /// In zh, this message translates to:
  /// **'群成员 ({count})'**
  String groupMembersCount(int count);

  /// No description provided for @groupLeave.
  ///
  /// In zh, this message translates to:
  /// **'退出群聊'**
  String get groupLeave;

  /// No description provided for @groupDismiss.
  ///
  /// In zh, this message translates to:
  /// **'解散群聊'**
  String get groupDismiss;

  /// No description provided for @groupRemoveMember.
  ///
  /// In zh, this message translates to:
  /// **'移除成员'**
  String get groupRemoveMember;

  /// No description provided for @groupRemoveAction.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get groupRemoveAction;

  /// No description provided for @groupSetAdminConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定将 {name} 设为管理员？'**
  String groupSetAdminConfirm(String name);

  /// No description provided for @groupUnsetAdminConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定取消 {name} 的管理员身份？'**
  String groupUnsetAdminConfirm(String name);

  /// No description provided for @groupSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get groupSaveFailed;

  /// No description provided for @groupLeaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'退出失败'**
  String get groupLeaveFailed;

  /// No description provided for @groupDismissFailed.
  ///
  /// In zh, this message translates to:
  /// **'解散失败'**
  String get groupDismissFailed;

  /// No description provided for @groupOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败'**
  String get groupOperationFailed;

  /// No description provided for @groupJoinLoginFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先登录后再加入群聊'**
  String get groupJoinLoginFirst;

  /// No description provided for @groupJoinTitle.
  ///
  /// In zh, this message translates to:
  /// **'加入群聊'**
  String get groupJoinTitle;

  /// No description provided for @groupJoinConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要加入该群聊吗？'**
  String get groupJoinConfirm;

  /// No description provided for @groupJoinSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已加入群聊，请在消息列表查看'**
  String get groupJoinSuccess;

  /// No description provided for @groupJoinFailed.
  ///
  /// In zh, this message translates to:
  /// **'加入失败'**
  String get groupJoinFailed;

  /// No description provided for @commonNone.
  ///
  /// In zh, this message translates to:
  /// **'暂无'**
  String get commonNone;

  /// No description provided for @commonLeave.
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get commonLeave;

  /// No description provided for @commonDismiss.
  ///
  /// In zh, this message translates to:
  /// **'解散'**
  String get commonDismiss;

  /// No description provided for @commonSuccess.
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get commonSuccess;

  /// No description provided for @chatNoMatchingMembers.
  ///
  /// In zh, this message translates to:
  /// **'暂无匹配成员'**
  String get chatNoMatchingMembers;

  /// No description provided for @chatNotFriendCannotSend.
  ///
  /// In zh, this message translates to:
  /// **'已不是好友，无法发送'**
  String get chatNotFriendCannotSend;

  /// No description provided for @chatRecordingTooShort.
  ///
  /// In zh, this message translates to:
  /// **'录音时间太短'**
  String get chatRecordingTooShort;

  /// No description provided for @chatGrantMicPermission.
  ///
  /// In zh, this message translates to:
  /// **'请授予麦克风权限'**
  String get chatGrantMicPermission;

  /// No description provided for @chatNoSupabaseCannotSendMedia.
  ///
  /// In zh, this message translates to:
  /// **'未配置 Supabase，无法发送媒体'**
  String get chatNoSupabaseCannotSendMedia;

  /// No description provided for @chatFileEmptyCannotSend.
  ///
  /// In zh, this message translates to:
  /// **'文件为空，无法发送'**
  String get chatFileEmptyCannotSend;

  /// No description provided for @chatSendFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'发送失败'**
  String get chatSendFailedPrefix;

  /// No description provided for @chatCannotReadFile.
  ///
  /// In zh, this message translates to:
  /// **'无法读取该文件'**
  String get chatCannotReadFile;

  /// No description provided for @chatSelectFileFailed.
  ///
  /// In zh, this message translates to:
  /// **'选择文件失败'**
  String get chatSelectFileFailed;

  /// No description provided for @chatForwardInDevelopment.
  ///
  /// In zh, this message translates to:
  /// **'转发功能正在开发中'**
  String get chatForwardInDevelopment;

  /// No description provided for @chatRecalled.
  ///
  /// In zh, this message translates to:
  /// **'已撤回'**
  String get chatRecalled;

  /// No description provided for @chatRecallFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'撤回失败'**
  String get chatRecallFailedPrefix;

  /// No description provided for @chatCallLabel.
  ///
  /// In zh, this message translates to:
  /// **'通话'**
  String get chatCallLabel;

  /// No description provided for @chatFileSendFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'文件发送失败'**
  String get chatFileSendFailedPrefix;

  /// No description provided for @chatRemarkSaved.
  ///
  /// In zh, this message translates to:
  /// **'备注已保存'**
  String get chatRemarkSaved;

  /// No description provided for @chatUnpinned.
  ///
  /// In zh, this message translates to:
  /// **'已取消置顶'**
  String get chatUnpinned;

  /// No description provided for @chatPinned.
  ///
  /// In zh, this message translates to:
  /// **'已置顶会话'**
  String get chatPinned;

  /// No description provided for @chatHistoryCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清空聊天记录'**
  String get chatHistoryCleared;

  /// No description provided for @chatClearFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'清空失败'**
  String get chatClearFailedPrefix;

  /// No description provided for @chatJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get chatJustNow;

  /// No description provided for @chatToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get chatToday;

  /// No description provided for @chatYesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get chatYesterday;

  /// No description provided for @chatUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get chatUnknown;

  /// No description provided for @chatLastOnline.
  ///
  /// In zh, this message translates to:
  /// **'最后上线：'**
  String get chatLastOnline;

  /// No description provided for @chatNoNetworkNoCache.
  ///
  /// In zh, this message translates to:
  /// **'无网络，暂无本地缓存'**
  String get chatNoNetworkNoCache;

  /// No description provided for @chatNoMessagesYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有聊天记录'**
  String get chatNoMessagesYet;

  /// No description provided for @chatRecordingReleaseToSend.
  ///
  /// In zh, this message translates to:
  /// **'录音中…松开发送'**
  String get chatRecordingReleaseToSend;

  /// No description provided for @chatKeyboard.
  ///
  /// In zh, this message translates to:
  /// **'键盘'**
  String get chatKeyboard;

  /// No description provided for @chatVoice.
  ///
  /// In zh, this message translates to:
  /// **'语音'**
  String get chatVoice;

  /// No description provided for @chatHoldToSpeak.
  ///
  /// In zh, this message translates to:
  /// **'按住 说话'**
  String get chatHoldToSpeak;

  /// No description provided for @chatReleaseToSend.
  ///
  /// In zh, this message translates to:
  /// **'松开发送'**
  String get chatReleaseToSend;

  /// No description provided for @chatAnswered.
  ///
  /// In zh, this message translates to:
  /// **'已接听'**
  String get chatAnswered;

  /// No description provided for @chatDeclined.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get chatDeclined;

  /// No description provided for @chatCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get chatCancelled;

  /// No description provided for @chatMissed.
  ///
  /// In zh, this message translates to:
  /// **'未接听'**
  String get chatMissed;

  /// No description provided for @chatVoiceCall.
  ///
  /// In zh, this message translates to:
  /// **'语音通话'**
  String get chatVoiceCall;

  /// No description provided for @chatVideoCall.
  ///
  /// In zh, this message translates to:
  /// **'视频通话'**
  String get chatVideoCall;

  /// No description provided for @chatMeStatus.
  ///
  /// In zh, this message translates to:
  /// **'我 · {status}'**
  String chatMeStatus(String status);

  /// No description provided for @chatOtherStatus.
  ///
  /// In zh, this message translates to:
  /// **'对方 · {status}'**
  String chatOtherStatus(String status);

  /// No description provided for @chatOpening.
  ///
  /// In zh, this message translates to:
  /// **'正在打开…'**
  String get chatOpening;

  /// No description provided for @chatCannotOpenFile.
  ///
  /// In zh, this message translates to:
  /// **'无法打开该文件'**
  String get chatCannotOpenFile;

  /// No description provided for @chatVideoLoadFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'视频加载失败'**
  String get chatVideoLoadFailedPrefix;

  /// No description provided for @chatMinutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count}分钟前'**
  String chatMinutesAgo(int count);

  /// No description provided for @chatTodayAt.
  ///
  /// In zh, this message translates to:
  /// **'今天 {time}'**
  String chatTodayAt(String time);

  /// No description provided for @chatYesterdayAt.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {time}'**
  String chatYesterdayAt(String time);

  /// No description provided for @chatDaysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count}天前'**
  String chatDaysAgo(int count);

  /// No description provided for @chatDateMonthDay.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 {time}'**
  String chatDateMonthDay(int month, int day, String time);

  /// No description provided for @chatDateFull.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月{day}日'**
  String chatDateFull(int year, int month, int day);

  /// No description provided for @chatLastOnlineLabel.
  ///
  /// In zh, this message translates to:
  /// **'最后上线：'**
  String get chatLastOnlineLabel;

  /// No description provided for @chatWebRecordingNotSupported.
  ///
  /// In zh, this message translates to:
  /// **'Web 暂不支持录音'**
  String get chatWebRecordingNotSupported;

  /// No description provided for @chatWebFileNotSupported.
  ///
  /// In zh, this message translates to:
  /// **'Web 暂不支持发送文件'**
  String get chatWebFileNotSupported;

  /// No description provided for @chatFileExpiredOrNotExist.
  ///
  /// In zh, this message translates to:
  /// **'文件已过期或不存在，请让对方重新发送'**
  String get chatFileExpiredOrNotExist;

  /// No description provided for @chatTypeImage.
  ///
  /// In zh, this message translates to:
  /// **'[图片]'**
  String get chatTypeImage;

  /// No description provided for @chatTypeVideo.
  ///
  /// In zh, this message translates to:
  /// **'[视频]'**
  String get chatTypeVideo;

  /// No description provided for @chatTypeAudio.
  ///
  /// In zh, this message translates to:
  /// **'[语音]'**
  String get chatTypeAudio;

  /// No description provided for @chatTypeFile.
  ///
  /// In zh, this message translates to:
  /// **'[文件]'**
  String get chatTypeFile;

  /// No description provided for @chatTeacherCard.
  ///
  /// In zh, this message translates to:
  /// **'[交易员名片]'**
  String get chatTeacherCard;

  /// No description provided for @groupInviteFriends.
  ///
  /// In zh, this message translates to:
  /// **'邀请好友进群'**
  String get groupInviteFriends;

  /// No description provided for @groupInviteFriendHint.
  ///
  /// In zh, this message translates to:
  /// **'好友打开链接或扫描二维码即可申请加入'**
  String get groupInviteFriendHint;

  /// No description provided for @groupInviteFriendHintWithName.
  ///
  /// In zh, this message translates to:
  /// **'好友打开链接或扫描二维码即可申请加入「{name}」'**
  String groupInviteFriendHintWithName(String name);

  /// No description provided for @groupCopyInviteLink.
  ///
  /// In zh, this message translates to:
  /// **'复制邀请链接'**
  String get groupCopyInviteLink;

  /// No description provided for @groupClickLinkToJoin.
  ///
  /// In zh, this message translates to:
  /// **'点击此链接加入群：{link}'**
  String groupClickLinkToJoin(String link);

  /// No description provided for @groupLinkCopied.
  ///
  /// In zh, this message translates to:
  /// **'链接已复制，好友点击链接即可加入群'**
  String get groupLinkCopied;

  /// No description provided for @groupQrInvite.
  ///
  /// In zh, this message translates to:
  /// **'二维码邀请'**
  String get groupQrInvite;

  /// No description provided for @groupQrCopied.
  ///
  /// In zh, this message translates to:
  /// **'扫码加入群'**
  String get groupQrCopied;

  /// No description provided for @groupAppNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'未安装 App？前往下载'**
  String get groupAppNotInstalled;

  /// No description provided for @groupAppNotInstalledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'好友未安装时可引导其下载'**
  String get groupAppNotInstalledSubtitle;

  /// No description provided for @groupScanToJoin.
  ///
  /// In zh, this message translates to:
  /// **'扫码加入「{name}」'**
  String groupScanToJoin(String name);

  /// No description provided for @groupScanWithApp.
  ///
  /// In zh, this message translates to:
  /// **'好友使用本 App 扫一扫即可进群'**
  String get groupScanWithApp;

  /// No description provided for @groupClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get groupClose;

  /// No description provided for @groupOwner.
  ///
  /// In zh, this message translates to:
  /// **'群主'**
  String get groupOwner;

  /// No description provided for @groupNoFriendsToInvite.
  ///
  /// In zh, this message translates to:
  /// **'没有可邀请的好友'**
  String get groupNoFriendsToInvite;

  /// No description provided for @groupInvitedCount.
  ///
  /// In zh, this message translates to:
  /// **'已邀请 {count} 人'**
  String groupInvitedCount(int count);

  /// No description provided for @groupInviteFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'邀请失败'**
  String get groupInviteFailedPrefix;

  /// No description provided for @groupEditName.
  ///
  /// In zh, this message translates to:
  /// **'修改群名称'**
  String get groupEditName;

  /// No description provided for @groupNameHint.
  ///
  /// In zh, this message translates to:
  /// **'群名称'**
  String get groupNameHint;

  /// No description provided for @groupNameUpdated.
  ///
  /// In zh, this message translates to:
  /// **'群名称已更新'**
  String get groupNameUpdated;

  /// No description provided for @groupMuteOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启消息免打扰'**
  String get groupMuteOn;

  /// No description provided for @groupMuteOff.
  ///
  /// In zh, this message translates to:
  /// **'已关闭消息免打扰'**
  String get groupMuteOff;

  /// No description provided for @groupNoSupabaseUpload.
  ///
  /// In zh, this message translates to:
  /// **'未配置 Supabase，无法上传'**
  String get groupNoSupabaseUpload;

  /// No description provided for @groupAvatarUpdated.
  ///
  /// In zh, this message translates to:
  /// **'群头像已更新'**
  String get groupAvatarUpdated;

  /// No description provided for @groupUploadFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'上传失败'**
  String get groupUploadFailedPrefix;

  /// No description provided for @groupShortLabel.
  ///
  /// In zh, this message translates to:
  /// **'群'**
  String get groupShortLabel;

  /// No description provided for @groupEditAnnouncement.
  ///
  /// In zh, this message translates to:
  /// **'群公告'**
  String get groupEditAnnouncement;

  /// No description provided for @groupAnnouncementHint.
  ///
  /// In zh, this message translates to:
  /// **'输入群公告'**
  String get groupAnnouncementHint;

  /// No description provided for @groupAnnouncementUpdated.
  ///
  /// In zh, this message translates to:
  /// **'群公告已更新'**
  String get groupAnnouncementUpdated;

  /// No description provided for @groupLoadFailedPrefix.
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get groupLoadFailedPrefix;

  /// No description provided for @groupLoadError.
  ///
  /// In zh, this message translates to:
  /// **'无法加载群信息'**
  String get groupLoadError;

  /// No description provided for @groupInviteNewMembers.
  ///
  /// In zh, this message translates to:
  /// **'邀请新成员'**
  String get groupInviteNewMembers;

  /// No description provided for @groupConfirmCountShort.
  ///
  /// In zh, this message translates to:
  /// **'确定({count})'**
  String groupConfirmCountShort(int count);

  /// No description provided for @groupMemberListTitle.
  ///
  /// In zh, this message translates to:
  /// **'群成员 ({count})'**
  String groupMemberListTitle(int count);

  /// No description provided for @groupRoleOwner.
  ///
  /// In zh, this message translates to:
  /// **'群主'**
  String get groupRoleOwner;

  /// No description provided for @groupRoleAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get groupRoleAdmin;

  /// No description provided for @groupMemberHint.
  ///
  /// In zh, this message translates to:
  /// **'点击右侧 ⋮ 可移出、转让群主、设管理员'**
  String get groupMemberHint;

  /// No description provided for @ordersConfirmCancel.
  ///
  /// In zh, this message translates to:
  /// **'确认撤单'**
  String get ordersConfirmCancel;

  /// No description provided for @ordersTodayOrders.
  ///
  /// In zh, this message translates to:
  /// **'当日委托'**
  String get ordersTodayOrders;

  /// No description provided for @ordersNoTodayOrders.
  ///
  /// In zh, this message translates to:
  /// **'暂无当日委托'**
  String get ordersNoTodayOrders;

  /// No description provided for @ordersOrderPrice.
  ///
  /// In zh, this message translates to:
  /// **'委托价'**
  String get ordersOrderPrice;

  /// No description provided for @ordersQuantity.
  ///
  /// In zh, this message translates to:
  /// **'数量'**
  String get ordersQuantity;

  /// No description provided for @ordersFilled.
  ///
  /// In zh, this message translates to:
  /// **'已成交'**
  String get ordersFilled;

  /// No description provided for @ordersCancelOrder.
  ///
  /// In zh, this message translates to:
  /// **'撤单'**
  String get ordersCancelOrder;

  /// No description provided for @ordersStatusPending.
  ///
  /// In zh, this message translates to:
  /// **'待成交'**
  String get ordersStatusPending;

  /// No description provided for @ordersStatusPartial.
  ///
  /// In zh, this message translates to:
  /// **'部分成交'**
  String get ordersStatusPartial;

  /// No description provided for @ordersStatusFilled.
  ///
  /// In zh, this message translates to:
  /// **'已成交'**
  String get ordersStatusFilled;

  /// No description provided for @ordersStatusCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已撤单'**
  String get ordersStatusCancelled;

  /// No description provided for @ordersStatusRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get ordersStatusRejected;

  /// No description provided for @ordersBuy.
  ///
  /// In zh, this message translates to:
  /// **'买入'**
  String get ordersBuy;

  /// No description provided for @ordersSell.
  ///
  /// In zh, this message translates to:
  /// **'卖出'**
  String get ordersSell;

  /// No description provided for @ordersMarket.
  ///
  /// In zh, this message translates to:
  /// **'市价'**
  String get ordersMarket;

  /// No description provided for @marketGainersLosersTitle.
  ///
  /// In zh, this message translates to:
  /// **'涨跌榜'**
  String get marketGainersLosersTitle;

  /// No description provided for @marketThreeIndicesLabel.
  ///
  /// In zh, this message translates to:
  /// **'三大指数'**
  String get marketThreeIndicesLabel;

  /// No description provided for @marketNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get marketNameLabel;

  /// No description provided for @msgNewFriendRequest.
  ///
  /// In zh, this message translates to:
  /// **'你有一条新的好友申请'**
  String get msgNewFriendRequest;

  /// No description provided for @msgNewFriendRequests.
  ///
  /// In zh, this message translates to:
  /// **'你有 {count} 条新的好友申请'**
  String msgNewFriendRequests(int count);

  /// No description provided for @msgNoNicknameSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置昵称'**
  String get msgNoNicknameSet;

  /// No description provided for @msgSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索好友/备注/账号ID'**
  String get msgSearchHint;

  /// No description provided for @msgShowBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'显示黑名单'**
  String get msgShowBlacklist;

  /// No description provided for @msgHideBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'隐藏黑名单'**
  String get msgHideBlacklist;

  /// No description provided for @msgBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'黑名单'**
  String get msgBlacklist;

  /// No description provided for @msgBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已拉黑'**
  String get msgBlocked;

  /// No description provided for @msgRemoveFromBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'移出黑名单'**
  String get msgRemoveFromBlacklist;

  /// No description provided for @msgAddToBlacklist.
  ///
  /// In zh, this message translates to:
  /// **'加入黑名单'**
  String get msgAddToBlacklist;

  /// No description provided for @msgDeleteFriend.
  ///
  /// In zh, this message translates to:
  /// **'删除好友'**
  String get msgDeleteFriend;

  /// No description provided for @msgSetRemark.
  ///
  /// In zh, this message translates to:
  /// **'设置备注名'**
  String get msgSetRemark;

  /// No description provided for @msgRemarkHint.
  ///
  /// In zh, this message translates to:
  /// **'输入备注名'**
  String get msgRemarkHint;

  /// No description provided for @msgNoConversations.
  ///
  /// In zh, this message translates to:
  /// **'暂无会话'**
  String get msgNoConversations;

  /// No description provided for @msgNoMatchingConversations.
  ///
  /// In zh, this message translates to:
  /// **'未找到匹配的会话'**
  String get msgNoMatchingConversations;

  /// No description provided for @msgFriendRequest.
  ///
  /// In zh, this message translates to:
  /// **'好友申请'**
  String get msgFriendRequest;

  /// No description provided for @msgNoFriends.
  ///
  /// In zh, this message translates to:
  /// **'暂无好友'**
  String get msgNoFriends;

  /// No description provided for @msgOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get msgOnline;

  /// No description provided for @msgOffline.
  ///
  /// In zh, this message translates to:
  /// **'离线'**
  String get msgOffline;

  /// No description provided for @msgFeatureDeveloping.
  ///
  /// In zh, this message translates to:
  /// **'功能正在开发中'**
  String get msgFeatureDeveloping;

  /// No description provided for @msgUnpin.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get msgUnpin;

  /// No description provided for @msgPin.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get msgPin;

  /// No description provided for @msgDeleteConversation.
  ///
  /// In zh, this message translates to:
  /// **'删除会话'**
  String get msgDeleteConversation;

  /// No description provided for @msgDeleteFriendConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除 {name} 吗？'**
  String msgDeleteFriendConfirm(String name);

  /// No description provided for @msgDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get msgDelete;

  /// No description provided for @msgSelectConversation.
  ///
  /// In zh, this message translates to:
  /// **'选择会话开始聊天'**
  String get msgSelectConversation;

  /// No description provided for @msgClickLeftToOpen.
  ///
  /// In zh, this message translates to:
  /// **'在左侧点击任一会话即可打开'**
  String get msgClickLeftToOpen;

  /// No description provided for @msgMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get msgMore;

  /// No description provided for @msgDecline.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get msgDecline;

  /// No description provided for @msgAccept.
  ///
  /// In zh, this message translates to:
  /// **'同意'**
  String get msgAccept;

  /// No description provided for @msgOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败'**
  String get msgOperationFailed;

  /// No description provided for @msgSearchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败'**
  String get msgSearchFailed;

  /// No description provided for @msgSendFailed.
  ///
  /// In zh, this message translates to:
  /// **'发送失败'**
  String get msgSendFailed;

  /// No description provided for @msgAcceptFriendSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已同意好友申请'**
  String get msgAcceptFriendSuccess;

  /// No description provided for @msgRejectFriendSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝好友申请'**
  String get msgRejectFriendSuccess;

  /// No description provided for @tradingCurrentPositions.
  ///
  /// In zh, this message translates to:
  /// **'当前持仓'**
  String get tradingCurrentPositions;

  /// No description provided for @tradingMyRecords.
  ///
  /// In zh, this message translates to:
  /// **'我的交易记录'**
  String get tradingMyRecords;

  /// No description provided for @tradingNoRecordsAdd.
  ///
  /// In zh, this message translates to:
  /// **'暂无记录，点击右下角 + 添加'**
  String get tradingNoRecordsAdd;

  /// No description provided for @tradingRealtimeQuote.
  ///
  /// In zh, this message translates to:
  /// **'实时行情'**
  String get tradingRealtimeQuote;

  /// No description provided for @tradingCurrentPrice.
  ///
  /// In zh, this message translates to:
  /// **'当前价'**
  String get tradingCurrentPrice;

  /// No description provided for @tradingChangePct.
  ///
  /// In zh, this message translates to:
  /// **'涨跌幅'**
  String get tradingChangePct;

  /// No description provided for @tradingAddRecord.
  ///
  /// In zh, this message translates to:
  /// **'添加交易记录'**
  String get tradingAddRecord;

  /// No description provided for @tradingStockCode.
  ///
  /// In zh, this message translates to:
  /// **'股票代码'**
  String get tradingStockCode;

  /// No description provided for @tradingStockName.
  ///
  /// In zh, this message translates to:
  /// **'股票名称'**
  String get tradingStockName;

  /// No description provided for @tradingBuyTime.
  ///
  /// In zh, this message translates to:
  /// **'买入时机'**
  String get tradingBuyTime;

  /// No description provided for @tradingBuyPrice.
  ///
  /// In zh, this message translates to:
  /// **'买入价格'**
  String get tradingBuyPrice;

  /// No description provided for @tradingBuyQty.
  ///
  /// In zh, this message translates to:
  /// **'买入数量'**
  String get tradingBuyQty;

  /// No description provided for @tradingSellTime.
  ///
  /// In zh, this message translates to:
  /// **'卖出时间'**
  String get tradingSellTime;

  /// No description provided for @tradingSellPrice.
  ///
  /// In zh, this message translates to:
  /// **'卖出价格'**
  String get tradingSellPrice;

  /// No description provided for @tradingSellQty.
  ///
  /// In zh, this message translates to:
  /// **'卖出数量'**
  String get tradingSellQty;

  /// No description provided for @tradingCost.
  ///
  /// In zh, this message translates to:
  /// **'成本'**
  String get tradingCost;

  /// No description provided for @tradingCurrentPriceLabel.
  ///
  /// In zh, this message translates to:
  /// **'现价'**
  String get tradingCurrentPriceLabel;

  /// No description provided for @tradingHintStockCode.
  ///
  /// In zh, this message translates to:
  /// **'如 600519'**
  String get tradingHintStockCode;

  /// No description provided for @tradingHintStockName.
  ///
  /// In zh, this message translates to:
  /// **'选填，如 贵州茅台'**
  String get tradingHintStockName;

  /// No description provided for @tradingQty.
  ///
  /// In zh, this message translates to:
  /// **'数量'**
  String get tradingQty;

  /// No description provided for @tradingPnl.
  ///
  /// In zh, this message translates to:
  /// **'盈亏'**
  String get tradingPnl;

  /// No description provided for @tradingHintYuan.
  ///
  /// In zh, this message translates to:
  /// **'元'**
  String get tradingHintYuan;

  /// No description provided for @tradingHintShares.
  ///
  /// In zh, this message translates to:
  /// **'股/手'**
  String get tradingHintShares;

  /// No description provided for @searchUsStock.
  ///
  /// In zh, this message translates to:
  /// **'美股'**
  String get searchUsStock;

  /// No description provided for @searchCrypto.
  ///
  /// In zh, this message translates to:
  /// **'加密货币'**
  String get searchCrypto;

  /// No description provided for @searchForex.
  ///
  /// In zh, this message translates to:
  /// **'外汇'**
  String get searchForex;

  /// No description provided for @searchIndex.
  ///
  /// In zh, this message translates to:
  /// **'指数'**
  String get searchIndex;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'股票或加密货币名称、代码'**
  String get searchHint;

  /// No description provided for @searchInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入股票或加密货币名称、代码搜索'**
  String get searchInputHint;

  /// No description provided for @searchNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到「{query}」相关标的'**
  String searchNotFound(String query);

  /// No description provided for @searchAddWatchlist.
  ///
  /// In zh, this message translates to:
  /// **'加自选'**
  String get searchAddWatchlist;

  /// No description provided for @commonUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get commonUnknown;

  /// No description provided for @commonUserInitial.
  ///
  /// In zh, this message translates to:
  /// **'用'**
  String get commonUserInitial;

  /// No description provided for @groupNewMember.
  ///
  /// In zh, this message translates to:
  /// **'新成员'**
  String get groupNewMember;

  /// No description provided for @groupSomeUser.
  ///
  /// In zh, this message translates to:
  /// **'某用户'**
  String get groupSomeUser;

  /// No description provided for @commonListSeparator.
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get commonListSeparator;

  /// No description provided for @watchlistTitle.
  ///
  /// In zh, this message translates to:
  /// **'自选'**
  String get watchlistTitle;

  /// No description provided for @watchlistAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get watchlistAdd;

  /// No description provided for @watchlistRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除自选'**
  String get watchlistRemove;

  /// No description provided for @marketIndexDow.
  ///
  /// In zh, this message translates to:
  /// **'道琼斯'**
  String get marketIndexDow;

  /// No description provided for @marketRequestTimeout.
  ///
  /// In zh, this message translates to:
  /// **'首页行情请求超时'**
  String get marketRequestTimeout;

  /// No description provided for @chartNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get chartNoData;

  /// No description provided for @chartLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中…'**
  String get chartLoading;

  /// No description provided for @chartPreMarket.
  ///
  /// In zh, this message translates to:
  /// **'未开市'**
  String get chartPreMarket;

  /// No description provided for @chartClosed.
  ///
  /// In zh, this message translates to:
  /// **'已收盘'**
  String get chartClosed;

  /// No description provided for @chartIntraday.
  ///
  /// In zh, this message translates to:
  /// **'盘中'**
  String get chartIntraday;

  /// No description provided for @chartPrice.
  ///
  /// In zh, this message translates to:
  /// **'价'**
  String get chartPrice;

  /// No description provided for @chartAvg.
  ///
  /// In zh, this message translates to:
  /// **'均'**
  String get chartAvg;

  /// No description provided for @chartChangeShort.
  ///
  /// In zh, this message translates to:
  /// **'涨'**
  String get chartChangeShort;

  /// No description provided for @chartVol.
  ///
  /// In zh, this message translates to:
  /// **'量'**
  String get chartVol;

  /// No description provided for @chartTurnover.
  ///
  /// In zh, this message translates to:
  /// **'额'**
  String get chartTurnover;

  /// No description provided for @chartFetching.
  ///
  /// In zh, this message translates to:
  /// **'正在拉取数据…'**
  String get chartFetching;

  /// No description provided for @chartFetchingWithLabel.
  ///
  /// In zh, this message translates to:
  /// **'正在拉取{label}数据…'**
  String chartFetchingWithLabel(String label);

  /// No description provided for @chartTimeshareLabel.
  ///
  /// In zh, this message translates to:
  /// **'分时'**
  String get chartTimeshareLabel;

  /// No description provided for @chartKlineLabel.
  ///
  /// In zh, this message translates to:
  /// **'K线'**
  String get chartKlineLabel;

  /// No description provided for @chartChangePercent.
  ///
  /// In zh, this message translates to:
  /// **'涨跌幅'**
  String get chartChangePercent;

  /// No description provided for @chartEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'分时与 K 线数据暂时无法加载，请稍后重试或检查数据源配置'**
  String get chartEmptyHint;

  /// No description provided for @chartNoIntradayData.
  ///
  /// In zh, this message translates to:
  /// **'暂无分时数据'**
  String get chartNoIntradayData;

  /// No description provided for @chartNoKlineData.
  ///
  /// In zh, this message translates to:
  /// **'暂无K线数据'**
  String get chartNoKlineData;

  /// No description provided for @chartRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get chartRetry;

  /// No description provided for @chartSwitchDataSource.
  ///
  /// In zh, this message translates to:
  /// **'切换数据源'**
  String get chartSwitchDataSource;

  /// No description provided for @chartPriceOpen.
  ///
  /// In zh, this message translates to:
  /// **'今开'**
  String get chartPriceOpen;

  /// No description provided for @chartPriceHigh.
  ///
  /// In zh, this message translates to:
  /// **'最高'**
  String get chartPriceHigh;

  /// No description provided for @chartPriceLow.
  ///
  /// In zh, this message translates to:
  /// **'最低'**
  String get chartPriceLow;

  /// No description provided for @chartPricePrevClose.
  ///
  /// In zh, this message translates to:
  /// **'昨收'**
  String get chartPricePrevClose;

  /// No description provided for @chartPriceTotalTurnover.
  ///
  /// In zh, this message translates to:
  /// **'总成交'**
  String get chartPriceTotalTurnover;

  /// No description provided for @chartPriceTurnoverRate.
  ///
  /// In zh, this message translates to:
  /// **'换手率'**
  String get chartPriceTurnoverRate;

  /// No description provided for @chartPriceAmplitude.
  ///
  /// In zh, this message translates to:
  /// **'振幅'**
  String get chartPriceAmplitude;

  /// No description provided for @chartStatsOpen.
  ///
  /// In zh, this message translates to:
  /// **'开'**
  String get chartStatsOpen;

  /// No description provided for @chartStatsHigh.
  ///
  /// In zh, this message translates to:
  /// **'高'**
  String get chartStatsHigh;

  /// No description provided for @chartStatsLow.
  ///
  /// In zh, this message translates to:
  /// **'低'**
  String get chartStatsLow;

  /// No description provided for @chartStatsClose.
  ///
  /// In zh, this message translates to:
  /// **'收'**
  String get chartStatsClose;

  /// No description provided for @chartStatsPrevClose.
  ///
  /// In zh, this message translates to:
  /// **'昨收'**
  String get chartStatsPrevClose;

  /// No description provided for @chartStatsChange.
  ///
  /// In zh, this message translates to:
  /// **'涨跌'**
  String get chartStatsChange;

  /// No description provided for @chartStatsChangePct.
  ///
  /// In zh, this message translates to:
  /// **'涨跌幅'**
  String get chartStatsChangePct;

  /// No description provided for @chartStatsAmplitude.
  ///
  /// In zh, this message translates to:
  /// **'振幅'**
  String get chartStatsAmplitude;

  /// No description provided for @chartStatsAvgPrice.
  ///
  /// In zh, this message translates to:
  /// **'均价'**
  String get chartStatsAvgPrice;

  /// No description provided for @chartStatsVolume.
  ///
  /// In zh, this message translates to:
  /// **'成交量'**
  String get chartStatsVolume;

  /// No description provided for @chartStatsTurnover.
  ///
  /// In zh, this message translates to:
  /// **'成交额'**
  String get chartStatsTurnover;

  /// No description provided for @chartStatsDividendYield.
  ///
  /// In zh, this message translates to:
  /// **'股息率'**
  String get chartStatsDividendYield;

  /// No description provided for @chartStatsTurnoverRate.
  ///
  /// In zh, this message translates to:
  /// **'换手率'**
  String get chartStatsTurnoverRate;

  /// No description provided for @chartStatsPeTtm.
  ///
  /// In zh, this message translates to:
  /// **'市盈率TTM'**
  String get chartStatsPeTtm;

  /// No description provided for @chartOrderBookSell.
  ///
  /// In zh, this message translates to:
  /// **'卖一'**
  String get chartOrderBookSell;

  /// No description provided for @chartOrderBookQty.
  ///
  /// In zh, this message translates to:
  /// **'数量'**
  String get chartOrderBookQty;

  /// No description provided for @chartOrderBookBuy.
  ///
  /// In zh, this message translates to:
  /// **'买一'**
  String get chartOrderBookBuy;

  /// No description provided for @chartTabOrderBook.
  ///
  /// In zh, this message translates to:
  /// **'盘口'**
  String get chartTabOrderBook;

  /// No description provided for @chartTabIndicator.
  ///
  /// In zh, this message translates to:
  /// **'指标'**
  String get chartTabIndicator;

  /// No description provided for @chartTabCapital.
  ///
  /// In zh, this message translates to:
  /// **'资金'**
  String get chartTabCapital;

  /// No description provided for @chartTabNews.
  ///
  /// In zh, this message translates to:
  /// **'新闻'**
  String get chartTabNews;

  /// No description provided for @chartTabAnnouncement.
  ///
  /// In zh, this message translates to:
  /// **'公告'**
  String get chartTabAnnouncement;

  /// No description provided for @chartIndicatorNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get chartIndicatorNone;

  /// No description provided for @chartIndicatorYes.
  ///
  /// In zh, this message translates to:
  /// **'有'**
  String get chartIndicatorYes;

  /// No description provided for @chartIndicatorNo.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get chartIndicatorNo;

  /// No description provided for @chartPrevCloseLine.
  ///
  /// In zh, this message translates to:
  /// **'昨收线'**
  String get chartPrevCloseLine;

  /// No description provided for @chartMainOverlay.
  ///
  /// In zh, this message translates to:
  /// **'主图叠加'**
  String get chartMainOverlay;

  /// No description provided for @chartQuoteLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get chartQuoteLoadFailed;

  /// No description provided for @chartClickToClose.
  ///
  /// In zh, this message translates to:
  /// **'点击图表关闭'**
  String get chartClickToClose;

  /// No description provided for @chartMockDataHint.
  ///
  /// In zh, this message translates to:
  /// **'模拟数据，仅作展示'**
  String get chartMockDataHint;

  /// No description provided for @chartCompanyActions.
  ///
  /// In zh, this message translates to:
  /// **'公司行动'**
  String get chartCompanyActions;

  /// No description provided for @chartDividends.
  ///
  /// In zh, this message translates to:
  /// **'分红'**
  String get chartDividends;

  /// No description provided for @chartSplits.
  ///
  /// In zh, this message translates to:
  /// **'拆股'**
  String get chartSplits;

  /// No description provided for @chartQuoteRefreshHint.
  ///
  /// In zh, this message translates to:
  /// **'每秒更新报价，图表每10秒刷新'**
  String get chartQuoteRefreshHint;

  /// No description provided for @chartOhlcHint.
  ///
  /// In zh, this message translates to:
  /// **'下方为当日开、高、低、收等行情'**
  String get chartOhlcHint;

  /// No description provided for @chartRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求失败: {error}'**
  String chartRequestFailed(String error);

  /// No description provided for @chartClickRetry.
  ///
  /// In zh, this message translates to:
  /// **'点击刷新重试'**
  String get chartClickRetry;

  /// No description provided for @chartNoDataTroubleshoot.
  ///
  /// In zh, this message translates to:
  /// **'若仍无数据：请确认后端已启动；真机/模拟器将 .env 中 TONGXIN_API_URL 改为本机 IP'**
  String get chartNoDataTroubleshoot;

  /// No description provided for @chartNoChartData.
  ///
  /// In zh, this message translates to:
  /// **'暂无图表数据'**
  String get chartNoChartData;

  /// No description provided for @chartWeekK.
  ///
  /// In zh, this message translates to:
  /// **'周K'**
  String get chartWeekK;

  /// No description provided for @chartMonthK.
  ///
  /// In zh, this message translates to:
  /// **'月K'**
  String get chartMonthK;

  /// No description provided for @chartYearK.
  ///
  /// In zh, this message translates to:
  /// **'年K'**
  String get chartYearK;

  /// No description provided for @chart1Min.
  ///
  /// In zh, this message translates to:
  /// **'1分'**
  String get chart1Min;

  /// No description provided for @chart5Min.
  ///
  /// In zh, this message translates to:
  /// **'5分'**
  String get chart5Min;

  /// No description provided for @chart15Min.
  ///
  /// In zh, this message translates to:
  /// **'15分'**
  String get chart15Min;

  /// No description provided for @chart30Min.
  ///
  /// In zh, this message translates to:
  /// **'30分'**
  String get chart30Min;

  /// No description provided for @chart1min.
  ///
  /// In zh, this message translates to:
  /// **'1分'**
  String get chart1min;

  /// No description provided for @chart5min.
  ///
  /// In zh, this message translates to:
  /// **'5分'**
  String get chart5min;

  /// No description provided for @chart15min.
  ///
  /// In zh, this message translates to:
  /// **'15分'**
  String get chart15min;

  /// No description provided for @chart30min.
  ///
  /// In zh, this message translates to:
  /// **'30分'**
  String get chart30min;

  /// No description provided for @chartDayK.
  ///
  /// In zh, this message translates to:
  /// **'日K'**
  String get chartDayK;

  /// No description provided for @chartTimeshare.
  ///
  /// In zh, this message translates to:
  /// **'分时'**
  String get chartTimeshare;

  /// No description provided for @promoTitle.
  ///
  /// In zh, this message translates to:
  /// **'金融培训机构\n专注实盘与策略落地'**
  String get promoTitle;

  /// No description provided for @promoSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'资深导师带你建立策略体系，从认知到执行全面提升。'**
  String get promoSubtitle;

  /// No description provided for @promoFeature1.
  ///
  /// In zh, this message translates to:
  /// **'导师认证与战绩公示'**
  String get promoFeature1;

  /// No description provided for @promoFeature2.
  ///
  /// In zh, this message translates to:
  /// **'每日策略与持仓跟踪'**
  String get promoFeature2;

  /// No description provided for @promoFeature3.
  ///
  /// In zh, this message translates to:
  /// **'同学互助与社群交流'**
  String get promoFeature3;

  /// No description provided for @promoCarouselTitle.
  ///
  /// In zh, this message translates to:
  /// **'教学特色'**
  String get promoCarouselTitle;

  /// No description provided for @promoSlide1Title.
  ///
  /// In zh, this message translates to:
  /// **'量化与风控'**
  String get promoSlide1Title;

  /// No description provided for @promoSlide1Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'策略复盘 + 风控模型 + 实盘跟踪'**
  String get promoSlide1Subtitle;

  /// No description provided for @promoSlide2Title.
  ///
  /// In zh, this message translates to:
  /// **'资产配置'**
  String get promoSlide2Title;

  /// No description provided for @promoSlide2Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'多维度资产组合，稳健增值'**
  String get promoSlide2Subtitle;

  /// No description provided for @promoSlide3Title.
  ///
  /// In zh, this message translates to:
  /// **'导师陪跑'**
  String get promoSlide3Title;

  /// No description provided for @promoSlide3Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'每日策略解读与实操指导'**
  String get promoSlide3Subtitle;

  /// No description provided for @promoBrand.
  ///
  /// In zh, this message translates to:
  /// **'金融培训机构'**
  String get promoBrand;

  /// No description provided for @notifChannelChat.
  ///
  /// In zh, this message translates to:
  /// **'消息通知'**
  String get notifChannelChat;

  /// No description provided for @notifChannelCall.
  ///
  /// In zh, this message translates to:
  /// **'来电'**
  String get notifChannelCall;

  /// No description provided for @notifOther.
  ///
  /// In zh, this message translates to:
  /// **'对方'**
  String get notifOther;

  /// No description provided for @notifInviteCall.
  ///
  /// In zh, this message translates to:
  /// **'{name} 邀请你{type}通话'**
  String notifInviteCall(String name, String type);

  /// No description provided for @notifVideoCall.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get notifVideoCall;

  /// No description provided for @notifVoiceCall.
  ///
  /// In zh, this message translates to:
  /// **'语音'**
  String get notifVoiceCall;

  /// No description provided for @notifNewMessage.
  ///
  /// In zh, this message translates to:
  /// **'新消息'**
  String get notifNewMessage;

  /// No description provided for @notifNewMessageBody.
  ///
  /// In zh, this message translates to:
  /// **'你收到一条新消息'**
  String get notifNewMessageBody;

  /// No description provided for @notifFullScreenIntentHint.
  ///
  /// In zh, this message translates to:
  /// **'请在设置页开启「全屏 intent」开关'**
  String get notifFullScreenIntentHint;

  /// No description provided for @notifNotEnabled.
  ///
  /// In zh, this message translates to:
  /// **'通知未开启'**
  String get notifNotEnabled;

  /// No description provided for @notifPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'您已拒绝通知权限，将无法收到新消息提醒。可点击「去授权」再次请求，或到系统设置中开启。'**
  String get notifPermissionDenied;

  /// No description provided for @notifGoAuthorize.
  ///
  /// In zh, this message translates to:
  /// **'去授权'**
  String get notifGoAuthorize;

  /// No description provided for @notifGoSettings.
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get notifGoSettings;

  /// No description provided for @restrictStatusNormal.
  ///
  /// In zh, this message translates to:
  /// **'账号状态：正常'**
  String get restrictStatusNormal;

  /// No description provided for @restrictBannedUntil.
  ///
  /// In zh, this message translates to:
  /// **'账号已封禁至 {date}'**
  String restrictBannedUntil(String date);

  /// No description provided for @restrictFrozenUntil.
  ///
  /// In zh, this message translates to:
  /// **'账号已冻结至 {date}'**
  String restrictFrozenUntil(String date);

  /// No description provided for @restrictLogin.
  ///
  /// In zh, this message translates to:
  /// **'账号状态：已限制登录'**
  String get restrictLogin;

  /// No description provided for @restrictSendMessage.
  ///
  /// In zh, this message translates to:
  /// **'账号状态：已限制发消息'**
  String get restrictSendMessage;

  /// No description provided for @restrictAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'账号状态：已禁止加好友'**
  String get restrictAddFriend;

  /// No description provided for @restrictJoinGroup.
  ///
  /// In zh, this message translates to:
  /// **'账号状态：已禁止加入群聊'**
  String get restrictJoinGroup;

  /// No description provided for @restrictCreateGroup.
  ///
  /// In zh, this message translates to:
  /// **'账号状态：已禁止建群'**
  String get restrictCreateGroup;

  /// No description provided for @adminOverview.
  ///
  /// In zh, this message translates to:
  /// **'总览'**
  String get adminOverview;

  /// No description provided for @adminUserManagement.
  ///
  /// In zh, this message translates to:
  /// **'用户管理'**
  String get adminUserManagement;

  /// No description provided for @adminTeacherReview.
  ///
  /// In zh, this message translates to:
  /// **'交易员审核'**
  String get adminTeacherReview;

  /// No description provided for @adminSystemMessages.
  ///
  /// In zh, this message translates to:
  /// **'系统消息'**
  String get adminSystemMessages;

  /// No description provided for @adminReports.
  ///
  /// In zh, this message translates to:
  /// **'举报与审核'**
  String get adminReports;

  /// No description provided for @adminSettings.
  ///
  /// In zh, this message translates to:
  /// **'系统设置'**
  String get adminSettings;

  /// No description provided for @adminKeyMetrics.
  ///
  /// In zh, this message translates to:
  /// **'关键指标与系统状态'**
  String get adminKeyMetrics;

  /// No description provided for @adminTeachersTotal.
  ///
  /// In zh, this message translates to:
  /// **'交易员总数'**
  String get adminTeachersTotal;

  /// No description provided for @adminPending.
  ///
  /// In zh, this message translates to:
  /// **'待审核'**
  String get adminPending;

  /// No description provided for @adminApproved.
  ///
  /// In zh, this message translates to:
  /// **'已通过'**
  String get adminApproved;

  /// No description provided for @adminRejected.
  ///
  /// In zh, this message translates to:
  /// **'已驳回'**
  String get adminRejected;

  /// No description provided for @adminFrozen.
  ///
  /// In zh, this message translates to:
  /// **'已冻结'**
  String get adminFrozen;

  /// No description provided for @adminBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已封禁'**
  String get adminBlocked;

  /// No description provided for @adminSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get adminSaved;

  /// No description provided for @adminSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get adminSaveFailed;

  /// No description provided for @adminUserProfile.
  ///
  /// In zh, this message translates to:
  /// **'用户资料'**
  String get adminUserProfile;

  /// No description provided for @adminRestrictAndBan.
  ///
  /// In zh, this message translates to:
  /// **'限制与封禁'**
  String get adminRestrictAndBan;

  /// No description provided for @adminBanUntil.
  ///
  /// In zh, this message translates to:
  /// **'封禁至 {date}'**
  String adminBanUntil(String date);

  /// No description provided for @adminFrozenUntil.
  ///
  /// In zh, this message translates to:
  /// **'冻结至 {date}'**
  String adminFrozenUntil(String date);

  /// No description provided for @adminBan.
  ///
  /// In zh, this message translates to:
  /// **'封禁'**
  String get adminBan;

  /// No description provided for @adminFreeze.
  ///
  /// In zh, this message translates to:
  /// **'冻结'**
  String get adminFreeze;

  /// No description provided for @adminRestrictHint.
  ///
  /// In zh, this message translates to:
  /// **'权限开关（开启即禁止该用户对应行为）'**
  String get adminRestrictHint;

  /// No description provided for @adminRestrictLogin.
  ///
  /// In zh, this message translates to:
  /// **'限制登录'**
  String get adminRestrictLogin;

  /// No description provided for @adminRestrictLoginSub.
  ///
  /// In zh, this message translates to:
  /// **'禁止该账号登录'**
  String get adminRestrictLoginSub;

  /// No description provided for @adminRestrictSendMessage.
  ///
  /// In zh, this message translates to:
  /// **'限制发消息'**
  String get adminRestrictSendMessage;

  /// No description provided for @adminRestrictAddFriend.
  ///
  /// In zh, this message translates to:
  /// **'禁止加好友'**
  String get adminRestrictAddFriend;

  /// No description provided for @adminRestrictJoinGroup.
  ///
  /// In zh, this message translates to:
  /// **'禁止加入群聊'**
  String get adminRestrictJoinGroup;

  /// No description provided for @adminRestrictCreateGroup.
  ///
  /// In zh, this message translates to:
  /// **'禁止建群'**
  String get adminRestrictCreateGroup;

  /// No description provided for @adminBanDuration.
  ///
  /// In zh, this message translates to:
  /// **'封禁时长'**
  String get adminBanDuration;

  /// No description provided for @adminFrozenDuration.
  ///
  /// In zh, this message translates to:
  /// **'冻结时长'**
  String get adminFrozenDuration;

  /// No description provided for @adminDays7.
  ///
  /// In zh, this message translates to:
  /// **'7 天'**
  String get adminDays7;

  /// No description provided for @adminDays30.
  ///
  /// In zh, this message translates to:
  /// **'30 天'**
  String get adminDays30;

  /// No description provided for @adminDays90.
  ///
  /// In zh, this message translates to:
  /// **'90 天'**
  String get adminDays90;

  /// No description provided for @adminPermanent.
  ///
  /// In zh, this message translates to:
  /// **'永久'**
  String get adminPermanent;

  /// No description provided for @adminSelectUser.
  ///
  /// In zh, this message translates to:
  /// **'请从左侧选择用户'**
  String get adminSelectUser;

  /// No description provided for @adminNoUserData.
  ///
  /// In zh, this message translates to:
  /// **'暂无用户数据'**
  String get adminNoUserData;

  /// No description provided for @adminUsersCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 人'**
  String adminUsersCount(int count);

  /// No description provided for @adminRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get adminRefresh;

  /// No description provided for @adminPlaceholderHint.
  ///
  /// In zh, this message translates to:
  /// **'此模块已搭好框架，下一步接入数据与操作逻辑。'**
  String get adminPlaceholderHint;

  /// No description provided for @adminSystemMessagesDesc.
  ///
  /// In zh, this message translates to:
  /// **'编辑系统公告、推送通知、运营消息模板。'**
  String get adminSystemMessagesDesc;

  /// No description provided for @adminReportsDesc.
  ///
  /// In zh, this message translates to:
  /// **'处理用户举报、内容风控、违规记录。'**
  String get adminReportsDesc;

  /// No description provided for @adminSettingsDesc.
  ///
  /// In zh, this message translates to:
  /// **'运营开关、基础配置、版本策略。'**
  String get adminSettingsDesc;

  /// No description provided for @adminSystemMessagesHint.
  ///
  /// In zh, this message translates to:
  /// **'建议接入 messages 与推送函数 send_push。'**
  String get adminSystemMessagesHint;

  /// No description provided for @adminNickname.
  ///
  /// In zh, this message translates to:
  /// **'昵称'**
  String get adminNickname;

  /// No description provided for @adminShortId.
  ///
  /// In zh, this message translates to:
  /// **'短号'**
  String get adminShortId;

  /// No description provided for @adminRole.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get adminRole;

  /// No description provided for @adminUserId.
  ///
  /// In zh, this message translates to:
  /// **'用户 ID'**
  String get adminUserId;

  /// No description provided for @adminSignature.
  ///
  /// In zh, this message translates to:
  /// **'个性签名'**
  String get adminSignature;

  /// No description provided for @adminProfileSaved.
  ///
  /// In zh, this message translates to:
  /// **'资料已保存'**
  String get adminProfileSaved;

  /// No description provided for @adminStatusUpdated.
  ///
  /// In zh, this message translates to:
  /// **'状态已更新为：{label}'**
  String adminStatusUpdated(String label);

  /// No description provided for @adminUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败'**
  String get adminUpdateFailed;

  /// No description provided for @adminSelectTeacher.
  ///
  /// In zh, this message translates to:
  /// **'请选择交易员'**
  String get adminSelectTeacher;

  /// No description provided for @adminPerformanceLabel.
  ///
  /// In zh, this message translates to:
  /// **'业绩说明'**
  String get adminPerformanceLabel;

  /// No description provided for @adminIdPhotoLabel.
  ///
  /// In zh, this message translates to:
  /// **'证件与资质照片'**
  String get adminIdPhotoLabel;

  /// No description provided for @adminReviewCredentials.
  ///
  /// In zh, this message translates to:
  /// **'审核资料（证件与资质）'**
  String get adminReviewCredentials;

  /// No description provided for @adminSaveProfile.
  ///
  /// In zh, this message translates to:
  /// **'保存资料'**
  String get adminSaveProfile;

  /// No description provided for @adminAddStrategy.
  ///
  /// In zh, this message translates to:
  /// **'新增策略'**
  String get adminAddStrategy;

  /// No description provided for @adminAddTradeRecord.
  ///
  /// In zh, this message translates to:
  /// **'新增交易记录'**
  String get adminAddTradeRecord;

  /// No description provided for @adminAddCurrentPosition.
  ///
  /// In zh, this message translates to:
  /// **'新增当前持仓'**
  String get adminAddCurrentPosition;

  /// No description provided for @adminAddHistoryPosition.
  ///
  /// In zh, this message translates to:
  /// **'新增历史持仓'**
  String get adminAddHistoryPosition;

  /// No description provided for @adminAddComment.
  ///
  /// In zh, this message translates to:
  /// **'新增评论'**
  String get adminAddComment;

  /// No description provided for @adminAddArticle.
  ///
  /// In zh, this message translates to:
  /// **'新增文章'**
  String get adminAddArticle;

  /// No description provided for @adminAddSchedule.
  ///
  /// In zh, this message translates to:
  /// **'新增日程'**
  String get adminAddSchedule;

  /// No description provided for @adminNotUploaded.
  ///
  /// In zh, this message translates to:
  /// **'未上传'**
  String get adminNotUploaded;

  /// No description provided for @adminApprove.
  ///
  /// In zh, this message translates to:
  /// **'审核通过'**
  String get adminApprove;

  /// No description provided for @adminReject.
  ///
  /// In zh, this message translates to:
  /// **'驳回'**
  String get adminReject;

  /// No description provided for @adminUnfreeze.
  ///
  /// In zh, this message translates to:
  /// **'解除冻结'**
  String get adminUnfreeze;

  /// No description provided for @adminUnblock.
  ///
  /// In zh, this message translates to:
  /// **'解除封禁'**
  String get adminUnblock;

  /// No description provided for @adminRevertToPending.
  ///
  /// In zh, this message translates to:
  /// **'改为待审核'**
  String get adminRevertToPending;

  /// No description provided for @adminNotifyTraderResult.
  ///
  /// In zh, this message translates to:
  /// **'交易员申请结果'**
  String get adminNotifyTraderResult;

  /// No description provided for @adminNotifyRejected.
  ///
  /// In zh, this message translates to:
  /// **'您的交易员申请已被驳回，可修改后重新提交。'**
  String get adminNotifyRejected;

  /// No description provided for @adminNotifyApproved.
  ///
  /// In zh, this message translates to:
  /// **'恭喜，您的交易员申请已通过，可以发布策略与交易记录。'**
  String get adminNotifyApproved;

  /// No description provided for @adminNotifyBlocked.
  ///
  /// In zh, this message translates to:
  /// **'您的交易员账号已被封禁，如有疑问请联系客服。'**
  String get adminNotifyBlocked;

  /// No description provided for @adminNotifyFrozen.
  ///
  /// In zh, this message translates to:
  /// **'您的交易员账号已被冻结，冻结期内无法发布内容。'**
  String get adminNotifyFrozen;

  /// No description provided for @adminAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get adminAll;

  /// No description provided for @adminPendingJustApplied.
  ///
  /// In zh, this message translates to:
  /// **'待审核（刚刚申请）'**
  String get adminPendingJustApplied;

  /// No description provided for @adminAllTeachers.
  ///
  /// In zh, this message translates to:
  /// **'全部交易员'**
  String get adminAllTeachers;

  /// No description provided for @adminTeachersCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 人'**
  String adminTeachersCount(int count);

  /// No description provided for @adminRefreshList.
  ///
  /// In zh, this message translates to:
  /// **'刷新列表'**
  String get adminRefreshList;

  /// No description provided for @adminFilterByStatus.
  ///
  /// In zh, this message translates to:
  /// **'按状态筛选'**
  String get adminFilterByStatus;

  /// No description provided for @adminNoTeachersData.
  ///
  /// In zh, this message translates to:
  /// **'暂无交易员数据'**
  String get adminNoTeachersData;

  /// No description provided for @adminNoMatchingData.
  ///
  /// In zh, this message translates to:
  /// **'暂无符合条件的数据'**
  String get adminNoMatchingData;

  /// No description provided for @adminConfirmTableData.
  ///
  /// In zh, this message translates to:
  /// **'请确认 teacher_profiles 表已有数据'**
  String get adminConfirmTableData;

  /// No description provided for @adminTrySwitchAll.
  ///
  /// In zh, this message translates to:
  /// **'可尝试切换「全部」查看'**
  String get adminTrySwitchAll;

  /// No description provided for @adminActionsByStatus.
  ///
  /// In zh, this message translates to:
  /// **'操作（根据当前状态）'**
  String get adminActionsByStatus;

  /// No description provided for @adminBasicInfo.
  ///
  /// In zh, this message translates to:
  /// **'基础信息'**
  String get adminBasicInfo;

  /// No description provided for @adminDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'展示名'**
  String get adminDisplayName;

  /// No description provided for @adminRealName.
  ///
  /// In zh, this message translates to:
  /// **'真实姓名'**
  String get adminRealName;

  /// No description provided for @adminTitlePosition.
  ///
  /// In zh, this message translates to:
  /// **'职位/称号'**
  String get adminTitlePosition;

  /// No description provided for @adminOrg.
  ///
  /// In zh, this message translates to:
  /// **'机构'**
  String get adminOrg;

  /// No description provided for @adminBio.
  ///
  /// In zh, this message translates to:
  /// **'个人简介'**
  String get adminBio;

  /// No description provided for @adminTags.
  ///
  /// In zh, this message translates to:
  /// **'标签(逗号分隔)'**
  String get adminTags;

  /// No description provided for @adminLicenseNo.
  ///
  /// In zh, this message translates to:
  /// **'执照/注册编号'**
  String get adminLicenseNo;

  /// No description provided for @adminCertifications.
  ///
  /// In zh, this message translates to:
  /// **'资质/证书'**
  String get adminCertifications;

  /// No description provided for @adminMarkets.
  ///
  /// In zh, this message translates to:
  /// **'主要市场'**
  String get adminMarkets;

  /// No description provided for @adminStyle.
  ///
  /// In zh, this message translates to:
  /// **'交易风格'**
  String get adminStyle;

  /// No description provided for @adminBroker.
  ///
  /// In zh, this message translates to:
  /// **'合作券商/交易平台'**
  String get adminBroker;

  /// No description provided for @adminCountry.
  ///
  /// In zh, this message translates to:
  /// **'国家/地区'**
  String get adminCountry;

  /// No description provided for @adminCity.
  ///
  /// In zh, this message translates to:
  /// **'城市'**
  String get adminCity;

  /// No description provided for @adminYearsExperience.
  ///
  /// In zh, this message translates to:
  /// **'从业年限'**
  String get adminYearsExperience;

  /// No description provided for @adminIdPhoto.
  ///
  /// In zh, this message translates to:
  /// **'证件照'**
  String get adminIdPhoto;

  /// No description provided for @adminLicensePhoto.
  ///
  /// In zh, this message translates to:
  /// **'资质证明'**
  String get adminLicensePhoto;

  /// No description provided for @adminCertificationPhoto.
  ///
  /// In zh, this message translates to:
  /// **'资质照片'**
  String get adminCertificationPhoto;

  /// No description provided for @adminPerformanceSection.
  ///
  /// In zh, this message translates to:
  /// **'战绩与盈亏'**
  String get adminPerformanceSection;

  /// No description provided for @adminWins.
  ///
  /// In zh, this message translates to:
  /// **'胜场'**
  String get adminWins;

  /// No description provided for @adminLosses.
  ///
  /// In zh, this message translates to:
  /// **'败场'**
  String get adminLosses;

  /// No description provided for @adminRating.
  ///
  /// In zh, this message translates to:
  /// **'评分'**
  String get adminRating;

  /// No description provided for @adminTodayStrategy.
  ///
  /// In zh, this message translates to:
  /// **'今日策略'**
  String get adminTodayStrategy;

  /// No description provided for @adminPnlCurrent.
  ///
  /// In zh, this message translates to:
  /// **'本周总盈亏'**
  String get adminPnlCurrent;

  /// No description provided for @adminPnlMonth.
  ///
  /// In zh, this message translates to:
  /// **'年度盈亏'**
  String get adminPnlMonth;

  /// No description provided for @adminPnlYear.
  ///
  /// In zh, this message translates to:
  /// **'总盈亏'**
  String get adminPnlYear;

  /// No description provided for @adminPnlTotal.
  ///
  /// In zh, this message translates to:
  /// **'累计盈亏'**
  String get adminPnlTotal;

  /// No description provided for @adminContentManagement.
  ///
  /// In zh, this message translates to:
  /// **'内容管理'**
  String get adminContentManagement;

  /// No description provided for @adminReviewActions.
  ///
  /// In zh, this message translates to:
  /// **'审核操作（刚刚申请）'**
  String get adminReviewActions;

  /// No description provided for @adminReviewActionsShort.
  ///
  /// In zh, this message translates to:
  /// **'审核操作'**
  String get adminReviewActionsShort;

  /// No description provided for @adminDispose.
  ///
  /// In zh, this message translates to:
  /// **'处置'**
  String get adminDispose;

  /// No description provided for @adminConfirmReject.
  ///
  /// In zh, this message translates to:
  /// **'确定驳回该申请？'**
  String get adminConfirmReject;

  /// No description provided for @adminConfirmBlock.
  ///
  /// In zh, this message translates to:
  /// **'确定封禁该交易员？封禁后其主页将不在公域展示。'**
  String get adminConfirmBlock;

  /// No description provided for @adminFrozenUntilLabel.
  ///
  /// In zh, this message translates to:
  /// **'冻结至：{date}'**
  String adminFrozenUntilLabel(String date);

  /// No description provided for @adminConfirmUnfreeze.
  ///
  /// In zh, this message translates to:
  /// **'确定解除冻结？'**
  String get adminConfirmUnfreeze;

  /// No description provided for @adminConfirmUnblock.
  ///
  /// In zh, this message translates to:
  /// **'确定解除封禁？'**
  String get adminConfirmUnblock;

  /// No description provided for @adminRevertToPendingConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定改为待审核？'**
  String get adminRevertToPendingConfirm;

  /// No description provided for @adminSelectFreezeDuration.
  ///
  /// In zh, this message translates to:
  /// **'请选择冻结时长：'**
  String get adminSelectFreezeDuration;

  /// No description provided for @adminFreezeDuration.
  ///
  /// In zh, this message translates to:
  /// **'冻结时长'**
  String get adminFreezeDuration;

  /// No description provided for @adminLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get adminLoadFailed;

  /// No description provided for @adminTeacherDefault.
  ///
  /// In zh, this message translates to:
  /// **'交易员'**
  String get adminTeacherDefault;

  /// No description provided for @adminCurrentStatus.
  ///
  /// In zh, this message translates to:
  /// **'当前状态：'**
  String get adminCurrentStatus;

  /// No description provided for @adminFormLabelTitle.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get adminFormLabelTitle;

  /// No description provided for @adminFormLabelSummary.
  ///
  /// In zh, this message translates to:
  /// **'摘要'**
  String get adminFormLabelSummary;

  /// No description provided for @adminFormLabelContent.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get adminFormLabelContent;

  /// No description provided for @adminFormLabelAsset.
  ///
  /// In zh, this message translates to:
  /// **'品种'**
  String get adminFormLabelAsset;

  /// No description provided for @adminFormLabelBuyTime.
  ///
  /// In zh, this message translates to:
  /// **'买入时间(YYYY-MM-DD)'**
  String get adminFormLabelBuyTime;

  /// No description provided for @adminFormLabelBuyShares.
  ///
  /// In zh, this message translates to:
  /// **'买入数量'**
  String get adminFormLabelBuyShares;

  /// No description provided for @adminFormLabelBuyPrice.
  ///
  /// In zh, this message translates to:
  /// **'买入价'**
  String get adminFormLabelBuyPrice;

  /// No description provided for @adminFormLabelSellTime.
  ///
  /// In zh, this message translates to:
  /// **'卖出时间(YYYY-MM-DD)'**
  String get adminFormLabelSellTime;

  /// No description provided for @adminFormLabelSellShares.
  ///
  /// In zh, this message translates to:
  /// **'卖出数量'**
  String get adminFormLabelSellShares;

  /// No description provided for @adminFormLabelSellPrice.
  ///
  /// In zh, this message translates to:
  /// **'卖出价'**
  String get adminFormLabelSellPrice;

  /// No description provided for @adminFormLabelPnlRatio.
  ///
  /// In zh, this message translates to:
  /// **'收益率%'**
  String get adminFormLabelPnlRatio;

  /// No description provided for @adminFormLabelPnlAmount.
  ///
  /// In zh, this message translates to:
  /// **'盈亏金额'**
  String get adminFormLabelPnlAmount;

  /// No description provided for @adminFormLabelCostPrice.
  ///
  /// In zh, this message translates to:
  /// **'成本价'**
  String get adminFormLabelCostPrice;

  /// No description provided for @adminFormLabelCurrentPrice.
  ///
  /// In zh, this message translates to:
  /// **'现价'**
  String get adminFormLabelCurrentPrice;

  /// No description provided for @adminFormLabelFloatingPnl.
  ///
  /// In zh, this message translates to:
  /// **'浮动盈亏'**
  String get adminFormLabelFloatingPnl;

  /// No description provided for @adminFormLabelUserName.
  ///
  /// In zh, this message translates to:
  /// **'用户昵称'**
  String get adminFormLabelUserName;

  /// No description provided for @adminFormLabelLocation.
  ///
  /// In zh, this message translates to:
  /// **'地点'**
  String get adminFormLabelLocation;

  /// No description provided for @adminFormLabelTime.
  ///
  /// In zh, this message translates to:
  /// **'时间(YYYY-MM-DD)'**
  String get adminFormLabelTime;

  /// No description provided for @adminFormLabelTimeSchedule.
  ///
  /// In zh, this message translates to:
  /// **'时间(YYYY-MM-DD HH:MM)'**
  String get adminFormLabelTimeSchedule;

  /// No description provided for @adminFormLabelSellTimeHistory.
  ///
  /// In zh, this message translates to:
  /// **'卖出时间(YYYY-MM-DD)'**
  String get adminFormLabelSellTimeHistory;

  /// No description provided for @adminFormLabelSellPriceHistory.
  ///
  /// In zh, this message translates to:
  /// **'卖出价格'**
  String get adminFormLabelSellPriceHistory;

  /// No description provided for @adminUnknownStatus.
  ///
  /// In zh, this message translates to:
  /// **'未知状态: {raw}，请检查数据库 status 字段是否为 pending/approved/rejected/frozen/blocked'**
  String adminUnknownStatus(String raw);

  /// No description provided for @roleNormal.
  ///
  /// In zh, this message translates to:
  /// **'普通用户'**
  String get roleNormal;

  /// No description provided for @roleTrader.
  ///
  /// In zh, this message translates to:
  /// **'交易员'**
  String get roleTrader;

  /// No description provided for @roleAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get roleAdmin;

  /// No description provided for @roleVip.
  ///
  /// In zh, this message translates to:
  /// **'会员'**
  String get roleVip;

  /// No description provided for @roleCustomerService.
  ///
  /// In zh, this message translates to:
  /// **'客服'**
  String get roleCustomerService;

  /// No description provided for @pcHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get pcHome;

  /// No description provided for @pcNotify.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get pcNotify;

  /// No description provided for @pcGreetingHello.
  ///
  /// In zh, this message translates to:
  /// **'你好'**
  String get pcGreetingHello;

  /// No description provided for @pcGreetingMorning.
  ///
  /// In zh, this message translates to:
  /// **'上午好'**
  String get pcGreetingMorning;

  /// No description provided for @pcGreetingAfternoon.
  ///
  /// In zh, this message translates to:
  /// **'下午好'**
  String get pcGreetingAfternoon;

  /// No description provided for @pcGreetingEvening.
  ///
  /// In zh, this message translates to:
  /// **'晚上好'**
  String get pcGreetingEvening;

  /// No description provided for @pcWelcomeBack.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来，这是你的工作台概览'**
  String get pcWelcomeBack;

  /// No description provided for @pcFollow.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get pcFollow;

  /// No description provided for @pcFollowSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'已关注标的'**
  String get pcFollowSubtitle;

  /// No description provided for @pcTodayChat.
  ///
  /// In zh, this message translates to:
  /// **'今日会话'**
  String get pcTodayChat;

  /// No description provided for @pcMessageCount.
  ///
  /// In zh, this message translates to:
  /// **'消息数'**
  String get pcMessageCount;

  /// No description provided for @pcWatchlist.
  ///
  /// In zh, this message translates to:
  /// **'自选'**
  String get pcWatchlist;

  /// No description provided for @pcWatchlistSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'自选标的'**
  String get pcWatchlistSubtitle;

  /// No description provided for @pcRanking.
  ///
  /// In zh, this message translates to:
  /// **'排名'**
  String get pcRanking;

  /// No description provided for @pcRankingSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'当前排名'**
  String get pcRankingSubtitle;

  /// No description provided for @pcMarket.
  ///
  /// In zh, this message translates to:
  /// **'行情'**
  String get pcMarket;

  /// No description provided for @pcMarketSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看市场与指数'**
  String get pcMarketSubtitle;

  /// No description provided for @pcManageWatchlist.
  ///
  /// In zh, this message translates to:
  /// **'管理自选标的'**
  String get pcManageWatchlist;

  /// No description provided for @pcMessages.
  ///
  /// In zh, this message translates to:
  /// **'消息'**
  String get pcMessages;

  /// No description provided for @pcMessagesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'会话与好友'**
  String get pcMessagesSubtitle;

  /// No description provided for @pcLeaderboard.
  ///
  /// In zh, this message translates to:
  /// **'排行榜'**
  String get pcLeaderboard;

  /// No description provided for @pcLeaderboardSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看排名'**
  String get pcLeaderboardSubtitle;

  /// No description provided for @pcQuickEntry.
  ///
  /// In zh, this message translates to:
  /// **'快捷入口'**
  String get pcQuickEntry;

  /// No description provided for @pcEnter.
  ///
  /// In zh, this message translates to:
  /// **'进入'**
  String get pcEnter;

  /// No description provided for @networkNoConnection.
  ///
  /// In zh, this message translates to:
  /// **'无网络连接，请检查网络后重试'**
  String get networkNoConnection;

  /// No description provided for @networkTryAgain.
  ///
  /// In zh, this message translates to:
  /// **'网络异常，请稍后重试'**
  String get networkTryAgain;

  /// No description provided for @networkAuthExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录已过期或无效，请重新登录'**
  String get networkAuthExpired;

  /// No description provided for @networkPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'权限不足或操作被拒绝，请检查登录状态'**
  String get networkPermissionDenied;

  /// No description provided for @adminReportReporter.
  ///
  /// In zh, this message translates to:
  /// **'举报人'**
  String get adminReportReporter;

  /// No description provided for @adminReportReported.
  ///
  /// In zh, this message translates to:
  /// **'被举报人'**
  String get adminReportReported;

  /// No description provided for @adminReportNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无举报记录'**
  String get adminReportNoData;

  /// No description provided for @adminReportNotes.
  ///
  /// In zh, this message translates to:
  /// **'管理员备注'**
  String get adminReportNotes;

  /// No description provided for @profileCsWorkbench.
  ///
  /// In zh, this message translates to:
  /// **'客服工作台'**
  String get profileCsWorkbench;

  /// No description provided for @profileCsWorkbenchSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看并回复用户消息'**
  String get profileCsWorkbenchSubtitle;

  /// No description provided for @adminCsConfig.
  ///
  /// In zh, this message translates to:
  /// **'客服配置'**
  String get adminCsConfig;

  /// No description provided for @adminCsSystemAccount.
  ///
  /// In zh, this message translates to:
  /// **'系统客服账号'**
  String get adminCsSystemAccount;

  /// No description provided for @adminCsSystemAccountHint.
  ///
  /// In zh, this message translates to:
  /// **'用户添加的好友、消息接收方，需从用户列表选择'**
  String get adminCsSystemAccountHint;

  /// No description provided for @adminCsAvatarUrl.
  ///
  /// In zh, this message translates to:
  /// **'客服固定头像'**
  String get adminCsAvatarUrl;

  /// No description provided for @adminCsStaff.
  ///
  /// In zh, this message translates to:
  /// **'客服人员'**
  String get adminCsStaff;

  /// No description provided for @adminCsStaffHint.
  ///
  /// In zh, this message translates to:
  /// **'登录后可见「客服工作台」，可回复用户消息'**
  String get adminCsStaffHint;

  /// No description provided for @adminSelectAsSystemCs.
  ///
  /// In zh, this message translates to:
  /// **'设为系统客服'**
  String get adminSelectAsSystemCs;

  /// No description provided for @adminAddAsCsStaff.
  ///
  /// In zh, this message translates to:
  /// **'设为客服人员'**
  String get adminAddAsCsStaff;

  /// No description provided for @adminRemoveCsStaff.
  ///
  /// In zh, this message translates to:
  /// **'移除客服身份'**
  String get adminRemoveCsStaff;

  /// No description provided for @adminCsNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get adminCsNotConfigured;

  /// No description provided for @adminCsUploadAvatar.
  ///
  /// In zh, this message translates to:
  /// **'上传头像'**
  String get adminCsUploadAvatar;

  /// No description provided for @adminCsWelcomeMessage.
  ///
  /// In zh, this message translates to:
  /// **'自动欢迎语'**
  String get adminCsWelcomeMessage;

  /// No description provided for @adminCsWelcomeMessageHint.
  ///
  /// In zh, this message translates to:
  /// **'用户首次联系客服时自动发送，留空则不发送'**
  String get adminCsWelcomeMessageHint;

  /// No description provided for @adminCsBroadcast.
  ///
  /// In zh, this message translates to:
  /// **'群发消息'**
  String get adminCsBroadcast;

  /// No description provided for @adminCsBroadcastHint.
  ///
  /// In zh, this message translates to:
  /// **'以系统客服身份向所有已添加客服的用户发送'**
  String get adminCsBroadcastHint;

  /// No description provided for @adminCsBroadcastSend.
  ///
  /// In zh, this message translates to:
  /// **'发送群发消息'**
  String get adminCsBroadcastSend;

  /// No description provided for @adminCsBroadcastSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已向 {count} 个用户发送'**
  String adminCsBroadcastSuccess(Object count);

  /// No description provided for @adminCsBroadcastEmpty.
  ///
  /// In zh, this message translates to:
  /// **'消息不能为空'**
  String get adminCsBroadcastEmpty;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

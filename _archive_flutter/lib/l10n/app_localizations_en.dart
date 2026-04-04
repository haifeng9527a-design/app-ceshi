// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Finance Training';

  @override
  String get adminTitle => 'Admin';

  @override
  String get navHome => 'Home';

  @override
  String get navMainPage => 'Home';

  @override
  String get navMarket => 'Market';

  @override
  String get navWatchlist => 'Watchlist';

  @override
  String get navMessages => 'Messages';

  @override
  String get navRankings => 'Rankings';

  @override
  String get navFollow => 'Following';

  @override
  String get navProfile => 'Profile';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonNoData => 'No data';

  @override
  String get commonUser => 'User';

  @override
  String get commonOther => 'Other';

  @override
  String get commonFriend => 'Friend';

  @override
  String get commonMe => 'Me';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonForward => 'Forward';

  @override
  String get commonReply => 'Reply';

  @override
  String get commonImage => 'Image';

  @override
  String get commonVideo => 'Video';

  @override
  String get commonFile => 'File';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonKnowIt => 'Got it';

  @override
  String get commonGoToSettings => 'Settings';

  @override
  String get commonGoToEnable => 'Enable';

  @override
  String get authLoginOrRegister => 'Login / Register';

  @override
  String get authLogin => 'Login';

  @override
  String get authLoginHint => 'Sign in with email or third-party account';

  @override
  String get authRegisterHint => 'Create account and verify email';

  @override
  String get authNameHint => 'Enter your name';

  @override
  String get authEmailHint => 'Enter your email';

  @override
  String get authPasswordHint => 'Enter password';

  @override
  String get authConfirmPasswordHint => 'Enter password again';

  @override
  String get authPleaseConfigureFirebase => 'Please configure Firebase first';

  @override
  String get authPleaseFillEmailAndPassword =>
      'Please fill in email and password';

  @override
  String get authAccountOrPasswordWrong => 'Invalid account or password';

  @override
  String get authEnterAccount => 'Enter account';

  @override
  String get authEnterPassword => 'Enter password';

  @override
  String get authAccount => 'Account';

  @override
  String get authPassword => 'Password';

  @override
  String get authPleaseLoginToManage => 'Please login to manage';

  @override
  String get authEnterAdminAccount => 'Enter admin account';

  @override
  String get authEnterPasswordHint => 'Enter password';

  @override
  String get profileMy => 'Profile';

  @override
  String get profileEditSignature => 'Edit signature';

  @override
  String get profileSignatureHint => 'Write something…';

  @override
  String get profileAvatarUploadFailedNoSupabase =>
      'Avatar upload failed: Supabase not configured';

  @override
  String get profileAvatarUpdated => 'Avatar updated';

  @override
  String get profileAvatarUploadFailed => 'Avatar upload failed';

  @override
  String get profileSignatureUpdated => 'Signature updated';

  @override
  String get profileSignatureUpdateFailed => 'Signature update failed';

  @override
  String get profileAdmin => 'Admin';

  @override
  String get profileVip => 'VIP';

  @override
  String get profileTeacher => 'Trader';

  @override
  String get profileNormalUser => 'User';

  @override
  String get profileStudentAccount => 'Student Account';

  @override
  String get profileNotLoggedIn => 'Not logged in';

  @override
  String get profileBecomeTeacher => 'Become Trader';

  @override
  String get profileLoginToSubmit => 'Login to submit';

  @override
  String get profileFirebaseNotConfigured =>
      'Firebase not configured. Login and messaging unavailable.';

  @override
  String get profileNotificationNotEnabled =>
      'Notifications disabled. You may miss new messages.';

  @override
  String get profileAccountId => 'Account ID';

  @override
  String profileAccountIdValue(String id) {
    return 'Account ID $id';
  }

  @override
  String get profileAccountIdDash => 'Account ID --';

  @override
  String get profileLazySignature => 'Nothing here yet';

  @override
  String get profileTeacherCenter => 'Trader Center';

  @override
  String get profileManageStrategyAndRecords => 'Manage strategies and records';

  @override
  String get profileSubmitProfileAndPublish => 'Submit profile and publish';

  @override
  String get profileMyFollowing => 'My Following';

  @override
  String get profileAdminPc => 'Admin (PC)';

  @override
  String get profilePushNotificationGuide => 'Not receiving push?';

  @override
  String get profileNotificationGuideSubtitle =>
      'View notification and startup settings';

  @override
  String get profileEnsureReceiveMessages => 'Ensure you receive messages';

  @override
  String get profileNotificationPermissionGuide =>
      '1. Allow notification and background permissions.\n\n2. Huawei/Honor: Enable auto-start and background activity.\n\n3. Huawei/Honor: Enable pop-up or overlay for incoming calls.\n\n4. Enable badge for unread count on app icon.';

  @override
  String get profileIncomingCallFullScreen => 'Full-screen incoming call';

  @override
  String get profileIncomingCallFullScreenSubtitle =>
      'Show call UI when backgrounded or locked (Android 14+ full-screen intent)';

  @override
  String get profileFullScreenIntentEnabled =>
      'Enabled. Calls will show full-screen.';

  @override
  String get profileCurrentNotLoggedIn => 'Not logged in';

  @override
  String get profileLogout => 'Logout';

  @override
  String get profileLoggedIn => 'Logged in';

  @override
  String get profileReRequestPermission => 'Request again';

  @override
  String get profileHelp => 'Help';

  @override
  String get profileHelpTitle => 'Help & Support';

  @override
  String get profileTraderFriends => 'Trader Friends';

  @override
  String get profileTraderFriendsSubtitle => 'Traders I follow';

  @override
  String get profileAccountDeletion => 'Delete Account';

  @override
  String get profileAccountDeletionConfirm =>
      'Your account will be permanently deleted and cannot be recovered. Continue?';

  @override
  String get profileDeletionSuccess => 'Account deleted';

  @override
  String get profilePrivacyPolicy => 'Privacy Policy';

  @override
  String get profilePrivacyPolicySubtitle => 'View privacy policy and terms';

  @override
  String get profileReport => 'Report';

  @override
  String get profileReportSubtitle => 'Report violations or users';

  @override
  String get profileUserTradingCenterMenuTitle => 'User Trading Center';

  @override
  String get profileUserTradingCenterMenuSubtitle =>
      'Open user trading center via WebView';

  @override
  String get profileUserTradingCenterHiddenMenuTitle => 'User Trading Center';

  @override
  String get profileUserTradingCenterHiddenMenuSubtitle =>
      'Current version is not supported. Please use the link below.';

  @override
  String get profileLinkPrefix => 'Link: ';

  @override
  String get profilePrivacyPolicyContent =>
      'We respect and protect your privacy. Information we collect is used only to provide and improve our services. See the full privacy policy on the app store or our website.';

  @override
  String get profileReportContent =>
      'To report violations or users, please use in-app feedback or contact support. We will process your report as soon as possible.';

  @override
  String get reportPageTitle => 'Report User';

  @override
  String get reportTargetUser => 'Reported User';

  @override
  String get reportTargetUserHint => 'Search by account ID or email';

  @override
  String get reportReason => 'Report Reason';

  @override
  String get reportReasonHarassment => 'Harassment';

  @override
  String get reportReasonSpam => 'Spam/Ads';

  @override
  String get reportReasonFraud => 'Fraud';

  @override
  String get reportReasonInappropriate => 'Inappropriate Content';

  @override
  String get reportReasonOther => 'Other';

  @override
  String get reportContent => 'Details';

  @override
  String get reportContentHint => 'Describe the situation (optional)';

  @override
  String get reportScreenshots => 'Screenshots';

  @override
  String get reportScreenshotsMax => 'Up to 5';

  @override
  String get reportSubmit => 'Submit Report';

  @override
  String get reportSuccess => 'Report submitted. We will process it soon.';

  @override
  String get reportFailed => 'Submit failed';

  @override
  String get reportPleaseSelectUser =>
      'Please search and select the reported user';

  @override
  String get reportPleaseSelectReason => 'Please select a report reason';

  @override
  String get featuredTrader => 'Trader';

  @override
  String get featuredMentor => 'Mentor';

  @override
  String get featuredNoTodayStrategy => 'No strategy today';

  @override
  String get featuredNoTeacherInfo => 'No trader info';

  @override
  String get featuredLoadFailedRetry => 'Load failed, retry';

  @override
  String get featuredServiceNotReady => 'Service not ready';

  @override
  String get featuredNoFollowingOrRanking => 'No following or ranking data';

  @override
  String get featuredNetworkRestricted =>
      'Network restricted. Check network or run locally.';

  @override
  String get featuredNotStartedInvestment =>
      'You haven\'t started your investment journey';

  @override
  String get featuredPnlOverview => 'P&L Overview';

  @override
  String get featuredTodayStrategy => 'Today\'s Strategy';

  @override
  String get featuredViewAllStrategies => 'View all strategies';

  @override
  String get featuredCurrentPositions => 'Current Positions';

  @override
  String get featuredHistoryPositions => 'History';

  @override
  String get featuredWins => 'Wins';

  @override
  String get featuredLosses => 'Losses';

  @override
  String get featuredWinRate => 'Win Rate';

  @override
  String get featuredPositionPnl => 'Position P&L';

  @override
  String get featuredYearPnl => 'Year P&L';

  @override
  String get featuredTotalPnl => 'Total P&L';

  @override
  String get featuredCoreStrategy => 'Core Strategy';

  @override
  String get featuredCollapse => 'Collapse';

  @override
  String featuredExpandReplies(int count) {
    return 'Expand $count replies';
  }

  @override
  String get featuredLoginBeforeForward => 'Please login to forward';

  @override
  String get featuredViewFullStrategy => 'Tap to view full strategy';

  @override
  String get featuredHideComments => 'Hide comments';

  @override
  String get featuredViewComments => 'View comments';

  @override
  String get featuredForwardTooltip => 'Forward';

  @override
  String get featuredNoComments => 'No comments';

  @override
  String get featuredForwarded => 'Forwarded';

  @override
  String get featuredForwardFailed => 'Forward failed';

  @override
  String featuredForwardFailedWithMessage(String message) {
    return 'Forward failed: $message';
  }

  @override
  String get featuredForwardTo => 'Forward to';

  @override
  String get featuredNoConversationAddFriend =>
      'No conversations. Add friends or join groups.';

  @override
  String get featuredLoginBeforeComment => 'Please login to comment';

  @override
  String get featuredCommentPublished => 'Comment published';

  @override
  String get featuredCommentPublishFailed => 'Publish failed';

  @override
  String featuredCommentPublishFailedWithMessage(String message) {
    return 'Publish failed: $message';
  }

  @override
  String featuredCommentsCount(int count) {
    return '$count comments';
  }

  @override
  String get featuredCommentHint => 'Write your comment…';

  @override
  String get featuredPublishing => 'Publishing…';

  @override
  String get featuredPublish => 'Publish';

  @override
  String get featuredBuy => 'Buy';

  @override
  String get featuredCost => 'Cost';

  @override
  String get featuredQuantity => 'Qty';

  @override
  String get featuredSell => 'Sell';

  @override
  String get featuredSellPrice => 'Sell Price';

  @override
  String get featuredCurrentPrice => 'Price';

  @override
  String get featuredFloatingPnl => 'Floating P&L';

  @override
  String get featuredCurrentPositionPnl => 'Position P&L';

  @override
  String get featuredCurrentPosition => 'Current Position';

  @override
  String get featuredBuyTime => 'Buy Time';

  @override
  String get featuredBuyShares => 'Shares';

  @override
  String get featuredBuyPrice => 'Buy Price';

  @override
  String get featuredPositionCost => 'Position Cost';

  @override
  String get featuredPositionPnlRatio => 'P&L Ratio';

  @override
  String get featuredProfitRatio => 'Profit Ratio';

  @override
  String get featuredPnlAmount => 'P&L Amount';

  @override
  String get featuredShares => 'Shares';

  @override
  String get featuredPrice => 'Price';

  @override
  String get featuredMonthTotalPnl => 'Month Total P&L';

  @override
  String get featuredPositionPnlAmount => 'Position P&L Amount';

  @override
  String get featuredTodayStrategyTab => 'Today';

  @override
  String get featuredPositionTab => 'Positions';

  @override
  String get featuredHistoryTab => 'History';

  @override
  String get tradingApple => 'Apple';

  @override
  String get tradingMicrosoft => 'Microsoft';

  @override
  String get tradingGoogle => 'Google';

  @override
  String get tradingAmazon => 'Amazon';

  @override
  String get tradingTesla => 'Tesla';

  @override
  String get tradingStock => 'Stock';

  @override
  String get tradingForex => 'Forex';

  @override
  String get tradingCrypto => 'Crypto';

  @override
  String get tradingQuoteRefreshFailed => 'Quote refresh failed';

  @override
  String get tradingSearchAndSelectFirst => 'Search and select symbol first';

  @override
  String get tradingOrderSubmitted => 'Order submitted';

  @override
  String get tradingVolume => 'Volume';

  @override
  String get tradingSelectGainersOrSearch => 'Select from gainers or search';

  @override
  String get tradingViewRealtimeQuote => 'View real-time quote and chart';

  @override
  String get tradingGainersList => 'Gainers';

  @override
  String get tradingUpdateTime => 'Updated';

  @override
  String tradingUpdateTimeValue(String time) {
    return 'Updated $time';
  }

  @override
  String get tradingConfigurePolygonApiKey => 'Configure POLYGON_API_KEY';

  @override
  String get tradingStockCodeOrName => 'Stock code or name';

  @override
  String get tradingForexCodeExample => 'Forex e.g. EUR/USD';

  @override
  String get tradingCryptoExample => 'Crypto e.g. BTC, ETH';

  @override
  String get tradingIntraday => 'Intraday';

  @override
  String get tradingNoChartData => 'No chart data';

  @override
  String get tradingBuy => 'Buy';

  @override
  String get tradingSell => 'Sell';

  @override
  String get tradingLimitOrder => 'Limit';

  @override
  String get tradingMarketOrder => 'Market';

  @override
  String get tradingPriceLabel => 'Price';

  @override
  String get tradingQuantityLabel => 'Quantity';

  @override
  String get tradingEnterValidQuantity => 'Enter valid quantity (> 0)';

  @override
  String get tradingEnterValidPriceForLimit =>
      'Enter valid price for limit order (> 0)';

  @override
  String get tradingConfirmBuy => 'Confirm Buy';

  @override
  String get tradingConfirmSell => 'Confirm Sell';

  @override
  String get tradingNoData => 'No data';

  @override
  String tradingBuySellSubmitted(String action, String symbol) {
    return '$action $symbol order submitted';
  }

  @override
  String get callCallerCancelled => 'Caller cancelled';

  @override
  String get callVideoCall => 'Video Call';

  @override
  String get callVoiceCall => 'Voice Call';

  @override
  String get callInviteVideoCall => 'invites you to video call';

  @override
  String get callInviteVoiceCall => 'invites you to voice call';

  @override
  String get callDecline => 'Decline';

  @override
  String get callAnswer => 'Answer';

  @override
  String callInviteCallBody(String name, String type) {
    return '$name invites you to $type';
  }

  @override
  String get messagesNoMatchingMembers => 'No matching members';

  @override
  String get messagesNotFriendCannotSend => 'Not friends, cannot send';

  @override
  String get messagesRecordingTooShort => 'Recording too short';

  @override
  String get messagesGrantMicPermission => 'Grant microphone permission';

  @override
  String get messagesNoSupabaseCannotSendMedia =>
      'Supabase not configured, cannot send media';

  @override
  String get messagesFileEmptyCannotSend => 'File is empty, cannot send';

  @override
  String get messagesSendFailed => 'Send failed';

  @override
  String get messagesCannotReadFile => 'Cannot read file';

  @override
  String get messagesSelectFileFailed => 'Select file failed';

  @override
  String get messagesForwardInDevelopment => 'Forward in development';

  @override
  String get messagesRecall => 'Recall';

  @override
  String get messagesRecallMessage => 'Recall message';

  @override
  String get messagesConfirmRecallMessage => 'Recall this message?';

  @override
  String get messagesRecalled => 'Recalled';

  @override
  String get messagesRecallFailed => 'Recall failed';

  @override
  String get messagesAlbum => 'Album';

  @override
  String get messagesCamera => 'Camera';

  @override
  String get messagesFileLabel => 'File';

  @override
  String get messagesCallLabel => 'Call';

  @override
  String get messagesTakePhoto => 'Take photo';

  @override
  String get messagesTakeVideo => 'Record video';

  @override
  String get messagesVoiceCall => 'Voice call';

  @override
  String get messagesVideoCall => 'Video call';

  @override
  String get messagesNoAgoraCannotCall => 'Agora not configured, cannot call';

  @override
  String get messagesNeedMicForCall =>
      'Microphone permission required for calls';

  @override
  String get messagesNeedCameraForVideo =>
      'Camera permission required for video calls';

  @override
  String get messagesGroupSettings => 'Group settings';

  @override
  String get messagesSetRemark => 'Set remark';

  @override
  String get messagesPinConversation => 'Pin conversation';

  @override
  String get messagesClearChatHistory => 'Clear chat history';

  @override
  String get messagesImage => 'Image';

  @override
  String get messagesVideo => 'Video';

  @override
  String get messagesReply => 'Reply';

  @override
  String get messagesCopy => 'Copy';

  @override
  String get messagesForward => 'Forward';

  @override
  String get messagesCopied => 'Copied';

  @override
  String get messagesNoFriendCannotSend => 'Not friends, cannot send';

  @override
  String get messagesSendFailedPrefix => 'Send failed';

  @override
  String get messagesFileSendFailedPrefix => 'File send failed';

  @override
  String get messagesRecallFailedPrefix => 'Recall failed';

  @override
  String get messagesViewProfile => 'View profile';

  @override
  String get messagesRemarkHint => 'Enter remark name';

  @override
  String get messagesConfirmClearChat =>
      'Clear all chat history? This cannot be undone.';

  @override
  String get messagesClear => 'Clear';

  @override
  String get messagesGroupAnnouncement => 'Group announcement';

  @override
  String get messagesInputHint => 'Enter message';

  @override
  String get messagesSend => 'Send';

  @override
  String get messagesOpening => 'Opening…';

  @override
  String get messagesCannotOpenFile => 'Cannot open file';

  @override
  String get messagesFileExpiredOrMissing =>
      'File expired or missing. Ask sender to resend.';

  @override
  String get messagesUseCompatiblePlayer => 'Use compatible player';

  @override
  String get marketNoData => 'No data';

  @override
  String tradingQuoteRefreshFailedWithError(String error) {
    return 'Quote refresh failed: $error';
  }

  @override
  String get tradingKline => 'K-line';

  @override
  String get teachersConfirmRiskPrompt =>
      'Please confirm you have read the risk disclosure';

  @override
  String get teachersProfileSubmitted => 'Profile submitted';

  @override
  String get teachersSaveFailed => 'Save failed';

  @override
  String get teachersPhotoUploaded => 'Photo uploaded';

  @override
  String get teachersUploadFailed => 'Upload failed';

  @override
  String get teachersPublishStrategy => 'Publish strategy';

  @override
  String get teachersTitleLabel => 'Title';

  @override
  String get teachersStrategyContent => 'Strategy content';

  @override
  String get teachersImages => 'Images';

  @override
  String get teachersAddImage => 'Add image';

  @override
  String get teachersStrategyImage => 'Images';

  @override
  String get teachersFillStrategyTitle => 'Please fill strategy title';

  @override
  String get teachersPublish => 'Publish';

  @override
  String get teachersStrategyPublished =>
      'Strategy published, will show in Today\'s Strategy';

  @override
  String get teachersPublishFailed => 'Publish failed';

  @override
  String get teachersDeleteStrategy => 'Delete strategy';

  @override
  String get teachersDeleteStrategyConfirm =>
      'Delete this strategy? This action cannot be undone.';

  @override
  String get teachersStrategyDeleted => 'Strategy deleted';

  @override
  String get teachersDeleteStrategyFailed => 'Failed to delete strategy';

  @override
  String get teachersUploadTradeRecord => 'Upload trade record';

  @override
  String get teachersVarietyLabel => 'Symbol';

  @override
  String get teachersDirectionLabel => 'Direction (buy/sell)';

  @override
  String get teachersPnlLabel => 'P&L';

  @override
  String get teachersNoScreenshotSelected => 'No screenshot selected';

  @override
  String get teachersSelectScreenshot => 'Select screenshot';

  @override
  String get teachersTradeRecordSaved => 'Trade record saved';

  @override
  String get teachersTeacherCenter => 'Trader Center';

  @override
  String get teachersPleaseLoginFirst => 'Please login first';

  @override
  String get teachersStrategyTab => 'Strategy';

  @override
  String get teachersQuoteAndTradeTab => 'Quote & Trade';

  @override
  String get teachersOrderTab => 'Orders';

  @override
  String get teachersHistoryOrderTab => 'History';

  @override
  String get teachersFillsAndPositionsTab => 'Fills & Positions';

  @override
  String get teachersBasicInfo => 'Basic Info';

  @override
  String get teachersNoNicknameSet => 'No nickname set';

  @override
  String get teachersAvatarNicknameHint => 'Avatar/name synced with account';

  @override
  String get teachersRealNameRequired => 'Real name (required)';

  @override
  String get teachersProfessionalTitle => 'Title';

  @override
  String get teachersOrgCompany => 'Organization';

  @override
  String get teachersCountryRegion => 'Country/Region';

  @override
  String get teachersYearsExperience => 'Years of experience';

  @override
  String get teachersYearsAbove20 => '20+ years';

  @override
  String teachersYearsFormat(int n) {
    return '$n years';
  }

  @override
  String get teachersTradingBackground => 'Trading background';

  @override
  String get teachersMainMarketLabel =>
      'Main markets (stock/option/futures/forex/crypto)';

  @override
  String get teachersMainVariety => 'Main symbols/industries';

  @override
  String get teachersRiskPreference => 'Risk preference';

  @override
  String get teachersExpertiseVariety => 'Expertise (comma-separated)';

  @override
  String get teachersQualificationCompliance => 'Qualifications (optional)';

  @override
  String get teachersQualificationCert => 'Certifications (e.g. CFA, Series 7)';

  @override
  String get teachersBrokerLabel => 'Broker/Platform';

  @override
  String get teachersPerformanceIntro => 'Performance & Intro';

  @override
  String get teachersPerformanceLabel =>
      'Performance (e.g. 1Y return, max drawdown)';

  @override
  String get teachersIdVerification => 'ID verification (recommended)';

  @override
  String get teachersCountryOptions =>
      'United States, China, Hong Kong, Singapore, UK, Canada, Australia, Japan, Korea, Germany, France, UAE, Other';

  @override
  String get teachersCityLabel => 'City';

  @override
  String get teachersTradingStyle => 'Trading style';

  @override
  String get strategiesFullStrategy => 'Full strategy';

  @override
  String get strategiesPageTitle => 'Trading Strategies';

  @override
  String get strategiesTodayStrategies => 'Today\'s Strategies';

  @override
  String get strategiesHistoryStrategies => 'Historical Strategies';

  @override
  String get strategiesNoHistory => 'No historical strategies';

  @override
  String get featuredNoStrategyContent => 'No strategy content';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageChinese => '简体中文';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get messagesLoginToUseChat => 'Login to use chat';

  @override
  String get messagesLoginMethods => 'Email, Google, Apple login supported';

  @override
  String get messagesAddFriend => 'Add friend';

  @override
  String get addFriendScanQr => 'Scan to add';

  @override
  String get addFriendMyQrCode => 'My QR code';

  @override
  String get addFriendTabEmail => 'Email';

  @override
  String get addFriendTabAccountId => 'Account ID';

  @override
  String get addFriendTabQrCode => 'QR Code';

  @override
  String get addFriendHintEmail => 'Enter their registered email';

  @override
  String get addFriendHintId => 'Enter their account ID';

  @override
  String get addFriendLabelTargetEmail => 'Recipient email';

  @override
  String get addFriendLabelAccountIdRule => 'Account ID (6-9 digits)';

  @override
  String get addFriendEnterEmail => 'Please enter email';

  @override
  String get addFriendEnterAccountId => 'Please enter account ID';

  @override
  String get addFriendUserNotFound => 'User not found';

  @override
  String get addFriendRequestSent => 'Friend request sent';

  @override
  String get addFriendAlreadyFriends => 'You are already friends';

  @override
  String get addFriendAlreadyPending =>
      'Request already sent. Please wait for response.';

  @override
  String get commonGenerating => 'Generating...';

  @override
  String get addFriendAccountIdGenerating => 'Account ID: generating...';

  @override
  String addFriendAccountIdValue(String id) {
    return 'Account ID: $id';
  }

  @override
  String get commonAdd => 'Add';

  @override
  String get featuredFollowTrader => 'Follow trader';

  @override
  String get promoEnterSelectTrader => 'Enter to select trader';

  @override
  String get messagesCreateGroup => 'Create group';

  @override
  String get messagesSystemNotifications => 'System notifications';

  @override
  String get messagesSearchConversations => 'Search conversations';

  @override
  String get messagesSearchFriends => 'Search friends';

  @override
  String get messagesRecentChats => 'Recent';

  @override
  String get messagesFriendList => 'Friends';

  @override
  String get messagesFirebaseNotConfigured => 'Firebase not configured';

  @override
  String get messagesAddConfigFirst => 'Add config file to use messaging';

  @override
  String get messagesSupabaseNotConfigured => 'Supabase not configured';

  @override
  String get messagesConfigureSupabase =>
      'Configure SUPABASE_URL / SUPABASE_ANON_KEY';

  @override
  String get messagesApiNotConfigured => 'Backend API not configured';

  @override
  String get messagesConfigureApi =>
      'Configure TONGXIN_API_URL and ensure backend is running';

  @override
  String get marketTitle => 'Market';

  @override
  String get marketTabHome => 'Home';

  @override
  String get marketTabUsStock => 'US Stocks';

  @override
  String get marketTabForex => 'Forex';

  @override
  String get marketTabCrypto => 'Crypto';

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
  String get marketGainersList => 'Gainers';

  @override
  String get marketLosersList => 'Losers';

  @override
  String get marketNoForexData => 'No forex data';

  @override
  String get marketLoadingUsStockList => 'Loading US stock list…';

  @override
  String get marketLoadingQuote => 'Loading quote…';

  @override
  String get marketNoUsStockList => 'No US stock list';

  @override
  String get marketStockOrCryptoSearch => 'Stock or crypto name, symbol';

  @override
  String get rankingsPromo1Title => 'Follow the right mentor, see the returns';

  @override
  String get rankingsPromo1Subtitle =>
      'Transparent strategy · Real trading · Monthly profits at a glance';

  @override
  String get rankingsPromo2Title => 'Real trading, verifiable';

  @override
  String get rankingsPromo2Subtitle =>
      'Verified mentors · Win rate and P&L fully traceable';

  @override
  String get rankingsPromo3Title => 'Monthly rankings, who leads';

  @override
  String get rankingsPromo3Subtitle =>
      'Monthly profit ranking · One-tap follow · Never lose track';

  @override
  String get rankingsLearnMore => 'Learn more';

  @override
  String get rankingsMentorVerified => 'Mentor verified';

  @override
  String get rankingsStrategyTraceable => 'Strategies & returns traceable';

  @override
  String get rankingsCommunitySupport => 'Community support';

  @override
  String get rankingsMonthProfitRank => 'Monthly profit ranking';

  @override
  String get rankingsRealtimeTransparent => 'Real-time · Transparent';

  @override
  String get teachersNoStrategy => 'No strategy yet';

  @override
  String get marketIndexDowJones => 'Dow Jones';

  @override
  String get marketIndexNasdaq => 'Nasdaq';

  @override
  String get marketIndexSp500 => 'S&P 500';

  @override
  String get marketAll => 'All';

  @override
  String get marketNoWatchlist => 'No watchlist';

  @override
  String get marketAddWatchlistHint => 'Add in search or detail page';

  @override
  String get marketGoAdd => 'Add';

  @override
  String get marketThreeIndices => 'Major indices';

  @override
  String get marketWatchlist => 'Watchlist';

  @override
  String get marketMockDataHint =>
      'Mock data. Configure TWELVE_DATA_API_KEY for real quotes.';

  @override
  String get marketNoDataConfigHint =>
      'No data. Configure TWELVE_DATA_API_KEY or retry later.';

  @override
  String get marketGlobalIndices => 'Global indices';

  @override
  String get marketNews => 'News';

  @override
  String marketQuoteLoadFailed(String error) {
    return 'Quote fetch failed: $error';
  }

  @override
  String get marketConnectFailed =>
      'Cannot connect to quote service. Ensure backend is running (e.g. http://localhost:3000).';

  @override
  String get marketStockQuoteCacheEmpty =>
      'stock_quote_cache table is empty. Ensure backend is configured and updating it in real-time.';

  @override
  String get marketCsvHeader =>
      'Code,Name,Change %,Price,Change,Open,Prev Close,High,Low,Volume';

  @override
  String get marketMockDataPcHint =>
      'Mock data for display only. Configure POLYGON_API_KEY for real quotes.';

  @override
  String get marketExportCsv => 'Export CSV';

  @override
  String get marketHotNews => 'Hot news';

  @override
  String get marketSubscribeTopic => 'Subscribe';

  @override
  String get marketTradableCoins => 'Tradable coins';

  @override
  String get marketMarketCap => 'Market cap';

  @override
  String get marketTopGainers => 'Top gainers';

  @override
  String get marketTopLosers => 'Top losers';

  @override
  String get authEmail => 'Email';

  @override
  String get authThirdPartyLogin => 'Third-party login';

  @override
  String get authGoogleLogin => 'Google login';

  @override
  String get authAppleLogin => 'Apple login';

  @override
  String get authRegisterAndSendEmail => 'Register & send verification';

  @override
  String get authConfirmPassword => 'Confirm password';

  @override
  String get authRegister => 'Register';

  @override
  String get authName => 'Name';

  @override
  String get authSendVerificationEmail => 'Send verification email';

  @override
  String authSendVerificationEmailCooldown(int seconds) {
    return 'Send verification email (${seconds}s)';
  }

  @override
  String get authFirebaseConfigHint =>
      'Firebase not configured. Add google-services.json / GoogleService-Info.plist first.';

  @override
  String get authFirebaseConfigHintWeb =>
      'Web login is not configured yet. Firebase sign-in is currently unavailable on the web app.';

  @override
  String get authVerificationSent =>
      'Verification email sent. Please verify and log in again.';

  @override
  String get authFillNameEmailPassword =>
      'Please fill name, email and both passwords';

  @override
  String get authPasswordMismatch => 'Passwords do not match';

  @override
  String get authPasswordMinLength => 'Password must be at least 6 characters';

  @override
  String authResendCooldown(int seconds) {
    return 'Please try again in ${seconds}s';
  }

  @override
  String get authVerificationEmailSent =>
      'Verification email sent. Please check your inbox.';

  @override
  String get authMacosUseEmailOrGoogle =>
      'On macOS, use email or Google login.';

  @override
  String get authWebAppleLimited =>
      'Apple login is limited on Web. Use email or Google.';

  @override
  String get teachersNoRecord => 'No trade records';

  @override
  String get teachersUploadRecord => 'Upload record';

  @override
  String get teachersOffline => 'Offline';

  @override
  String get teachersOnline => 'Online';

  @override
  String teachersFrozenOrBlocked(String status) {
    return 'Your account is $status. Cannot upload trade records.';
  }

  @override
  String get teachersFrozen => 'frozen';

  @override
  String get teachersBlocked => 'blocked';

  @override
  String get teachersReviewRequired =>
      'Trade record upload available after approval';

  @override
  String get teachersConfirmRiskAck =>
      'Please confirm you have read the risk notice';

  @override
  String get teachersRecordSaved => 'Trade record saved';

  @override
  String get teachersTradeRecordSymbol => 'Symbol';

  @override
  String get teachersTradeRecordSide => 'Side (buy/sell)';

  @override
  String get teachersTradeRecordPnl => 'PnL';

  @override
  String get teachersUploadQualification => 'Upload qualification';

  @override
  String get teachersUploadIdPhoto => 'Upload ID photo';

  @override
  String get teachersUploadCertification => 'Upload certification';

  @override
  String get teachersRiskAckTitle => 'I have read and agree to the risk notice';

  @override
  String get teachersPreviewHomepage => 'Preview homepage';

  @override
  String get marketMore => 'More';

  @override
  String get marketMajorIndices => 'Major indices';

  @override
  String get marketGainersLosers => 'Gainers & Losers';

  @override
  String get marketCrypto => 'Crypto';

  @override
  String get marketName => 'Name';

  @override
  String get marketLatestPrice => 'Price';

  @override
  String get marketChangePct => 'Change %';

  @override
  String get marketChangeAmount => 'Change';

  @override
  String get marketOpen => 'Open';

  @override
  String get marketPrevClose => 'Prev close';

  @override
  String get marketHigh => 'High';

  @override
  String get marketLow => 'Low';

  @override
  String get marketVolume => 'Volume';

  @override
  String get marketTurnover => 'Turnover';

  @override
  String get marketCode => 'Code';

  @override
  String get marketChange => 'Change';

  @override
  String get marketHeatmap => 'Market Heatmap';

  @override
  String get marketTradeSubcategory => 'Trade subcategory';

  @override
  String get marketHot => 'Hot';

  @override
  String get marketGoSearch => 'Search';

  @override
  String get tradingRecords => 'Trading records';

  @override
  String get tradingBuyApiPending => 'Buy API pending';

  @override
  String get tradingSellApiPending => 'Sell API pending';

  @override
  String get tradingRecordAdded => 'Trade record added';

  @override
  String get tradingDeleteRecord => 'Delete record';

  @override
  String get tradingConfirmDeleteRecord => 'Delete this trade record?';

  @override
  String get tradingDelete => 'Delete';

  @override
  String get tradingFillSymbol => 'Please enter symbol';

  @override
  String get tradingFillPriceQty => 'Please enter valid price and quantity';

  @override
  String get tradingSymbolHint => 'Enter symbol or name';

  @override
  String get tradingSymbolLabel => 'Symbol';

  @override
  String get orderClear => 'Clear';

  @override
  String orderConfirmCancel(String symbol, String action) {
    return 'Cancel $action order for $symbol?';
  }

  @override
  String get orderCancelSuccess => 'Order cancelled (simulated)';

  @override
  String get orderCancelBuy => 'buy';

  @override
  String get orderCancelSell => 'sell';

  @override
  String get chartVolume => 'Vol';

  @override
  String get chartPrevClose => 'Prev close line';

  @override
  String get chartOverlay => 'Overlay';

  @override
  String get chartSubIndicator => 'Sub indicator';

  @override
  String get chartCurrentValue => 'Current value';

  @override
  String get chartYes => 'Yes';

  @override
  String get chartNo => 'No';

  @override
  String get chartBackToLatest => 'Back to latest';

  @override
  String get commonOpening => 'Opening…';

  @override
  String get commonFeatureDeveloping => 'Feature in development';

  @override
  String get teachersNoTeachers => 'No traders';

  @override
  String get teachersTeacherHomepage => 'Trader homepage';

  @override
  String get teachersBecomeTeacher => 'Become trader';

  @override
  String get teachersHomepage => 'Homepage';

  @override
  String get teachersNoTeacherInfo => 'No trader info';

  @override
  String get teachersNone => 'None';

  @override
  String get callOtherCancelled => 'Other party cancelled';

  @override
  String get callOtherRejected => 'Other party rejected';

  @override
  String get callOtherHangup => 'Other party hung up';

  @override
  String get callPleaseHangup => 'Please tap hang up to end call';

  @override
  String get callHangup => 'Hang up';

  @override
  String get callWaiting => 'Waiting for answer...';

  @override
  String get callJoinFailed => 'Failed to join call';

  @override
  String get callFlipCamera => 'Flip';

  @override
  String get callSpeaker => 'Speaker';

  @override
  String get callEarpiece => 'Earpiece';

  @override
  String get callCheckNetwork => 'Check network if you cannot hear';

  @override
  String get callMute => 'Mute';

  @override
  String get callUnmute => 'Unmute';

  @override
  String get notificationFullScreenHint =>
      'Enable full-screen intent in settings';

  @override
  String get notificationNotEnabled => 'Notifications disabled';

  @override
  String get notificationGoToAuth => 'Authorize';

  @override
  String get notificationGoToSettings => 'Settings';

  @override
  String get appDownloadComing => 'Download link coming soon';

  @override
  String get appDownloadOpenFailed => 'Cannot open download page';

  @override
  String get chatFileExpired =>
      'File expired or not found. Ask sender to resend.';

  @override
  String searchAddedToWatchlist(String symbol) {
    return 'Added $symbol to watchlist';
  }

  @override
  String marketCopyCsvSuccess(int count) {
    return 'Copied $count rows to clipboard (CSV)';
  }

  @override
  String get msgFriendRequestAccepted => 'Friend request accepted';

  @override
  String get msgAcceptFailed => 'Accept failed';

  @override
  String get msgRejectFailed => 'Reject failed';

  @override
  String get msgSystemNotificationsEmptyHint =>
      'Friend requests and accept/reject records appear here';

  @override
  String get msgNoSystemNotifications => 'No system notifications';

  @override
  String get msgPendingOther => 'Pending';

  @override
  String get msgRequestAddYou => 'Wants to add you as friend';

  @override
  String get msgAccepted => 'Accepted';

  @override
  String get msgRejected => 'Rejected';

  @override
  String get msgYouRequestAddFriend => 'You requested to add as friend';

  @override
  String get msgAcceptShort => 'Accept';

  @override
  String get msgFriendRequestRejected => 'Friend request rejected';

  @override
  String get msgOpenChatFailed => 'Failed to open chat. Please retry.';

  @override
  String get msgOpenChatFailedPrefix => 'Failed to open chat';

  @override
  String msgConfirmDeleteFriend(String name) {
    return 'Delete $name?';
  }

  @override
  String get msgFriendDeleted => 'Friend removed';

  @override
  String get msgFriendRequestSent => 'Friend request sent';

  @override
  String get msgSendMessage => 'Send message';

  @override
  String get profilePersonalInfo => 'Profile';

  @override
  String get profileItsYou => 'This is you';

  @override
  String get msgSelectGroup => 'Select user from left';

  @override
  String groupConfirmTransfer(String name) {
    return 'Transfer ownership to $name? You will become admin.';
  }

  @override
  String get groupTransferSuccess => 'Ownership transferred';

  @override
  String get groupMemberRemoved => 'Member removed';

  @override
  String get groupRemove => 'Remove from group';

  @override
  String get groupTransferOwner => 'Transfer ownership';

  @override
  String get groupSetAdmin => 'Set as admin';

  @override
  String get groupUnsetAdmin => 'Remove admin';

  @override
  String groupConfirmCount(int count) {
    return 'Confirm ($count)';
  }

  @override
  String get groupSelectFriends => 'Select friends';

  @override
  String get pcSearchHint => 'Search…';

  @override
  String get orderNoHistory => 'No history orders';

  @override
  String get orderDate => 'Date';

  @override
  String get orderPrice => 'Price';

  @override
  String get orderFilled => 'Filled';

  @override
  String get orderSimulated => '(Simulated)';

  @override
  String get orderStatusPending => 'Pending';

  @override
  String get orderStatusPartial => 'Partial';

  @override
  String get orderStatusCancelled => 'Cancelled';

  @override
  String get orderStatusRejected => 'Rejected';

  @override
  String get tradesFillsRecord => 'Fills';

  @override
  String get tradesCurrentPositions => 'Positions';

  @override
  String get tradesNoFills => 'No fills';

  @override
  String get tradesNoPosition => 'No positions';

  @override
  String get tradesLoadPositionsFailed => 'Failed to load positions';

  @override
  String get tradesPositionShares => 'Shares';

  @override
  String get tradesPnl => 'PnL';

  @override
  String tradesQuickSellPending(String symbol) {
    return 'Quick sell $symbol (pending)';
  }

  @override
  String tradesSellPending(String symbol) {
    return 'Sell $symbol (pending)';
  }

  @override
  String get tradesConfirmMarketSellTitle => 'Confirm market sell';

  @override
  String tradesConfirmMarketSellContent(String symbol, String qty) {
    return 'Confirm market sell $symbol, quantity $qty?';
  }

  @override
  String tradesSellSubmitted(String symbol) {
    return 'Sell submitted: $symbol';
  }

  @override
  String get tradesPositionBuyMarketValue => 'Buy market value';

  @override
  String get tradesPositionCurrentMarketValue => 'Current market value';

  @override
  String get tradesPositionTotalPnl => 'Total P/L';

  @override
  String get tradesPositionTodayFloatingPnl => 'Today floating P/L';

  @override
  String get teachersProfileTitle => 'Trader profile';

  @override
  String get teachersPersonalIntro => 'Introduction';

  @override
  String get teachersExpertiseProducts => 'Expertise';

  @override
  String get teachersStrategySection => 'Strategies';

  @override
  String get teachersNoPublicStrategy => 'No public strategies';

  @override
  String get teachersEnterStrategyCenter => 'Enter strategy center';

  @override
  String teachersFollowingCount(int count) {
    return 'Following $count';
  }

  @override
  String get teachersSignatureLabel => 'Signature';

  @override
  String get teachersLicenseNoLabel => 'License No.';

  @override
  String get teachersMainMarket => 'Main market';

  @override
  String get teachersTradingStyleShort => 'Trading style';

  @override
  String get teachersRecordAndEarnings => 'Record & earnings';

  @override
  String get teachersTotalEarnings => 'Total';

  @override
  String get teachersMonthlyEarnings => 'Monthly';

  @override
  String get teachersRatingLabel => 'Rating';

  @override
  String get teachersPerformanceSection => 'Performance';

  @override
  String get teachersIntroSection => 'Introduction';

  @override
  String get teachersLatestArticles => 'Latest Articles';

  @override
  String get teachersRecentSchedule => 'Recent Schedule';

  @override
  String get msgGroupChat => 'Group';

  @override
  String msgGroupChatN(int n) {
    return 'Group ($n)';
  }

  @override
  String get msgViewTraderProfile => 'View trader profile';

  @override
  String msgExitedGroup(String name) {
    return '$name left the group';
  }

  @override
  String msgJoinedGroup(String name) {
    return '$name joined the group';
  }

  @override
  String get msgAddFriend => 'Add friend';

  @override
  String get msgAlreadyFriends => 'Already friends';

  @override
  String get msgAlreadyPending => 'Request sent. Waiting for response.';

  @override
  String get msgAddFriendFailed => 'Add friend failed';

  @override
  String get msgMePrefix => 'Me: ';

  @override
  String get msgDraft => 'Draft: ';

  @override
  String get msgOpenChatFromList => 'Failed to open chat. Go to Messages.';

  @override
  String get teachersMyTradeRecords => 'My trade records';

  @override
  String get teachersNoTradeRecords => 'No trade records';

  @override
  String get teachersNoIntro => 'No introduction';

  @override
  String get msgPrivateChat => 'Private';

  @override
  String get groupCreateGroup => 'Create group';

  @override
  String get groupCreateFailed => 'Create failed';

  @override
  String get groupCreateGroupHint => 'Leave empty to show \"Group (n)\"';

  @override
  String get groupCreateGroupButton => 'Create group';

  @override
  String groupCreateGroupButtonN(int n) {
    return 'Create group ($n)';
  }

  @override
  String get groupGroupNameLabel => 'Group name (optional)';

  @override
  String get groupNoFriendsHint => 'No friends yet. Add friends first.';

  @override
  String get groupSelectAtLeastOne => 'Select at least one friend';

  @override
  String get groupLeaveConfirm => 'Leave this group?';

  @override
  String get groupLeaveSuccess => 'Left group';

  @override
  String get groupDismissConfirm =>
      'Dismiss this group? All members will leave. Chat history cannot be recovered.';

  @override
  String get groupDismissSuccess => 'Group dismissed';

  @override
  String get groupRemoveConfirm => 'Remove this member from group?';

  @override
  String get groupSettingsTitle => 'Group settings';

  @override
  String get groupGroupName => 'Group name';

  @override
  String get groupAnnouncement => 'Announcement';

  @override
  String get groupMute => 'Mute notifications';

  @override
  String get groupInviteMembers => 'Invite members';

  @override
  String get groupInviteLink => 'Invite link';

  @override
  String groupMembersCount(int count) {
    return 'Members ($count)';
  }

  @override
  String get groupLeave => 'Leave group';

  @override
  String get groupDismiss => 'Dismiss group';

  @override
  String get groupRemoveMember => 'Remove member';

  @override
  String get groupRemoveAction => 'Remove';

  @override
  String groupSetAdminConfirm(String name) {
    return 'Set $name as admin?';
  }

  @override
  String groupUnsetAdminConfirm(String name) {
    return 'Remove admin from $name?';
  }

  @override
  String get groupSaveFailed => 'Save failed';

  @override
  String get groupLeaveFailed => 'Leave failed';

  @override
  String get groupDismissFailed => 'Dismiss failed';

  @override
  String get groupOperationFailed => 'Operation failed';

  @override
  String get groupJoinLoginFirst => 'Please login to join group';

  @override
  String get groupJoinTitle => 'Join group';

  @override
  String get groupJoinConfirm => 'Join this group?';

  @override
  String get groupJoinSuccess => 'Joined. Check Messages.';

  @override
  String get groupJoinFailed => 'Join failed';

  @override
  String get commonNone => 'None';

  @override
  String get commonLeave => 'Leave';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get commonSuccess => 'Success';

  @override
  String get chatNoMatchingMembers => 'No matching members';

  @override
  String get chatNotFriendCannotSend => 'Not friends, cannot send';

  @override
  String get chatRecordingTooShort => 'Recording too short';

  @override
  String get chatGrantMicPermission => 'Grant microphone permission';

  @override
  String get chatNoSupabaseCannotSendMedia =>
      'Supabase not configured, cannot send media';

  @override
  String get chatFileEmptyCannotSend => 'File is empty, cannot send';

  @override
  String get chatSendFailedPrefix => 'Send failed';

  @override
  String get chatCannotReadFile => 'Cannot read file';

  @override
  String get chatSelectFileFailed => 'Select file failed';

  @override
  String get chatForwardInDevelopment => 'Forward in development';

  @override
  String get chatRecalled => 'Recalled';

  @override
  String get chatRecallFailedPrefix => 'Recall failed';

  @override
  String get chatCallLabel => 'Call';

  @override
  String get chatFileSendFailedPrefix => 'File send failed';

  @override
  String get chatRemarkSaved => 'Remark saved';

  @override
  String get chatUnpinned => 'Unpinned';

  @override
  String get chatPinned => 'Pinned';

  @override
  String get chatHistoryCleared => 'Chat history cleared';

  @override
  String get chatClearFailedPrefix => 'Clear failed';

  @override
  String get chatJustNow => 'Just now';

  @override
  String get chatToday => 'Today';

  @override
  String get chatYesterday => 'Yesterday';

  @override
  String get chatUnknown => 'Unknown';

  @override
  String get chatLastOnline => 'Last online';

  @override
  String get chatNoNetworkNoCache => 'No network, no local cache';

  @override
  String get chatNoMessagesYet => 'No messages yet';

  @override
  String get chatRecordingReleaseToSend => 'Recording… Release to send';

  @override
  String get chatKeyboard => 'Keyboard';

  @override
  String get chatVoice => 'Voice';

  @override
  String get chatHoldToSpeak => 'Hold to speak';

  @override
  String get chatReleaseToSend => 'Release to send';

  @override
  String get chatAnswered => 'Answered';

  @override
  String get chatDeclined => 'Declined';

  @override
  String get chatCancelled => 'Cancelled';

  @override
  String get chatMissed => 'Missed';

  @override
  String get chatVoiceCall => 'Voice call';

  @override
  String get chatVideoCall => 'Video call';

  @override
  String chatMeStatus(String status) {
    return 'Me · $status';
  }

  @override
  String chatOtherStatus(String status) {
    return 'Other · $status';
  }

  @override
  String get chatOpening => 'Opening…';

  @override
  String get chatCannotOpenFile => 'Cannot open file';

  @override
  String get chatVideoLoadFailedPrefix => 'Video load failed';

  @override
  String chatMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String chatTodayAt(String time) {
    return 'Today $time';
  }

  @override
  String chatYesterdayAt(String time) {
    return 'Yesterday $time';
  }

  @override
  String chatDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String chatDateMonthDay(int month, int day, String time) {
    return '$month/$day $time';
  }

  @override
  String chatDateFull(int year, int month, int day) {
    return '$year/$month/$day';
  }

  @override
  String get chatLastOnlineLabel => 'Last online: ';

  @override
  String get chatWebRecordingNotSupported => 'Recording not supported on Web';

  @override
  String get chatWebFileNotSupported => 'File send not supported on Web';

  @override
  String get chatFileExpiredOrNotExist =>
      'File expired or not found. Ask sender to resend.';

  @override
  String get chatTypeImage => '[Image]';

  @override
  String get chatTypeVideo => '[Video]';

  @override
  String get chatTypeAudio => '[Voice]';

  @override
  String get chatTypeFile => '[File]';

  @override
  String get chatTeacherCard => '[Trader Card]';

  @override
  String get groupInviteFriends => 'Invite friends';

  @override
  String get groupInviteFriendHint => 'Friends can join by link or QR';

  @override
  String groupInviteFriendHintWithName(String name) {
    return 'Friends can join by link or QR to join \"$name\"';
  }

  @override
  String get groupCopyInviteLink => 'Copy invite link';

  @override
  String groupClickLinkToJoin(String link) {
    return 'Click to join: $link';
  }

  @override
  String get groupLinkCopied => 'Link copied. Friends can join via link.';

  @override
  String get groupQrInvite => 'QR invite';

  @override
  String get groupQrCopied => 'Scan to join';

  @override
  String get groupAppNotInstalled => 'App not installed? Download';

  @override
  String get groupAppNotInstalledSubtitle =>
      'Guide friends to download if not installed';

  @override
  String groupScanToJoin(String name) {
    return 'Scan to join \"$name\"';
  }

  @override
  String get groupScanWithApp => 'Scan with app to join';

  @override
  String get groupClose => 'Close';

  @override
  String get groupOwner => 'Owner';

  @override
  String get groupNoFriendsToInvite => 'No friends to invite';

  @override
  String groupInvitedCount(int count) {
    return 'Invited $count';
  }

  @override
  String get groupInviteFailedPrefix => 'Invite failed';

  @override
  String get groupEditName => 'Edit group name';

  @override
  String get groupNameHint => 'Group name';

  @override
  String get groupNameUpdated => 'Group name updated';

  @override
  String get groupMuteOn => 'Mute on';

  @override
  String get groupMuteOff => 'Mute off';

  @override
  String get groupNoSupabaseUpload => 'Supabase not configured, cannot upload';

  @override
  String get groupAvatarUpdated => 'Group avatar updated';

  @override
  String get groupUploadFailedPrefix => 'Upload failed';

  @override
  String get groupShortLabel => 'Group';

  @override
  String get groupEditAnnouncement => 'Announcement';

  @override
  String get groupAnnouncementHint => 'Enter announcement';

  @override
  String get groupAnnouncementUpdated => 'Announcement updated';

  @override
  String get groupLoadFailedPrefix => 'Load failed';

  @override
  String get groupLoadError => 'Cannot load group info';

  @override
  String get groupInviteNewMembers => 'Invite members';

  @override
  String groupConfirmCountShort(int count) {
    return 'Confirm($count)';
  }

  @override
  String groupMemberListTitle(int count) {
    return 'Members ($count)';
  }

  @override
  String get groupRoleOwner => 'Owner';

  @override
  String get groupRoleAdmin => 'Admin';

  @override
  String get groupMemberHint => 'Tap ⋮ to remove, transfer, or set admin';

  @override
  String get ordersConfirmCancel => 'Confirm cancel';

  @override
  String get ordersTodayOrders => 'Today\'s orders';

  @override
  String get ordersNoTodayOrders => 'No orders today';

  @override
  String get ordersOrderPrice => 'Price';

  @override
  String get ordersQuantity => 'Qty';

  @override
  String get ordersFilled => 'Filled';

  @override
  String get ordersCancelOrder => 'Cancel';

  @override
  String get ordersStatusPending => 'Pending';

  @override
  String get ordersStatusPartial => 'Partial';

  @override
  String get ordersStatusFilled => 'Filled';

  @override
  String get ordersStatusCancelled => 'Cancelled';

  @override
  String get ordersStatusRejected => 'Rejected';

  @override
  String get ordersBuy => 'Buy';

  @override
  String get ordersSell => 'Sell';

  @override
  String get ordersMarket => 'Market';

  @override
  String get marketGainersLosersTitle => 'Gainers & Losers';

  @override
  String get marketThreeIndicesLabel => 'Major indices';

  @override
  String get marketNameLabel => 'Name';

  @override
  String get msgNewFriendRequest => 'You have a new friend request';

  @override
  String msgNewFriendRequests(int count) {
    return 'You have $count new friend requests';
  }

  @override
  String get msgNoNicknameSet => 'No nickname set';

  @override
  String get msgSearchHint => 'Search friends/remark/Account ID';

  @override
  String get msgShowBlacklist => 'Show blacklist';

  @override
  String get msgHideBlacklist => 'Hide blacklist';

  @override
  String get msgBlacklist => 'Blacklist';

  @override
  String get msgBlocked => 'Blocked';

  @override
  String get msgRemoveFromBlacklist => 'Remove from blacklist';

  @override
  String get msgAddToBlacklist => 'Add to blacklist';

  @override
  String get msgDeleteFriend => 'Delete friend';

  @override
  String get msgSetRemark => 'Set remark';

  @override
  String get msgRemarkHint => 'Enter remark';

  @override
  String get msgNoConversations => 'No conversations';

  @override
  String get msgNoMatchingConversations => 'No matching conversations';

  @override
  String get msgFriendRequest => 'Friend request';

  @override
  String get msgNoFriends => 'No friends';

  @override
  String get msgOnline => 'Online';

  @override
  String get msgOffline => 'Offline';

  @override
  String get msgFeatureDeveloping => 'Feature in development';

  @override
  String get msgUnpin => 'Unpin';

  @override
  String get msgPin => 'Pin';

  @override
  String get msgDeleteConversation => 'Delete conversation';

  @override
  String msgDeleteFriendConfirm(String name) {
    return 'Delete $name?';
  }

  @override
  String get msgDelete => 'Delete';

  @override
  String get msgSelectConversation => 'Select a conversation to chat';

  @override
  String get msgClickLeftToOpen => 'Tap a conversation on the left to open';

  @override
  String get msgMore => 'More';

  @override
  String get msgDecline => 'Decline';

  @override
  String get msgAccept => 'Accept';

  @override
  String get msgOperationFailed => 'Operation failed';

  @override
  String get msgSearchFailed => 'Search failed';

  @override
  String get msgSendFailed => 'Send failed';

  @override
  String get msgAcceptFriendSuccess => 'Friend request accepted';

  @override
  String get msgRejectFriendSuccess => 'Friend request declined';

  @override
  String get tradingCurrentPositions => 'Current positions';

  @override
  String get tradingMyRecords => 'My records';

  @override
  String get tradingNoRecordsAdd => 'No records. Tap + to add.';

  @override
  String get tradingRealtimeQuote => 'Realtime quote';

  @override
  String get tradingCurrentPrice => 'Current price';

  @override
  String get tradingChangePct => 'Change %';

  @override
  String get tradingAddRecord => 'Add record';

  @override
  String get tradingStockCode => 'Stock code';

  @override
  String get tradingStockName => 'Stock name';

  @override
  String get tradingBuyTime => 'Buy time';

  @override
  String get tradingBuyPrice => 'Buy price';

  @override
  String get tradingBuyQty => 'Buy qty';

  @override
  String get tradingSellTime => 'Sell time';

  @override
  String get tradingSellPrice => 'Sell price';

  @override
  String get tradingSellQty => 'Sell qty';

  @override
  String get tradingCost => 'Cost';

  @override
  String get tradingCurrentPriceLabel => 'Current';

  @override
  String get tradingHintStockCode => 'e.g. 600519';

  @override
  String get tradingHintStockName => 'Optional, e.g. Kweichow Moutai';

  @override
  String get tradingQty => 'Qty';

  @override
  String get tradingPnl => 'P/L';

  @override
  String get tradingHintYuan => 'CNY';

  @override
  String get tradingHintShares => 'shares';

  @override
  String get searchUsStock => 'US Stocks';

  @override
  String get searchCrypto => 'Crypto';

  @override
  String get searchForex => 'Forex';

  @override
  String get searchIndex => 'Index';

  @override
  String get searchHint => 'Stock or crypto name, symbol';

  @override
  String get searchInputHint => 'Enter name or symbol to search';

  @override
  String searchNotFound(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get searchAddWatchlist => 'Add to watchlist';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get commonUserInitial => 'U';

  @override
  String get groupNewMember => 'New member';

  @override
  String get groupSomeUser => 'User';

  @override
  String get commonListSeparator => ', ';

  @override
  String get watchlistTitle => 'Watchlist';

  @override
  String get watchlistAdd => 'Add';

  @override
  String get watchlistRemove => 'Remove';

  @override
  String get marketIndexDow => 'Dow Jones';

  @override
  String get marketRequestTimeout => 'Request timeout';

  @override
  String get chartNoData => 'No data';

  @override
  String get chartLoading => 'Loading…';

  @override
  String get chartPreMarket => 'Pre-market';

  @override
  String get chartClosed => 'Closed';

  @override
  String get chartIntraday => 'Intraday';

  @override
  String get chartPrice => 'Price';

  @override
  String get chartAvg => 'Avg';

  @override
  String get chartChangeShort => 'Chg';

  @override
  String get chartVol => 'Vol';

  @override
  String get chartTurnover => 'Turnover';

  @override
  String get chartFetching => 'Fetching data…';

  @override
  String chartFetchingWithLabel(String label) {
    return 'Fetching $label data…';
  }

  @override
  String get chartTimeshareLabel => 'Intraday';

  @override
  String get chartKlineLabel => 'K-line';

  @override
  String get chartChangePercent => 'Chg %';

  @override
  String get chartEmptyHint =>
      'Intraday and K-line data unavailable. Retry later or check data source.';

  @override
  String get chartNoIntradayData => 'No intraday data';

  @override
  String get chartNoKlineData => 'No K-line data';

  @override
  String get chartRetry => 'Retry';

  @override
  String get chartSwitchDataSource => 'Switch data source';

  @override
  String get chartPriceOpen => 'Open';

  @override
  String get chartPriceHigh => 'High';

  @override
  String get chartPriceLow => 'Low';

  @override
  String get chartPricePrevClose => 'Prev close';

  @override
  String get chartPriceTotalTurnover => 'Turnover';

  @override
  String get chartPriceTurnoverRate => 'Turnover rate';

  @override
  String get chartPriceAmplitude => 'Amplitude';

  @override
  String get chartStatsOpen => 'O';

  @override
  String get chartStatsHigh => 'H';

  @override
  String get chartStatsLow => 'L';

  @override
  String get chartStatsClose => 'C';

  @override
  String get chartStatsPrevClose => 'Prev';

  @override
  String get chartStatsChange => 'Chg';

  @override
  String get chartStatsChangePct => 'Chg%';

  @override
  String get chartStatsAmplitude => 'Amp';

  @override
  String get chartStatsAvgPrice => 'Avg';

  @override
  String get chartStatsVolume => 'Vol';

  @override
  String get chartStatsTurnover => 'Turnover';

  @override
  String get chartStatsDividendYield => 'Yield';

  @override
  String get chartStatsTurnoverRate => 'Turnover';

  @override
  String get chartStatsPeTtm => 'P/E TTM';

  @override
  String get chartOrderBookSell => 'Sell';

  @override
  String get chartOrderBookQty => 'Qty';

  @override
  String get chartOrderBookBuy => 'Buy';

  @override
  String get chartTabOrderBook => 'Order book';

  @override
  String get chartTabIndicator => 'Indicator';

  @override
  String get chartTabCapital => 'Capital';

  @override
  String get chartTabNews => 'News';

  @override
  String get chartTabAnnouncement => 'Announcement';

  @override
  String get chartIndicatorNone => 'None';

  @override
  String get chartIndicatorYes => 'Yes';

  @override
  String get chartIndicatorNo => 'No';

  @override
  String get chartPrevCloseLine => 'Prev close line';

  @override
  String get chartMainOverlay => 'Main overlay';

  @override
  String get chartQuoteLoadFailed => 'Load failed';

  @override
  String get chartClickToClose => 'Click to close';

  @override
  String get chartMockDataHint => 'Mock data for display';

  @override
  String get chartCompanyActions => 'Corporate actions';

  @override
  String get chartDividends => 'Dividends';

  @override
  String get chartSplits => 'Splits';

  @override
  String get chartQuoteRefreshHint =>
      'Quote updates every second, chart refreshes every 10s';

  @override
  String get chartOhlcHint => 'Below: day open, high, low, close';

  @override
  String chartRequestFailed(String error) {
    return 'Request failed: $error';
  }

  @override
  String get chartClickRetry => 'Tap to refresh';

  @override
  String get chartNoDataTroubleshoot =>
      'If still no data: ensure backend is running; set TONGXIN_API_URL to your machine IP in .env';

  @override
  String get chartNoChartData => 'No chart data';

  @override
  String get chartWeekK => 'Week';

  @override
  String get chartMonthK => 'Month';

  @override
  String get chartYearK => 'Year';

  @override
  String get chart1Min => '1m';

  @override
  String get chart5Min => '5m';

  @override
  String get chart15Min => '15m';

  @override
  String get chart30Min => '30m';

  @override
  String get chart1min => '1m';

  @override
  String get chart5min => '5m';

  @override
  String get chart15min => '15m';

  @override
  String get chart30min => '30m';

  @override
  String get chartDayK => 'Day';

  @override
  String get chartTimeshare => 'Intraday';

  @override
  String get promoTitle =>
      'Finance Training\nFocused on Live Trading & Strategy';

  @override
  String get promoSubtitle =>
      'Expert mentors help you build a strategy system from cognition to execution.';

  @override
  String get promoFeature1 => 'Mentor verification & performance display';

  @override
  String get promoFeature2 => 'Daily strategy & position tracking';

  @override
  String get promoFeature3 => 'Peer support & community';

  @override
  String get promoCarouselTitle => 'Teaching features';

  @override
  String get promoSlide1Title => 'Quant & Risk Control';

  @override
  String get promoSlide1Subtitle =>
      'Strategy review + risk model + live tracking';

  @override
  String get promoSlide2Title => 'Asset Allocation';

  @override
  String get promoSlide2Subtitle =>
      'Multi-dimensional portfolio, steady growth';

  @override
  String get promoSlide3Title => 'Mentor Support';

  @override
  String get promoSlide3Subtitle =>
      'Daily strategy insights & hands-on guidance';

  @override
  String get promoBrand => 'Finance Training';

  @override
  String get notifChannelChat => 'Messages';

  @override
  String get notifChannelCall => 'Incoming call';

  @override
  String get notifOther => 'Other';

  @override
  String notifInviteCall(String name, String type) {
    return '$name invites you to $type call';
  }

  @override
  String get notifVideoCall => 'video';

  @override
  String get notifVoiceCall => 'voice';

  @override
  String get notifNewMessage => 'New message';

  @override
  String get notifNewMessageBody => 'You have a new message';

  @override
  String get notifFullScreenIntentHint =>
      'Enable full-screen intent in settings';

  @override
  String get notifNotEnabled => 'Notifications disabled';

  @override
  String get notifPermissionDenied =>
      'You have denied notification permission. Tap \"Authorize\" to request again, or enable in system settings.';

  @override
  String get notifGoAuthorize => 'Authorize';

  @override
  String get notifGoSettings => 'Settings';

  @override
  String get restrictStatusNormal => 'Account status: Normal';

  @override
  String restrictBannedUntil(String date) {
    return 'Account banned until $date';
  }

  @override
  String restrictFrozenUntil(String date) {
    return 'Account frozen until $date';
  }

  @override
  String get restrictLogin => 'Account status: Login restricted';

  @override
  String get restrictSendMessage => 'Account status: Messaging restricted';

  @override
  String get restrictAddFriend => 'Account status: Add friend disabled';

  @override
  String get restrictJoinGroup => 'Account status: Join group disabled';

  @override
  String get restrictCreateGroup => 'Account status: Create group disabled';

  @override
  String get adminOverview => 'Overview';

  @override
  String get adminUserManagement => 'User Management';

  @override
  String get adminTeacherReview => 'Teacher Review';

  @override
  String get adminSystemMessages => 'System Messages';

  @override
  String get adminReports => 'Reports & Review';

  @override
  String get adminSettings => 'Settings';

  @override
  String get adminKeyMetrics => 'Key metrics and system status';

  @override
  String get adminTeachersTotal => 'Total traders';

  @override
  String get adminPending => 'Pending';

  @override
  String get adminApproved => 'Approved';

  @override
  String get adminRejected => 'Rejected';

  @override
  String get adminFrozen => 'Frozen';

  @override
  String get adminBlocked => 'Blocked';

  @override
  String get adminSaved => 'Saved';

  @override
  String get adminSaveFailed => 'Save failed';

  @override
  String get adminUserProfile => 'User Profile';

  @override
  String get adminRestrictAndBan => 'Restrictions & Ban';

  @override
  String adminBanUntil(String date) {
    return 'Banned until $date';
  }

  @override
  String adminFrozenUntil(String date) {
    return 'Frozen until $date';
  }

  @override
  String get adminBan => 'Ban';

  @override
  String get adminFreeze => 'Freeze';

  @override
  String get adminRestrictHint => 'Toggle to disable user actions';

  @override
  String get adminRestrictLogin => 'Restrict login';

  @override
  String get adminRestrictLoginSub => 'Block this account from logging in';

  @override
  String get adminRestrictSendMessage => 'Restrict messaging';

  @override
  String get adminRestrictAddFriend => 'Disable add friend';

  @override
  String get adminRestrictJoinGroup => 'Disable join group';

  @override
  String get adminRestrictCreateGroup => 'Disable create group';

  @override
  String get adminBanDuration => 'Ban duration';

  @override
  String get adminFrozenDuration => 'Freeze duration';

  @override
  String get adminDays7 => '7 days';

  @override
  String get adminDays30 => '30 days';

  @override
  String get adminDays90 => '90 days';

  @override
  String get adminPermanent => 'Permanent';

  @override
  String get adminSelectUser => 'Select user from left';

  @override
  String get adminNoUserData => 'No user data';

  @override
  String adminUsersCount(int count) {
    return '$count users';
  }

  @override
  String get adminRefresh => 'Refresh';

  @override
  String get adminPlaceholderHint =>
      'This module is ready. Next: connect data and logic.';

  @override
  String get adminSystemMessagesDesc =>
      'Edit system announcements, push notifications, templates.';

  @override
  String get adminReportsDesc =>
      'Handle user reports, content moderation, violations.';

  @override
  String get adminSettingsDesc => 'Feature toggles, config, version strategy.';

  @override
  String get adminSystemMessagesHint =>
      'Connect to messages and send_push function.';

  @override
  String get adminNickname => 'Nickname';

  @override
  String get adminShortId => 'Short ID';

  @override
  String get adminRole => 'Role';

  @override
  String get adminUserId => 'User ID';

  @override
  String get adminSignature => 'Signature';

  @override
  String get adminProfileSaved => 'Profile saved';

  @override
  String adminStatusUpdated(String label) {
    return 'Status updated to: $label';
  }

  @override
  String get adminUpdateFailed => 'Update failed';

  @override
  String get adminSelectTeacher => 'Select a teacher';

  @override
  String get adminPerformanceLabel => 'Performance';

  @override
  String get adminIdPhotoLabel => 'ID & qualification photos';

  @override
  String get adminReviewCredentials =>
      'Review credentials (ID & qualifications)';

  @override
  String get adminSaveProfile => 'Save profile';

  @override
  String get adminAddStrategy => 'Add strategy';

  @override
  String get adminAddTradeRecord => 'Add trade record';

  @override
  String get adminAddCurrentPosition => 'Add current position';

  @override
  String get adminAddHistoryPosition => 'Add history position';

  @override
  String get adminAddComment => 'Add comment';

  @override
  String get adminAddArticle => 'Add article';

  @override
  String get adminAddSchedule => 'Add schedule';

  @override
  String get adminNotUploaded => 'Not uploaded';

  @override
  String get adminApprove => 'Approve';

  @override
  String get adminReject => 'Reject';

  @override
  String get adminUnfreeze => 'Unfreeze';

  @override
  String get adminUnblock => 'Unblock';

  @override
  String get adminRevertToPending => 'Revert to pending';

  @override
  String get adminNotifyTraderResult => 'Trader application result';

  @override
  String get adminNotifyRejected =>
      'Your trader application has been rejected. You may revise and resubmit.';

  @override
  String get adminNotifyApproved =>
      'Congratulations! Your trader application has been approved. You can now publish strategies and trade records.';

  @override
  String get adminNotifyBlocked =>
      'Your trader account has been blocked. Please contact support if you have questions.';

  @override
  String get adminNotifyFrozen =>
      'Your trader account has been frozen. You cannot publish content during the freeze period.';

  @override
  String get adminAll => 'All';

  @override
  String get adminPendingJustApplied => 'Pending (just applied)';

  @override
  String get adminAllTeachers => 'All teachers';

  @override
  String adminTeachersCount(int count) {
    return '$count teachers';
  }

  @override
  String get adminRefreshList => 'Refresh list';

  @override
  String get adminFilterByStatus => 'Filter by status';

  @override
  String get adminNoTeachersData => 'No teacher data';

  @override
  String get adminNoMatchingData => 'No matching data';

  @override
  String get adminConfirmTableData =>
      'Please ensure teacher_profiles table has data';

  @override
  String get adminTrySwitchAll => 'Try switching to \"All\"';

  @override
  String get adminActionsByStatus => 'Actions (by current status)';

  @override
  String get adminBasicInfo => 'Basic info';

  @override
  String get adminDisplayName => 'Display name';

  @override
  String get adminRealName => 'Real name';

  @override
  String get adminTitlePosition => 'Title / position';

  @override
  String get adminOrg => 'Organization';

  @override
  String get adminBio => 'Bio';

  @override
  String get adminTags => 'Tags (comma-separated)';

  @override
  String get adminLicenseNo => 'License / registration no.';

  @override
  String get adminCertifications => 'Certifications';

  @override
  String get adminMarkets => 'Markets';

  @override
  String get adminStyle => 'Trading style';

  @override
  String get adminBroker => 'Broker / platform';

  @override
  String get adminCountry => 'Country / region';

  @override
  String get adminCity => 'City';

  @override
  String get adminYearsExperience => 'Years of experience';

  @override
  String get adminIdPhoto => 'ID photo';

  @override
  String get adminLicensePhoto => 'License proof';

  @override
  String get adminCertificationPhoto => 'Certification photo';

  @override
  String get adminPerformanceSection => 'Performance & P&L';

  @override
  String get adminWins => 'Wins';

  @override
  String get adminLosses => 'Losses';

  @override
  String get adminRating => 'Rating';

  @override
  String get adminTodayStrategy => 'Today\'s strategy';

  @override
  String get adminPnlCurrent => 'Weekly P&L';

  @override
  String get adminPnlMonth => 'Monthly P&L';

  @override
  String get adminPnlYear => 'Yearly P&L';

  @override
  String get adminPnlTotal => 'Total P&L';

  @override
  String get adminContentManagement => 'Content management';

  @override
  String get adminReviewActions => 'Review actions (just applied)';

  @override
  String get adminReviewActionsShort => 'Review actions';

  @override
  String get adminDispose => 'Actions';

  @override
  String get adminConfirmReject => 'Confirm reject this application?';

  @override
  String get adminConfirmBlock =>
      'Confirm block this teacher? Their profile will be hidden from public.';

  @override
  String adminFrozenUntilLabel(String date) {
    return 'Frozen until: $date';
  }

  @override
  String get adminConfirmUnfreeze => 'Confirm unfreeze?';

  @override
  String get adminConfirmUnblock => 'Confirm unblock?';

  @override
  String get adminRevertToPendingConfirm => 'Confirm revert to pending?';

  @override
  String get adminSelectFreezeDuration => 'Select freeze duration:';

  @override
  String get adminFreezeDuration => 'Freeze duration';

  @override
  String get adminLoadFailed => 'Load failed';

  @override
  String get adminTeacherDefault => 'Teacher';

  @override
  String get adminCurrentStatus => 'Current status:';

  @override
  String get adminFormLabelTitle => 'Title';

  @override
  String get adminFormLabelSummary => 'Summary';

  @override
  String get adminFormLabelContent => 'Content';

  @override
  String get adminFormLabelAsset => 'Asset';

  @override
  String get adminFormLabelBuyTime => 'Buy time (YYYY-MM-DD)';

  @override
  String get adminFormLabelBuyShares => 'Buy quantity';

  @override
  String get adminFormLabelBuyPrice => 'Buy price';

  @override
  String get adminFormLabelSellTime => 'Sell time (YYYY-MM-DD)';

  @override
  String get adminFormLabelSellShares => 'Sell quantity';

  @override
  String get adminFormLabelSellPrice => 'Sell price';

  @override
  String get adminFormLabelPnlRatio => 'Return %';

  @override
  String get adminFormLabelPnlAmount => 'P&L amount';

  @override
  String get adminFormLabelCostPrice => 'Cost price';

  @override
  String get adminFormLabelCurrentPrice => 'Current price';

  @override
  String get adminFormLabelFloatingPnl => 'Floating P&L';

  @override
  String get adminFormLabelUserName => 'User nickname';

  @override
  String get adminFormLabelLocation => 'Location';

  @override
  String get adminFormLabelTime => 'Time (YYYY-MM-DD)';

  @override
  String get adminFormLabelTimeSchedule => 'Time (YYYY-MM-DD HH:MM)';

  @override
  String get adminFormLabelSellTimeHistory => 'Sell time (YYYY-MM-DD)';

  @override
  String get adminFormLabelSellPriceHistory => 'Sell price';

  @override
  String adminUnknownStatus(String raw) {
    return 'Unknown status: $raw. Check DB status field (pending/approved/rejected/frozen/blocked)';
  }

  @override
  String get roleNormal => 'User';

  @override
  String get roleTrader => 'Trader';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleVip => 'Member';

  @override
  String get roleCustomerService => 'Customer Service';

  @override
  String get pcHome => 'Home';

  @override
  String get pcNotify => 'Notifications';

  @override
  String get pcGreetingHello => 'Hello';

  @override
  String get pcGreetingMorning => 'Good morning';

  @override
  String get pcGreetingAfternoon => 'Good afternoon';

  @override
  String get pcGreetingEvening => 'Good evening';

  @override
  String get pcWelcomeBack => 'Welcome back. Here is your dashboard overview.';

  @override
  String get pcFollow => 'Following';

  @override
  String get pcFollowSubtitle => 'Followed symbols';

  @override
  String get pcTodayChat => 'Today\'s chats';

  @override
  String get pcMessageCount => 'Messages';

  @override
  String get pcWatchlist => 'Watchlist';

  @override
  String get pcWatchlistSubtitle => 'Watchlist symbols';

  @override
  String get pcRanking => 'Ranking';

  @override
  String get pcRankingSubtitle => 'Current rank';

  @override
  String get pcMarket => 'Market';

  @override
  String get pcMarketSubtitle => 'View market and indices';

  @override
  String get pcManageWatchlist => 'Manage watchlist';

  @override
  String get pcMessages => 'Messages';

  @override
  String get pcMessagesSubtitle => 'Chats and friends';

  @override
  String get pcLeaderboard => 'Leaderboard';

  @override
  String get pcLeaderboardSubtitle => 'View rankings';

  @override
  String get pcQuickEntry => 'Quick entry';

  @override
  String get pcEnter => 'Enter';

  @override
  String get networkNoConnection => 'No network. Check connection and retry.';

  @override
  String get networkTryAgain => 'Network error. Please try again later.';

  @override
  String get networkAuthExpired =>
      'Login expired or invalid. Please login again.';

  @override
  String get networkPermissionDenied =>
      'Permission denied. Check login status.';

  @override
  String get adminReportReporter => 'Reporter';

  @override
  String get adminReportReported => 'Reported user';

  @override
  String get adminReportNoData => 'No reports yet';

  @override
  String get adminReportNotes => 'Admin notes';

  @override
  String get profileCsWorkbench => 'Customer Service';

  @override
  String get profileCsWorkbenchSubtitle => 'View and reply to user messages';

  @override
  String get adminCsConfig => 'Customer Service Config';

  @override
  String get adminCsSystemAccount => 'System CS Account';

  @override
  String get adminCsSystemAccountHint =>
      'The friend users add, select from user list';

  @override
  String get adminCsAvatarUrl => 'CS Avatar URL';

  @override
  String get adminCsStaff => 'CS Staff';

  @override
  String get adminCsStaffHint => 'Can access workbench and reply to users';

  @override
  String get adminSelectAsSystemCs => 'Set as System CS';

  @override
  String get adminAddAsCsStaff => 'Add as CS Staff';

  @override
  String get adminRemoveCsStaff => 'Remove CS Staff';

  @override
  String get adminCsNotConfigured => 'Not configured';

  @override
  String get adminCsUploadAvatar => 'Upload Avatar';

  @override
  String get adminCsWelcomeMessage => 'Auto Welcome Message';

  @override
  String get adminCsWelcomeMessageHint =>
      'Sent when user first contacts CS, leave empty to disable';

  @override
  String get adminCsBroadcast => 'Broadcast Message';

  @override
  String get adminCsBroadcastHint =>
      'Send as system CS to all users who have added CS';

  @override
  String get adminCsBroadcastSend => 'Send Broadcast';

  @override
  String adminCsBroadcastSuccess(Object count) {
    return 'Sent to $count users';
  }

  @override
  String get adminCsBroadcastEmpty => 'Message cannot be empty';

  @override
  String get tradingSummaryUnavailable => 'Account data unavailable';

  @override
  String get tradingSummaryAvailable => 'Available';

  @override
  String get tradingSummaryEquity => 'Equity';

  @override
  String get tradingSummaryMarketValue => 'Market value';

  @override
  String get tradingSummaryOpenOrders => 'Open orders';

  @override
  String get tradingSummaryAvailableFunds => 'Available funds';

  @override
  String get tradingSummaryFrozenFunds => 'Frozen funds';

  @override
  String get tradingSummaryCashBalance => 'Cash balance';

  @override
  String get tradingSummaryRealizedPnl => 'Realized P/L';

  @override
  String get tradingSummaryUnrealizedPnl => 'Unrealized P/L';

  @override
  String get tradingSummaryTodayPnl => 'Today P/L';

  @override
  String get tradingSummaryFundDistribution => 'Fund Distribution';

  @override
  String get tradingSummaryAssetStructure => 'Asset Structure';

  @override
  String get tradingSummaryProfitOverview => 'Profit Overview';

  @override
  String get tradingLedgerTitle => 'Account Ledger';

  @override
  String get tradingLedgerTypeFilter => 'Type filter: ';

  @override
  String get tradingLedgerEmpty => 'No ledger entries';

  @override
  String get tradingLedgerBalanceLabel => 'Balance';

  @override
  String get tradingLedgerCsvCopied => 'CSV copied to clipboard';

  @override
  String get tradingLedgerTypeAccountReset => 'Account reset';

  @override
  String get tradingLedgerTypeOrderCashFrozen => 'Order cash frozen';

  @override
  String get tradingLedgerTypeOrderCancelUnfreeze => 'Order cancel unfreeze';

  @override
  String get tradingLedgerTypeOrderFilledBuy => 'Buy fill';

  @override
  String get tradingLedgerTypeOrderFilledSell => 'Sell fill';

  @override
  String get teachersAccountAndLedgerTab => 'Account & Ledger';

  @override
  String get teachersQualificationPhoto => 'Qualification photo';

  @override
  String get teachersSubmitting => 'Submitting...';

  @override
  String get teachersSubmittedPendingReview => 'Submitted, waiting for review';

  @override
  String get teachersSubmitApplication => 'Submit Application';

  @override
  String get teachersStatusFrozenMessage =>
      'Your account is frozen. You cannot publish strategies or trade records.';

  @override
  String teachersStatusUnfreezeTime(String date) {
    return ' Unfreeze at: $date';
  }

  @override
  String get teachersStatusBlockedMessage =>
      'Your account is blocked. You cannot publish strategies or trade records. Please contact customer service if needed.';

  @override
  String get teachersStatusRejectedMessage =>
      'Your application was rejected. You cannot publish strategies or trade records. Please contact customer service if needed.';

  @override
  String get teachersStatusPendingMessage =>
      'Under review. Publishing strategies and trade records will be enabled after approval.';

  @override
  String teachersStatusCannotPublishHint(String status) {
    return 'Your account is $status. Publishing strategies is not available.';
  }

  @override
  String get teachersStatusOpenAfterApproval =>
      'Strategy publishing will be available after approval';

  @override
  String get teachersTradingAccount => 'Trading Account';

  @override
  String get teachersSpotAccount => 'Spot Account';

  @override
  String get teachersContractAccount => 'Contract Account';

  @override
  String get tradingSpotBuy => 'Spot Buy';

  @override
  String get tradingSpotSell => 'Spot Sell';

  @override
  String get tradingOpenLong => 'Open Long';

  @override
  String get tradingCloseLong => 'Close Long';

  @override
  String get tradingOpenShort => 'Open Short';

  @override
  String get tradingCloseShort => 'Close Short';

  @override
  String get tradingProductSpot => 'Spot';

  @override
  String get tradingProductPerpetual => 'Perpetual';

  @override
  String get tradingProductFuture => 'Futures';

  @override
  String get tradingPositionLong => 'Long';

  @override
  String get tradingPositionShort => 'Short';

  @override
  String get tradingMarginCross => 'Cross';

  @override
  String get tradingMarginIsolated => 'Isolated';

  @override
  String get tradingNoMatchedSymbol => 'No matching symbol found';

  @override
  String tradingPickSymbol(String query) {
    return 'Select symbol (\"$query\")';
  }

  @override
  String get tradingOrderPlaced => 'Order placed';

  @override
  String get tradingMode => 'Trading Mode';

  @override
  String tradingMaintenanceRate(String rate) {
    return 'Maintenance margin rate $rate%';
  }

  @override
  String get tradingPositionDirection => 'Position Direction';

  @override
  String get tradingMarginMode => 'Margin Mode';

  @override
  String get tradingLeverage => 'Leverage';

  @override
  String get tradingMargin => 'Margin';

  @override
  String tradingLeverageWithMax(String leverage, String max) {
    return 'Leverage ${leverage}x / Max ${max}x';
  }

  @override
  String get tradingAvailableFunds => 'Available Funds';

  @override
  String get tradingEstimatedOccupied => 'Estimated Used';

  @override
  String get tradingEstimatedMargin => 'Estimated Margin';

  @override
  String get tradingInsufficientFunds => 'Insufficient available funds';

  @override
  String get tradingInsufficientMargin => 'Insufficient available margin';

  @override
  String tradingNeedAndCurrent(String label, String need, String current) {
    return '$label (need $need, current $current)';
  }

  @override
  String get tradingTransferFunds => 'Account Transfer';

  @override
  String tradingTransferFromTo(String from, String to) {
    return 'Transfer from $from to $to';
  }

  @override
  String get tradingTransferAmount => 'Transfer Amount';

  @override
  String get tradingEnterValidTransferAmount =>
      'Please enter a valid transfer amount';

  @override
  String get tradingInsufficientAvailableFunds =>
      'Insufficient available funds';

  @override
  String get tradingTransferSuccess => 'Transfer completed';

  @override
  String get tradingLedgerTypePositionLiquidated => 'Forced Liquidation';

  @override
  String get tradingLedgerTypeTransferOut => 'Transfer Out';

  @override
  String get tradingLedgerTypeTransferIn => 'Transfer In';

  @override
  String tradingLedgerCsvHeader(String suffix) {
    return 'Time,Entry Type,Symbol,Asset Class,Product Type,Side,Position Side,Amount$suffix,Balance After$suffix,Note';
  }

  @override
  String get tradingLoadMore => 'Load more';

  @override
  String get tradingViewDetails => 'View details';

  @override
  String get tradingSellableQuantity => 'Sellable Qty';

  @override
  String get tradingClosableQuantity => 'Closable Qty';

  @override
  String get tradingAssetGeneric => 'Asset';

  @override
  String get reportSelectFromFriends => 'Select from friends';

  @override
  String get reportNoFriendsYet => 'No friends yet';

  @override
  String get reportSelectFriendHint => 'Select a friend';

  @override
  String get reportInvalidTargetUser => 'Report failed: invalid target user';

  @override
  String get reportScreenshotUploadFailed =>
      'Report failed: screenshot upload failed';

  @override
  String get rankingsBoardWeekly => 'Weekly';

  @override
  String get rankingsBoardMonthly => 'Monthly';

  @override
  String get rankingsBoardQuarterly => 'Quarterly';

  @override
  String get rankingsBoardYearly => 'Yearly';

  @override
  String get rankingsBoardAllTime => 'All Time';

  @override
  String get rankingsTop10 => 'Top 10';

  @override
  String tradingLeverageX(String value) {
    return '${value}x';
  }

  @override
  String tradingNotionalValue(String value) {
    return 'Notional $value';
  }

  @override
  String get tradingPositionHolding => 'Position';

  @override
  String get tradingLiquidationPrice => 'Liq. Price';

  @override
  String tradingCloseQuantityExceeded(String label, String max) {
    return '$label insufficient, max closable now: $max';
  }

  @override
  String tradingEnterValidCloseQuantity(String action) {
    return 'Enter a valid $action quantity';
  }

  @override
  String tradingEnterValidLimitPriceFor(String action) {
    return 'Enter a valid limit price for $action';
  }

  @override
  String tradingCurrentAndFloating(String current, String floating) {
    return 'Current $current   Floating $floating';
  }

  @override
  String tradingPriceForAction(String action) {
    return '$action price';
  }

  @override
  String tradingConfirmAction(String action) {
    return 'Confirm $action';
  }

  @override
  String get tradingQuantityWord => 'Qty';

  @override
  String get dashboardEyebrowMentor => 'Featured Mentors';

  @override
  String get dashboardTitleMentor =>
      'Browse first, then follow with confidence';

  @override
  String get dashboardActionViewAll => 'View all';

  @override
  String get dashboardEyebrowRanking => 'Monthly Rankings';

  @override
  String get dashboardTitleRanking => 'Check Top 3 first, then dive deeper';

  @override
  String get dashboardActionFullRanking => 'Full rankings';

  @override
  String get dashboardEyebrowNews => 'Hot News';

  @override
  String get dashboardTitleNews => 'English market highlights at a glance';

  @override
  String get dashboardActionMoreNews => 'More news';

  @override
  String get dashboardHeroTitle => 'Understand rankings before following';

  @override
  String get dashboardHeroSubtitle =>
      'Home combines ranking insights, mentor entry points, and market snapshots to help you make clearer follow decisions in less time.';

  @override
  String get dashboardHeroActionViewRanking => 'View rankings';

  @override
  String get dashboardHeroMetricDimensionLabel => 'Ranking dimensions';

  @override
  String get dashboardHeroMetricDimensionValue => '5 types';

  @override
  String get dashboardHeroMetricCountLabel => 'Displayed count';

  @override
  String get dashboardHeroMetricCountValue => 'Top10';

  @override
  String get dashboardHeroMetricUpdateLabel => 'Update frequency';

  @override
  String get dashboardHeroMetricUpdateValue => 'Realtime';

  @override
  String get dashboardQuickMarketTitle => 'Market';

  @override
  String get dashboardQuickMarketSubtitle =>
      'Indices, highlights, and watchlist';

  @override
  String get dashboardQuickMentorTitle => 'Mentor Center';

  @override
  String get dashboardQuickMentorSubtitle => 'Review profiles before following';

  @override
  String get dashboardQuickRankingTitle => 'Rankings';

  @override
  String get dashboardQuickRankingSubtitle => 'Quickly find Top traders';

  @override
  String get dashboardQuickMessageTitle => 'Messages';

  @override
  String get dashboardQuickMessageSubtitle =>
      'Conversations and system notices';

  @override
  String get dashboardTrust1 => 'Real returns visualized';

  @override
  String get dashboardTrust2 => 'Mentor strategies traceable';

  @override
  String get dashboardTrust3 => 'Clearer ranking entry';

  @override
  String get dashboardTrust4 => 'More direct message reach';

  @override
  String get dashboardMentorFallbackTitle => 'Trading Mentor';

  @override
  String get dashboardMentorTip =>
      'Tap to view mentor profile. Strategy center is for friends only.';

  @override
  String get dashboardNoHotNews => 'No hot news yet';

  @override
  String get teachersStrategyMaxNineImages => 'Up to 9 images per post';

  @override
  String get teachersStrategyExceedNineIgnored =>
      'Extra images were ignored (max 9)';
}

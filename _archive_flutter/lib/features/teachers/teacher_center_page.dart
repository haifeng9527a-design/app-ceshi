import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/components.dart';
import '../trading/fills_and_positions_tab.dart';
import '../trading/account_ledger_tab.dart';
import '../trading/market_trade_tab.dart';
import '../trading/order_history_tab.dart';
import '../trading/orders_tab.dart';
import '../trading/trading_models.dart';
import '../trading/trading_ui.dart';
import 'teacher_models.dart';
import 'teacher_public_page.dart';
import 'teacher_repository.dart';

class TeacherCenterPage extends StatefulWidget {
  const TeacherCenterPage({
    super.key,
    this.initialTeacherStatus,
  });

  final String? initialTeacherStatus;

  @override
  State<TeacherCenterPage> createState() => _TeacherCenterPageState();
}

class _TeacherCenterPageState extends State<TeacherCenterPage>
    with SingleTickerProviderStateMixin {
  final _repository = TeacherRepository();
  TabController? _tabController;
  int _activeTradingTabIndex = 0;
  TradingAccountType _selectedTradingAccountType = TradingAccountType.spot;
  final Set<int> _loadedTradingTabs = <int>{0};
  final _realNameController = TextEditingController();
  final _titleController = TextEditingController();
  final _orgController = TextEditingController();
  final _countryController = TextEditingController();
  final _cityController = TextEditingController();
  final _yearsController = TextEditingController();
  final _marketsController = TextEditingController();
  final _instrumentsController = TextEditingController();
  final _certificationsController = TextEditingController();
  final _licenseController = TextEditingController();
  final _brokerController = TextEditingController();
  final _trackRecordController = TextEditingController();
  final _bioController = TextEditingController();
  final _styleController = TextEditingController();
  final _riskController = TextEditingController();
  final _specialtiesController = TextEditingController();
  bool _saving = false;
  bool _applicationAck = false;
  bool _profileLoaded = false;
  bool? _configuredApprovedState;
  String? _countryValue;
  int? _yearsValue;
  String? _idPhotoUrl;
  String? _licensePhotoUrl;
  String? _certificationPhotoUrl;

  String _statusLabel = '';
  DateTime? _frozenUntil;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _statusLabel = widget.initialTeacherStatus?.trim().toLowerCase() ?? '';
    _configureTabsForCurrentStatus();
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTradingTabChanged);
    _tabController?.dispose();
    _realNameController.dispose();
    _titleController.dispose();
    _orgController.dispose();
    _countryController.dispose();
    _cityController.dispose();
    _yearsController.dispose();
    _marketsController.dispose();
    _instrumentsController.dispose();
    _certificationsController.dispose();
    _licenseController.dispose();
    _brokerController.dispose();
    _trackRecordController.dispose();
    _bioController.dispose();
    _styleController.dispose();
    _riskController.dispose();
    _specialtiesController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) {
      return;
    }
    final profile = await _repository.fetchProfile(userId);
    if (!mounted || profile == null) {
      return;
    }
    _realNameController.text = profile.realName ?? '';
    _titleController.text = profile.title ?? '';
    _orgController.text = profile.organization ?? '';
    _countryController.text = profile.country ?? '';
    _countryValue = (profile.country ?? '').isEmpty ? null : profile.country;
    _cityController.text = profile.city ?? '';
    _yearsController.text = profile.yearsExperience?.toString() ?? '';
    _yearsValue = profile.yearsExperience;
    _marketsController.text = profile.markets ?? '';
    _instrumentsController.text = profile.instruments ?? '';
    _certificationsController.text = profile.certifications ?? '';
    _licenseController.text = profile.licenseNo ?? '';
    _brokerController.text = profile.broker ?? '';
    _trackRecordController.text = profile.trackRecord ?? '';
    _idPhotoUrl = profile.idPhotoUrl;
    _licensePhotoUrl = profile.licensePhotoUrl;
    _certificationPhotoUrl = profile.certificationPhotoUrl;
    _bioController.text = profile.bio ?? '';
    _styleController.text = profile.style ?? '';
    _riskController.text = profile.riskLevel ?? '';
    _specialtiesController.text = (profile.specialties ?? []).join(',');
    _statusLabel = profile.status ?? 'pending';
    _frozenUntil = profile.frozenUntil;
    _applicationAck = profile.applicationAck ?? false;
    _profileLoaded = true;
    _configureTabsForCurrentStatus();
    if (mounted) {
      setState(() {});
    }
  }

  void _configureTabsForCurrentStatus() {
    final approved = _statusLabel.toString().trim().toLowerCase() == 'approved';
    final alreadyConfigured =
        _configuredApprovedState == approved &&
        ((approved && _tabController != null) || (!approved && _tabController == null));
    if (alreadyConfigured) {
      return;
    }
    _tabController?.removeListener(_handleTradingTabChanged);
    _tabController?.dispose();
    if (approved) {
      _tabController = TabController(length: 5, vsync: this);
      _activeTradingTabIndex = 0;
      _selectedTradingAccountType = TradingAccountType.spot;
      _loadedTradingTabs
        ..clear()
        ..add(0);
      _tabController!.addListener(_handleTradingTabChanged);
    } else {
      _tabController = null;
    }
    _configuredApprovedState = approved;
  }

  void _handleTradingTabChanged() {
    final controller = _tabController;
    if (controller == null) return;
    final nextIndex = controller.index;
    if (_activeTradingTabIndex == nextIndex &&
        _loadedTradingTabs.contains(nextIndex)) {
      return;
    }
    setState(() {
      _activeTradingTabIndex = nextIndex;
      _loadedTradingTabs.add(nextIndex);
    });
  }

  Widget _buildTradingAccountSwitcher() {
    final l10n = AppLocalizations.of(context)!;
    Widget chip(TradingAccountType type, String label) {
      final selected = _selectedTradingAccountType == type;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          if (_selectedTradingAccountType == type) return;
          setState(() => _selectedTradingAccountType = type);
        },
        labelStyle: TextStyle(
          color: selected ? TradingUi.pageBg : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        selectedColor: TradingUi.accent,
        backgroundColor: TradingUi.surface,
        side: BorderSide(
          color: selected ? TradingUi.accent : TradingUi.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        showCheckmark: false,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: TradingUi.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.teachersTradingAccount,
                style: const TextStyle(
                  color: TradingUi.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(TradingAccountType.spot, l10n.teachersSpotAccount),
              chip(TradingAccountType.contract, l10n.teachersContractAccount),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradingTabChild(int index, String userId) {
    if (!_loadedTradingTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case 0:
        return MarketTradeTab(
          teacherId: userId,
          isActive: _activeTradingTabIndex == 0,
        );
      case 1:
        return OrdersTab(
          teacherId: userId,
          accountType: _selectedTradingAccountType,
          isActive: _activeTradingTabIndex == 1,
        );
      case 2:
        return OrderHistoryTab(
          teacherId: userId,
          accountType: _selectedTradingAccountType,
          isActive: _activeTradingTabIndex == 2,
        );
      case 3:
        return FillsAndPositionsTab(
          teacherId: userId,
          accountType: _selectedTradingAccountType,
          isActive: _activeTradingTabIndex == 3,
        );
      case 4:
        return AccountLedgerTab(
          teacherId: userId,
          accountType: _selectedTradingAccountType,
          isActive: _activeTradingTabIndex == 4,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _saveProfile() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) {
      return;
    }
    if (!_applicationAck) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.teachersConfirmRiskAck)),
      );
      return;
    }
    setState(() => _saving = true);
    final specialties = _specialtiesController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final years = int.tryParse(_yearsController.text.trim());
    final avatarUrl = FirebaseAuth.instance.currentUser?.photoURL;
    final profile = TeacherProfile(
      userId: userId,
      avatarUrl: avatarUrl?.trim().isEmpty == true ? null : avatarUrl,
      realName: _realNameController.text.trim(),
      title: _titleController.text.trim(),
      organization: _orgController.text.trim(),
      country: _countryValue ?? _countryController.text.trim(),
      city: _cityController.text.trim(),
      yearsExperience: _yearsValue ?? years,
      markets: _marketsController.text.trim(),
      instruments: _instrumentsController.text.trim(),
      certifications: _certificationsController.text.trim(),
      licenseNo: _licenseController.text.trim(),
      broker: _brokerController.text.trim(),
      trackRecord: _trackRecordController.text.trim(),
      applicationAck: _applicationAck,
      idPhotoUrl: _idPhotoUrl,
      licensePhotoUrl: _licensePhotoUrl,
      certificationPhotoUrl: _certificationPhotoUrl,
      bio: _bioController.text.trim(),
      style: _styleController.text.trim(),
      riskLevel: _riskController.text.trim(),
      specialties: specialties.isEmpty ? null : specialties,
      status: 'pending',
    );
    try {
      await _repository.upsertProfile(profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.teachersProfileSubmitted)),
      );
      await _loadProfile();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.teachersSaveFailed}：$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickVerificationPhoto({
    required String category,
    required void Function(String url) onUploaded,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) {
      return;
    }
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      return;
    }
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name;
      final contentType = _guessImageContentType(name);
      final url = await _repository.uploadTeacherVerification(
        teacherId: userId,
        fileName: name,
        bytes: bytes,
        contentType: contentType,
        category: category,
      );
      if (!mounted) return;
      onUploaded(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.teachersPhotoUploaded)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.teachersUploadFailed}：$error')),
      );
    }
  }

  static const Color _accent = AppColors.primary;
  static const Color _muted = AppColors.textTertiary;

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_sectionTitle(title), ...children],
        ),
      ),
    );
  }

  Widget _buildVerifyThumb(String? url, String label) {
    if (url == null || url.trim().isEmpty) {
      return Container(
        height: 56,
        width: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        height: 56,
        width: 56,
        fit: BoxFit.cover,
      ),
    );
  }

  bool get _isApproved => _statusLabel == 'approved';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final l10n = AppLocalizations.of(context)!;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.teachersTeacherCenter)),
        body: Center(child: Text(l10n.teachersPleaseLoginFirst)),
      );
    }
    return Scaffold(
      backgroundColor: TradingUi.pageBg,
      appBar: AppBar(
        title: Text(l10n.teachersTeacherCenter),
        backgroundColor: TradingUi.pageBg,
        bottom: (_isApproved && _tabController != null)
            ? TabBar(
                controller: _tabController!,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorColor: TradingUi.accent,
                indicatorWeight: 3,
                labelColor: TradingUi.accent,
                unselectedLabelColor: TradingUi.textMuted,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                tabs: [
                  Tab(text: l10n.teachersQuoteAndTradeTab),
                  Tab(text: l10n.teachersOrderTab),
                  Tab(text: l10n.teachersHistoryOrderTab),
                  Tab(text: l10n.teachersFillsAndPositionsTab),
                  Tab(text: l10n.teachersAccountAndLedgerTab),
                ],
              )
            : null,
      ),
      body: !_profileLoaded && !_isApproved
          ? const Center(
              child: CircularProgressIndicator(color: TradingUi.accent),
            )
          : (_isApproved && _tabController != null)
              ? Container(
                  decoration: const BoxDecoration(
                    color: TradingUi.pageBg,
                  ),
                  child: Column(
                    children: [
                      if (_activeTradingTabIndex >= 1)
                        _buildTradingAccountSwitcher(),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController!,
                          children: [
                            for (var i = 0; i < 5; i++)
                              _buildTradingTabChild(i, user.uid),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : _buildProfileTab(),
    );
  }

  Widget _buildProfileTab() {
    final user = FirebaseAuth.instance.currentUser;
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_isApproved) _buildStatusBanner(),
        _sectionCard(l10n.teachersBasicInfo, [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _accent,
                backgroundImage: user?.photoURL?.trim().isNotEmpty == true
                    ? NetworkImage(user!.photoURL!.trim())
                    : null,
                child: user?.photoURL?.trim().isNotEmpty == true
                    ? null
                    : const Icon(Icons.person, color: AppColors.surface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName?.trim().isNotEmpty == true
                          ? user!.displayName!.trim()
                          : l10n.teachersNoNicknameSet,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.teachersAvatarNicknameHint,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _realNameController,
            decoration: InputDecoration(labelText: l10n.teachersRealNameRequired),
          ),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(labelText: l10n.teachersProfessionalTitle),
          ),
          TextField(
            controller: _orgController,
            decoration: InputDecoration(labelText: l10n.teachersOrgCompany),
          ),
          DropdownButtonFormField<String>(
            initialValue: _countryValue,
            decoration: InputDecoration(labelText: l10n.teachersCountryRegion),
            items: l10n.teachersCountryOptions.split(', ').map((item) => DropdownMenuItem(value: item.trim(), child: Text(item.trim()))).toList(),
            onChanged: (value) => setState(() => _countryValue = value),
          ),
          TextField(
            controller: _cityController,
            decoration: InputDecoration(labelText: l10n.teachersCityLabel),
          ),
          DropdownButtonFormField<int>(
            initialValue: _yearsValue,
            decoration: InputDecoration(labelText: l10n.teachersYearsExperience),
            items: List.generate(21, (index) => index)
                .where((item) => item > 0)
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(item == 20 ? l10n.teachersYearsAbove20 : l10n.teachersYearsFormat(item)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _yearsValue = value),
          ),
        ]),
        _sectionCard(l10n.teachersTradingBackground, [
          TextField(
            controller: _marketsController,
            decoration: InputDecoration(
              labelText: l10n.teachersMainMarketLabel,
            ),
          ),
          TextField(
            controller: _instrumentsController,
            decoration: InputDecoration(
              labelText: l10n.teachersMainVariety,
            ),
          ),
          TextField(
            controller: _styleController,
            decoration: InputDecoration(labelText: l10n.teachersTradingStyle),
          ),
          TextField(
            controller: _riskController,
            decoration: InputDecoration(labelText: l10n.teachersRiskPreference),
          ),
          TextField(
            controller: _specialtiesController,
            decoration: InputDecoration(
              labelText: l10n.teachersExpertiseVariety,
            ),
          ),
        ]),
        _sectionCard(l10n.teachersQualificationCompliance, [
          TextField(
            controller: _certificationsController,
            decoration: InputDecoration(
              labelText: l10n.teachersQualificationCert,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildVerifyThumb(_certificationPhotoUrl, l10n.teachersQualificationPhoto),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickVerificationPhoto(
                    category: 'certification',
                    onUploaded: (url) {
                      setState(() => _certificationPhotoUrl = url);
                    },
                  ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(AppLocalizations.of(context)!.teachersUploadQualification),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _licenseController,
            decoration: InputDecoration(labelText: l10n.teachersLicenseNoLabel),
          ),
          TextField(
            controller: _brokerController,
            decoration: InputDecoration(labelText: l10n.teachersBrokerLabel),
          ),
        ]),
        _sectionCard(l10n.teachersPerformanceIntro, [
          TextField(
            controller: _trackRecordController,
            decoration: InputDecoration(
              labelText: l10n.teachersPerformanceLabel,
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioController,
            decoration: InputDecoration(labelText: l10n.teachersPersonalIntro),
            maxLines: 3,
          ),
        ]),
        _sectionCard(l10n.teachersIdVerification, [
          Row(
            children: [
              _buildVerifyThumb(_idPhotoUrl, l10n.teachersUploadIdPhoto),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickVerificationPhoto(
                    category: 'id',
                    onUploaded: (url) => setState(() => _idPhotoUrl = url),
                  ),
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(AppLocalizations.of(context)!.teachersUploadIdPhoto),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildVerifyThumb(_licensePhotoUrl, l10n.teachersUploadCertification),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickVerificationPhoto(
                    category: 'license',
                    onUploaded: (url) =>
                        setState(() => _licensePhotoUrl = url),
                  ),
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(AppLocalizations.of(context)!.teachersUploadCertification),
                ),
              ),
            ],
          ),
        ]),
        AppCard(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _applicationAck,
                  onChanged: (value) =>
                      setState(() => _applicationAck = value),
                  title: Text(AppLocalizations.of(context)!.teachersRiskAckTitle),
                ),
                const SizedBox(height: 12),
                AppButton(
                  onPressed: (_saving ||
                          _statusLabel.toString().trim().toLowerCase() ==
                              'pending')
                      ? null
                      : _saveProfile,
                  label: _saving
                      ? l10n.teachersSubmitting
                      : (_statusLabel.toString().trim().toLowerCase() ==
                              'pending'
                          ? l10n.teachersSubmittedPendingReview
                          : l10n.teachersSubmitApplication),
                ),
                const SizedBox(height: 8),
                AppButton(
                  variant: AppButtonVariant.text,
                  label: AppLocalizations.of(context)!.teachersPreviewHomepage,
                  onPressed: () {
                    final userId =
                        FirebaseAuth.instance.currentUser?.uid ?? '';
                    if (userId.isEmpty) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TeacherPublicPage(teacherId: userId),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner() {
    final status = _statusLabel.toString().trim().toLowerCase();
    String message;
    Color color;
    IconData icon;
    if (status == 'frozen') {
      color = AppColors.warning;
      icon = Icons.ac_unit;
      message = AppLocalizations.of(context)!.teachersStatusFrozenMessage;
      if (_frozenUntil != null) {
        final until = _frozenUntil!.toLocal();
        final dateLabel =
            '${until.year}-${until.month.toString().padLeft(2, '0')}-${until.day.toString().padLeft(2, '0')} ${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
        message += AppLocalizations.of(context)!
            .teachersStatusUnfreezeTime(dateLabel);
      }
    } else if (status == 'blocked') {
      color = AppColors.negative;
      icon = Icons.block;
      message = AppLocalizations.of(context)!.teachersStatusBlockedMessage;
    } else if (status == 'rejected') {
      color = AppColors.textTertiary;
      icon = Icons.cancel_outlined;
      message = AppLocalizations.of(context)!.teachersStatusRejectedMessage;
    } else {
      color = _accent;
      icon = Icons.info_outline;
      message = AppLocalizations.of(context)!.teachersStatusPendingMessage;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  String _guessImageContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}

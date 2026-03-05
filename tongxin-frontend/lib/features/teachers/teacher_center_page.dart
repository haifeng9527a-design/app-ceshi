import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/components.dart';
import '../trading/fills_and_positions_tab.dart';
import '../trading/market_trade_tab.dart';
import '../trading/order_history_tab.dart';
import '../trading/orders_tab.dart';
import 'teacher_models.dart';
import 'teacher_public_page.dart';
import 'teacher_repository.dart';

class TeacherCenterPage extends StatefulWidget {
  const TeacherCenterPage({super.key});

  @override
  State<TeacherCenterPage> createState() => _TeacherCenterPageState();
}

class _TeacherCenterPageState extends State<TeacherCenterPage>
    with SingleTickerProviderStateMixin {
  final _repository = TeacherRepository();
  TabController? _tabController;
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
    _loadProfile();
  }

  @override
  void dispose() {
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
    final approved = (_statusLabel.toString().trim().toLowerCase() == 'approved');
    _tabController?.dispose();
    if (approved) {
      _tabController = TabController(length: 5, vsync: this);
    } else {
      _tabController = null;
    }
    if (mounted) {
      setState(() {});
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

  Future<void> _addStrategyDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final List<XFile> dialogImages = [];
    final result = await showDialog<(String title, String content, List<XFile> images)?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1A1C21),
            ),
            colorScheme: const ColorScheme.dark(
              surface: Color(0xFF1A1C21),
              onSurface: Colors.white,
              primary: _accent,
            ),
          ),
          child: AlertDialog(
            title: Text(AppLocalizations.of(dialogContext)!.teachersPublishStrategy, style: const TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setDialogState) {
                  final l10n = AppLocalizations.of(dialogContext)!;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: l10n.teachersTitleLabel,
                          labelStyle: const TextStyle(color: Color(0xFF6C6F77)),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                      TextField(
                        controller: contentController,
                        decoration: InputDecoration(
                          labelText: l10n.teachersStrategyContent,
                          labelStyle: const TextStyle(color: Color(0xFF6C6F77)),
                        ),
                        style: const TextStyle(color: Colors.white),
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            l10n.teachersStrategyImage,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await _imagePicker.pickMultiImage(
                                imageQuality: 85,
                              );
                              if (picked.isNotEmpty) {
                                dialogImages.addAll(picked);
                                setDialogState(() {});
                              }
                            },
                            icon: const Icon(Icons.add_photo_alternate, size: 20, color: _accent),
                            label: Text(l10n.teachersAddImage, style: const TextStyle(color: _accent)),
                          ),
                        ],
                      ),
                      if (dialogImages.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: dialogImages.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final x = dialogImages[index];
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: FutureBuilder<Widget>(
                                        future: _thumbnailForXFile(x),
                                        builder: (_, snap) {
                                          if (snap.hasData) return snap.data!;
                                          return const ColoredBox(
                                            color: Color(0xFF2A2C33),
                                            child: Center(child: Icon(Icons.image, color: _accent)),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.black54,
                                        padding: const EdgeInsets.all(4),
                                        minimumSize: const Size(24, 24),
                                      ),
                                      onPressed: () {
                                        dialogImages.removeAt(index);
                                        setDialogState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: Text(AppLocalizations.of(dialogContext)!.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(AppLocalizations.of(dialogContext)!.teachersFillStrategyTitle)),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop((
                    title,
                    contentController.text.trim(),
                    List<XFile>.from(dialogImages),
                  ));
                },
                child: Text(AppLocalizations.of(dialogContext)!.teachersPublish),
              ),
            ],
          ),
        );
      },
    );
    titleController.dispose();
    contentController.dispose();
    if (result == null) return;
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.teachersPleaseLoginFirst)),
      );
      return;
    }
    try {
      final List<String> imageUrls = [];
      for (final x in result.$3) {
        final bytes = await x.readAsBytes();
        final name = x.name.isNotEmpty ? x.name : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final mime = x.mimeType ?? 'image/jpeg';
        final url = await _repository.uploadStrategyImage(
          teacherId: userId,
          fileName: name,
          bytes: bytes,
          contentType: mime,
        );
        imageUrls.add(url);
      }
      await _repository.addStrategy(
        teacherId: userId,
        title: result.$1,
        summary: '',
        content: result.$2,
        imageUrls: imageUrls,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.teachersStrategyPublished)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.teachersPublishFailed}：$e')),
      );
    }
  }

  Future<Widget> _thumbnailForXFile(XFile x) async {
    final bytes = await x.readAsBytes();
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      width: 72,
      height: 72,
    );
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
      appBar: AppBar(
        title: Text(l10n.teachersTeacherCenter),
        bottom: (_isApproved && _tabController != null)
            ? TabBar(
                controller: _tabController!,
                isScrollable: true,
                tabs: [
                  Tab(text: l10n.teachersStrategyTab),
                  Tab(text: l10n.teachersQuoteAndTradeTab),
                  Tab(text: l10n.teachersOrderTab),
                  Tab(text: l10n.teachersHistoryOrderTab),
                  Tab(text: l10n.teachersFillsAndPositionsTab),
                ],
              )
            : null,
      ),
      body: (_isApproved && _tabController != null)
          ? TabBarView(
              controller: _tabController!,
              children: [
                _buildStrategiesTab(user.uid),
                MarketTradeTab(teacherId: user.uid),
                OrdersTab(teacherId: user.uid),
                OrderHistoryTab(teacherId: user.uid),
                FillsAndPositionsTab(teacherId: user.uid),
              ],
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
              _buildVerifyThumb(_certificationPhotoUrl, '资质照片'),
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
                      ? '提交中…'
                      : (_statusLabel.toString().trim().toLowerCase() ==
                              'pending'
                          ? '已提交等待审核'
                          : '提交申请'),
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
      message = '您当前处于冻结状态，无法发布策略与交易记录。';
      if (_frozenUntil != null) {
        final until = _frozenUntil!.toLocal();
        message += '解冻时间：${until.year}-${until.month.toString().padLeft(2, '0')}-${until.day.toString().padLeft(2, '0')} ${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
      }
    } else if (status == 'blocked') {
      color = AppColors.negative;
      icon = Icons.block;
      message = '您当前处于封禁状态，无法发布策略与交易记录。如有疑问请联系客服。';
    } else if (status == 'rejected') {
      color = AppColors.textTertiary;
      icon = Icons.cancel_outlined;
      message = '您的申请已被拒绝，无法发布策略与交易记录。如有疑问请联系客服。';
    } else {
      color = _accent;
      icon = Icons.info_outline;
      message = '审核中，通过后可发布策略与交易记录';
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

  Widget _buildStrategiesTab(String userId) {
    if (_statusLabel != 'approved') {
      final status = _statusLabel.toString().trim().toLowerCase();
      final hint = (status == 'frozen' || status == 'blocked')
          ? '您当前处于${status == 'frozen' ? '冻结' : '封禁'}状态，无法发布策略'
          : '审核通过后开放策略发布';
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            hint,
            style: const TextStyle(color: AppColors.textTertiary),
          ),
        ],
      );
    }
    return StreamBuilder<List<TeacherStrategy>>(
      stream: _repository.watchStrategies(userId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <TeacherStrategy>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                onPressed: _addStrategyDialog,
                label: AppLocalizations.of(context)!.teachersPublishStrategy,
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                AppLocalizations.of(context)!.teachersNoStrategy,
                style: const TextStyle(color: AppColors.textTertiary),
              )
            else
              ...items.map(
                (item) {
                  final body = (item.content?.trim().isNotEmpty == true
                          ? item.content!
                          : item.summary.trim().isNotEmpty
                              ? item.summary
                              : '')
                      .trim();
                  final urls = item.imageUrls ?? const [];
                  return AppCard(
                    child: ListTile(
                      title: Text(item.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (body.isNotEmpty)
                            Text(
                              body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (urls.isNotEmpty) ...[
                            if (body.isNotEmpty) const SizedBox(height: 6),
                            SizedBox(
                              height: 48,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: urls.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 6),
                                itemBuilder: (_, i) => ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    urls[i],
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Icon(Icons.broken_image_outlined, color: _accent),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      isThreeLine: body.isNotEmpty || urls.isNotEmpty,
                      trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        await _repository.updateStrategyStatus(
                          strategyId: item.id,
                          status: value,
                        );
                      },
                      itemBuilder: (context) {
                        final items = <PopupMenuEntry<String>>[];
                        final l10n = AppLocalizations.of(context)!;
                        if (item.status == 'published') {
                          items.add(
                            PopupMenuItem(
                              value: 'draft',
                              child: Text(l10n.teachersOffline),
                            ),
                          );
                        } else {
                          items.add(
                            PopupMenuItem(
                              value: 'published',
                              child: Text(l10n.teachersOnline),
                            ),
                          );
                        }
                        return items;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(item.status),
                      ),
                    ),
                  ),
                );
                },
              ),
          ],
        );
      },
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

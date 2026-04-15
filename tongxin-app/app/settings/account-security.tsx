import { useCallback, useMemo, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import AppIcon from '../../components/ui/AppIcon';
import { changeEmail, changePassword, checkDeleteAccount, deleteAccount, type DeleteAccountCheckResponse } from '../../services/api/accountApi';
import { useAuthStore } from '../../services/store/authStore';
import { Colors, Sizes } from '../../theme/colors';

function ReasonList({ reasons, title }: { reasons: string[]; title: string }) {
  const { t } = useTranslation();
  const labels = useMemo<Record<string, string>>(
    () => ({
      HAS_WALLET_BALANCE: t('accountSecurity.reasonWalletBalance'),
      HAS_OPEN_POSITIONS: t('accountSecurity.reasonOpenPositions'),
      HAS_PENDING_ORDERS: t('accountSecurity.reasonPendingOrders'),
      OWNS_GROUPS: t('accountSecurity.reasonOwnsGroups'),
      HAS_ACTIVE_COPY_TRADING: t('accountSecurity.reasonCopyTrading'),
      IS_SUPPORT_AGENT: t('accountSecurity.reasonSupportAgent'),
      IS_ADMIN: t('accountSecurity.reasonAdmin'),
    }),
    [t]
  );

  if (!reasons.length) return null;

  return (
    <View style={styles.reasonWrap}>
      <Text style={styles.reasonTitle}>{title}</Text>
      {reasons.map((reason) => (
        <Text key={reason} style={styles.reasonItem}>
          • {labels[reason] || reason}
        </Text>
      ))}
    </View>
  );
}

export default function AccountSecurityScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const { user, syncProfile, signOut } = useAuthStore();
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [newEmail, setNewEmail] = useState('');
  const [emailPassword, setEmailPassword] = useState('');
  const [deletePassword, setDeletePassword] = useState('');
  const [changingPassword, setChangingPassword] = useState(false);
  const [changingEmail, setChangingEmail] = useState(false);
  const [deletingAccount, setDeletingAccount] = useState(false);
  const [deleteCheck, setDeleteCheck] = useState<DeleteAccountCheckResponse | null>(null);
  const [checkingDelete, setCheckingDelete] = useState(false);
  const [passwordSuccess, setPasswordSuccess] = useState(false);
  const [emailSuccess, setEmailSuccess] = useState(false);
  const trimmedEmail = newEmail.trim();
  const passwordTooShort = !!newPassword && newPassword.length < 6;
  const passwordMismatch = !!confirmPassword && confirmPassword !== newPassword;
  const emailLooksInvalid = !!trimmedEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail);
  const canSubmitPassword =
    !!currentPassword &&
    !!newPassword &&
    !!confirmPassword &&
    newPassword.length >= 6 &&
    newPassword === confirmPassword &&
    currentPassword !== newPassword &&
    !changingPassword;
  const canSubmitEmail =
    !!trimmedEmail &&
    !emailLooksInvalid &&
    trimmedEmail !== (user?.email || '') &&
    !!emailPassword &&
    !changingEmail;
  const groupedDeleteReasons = useMemo(() => {
    const assetAndTrading = ['HAS_WALLET_BALANCE', 'HAS_OPEN_POSITIONS', 'HAS_PENDING_ORDERS', 'HAS_ACTIVE_COPY_TRADING'];
    const identityAndPermissions = ['OWNS_GROUPS', 'IS_SUPPORT_AGENT', 'IS_ADMIN'];
    const reasons = deleteCheck?.reasons || [];

    return {
      assetAndTrading: reasons.filter((reason) => assetAndTrading.includes(reason)),
      identityAndPermissions: reasons.filter((reason) => identityAndPermissions.includes(reason)),
    };
  }, [deleteCheck?.reasons]);

  const refreshDeleteCheck = useCallback(async () => {
    setCheckingDelete(true);
    try {
      const data = await checkDeleteAccount();
      setDeleteCheck(data);
    } catch (e: any) {
      Alert.alert(t('accountSecurity.checkFailedTitle'), e?.response?.data?.error || e?.message || t('accountSecurity.checkFailedBody'));
    } finally {
      setCheckingDelete(false);
    }
  }, [t]);

  useFocusEffect(
    useCallback(() => {
      void refreshDeleteCheck();
    }, [refreshDeleteCheck])
  );

  const handlePasswordChange = async () => {
    if (!currentPassword || !newPassword || !confirmPassword) {
      Alert.alert(t('accountSecurity.passwordFailedTitle'), t('accountSecurity.passwordFieldsRequired'));
      return;
    }
    if (newPassword !== confirmPassword) {
      Alert.alert(t('accountSecurity.passwordFailedTitle'), t('accountSecurity.passwordMismatch'));
      return;
    }
    if (currentPassword === newPassword) {
      Alert.alert(t('accountSecurity.passwordFailedTitle'), t('accountSecurity.passwordSameAsCurrent'));
      return;
    }
    setChangingPassword(true);
    try {
      await changePassword(currentPassword, newPassword);
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      setPasswordSuccess(true);
      setEmailSuccess(false);
      Alert.alert(t('accountSecurity.passwordUpdatedTitle'), t('accountSecurity.passwordUpdatedBody'));
    } catch (e: any) {
      Alert.alert(t('accountSecurity.passwordFailedTitle'), e?.response?.data?.error || e?.message || t('accountSecurity.passwordFailedBody'));
    } finally {
      setChangingPassword(false);
    }
  };

  const handleEmailChange = async () => {
    if (!trimmedEmail || !emailPassword) {
      Alert.alert(t('accountSecurity.emailFailedTitle'), t('accountSecurity.emailFieldsRequired'));
      return;
    }
    if (emailLooksInvalid) {
      Alert.alert(t('accountSecurity.emailFailedTitle'), t('accountSecurity.emailInvalid'));
      return;
    }
    if (trimmedEmail === (user?.email || '')) {
      Alert.alert(t('accountSecurity.emailFailedTitle'), t('accountSecurity.emailSameAsCurrent'));
      return;
    }
    setChangingEmail(true);
    try {
      await changeEmail(trimmedEmail, emailPassword);
      await syncProfile();
      setNewEmail('');
      setEmailPassword('');
      setEmailSuccess(true);
      setPasswordSuccess(false);
      Alert.alert(t('accountSecurity.emailUpdatedTitle'), t('accountSecurity.emailUpdatedBody'));
      await refreshDeleteCheck();
    } catch (e: any) {
      Alert.alert(t('accountSecurity.emailFailedTitle'), e?.response?.data?.error || e?.message || t('accountSecurity.emailFailedBody'));
    } finally {
      setChangingEmail(false);
    }
  };

  const handleLogout = () => {
    Alert.alert(t('accountSecurity.logoutTitle'), t('accountSecurity.logoutBody'), [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('auth.logout'),
        style: 'destructive',
        onPress: async () => {
          await signOut();
          router.replace('/' as any);
        },
      },
    ]);
  };

  const handleDeleteAccount = () => {
    if (!deleteCheck?.can_delete) {
      Alert.alert(t('accountSecurity.deleteBlockedTitle'), t('accountSecurity.deleteBlockedBody'));
      return;
    }
    if (!deletePassword) {
      Alert.alert(t('accountSecurity.deleteFailedTitle'), t('accountSecurity.deletePasswordRequired'));
      return;
    }
    Alert.alert(t('accountSecurity.deleteConfirmTitle'), t('accountSecurity.deleteConfirmBody'), [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('accountSecurity.deleteAction'),
        style: 'destructive',
        onPress: async () => {
          setDeletingAccount(true);
          try {
            await deleteAccount(deletePassword);
            setDeletePassword('');
            await signOut();
            Alert.alert(t('accountSecurity.deleteSuccessTitle'), t('accountSecurity.deleteSuccessBody'));
            router.replace('/' as any);
          } catch (e: any) {
            Alert.alert(t('accountSecurity.deleteFailedTitle'), e?.response?.data?.error || e?.message || t('accountSecurity.deleteFailedBody'));
          } finally {
            setDeletingAccount(false);
          }
        },
      },
    ]);
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.backBtn} activeOpacity={0.8} onPress={() => router.back()}>
          <AppIcon name="back" size={18} color={Colors.textSecondary} />
        </TouchableOpacity>
        <View style={styles.headerBody}>
          <Text style={styles.title}>{t('accountSecurity.title')}</Text>
          <Text style={styles.subtitle}>{t('accountSecurity.subtitle')}</Text>
        </View>
      </View>

      <View style={styles.card}>
        <Text style={styles.sectionTitle}>{t('accountSecurity.accountInfo')}</Text>
        <InfoRow label={t('accountSecurity.currentEmail')} value={user?.email || '--'} />
        <InfoRow label={t('accountSecurity.uidLabel')} value={user?.uid || '--'} last />
      </View>

      <View style={styles.card}>
        <Text style={styles.sectionTitle}>{t('accountSecurity.changePassword')}</Text>
        <Field
          label={t('accountSecurity.currentPassword')}
          value={currentPassword}
          onChangeText={setCurrentPassword}
          placeholder={t('accountSecurity.currentPasswordPlaceholder')}
          secureTextEntry
        />
        <Field
          label={t('accountSecurity.newPassword')}
          value={newPassword}
          onChangeText={(text) => {
            setPasswordSuccess(false);
            setNewPassword(text);
          }}
          placeholder={t('accountSecurity.newPasswordPlaceholder')}
          secureTextEntry
        />
        <Field
          label={t('accountSecurity.confirmPassword')}
          value={confirmPassword}
          onChangeText={(text) => {
            setPasswordSuccess(false);
            setConfirmPassword(text);
          }}
          placeholder={t('accountSecurity.confirmPasswordPlaceholder')}
          secureTextEntry
          last
        />
        <Text style={styles.helperText}>{t('accountSecurity.passwordRule')}</Text>
        {passwordTooShort ? <Text style={styles.errorText}>{t('accountSecurity.passwordTooShort')}</Text> : null}
        {passwordMismatch ? <Text style={styles.errorText}>{t('accountSecurity.passwordMismatch')}</Text> : null}
        {passwordSuccess ? (
          <View style={styles.successBanner}>
            <AppIcon name="shield" size={14} color={Colors.up} />
            <Text style={styles.successBannerText}>{t('accountSecurity.passwordUpdatedBody')}</Text>
          </View>
        ) : null}
        <TouchableOpacity style={[styles.primaryBtn, !canSubmitPassword && styles.disabledPrimaryBtn]} onPress={() => void handlePasswordChange()} disabled={!canSubmitPassword} activeOpacity={0.85}>
          <Text style={styles.primaryBtnText}>
            {changingPassword ? t('accountSecurity.passwordUpdating') : t('accountSecurity.changePasswordAction')}
          </Text>
        </TouchableOpacity>
      </View>

      <View style={styles.card}>
        <Text style={styles.sectionTitle}>{t('accountSecurity.changeEmail')}</Text>
        <Field label={t('accountSecurity.currentEmail')} value={user?.email || ''} editable={false} />
        <Field
          label={t('accountSecurity.newEmail')}
          value={newEmail}
          onChangeText={(text) => {
            setEmailSuccess(false);
            setNewEmail(text);
          }}
          placeholder={t('accountSecurity.newEmailPlaceholder')}
          keyboardType="email-address"
          autoCapitalize="none"
        />
        <Field
          label={t('accountSecurity.currentPassword')}
          value={emailPassword}
          onChangeText={setEmailPassword}
          placeholder={t('accountSecurity.emailPasswordPlaceholder')}
          secureTextEntry
          last
        />
        <Text style={styles.helperText}>{t('accountSecurity.emailHint')}</Text>
        {emailLooksInvalid ? <Text style={styles.errorText}>{t('accountSecurity.emailInvalid')}</Text> : null}
        {emailSuccess ? (
          <View style={styles.successBanner}>
            <AppIcon name="shield" size={14} color={Colors.up} />
            <Text style={styles.successBannerText}>{t('accountSecurity.emailUpdatedBody')}</Text>
          </View>
        ) : null}
        <TouchableOpacity style={[styles.primaryBtn, !canSubmitEmail && styles.disabledPrimaryBtn]} onPress={() => void handleEmailChange()} disabled={!canSubmitEmail} activeOpacity={0.85}>
          <Text style={styles.primaryBtnText}>
            {changingEmail ? t('accountSecurity.emailUpdating') : t('accountSecurity.changeEmailAction')}
          </Text>
        </TouchableOpacity>
      </View>

      <View style={styles.card}>
        <View style={styles.sectionHeaderRow}>
          <Text style={styles.sectionTitle}>{t('accountSecurity.deleteAccount')}</Text>
          <TouchableOpacity onPress={() => void refreshDeleteCheck()} disabled={checkingDelete} activeOpacity={0.8}>
            <Text style={styles.linkText}>{checkingDelete ? t('common.loading') : t('accountSecurity.refreshCheck')}</Text>
          </TouchableOpacity>
        </View>
        <Text style={styles.dangerHint}>{t('accountSecurity.deleteWarning')}</Text>
        {checkingDelete ? <Text style={styles.helperText}>{t('accountSecurity.checkingDelete')}</Text> : null}
        <View style={styles.statusPillRow}>
          <View style={[styles.statusPill, deleteCheck?.can_delete ? styles.statusPillOk : styles.statusPillWarn]}>
            <AppIcon
              name={deleteCheck?.can_delete ? 'shield' : 'trash'}
              size={14}
              color={deleteCheck?.can_delete ? Colors.up : Colors.down}
            />
            <Text style={[styles.statusPillText, deleteCheck?.can_delete ? styles.statusPillTextOk : styles.statusPillTextWarn]}>
              {deleteCheck?.can_delete ? t('accountSecurity.canDelete') : t('accountSecurity.cannotDelete')}
            </Text>
          </View>
        </View>
        {!deleteCheck?.can_delete ? <Text style={styles.reasonSummary}>{t('accountSecurity.deleteBlockedReasonTitle')}</Text> : null}
        <ReasonList reasons={groupedDeleteReasons.assetAndTrading} title={t('accountSecurity.assetRestrictionTitle')} />
        <ReasonList reasons={groupedDeleteReasons.identityAndPermissions} title={t('accountSecurity.identityRestrictionTitle')} />
        <Field
          label={t('accountSecurity.currentPassword')}
          value={deletePassword}
          onChangeText={setDeletePassword}
          placeholder={t('accountSecurity.deletePasswordPlaceholder')}
          secureTextEntry
          editable={!!deleteCheck?.can_delete}
          last
        />
        {!deleteCheck?.can_delete ? (
          <Text style={styles.helperText}>{t('accountSecurity.deletePasswordLocked')}</Text>
        ) : null}
        <TouchableOpacity
          style={[styles.secondaryBtn, styles.logoutBtn]}
          onPress={handleLogout}
          activeOpacity={0.85}
        >
          <AppIcon name="logout" size={16} color={Colors.down} />
          <Text style={styles.logoutBtnText}>{t('auth.logout')}</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.secondaryBtn, styles.deleteBtn, (!deleteCheck?.can_delete || deletingAccount) && styles.disabledBtn]}
          onPress={handleDeleteAccount}
          activeOpacity={0.85}
          disabled={!deleteCheck?.can_delete || deletingAccount}
        >
          <AppIcon name="trash" size={16} color={Colors.down} />
          <Text style={styles.deleteBtnText}>
            {deletingAccount ? t('accountSecurity.deletingAccount') : t('accountSecurity.deleteAction')}
          </Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
}

function InfoRow({ label, value, last = false }: { label: string; value: string; last?: boolean }) {
  return (
    <View style={[styles.infoRow, !last && styles.rowBorder]}>
      <Text style={styles.infoLabel}>{label}</Text>
      <Text style={styles.infoValue}>{value}</Text>
    </View>
  );
}

function Field({
  label,
  value,
  onChangeText,
  placeholder,
  secureTextEntry,
  editable = true,
  keyboardType,
  autoCapitalize,
  last = false,
}: {
  label: string;
  value: string;
  onChangeText?: (text: string) => void;
  placeholder?: string;
  secureTextEntry?: boolean;
  editable?: boolean;
  keyboardType?: 'default' | 'email-address';
  autoCapitalize?: 'none' | 'sentences';
  last?: boolean;
}) {
  return (
    <View style={[styles.fieldWrap, !last && styles.fieldGap]}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={Colors.textMuted}
        secureTextEntry={secureTextEntry}
        editable={editable}
        keyboardType={keyboardType}
        autoCapitalize={autoCapitalize}
        style={[styles.input, !editable && styles.inputDisabled]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  content: {
    padding: 20,
    gap: 18,
    paddingBottom: 40,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  backBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerBody: {
    flex: 1,
  },
  title: {
    color: Colors.textActive,
    fontSize: 20,
    fontWeight: '800',
  },
  subtitle: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 2,
  },
  card: {
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 18,
    gap: 14,
  },
  sectionTitle: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  sectionHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  linkText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
    paddingVertical: 10,
  },
  rowBorder: {
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  infoLabel: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  infoValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
    flexShrink: 1,
    textAlign: 'right',
  },
  fieldWrap: {
    gap: 8,
  },
  fieldGap: {
    marginBottom: 2,
  },
  fieldLabel: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  input: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 14,
    paddingVertical: 13,
    color: Colors.textActive,
    fontSize: 14,
  },
  inputDisabled: {
    opacity: 0.7,
  },
  primaryBtn: {
    backgroundColor: Colors.primary,
    borderRadius: Sizes.borderRadiusSm,
    paddingVertical: 14,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 4,
  },
  primaryBtnText: {
    color: Colors.background,
    fontSize: 14,
    fontWeight: '800',
  },
  disabledPrimaryBtn: {
    opacity: 0.45,
  },
  helperText: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
  },
  errorText: {
    color: Colors.down,
    fontSize: 12,
    lineHeight: 18,
    fontWeight: '700',
  },
  successBanner: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 8,
    backgroundColor: 'rgba(46, 184, 114, 0.12)',
    borderWidth: 1,
    borderColor: 'rgba(46, 184, 114, 0.24)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  successBannerText: {
    flex: 1,
    color: Colors.up,
    fontSize: 12,
    lineHeight: 18,
    fontWeight: '700',
  },
  dangerHint: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
  },
  statusPillRow: {
    flexDirection: 'row',
  },
  statusPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
  },
  statusPillOk: {
    backgroundColor: 'rgba(46, 184, 114, 0.12)',
    borderColor: 'rgba(46, 184, 114, 0.28)',
  },
  statusPillWarn: {
    backgroundColor: 'rgba(224, 92, 67, 0.12)',
    borderColor: 'rgba(224, 92, 67, 0.28)',
  },
  statusPillText: {
    fontSize: 12,
    fontWeight: '700',
  },
  statusPillTextOk: {
    color: Colors.up,
  },
  statusPillTextWarn: {
    color: Colors.down,
  },
  reasonWrap: {
    gap: 8,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
  },
  reasonSummary: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
  },
  reasonTitle: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
  },
  reasonItem: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
  },
  secondaryBtn: {
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    paddingVertical: 13,
    paddingHorizontal: 14,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  logoutBtn: {
    borderColor: 'rgba(224, 92, 67, 0.25)',
    backgroundColor: 'rgba(224, 92, 67, 0.08)',
  },
  logoutBtnText: {
    color: Colors.down,
    fontSize: 13,
    fontWeight: '800',
  },
  deleteBtn: {
    borderColor: 'rgba(224, 92, 67, 0.35)',
    backgroundColor: 'rgba(224, 92, 67, 0.14)',
  },
  deleteBtnText: {
    color: Colors.down,
    fontSize: 13,
    fontWeight: '800',
  },
  disabledBtn: {
    opacity: 0.45,
  },
});

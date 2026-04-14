import { useState, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  ActivityIndicator,
  useWindowDimensions,
  ImageBackground,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import AppIcon from '../../components/ui/AppIcon';

type AuthMode = 'login' | 'register';

export default function LoginScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { width: screenWidth } = useWindowDimensions();
  const isDesktop = screenWidth >= 1024;
  const {
    user,
    signInWithEmail,
    registerWithEmail,
    signInWithGoogle,
    signInWithApple,
    loading,
    error,
    clearError,
  } = useAuthStore();

  // Redirect to main app after successful login
  useEffect(() => {
    if (user) {
      router.replace('/(tabs)/market');
    }
  }, [user]);

  const [mode, setMode] = useState<AuthMode>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [localError, setLocalError] = useState('');

  const switchMode = useCallback((m: AuthMode) => {
    setMode(m);
    setLocalError('');
    clearError();
  }, []);

  const handleSubmit = useCallback(async () => {
    setLocalError('');
    clearError();

    if (!email.trim()) {
      setLocalError(t('auth.emailHint'));
      return;
    }
    if (!password || password.length < 6) {
      setLocalError(t('auth.passwordTooShort'));
      return;
    }

    if (mode === 'register') {
      if (!displayName.trim()) {
        setLocalError('Please enter a display name');
        return;
      }
      if (password !== confirmPassword) {
        setLocalError('Passwords do not match');
        return;
      }
      await registerWithEmail(email.trim(), password, displayName.trim());
    } else {
      await signInWithEmail(email.trim(), password);
    }
  }, [mode, email, password, confirmPassword, displayName]);

  const displayError = localError || error;

  return (
    <View style={styles.root}>
      {/* ── Top Nav Bar ── */}
      <View style={styles.topNav}>
        <Text style={styles.topNavTitle}>The Sovereign Exchange</Text>
        <AppIcon name="lock" size={16} color={Colors.primary} />
      </View>

      <View style={styles.mainContainer}>
        {/* ── Left Panel (desktop only) ── */}
        {isDesktop && (
          <ImageBackground
            source={require('../../assets/images/vault-bg.jpg')}
            style={styles.leftPanel}
            resizeMode="cover"
            imageStyle={{ opacity: 0.3 }}
          >
            {/* Simulate bottom-to-top gradient with stacked layers */}
            <View style={styles.gradLayer1} />
            <View style={styles.gradLayer2} />
            <View style={styles.gradLayer3} />
            <View style={styles.gradLayer4} />
            {/* Left side subtle darkening */}
            <View style={styles.leftEdgeFade} />
            {/* Gold ambient glow */}
            <View style={styles.goldGlow} />
            <View style={styles.leftContent}>
              {/* Icon */}
              <View style={styles.leftIconWrap}>
                <AppIcon name="building" size={28} color={Colors.primary} />
              </View>

              {/* Headline */}
              <Text style={styles.leftHeadline}>
                身份验证：解锁全球机构级投研体系与交易策略
              </Text>

              {/* Stats Grid */}
              <View style={styles.statsGrid}>
                <View style={styles.statsCard}>
                  <Text style={styles.statsTitle}>实时同步</Text>
                  <Text style={styles.statsDesc}>全链路行情与跟单指令毫秒级触达</Text>
                </View>
                <View style={styles.statsCard}>
                  <Text style={styles.statsTitle}>生态互通</Text>
                  <Text style={styles.statsDesc}>多终端账户体系深度集成，资产管理行云流水</Text>
                </View>
              </View>

              {/* Info Box */}
              <View style={styles.infoBox}>
                <Text style={styles.infoText}>
                  支持企业级安全认证：邮箱验证、Google 身份鉴权及浏览器端即时风险预警
                </Text>
              </View>
            </View>
          </ImageBackground>
        )}

        {/* ── Right Panel: Auth Card ── */}
        <KeyboardAvoidingView
          style={styles.rightPanel}
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        >
          <ScrollView
            contentContainerStyle={styles.rightScrollContent}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            <View style={[styles.authCard, isDesktop && styles.authCardDesktop]}>
              {/* ── Toggle: Login / Register ── */}
              <View style={styles.toggleWrap}>
                <TouchableOpacity
                  style={[styles.toggleBtn, mode === 'login' && styles.toggleBtnActive]}
                  onPress={() => switchMode('login')}
                >
                  <Text style={[styles.toggleText, mode === 'login' && styles.toggleTextActive]}>
                    {t('auth.login')}
                  </Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={[styles.toggleBtn, mode === 'register' && styles.toggleBtnActive]}
                  onPress={() => switchMode('register')}
                >
                  <Text style={[styles.toggleText, mode === 'register' && styles.toggleTextActive]}>
                    {t('auth.register')}
                  </Text>
                </TouchableOpacity>
              </View>

              {/* ── Header ── */}
              <View style={styles.headerRow}>
                <View style={styles.headerIcon}>
                  <AppIcon
                    name={mode === 'login' ? 'lock' : 'sparkles'}
                    size={22}
                    color={Colors.primary}
                  />
                </View>
                <View>
                  <Text style={styles.headerTitle}>
                    {mode === 'login' ? t('auth.loginTitle') : t('auth.registerTitle')}
                  </Text>
                  <Text style={styles.headerSub}>{t('auth.loginHint')}</Text>
                </View>
              </View>

              {/* ── Form ── */}
              <View style={styles.formArea}>
                {/* Display Name (register only) */}
                {mode === 'register' && (
                  <View style={styles.fieldGroup}>
                    <Text style={styles.fieldLabel}>DISPLAY NAME</Text>
                    <View style={styles.inputWrap}>
                      <AppIcon name="user" size={16} color={Colors.textMuted} />
                      <TextInput
                        style={styles.input}
                        placeholder={t('auth.displayNameHint')}
                        placeholderTextColor="rgba(107,107,128,0.6)"
                        value={displayName}
                        onChangeText={setDisplayName}
                        autoCapitalize="words"
                      />
                    </View>
                  </View>
                )}

                {/* Email */}
                <View style={styles.fieldGroup}>
                  <Text style={styles.fieldLabel}>EMAIL</Text>
                  <View style={styles.inputWrap}>
                    <AppIcon name="mail" size={16} color={Colors.textMuted} />
                    <TextInput
                      style={styles.input}
                      placeholder={t('auth.emailHint')}
                      placeholderTextColor="rgba(107,107,128,0.6)"
                      value={email}
                      onChangeText={setEmail}
                      keyboardType="email-address"
                      autoCapitalize="none"
                      autoCorrect={false}
                    />
                  </View>
                </View>

                {/* Password */}
                <View style={styles.fieldGroup}>
                  <Text style={styles.fieldLabel}>PASSWORD</Text>
                  <View style={styles.inputWrap}>
                    <AppIcon name="lock" size={16} color={Colors.textMuted} />
                    <TextInput
                      style={styles.input}
                      placeholder={t('auth.passwordHint')}
                      placeholderTextColor="rgba(107,107,128,0.6)"
                      value={password}
                      onChangeText={setPassword}
                      secureTextEntry={!showPassword}
                    />
                    <TouchableOpacity
                      onPress={() => setShowPassword(!showPassword)}
                      hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
                    >
                      <AppIcon name="visibility" size={16} color={Colors.textMuted} />
                    </TouchableOpacity>
                  </View>
                </View>

                {/* Confirm Password (register only) */}
                {mode === 'register' && (
                  <View style={styles.fieldGroup}>
                    <Text style={styles.fieldLabel}>CONFIRM PASSWORD</Text>
                    <View style={styles.inputWrap}>
                      <AppIcon name="lock" size={16} color={Colors.textMuted} />
                      <TextInput
                        style={styles.input}
                        placeholder={t('auth.confirmPasswordHint')}
                        placeholderTextColor="rgba(107,107,128,0.6)"
                        value={confirmPassword}
                        onChangeText={setConfirmPassword}
                        secureTextEntry
                      />
                    </View>
                  </View>
                )}

                {/* Error Message */}
                {displayError ? (
                  <View style={[styles.msgBox, styles.msgError]}>
                    <Text style={[styles.msgText, styles.msgErrorText]}>
                      {displayError}
                    </Text>
                  </View>
                ) : null}

                {/* Submit Button */}
                <TouchableOpacity
                  style={[styles.submitBtn, loading && styles.submitBtnDisabled]}
                  onPress={handleSubmit}
                  disabled={loading}
                  activeOpacity={0.85}
                >
                  {loading ? (
                    <ActivityIndicator color={Colors.background} size="small" />
                  ) : (
                    <Text style={styles.submitBtnText}>
                      {mode === 'login' ? t('auth.login') : t('auth.registerTitle')}
                    </Text>
                  )}
                </TouchableOpacity>
              </View>

              {/* ── Divider ── */}
              <View style={styles.divider}>
                <View style={styles.dividerLine} />
                <Text style={styles.dividerText}>{t('auth.thirdPartyLogin')}</Text>
                <View style={styles.dividerLine} />
              </View>

              {/* ── Social Login ── */}
              <TouchableOpacity
                style={styles.googleBtn}
                onPress={signInWithGoogle}
                disabled={loading}
                activeOpacity={0.7}
              >
                <Text style={styles.googleIcon}>G</Text>
                <Text style={styles.googleText}>{t('auth.googleLogin')}</Text>
              </TouchableOpacity>

              {(Platform.OS === 'ios' || Platform.OS === 'web') && (
                <TouchableOpacity
                  style={[styles.googleBtn, { marginTop: 10 }]}
                  onPress={signInWithApple}
                  disabled={loading}
                  activeOpacity={0.7}
                >
                  <Text style={styles.googleIcon}>{'\uF8FF'}</Text>
                  <Text style={styles.googleText}>{t('auth.appleLogin')}</Text>
                </TouchableOpacity>
              )}

              {/* ── Footer Disclaimer ── */}
              <View style={styles.disclaimer}>
                <Text style={styles.disclaimerText}>
                  系统检测：当前环境支持安全指纹及 Google 密钥验证。
                </Text>
                <Text style={styles.disclaimerText}>
                  合规声明：Apple ID 登录暂限 iOS/WEB 端，请优先使用密保邮箱。
                </Text>
              </View>
            </View>
          </ScrollView>
        </KeyboardAvoidingView>
      </View>

      {/* ── Bottom Footer (desktop) ── */}
      {isDesktop && (
        <View style={styles.footer}>
          <Text style={styles.footerText}>
            © 2024 THE SOVEREIGN EXCHANGE. ALL RIGHTS RESERVED.
          </Text>
          <View style={styles.footerLinks}>
            <Text style={styles.footerLink}>PRIVACY</Text>
            <Text style={styles.footerLink}>SECURITY</Text>
            <Text style={styles.footerLink}>INSTITUTIONAL TERMS</Text>
          </View>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: Colors.background,
  },

  // ── Top Nav ──
  topNav: {
    height: 80,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 32,
    backgroundColor: 'rgba(19,19,19,0.6)',
    borderBottomWidth: 0,
    zIndex: 50,
  },
  topNavTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#e5e2e1',
    letterSpacing: -0.3,
  },
  topNavIcon: {
    fontSize: 20,
    color: Colors.primaryLight,
  },

  // ── Main Container ──
  mainContainer: {
    flex: 1,
    flexDirection: 'row',
  },

  // ── Left Panel ──
  leftPanel: {
    flex: 1.2,
    position: 'relative',
    justifyContent: 'center',
    paddingHorizontal: 64,
    paddingVertical: 40,
    overflow: 'hidden',
  },
  // Bottom gradient: 4 stacked layers simulating fade from transparent → solid
  gradLayer1: {
    position: 'absolute',
    left: 0, right: 0, bottom: 0,
    height: '70%',
    backgroundColor: Colors.background,
    opacity: 0.15,
  },
  gradLayer2: {
    position: 'absolute',
    left: 0, right: 0, bottom: 0,
    height: '50%',
    backgroundColor: Colors.background,
    opacity: 0.25,
  },
  gradLayer3: {
    position: 'absolute',
    left: 0, right: 0, bottom: 0,
    height: '30%',
    backgroundColor: Colors.background,
    opacity: 0.4,
  },
  gradLayer4: {
    position: 'absolute',
    left: 0, right: 0, bottom: 0,
    height: '12%',
    backgroundColor: Colors.background,
    opacity: 0.7,
  },
  // Left edge: subtle darkening for text readability
  leftEdgeFade: {
    position: 'absolute',
    left: 0, top: 0, bottom: 0,
    width: '40%',
    backgroundColor: Colors.background,
    opacity: 0.2,
  },
  // Subtle gold ambient light
  goldGlow: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(242, 202, 80, 0.02)',
  },
  leftContent: {
    position: 'relative',
    zIndex: 10,
    maxWidth: 580,
  },
  leftIconWrap: {
    width: 48,
    height: 48,
    borderRadius: 12,
    backgroundColor: 'rgba(242,202,80,0.1)',
    borderWidth: 1,
    borderColor: 'rgba(242,202,80,0.2)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 32,
  },
  leftIconText: {
    fontSize: 24,
  },
  leftHeadline: {
    fontSize: 42,
    fontWeight: '800',
    color: '#e5e2e1',
    lineHeight: 50,
    letterSpacing: -0.5,
    marginBottom: 12,
  },

  // ── Stats Grid ──
  statsGrid: {
    flexDirection: 'row',
    gap: 16,
    marginTop: 40,
  },
  statsCard: {
    flex: 1,
    backgroundColor: 'rgba(28,27,27,0.4)',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    padding: 20,
  },
  statsTitle: {
    color: Colors.primaryLight,
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 6,
  },
  statsDesc: {
    color: '#d0c5af',
    fontSize: 13,
    lineHeight: 18,
  },

  // ── Info Box ──
  infoBox: {
    marginTop: 32,
    padding: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  infoText: {
    color: 'rgba(208,197,175,0.8)',
    fontSize: 13,
    lineHeight: 20,
  },

  // ── Right Panel ──
  rightPanel: {
    flex: 1,
    justifyContent: 'center',
  },
  rightScrollContent: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 24,
    paddingVertical: 40,
  },

  // ── Auth Card ──
  authCard: {
    width: '100%',
    maxWidth: 440,
    alignSelf: 'center',
    backgroundColor: 'rgba(28,27,27,0.4)',
    borderRadius: 24,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    padding: 32,
    ...Shadows.card,
  },
  authCardDesktop: {
    padding: 40,
  },

  // ── Toggle ──
  toggleWrap: {
    flexDirection: 'row',
    padding: 6,
    backgroundColor: 'rgba(14,14,14,0.5)',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    marginBottom: 32,
  },
  toggleBtn: {
    flex: 1,
    paddingVertical: 12,
    alignItems: 'center',
    borderRadius: 12,
  },
  toggleBtnActive: {
    backgroundColor: '#2a2a2a',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
  },
  toggleText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#d0c5af',
  },
  toggleTextActive: {
    color: Colors.primaryLight,
    fontWeight: '700',
  },

  // ── Header ──
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 32,
  },
  headerIcon: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: 'rgba(242,202,80,0.1)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerIconText: {
    fontSize: 20,
  },
  headerTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#e5e2e1',
    letterSpacing: -0.3,
  },
  headerSub: {
    fontSize: 13,
    color: 'rgba(208,197,175,0.8)',
    marginTop: 2,
  },

  // ── Form ──
  formArea: {
    gap: 18,
  },
  fieldGroup: {
    gap: 6,
  },
  fieldLabel: {
    fontSize: 10,
    fontWeight: '600',
    color: 'rgba(208,197,175,0.6)',
    letterSpacing: 1.5,
    marginLeft: 4,
  },
  inputWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(14,14,14,0.3)',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    paddingHorizontal: 14,
  },
  inputIcon: {
    fontSize: 16,
    marginRight: 10,
    opacity: 0.6,
  },
  input: {
    flex: 1,
    paddingVertical: 14,
    color: '#e5e2e1',
    fontSize: 15,
  },
  visibilityIcon: {
    fontSize: 18,
    opacity: 0.6,
    padding: 4,
  },

  // ── Messages ──
  msgBox: {
    borderRadius: 10,
    padding: 14,
  },
  msgError: {
    backgroundColor: 'rgba(255,180,171,0.1)',
    borderWidth: 1,
    borderColor: 'rgba(255,180,171,0.2)',
  },
  msgText: {
    fontSize: 13,
    lineHeight: 18,
  },
  msgErrorText: {
    color: Colors.down,
  },

  // ── Submit Button ──
  submitBtn: {
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
    backgroundColor: Colors.primaryLight,
    ...Shadows.glow,
  },
  submitBtnDisabled: {
    opacity: 0.6,
  },
  submitBtnText: {
    color: Colors.background,
    fontSize: 16,
    fontWeight: '700',
    letterSpacing: 0.5,
  },

  // ── Divider ──
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 28,
  },
  dividerLine: {
    flex: 1,
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  dividerText: {
    color: 'rgba(153,144,124,0.5)',
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 3,
    marginHorizontal: 12,
  },

  // ── Google / Social ──
  googleBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(42,42,42,0.4)',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    paddingVertical: 14,
    gap: 10,
  },
  googleIcon: {
    fontSize: 18,
    fontWeight: '700',
    color: '#e5e2e1',
  },
  googleText: {
    fontSize: 13,
    fontWeight: '600',
    color: '#d0c5af',
  },

  // ── Disclaimer ──
  disclaimer: {
    marginTop: 28,
    gap: 6,
    alignItems: 'center',
  },
  disclaimerText: {
    fontSize: 9,
    color: 'rgba(208,197,175,0.4)',
    textAlign: 'center',
    letterSpacing: 0.3,
    lineHeight: 14,
  },

  // ── Footer ──
  footer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 48,
    paddingVertical: 24,
  },
  footerText: {
    fontSize: 9,
    color: 'rgba(153,144,124,0.4)',
    letterSpacing: 2,
    fontWeight: '500',
  },
  footerLinks: {
    flexDirection: 'row',
    gap: 32,
  },
  footerLink: {
    fontSize: 9,
    color: 'rgba(153,144,124,0.4)',
    letterSpacing: 2,
    fontWeight: '500',
  },
});

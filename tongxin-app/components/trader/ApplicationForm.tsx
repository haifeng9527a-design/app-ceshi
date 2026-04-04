import { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { Colors } from '../../theme/colors';
import { submitApplication, SubmitApplicationRequest } from '../../services/api/traderApi';

const MARKET_OPTIONS = [
  { key: 'crypto', labelKey: 'traderCenter.marketCrypto' },
  { key: 'forex', labelKey: 'traderCenter.marketForex' },
  { key: 'stocks', labelKey: 'traderCenter.marketStocks' },
  { key: 'futures', labelKey: 'traderCenter.marketFutures' },
  { key: 'options', labelKey: 'traderCenter.marketOptions' },
];

const CAPITAL_OPTIONS = [
  { key: 'salary', labelKey: 'traderCenter.capitalSalary' },
  { key: 'business', labelKey: 'traderCenter.capitalBusiness' },
  { key: 'investment', labelKey: 'traderCenter.capitalInvestment' },
  { key: 'other', labelKey: 'traderCenter.capitalOther' },
];

const VOLUME_OPTIONS = [
  { key: '<100k', labelKey: 'traderCenter.volumeSmall' },
  { key: '100k-500k', labelKey: 'traderCenter.volumeMedium' },
  { key: '500k-2m', labelKey: 'traderCenter.volumeLarge' },
  { key: '>2m', labelKey: 'traderCenter.volumeXLarge' },
];

interface Props {
  onSuccess: () => void;
}

export default function ApplicationForm({ onSuccess }: Props) {
  const { t } = useTranslation();
  const [step, setStep] = useState(0);
  const [submitting, setSubmitting] = useState(false);

  // Step 1
  const [realName, setRealName] = useState('');
  const [idNumber, setIdNumber] = useState('');
  const [phone, setPhone] = useState('');
  const [nationality, setNationality] = useState('');
  const [address, setAddress] = useState('');

  // Step 2
  const [experienceYears, setExperienceYears] = useState('');
  const [markets, setMarkets] = useState<string[]>([]);
  const [capitalSource, setCapitalSource] = useState('');
  const [estimatedVolume, setEstimatedVolume] = useState('');

  // Step 3
  const [riskAgreed, setRiskAgreed] = useState(false);
  const [termsAgreed, setTermsAgreed] = useState(false);

  const toggleMarket = (key: string) => {
    setMarkets((prev) =>
      prev.includes(key) ? prev.filter((m) => m !== key) : [...prev, key]
    );
  };

  const canNext = () => {
    if (step === 0) return realName && idNumber && phone;
    if (step === 1) return experienceYears && markets.length > 0 && capitalSource && estimatedVolume;
    if (step === 2) return riskAgreed && termsAgreed;
    return false;
  };

  const handleSubmit = async () => {
    setSubmitting(true);
    try {
      const req: SubmitApplicationRequest = {
        real_name: realName,
        id_number: idNumber,
        phone,
        nationality,
        address,
        experience_years: parseInt(experienceYears) || 0,
        markets,
        capital_source: capitalSource,
        estimated_volume: estimatedVolume,
        risk_agreed: riskAgreed,
        terms_agreed: termsAgreed,
      };
      await submitApplication(req);
      onSuccess();
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.error || e.message);
    } finally {
      setSubmitting(false);
    }
  };

  const steps = [t('traderCenter.step1'), t('traderCenter.step2'), t('traderCenter.step3')];

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      {/* Step indicator */}
      <View style={styles.stepRow}>
        {steps.map((label, i) => (
          <View key={i} style={styles.stepItem}>
            <View style={[styles.stepDot, i <= step && styles.stepDotActive]}>
              <Text style={[styles.stepDotText, i <= step && styles.stepDotTextActive]}>
                {i + 1}
              </Text>
            </View>
            <Text style={[styles.stepLabel, i === step && styles.stepLabelActive]}>
              {label}
            </Text>
          </View>
        ))}
      </View>

      {/* Step 1: Basic Info */}
      {step === 0 && (
        <View style={styles.formSection}>
          <FormInput
            label={t('traderCenter.realName')}
            value={realName}
            onChangeText={setRealName}
            required
          />
          <FormInput
            label={t('traderCenter.idNumber')}
            value={idNumber}
            onChangeText={setIdNumber}
            required
          />
          <FormInput
            label={t('traderCenter.phone')}
            value={phone}
            onChangeText={setPhone}
            keyboardType="phone-pad"
            required
          />
          <FormInput
            label={t('traderCenter.nationality')}
            value={nationality}
            onChangeText={setNationality}
          />
          <FormInput
            label={t('traderCenter.address')}
            value={address}
            onChangeText={setAddress}
          />
        </View>
      )}

      {/* Step 2: Trading Qualifications */}
      {step === 1 && (
        <View style={styles.formSection}>
          <FormInput
            label={t('traderCenter.experienceYears')}
            value={experienceYears}
            onChangeText={setExperienceYears}
            keyboardType="numeric"
            required
          />

          <Text style={styles.fieldLabel}>
            {t('traderCenter.markets')} <Text style={styles.required}>*</Text>
          </Text>
          <View style={styles.chipRow}>
            {MARKET_OPTIONS.map((opt) => (
              <TouchableOpacity
                key={opt.key}
                style={[styles.chip, markets.includes(opt.key) && styles.chipActive]}
                onPress={() => toggleMarket(opt.key)}
              >
                <Text
                  style={[styles.chipText, markets.includes(opt.key) && styles.chipTextActive]}
                >
                  {t(opt.labelKey)}
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          <Text style={styles.fieldLabel}>
            {t('traderCenter.capitalSource')} <Text style={styles.required}>*</Text>
          </Text>
          <View style={styles.chipRow}>
            {CAPITAL_OPTIONS.map((opt) => (
              <TouchableOpacity
                key={opt.key}
                style={[styles.chip, capitalSource === opt.key && styles.chipActive]}
                onPress={() => setCapitalSource(opt.key)}
              >
                <Text
                  style={[styles.chipText, capitalSource === opt.key && styles.chipTextActive]}
                >
                  {t(opt.labelKey)}
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          <Text style={styles.fieldLabel}>
            {t('traderCenter.estimatedVolume')} <Text style={styles.required}>*</Text>
          </Text>
          <View style={styles.chipRow}>
            {VOLUME_OPTIONS.map((opt) => (
              <TouchableOpacity
                key={opt.key}
                style={[styles.chip, estimatedVolume === opt.key && styles.chipActive]}
                onPress={() => setEstimatedVolume(opt.key)}
              >
                <Text
                  style={[
                    styles.chipText,
                    estimatedVolume === opt.key && styles.chipTextActive,
                  ]}
                >
                  {t(opt.labelKey)}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>
      )}

      {/* Step 3: Risk Disclosure */}
      {step === 2 && (
        <View style={styles.formSection}>
          <TouchableOpacity
            style={styles.checkRow}
            onPress={() => setRiskAgreed(!riskAgreed)}
          >
            <View style={[styles.checkbox, riskAgreed && styles.checkboxActive]}>
              {riskAgreed && <Text style={styles.checkmark}>✓</Text>}
            </View>
            <Text style={styles.checkLabel}>{t('traderCenter.riskAgreed')}</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.checkRow}
            onPress={() => setTermsAgreed(!termsAgreed)}
          >
            <View style={[styles.checkbox, termsAgreed && styles.checkboxActive]}>
              {termsAgreed && <Text style={styles.checkmark}>✓</Text>}
            </View>
            <Text style={styles.checkLabel}>{t('traderCenter.termsAgreed')}</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Navigation buttons */}
      <View style={styles.buttonRow}>
        {step > 0 && (
          <TouchableOpacity style={styles.secondaryBtn} onPress={() => setStep(step - 1)}>
            <Text style={styles.secondaryBtnText}>{t('traderCenter.prev')}</Text>
          </TouchableOpacity>
        )}
        <View style={{ flex: 1 }} />
        {step < 2 ? (
          <TouchableOpacity
            style={[styles.primaryBtn, !canNext() && styles.btnDisabled]}
            onPress={() => canNext() && setStep(step + 1)}
            disabled={!canNext()}
          >
            <Text style={styles.primaryBtnText}>{t('traderCenter.next')}</Text>
          </TouchableOpacity>
        ) : (
          <TouchableOpacity
            style={[styles.primaryBtn, (!canNext() || submitting) && styles.btnDisabled]}
            onPress={handleSubmit}
            disabled={!canNext() || submitting}
          >
            {submitting ? (
              <ActivityIndicator color={Colors.textOnPrimary} size="small" />
            ) : (
              <Text style={styles.primaryBtnText}>{t('traderCenter.submit')}</Text>
            )}
          </TouchableOpacity>
        )}
      </View>
    </ScrollView>
  );
}

function FormInput({
  label,
  value,
  onChangeText,
  keyboardType,
  required,
}: {
  label: string;
  value: string;
  onChangeText: (v: string) => void;
  keyboardType?: 'default' | 'numeric' | 'phone-pad';
  required?: boolean;
}) {
  return (
    <View style={styles.fieldGroup}>
      <Text style={styles.fieldLabel}>
        {label} {required && <Text style={styles.required}>*</Text>}
      </Text>
      <TextInput
        style={styles.input}
        value={value}
        onChangeText={onChangeText}
        keyboardType={keyboardType || 'default'}
        placeholderTextColor={Colors.textMuted}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  contentContainer: { padding: 20, paddingBottom: 40 },
  stepRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    marginBottom: 32,
    gap: 24,
  },
  stepItem: { alignItems: 'center', gap: 6 },
  stepDot: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  stepDotActive: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  stepDotText: { color: Colors.textMuted, fontSize: 14, fontWeight: '600' },
  stepDotTextActive: { color: Colors.textOnPrimary },
  stepLabel: { color: Colors.textMuted, fontSize: 12 },
  stepLabelActive: { color: Colors.primary, fontWeight: '600' },
  formSection: { gap: 16 },
  fieldGroup: { gap: 6 },
  fieldLabel: { color: Colors.textSecondary, fontSize: 14, fontWeight: '500' },
  required: { color: Colors.down },
  input: {
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
    borderRadius: 8,
    padding: 12,
    color: Colors.textActive,
    fontSize: 15,
  },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 8 },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  chipActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primary,
  },
  chipText: { color: Colors.textSecondary, fontSize: 13 },
  chipTextActive: { color: Colors.primary, fontWeight: '600' },
  checkRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 8 },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 4,
    borderWidth: 1.5,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    justifyContent: 'center',
    alignItems: 'center',
  },
  checkboxActive: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  checkmark: { color: Colors.textOnPrimary, fontSize: 14, fontWeight: '700' },
  checkLabel: { color: Colors.textActive, fontSize: 14, flex: 1 },
  buttonRow: {
    flexDirection: 'row',
    marginTop: 32,
    gap: 12,
  },
  primaryBtn: {
    backgroundColor: Colors.primary,
    paddingHorizontal: 28,
    paddingVertical: 12,
    borderRadius: 8,
    minWidth: 120,
    alignItems: 'center',
  },
  primaryBtnText: { color: Colors.textOnPrimary, fontSize: 15, fontWeight: '700' },
  secondaryBtn: {
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 28,
    paddingVertical: 12,
    borderRadius: 8,
  },
  secondaryBtnText: { color: Colors.textSecondary, fontSize: 15, fontWeight: '600' },
  btnDisabled: { opacity: 0.5 },
});

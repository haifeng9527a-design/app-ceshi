import { useState } from 'react';
import {
  Alert,
  Image,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
  ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import * as ImagePicker from 'expo-image-picker';
import { useTranslation } from 'react-i18next';
import { Colors } from '../../theme/colors';
import { submitFeedback, uploadImage } from '../../services/api/feedbackApi';
import AppIcon, { type AppIconName } from '../../components/ui/AppIcon';
import { showAlert } from '../../services/utils/dialog';

type Category = 'complaint' | 'suggestion' | 'bug' | 'other';

const MAX_IMAGES = 3;
const MAX_CONTENT = 500;

export default function FeedbackScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const [category, setCategory] = useState<Category>('suggestion');
  const [content, setContent] = useState('');
  const [images, setImages] = useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const categories: { value: Category; label: string; icon: AppIconName }[] = [
    { value: 'complaint', label: t('feedback.categoryComplaint'), icon: 'shield' },
    { value: 'suggestion', label: t('feedback.categorySuggestion'), icon: 'bulb' },
    { value: 'bug', label: t('feedback.categoryBug'), icon: 'settings' },
    { value: 'other', label: t('feedback.categoryOther'), icon: 'paper' },
  ];

  const notify = (title: string, body: string, onOk?: () => void) => {
    showAlert(body, title);
    onOk?.();
  };

  const pickImage = async () => {
    if (images.length >= MAX_IMAGES) {
      notify(t('common.tip'), t('feedback.maxImages', { count: MAX_IMAGES }));
      return;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      quality: 0.8,
      allowsMultipleSelection: false,
    });

    if (!result.canceled && result.assets[0]) {
      setImages([...images, result.assets[0].uri]);
    }
  };

  const removeImage = (index: number) => {
    setImages(images.filter((_, i) => i !== index));
  };

  const handleSubmit = async () => {
    if (!content.trim()) {
      notify(t('common.tip'), t('feedback.contentRequired'));
      return;
    }

    setSubmitting(true);
    try {
      // Upload images first
      const imageUrls: string[] = [];
      for (const uri of images) {
        const url = await uploadImage(uri);
        imageUrls.push(url);
      }

      // Submit feedback
      await submitFeedback({
        content: content.trim(),
        image_urls: imageUrls,
        category,
      });

      // 提交完成后跳"我的反馈"历史页，让用户看到刚提交的这条 → 闭环
      notify(t('feedback.submitSuccessTitle'), t('feedback.submitSuccessBody'), () => {
        router.replace('/settings/feedback-history');
      });
    } catch (e: any) {
      console.error('[feedback] submit failed:', e);
      const status = e?.response?.status;
      const backendMsg = e?.response?.data?.error || e?.response?.data?.message;
      if (status === 401) {
        // 会话过期：提示并跳登录页
        notify(t('feedback.submitFailedTitle'), t('feedback.sessionExpired'), () => {
          router.replace('/(auth)/login' as any);
        });
      } else if (backendMsg) {
        // 后端有明确错误信息（业务错误），优先展示给用户
        notify(t('feedback.submitFailedTitle'), backendMsg);
      } else {
        // 真正无响应（断网/超时等），才提示检查网络
        notify(t('feedback.submitFailedTitle'), t('feedback.submitFailedBody'));
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <TouchableOpacity style={styles.backBtn} activeOpacity={0.8} onPress={() => router.back()}>
        <AppIcon name="back" size={16} color={Colors.primary} />
        <Text style={styles.backBtnText}>{t('common.back')}</Text>
      </TouchableOpacity>
      <View style={styles.headerRow}>
        <View style={{ flex: 1 }}>
          <Text style={styles.title}>{t('feedback.title')}</Text>
          <Text style={styles.subtitle}>{t('feedback.subtitle')}</Text>
        </View>
        <TouchableOpacity
          style={styles.historyLink}
          activeOpacity={0.7}
          onPress={() => router.push('/settings/feedback-history')}
        >
          <Text style={styles.historyLinkText}>{t('feedback.viewHistory')} →</Text>
        </TouchableOpacity>
      </View>

      {/* Category Picker */}
      <View style={styles.card}>
        <Text style={styles.sectionLabel}>{t('feedback.categoryLabel')}</Text>
        <View style={styles.categoryRow}>
          {categories.map((cat) => {
            const active = cat.value === category;
            return (
              <TouchableOpacity
                key={cat.value}
                style={[styles.categoryBtn, active && styles.categoryBtnActive]}
                activeOpacity={0.8}
                onPress={() => setCategory(cat.value)}
              >
                <AppIcon name={cat.icon} size={18} color={active ? Colors.background : Colors.textSecondary} />
                <Text style={[styles.categoryLabel, active && styles.categoryLabelActive]}>
                  {cat.label}
                </Text>
              </TouchableOpacity>
            );
          })}
        </View>
      </View>

      {/* Content Input */}
      <View style={styles.card}>
        <Text style={styles.sectionLabel}>{t('feedback.contentLabel')}</Text>
        <TextInput
          style={styles.textInput}
          placeholder={t('feedback.contentPlaceholder')}
          placeholderTextColor={Colors.textMuted}
          multiline
          maxLength={MAX_CONTENT}
          value={content}
          onChangeText={setContent}
          textAlignVertical="top"
        />
        <Text style={styles.charCount}>{content.length}/{MAX_CONTENT}</Text>
      </View>

      {/* Image Picker */}
      <View style={styles.card}>
        <Text style={styles.sectionLabel}>{t('feedback.imagesLabel', { count: MAX_IMAGES })}</Text>
        <View style={styles.imageRow}>
          {images.map((uri, idx) => (
            <View key={idx} style={styles.imageWrapper}>
              <Image source={{ uri }} style={styles.imageThumb} />
              <TouchableOpacity style={styles.removeBtn} onPress={() => removeImage(idx)}>
                <Text style={styles.removeBtnText}>✕</Text>
              </TouchableOpacity>
            </View>
          ))}
          {images.length < MAX_IMAGES && (
            <TouchableOpacity style={styles.addImageBtn} activeOpacity={0.8} onPress={pickImage}>
              <Text style={styles.addImageIcon}>+</Text>
              <Text style={styles.addImageText}>{t('feedback.addImage')}</Text>
            </TouchableOpacity>
          )}
        </View>
      </View>

      {/* Submit */}
      <TouchableOpacity
        style={[styles.submitBtn, submitting && styles.submitBtnDisabled]}
        activeOpacity={0.85}
        onPress={handleSubmit}
        disabled={submitting}
      >
        {submitting ? (
          <ActivityIndicator color={Colors.textOnPrimary} size="small" />
        ) : (
          <Text style={styles.submitBtnText}>{t('feedback.submit')}</Text>
        )}
      </TouchableOpacity>
    </ScrollView>
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
  backBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    alignSelf: 'flex-start',
    paddingVertical: 4,
  },
  backBtnText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    marginTop: 12,
    gap: 12,
  },
  historyLink: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingVertical: 6,
    paddingHorizontal: 10,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  historyLinkText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '600',
  },
  title: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
  },
  subtitle: {
    color: Colors.textMuted,
    fontSize: 13,
    lineHeight: 20,
  },
  card: {
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 18,
  },
  sectionLabel: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '600',
    marginBottom: 12,
  },
  categoryRow: {
    flexDirection: 'row',
    gap: 10,
  },
  categoryBtn: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 12,
    borderRadius: 12,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  categoryBtnActive: {
    borderColor: Colors.primary,
    backgroundColor: Colors.primaryDim,
  },
  categoryEmoji: {
    fontSize: 20,
    marginBottom: 4,
  },
  categoryLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  categoryLabelActive: {
    color: Colors.primary,
  },
  textInput: {
    color: Colors.textActive,
    fontSize: 14,
    lineHeight: 22,
    minHeight: 120,
    padding: 0,
  },
  charCount: {
    color: Colors.textMuted,
    fontSize: 11,
    textAlign: 'right',
    marginTop: 8,
  },
  imageRow: {
    flexDirection: 'row',
    gap: 10,
    flexWrap: 'wrap',
  },
  imageWrapper: {
    position: 'relative',
  },
  imageThumb: {
    width: 80,
    height: 80,
    borderRadius: 12,
    backgroundColor: Colors.surfaceAlt,
  },
  removeBtn: {
    position: 'absolute',
    top: -6,
    right: -6,
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: '#ff4444',
    alignItems: 'center',
    justifyContent: 'center',
  },
  removeBtnText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  addImageBtn: {
    width: 80,
    height: 80,
    borderRadius: 12,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
    borderStyle: 'dashed',
    alignItems: 'center',
    justifyContent: 'center',
  },
  addImageIcon: {
    color: Colors.textMuted,
    fontSize: 24,
    fontWeight: '300',
  },
  addImageText: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 2,
  },
  submitBtn: {
    backgroundColor: Colors.primary,
    borderRadius: 14,
    paddingVertical: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  submitBtnDisabled: {
    opacity: 0.6,
  },
  submitBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 16,
    fontWeight: '700',
  },
});

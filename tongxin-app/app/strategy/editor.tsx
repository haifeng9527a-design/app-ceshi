import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  useWindowDimensions,
  Platform,
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Shadows } from '../../theme/colors';
import RichTextEditor from '../../components/editor/RichTextEditor';
import apiClient from '../../services/api/client';
import {
  createStrategy,
  updateStrategy,
  getStrategy,
  TraderStrategy,
} from '../../services/api/traderStrategyApi';

const CATEGORIES = [
  { key: 'technical', label: 'strategy.categoryTechnical' },
  { key: 'fundamental', label: 'strategy.categoryFundamental' },
  { key: 'macro', label: 'strategy.categoryMacro' },
  { key: 'news', label: 'strategy.categoryNews' },
  { key: 'education', label: 'strategy.categoryEducation' },
  { key: 'other', label: 'strategy.categoryOther' },
];

export default function StrategyEditorScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const params = useLocalSearchParams<{ id?: string }>();
  const isEdit = !!params.id;
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;

  const [title, setTitle] = useState('');
  const [contentHtml, setContentHtml] = useState('');
  const [category, setCategory] = useState('technical');
  const [coverImage, setCoverImage] = useState('');
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [existing, setExisting] = useState<TraderStrategy | null>(null);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  // Load existing strategy if editing
  useEffect(() => {
    if (params.id) {
      setLoading(true);
      getStrategy(params.id)
        .then(({ strategy }) => {
          setExisting(strategy);
          setTitle(strategy.title);
          setContentHtml(strategy.content_html);
          setCategory(strategy.category || 'technical');
          setCoverImage(strategy.cover_image || '');
        })
        .catch(() => setError(t('strategy.loadFailed')))
        .finally(() => setLoading(false));
    }
  }, [params.id, t]);

  // Extract summary from HTML (first 200 chars of plain text)
  const extractSummary = (html: string): string => {
    if (Platform.OS === 'web') {
      const div = document.createElement('div');
      div.innerHTML = html;
      const text = div.textContent || div.innerText || '';
      return text.slice(0, 200).trim();
    }
    return html.replace(/<[^>]*>/g, '').slice(0, 200).trim();
  };

  const handleSave = async (status: 'draft' | 'published') => {
    setError('');
    setSuccess('');

    if (!title.trim()) {
      setError(t('strategy.titleRequired'));
      return;
    }
    if (!contentHtml.trim() || contentHtml === '<br>') {
      setError(t('strategy.contentRequired'));
      return;
    }

    setSaving(true);
    try {
      const summary = extractSummary(contentHtml);
      if (isEdit && params.id) {
        await updateStrategy(params.id, {
          title: title.trim(),
          summary,
          content_html: contentHtml,
          category,
          cover_image: coverImage,
          status,
        });
      } else {
        await createStrategy({
          title: title.trim(),
          summary,
          content_html: contentHtml,
          category,
          cover_image: coverImage,
          status,
        });
      }

      setSuccess(status === 'published' ? t('strategy.publishSuccess') : t('strategy.draftSaved'));
      setTimeout(() => {
        router.replace('/(tabs)/trader-center' as any);
      }, 1000);
    } catch (err: any) {
      setError(err?.response?.data?.error || err.message || t('strategy.saveFailed'));
    } finally {
      setSaving(false);
    }
  };

  const goBack = () => {
    router.back();
  };

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={goBack}>
          <Text style={styles.backBtn}>← {t('common.back')}</Text>
        </TouchableOpacity>
        <Text style={styles.headerTitle}>
          {isEdit ? t('strategy.editorTitleEdit') : t('strategy.editorTitleCreate')}
        </Text>
        <View style={styles.headerActions}>
          <TouchableOpacity
            style={styles.draftBtn}
            onPress={() => handleSave('draft')}
            disabled={saving}
          >
            <Text style={styles.draftBtnText}>
              {saving ? '...' : t('strategy.saveDraft')}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.publishBtn}
            onPress={() => handleSave('published')}
            disabled={saving}
          >
            <Text style={styles.publishBtnText}>
              {saving ? t('strategy.publishing') : t('strategy.publishNow')}
            </Text>
          </TouchableOpacity>
        </View>
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={[
          styles.scrollContent,
          isDesktop && { maxWidth: 900, alignSelf: 'center', width: '100%' },
        ]}
      >
        {/* Feedback Messages */}
        {error ? (
          <View style={styles.errorBanner}>
            <Text style={styles.errorBannerText}>{error}</Text>
          </View>
        ) : null}
        {success ? (
          <View style={styles.successBanner}>
            <Text style={styles.successBannerText}>{success}</Text>
          </View>
        ) : null}

        {/* Title */}
        <TextInput
          style={styles.titleInput}
          placeholder={t('strategy.titlePlaceholder')}
          placeholderTextColor={Colors.textMuted}
          value={title}
          onChangeText={setTitle}
          maxLength={200}
        />

        {/* Category Chips */}
        <View style={styles.categoryRow}>
          <Text style={styles.fieldLabel}>{t('strategy.categoryLabel')}</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            <View style={styles.chipRow}>
              {CATEGORIES.map((cat) => (
                <TouchableOpacity
                  key={cat.key}
                  style={[
                    styles.chip,
                    category === cat.key && styles.chipActive,
                  ]}
                  onPress={() => setCategory(cat.key)}
                >
                  <Text
                    style={[
                      styles.chipText,
                      category === cat.key && styles.chipTextActive,
                    ]}
                  >
                    {t(cat.label)}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </ScrollView>
        </View>

        {/* Cover Image URL */}
        <View style={styles.fieldRow}>
          <Text style={styles.fieldLabel}>{t('strategy.coverImageOptional')}</Text>
          <TextInput
            style={styles.urlInput}
            placeholder={t('strategy.coverImagePlaceholder')}
            placeholderTextColor={Colors.textMuted}
            value={coverImage}
            onChangeText={setCoverImage}
          />
        </View>

        {/* Rich Text Editor */}
        <View style={styles.editorSection}>
          <Text style={styles.fieldLabel}>{t('strategy.contentLabel')}</Text>
          <RichTextEditor
            initialContent={contentHtml}
            onContentChange={setContentHtml}
            placeholder={t('strategy.contentPlaceholder')}
            minHeight={500}
          />
        </View>

        <View style={{ height: 60 }} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: Colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    backgroundColor: Colors.surface,
    gap: 12,
  },
  backBtn: {
    color: Colors.primary,
    fontSize: 15,
    fontWeight: '600',
  },
  headerTitle: {
    color: Colors.textActive,
    fontSize: 17,
    fontWeight: '700',
    flex: 1,
  },
  headerActions: {
    flexDirection: 'row',
    gap: 8,
  },
  draftBtn: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  draftBtnText: {
    color: Colors.textMuted,
    fontSize: 14,
    fontWeight: '600',
  },
  publishBtn: {
    paddingHorizontal: 20,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: Colors.primary,
  },
  publishBtnText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
  },
  titleInput: {
    fontSize: 28,
    fontWeight: '800',
    color: Colors.textActive,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    marginBottom: 20,
  },
  categoryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
    gap: 8,
  },
  chipRow: {
    flexDirection: 'row',
    gap: 8,
  },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  chipActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primary,
  },
  chipText: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '500',
  },
  chipTextActive: {
    color: Colors.primary,
    fontWeight: '600',
  },
  fieldRow: {
    marginBottom: 16,
    gap: 6,
  },
  fieldLabel: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '600',
    marginBottom: 4,
  },
  urlInput: {
    backgroundColor: Colors.surface,
    borderRadius: 8,
    padding: 12,
    color: Colors.textActive,
    fontSize: 14,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  editorSection: {
    marginTop: 8,
    gap: 8,
  },
  errorBanner: {
    backgroundColor: 'rgba(255, 59, 48, 0.15)',
    borderWidth: 1,
    borderColor: 'rgba(255, 59, 48, 0.3)',
    borderRadius: 10,
    padding: 12,
    marginBottom: 16,
  },
  errorBannerText: {
    color: '#FF3B30',
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'center',
  },
  successBanner: {
    backgroundColor: 'rgba(52, 199, 89, 0.15)',
    borderWidth: 1,
    borderColor: 'rgba(52, 199, 89, 0.3)',
    borderRadius: 10,
    padding: 12,
    marginBottom: 16,
  },
  successBannerText: {
    color: '#34C759',
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'center',
  },
});

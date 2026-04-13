import { useState } from 'react';
import {
  Alert,
  Image,
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
import { Colors } from '../../theme/colors';
import { submitFeedback, uploadImage } from '../../services/api/feedbackApi';

type Category = 'complaint' | 'suggestion' | 'bug' | 'other';

const CATEGORIES: { value: Category; label: string; emoji: string }[] = [
  { value: 'complaint', label: '投诉', emoji: '😤' },
  { value: 'suggestion', label: '建议', emoji: '💡' },
  { value: 'bug', label: 'Bug', emoji: '🐛' },
  { value: 'other', label: '其他', emoji: '📝' },
];

const MAX_IMAGES = 3;
const MAX_CONTENT = 500;

export default function FeedbackScreen() {
  const router = useRouter();
  const [category, setCategory] = useState<Category>('suggestion');
  const [content, setContent] = useState('');
  const [images, setImages] = useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);

  const pickImage = async () => {
    if (images.length >= MAX_IMAGES) {
      Alert.alert('提示', `最多上传 ${MAX_IMAGES} 张图片`);
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
      Alert.alert('提示', '请填写反馈内容');
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

      Alert.alert('提交成功', '感谢您的反馈，我们会尽快处理！', [
        { text: '确定', onPress: () => router.back() },
      ]);
    } catch {
      Alert.alert('提交失败', '请检查网络后重试');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <Text style={styles.title}>投诉建议</Text>
      <Text style={styles.subtitle}>请选择反馈类型并填写详情，我们会认真处理每一条反馈。</Text>

      {/* Category Picker */}
      <View style={styles.card}>
        <Text style={styles.sectionLabel}>反馈类型</Text>
        <View style={styles.categoryRow}>
          {CATEGORIES.map((cat) => {
            const active = cat.value === category;
            return (
              <TouchableOpacity
                key={cat.value}
                style={[styles.categoryBtn, active && styles.categoryBtnActive]}
                activeOpacity={0.8}
                onPress={() => setCategory(cat.value)}
              >
                <Text style={styles.categoryEmoji}>{cat.emoji}</Text>
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
        <Text style={styles.sectionLabel}>详细描述</Text>
        <TextInput
          style={styles.textInput}
          placeholder="请描述您的问题或建议..."
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
        <Text style={styles.sectionLabel}>附件图片（选填，最多{MAX_IMAGES}张）</Text>
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
              <Text style={styles.addImageText}>添加</Text>
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
          <Text style={styles.submitBtnText}>提交反馈</Text>
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
  title: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    marginTop: 12,
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

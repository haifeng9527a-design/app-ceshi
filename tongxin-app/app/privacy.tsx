import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { Colors } from '../theme/colors';

const SECTIONS = [
  {
    title: '1. 我们收集哪些信息',
    body: '包括账号资料、消息相关的最小必要信息、交易员资料、跟单配置，以及为了保障安全而产生的登录与设备记录。',
  },
  {
    title: '2. 信息如何被使用',
    body: '主要用于身份识别、消息送达、交易员展示、跟单功能、风控校验和体验优化。不会因为单纯做产品统计而暴露你的私聊内容。',
  },
  {
    title: '3. 谁可以看到这些信息',
    body: '公开主页只展示用户主动开放的资料；私聊、群聊、跟单配置等仅在业务需要的范围内使用，敏感信息不会作为公开资料展示。',
  },
  {
    title: '4. 数据保留与安全',
    body: '消息和交易相关数据会按业务需要保留，系统会尽量通过鉴权、权限分层、连接校验和操作日志降低误用风险。',
  },
];

export default function PrivacyScreen() {
  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <Text style={styles.title}>隐私政策</Text>
      <Text style={styles.subtitle}>当前先提供应用内可阅读版本，后续可再替换成法务确认后的正式文本。</Text>

      {SECTIONS.map((section) => (
        <View key={section.title} style={styles.card}>
          <Text style={styles.sectionTitle}>{section.title}</Text>
          <Text style={styles.sectionBody}>{section.body}</Text>
        </View>
      ))}
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
    gap: 16,
  },
  title: {
    marginTop: 12,
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
    gap: 8,
  },
  sectionTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  sectionBody: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
  },
});

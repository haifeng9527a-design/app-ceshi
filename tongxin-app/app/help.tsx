import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { Colors } from '../theme/colors';

const FAQS = [
  {
    q: '收不到消息怎么办？',
    a: '先确认网络和消息服务连接状态，其次检查对方是否已成为好友。如果仍有问题，回到消息页等待自动重连，系统会补拉最近消息。',
  },
  {
    q: '语音通话为什么无法建立？',
    a: '网页端需要浏览器麦克风权限，同时 LiveKit 服务需要已配置。若仅看到预览页，请检查当前环境是否已经完成语音服务接入。',
  },
  {
    q: '跟单设置在哪里改？',
    a: '在交易员资料侧栏或私聊资料页里，可以打开跟单设置并调整比例、最大仓位等参数。',
  },
  {
    q: '群聊管理有哪些能力？',
    a: '群主和管理员可以编辑群信息、添加成员、移除成员。群主还可以设定管理员和解散群。',
  },
];

export default function HelpScreen() {
  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <Text style={styles.title}>帮助中心</Text>
      <Text style={styles.subtitle}>先把最常见的问题集中放在这里，方便用户自助排查，不必在设置里点开一堆空入口。</Text>

      {FAQS.map((item) => (
        <View key={item.q} style={styles.card}>
          <Text style={styles.question}>{item.q}</Text>
          <Text style={styles.answer}>{item.a}</Text>
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
  question: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  answer: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
  },
});

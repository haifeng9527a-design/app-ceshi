import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';

interface SentimentCardProps {
  score: number; // 0-100
}

function GaugeArc({ score, label }: { score: number; label: string }) {

  const color =
    score >= 75 ? Colors.up :
    score >= 55 ? Colors.primaryLight :
    score >= 45 ? Colors.textSecondary :
    score >= 25 ? Colors.warning :
    Colors.down;

  return (
    <View style={gaugeStyles.container}>
      <View style={[gaugeStyles.circle, { borderColor: color }]}>
        <Text style={[gaugeStyles.score, { color }]}>{score}</Text>
        <Text style={gaugeStyles.max}>/100</Text>
      </View>
      <Text style={[gaugeStyles.label, { color }]}>{label}</Text>

      <View style={gaugeStyles.barTrack}>
        <View
          style={[
            gaugeStyles.barFill,
            { width: `${score}%`, backgroundColor: color },
          ]}
        />
      </View>
    </View>
  );
}

const gaugeStyles = StyleSheet.create({
  container: {
    alignItems: 'center',
    paddingVertical: 12,
  },
  circle: {
    width: 80,
    height: 80,
    borderRadius: 40,
    borderWidth: 3,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  score: {
    fontSize: 28,
    fontWeight: '800',
    fontFamily: 'monospace',
  },
  max: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: -2,
  },
  label: {
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 0.5,
    marginBottom: 12,
  },
  barTrack: {
    width: '80%',
    height: 4,
    backgroundColor: Colors.border,
    borderRadius: 2,
    overflow: 'hidden',
  },
  barFill: {
    height: '100%',
    borderRadius: 2,
  },
});

interface BulletProps {
  icon: string;
  text: string;
  type: 'positive' | 'warning';
}

function Bullet({ icon, text, type }: BulletProps) {
  const iconColor = type === 'positive' ? Colors.up : Colors.warning;
  return (
    <View style={bulletStyles.row}>
      <Text style={[bulletStyles.icon, { color: iconColor }]}>{icon}</Text>
      <Text style={bulletStyles.text}>{text}</Text>
    </View>
  );
}

const bulletStyles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 4,
  },
  icon: {
    fontSize: 14,
    marginRight: 8,
    width: 20,
  },
  text: {
    color: Colors.textSecondary,
    fontSize: 12,
    flex: 1,
  },
});

export default function SentimentCard({ score }: SentimentCardProps) {
  const { t } = useTranslation();

  const riskLabel = score >= 55 ? t('market.riskOn') : t('marketCard.riskOff');
  const sentimentGaugeLabel =
    score >= 75 ? t('marketCard.extremeGreed') :
    score >= 55 ? t('marketCard.greed') :
    score >= 45 ? t('marketCard.neutral') :
    score >= 25 ? t('marketCard.fear') :
    t('marketCard.extremeFear');

  return (
    <View style={styles.card}>
      {/* Header */}
      <View style={styles.header}>
        <View style={styles.badge}>
          <Text style={styles.badgeText}>{t('market.marketSentiment')}</Text>
        </View>
        <Text style={styles.title}>{riskLabel}</Text>
      </View>

      <GaugeArc score={score} label={sentimentGaugeLabel} />

      {/* Bullet points */}
      <View style={styles.bullets}>
        <Bullet icon="✅" text={t('marketCard.institutionalInflows')} type="positive" />
        <Bullet icon="✅" text={t('marketCard.macroLiquidity')} type="positive" />
        <Bullet icon="⚠️" text={t('marketCard.retailSentiment')} type="warning" />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    flex: 1,
    backgroundColor: Colors.surface,
    borderRadius: Sizes.borderRadius,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    ...Shadows.card,
  },
  header: {
    marginBottom: 4,
  },
  badge: {
    alignSelf: 'flex-start',
    backgroundColor: Colors.primaryDim,
    borderRadius: 4,
    paddingHorizontal: 8,
    paddingVertical: 3,
    marginBottom: 6,
  },
  badgeText: {
    color: Colors.primary,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  title: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '700',
  },
  bullets: {
    marginTop: 12,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
    paddingTop: 10,
  },
});

import type { StyleProp, ViewStyle } from 'react-native';
import Svg, { Circle, Line, Path, Polyline, Rect } from 'react-native-svg';
import { Colors } from '../../theme/colors';

export type AppIconName =
  | 'back'
  | 'search'
  | 'close'
  | 'check'
  | 'market'
  | 'watchlist'
  | 'eye'
  | 'trading'
  | 'badge'
  | 'trophy'
  | 'message'
  | 'user'
  | 'building'
  | 'logout'
  | 'settings'
  | 'lock'
  | 'bell'
  | 'mail'
  | 'key'
  | 'qr'
  | 'camera'
  | 'users'
  | 'help'
  | 'globe'
  | 'bot'
  | 'shield'
  | 'trash'
  | 'chart'
  | 'bulb'
  | 'paper'
  | 'clock'
  | 'heart'
  | 'forex'
  | 'bitcoin'
  | 'futures'
  | 'flame'
  | 'trend-up'
  | 'trend-down'
  | 'user-circle'
  | 'sparkles'
  | 'visibility'
  | 'phone'
  | 'image'
  | 'send';

type Props = {
  name: AppIconName;
  size?: number;
  color?: string;
  strokeWidth?: number;
  style?: StyleProp<ViewStyle>;
};

export default function AppIcon({
  name,
  size = 18,
  color = Colors.textSecondary,
  strokeWidth = 1.8,
  style,
}: Props) {
  const common = {
    stroke: color,
    strokeWidth,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    fill: 'none' as const,
  };

  const renderPath = () => {
    switch (name) {
      case 'back':
        return <Polyline points="15,6 9,12 15,18" {...common} />;
      case 'search':
        return (
          <>
            <Circle cx="11" cy="11" r="5.5" {...common} />
            <Line x1="15.5" y1="15.5" x2="20" y2="20" {...common} />
          </>
        );
      case 'close':
        return (
          <>
            <Line x1="6" y1="6" x2="18" y2="18" {...common} />
            <Line x1="18" y1="6" x2="6" y2="18" {...common} />
          </>
        );
      case 'check':
        return <Polyline points="6.8,12.4 10.1,15.4 17.2,8.6" {...common} />;
      case 'market':
        return (
          <>
            <Line x1="6" y1="18" x2="18" y2="18" {...common} />
            <Rect x="6.5" y="11" width="2.8" height="7" rx="1.1" {...common} />
            <Rect x="10.6" y="8" width="2.8" height="10" rx="1.1" {...common} />
            <Rect x="14.7" y="5" width="2.8" height="13" rx="1.1" {...common} />
          </>
        );
      case 'watchlist':
        return <Path d="m12 4.8 2.1 4.3 4.7.7-3.4 3.3.8 4.7L12 15.6 7.8 17.8l.8-4.7-3.4-3.3 4.7-.7L12 4.8Z" {...common} />;
      case 'eye':
        return (
          <>
            <Path d="M3.8 12s3.2-5 8.2-5 8.2 5 8.2 5-3.2 5-8.2 5-8.2-5-8.2-5Z" {...common} />
            <Circle cx="12" cy="12" r="2.2" {...common} />
          </>
        );
      case 'trading':
        return (
          <>
            <Path d="M5 17h14" {...common} />
            <Polyline points="6,15 10,11 13,13 18,8" {...common} />
            <Polyline points="15.6,8 18,8 18,10.5" {...common} />
          </>
        );
      case 'badge':
        return (
          <>
            <Circle cx="12" cy="10" r="5" {...common} />
            <Path d="m9.2 14.2-1 5 3.8-2.2 3.8 2.2-1-5" {...common} />
          </>
        );
      case 'trophy':
        return (
          <>
            <Path d="M8 5h8v3.2A4 4 0 0 1 12 12.2 4 4 0 0 1 8 8.2V5Z" {...common} />
            <Path d="M8 6H5.5a2.2 2.2 0 0 0 2.2 4H8" {...common} />
            <Path d="M16 6h2.5a2.2 2.2 0 0 1-2.2 4H16" {...common} />
            <Path d="M12 12.2V16" {...common} />
            <Path d="M9 19h6" {...common} />
          </>
        );
      case 'message':
        return <Path d="M5.5 6.5h13a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H10l-4.5 3v-3H5.5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2Z" {...common} />;
      case 'user':
        return (
          <>
            <Circle cx="12" cy="8" r="3.2" {...common} />
            <Path d="M5.6 18c1-3 3.4-4.7 6.4-4.7s5.4 1.7 6.4 4.7" {...common} />
          </>
        );
      case 'building':
        return (
          <>
            <Rect x="5" y="4.5" width="14" height="15" rx="2" {...common} />
            <Line x1="8.5" y1="8" x2="8.5" y2="16" {...common} />
            <Line x1="12" y1="8" x2="12" y2="16" {...common} />
            <Line x1="15.5" y1="8" x2="15.5" y2="16" {...common} />
            <Line x1="5" y1="8" x2="19" y2="8" {...common} />
          </>
        );
      case 'logout':
        return (
          <>
            <Path d="M10 5.5H8a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h2" {...common} />
            <Line x1="13" y1="12" x2="21" y2="12" {...common} />
            <Polyline points="17.5,8.5 21,12 17.5,15.5" {...common} />
          </>
        );
      case 'settings':
        return (
          <>
            <Circle cx="12" cy="12" r="2.4" {...common} />
            <Path d="M12 4.8v2.1M12 17.1v2.1M19.2 12h-2.1M6.9 12H4.8M17.1 6.9l-1.5 1.5M8.4 15.6l-1.5 1.5M17.1 17.1l-1.5-1.5M8.4 8.4 6.9 6.9" {...common} />
          </>
        );
      case 'lock':
        return (
          <>
            <Rect x="6" y="11" width="12" height="9" rx="2.5" {...common} />
            <Path d="M8.5 11V8.8a3.5 3.5 0 0 1 7 0V11" {...common} />
          </>
        );
      case 'bell':
        return (
          <>
            <Path d="M8 17h8l-1.1-1.6V11a4.9 4.9 0 1 0-9.8 0v4.4L8 17Z" {...common} />
            <Path d="M10 18.5a2 2 0 0 0 4 0" {...common} />
          </>
        );
      case 'mail':
        return (
          <>
            <Rect x="4.5" y="6.5" width="15" height="11" rx="2.2" {...common} />
            <Path d="m6.5 8 5.5 4.5L17.5 8" {...common} />
          </>
        );
      case 'key':
        return (
          <>
            <Circle cx="9" cy="12" r="3.5" {...common} />
            <Path d="M12.4 12H20l-1.6 1.6 1.2 1.2-1.2 1.2" {...common} />
          </>
        );
      case 'qr':
        return (
          <>
            <Rect x="5" y="5" width="5" height="5" rx="1" {...common} />
            <Rect x="14" y="5" width="5" height="5" rx="1" {...common} />
            <Rect x="5" y="14" width="5" height="5" rx="1" {...common} />
            <Path d="M14 14h2v2h-2zM18 14h1v5h-5v-1M14 18h2" {...common} />
          </>
        );
      case 'camera':
        return (
          <>
            <Rect x="4.5" y="7.5" width="15" height="11" rx="2.4" {...common} />
            <Path d="M8 7.5 9.2 5.8h5.6L16 7.5" {...common} />
            <Circle cx="12" cy="13" r="3" {...common} />
          </>
        );
      case 'users':
        return (
          <>
            <Circle cx="9" cy="9" r="2.8" {...common} />
            <Circle cx="15.4" cy="8.2" r="2.2" {...common} />
            <Path d="M4.8 18c.7-2.2 2.5-3.6 4.7-3.6s4 1.4 4.7 3.6" {...common} />
            <Path d="M13.3 18c.5-1.5 1.8-2.4 3.4-2.4 1.5 0 2.8 1 3.3 2.4" {...common} />
          </>
        );
      case 'help':
        return (
          <>
            <Path d="M9.6 9.3a2.8 2.8 0 1 1 4.8 1.8c-.8.8-1.8 1.3-1.8 2.6" {...common} />
            <Circle cx="12" cy="17.5" r="0.8" fill={color} />
            <Circle cx="12" cy="12" r="8" {...common} />
          </>
        );
      case 'globe':
        return (
          <>
            <Circle cx="12" cy="12" r="8" {...common} />
            <Path d="M4.5 12h15M12 4.2c2.2 2 3.4 4.8 3.4 7.8 0 3-1.2 5.8-3.4 7.8M12 4.2c-2.2 2-3.4 4.8-3.4 7.8 0 3 1.2 5.8 3.4 7.8" {...common} />
          </>
        );
      case 'bot':
        return (
          <>
            <Rect x="6" y="8" width="12" height="10" rx="3" {...common} />
            <Line x1="12" y1="5" x2="12" y2="8" {...common} />
            <Circle cx="9.5" cy="12.5" r="1" fill={color} />
            <Circle cx="14.5" cy="12.5" r="1" fill={color} />
            <Path d="M9.5 15.5h5" {...common} />
          </>
        );
      case 'shield':
        return (
          <>
            <Path d="M12 4.8 18 7v4.9c0 3.6-2.3 6-6 7.3-3.7-1.3-6-3.7-6-7.3V7l6-2.2Z" {...common} />
            <Path d="m9.4 12.2 1.7 1.7 3.5-3.6" {...common} />
          </>
        );
      case 'trash':
        return (
          <>
            <Path d="M7.5 7.5h9" {...common} />
            <Path d="M9 7.5V6.2a1.2 1.2 0 0 1 1.2-1.2h3.6A1.2 1.2 0 0 1 15 6.2v1.3" {...common} />
            <Rect x="7.5" y="7.5" width="9" height="11.5" rx="1.5" {...common} />
            <Line x1="10.3" y1="10.2" x2="10.3" y2="16.2" {...common} />
            <Line x1="13.7" y1="10.2" x2="13.7" y2="16.2" {...common} />
          </>
        );
      case 'chart':
        return (
          <>
            <Polyline points="5,15 9,11 12,13 18,7 20,9" {...common} />
            <Path d="M5 19h14" {...common} />
          </>
        );
      case 'bulb':
        return (
          <>
            <Path d="M9 15.5c-1.5-1-2.5-2.7-2.5-4.6a5.5 5.5 0 1 1 11 0c0 1.9-1 3.6-2.5 4.6" {...common} />
            <Path d="M10 17h4M10.5 19h3" {...common} />
          </>
        );
      case 'paper':
        return (
          <>
            <Path d="M7 4.8h7.2l3.3 3.3V19H7z" {...common} />
            <Path d="M14.2 4.8V8h3.3" {...common} />
            <Path d="M9.4 11.4h5.2M9.4 14.2h5.2" {...common} />
          </>
        );
      case 'clock':
        return (
          <>
            <Circle cx="12" cy="12" r="8" {...common} />
            <Path d="M12 8v4.2l2.8 1.8" {...common} />
          </>
        );
      case 'heart':
        return <Path d="M12 19.2 5.8 13a4 4 0 1 1 5.7-5.7l.5.5.5-.5A4 4 0 1 1 18.2 13L12 19.2Z" {...common} />;
      case 'forex':
        return (
          <>
            <Path d="M8.2 8.4h6.2a2.7 2.7 0 1 1 0 5.4H9.5" {...common} />
            <Path d="M10.5 6.5 8.2 8.7l2.3 2.2" {...common} />
            <Path d="M15.8 15.6H9.6a2.7 2.7 0 1 1 0-5.4h4.9" {...common} />
            <Path d="m13.5 17.5 2.3-2.2-2.3-2.2" {...common} />
          </>
        );
      case 'bitcoin':
        return (
          <>
            <Circle cx="12" cy="12" r="8" {...common} />
            <Path d="M10.2 8.2v7.6M13.2 8.2v7.6M9.2 9.5h4.3a1.8 1.8 0 0 1 0 3.6H9.2h4.9a1.9 1.9 0 1 1 0 3.8H9.2" {...common} />
          </>
        );
      case 'futures':
        return (
          <>
            <Rect x="5" y="6" width="14" height="12" rx="2" {...common} />
            <Path d="M8.2 10.2h7.6M8.2 13.8h7.6" {...common} />
            <Path d="M9.3 6V4.7M14.7 6V4.7" {...common} />
          </>
        );
      case 'flame':
        return <Path d="M12 4.5c1.8 2 3.8 3.9 3.8 6.7a3.8 3.8 0 1 1-7.6 0c0-1.6.7-2.8 1.8-4 .6 1 1.2 1.6 2 2.1.3-1.8 1-3.2 2-4.8Z" {...common} />;
      case 'trend-up':
        return (
          <>
            <Path d="M5 18h14" {...common} />
            <Polyline points="6,15 10,11 13,12.8 18,7.8" {...common} />
            <Polyline points="15.3,7.8 18,7.8 18,10.5" {...common} />
          </>
        );
      case 'trend-down':
        return (
          <>
            <Path d="M5 18h14" {...common} />
            <Polyline points="6,9 10,13 13,11.2 18,16.2" {...common} />
            <Polyline points="15.3,16.2 18,16.2 18,13.5" {...common} />
          </>
        );
      case 'user-circle':
        return (
          <>
            <Circle cx="12" cy="12" r="8" {...common} />
            <Circle cx="12" cy="10" r="2.5" {...common} />
            <Path d="M8.2 17c.8-1.8 2.1-2.7 3.8-2.7 1.7 0 3 .9 3.8 2.7" {...common} />
          </>
        );
      case 'sparkles':
        return (
          <>
            <Path d="m12 5 1.1 3.2L16.3 9l-3.2 1-1.1 3.2-1.1-3.2L7.7 9l3.2-.8L12 5Z" {...common} />
            <Path d="m17.5 14.5.6 1.8 1.9.5-1.9.6-.6 1.8-.6-1.8-1.9-.6 1.9-.5.6-1.8Z" {...common} />
          </>
        );
      case 'visibility':
        return (
          <>
            <Path d="M4 12s3.2-4.6 8-4.6 8 4.6 8 4.6-3.2 4.6-8 4.6S4 12 4 12Z" {...common} />
            <Circle cx="12" cy="12" r="1.8" {...common} />
          </>
        );
      case 'phone':
        return <Path d="M8.2 5.5c.6-.6 1.6-.6 2.2 0l1.6 1.6c.5.5.6 1.2.2 1.8l-.9 1.3a14.7 14.7 0 0 0 2.5 2.5l1.3-.9c.6-.4 1.4-.3 1.8.2l1.6 1.6c.6.6.6 1.6 0 2.2l-1 1c-.8.8-2 .9-3 .4-2.7-1.3-5.6-4.2-6.9-6.9-.5-1-.4-2.2.4-3l1-1Z" {...common} />;
      case 'image':
        return (
          <>
            <Rect x="4" y="5" width="16" height="14" rx="3" {...common} />
            <Circle cx="9" cy="10" r="1.6" {...common} />
            <Path d="M7 17l4.2-4.1c.4-.4 1-.4 1.4 0l1.6 1.6c.4.4 1 .4 1.4 0L18 12" {...common} />
          </>
        );
      case 'send':
        return <Path d="M4 12 20 5l-3 14-4.5-4L8 16l1-4-5-0Z" {...common} />;
      default:
        return null;
    }
  };

  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" style={style}>
      {renderPath()}
    </Svg>
  );
}

import { useEffect, useRef, useState } from 'react';
import { Animated } from 'react-native';

const UP_COLOR = '#22c55e';
const DOWN_COLOR = '#ef4444';

/**
 * Returns an Animated background color that flashes green/red
 * when `price` changes.
 */
export function usePriceFlash(price: number | undefined) {
  const flashAnim = useRef(new Animated.Value(0)).current;
  const prevRef = useRef(price);
  const [flashColor, setFlashColor] = useState<string | null>(null);

  useEffect(() => {
    const prev = prevRef.current;
    if (prev != null && price != null && prev !== price) {
      setFlashColor(price > prev ? UP_COLOR : DOWN_COLOR);
      flashAnim.setValue(1);
      Animated.timing(flashAnim, {
        toValue: 0,
        duration: 600,
        useNativeDriver: false,
      }).start();
    }
    prevRef.current = price;
  }, [price]);

  const backgroundColor = flashColor
    ? flashAnim.interpolate({
        inputRange: [0, 1],
        outputRange: ['transparent', flashColor + '30'],
      })
    : 'transparent';

  return backgroundColor;
}

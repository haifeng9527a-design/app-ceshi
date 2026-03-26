/**
 * 涨跌色：涨绿 #22C55E，跌红 #EF4444
 */
export const UP = '#22C55E';
export const DOWN = '#EF4444';

export function colorByChange(changePercent: number): string {
  return changePercent >= 0 ? UP : DOWN;
}

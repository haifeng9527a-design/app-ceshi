import React from 'react';
import { colorByChange } from '@/utils/colors';

const W = 120;
const H = 28;

interface SparklineProps {
  data: number[];
  changePercent: number;
  width?: number;
  height?: number;
  className?: string;
}

/**
 * 纯 SVG 迷你折线图，涨绿跌红
 */
export function Sparkline({
  data,
  changePercent,
  width = W,
  height = H,
  className = '',
}: SparklineProps) {
  if (!data.length) return null;
  const color = colorByChange(changePercent);
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const padding = 2;
  const w = width - padding * 2;
  const h = height - padding * 2;
  const step = data.length > 1 ? w / (data.length - 1) : 0;
  const points = data
    .map((y, i) => {
      const x = padding + i * step;
      const ny = padding + h - ((y - min) / range) * h;
      return `${x},${ny}`;
    })
    .join(' ');
  return (
    <svg
      width={width}
      height={height}
      className={className}
      aria-hidden
    >
      <polyline
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
        points={points}
      />
    </svg>
  );
}

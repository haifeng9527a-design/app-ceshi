/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        surface: '#0B0F14',
        card: '#0F1722',
        border: 'rgba(255,255,255,0.06)',
        up: '#22C55E',
        down: '#EF4444',
        muted: 'rgba(255,255,255,0.6)',
      },
      borderRadius: {
        card: '16px',
        btn: '12px',
        input: '14px',
      },
      fontFamily: {
        mono: ['ui-monospace', 'monospace'],
      },
    },
  },
  plugins: [],
};

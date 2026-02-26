import React, { useState, useEffect } from 'react';
import UsStocksPage from './pages/UsStocksPage';
import ChartPage from './pages/ChartPage';

function App() {
  const [isChart, setIsChart] = useState(
    () => (typeof window !== 'undefined' && (window.location.pathname === '/chart' || window.location.hash === '#chart'))
  );
  useEffect(() => {
    const check = () => setIsChart(window.location.pathname === '/chart' || window.location.hash === '#chart');
    window.addEventListener('hashchange', check);
    return () => window.removeEventListener('hashchange', check);
  }, []);
  return isChart ? <ChartPage /> : <UsStocksPage />;
}

export default App;

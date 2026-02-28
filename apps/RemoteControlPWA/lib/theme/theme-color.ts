'use client';

import { useEffect } from 'react';

function updateThemeColorMeta() {
  const meta = document.querySelector('meta[name="theme-color"]');
  if (!meta) {
    return;
  }
  const prefersLight = window.matchMedia?.('(prefers-color-scheme: light)')?.matches === true;
  meta.setAttribute('content', prefersLight ? '#ffffff' : '#000000');
}

export function useThemeColorMeta() {
  useEffect(() => {
    updateThemeColorMeta();
    const media = window.matchMedia?.('(prefers-color-scheme: light)');
    if (!media) {
      return;
    }

    const onChange = () => updateThemeColorMeta();
    if (typeof media.addEventListener === 'function') {
      media.addEventListener('change', onChange);
      return () => media.removeEventListener('change', onChange);
    }

    media.addListener(onChange);
    return () => media.removeListener(onChange);
  }, []);
}

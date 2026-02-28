'use client';

import { useEffect } from 'react';
import { remoteStoreApi } from '@/lib/remote/store';

function setRootCSSVar(name: string, value: string) {
  document.documentElement.style.setProperty(name, value);
}

function syncVisualViewportMetrics() {
  const vv = window.visualViewport;
  const viewportHeight = vv ? vv.height : window.innerHeight;
  const keyboardOffset = vv ? Math.max(0, window.innerHeight - vv.height - vv.offsetTop) : 0;

  setRootCSSVar('--vvh', `${Math.max(1, Math.round(viewportHeight))}px`);
  setRootCSSVar('--keyboard-offset', `${Math.max(0, Math.round(keyboardOffset))}px`);

  remoteStoreApi.setState({
    visualViewportHeight: viewportHeight,
    keyboardOffset
  });
}

export function useVisualViewportSync() {
  useEffect(() => {
    syncVisualViewportMetrics();

    const onResize = () => syncVisualViewportMetrics();
    window.addEventListener('resize', onResize);
    window.addEventListener('orientationchange', onResize);

    const vv = window.visualViewport;
    if (vv) {
      vv.addEventListener('resize', onResize);
      vv.addEventListener('scroll', onResize);
    }

    return () => {
      window.removeEventListener('resize', onResize);
      window.removeEventListener('orientationchange', onResize);
      if (vv) {
        vv.removeEventListener('resize', onResize);
        vv.removeEventListener('scroll', onResize);
      }
    };
  }, []);
}

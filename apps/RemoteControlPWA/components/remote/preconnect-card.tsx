'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';
import { Button } from '@/components/ui/button';

export function PreconnectCard() {
  const client = getRemoteClient();
  const {
    isStandaloneMode,
    isAuthenticated,
    installPromptEvent,
    joinToken,
    isPairingInFlight,
    pairingLinkURL,
    connectionStatusText
  } = useRemoteStore(
    useShallow((state) => ({
      isStandaloneMode: state.isStandaloneMode,
      isAuthenticated: state.isAuthenticated,
      installPromptEvent: state.installPromptEvent,
      joinToken: state.joinToken,
      isPairingInFlight: state.isPairingInFlight,
      pairingLinkURL: state.pairingLinkURL,
      connectionStatusText: state.connectionStatusText
    }))
  );

  const canPair = Boolean(joinToken) && !isPairingInFlight;
  const showHandoff = !isStandaloneMode && Boolean(pairingLinkURL);
  const showInstall = !isStandaloneMode;

  return (
    <section 
      id="preConnectPanel" 
      className="flex flex-col items-center justify-center min-h-[calc(var(--vvh)-var(--safe-top)-var(--safe-bottom))] px-4 w-full max-w-md mx-auto" 
      hidden={isAuthenticated}
    >
      <div className="bg-surface border border-line rounded-[24px] shadow-sm p-6 w-full flex flex-col gap-6" aria-labelledby="preconnectTitle">
        <div className="text-center flex flex-col gap-2">
          <div className="w-16 h-16 bg-accent/10 rounded-2xl mx-auto flex items-center justify-center mb-2">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-accent">
              <rect x="5" y="2" width="14" height="20" rx="2" ry="2"></rect>
              <path d="M12 18h.01"></path>
            </svg>
          </div>
          <h2 id="preconnectTitle" className="text-2xl font-bold tracking-tight text-fg">Pair this phone</h2>
          <p className="text-muted text-[15px] leading-relaxed">
            Scan the desktop QR code or paste a pair link, then approve on your Mac.
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Button id="scanQRButton" variant="primary" type="button" onClick={() => client.openQRScanner()}>
            Scan QR
          </Button>
          <Button id="pastePairLinkCardButton" type="button" onClick={() => void client.pasteJoinLinkFromClipboard()}>
            Paste Link
          </Button>
          <Button 
            id="preconnectPairButton" 
            type="button" 
            className="col-span-2" 
            disabled={!canPair} 
            variant={canPair ? 'primary' : 'default'}
            onClick={() => void client.pairDevice()}
          >
            Pair Device
          </Button>
        </div>

        {showInstall ? (
          <section className="bg-surface-alt rounded-2xl p-4 flex flex-col gap-3 border border-line mt-2">
            <div>
              <h3 className="text-base font-semibold text-fg">Install App</h3>
              <p id="installHint" className="text-sm text-muted mt-1 leading-relaxed">
                {installPromptEvent
                  ? 'Install now for the smoothest background reconnect experience.'
                  : 'Use your browser menu to add this app to your home screen.'}
              </p>
            </div>
            <Button 
              id="installButton" 
              variant="primary" 
              type="button" 
              hidden={!installPromptEvent} 
              onClick={() => void client.promptInstall()}
            >
              Add to Home Screen
            </Button>
          </section>
        ) : null}

        {showHandoff ? (
          <div className="bg-surface-alt rounded-2xl p-4 flex flex-col gap-3 border border-line mt-2">
            <p className="text-sm text-muted leading-relaxed">
              iPhone camera opens QR links in browser first. Open installed app and tap Paste Link.
            </p>
            <Button id="copyPairLinkButton" type="button" onClick={() => void client.copyPairingLinkToClipboard()}>
              Copy Pair Link
            </Button>
          </div>
        ) : null}

        {connectionStatusText && (
          <p className="text-sm text-muted text-center font-medium">{connectionStatusText}</p>
        )}
      </div>
    </section>
  );
}

'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

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
    <section id="preConnectPanel" className="preconnect-view" hidden={isAuthenticated}>
      <section className="panel preconnect-card" aria-labelledby="preconnectTitle">
        <h2 id="preconnectTitle">Pair this phone</h2>
        <p>Scan the desktop QR code or paste a pair link, then pair and approve on your Mac.</p>
        <div className="preconnect-actions">
          <button id="scanQRButton" className="primary" type="button" onClick={() => client.openQRScanner()}>
            Scan QR
          </button>
          <button id="pastePairLinkCardButton" type="button" onClick={() => void client.pasteJoinLinkFromClipboard()}>
            Paste Pair Link
          </button>
          <button id="preconnectPairButton" type="button" disabled={!canPair} onClick={() => void client.pairDevice()}>
            Pair Device
          </button>
        </div>

        {showInstall ? (
          <section className="welcome-card compact">
            <h3>Install to Home Screen</h3>
            <p>Home-screen mode reconnects more reliably on iPhone and Android.</p>
            <button id="installButton" className="primary" type="button" hidden={!installPromptEvent} onClick={() => void client.promptInstall()}>
              Add to Home Screen
            </button>
            <p id="installHint" className="install-hint">
              {installPromptEvent
                ? 'Install now for the smoothest pairing/reconnect experience.'
                : 'Use your browser menu to add this app to your home screen.'}
            </p>
          </section>
        ) : null}

        {showHandoff ? (
          <div className="handoff-note">
            <p>iPhone camera opens QR links in browser first. Open installed app and tap Paste Pair Link.</p>
            <button id="copyPairLinkButton" type="button" onClick={() => void client.copyPairingLinkToClipboard()}>
              Copy Pair Link
            </button>
          </div>
        ) : null}

        <p className="status">{connectionStatusText}</p>
      </section>
    </section>
  );
}

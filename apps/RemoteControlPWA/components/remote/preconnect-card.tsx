'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

export function PreconnectCard() {
  const client = getRemoteClient();
  const {
    arrivedFromQRCode,
    isAuthenticated,
    welcomeDismissed,
    installPromptEvent,
    joinToken,
    isPairingInFlight,
    connectionStatusText
  } = useRemoteStore(
    useShallow((state) => ({
      arrivedFromQRCode: state.arrivedFromQRCode,
      isAuthenticated: state.isAuthenticated,
      welcomeDismissed: state.welcomeDismissed,
      installPromptEvent: state.installPromptEvent,
      joinToken: state.joinToken,
      isPairingInFlight: state.isPairingInFlight,
      connectionStatusText: state.connectionStatusText
    }))
  );

  const showWelcome = arrivedFromQRCode && !isAuthenticated && !welcomeDismissed;
  const canPair = Boolean(joinToken) && !isPairingInFlight;

  return (
    <section id="preConnectPanel" className="preconnect-view" hidden={isAuthenticated}>
      <section className="panel preconnect-card" aria-labelledby="preconnectTitle">
        <h2 id="preconnectTitle">Pair to continue</h2>
        <p>Projects and chats appear after desktop approves pairing and this device connects.</p>
        <button
          id="preconnectPairButton"
          className="primary"
          type="button"
          disabled={!canPair}
          onClick={() => {
            client.openAccountSheet();
            void client.pairDevice();
          }}
        >
          Pair Device
        </button>
        <section id="welcomePanel" className="welcome-card" hidden={!showWelcome}>
          <h3>Welcome from QR</h3>
          <p>For best reliability, add this app to your home screen before pairing.</p>
          <ol className="welcome-steps">
            <li>Install to home screen.</li>
            <li>Tap <strong>Pair Device</strong> and approve on your Mac.</li>
            <li>This device reconnects automatically until revoked from desktop.</li>
          </ol>
          <div className="welcome-actions">
            <button id="installButton" className="primary" type="button" hidden={!installPromptEvent} onClick={() => void client.promptInstall()}>
              Add to Home Screen
            </button>
            <button id="dismissWelcomeButton" type="button" onClick={() => client.dismissWelcome()}>
              Continue in Browser
            </button>
          </div>
          <p id="installHint" className="install-hint">
            {installPromptEvent
              ? 'Tip: install now for faster launch and better background reconnect behavior.'
              : 'If your browser supports install, use the browser menu to add this app to your home screen.'}
          </p>
        </section>
        {!showWelcome ? <p className="status">{connectionStatusText}</p> : null}
      </section>
    </section>
  );
}

'use client';

import * as Dialog from '@radix-ui/react-dialog';
import jsQR from 'jsqr';
import { useEffect, useRef, useState } from 'react';
import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';

type BarcodeDetectorLike = {
  detect: (image: ImageBitmapSource) => Promise<Array<{ rawValue?: string }>>;
};

type BarcodeDetectorCtor = new (options?: { formats?: string[] }) => BarcodeDetectorLike;

function getBarcodeDetectorCtor() {
  if (typeof window === 'undefined') {
    return null;
  }
  return (window as Window & { BarcodeDetector?: BarcodeDetectorCtor }).BarcodeDetector || null;
}

export function QRScannerSheet() {
  const client = getRemoteClient();
  const isOpen = useRemoteStore((state) => state.isQRScannerOpen);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [errorText, setErrorText] = useState('');
  const [statusText, setStatusText] = useState('Point the camera at the desktop pairing QR code.');
  const [manualText, setManualText] = useState('');

  useEffect(() => {
    if (!isOpen || typeof navigator === 'undefined') {
      return;
    }

    let cancelled = false;
    let stream: MediaStream | null = null;
    let rafID = 0;
    let lastDecodeAt = 0;
    let detector: BarcodeDetectorLike | null = null;

    const stopAll = () => {
      if (rafID) {
        window.cancelAnimationFrame(rafID);
      }
      if (stream) {
        for (const track of stream.getTracks()) {
          track.stop();
        }
      }
      if (videoRef.current) {
        videoRef.current.srcObject = null;
      }
    };

    const decodeFrame = async () => {
      if (cancelled) {
        return;
      }
      const video = videoRef.current;
      const canvas = canvasRef.current;
      if (!video || !canvas) {
        rafID = window.requestAnimationFrame(() => {
          void decodeFrame();
        });
        return;
      }

      if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA && video.videoWidth > 0 && video.videoHeight > 0) {
        const now = Date.now();
        if (now - lastDecodeAt >= 220) {
          lastDecodeAt = now;
          let decoded: string | null = null;

          if (detector) {
            try {
              const detections = await detector.detect(video);
              if (Array.isArray(detections)) {
                decoded = detections.find((item) => typeof item?.rawValue === 'string' && item.rawValue.trim().length > 0)?.rawValue || null;
              }
            } catch {
              detector = null;
            }
          }

          if (!decoded) {
            const ctx = canvas.getContext('2d', { willReadFrequently: true });
            if (ctx) {
              canvas.width = video.videoWidth;
              canvas.height = video.videoHeight;
              ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
              const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
              const result = jsQR(imageData.data, imageData.width, imageData.height, {
                inversionAttempts: 'attemptBoth'
              });
              decoded = result?.data || null;
            }
          }

          if (decoded) {
            const imported = client.importJoinLink(decoded, 'scanner');
            if (imported) {
              client.closeQRScanner();
              return;
            }
            setErrorText('Scanned code is not a valid Codex pairing QR.');
          }
        }
      }

      rafID = window.requestAnimationFrame(() => {
        void decodeFrame();
      });
    };

    const start = async () => {
      setErrorText('');
      setStatusText('Point the camera at the desktop pairing QR code.');
      if (!navigator.mediaDevices?.getUserMedia) {
        setErrorText('Camera API is unavailable in this browser. Paste the pair link manually.');
        return;
      }

      const BarcodeDetectorClass = getBarcodeDetectorCtor();
      if (BarcodeDetectorClass) {
        try {
          detector = new BarcodeDetectorClass({ formats: ['qr_code'] });
        } catch {
          detector = null;
        }
      }

      try {
        stream = await navigator.mediaDevices.getUserMedia({
          audio: false,
          video: {
            facingMode: { ideal: 'environment' }
          }
        });

        if (cancelled) {
          stopAll();
          return;
        }

        const video = videoRef.current;
        if (!video) {
          setErrorText('Unable to start camera preview.');
          return;
        }

        video.srcObject = stream;
        await video.play();
        setStatusText('Scanning...');
        rafID = window.requestAnimationFrame(() => {
          void decodeFrame();
        });
      } catch {
        setErrorText('Camera permission denied or unavailable. Use Paste Pair Link instead.');
      }
    };

    void start();
    return () => {
      cancelled = true;
      stopAll();
    };
  }, [client, isOpen]);

  return (
    <Dialog.Root open={isOpen} onOpenChange={(open) => (open ? client.openQRScanner() : client.closeQRScanner())}>
      <Dialog.Portal>
        <Dialog.Overlay className="sheet-backdrop" />
        <Dialog.Content id="qrScannerSheet" className="sheet-card scanner-sheet" aria-labelledby="qrScannerTitle">
          <div className="sheet-head">
            <Dialog.Title asChild>
              <h2 id="qrScannerTitle">Scan QR code</h2>
            </Dialog.Title>
            <Dialog.Close asChild>
              <button id="closeQRScannerButton" className="ghost" type="button" aria-label="Close QR scanner">
                Close
              </button>
            </Dialog.Close>
          </div>

          <p className="pairing-hint">{statusText}</p>
          <div className="scanner-preview" aria-live="polite">
            <video ref={videoRef} className="scanner-video" autoPlay muted playsInline />
          </div>
          <canvas ref={canvasRef} className="scanner-canvas" aria-hidden="true" />

          {errorText ? <p className="status warn">{errorText}</p> : null}

          <div className="actions">
            <button
              id="pastePairLinkButton"
              type="button"
              onClick={async () => {
                const imported = await client.pasteJoinLinkFromClipboard();
                if (imported) {
                  client.closeQRScanner();
                }
              }}
            >
              Paste Pair Link
            </button>
            <button id="retryScannerButton" type="button" onClick={() => client.closeQRScanner()}>
              Close Scanner
            </button>
          </div>

          <label className="sr-only" htmlFor="manualPairLinkInput">
            Pair link
          </label>
          <textarea
            id="manualPairLinkInput"
            className="manual-pair-input"
            rows={3}
            placeholder="Or paste a full pair link here"
            value={manualText}
            onChange={(event) => setManualText(event.target.value)}
          />
          <button
            id="importManualPairLinkButton"
            type="button"
            onClick={() => {
              const imported = client.importJoinLink(manualText, 'manual');
              if (imported) {
                client.closeQRScanner();
              }
            }}
          >
            Import Pair Link
          </button>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

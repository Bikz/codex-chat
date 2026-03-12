'use client';

import * as Dialog from '@radix-ui/react-dialog';
import jsQR from 'jsqr';
import { useEffect, useRef, useState } from 'react';
import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { Button } from '@/components/ui/button';

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
        <Dialog.Content id="qrScannerSheet" className="sheet-card flex flex-col gap-4" aria-labelledby="qrScannerTitle">
          <div className="flex items-center justify-between mb-2">
            <Dialog.Title asChild>
              <h2 id="qrScannerTitle" className="text-xl font-bold tracking-tight text-fg truncate">Scan QR code</h2>
            </Dialog.Title>
            <Dialog.Close asChild>
              <Button id="closeQRScannerButton" variant="ghost" size="sm" type="button" aria-label="Close QR scanner" className="h-8 px-3 rounded-full text-[13px] bg-surface-alt">
                Cancel
              </Button>
            </Dialog.Close>
          </div>

          <p className="text-sm text-muted leading-relaxed px-1">{statusText}</p>
          
          <div className="w-full bg-surface-alt border border-line rounded-3xl overflow-hidden aspect-[4/3] min-h-[220px] relative shadow-inner" aria-live="polite">
            <video ref={videoRef} className="w-full h-full object-cover absolute inset-0" autoPlay muted playsInline />
          </div>
          <canvas ref={canvasRef} className="hidden" aria-hidden="true" />

          {errorText ? <p className="text-[13px] text-danger font-medium px-1 bg-danger/10 border border-danger/20 p-2 rounded-lg">{errorText}</p> : null}

          <div className="grid grid-cols-2 gap-2 mt-2">
            <Button
              id="pastePairLinkButton"
              type="button"
              className="w-full"
              onClick={async () => {
                const imported = await client.pasteJoinLinkFromClipboard();
                if (imported) {
                  client.closeQRScanner();
                }
              }}
            >
              Paste Link
            </Button>
            <Button id="retryScannerButton" type="button" className="w-full" onClick={() => client.closeQRScanner()}>
              Close Scanner
            </Button>
          </div>

          <div className="bg-surface-alt rounded-2xl p-3 border border-line flex flex-col gap-2 mt-2">
            <label className="sr-only" htmlFor="manualPairLinkInput">
              Pair link
            </label>
            <textarea
              id="manualPairLinkInput"
              className="w-full min-h-[72px] resize-y bg-surface text-fg border border-line rounded-xl px-3 py-2.5 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent leading-relaxed break-all font-mono"
              rows={3}
              placeholder="Or paste a full pair link here"
              value={manualText}
              onChange={(event) => setManualText(event.target.value)}
            />
            <Button
              id="importManualPairLinkButton"
              type="button"
              variant="primary"
              className="w-full"
              disabled={!manualText.trim()}
              onClick={() => {
                const imported = client.importJoinLink(manualText, 'manual');
                if (imported) {
                  client.closeQRScanner();
                }
              }}
            >
              Import Link
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

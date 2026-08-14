import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'

import { applicationServices } from '@/app/providers/application-services'
import { normalizeBarcode } from '@/domain/products/barcode'
import type { DiaryAddContext } from '@/features/diary/diary-add-routes'
import {
  getDiaryAddAmountPath,
  getDiaryAddContext,
  getDiaryAddSelectionPath,
} from '@/features/diary/diary-add-routes'

const supportedFormats = ['ean_13', 'ean_8', 'upc_a', 'upc_e']

interface BarcodeDetection {
  rawValue?: string
}

interface NativeBarcodeDetector {
  detect(source: HTMLVideoElement): Promise<BarcodeDetection[]>
}

interface NativeBarcodeDetectorConstructor {
  new(options?: { formats?: string[] }): NativeBarcodeDetector
}

interface ScannerNavigationState {
  scannerInHistory?: boolean
}

type ScannerContext = ManagementScannerContext | DiaryScannerContext

interface ManagementScannerContext {
  kind: 'management'
  returnTo: string
}

interface DiaryScannerContext {
  kind: 'diary'
  diary: DiaryAddContext
  returnTo: string
}

/** Local-only scanner: native BarcodeDetector when available, otherwise manual lookup. */
export function BarcodeScannerPage() {
  const { date, mealType } = useParams()
  const navigate = useNavigate()
  const location = useLocation()
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | undefined>(undefined)
  const frameRequestRef = useRef<number | undefined>(undefined)
  const scanLockedRef = useRef(false)
  const resolveBarcodeRef = useRef<(value: string) => void>(() => undefined)
  const [manualBarcode, setManualBarcode] = useState('')
  const [cameraMessage, setCameraMessage] = useState<string | undefined>()
  const [isCameraReady, setIsCameraReady] = useState(false)
  const [isLookingUp, setIsLookingUp] = useState(false)
  const [lookupError, setLookupError] = useState<string | undefined>()
  const [unknownBarcode, setUnknownBarcode] = useState<string | undefined>()

  const context = useMemo<ScannerContext | undefined>(() => {
    if (date === undefined && mealType === undefined) {
      return { kind: 'management', returnTo: '/products' }
    }

    const diary = getDiaryAddContext(date, mealType)
    return diary === undefined ? undefined : { kind: 'diary', diary, returnTo: getDiaryAddSelectionPath(diary) }
  }, [date, mealType])
  const navigationState = location.state as ScannerNavigationState | null

  const stopCamera = useCallback((): void => {
    if (frameRequestRef.current !== undefined) {
      window.cancelAnimationFrame(frameRequestRef.current)
      frameRequestRef.current = undefined
    }

    streamRef.current?.getTracks().forEach((track) => track.stop())
    streamRef.current = undefined

    const video = videoRef.current

    if (video !== null) {
      video.pause()
      video.srcObject = null
    }
  }, [])

  const resolveBarcode = useCallback(async (value: string): Promise<void> => {
    const barcode = normalizeBarcode(value)

    if (barcode === undefined) {
      setLookupError('Введите штрихкод.')
      return
    }

    if (context === undefined || scanLockedRef.current) {
      return
    }

    scanLockedRef.current = true
    stopCamera()
    setIsCameraReady(false)
    setIsLookingUp(true)
    setLookupError(undefined)

    try {
      const result = await applicationServices.barcode.lookup(barcode)

      if (result === undefined) {
        setUnknownBarcode(barcode)
        return
      }

      if (context.kind === 'management') {
        navigate(`/products/${result.product.id}`, { replace: true })
        return
      }

      navigate(getDiaryAddAmountPath(context.diary, 'product', result.product.id), {
        replace: true,
        state: { diaryAddSelectionInHistory: true },
      })
    } catch (error) {
      console.error('Failed to look up a barcode locally.', error)
      setLookupError('Не удалось найти продукт в локальной базе. Попробуйте ещё раз.')
      scanLockedRef.current = false
    } finally {
      setIsLookingUp(false)
    }
  }, [context, navigate, stopCamera])

  resolveBarcodeRef.current = (value) => {
    void resolveBarcode(value)
  }

  useEffect(() => {
    if (context === undefined) {
      return stopCamera
    }

    const BarcodeDetectorConstructor = getBarcodeDetectorConstructor()

    if (BarcodeDetectorConstructor === undefined) {
      setCameraMessage('Автоматическое распознавание недоступно в этом браузере. Введите штрихкод вручную.')
      return stopCamera
    }

    const detectorConstructor = BarcodeDetectorConstructor

    let isMounted = true

    async function startCamera(): Promise<void> {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: false,
          video: { facingMode: { ideal: 'environment' } },
        })

        if (!isMounted || scanLockedRef.current) {
          stream.getTracks().forEach((track) => track.stop())
          return
        }

        const video = videoRef.current

        if (video === null) {
          stream.getTracks().forEach((track) => track.stop())
          return
        }

        streamRef.current = stream
        video.srcObject = stream
        await video.play()

        if (!isMounted || scanLockedRef.current) {
          return
        }

        const detector = createBarcodeDetector(detectorConstructor)
        setIsCameraReady(true)

        const scanFrame = async (): Promise<void> => {
          if (!isMounted || scanLockedRef.current) {
            return
          }

          if (video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
            frameRequestRef.current = window.requestAnimationFrame(() => void scanFrame())
            return
          }

          try {
            const [result] = await detector.detect(video)

            if (result?.rawValue !== undefined) {
              resolveBarcodeRef.current(result.rawValue)
              return
            }
          } catch (error) {
            console.error('Barcode frame decoding failed.', error)
          }

          if (isMounted && !scanLockedRef.current) {
            frameRequestRef.current = window.requestAnimationFrame(() => void scanFrame())
          }
        }

        frameRequestRef.current = window.requestAnimationFrame(() => void scanFrame())
      } catch (error) {
        if (!isMounted) {
          return
        }

        setIsCameraReady(false)
        stopCamera()
        setCameraMessage(getCameraErrorMessage(error))
      }
    }

    void startCamera()

    return () => {
      isMounted = false
      stopCamera()
    }
  }, [context, stopCamera])

  function returnToPreviousPage(): void {
    stopCamera()

    if (navigationState?.scannerInHistory === true) {
      navigate(-1)
      return
    }

    navigate(context?.returnTo ?? '/products', { replace: true })
  }

  function createProductPath(barcode: string): string {
    const returnTo = context?.returnTo ?? '/products'
    return `/products/new?barcode=${encodeURIComponent(barcode)}&returnTo=${encodeURIComponent(returnTo)}`
  }

  if (context === undefined) {
    return (
      <section className="empty-state" aria-labelledby="barcode-scanner-context-title">
        <h1 id="barcode-scanner-context-title">Не удалось открыть сканер</h1>
        <p>Дата или приём пищи в ссылке некорректны.</p>
        <Link className="button button--secondary" to="/diary">К дневнику</Link>
      </section>
    )
  }

  return (
    <section className="barcode-scanner" aria-labelledby="barcode-scanner-title">
      <header className="diary-add-page__header">
        <button className="back-link diary-add-page__back" type="button" onClick={returnToPreviousPage}>‹ {context.kind === 'diary' ? 'Выбор еды' : 'Продукты'}</button>
      </header>
      <div className="barcode-scanner__scroll">
        <div className="diary-add-page__intro">
          <h1 id="barcode-scanner-title">Сканировать штрихкод</h1>
          <p>{context.kind === 'diary' ? 'Найденный продукт будет добавлен в выбранный приём пищи.' : 'Поиск выполняется только в вашей локальной базе.'}</p>
        </div>

        {unknownBarcode === undefined ? (
          <>
            <div className={isCameraReady ? 'barcode-scanner__preview barcode-scanner__preview--ready' : 'barcode-scanner__preview'}>
              <video ref={videoRef} autoPlay muted playsInline aria-label="Предпросмотр камеры для сканирования штрихкода" />
              {isCameraReady ? <span>Наведите камеру на штрихкод</span> : <span>{cameraMessage ?? 'Запуск камеры…'}</span>}
            </div>
            <form className="barcode-scanner__manual" onSubmit={(event) => {
              event.preventDefault()
              void resolveBarcode(manualBarcode)
            }}>
              <label htmlFor="manual-barcode">Ввести штрихкод вручную</label>
              <div>
                <input id="manual-barcode" type="text" inputMode="numeric" autoComplete="off" value={manualBarcode} onChange={(event) => setManualBarcode(event.target.value)} />
                <button className="button button--primary" type="submit" disabled={isLookingUp}>{isLookingUp ? 'Поиск…' : 'Найти'}</button>
              </div>
              {lookupError === undefined ? null : <p className="field-error" role="alert">{lookupError}</p>}
            </form>
          </>
        ) : (
          <section className="empty-state barcode-scanner__unknown" aria-labelledby="unknown-barcode-title">
            <h2 id="unknown-barcode-title">Продукт не найден</h2>
            <p>Штрихкод <strong>{unknownBarcode}</strong> отсутствует в локальной базе.</p>
            <Link className="button button--primary" to={createProductPath(unknownBarcode)}>Создать продукт</Link>
            <button className="button button--secondary" type="button" onClick={returnToPreviousPage}>Назад</button>
          </section>
        )}
      </div>
    </section>
  )
}

function getBarcodeDetectorConstructor(): NativeBarcodeDetectorConstructor | undefined {
  return (window as typeof window & { BarcodeDetector?: NativeBarcodeDetectorConstructor }).BarcodeDetector
}

function createBarcodeDetector(BarcodeDetectorConstructor: NativeBarcodeDetectorConstructor): NativeBarcodeDetector {
  try {
    return new BarcodeDetectorConstructor({ formats: supportedFormats })
  } catch {
    return new BarcodeDetectorConstructor()
  }
}

function getCameraErrorMessage(error: unknown): string {
  if (error instanceof DOMException && (error.name === 'NotAllowedError' || error.name === 'SecurityError')) {
    return 'Доступ к камере не разрешён. Введите штрихкод вручную.'
  }

  return 'Камера недоступна. Введите штрихкод вручную.'
}

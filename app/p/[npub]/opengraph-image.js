import { ImageResponse } from 'next/og'

export const runtime = 'edge'
export const alt = 'ぬるぬるでプロフィールを見てね'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

function shortNpub(value) {
  if (!value) return ''
  const raw = String(value)
  return raw.length > 28 ? `${raw.slice(0, 14)}…${raw.slice(-10)}` : raw
}

export default function Image({ params }) {
  const npub = shortNpub(params?.npub)
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          background: '#050505',
          color: 'white',
          padding: 72,
          fontFamily: 'sans-serif',
        }}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            borderRadius: 44,
            background: 'linear-gradient(135deg, #111 0%, #161616 55%, #06391d 100%)',
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'center',
            padding: 72,
            boxShadow: '0 24px 80px rgba(0,0,0,.45)',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 28, marginBottom: 44 }}>
            <div
              style={{
                width: 112,
                height: 112,
                borderRadius: 28,
                background: '#06C755',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 64,
                fontWeight: 900,
              }}
            >ぬ</div>
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              <div style={{ color: '#06C755', fontSize: 30, fontWeight: 800 }}>ぬるぬる</div>
              <div style={{ color: '#b8b8b8', fontSize: 24 }}>Nostr client for Japan</div>
            </div>
          </div>
          <div style={{ fontSize: 58, lineHeight: 1.15, fontWeight: 900, marginBottom: 24 }}>
            プロフィールを見てね
          </div>
          <div style={{ fontSize: 32, lineHeight: 1.4, color: '#d0d0d0', marginBottom: 36 }}>
            リンクから始めると、このユーザーをフォローした状態でスタートできます。
          </div>
          <div style={{ fontSize: 26, color: '#8f8f8f' }}>{npub}</div>
        </div>
      </div>
    ),
    size
  )
}

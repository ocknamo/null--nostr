import { ImageResponse } from 'next/og'

export const runtime = 'edge'
export const alt = 'ぬるぬるの投稿'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

function shortId(value) {
  if (!value) return ''
  const raw = String(value)
  return raw.length > 24 ? `${raw.slice(0, 12)}…${raw.slice(-10)}` : raw
}

export default function Image({ params }) {
  const id = shortId(params?.eventId)
  return new ImageResponse(
    (
      <div style={{ width: '100%', height: '100%', display: 'flex', background: '#050505', color: 'white', padding: 72, fontFamily: 'sans-serif' }}>
        <div style={{ width: '100%', height: '100%', borderRadius: 44, background: 'linear-gradient(135deg, #111 0%, #161616 55%, #06391d 100%)', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: 72 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 28, marginBottom: 44 }}>
            <div style={{ width: 112, height: 112, borderRadius: 28, background: '#06C755', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 64, fontWeight: 900 }}>ぬ</div>
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              <div style={{ color: '#06C755', fontSize: 30, fontWeight: 800 }}>ぬるぬる</div>
              <div style={{ color: '#b8b8b8', fontSize: 24 }}>Nostr post preview</div>
            </div>
          </div>
          <div style={{ fontSize: 58, lineHeight: 1.15, fontWeight: 900, marginBottom: 24 }}>投稿を見てね</div>
          <div style={{ fontSize: 32, lineHeight: 1.4, color: '#d0d0d0', marginBottom: 36 }}>ブログやSNSで埋め込みプレビューできる共有リンクです。</div>
          <div style={{ fontSize: 26, color: '#8f8f8f' }}>{id}</div>
        </div>
      </div>
    ),
    size
  )
}

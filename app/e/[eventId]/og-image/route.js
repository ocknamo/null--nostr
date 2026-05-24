import { ImageResponse } from 'next/og'
import { getEventPreview } from '../preview-data'

export const runtime = 'nodejs'

function shortId(value) {
  if (!value) return ''
  const raw = String(value)
  return raw.length > 24 ? `${raw.slice(0, 12)}…${raw.slice(-10)}` : raw
}

export async function GET(_request, { params }) {
  const resolvedParams = await params
  const eventId = String(resolvedParams?.eventId || '')
  const preview = await getEventPreview(eventId)
  const author = preview?.authorName || 'ぬるぬる'
  const content = preview?.content || 'ぬるぬるで投稿を見てね。'
  const id = shortId(eventId)

  return new ImageResponse(
    (
      <div style={{ width: '100%', height: '100%', display: 'flex', background: '#050505', color: 'white', padding: 64, fontFamily: 'sans-serif' }}>
        <div style={{ width: '100%', height: '100%', borderRadius: 44, background: 'linear-gradient(135deg, #111 0%, #171717 62%, #07381e 100%)', display: 'flex', flexDirection: 'column', padding: 64 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 24, marginBottom: 42 }}>
            <div style={{ width: 88, height: 88, borderRadius: 24, background: '#06C755', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 52, fontWeight: 900 }}>ぬ</div>
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              <div style={{ color: '#06C755', fontSize: 30, fontWeight: 900 }}>ぬるぬるの投稿</div>
              <div style={{ color: '#b8b8b8', fontSize: 24 }}>{author}</div>
            </div>
          </div>
          <div style={{ display: 'flex', flex: 1, alignItems: 'center' }}>
            <div style={{ fontSize: 48, lineHeight: 1.28, fontWeight: 800, color: '#f4f4f4', whiteSpace: 'pre-wrap' }}>{content}</div>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#8f8f8f', fontSize: 24, marginTop: 34 }}>
            <div>https://www.nullnull.app/e/{id}</div>
            <div style={{ color: '#06C755', fontWeight: 800 }}>開く →</div>
          </div>
        </div>
      </div>
    ),
    { width: 1200, height: 630 },
  )
}

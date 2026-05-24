import EventInviteClient from './EventInviteClient'
import { getEventPreview } from './preview-data'

const SITE_URL = 'https://www.nullnull.app'

function eventUrl(eventId) {
  return `${SITE_URL}/e/${encodeURIComponent(eventId || '')}`
}

export async function generateMetadata({ params }) {
  const resolvedParams = await params
  const eventId = String(resolvedParams?.eventId || '')
  const url = eventUrl(eventId)
  const preview = await getEventPreview(eventId)
  const title = preview ? `${preview.authorName} の投稿` : 'ぬるぬるの投稿'
  const description = preview?.content || 'ぬるぬるで投稿を見てね。'
  const image = `${url}/og-image`
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: {
      title,
      description,
      url,
      siteName: 'ぬるぬる',
      type: 'article',
      images: [{ url: image, width: 1200, height: 630, alt: description }],
    },
    twitter: {
      card: 'summary_large_image',
      title,
      description,
      images: [image],
    },
  }
}

export default async function EventPage({ params }) {
  const resolvedParams = await params
  return <EventInviteClient eventId={resolvedParams?.eventId || ''} />
}

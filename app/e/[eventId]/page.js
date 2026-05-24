import EventInviteClient from './EventInviteClient'

const SITE_URL = 'https://www.nullnull.app'

function eventUrl(eventId) {
  return `${SITE_URL}/e/${encodeURIComponent(eventId || '')}`
}

export async function generateMetadata({ params }) {
  const eventId = String(params?.eventId || '')
  const url = eventUrl(eventId)
  const title = 'ぬるぬるの投稿'
  const description = 'ぬるぬるで投稿を見てね。'
  const image = `${url}/opengraph-image`
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
      images: [{ url: image, width: 1200, height: 630, alt: title }],
    },
    twitter: {
      card: 'summary_large_image',
      title,
      description,
      images: [image],
    },
  }
}

export default function EventPage({ params }) {
  return <EventInviteClient eventId={params?.eventId || ''} />
}

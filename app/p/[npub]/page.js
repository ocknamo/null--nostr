import ProfileInviteClient from './ProfileInviteClient'

const SITE_URL = 'https://www.nullnull.app'

function canonicalNpub(value) {
  if (!value) return ''
  return String(value).trim()
}

export async function generateMetadata({ params }) {
  const npub = canonicalNpub(params?.npub)
  const url = `${SITE_URL}/p/${encodeURIComponent(npub)}`
  const title = 'ぬるぬるでプロフィールを見てね'
  const description = 'リンクから始めると、このユーザーをフォローした状態でぬるぬるをスタートできます。'
  const image = `${SITE_URL}/p/${encodeURIComponent(npub)}/opengraph-image`

  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: {
      title,
      description,
      url,
      siteName: 'ぬるぬる',
      type: 'profile',
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

export default function ProfileInvitePage({ params }) {
  return <ProfileInviteClient npubOrHex={params?.npub || ''} />
}

export const dynamic = 'force-static'

const body = {
  applinks: {
    apps: [],
    details: [
      {
        appID: '66G7S3P755.io.nurunuru.app',
        paths: ['/p/*', '/e/*'],
        components: [{ '/': '/p/*' }, { '/': '/e/*' }],
      },
    ],
  },
  webcredentials: {
    apps: ['66G7S3P755.io.nurunuru.app'],
  },
}

export async function GET() {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  })
}

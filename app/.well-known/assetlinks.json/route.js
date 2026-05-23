export const dynamic = 'force-static'

const body = [
  {
    relation: [
      'delegate_permission/common.handle_all_urls',
      'delegate_permission/common.get_login_creds',
    ],
    target: {
      namespace: 'android_app',
      package_name: 'io.nurunuru.app',
      sha256_cert_fingerprints: [
        'REPLACE_WITH_YOUR_SIGNING_CERTIFICATE_SHA256',
      ],
    },
  },
]

export async function GET() {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  })
}

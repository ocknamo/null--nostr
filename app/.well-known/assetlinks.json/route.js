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
        // Local debug keystore used by `./gradlew assembleDebug` / adb install.
        '45:CD:CB:AD:A9:F4:35:A0:A3:62:80:05:9C:02:FE:7A:B1:7C:CB:09:CE:05:E2:93:BB:C6:CF:08:27:04:05:60',
        // TODO: Add the Play App Signing SHA-256 fingerprint before production release.
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

/**
 * Shared Nostr event kind registry for Web.
 *
 * Keep names aligned with Android NostrKind and iOS NostrKind.
 * Constants-only entries do not imply full feature support.
 */

export const NOSTR_KINDS = Object.freeze({
  METADATA: 0,
  TEXT_NOTE: 1,
  RECOMMEND_RELAY: 2,
  CONTACTS: 3,
  ENCRYPTED_DM: 4,
  DELETE: 5,
  REPOST: 6,
  REACTION: 7,
  BADGE_AWARD: 8,
  SEAL: 13,
  DIRECT_MESSAGE: 14,          // NIP-17 chat message
  FILE_MESSAGE: 15,            // NIP-17 file message
  GENERIC_REPOST: 16,
  VIDEO_EVENT: 21,             // NIP-71 regular video event
  PORTRAIT_SHORT_VIDEO: 22,    // NIP-71 short-form portrait video event
  CHANNEL_CREATE: 40,
  CHANNEL_META: 41,
  CHANNEL_MESSAGE: 42,
  CHANNEL_HIDE: 43,
  CHANNEL_MUTE: 44,
  REQUEST_TO_VANISH: 62,       // NIP-62 request to vanish
  GIFT_WRAP: 1059,
  REPORT: 1984,
  LABEL: 1985,
  ZAP_REQUEST: 9734,
  ZAP: 9735,
  MUTE_LIST: 10000,
  PIN_LIST: 10001,
  RELAY_LIST: 10002,
  BOOKMARKS: 10003,
  COMMUNITIES: 10004,
  PUBLIC_CHATS: 10005,
  BLOCKED_RELAYS: 10006,
  SEARCH_RELAYS: 10007,
  USER_GROUPS: 10009,
  INTERESTS: 10015,
  EMOJI_LIST: 10030,
  DM_RELAY_LIST: 10050,        // NIP-17 DM receiving relay list
  BLOSSOM_USER_SERVER_LIST: 10063,
  NSITE_ROOT: 15128,           // NIP-5A root nsite manifest
  CLIENT_AUTH: 22242,          // NIP-42 relay authentication
  NOSTR_CONNECT: 24133,        // NIP-46 / Nostr Connect
  BLOSSOM_AUTH: 24242,
  NIP98_AUTH: 27235,
  LONG_FORM: 30023,
  DRAFT_LONG_FORM: 30024,
  EMOJI_SET: 30030,
  APP_DATA: 30078,
  LIVE_EVENT: 30311,
  CLASSIFIED: 30402,
  CALENDAR_EVENT: 31922,
  CALENDAR_RSVP: 31925,
  HANDLER_INFO: 31990,
  NSITE_LEGACY: 34128,         // NIP-5A legacy nsite manifest (deprecated upstream)
  ADDRESSABLE_VIDEO: 34235,    // NIP-71 addressable video event
  ADDRESSABLE_SHORT_VIDEO: 34236,
  NSITE_NAMED: 35128,          // NIP-5A named nsite manifest
})

export default NOSTR_KINDS

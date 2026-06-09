/**
 * Application Constants
 *
 * Centralized configuration for all magic numbers and settings.
 * Some constants are auto-generated from design-tokens/constants.json.
 */

import {
  WS_CONFIG as WS_CONFIG_GEN,
  CACHE_CONFIG as CACHE_CONFIG_GEN,
  DEDUP_CONFIG as DEDUP_CONFIG_GEN,
  UPLOAD_CONFIG as UPLOAD_CONFIG_GEN,
  UI_CONFIG as UI_CONFIG_GEN,
  TIME as TIME_GEN,
  ERROR_MESSAGES as ERROR_MESSAGES_GEN,
  ENGAGEMENT_WEIGHTS,
  NEGATIVE_WEIGHTS,
  SOCIAL_BOOST,
  TIME_DECAY
} from './constants.generated'
import { NOSTR_KINDS } from './nostr-kinds'

export const WS_CONFIG = WS_CONFIG_GEN
export const CACHE_CONFIG = CACHE_CONFIG_GEN
export const DEDUP_CONFIG = DEDUP_CONFIG_GEN
export const UPLOAD_CONFIG = UPLOAD_CONFIG_GEN
export const UI_CONFIG = UI_CONFIG_GEN
export const TIME = TIME_GEN
export const ERROR_MESSAGES = ERROR_MESSAGES_GEN

export {
  ENGAGEMENT_WEIGHTS,
  NEGATIVE_WEIGHTS,
  SOCIAL_BOOST,
  TIME_DECAY
}

// ============================================
// Nostr Protocol Constants
// ============================================
export { NOSTR_KINDS } from './nostr-kinds'

// ============================================
// Connection State (Managed Manually)
// ============================================
export const CONNECTION_STATE = {
  DISCONNECTED: 'disconnected',
  CONNECTING: 'connecting',
  CONNECTED: 'connected',
  RECONNECTING: 'reconnecting',
  ERROR: 'error',
}

// ============================================
// Default Export
// ============================================
export default {
  WS_CONFIG,
  CACHE_CONFIG,
  DEDUP_CONFIG,
  UPLOAD_CONFIG,
  UI_CONFIG,
  TIME,
  NOSTR_KINDS,
  ERROR_MESSAGES,
  CONNECTION_STATE,
  ENGAGEMENT_WEIGHTS,
  NEGATIVE_WEIGHTS,
  SOCIAL_BOOST,
  TIME_DECAY
}

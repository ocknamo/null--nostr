'use client'

import { useState, useEffect } from 'react'
import MiniAppModal from './MiniAppModal'

// Import mini app components
import ZapSettings from './miniapps/ZapSettings'
import RelaySettings from './miniapps/RelaySettings'
import UploadSettings from './miniapps/UploadSettings'
import MuteList from './miniapps/MuteList'
import EmojiSettings from './miniapps/EmojiSettings'
import BadgeSettings from './miniapps/BadgeSettings'
import ElevenLabsSettings from './miniapps/ElevenLabsSettings'
import SchedulerApp from './miniapps/SchedulerApp'
import EventBackupApp from './miniapps/EventBackupApp'
import VanishRequest from './miniapps/VanishRequest'

const APPS_METADATA = [
  {
    id: 'emoji',
    name: 'カスタム絵文字',
    description: '投稿やリアクションに使える絵文字を管理・追加',
    category: 'entertainment',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>
      </svg>
    )
  },
  {
    id: 'badge',
    name: 'プロフィールバッジ',
    description: 'プロフィールに表示するバッジを設定・管理',
    category: 'entertainment',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <circle cx="12" cy="8" r="6"/><path d="M12 14v8"/><path d="M9 18l3 3 3-3"/>
      </svg>
    )
  },
  {
    id: 'scheduler',
    name: '調整くん',
    description: 'オフ会や会議の予定を簡単に調整',
    category: 'entertainment',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>
      </svg>
    )
  },
  {
    id: 'zap',
    name: 'Zap設定',
    description: 'デフォルトのZap金額をクイック設定',
    category: 'tools',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
      </svg>
    )
  },
  {
    id: 'relay',
    name: 'リレー設定',
    description: '地域に基づいた最適なリレーを自動設定',
    category: 'tools',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <circle cx="12" cy="12" r="3"/><path d="M12 2v4m0 12v4M2 12h4m12 0h4"/><circle cx="12" cy="12" r="8" strokeDasharray="4 2"/>
      </svg>
    )
  },
  {
    id: 'upload',
    name: 'アップロード設定',
    description: '画像のアップロード先サーバーを選択',
    category: 'tools',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/>
      </svg>
    )
  },
  {
    id: 'mute',
    name: 'ミュートリスト',
    description: '不快なユーザーやキーワードを非表示に管理',
    category: 'tools',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
      </svg>
    )
  },
  {
    id: 'elevenlabs',
    name: '音声入力設定',
    description: 'ElevenLabs Scribeによる高精度な音声入力',
    category: 'tools',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>
      </svg>
    )
  },
  {
    id: 'backup',
    name: 'バックアップ',
    description: '自分の投稿データをJSON形式でエクスポート',
    category: 'tools',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>
      </svg>
    )
  },
  {
    id: 'vanish',
    name: '削除リクエスト',
    description: 'リレーに対して全データの削除を要求',
    category: 'tools',
    icon: (className) => (
      <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <path d="M3 6h18"/><path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6"/><path d="M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/>
      </svg>
    )
  }
]

export default function MiniAppTab({ pubkey }) {
  const [activeCategory, setActiveCategory] = useState('all')
  const [searchQuery, setSearchQuery] = useState('')
  const [favoriteApps, setFavoriteApps] = useState([])
  const [selectedApp, setSelectedApp] = useState(null)
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [showExternalAdd, setShowExternalAdd] = useState(false)
  const [externalAppName, setExternalAppName] = useState('')
  const [externalAppUrl, setExternalAppUrl] = useState('')

  useEffect(() => {
    const savedFavorites = localStorage.getItem('favoriteMiniApps')
    if (savedFavorites) {
      try {
        setFavoriteApps(JSON.parse(savedFavorites))
      } catch (e) {
        console.error(e)
      }
    }
  }, [])

  const saveFavorites = (apps) => {
    setFavoriteApps(apps)
    localStorage.setItem('favoriteMiniApps', JSON.stringify(apps))
  }

  const handleToggleFavorite = (appId, appName, appType = 'internal', url = null) => {
    if (favoriteApps.some(a => a.id === appId)) {
      saveFavorites(favoriteApps.filter(a => a.id !== appId))
    } else {
      saveFavorites([...favoriteApps, { id: appId, name: appName, type: appType, url }])
    }
  }

  const handleAddExternal = () => {
    if (!externalAppUrl.trim().startsWith('http')) return
    const appId = 'external_' + Date.now()
    const appName = externalAppName.trim() || new URL(externalAppUrl).hostname
    const newApp = { id: appId, name: appName, type: 'external', url: externalAppUrl }
    saveFavorites([...favoriteApps, newApp])
    setExternalAppName('')
    setExternalAppUrl('')
    setShowExternalAdd(false)
  }

  const openApp = (app) => {
    if (app.type === 'external') {
      window.open(app.url, '_blank', 'noopener,noreferrer')
    } else {
      setSelectedApp(app)
      setIsModalOpen(true)
    }
  }

  const filteredApps = APPS_METADATA.filter(app => {
    const matchesCategory = activeCategory === 'all' || app.category === activeCategory
    const matchesSearch = app.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          app.description.toLowerCase().includes(searchQuery.toLowerCase())
    return matchesCategory && matchesSearch
  })

  const renderAppContent = () => {
    if (!selectedApp) return null
    switch (selectedApp.id) {
      case 'emoji': return <EmojiSettings pubkey={pubkey} />
      case 'badge': return <BadgeSettings pubkey={pubkey} />
      case 'scheduler': return <SchedulerApp pubkey={pubkey} />
      case 'zap': return <ZapSettings />
      case 'relay': return <RelaySettings pubkey={pubkey} />
      case 'upload': return <UploadSettings />
      case 'mute': return <MuteList pubkey={pubkey} />
      case 'elevenlabs': return <ElevenLabsSettings />
      case 'backup': return <EventBackupApp pubkey={pubkey} />
      case 'vanish': return <VanishRequest pubkey={pubkey} />
      default: return null
    }
  }

  return (
    <div className="min-h-screen pb-20 bg-[var(--bg-primary)]">
      {/* Header */}
      <header className="sticky top-0 z-40 header-blur border-b border-[var(--border-color)]">
        <div className="flex items-center justify-between px-4 h-14">
          <div className="flex items-center gap-1">
            <h1 className="text-lg font-bold text-[var(--text-primary)]">ミニアプリ</h1>
          </div>
        </div>
      </header>

      <div className="p-4 space-y-6">
        {/* Search Bar */}
        <div className="relative">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="ミニアプリを検索"
            className="w-full h-10 pl-10 pr-4 bg-[var(--bg-secondary)] text-[var(--text-primary)] rounded-xl text-sm focus:outline-none focus:ring-1 focus:ring-[var(--line-green)]"
          />
          <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--text-tertiary)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/>
          </svg>
        </div>

        {/* History / Favorites */}
        {favoriteApps.length > 0 && (
          <section>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-bold text-[var(--text-primary)]">履歴・おすすめ</h2>
              <svg className="w-4 h-4 text-[var(--text-tertiary)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <polyline points="9 18 15 12 9 6"/>
              </svg>
            </div>
            <div className="flex gap-4 overflow-x-auto pb-4 scrollbar-hide">
              {favoriteApps.map(app => (
                <button key={app.id} onClick={() => openApp(app)} className="flex flex-col items-center gap-1.5 min-w-[64px] group">
                  <div className="w-14 h-14 rounded-full bg-[var(--bg-secondary)] flex items-center justify-center group-active:scale-95 transition-transform shadow-sm border border-[var(--border-color)]">
                    {app.type === 'external' ? (
                      <svg className="w-6 h-6 text-[var(--text-secondary)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
                        <path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6M15 3h6v6M10 14L21 3"/>
                      </svg>
                    ) : (
                      APPS_METADATA.find(a => a.id === app.id)?.icon("w-7 h-7 text-[var(--text-secondary)]")
                    )}
                  </div>
                  <span className="text-[10px] text-[var(--text-primary)] text-center line-clamp-1 w-16 font-medium">{app.name}</span>
                </button>
              ))}
            </div>
          </section>
        )}

        {/* Category Tabs */}
        <div className="flex gap-2 border-b border-[var(--border-color)] overflow-x-auto scrollbar-hide">
          {[
            { id: 'all', name: 'すべて' },
            { id: 'entertainment', name: 'エンタメ' },
            { id: 'tools', name: 'ツール' }
          ].map(cat => (
            <button
              key={cat.id}
              onClick={() => setActiveCategory(cat.id)}
              className={`pb-2 px-1 text-sm font-medium transition-colors relative ${activeCategory === cat.id ? 'text-[var(--text-primary)]' : 'text-[var(--text-tertiary)]'}`}
            >
              {cat.name}
              {activeCategory === cat.id && <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-[var(--text-primary)]" />}
            </button>
          ))}
        </div>

        {/* App List */}
        <div className="space-y-4">
          {filteredApps.map(app => (
            <div key={app.id} className="flex items-center gap-4 group">
              <button onClick={() => openApp(app)} className="flex-1 flex items-center gap-4 text-left">
                <div className="w-14 h-14 rounded-2xl bg-[var(--bg-secondary)] flex items-center justify-center flex-shrink-0 shadow-sm">
                  {app.icon("w-7 h-7 text-[var(--text-secondary)]")}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <h3 className="font-bold text-[var(--text-primary)] truncate">{app.name}</h3>
                    <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${app.category === 'entertainment' ? 'bg-purple-100 text-purple-600 dark:bg-purple-900/30 dark:text-purple-400' : 'bg-blue-100 text-blue-600 dark:bg-blue-900/30 dark:text-blue-400'}`}>
                      {app.category === 'entertainment' ? 'エンタメ' : 'ツール'}
                    </span>
                  </div>
                  <p className="text-xs text-[var(--text-tertiary)] line-clamp-1 mt-0.5">{app.description}</p>
                </div>
              </button>
              <button
                onClick={() => handleToggleFavorite(app.id, app.name)}
                className={`p-2 transition-colors ${favoriteApps.some(a => a.id === app.id) ? 'text-yellow-500' : 'text-[var(--text-tertiary)]'}`}
              >
                <svg className="w-5 h-5" fill={favoriteApps.some(a => a.id === app.id) ? "currentColor" : "none"} viewBox="0 0 24 24" stroke="currentColor" strokeWidth="2">
                  <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
                </svg>
              </button>
            </div>
          ))}

          {/* External App Add Button */}
          <div className="pt-4 border-t border-[var(--border-color)]">
            {showExternalAdd ? (
              <div className="space-y-3 p-4 bg-[var(--bg-secondary)] rounded-2xl animate-fadeIn">
                <input
                  type="text"
                  value={externalAppName}
                  onChange={(e) => setExternalAppName(e.target.value)}
                  placeholder="アプリ名 (任意)"
                  className="w-full input-line text-sm"
                />
                <div className="flex gap-2">
                  <input
                    type="url"
                    value={externalAppUrl}
                    onChange={(e) => setExternalAppUrl(e.target.value)}
                    placeholder="https://..."
                    className="flex-1 input-line text-sm"
                  />
                  <button onClick={handleAddExternal} disabled={!externalAppUrl.trim().startsWith('http')} className="btn-line text-sm px-4">
                    追加
                  </button>
                </div>
                <button onClick={() => setShowExternalAdd(false)} className="w-full text-xs text-[var(--text-tertiary)] hover:underline">
                  キャンセル
                </button>
              </div>
            ) : (
              <button
                onClick={() => setShowExternalAdd(true)}
                className="w-full py-4 flex items-center justify-center gap-2 text-sm text-[var(--text-secondary)] border-2 border-dashed border-[var(--border-color)] rounded-2xl hover:bg-[var(--bg-secondary)] transition-colors"
              >
                <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
                </svg>
                外部ミニアプリを追加
              </button>
            )}
          </div>
        </div>
      </div>

      <MiniAppModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        title={selectedApp?.name}
      >
        {renderAppContent()}
      </MiniAppModal>
    </div>
  )
}

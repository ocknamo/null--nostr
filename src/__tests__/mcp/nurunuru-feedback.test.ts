import { describe, expect, it } from 'vitest'

const modPromise = import('../../../scripts/mcp/nurunuru-feedback.mjs')

describe('nurunuru feedback MCP helpers', () => {
  it('builds a NIP-50 search filter with structured constraints', async () => {
    const { buildNip50Filter } = await modPromise
    const filter = buildNip50Filter({ query: 'ぬるぬる バグ', kinds: [1, 30023], limit: 999, since: 100, tags: { t: ['nurunuru'] } })
    expect(filter).toEqual({ search: 'ぬるぬる バグ', kinds: [1, 30023], limit: 100, since: 100, '#t': ['nurunuru'] })
  })

  it('uses feedback search queries focused on nullnull clients and via strings', async () => {
    const { defaults } = await modPromise
    expect(defaults.feedbackQueries).toEqual(['ぬるぬる', '#ぬるぬるはじめました', 'nullnull Android', 'nullnull iOS', 'nullnull', 'via nullnull Android', 'via nullnull iOS', 'via nullnull'])
  })

  it('classifies high-severity Japanese crash feedback', async () => {
    const { classifyFeedbackText } = await modPromise
    const result = classifyFeedbackText('Androidで画像投稿するとクラッシュして投稿できない')
    expect(result.type).toBe('bug')
    expect(result.severity).toBe('p0')
    expect(result.platform).toBe('android')
    expect(result.featureArea).toBe('post_composer')
    expect(result.labels).toContain('type:bug')
    expect(result.labels).toContain('platform:android')
  })

  it('infers platform from client tags and classifies URL/OGP feedback as post content', async () => {
    const { classifyFeedbackEvent } = await modPromise
    const result = classifyFeedbackEvent({ content: '#ぬるぬる URLリンクがクリックできない。OGPが出てる場合はそっちから飛べる', tags: [['client', 'nullnull Android']] })
    expect(result.classification.type).toBe('bug')
    expect(result.classification.platform).toBe('android')
    expect(result.classification.featureArea).toBe('post_content')
    expect(result.classification.labels).toContain('area:post_content')
  })

  it('infers platform from JSON via metadata when present in event content', async () => {
    const { classifyFeedbackEvent } = await modPromise
    const result = classifyFeedbackEvent({ content: JSON.stringify({ via: 'nullnull iOS', text: '投稿できない' }) })
    expect(result.classification.platform).toBe('ios')
    expect(result.classification.type).toBe('bug')
  })

  it('classifies signing failures separately from login/auth', async () => {
    const { classifyFeedbackText } = await modPromise
    const result = classifyFeedbackText('署名機能が動かないと出て投稿できない')
    expect(result.type).toBe('bug')
    expect(result.severity).toBe('p1')
    expect(result.featureArea).toBe('signing')
  })

  it('groups similar feedback and drafts issue markdown', async () => {
    const { buildIssueDraft, groupFeedbackItems, classifyFeedbackText } = await modPromise
    const items = [
      { text: 'iOSで通知がこない', classification: classifyFeedbackText('iOSで通知がこない') },
      { text: 'iPhoneで通知こないです', classification: classifyFeedbackText('iPhoneで通知こないです') },
    ]
    const groups = groupFeedbackItems(items)
    const draft = buildIssueDraft(groups[0], { projectName: 'ぬるぬる' })
    expect(groups[0].count).toBe(2)
    expect(draft.title).toContain('ios')
    expect(draft.body).toContain('User words')
    expect(draft.body).toContain('通知')
    expect(draft.labels).toContain('source:nostr')
  })

  it('does not over-group vague unknown feedback', async () => {
    const { classifyFeedbackText, groupFeedbackItems } = await modPromise
    const items = [
      { text: 'ぬるぬるは壊れている', event: { id: 'a'.repeat(64) }, classification: classifyFeedbackText('ぬるぬるは壊れている') },
      { text: 'ぬるぬるは壊れている以下省略', event: { id: 'b'.repeat(64) }, classification: classifyFeedbackText('ぬるぬるは壊れている以下省略') },
    ]
    const groups = groupFeedbackItems(items)
    expect(groups).toHaveLength(2)
    expect(groups[0].classification.labels).toContain('needs:thread-context')
  })
})

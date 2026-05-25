# ぬるぬる 1.5.2

- タイムラインを network-first に変更し、古いキャッシュが新着の下に混ざって時間軸が飛ぶ問題を修正。
- 過去投稿読み込みを高速化: bounded pagination、raw-first 表示、後追い enrichment。
- フォロータイムラインの active-author / NIP-65 relay-hint 取得を追加。
- 個別リレータイムラインでも過去投稿 pagination に対応。
- 最近のリポストを repost 時刻で表示し、11m → 1d のような見かけ上のジャンプを修正。

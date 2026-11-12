module.exports = async (req, res) => {
  const q = req.query && req.query.q;
  if (!q || typeof q !== 'string' || !q.trim()) {
    return res.status(400).json({ error: 'Missing query parameter q' });
  }

  const trimmed = q.trim();
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 's-maxage=86400, stale-while-revalidate');

  // 1. Try Google Translate public endpoint
  try {
    const url =
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=es&dt=t&q=' +
      encodeURIComponent(trimmed);
    const upstream = await fetch(url, {
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    });
    if (upstream.ok) {
      const text = await upstream.text();
      return res.status(200).send(text);
    }
  } catch (_) {}

  // 2. Fallback to MyMemory API (returns Google-compatible nested array)
  try {
    const mmUrl =
      'https://api.mymemory.translated.net/get?q=' +
      encodeURIComponent(trimmed.slice(0, 500)) +
      '&langpair=en|es';
    const mmRes = await fetch(mmUrl);
    if (mmRes.ok) {
      const data = await mmRes.json();
      const translated = data?.responseData?.translatedText;
      if (translated && typeof translated === 'string') {
        return res.status(200).json([[[translated, trimmed]]]);
      }
    }
  } catch (_) {}

  return res.status(502).json({ error: 'Translation upstream failed' });
};

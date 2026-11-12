module.exports = async (req, res) => {
  const q = req.query && req.query.q;
  if (!q || typeof q !== 'string' || !q.trim()) {
    return res.status(400).json({ error: 'Missing query parameter q' });
  }

  try {
    const url =
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=es&dt=t&q=' +
      encodeURIComponent(q.trim());
    const upstream = await fetch(url, {
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    });
    const text = await upstream.text();
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 's-maxage=86400, stale-while-revalidate');
    return res.status(upstream.status).send(text);
  } catch (err) {
    return res.status(502).json({ error: 'Translation upstream failed' });
  }
};


export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.setHeader("Cache-Control", "no-store");

    if (req.method === "OPTIONS") {
        return res.status(204).end();
    }

    const params = new URLSearchParams(req.query);
    const target = `https://lyrics-api.unsophisticated.lol/api/lyrics?${params.toString()}`;

    try {
        const upstream = await fetch(target);
        const data = await upstream.json();
        return res.status(upstream.status).json(data);
    } catch (err) {
        console.error("Lyrics proxy error:", err);
        return res.status(502).json({ error: "Failed to fetch lyrics" });
    }
}

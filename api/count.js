export default async function handler(req, res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");

    if (req.method === "OPTIONS") {
        return res.status(204).end();
    }

    let count = 1;
    const redisUrl = process.env.UPSTASH_REDIS_REST_URL
        || process.env.KV_REST_API_URL
        || process.env.STORAGE_REST_API_URL
        || process.env.STORAGE_URL;

    const redisToken = process.env.UPSTASH_REDIS_REST_TOKEN
        || process.env.KV_REST_API_TOKEN
        || process.env.STORAGE_REST_API_TOKEN
        || process.env.STORAGE_TOKEN;

    if (redisUrl && redisToken) {
        try {
            const cleanUrl = redisUrl.replace(/\/+$/, "");
            const upstream = await fetch(`${cleanUrl}/incr/unsophisticated_visits`, {
                headers: {
                    Authorization: `Bearer ${redisToken}`
                }
            });
            const data = await upstream.json();
            if (data && typeof data.result === "number") {
                count = data.result;
            }
        } catch (err) {
            console.error("Upstash Redis error:", err);
        }
    } else {
        // Local offline fallback when environment variables are not configured
        count = 1;
    }

    const formatted = Number(count).toLocaleString();
    // If this is bad asf (Claude made ts), I'll use all.min.css version
    // Check if SVG format is requested (e.g. for direct <img src="/api/count?format=svg">)
    const isSvg = req.query?.format === "svg" || req.headers?.accept?.includes("image/svg");

    if (isSvg) {
        const textWidth = Math.max(formatted.length * 8 + 36, 68);
        const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${textWidth}" height="24" viewBox="0 0 ${textWidth} 24" fill="none">
    <rect width="${textWidth}" height="24" rx="12" fill="#0e0e0e" stroke="rgba(255,255,255,0.12)" stroke-width="1"/>
    <g transform="translate(8, 5)" stroke="#c0c0c0" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M1 7s2.5-5 7-5 7 5 7 5-2.5 5-7 5-7-5-7-5Z"/>
        <circle cx="8" cy="7" r="2.2"/>
    </g>
    <text x="30" y="15.5" fill="#e0e0e0" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="11" font-weight="600" letter-spacing="0.2px">${formatted}</text>
</svg>`;
        res.setHeader("Content-Type", "image/svg+xml; charset=utf-8");
        return res.status(200).send(svg);
    }

    return res.status(200).json({
        count,
        formatted
    });
}

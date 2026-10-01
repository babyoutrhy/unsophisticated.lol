(function () {
            const USER1_ID = "810898281781657621";
            const USER2_ID = "1532110400173117591";
            const LYRICS_OFFSET = 0.7;
            const IS_IOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
            const NP_PALETTES = {
                crimson: { r: 220, g: 20, b: 60 },
                white: { r: 255, g: 255, b: 255 },
                black: { r: 0, g: 0, b: 0 },
                gold: { r: 255, g: 215, b: 0 },
                sapphire: { r: 15, g: 82, b: 186 },
                emerald: { r: 0, g: 201, b: 87 },
                violet: { r: 138, g: 43, b: 226 },
                scarlet: { r: 255, g: 36, b: 0 },
                rose: { r: 255, g: 0, b: 127 },
                azure: { r: 0, g: 127, b: 255 },
                amber: { r: 255, g: 191, b: 0 },
                silver: { r: 192, g: 192, b: 192 },
            };
            const PLATFORM_ICONS = {
                desktop: `<svg viewBox="0 0 24 24"><path d="M4 2.5c-1.103 0-2 .897-2 2v11c0 1.104.897 2 2 2h7v2H7v2h10v-2h-4v-2h7c1.103 0 2-.896 2-2v-11c0-1.103-.897-2-2-2H4Zm16 2v9H4v-9h16Z"/></svg>`,
                web: `<svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2Zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93Zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39Z"/></svg>`,
                mobile: `<svg viewBox="0 0 24 24"><path d="M17 1.01 7 1c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-1.99-2-1.99zM17 19H7V5h10v14z"/></svg>`,
                embedded: `<svg viewBox="0 0 50 50"><path d="M14.8 2.7 9 3.1V47h3.3c1.7 0 6.2.3 10 .7l6.7.6V2l-4.2.2c-2.4.1-6.9.3-10 .5zm1.8 6.4c1 1.7-1.3 3.6-2.7 2.2C12.7 10.1 13.5 8 15 8c.5 0 1.2.5 1.6 1.1zM16 33c0 6-.4 10-1 10s-1-4-1-10 .4-10 1-10 1 4 1 10zm15-8v23.3l3.8-.7c2-.3 4.7-.6 6-.6H43V3h-2.2c-1.3 0-4-.3-6-.6L31 1.7V25z"/></svg>`,
            };
            const GAME_ICONS = { "roblox studio": "./img/icons/RobloxStudio.png" };
            const appIconCache = {};
            let prevData = {},
                lyricsCache = {},
                spotifyIntervals = {},
                gameIntervals = {},
                listenIntervals = {},
                lanyardWs = null,
                clockInterval = null,
                activeToast = null;
            function esc(s) {
                return String(s).replace(/[&<>]/g, (m) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[m]);
            }
            function msToTime(ms) {
                let s = Math.floor(ms / 1000);
                return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
            }
            function msToElapsed(ms) {
                let t = Math.floor(ms / 1000),
                    h = Math.floor(t / 3600),
                    m = Math.floor((t % 3600) / 60),
                    s = t % 60;
                return h > 0
                    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
                    : `${m}:${String(s).padStart(2, "0")}`;
            }
            function defaultAvatarIndex(id) {
                return Number((BigInt(id) >> 22n) % 6n);
            }
            function resolveAssetUrl(key, appId) {
                if (!key) return "";
                if (key.startsWith("mp:")) return key.replace("mp:", "https://media.discordapp.net/");
                if (key.startsWith("https://")) return key;
                return `https://cdn.discordapp.com/app-assets/${appId}/${key}.png`;
            }
            document.querySelectorAll(".tab-btn").forEach((btn) =>
                btn.addEventListener("click", () => {
                    const tab = btn.dataset.tab;
                    document.querySelectorAll(".tab-btn").forEach((b) => b.classList.toggle("active", b === btn));
                    document.getElementById("tab-rhy").style.display = tab === "rhy" ? "" : "none";
                    document.getElementById("tab-yaseen").style.display = tab === "yaseen" ? "" : "none";
                    document.getElementById("socials-rhy").style.display = tab === "rhy" ? "" : "none";
                    document.getElementById("socials-yaseen").style.display = tab === "yaseen" ? "" : "none";
                    window.dispatchEvent(new CustomEvent("tp-switch", { detail: tab }));
                })
            );
            function updateClocks() {
                let n = new Date();
                if (document.getElementById("clock-1"))
                    document.getElementById("clock-1").textContent = n.toLocaleTimeString("en-GB", {
                        timeZone: "Europe/Rome",
                        hour12: false,
                    });
                if (document.getElementById("clock-0"))
                    document.getElementById("clock-0").textContent = n.toLocaleTimeString("en-GB", {
                        timeZone: "Europe/London",
                        hour12: false,
                    });
            }
            updateClocks();
            clockInterval = setInterval(updateClocks, 1000);
            function extractAlbumColor(url, cb) {
                let img = new Image();
                img.crossOrigin = "anonymous";
                img.src = url;
                img.onload = () => {
                    let c = document.createElement("canvas");
                    c.width = c.height = 32;
                    let ctx = c.getContext("2d");
                    if (!ctx) {
                        cb("40,40,40");
                        return;
                    }
                    ctx.drawImage(img, 0, 0, 32, 32);
                    let d = ctx.getImageData(0, 0, 32, 32).data;
                    let buckets = {};
                    for (let i = 0; i < d.length; i += 4) {
                        let r = d[i],
                            g = d[i + 1],
                            b = d[i + 2];
                        let max = Math.max(r, g, b),
                            min = Math.min(r, g, b),
                            sat = max === 0 ? 0 : (max - min) / max,
                            bri = max / 255;
                        if (bri < 0.12 || bri > 0.92 || sat < 0.2) continue;
                        let rq = Math.round(r / 24) * 24,
                            gq = Math.round(g / 24) * 24,
                            bq = Math.round(b / 24) * 24,
                            key = `${rq},${gq},${bq}`;
                        if (!buckets[key]) buckets[key] = { r: rq, g: gq, b: bq, count: 0, sat };
                        buckets[key].count++;
                    }
                    let br = 40,
                        bg = 40,
                        bb = 40,
                        best = -1;
                    for (let v of Object.values(buckets)) {
                        let sc = v.count * v.sat;
                        if (sc > best) {
                            best = sc;
                            br = v.r;
                            bg = v.g;
                            bb = v.b;
                        }
                    }
                    let dk = (v) => Math.floor(v * 0.35);
                    cb(`${dk(br)}, ${dk(bg)}, ${dk(bb)}`);
                };
                img.onerror = () => cb("40,40,40");
            }
            function applyActivityColor(block, rgb) {
                block.style.background = `linear-gradient(160deg, rgba(${rgb},0.42) 0%, rgba(${rgb},0.18) 50%, rgba(10,10,10,0.12) 100%)`;
                block.style.borderColor = `rgba(${rgb},0.35)`;
                block.style.boxShadow = `0 4px 24px 0 rgba(${rgb},0.12), inset 0 1px 0 rgba(255,255,255,0.05)`;
            }
            function applyFillColor(fill, rgb) {
                fill.style.background = `rgb(${rgb})`;
            }
            function applyNameplate(prefix, np) {
                let vid = document.getElementById(`nameplate-video-${prefix}`),
                    overlay = document.getElementById(`nameplate-overlay-${prefix}`);
                if (!vid || !overlay) return;
                if (!np?.asset) {
                    vid.style.opacity = "0";
                    overlay.style.background = "none";
                    overlay.style.boxShadow = "inset 0 0 0 1px rgba(255,255,255,0.05)";
                    return;
                }
                let url = `https://cdn.discordapp.com/assets/collectibles/${np.asset.replace(/\/+$/, "")}/asset.webm`;
                if (vid.dataset.src !== url) {
                    vid.dataset.src = url;
                    vid.src = url;
                    vid.style.opacity = IS_IOS ? "0.08" : "0";
                    vid.load();
                    vid.play()
                        .then(() => {
                            vid.style.opacity = IS_IOS ? "0.08" : "1";
                            vid.classList.add("loaded");
                        })
                        .catch(() => { });
                }
                if (np.palette) {
                    let p = NP_PALETTES[np.palette.toLowerCase()];
                    if (p) {
                        let { r, g, b } = p;
                        overlay.style.background = `linear-gradient(90deg, rgba(${r},${g},${b},0.03) 0%, rgba(${r},${g},${b},0.30) 100%)`;
                        overlay.style.boxShadow = `inset 0 0 0 1px rgba(${r},${g},${b},0.15)`;
                    }
                }
            }
            function renderPlatforms(prefix, data, status) {
                let el = document.getElementById(`platforms-${prefix}`);
                if (!el) return;
                let col =
                    { online: "#2a9d6e", idle: "#e5a23b", dnd: "#e05a5a", offline: "#6c7a8e" }[status] || "#6c7a8e";
                let p = [];
                if (data?.active_on_discord_desktop) p.push("desktop");
                if (data?.active_on_discord_web) p.push("web");
                if (data?.active_on_discord_mobile) p.push("mobile");
                if (data?.active_on_discord_console) p.push("embedded");
                el.innerHTML = p
                    .map(
                        (pl) =>
                            `<span class="platform-icon" data-desc="${esc(pl)}" title="${pl}" style="color:${col}; cursor: pointer;">${PLATFORM_ICONS[pl]}</span>`
                    )
                    .join("");
                el.querySelectorAll('.platform-icon').forEach(icon => {
                    icon.addEventListener('click', (e) => {
                        e.stopPropagation();
                        let desc = icon.getAttribute('data-desc');
                        showToast(desc.charAt(0).toUpperCase() + desc.slice(1));
                    });
                });
            }
            function renderStatus(prefix, status) {
                let dot = document.getElementById(`status-dot-${prefix}`);
                if (!dot) return;
                let col = { online: "#2a9d6e", idle: "#e5a23b", dnd: "#e05a5a", offline: "#6c7a8e" };
                dot.style.background = col[status] || col.offline;
            }
            async function fetchBadges(uid, pref) {
                let el = document.getElementById(`badges-${pref}`);
                if (!el) return;
                try {
                    let r = await fetch(`https://dcdn.dstn.to/profile/${uid}`);
                    let d = await r.json();
                    let b = Array.isArray(d?.badges) ? d.badges : [];
                    if (!b.length) {
                        el.innerHTML = "";
                        return;
                    }
                    el.innerHTML = b
                        .map(
                            (bd) =>
                                `<img class="badge-icon" data-desc="${esc(bd.description)}" src="https://cdn.discordapp.com/badge-icons/${bd.icon}.png" loading="lazy">`
                        )
                        .join("");
                    el.querySelectorAll(".badge-icon").forEach((img) =>
                        img.addEventListener("click", (e) => {
                            e.stopPropagation();
                            showToast(img.dataset.desc || "Badge");
                        })
                    );
                } catch {
                    el.innerHTML = "";
                }
            }
            function showToast(msg) {
                if (activeToast) activeToast.remove();
                let t = document.createElement("div");
                t.className = "badge-toast";
                t.textContent = msg;
                document.body.appendChild(t);
                activeToast = t;
                setTimeout(() => {
                    if (t.parentNode) t.remove();
                    if (activeToast === t) activeToast = null;
                }, 2800);
            }
            function parseLRC(lrc) {
                let lines = [],
                    re = /\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)/g,
                    m;
                while ((m = re.exec(lrc)) !== null) {
                    let time = parseInt(m[1]) * 60 + parseInt(m[2]) + parseInt(m[3].padEnd(3, "0")) / 1000,
                        text = m[4].trim();
                    if (text) lines.push({ time, text });
                }
                return lines.sort((a, b) => a.time - b.time);
            }
            function renderLyrics(lines, prefix, curr) {
                let sc = document.getElementById(`lyrics-scroll-${prefix}`);
                if (!sc || !lines) return;
                let off = curr + LYRICS_OFFSET,
                    idx = 0;
                for (let i = 0; i < lines.length; i++)
                    if (lines[i].time <= off) idx = i;
                    else break;
                sc.innerHTML = lines
                    .map(
                        (l, i) => `<div class="lyrics-line ${i === idx ? "current-line" : ""}">${esc(l.text)}</div>`
                    )
                    .join("");
                let par = sc.parentElement;
                if (par && par.scrollHeight > par.clientHeight) {
                    let cur = sc.children[idx];
                    if (cur) {
                        let cr = par.getBoundingClientRect(),
                            lr = cur.getBoundingClientRect();
                        let target = par.scrollTop + (lr.top - cr.top) - par.clientHeight / 2 + lr.height / 2;
                        par.scrollTo({
                            top: Math.max(0, Math.min(target, par.scrollHeight - par.clientHeight)),
                            behavior: "smooth",
                        });
                    }
                }
            }
            function updateLyricsHighlight(prefix, sec) {
                let lines = lyricsCache[prefix],
                    sc = document.getElementById(`lyrics-scroll-${prefix}`);
                if (!lines || !sc) return;
                let off = sec + LYRICS_OFFSET,
                    idx = 0;
                for (let i = 0; i < lines.length; i++)
                    if (lines[i].time <= off) idx = i;
                    else break;
                let ch = sc.children;
                for (let i = 0; i < ch.length; i++) ch[i].classList.toggle("current-line", i === idx);
                let par = sc.parentElement;
                if (par && par.scrollHeight > par.clientHeight) {
                    let cur = ch[idx];
                    if (cur) {
                        let cr = par.getBoundingClientRect(),
                            lr = cur.getBoundingClientRect();
                        let target = par.scrollTop + (lr.top - cr.top) - par.clientHeight / 2 + lr.height / 2;
                        par.scrollTo({
                            top: Math.max(0, Math.min(target, par.scrollHeight - par.clientHeight)),
                            behavior: "smooth",
                        });
                    }
                }
            }
            async function fetchLyrics(track, artist, pref, startTs, trackId) {
                let outer = document.getElementById(`lyrics-outer-${pref}`);
                if (!track || !artist) {
                    if (outer) outer.style.display = "none";
                    delete lyricsCache[pref];
                    return;
                }
                if (outer) outer.style.display = "none";
                delete lyricsCache[pref];

                // Helper: parse LRC format (SyncedLyrics from lrclib)
                function parseLRC(lrcText) {
                    return lrcText
                        .split("\n")
                        .map(line => {
                            let m = line.match(/\[(\d+):(\d+\.\d+)\](.*)/);
                            if (!m) return null;
                            let min = parseInt(m[1], 10);
                            let sec = parseFloat(m[2]);
                            return { time: min * 60 + sec, text: m[3].trim() };
                        })
                        .filter(l => l && l.text)
                        .sort((a, b) => a.time - b.time);
                }

                // Helper: parse our own lyrics-api timeTag format ("MM:SS.ss")
                function parseTimeTagLines(lines) {
                    return lines
                        .filter(l => l.words && l.words.trim() && l.words !== "♪")
                        .map(l => {
                            let m = String(l.timeTag).match(/(\d+):(\d+(?:\.\d+)?)/);
                            if (!m) return null;
                            let min = parseInt(m[1], 10);
                            let sec = parseFloat(m[2]);
                            return { time: min * 60 + sec, text: l.words.trim() };
                        })
                        .filter(Boolean)
                        .sort((a, b) => a.time - b.time);
                }

                // 1. Try our own lyrics-api (Spotify-sourced, fast) if we have a track ID
                if (trackId) {
                    try {
                        let spRes = await fetch(
                            `/api/lyrics?url=https://open.spotify.com/track/${encodeURIComponent(trackId)}&format=lrc`
                        );
                        if (spRes.ok) {
                            let spData = await spRes.json();
                            if (!spData.error && spData.syncType === "LINE_SYNCED" && spData.lines?.length) {
                                let lines = parseTimeTagLines(spData.lines);
                                if (lines.length) {
                                    lyricsCache[pref] = lines;
                                    renderLyrics(lines, pref, startTs ? (Date.now() - startTs) / 1000 : 0);
                                    if (outer) outer.style.display = "block";
                                    return;
                                }
                            }
                        }
                    } catch { }
                }
            }
            function startSpotifyProgress(pref, start, end) {
                let fill = document.getElementById(`sp-fill-${pref}`),
                    elapsed = document.getElementById(`sp-elapsed-${pref}`),
                    total = document.getElementById(`sp-total-${pref}`);
                if (!fill) return null;
                let tick = () => {
                    let now = Date.now(),
                        dur = end - start,
                        el = Math.max(0, Math.min(now - start, dur));
                    fill.style.width = `${(el / dur) * 100}%`;
                    if (elapsed) elapsed.textContent = msToTime(el);
                    if (total) total.textContent = msToTime(dur);
                    updateLyricsHighlight(pref, el / 1000);
                };
                tick();
                return setInterval(tick, 1000);
            }
            async function resolveGameCoverUrl(act) {
                let low = (act.name || "").toLowerCase().trim();
                if (GAME_ICONS[low]) return GAME_ICONS[low];
                if (act.assets?.large_image) return resolveAssetUrl(act.assets.large_image, act.application_id);
                let id = act.application_id;
                if (!id) return "";
                if (appIconCache[id] !== undefined) return appIconCache[id];
                try {
                    let r = await fetch(`https://discord.com/api/v10/applications/${id}/rpc`);
                    let d = await r.json();
                    let url = d.icon ? `https://cdn.discordapp.com/app-icons/${id}/${d.icon}.png` : "";
                    appIconCache[id] = url;
                    return url;
                } catch {
                    appIconCache[id] = "";
                    return "";
                }
            }
            const GAME_SVG = `<svg viewBox="0 0 24 24"><path d="M20.97 4.06c0 .18.08.35.24.43.55.28.9.82 1.04 1.42.3 1.24.75 3.7.75 7.09v4.91a3.09 3.09 0 0 1-5.85 1.38l-1.76-3.51a1.09 1.09 0 0 0-1.23-.55c-.57.13-1.36.27-2.16.27s-1.6-.14-2.16-.27c-.49-.11-1 .1-1.23.55l-1.76 3.51A3.09 3.09 0 0 1 1 17.91V13c0-3.38.46-5.85.75-7.1.15-.6.49-1.13 1.04-1.4a.47.47 0 0 0 .24-.44c0-.7.48-1.32 1.2-1.47l2.93-.62c.5-.1 1 .06 1.36.4.35.34.78.71 1.28.68a42.4 42.4 0 0 1 4.4 0c.5.03.93-.34 1.28-.69.35-.33.86-.5 1.36-.39l2.94.62c.7.15 1.19.78 1.19 1.47ZM20 7.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0ZM15.5 12a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM5 7a1 1 0 0 1 2 0v1h1a1 1 0 0 1 0 2H7v1a1 1 0 1 1-2 0v-1H4a1 1 0 1 1 0-2h1V7Z"/></svg>`;
            async function applyGameActivity(pref, act) {
                let block = document.getElementById(`game-${pref}`);
                if (!block) return;
                if (!act) {
                    block.style.display = "none";
                    if (gameIntervals[pref]) {
                        clearInterval(gameIntervals[pref]);
                        delete gameIntervals[pref];
                    }
                    return;
                }
                let cover = document.getElementById(`game-cover-${pref}`),
                    nameE = document.getElementById(`game-name-${pref}`),
                    detE = document.getElementById(`game-detail-${pref}`),
                    stateE = document.getElementById(`game-state-${pref}`),
                    elapE = document.getElementById(`game-elapsed-${pref}`),
                    labelE = block.querySelector('.activity-label');

                if (labelE) {
                    let typeNames = { 0: "Playing a Game", 1: "Streaming", 3: "Watching", 5: "Competing in" };
                    labelE.textContent = typeNames[act.type] || "Playing a Game";
                }
                cover.src = await resolveGameCoverUrl(act);
                nameE.textContent = act.name || "";
                detE.textContent = act.details || "";
                stateE.textContent = act.state || "";
                if (gameIntervals[pref]) clearInterval(gameIntervals[pref]);
                let start = act.timestamps?.start;
                if (start && elapE) {
                    let tick = () => {
                        elapE.innerHTML = `${GAME_SVG} ${msToElapsed(Date.now() - start)} elapsed`;
                    };
                    tick();
                    gameIntervals[pref] = setInterval(tick, 1000);
                } else if (elapE) elapE.innerHTML = "";
                if (cover.src) extractAlbumColor(cover.src, (rgb) => applyActivityColor(block, rgb));
                block.style.display = "block";
            }
            function applyListeningActivity(pref, act) {
                let block = document.getElementById(`listening-${pref}`);
                if (!block) return;
                if (!act) {
                    block.style.display = "none";
                    if (listenIntervals[pref]) {
                        clearInterval(listenIntervals[pref]);
                        delete listenIntervals[pref];
                    }
                    return;
                }
                let cover = document.getElementById(`lst-cover-${pref}`),
                    plat = document.getElementById(`lst-platform-${pref}`),
                    song = document.getElementById(`lst-song-${pref}`),
                    artist = document.getElementById(`lst-artist-${pref}`),
                    fill = document.getElementById(`lst-fill-${pref}`),
                    elap = document.getElementById(`lst-elapsed-${pref}`),
                    tot = document.getElementById(`lst-total-${pref}`),
                    link = document.getElementById(`lst-link-${pref}`);
                cover.src = resolveAssetUrl(act.assets?.large_image, act.application_id);
                if (plat) plat.textContent = `Listening on ${act.name}`;
                if (song) song.textContent = act.details || "";
                if (artist) artist.textContent = act.state || "";
                let url = act.details_url || act.assets?.large_url;
                if (link) {
                    if (url) {
                        link.href = url;
                        let p = act.name || "";
                        if (p === "SoundCloud")
                            link.innerHTML = '<i class="fab fa-soundcloud"></i> Play on SoundCloud';
                        else if (p === "Apple Music")
                            link.innerHTML = '<i class="fab fa-apple"></i> Play on Apple Music';
                        else link.innerHTML = `<i class="fas fa-music"></i> Open on ${p}`;
                        link.style.display = "inline-flex";
                    } else link.style.display = "none";
                }
                if (listenIntervals[pref]) clearInterval(listenIntervals[pref]);
                let start = act.timestamps?.start,
                    end = act.timestamps?.end;
                if (start && end && fill) {
                    let tick = () => {
                        let now = Date.now(),
                            dur = end - start,
                            el = Math.max(0, Math.min(now - start, dur));
                        fill.style.width = `${(el / dur) * 100}%`;
                        if (elap) elap.textContent = msToTime(el);
                        if (tot) tot.textContent = msToTime(dur);
                    };
                    tick();
                    listenIntervals[pref] = setInterval(tick, 1000);
                }
                if (cover.src) extractAlbumColor(cover.src, (rgb) => applyActivityColor(block, rgb));
                block.style.display = "block";
            }
            function applyDiscordData(uid, pref, data, spCh) {
                let av = document.getElementById(`avatar-${pref}`),
                    deco = document.getElementById(`deco-${pref}`),
                    dname = document.getElementById(`dname-${pref}`),
                    uname = document.getElementById(`uname-${pref}`),
                    guild = document.getElementById(`guild-${pref}`),
                    spBlock = document.getElementById(`spotify-${pref}`),
                    spCover = document.getElementById(`sp-cover-${pref}`),
                    spSong = document.getElementById(`sp-song-${pref}`),
                    spArtist = document.getElementById(`sp-artist-${pref}`),
                    spListen = document.getElementById(`sp-listen-${pref}`),
                    spPlay = document.getElementById(`sp-play-${pref}`),
                    spFill = document.getElementById(`sp-fill-${pref}`);
                if (!data?.discord_user) {
                    if (dname) dname.textContent = "Offline";
                    applyGameActivity(pref, null);
                    applyListeningActivity(pref, null);
                    return;
                }
                let user = data.discord_user,
                    status = data.discord_status || "offline",
                    spotify = data.spotify;
                if (av) {
                    if (user.avatar) {
                        let ext = user.avatar.startsWith("a_") ? "gif" : "png";
                        av.src = `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.${ext}?size=128`;
                    } else av.src = `https://cdn.discordapp.com/embed/avatars/${defaultAvatarIndex(user.id)}.png`;
                }
                if (deco) {
                    if (user.avatar_decoration_data?.asset) {
                        deco.src = `https://cdn.discordapp.com/avatar-decoration-presets/${user.avatar_decoration_data.asset}.png?size=160`;
                        deco.style.display = "block";
                    } else deco.style.display = "none";
                }
                if (dname) dname.textContent = user.global_name || user.username;
                if (uname) uname.textContent = `@${user.username}`;
                if (guild) {
                    if (user.primary_guild?.identity_enabled && user.primary_guild.badge) {
                        guild.innerHTML = `<img src="https://cdn.discordapp.com/clan-badges/${user.primary_guild.identity_guild_id}/${user.primary_guild.badge}.png?size=16"> <span>${esc(user.primary_guild.tag)}</span>`;
                        guild.style.display = "inline-flex";
                    } else guild.style.display = "none";
                }
                renderStatus(pref, status);
                renderPlatforms(pref, data, status);
                applyNameplate(pref, user.collectibles?.nameplate || null);
                if (spotify && spBlock) {
                    if (spCh) {
                        if (spCover) spCover.src = spotify.album_art_url;
                        if (spSong) {
                            spSong.innerHTML = spotify.track_id
                                ? `<a href="https://open.spotify.com/track/${spotify.track_id}" target="_blank">${esc(spotify.song)}</a>`
                                : esc(spotify.song);
                        }
                        if (spArtist) spArtist.textContent = (spotify.artist || "").replace(/\s*;\s*/g, ", ");
                        if (spListen) {
                            spListen.href = `spotify:track:${spotify.track_id}`;
                            spListen.style.display = "inline-flex";
                        }
                        if (spPlay) {
                            spPlay.href = `https://open.spotify.com/track/${spotify.track_id}`;
                            spPlay.style.display = "inline-flex";
                        }
                        if (spotifyIntervals[pref]) clearInterval(spotifyIntervals[pref]);
                        spotifyIntervals[pref] = startSpotifyProgress(
                            pref,
                            spotify.timestamps.start,
                            spotify.timestamps.end
                        );
                        fetchLyrics(spotify.song, spotify.artist, pref, spotify.timestamps?.start, spotify.track_id);
                        if (spotify.album_art_url)
                            extractAlbumColor(spotify.album_art_url, (rgb) => {
                                applyActivityColor(spBlock, rgb);
                                if (spFill) applyFillColor(spFill, rgb);
                            });
                    }
                    spBlock.style.display = "block";
                } else if (!spotify && spBlock) {
                    if (spCh) {
                        spBlock.style.display = "none";
                        spBlock.style.background = "";
                        spBlock.style.borderColor = "";
                        spBlock.style.boxShadow = "";
                        let outer = document.getElementById(`lyrics-outer-${pref}`);
                        if (outer) outer.style.display = "none";
                        delete lyricsCache[pref];
                        if (spotifyIntervals[pref]) {
                            clearInterval(spotifyIntervals[pref]);
                            delete spotifyIntervals[pref];
                        }
                        if (spListen) spListen.style.display = "none";
                        if (spPlay) spPlay.style.display = "none";
                    }
                }
                let acts = data.activities || [];
                let game = acts.find((a) => [0, 1, 3, 5].includes(a.type)) || null,
                    listen = acts.find((a) => a.type === 2 && a.name !== "Spotify") || null;
                applyGameActivity(pref, game);
                applyListeningActivity(pref, listen);
            }
            function updateIfChanged(uid, pref, newD) {
                let old = prevData[uid];
                if (!old && !newD) return;
                if (!old && newD) {
                    applyDiscordData(uid, pref, newD, true);
                    prevData[uid] = newD;
                    return;
                }
                if (old && !newD) {
                    let el = document.getElementById(`dname-${pref}`);
                    if (el) el.textContent = "Offline";
                    prevData[uid] = null;
                    return;
                }
                let changed = false,
                    spChanged = false;
                if (old.discord_user?.avatar !== newD.discord_user?.avatar) changed = true;
                if (old.discord_status !== newD.discord_status) changed = true;
                if (JSON.stringify(old.spotify) !== JSON.stringify(newD.spotify)) {
                    changed = true;
                    spChanged = true;
                    if (spotifyIntervals[pref]) clearInterval(spotifyIntervals[pref]);
                    let outer = document.getElementById(`lyrics-outer-${pref}`);
                    if (outer) outer.style.display = "none";
                    delete lyricsCache[pref];
                }
                if (JSON.stringify(old.activities) !== JSON.stringify(newD.activities)) changed = true;
                if (changed) applyDiscordData(uid, pref, newD, spChanged);
                prevData[uid] = newD;
            }
            let unload = false;
            window.addEventListener("beforeunload", () => {
                unload = true;
            });
            function connectLanyard() {
                let ws = new WebSocket("wss://api.lanyard.rest/socket");
                let hb = null;
                ws.onopen = () => {
                    ws.send(JSON.stringify({ op: 2, d: { subscribe_to_ids: [USER1_ID, USER2_ID] } }));
                };
                ws.onmessage = (e) => {
                    let msg = JSON.parse(e.data);
                    if (msg.op === 1) {
                        if (hb) clearInterval(hb);
                        hb = setInterval(() => {
                            if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ op: 3 }));
                        }, msg.d.heartbeat_interval);
                    } else if (msg.op === 0) {
                        if (msg.t === "INIT_STATE") {
                            updateIfChanged(USER1_ID, "1", msg.d[USER1_ID] || null);
                            updateIfChanged(USER2_ID, "2", msg.d[USER2_ID] || null);
                        } else if (msg.t === "PRESENCE_UPDATE") {
                            let d = msg.d,
                                uid = d.discord_user?.id;
                            if (uid === USER1_ID) updateIfChanged(USER1_ID, "1", d);
                            else if (uid === USER2_ID) updateIfChanged(USER2_ID, "2", d);
                        }
                    }
                };
                ws.onclose = () => {
                    if (hb) clearInterval(hb);
                    if (!unload) setTimeout(connectLanyard, 3000);
                };
                ws.onerror = () => ws.close();
                lanyardWs = ws;
            }
            connectLanyard();
            fetchBadges(USER1_ID, "1");
            fetchBadges(USER2_ID, "2");

            /* ── username click-to-copy ── */
            (function () {
                function setupCopy(id) {
                    const el = document.getElementById(id);
                    if (!el) return;
                    let timer = null;
                    el.addEventListener("click", () => {
                        if (timer) return; // debounce
                        const original = el.textContent;
                        const name = original.startsWith("@") ? original.slice(1) : original;
                        navigator.clipboard.writeText(name).catch(() => { });
                        el.textContent = "Username copied!";
                        timer = setTimeout(() => { el.textContent = original; timer = null; }, 1500);
                    });
                }
                setupCopy("uname-1");
                setupCopy("uname-2");
            })();

            let canvas = document.getElementById("rainCanvas"),
                ctx = canvas.getContext("2d"),
                dots = [];
            function resizeCanvas() {
                canvas.width = window.innerWidth;
                canvas.height = window.innerHeight;
            }
            function initDots() {
                dots = [];
                for (let i = 0; i < 70; i++)
                    dots.push({
                        x: Math.random() * canvas.width,
                        y: Math.random() * canvas.height,
                        radius: 1 + Math.random() * 2.5,
                        speed: 0.5 + Math.random() * 1.2,
                        alpha: 0.2 + Math.random() * 0.4,
                    });
            }
            function drawRain() {
                ctx.clearRect(0, 0, canvas.width, canvas.height);
                for (let d of dots) {
                    ctx.beginPath();
                    ctx.arc(d.x, d.y, d.radius, 0, Math.PI * 2);
                    ctx.fillStyle = `rgba(192, 192, 192, ${d.alpha * 0.5})`;
                    ctx.fill();
                    d.y += d.speed;
                    if (d.y > canvas.height + 15) {
                        d.y = -15;
                        d.x = Math.random() * canvas.width;
                    }
                }
                requestAnimationFrame(drawRain);
            }
            window.addEventListener("resize", () => {
                resizeCanvas();
                initDots();
            });
            resizeCanvas();
            initDots();
            drawRain();
            window.addEventListener("beforeunload", () => {
                if (lanyardWs) lanyardWs.close();
                clearInterval(clockInterval);
                Object.values(spotifyIntervals).forEach(clearInterval);
                Object.values(gameIntervals).forEach(clearInterval);
                Object.values(listenIntervals).forEach(clearInterval);
            });
        })();

        /* TRACK PLAYER (marquee fix, correct icons, playlist layout) */
        (function () {
            const BASE_AUDIO = "./audio/";
            const BASE_COVER = "./audio/cover/";
            const PLAYLISTS = {
                rhy: [
                    { file: "pp.mp3", cover: "pp.jpg", title: ":pp", artist: "xxcrush" },
                    {
                        file: "SOBRIO.mp3",
                        cover: "SOBRIO.jpg",
                        title: "SOBRIO",
                        artist: "LilTagliaGole, Narcolessia",
                    },
                    { file: "SUICIDOL.mp3", cover: "SUICIDOL.jpg", title: "SUIC!DOL", artist: "KidTrash" },
                    {
                        file: "better off without me.mp3",
                        cover: "better off without me.jpg",
                        title: "better off without me",
                        artist: "capoxxo",
                    },
                    {
                        file: "kiss me thru the discord.mp3",
                        cover: "kiss me thru the discord.jpg",
                        title: "kiss me thru the discord",
                        artist: "feeluvsyou, xaxanity",
                    },
                    {
                        file: "myspaceshawty.mp3",
                        cover: "myspaceshawty.jpg",
                        title: "MYSPACE SHAWTY!",
                        artist: "2007myspacegirl, 6snot",
                    },
                    { file: "oppai.mp3", cover: "oppai.jpg", title: "oppai", artist: "bergoz, sillyelly" },
                    {
                        file: "FLIPPHONE.mp3",
                        cover: "FLIPPHONE.jpg",
                        title: "FLIPPHONE",
                        artist: "KidTrash, Blackwinterwells",
                    },
                    {
                        file: "prettyravegirl.mp3",
                        cover: "prettyravegirl.jpg",
                        title: "pretty rave girl",
                        artist: "capoxxo",
                    },
                    {
                        file: "tinypants.mp3",
                        cover: "tinypants.jpg",
                        title: "TINY PANTS",
                        artist: "2007myspacegirl, YungSkeleton, Riffey",
                    },
                ],
                yaseen: [
                    {
                        file: "How U Feel.mp3",
                        cover: "How U Feel.jpg",
                        title: "How U Feel",
                        artist: "Huncho Jack, Travis Scott, Quavo",
                    },
                    {
                        file: "Impossible.mp3",
                        cover: "Impossible.jpg",
                        title: "Impossible",
                        artist: "Travis Scott",
                    },
                    { file: "regretful.mp3", cover: "regretful.jpg", title: "regretful", artist: "leverfall" },
                ],
            };
            const audio = document.getElementById("tpAudio"),
                coverEl = document.getElementById("tpCover"),
                songEl = document.getElementById("tpSong"),
                artistEl = document.getElementById("tpArtist"),
                seekTrack = document.getElementById("tpSeekTrack"),
                seekFill = document.getElementById("tpSeekFill"),
                seekDot = document.getElementById("tpSeekDot"),
                playBtn = document.getElementById("tpPlay"),
                prevBtn = document.getElementById("tpPrev"),
                nextBtn = document.getElementById("tpNext"),
                expandBtn = document.getElementById("tpExpand"),
                volSlider = document.getElementById("tpVol"),
                volIconBtn = document.getElementById("tpVolIcon"),
                iconPlay = document.getElementById("tpIconPlay"),
                iconPause = document.getElementById("tpIconPause"),
                playlistEl = document.getElementById("tpPlaylist"),
                playlistArt = document.getElementById("tpPlaylistArt"),
                playlistTracks = document.getElementById("tpPlaylistTracks"),
                plTitleEl = document.getElementById("tpPlTitle"),
                plArtistEl = document.getElementById("tpPlArtist"),
                volFull = document.getElementById("tpVolFull"),
                volMute = document.getElementById("tpVolMute");
            let activeWho = "rhy",
                currentIdx = 0,
                isShuffled = false,
                shuffleOrder = [],
                playlistOpen = false,
                isSeeking = false;
            function tracks() { return PLAYLISTS[activeWho]; }
            // ── seek bar (div-based, cosmin style) ──
            function setSeekPct(pct) {
                pct = Math.max(0, Math.min(100, pct));
                seekFill.style.width = pct + "%";
                seekDot.style.left = pct + "%";
            }
            function seekFromEvent(e) {
                if (!seekTrack) return;
                let rect = seekTrack.getBoundingClientRect();
                let clientX = e.touches ? e.touches[0].clientX : e.clientX;
                let pct = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
                setSeekPct(pct * 100);
                if (audio.duration) audio.currentTime = pct * audio.duration;
            }
            seekTrack.addEventListener("mousedown", (e) => { isSeeking = true; seekFromEvent(e); });
            seekTrack.addEventListener("touchstart", (e) => { isSeeking = true; seekFromEvent(e); }, { passive: true });
            window.addEventListener("mousemove", (e) => { if (isSeeking) seekFromEvent(e); });
            window.addEventListener("touchmove", (e) => { if (isSeeking) seekFromEvent(e); }, { passive: true });
            window.addEventListener("mouseup", () => { isSeeking = false; });
            window.addEventListener("touchend", () => { isSeeking = false; });
            seekTrack.addEventListener("click", seekFromEvent);
            // ── volume ──
            function fillVol(pct) {
                volSlider.style.background = `linear-gradient(to right,var(--accent) ${pct}%,#333333 ${pct}%)`;
            }
            function updateVolIcon() {
                let v = parseFloat(volSlider.value), muted = audio.muted;
                volFull.style.display = (!muted && v > 0) ? "" : "none";
                volMute.style.display = (muted || v === 0) ? "" : "none";
            }
            // ── shuffle / next / prev ──
            function buildShuffle() {
                shuffleOrder = [...Array(tracks().length).keys()].sort(() => Math.random() - 0.5);
            }
            function getNext() {
                if (isShuffled) return shuffleOrder[(shuffleOrder.indexOf(currentIdx) + 1) % shuffleOrder.length];
                return (currentIdx + 1) % tracks().length;
            }
            function getPrev() {
                if (isShuffled) return shuffleOrder[(shuffleOrder.indexOf(currentIdx) - 1 + shuffleOrder.length) % shuffleOrder.length];
                return (currentIdx - 1 + tracks().length) % tracks().length;
            }
            // ── marquee ──
            function setMarquee(el) {
                if (!el) return;
                let isOverflow = el.scrollWidth > el.clientWidth;
                if (isOverflow && !el.classList.contains("marquee")) {
                    el.classList.add("marquee");
                    let span = el.querySelector(".marquee-content");
                    if (!span) {
                        span = document.createElement("span");
                        span.className = "marquee-content";
                        span.textContent = el.textContent;
                        el.innerHTML = "";
                        el.appendChild(span);
                    }
                } else if (!isOverflow && el.classList.contains("marquee")) {
                    el.classList.remove("marquee");
                    let span = el.querySelector(".marquee-content");
                    if (span) el.textContent = span.textContent;
                }
            }
            // ── load track ──
            function loadTrack(idx, autoplay) {
                currentIdx = idx;
                let t = tracks()[idx];
                coverEl.src = BASE_COVER + t.cover;
                songEl.textContent = t.title;
                setMarquee(songEl);
                artistEl.textContent = t.artist;
                setMarquee(artistEl);
                audio.src = BASE_AUDIO + t.file;
                setSeekPct(0);
                setPlayState(false);
                audio.load();
                if (autoplay) audio.play().catch(() => { });
                if (playlistOpen) refreshPlaylistActive();
            }
            function setPlayState(playing) {
                iconPlay.style.display = playing ? "none" : "";
                iconPause.style.display = playing ? "" : "none";
            }
            // ── playlist ──
            function buildPlaylist() {
                if (!playlistEl || !playlistTracks) return;
                let list = tracks(), t = list[currentIdx];
                if (playlistArt) playlistArt.src = BASE_COVER + t.cover;
                if (plTitleEl) plTitleEl.textContent = t.title;
                if (plArtistEl) plArtistEl.textContent = t.artist;
                const PLAY_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="currentColor"><path d="M6.51 18.87a1 1 0 0 0 1-.01l10-6c.3-.18.49-.51.49-.86s-.18-.68-.49-.86l-10-6a.99.99 0 0 0-1.01-.01c-.31.18-.51.51-.51.87v12c0 .36.19.69.51.87Z"/></svg>`;
                playlistTracks.innerHTML = list.map((tr, i) =>
                    `<div class="tp-pl-item${i === currentIdx ? " active" : ""}" data-idx="${i}"><span class="tp-pl-num">${String(i + 1).padStart(2, "0")}</span><span class="tp-pl-play-ico">${PLAY_SVG}</span><span class="tp-pl-name">${tr.title}</span></div>`
                ).join("");
                playlistTracks.querySelectorAll(".tp-pl-item").forEach((item) => {
                    item.addEventListener("click", () => {
                        let idx = parseInt(item.dataset.idx, 10);
                        if (idx === currentIdx) { audio.paused ? audio.play() : audio.pause(); return; }
                        loadTrack(idx, true);
                    });
                });
            }
            function refreshPlaylistActive() {
                if (!playlistTracks) return;
                let t = tracks()[currentIdx];
                if (playlistArt) playlistArt.src = BASE_COVER + t.cover;
                if (plTitleEl) plTitleEl.textContent = t.title;
                if (plArtistEl) plArtistEl.textContent = t.artist;
                playlistTracks.querySelectorAll(".tp-pl-item").forEach((item, i) => item.classList.toggle("active", i === currentIdx));
            }
            function togglePlaylist() {
                playlistOpen = !playlistOpen;
                expandBtn.classList.toggle("active", playlistOpen);
                if (playlistOpen) { buildPlaylist(); playlistEl.classList.add("open"); }
                else playlistEl.classList.remove("open");
            }
            // ── tab switch ──
            window.addEventListener("tp-switch", (e) => {
                let who = e.detail;
                if (who === activeWho) return;
                let wasPlaying = !audio.paused;
                audio.pause();
                activeWho = who;
                currentIdx = 0;
                isShuffled = false;
                if (playlistOpen) buildPlaylist();
                loadTrack(0, wasPlaying);
            });
            // ── audio events ──
            audio.addEventListener("loadedmetadata", () => { });
            audio.addEventListener("timeupdate", () => {
                if (isSeeking || !audio.duration) return;
                setSeekPct((audio.currentTime / audio.duration) * 100);
            });
            audio.addEventListener("ended", () => {
                let nxt = getNext();
                if (nxt === 0 && !isShuffled) { setPlayState(false); return; }
                loadTrack(nxt, true);
            });
            audio.addEventListener("play", () => setPlayState(true));
            audio.addEventListener("pause", () => setPlayState(false));
            // ── controls ──
            expandBtn.addEventListener("click", togglePlaylist);
            playBtn.addEventListener("click", () => {
                if (!audio.src || audio.src === location.href) { loadTrack(currentIdx, true); return; }
                audio.paused ? audio.play() : audio.pause();
            });
            prevBtn.addEventListener("click", () => {
                if (audio.currentTime > 3) audio.currentTime = 0;
                else loadTrack(getPrev(), !audio.paused);
            });
            nextBtn.addEventListener("click", () => loadTrack(getNext(), !audio.paused));
            volSlider.addEventListener("input", () => {
                audio.volume = parseFloat(volSlider.value);
                fillVol(parseFloat(volSlider.value) * 100);
                updateVolIcon();
            });
            let prevVol = 1;
            volIconBtn.addEventListener("click", () => {
                if (audio.muted) {
                    audio.muted = false;
                    volSlider.value = prevVol;
                    fillVol(prevVol * 100);
                } else {
                    prevVol = parseFloat(volSlider.value);
                    audio.muted = true;
                    volSlider.value = 0;
                    fillVol(0);
                }
                updateVolIcon();
            });
            // ── init ──
            audio.volume = 1;
            fillVol(100);
            updateVolIcon();
            loadTrack(0, false);
        })();

(function () {
            const screen = document.getElementById("intro-screen");
            if (!screen) return;
            let dismissed = false;
            function dismiss() {
                if (dismissed) return;
                dismissed = true;
                setTimeout(() => {
                    screen.classList.add("hidden");
                    setTimeout(() => screen.remove(), 700);
                }, 1500);
            }
            // Dismiss on load, or after 2s max
            const maxTimer = setTimeout(dismiss, 2000);
            window.addEventListener("load", () => { clearTimeout(maxTimer); dismiss(); }, { once: true });
            if (document.readyState === "complete") { clearTimeout(maxTimer); dismiss(); }
        })();

// Anti-Developer Tools
        document.addEventListener('contextmenu', event => event.preventDefault()); // Disable right-click

        document.onkeydown = function (e) {
            // Disable F12
            if (e.keyCode == 123) {
                return false;
            }
            // Disable Ctrl+Shift+I
            if (e.ctrlKey && e.shiftKey && e.keyCode == 'I'.charCodeAt(0)) {
                return false;
            }
            // Disable Ctrl+Shift+C
            if (e.ctrlKey && e.shiftKey && e.keyCode == 'C'.charCodeAt(0)) {
                return false;
            }
            // Disable Ctrl+Shift+J
            if (e.ctrlKey && e.shiftKey && e.keyCode == 'J'.charCodeAt(0)) {
                return false;
            }
            // Disable Ctrl+U
            if (e.ctrlKey && e.keyCode == 'U'.charCodeAt(0)) {
                return false;
            }
        };
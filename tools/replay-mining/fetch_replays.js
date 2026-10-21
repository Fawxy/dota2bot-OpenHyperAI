'use strict';
// node fetch_replays.js --count 50 --out ./replays
// CLI only (never run by tests). Needs network and the system `bunzip2`.

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const { spawnSync } = require('child_process');

const API = 'https://api.opendota.com/api';
const args = process.argv.slice(2);
const opt = (name, def) => (args.includes(`--${name}`) ? args[args.indexOf(`--${name}`) + 1] : def);
const count = Number(opt('count', 50));
const outDir = path.resolve(opt('out', path.join(__dirname, 'replays')));

const REQUEST_TIMEOUT_MS = 60000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let lastRequest = 0;

async function throttle() {
    const wait = lastRequest + 1000 - Date.now();
    if (wait > 0) await sleep(wait);
    lastRequest = Date.now();
}

function get(url, onResponse, redirects = 5) {
    return new Promise((resolve, reject) => {
        const client = new URL(url).protocol === 'http:' ? http : https;
        client
            .get(url, { timeout: REQUEST_TIMEOUT_MS }, (res) => {
                if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && redirects > 0) {
                    res.resume();
                    resolve(get(new URL(res.headers.location, url).toString(), onResponse, redirects - 1));
                } else if (res.statusCode !== 200) {
                    res.resume();
                    reject(new Error(`${url}: HTTP ${res.statusCode}`));
                } else resolve(onResponse(res));
            })
            .on('timeout', function () {
                this.destroy(new Error(`${url}: timed out`));
            })
            .on('error', reject);
    });
}

const getJson = async (url) => {
    await throttle();
    return get(url, (res) => new Promise((resolve, reject) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => {
            try {
                resolve(JSON.parse(body));
            } catch (e) {
                reject(e);
            }
        });
    }));
};

const download = (url, dest) => get(url, (res) => new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    const fail = (e) => {
        file.destroy();
        fs.rmSync(dest, { force: true });
        reject(e);
    };
    res.on('error', fail);
    res.on('aborted', () => fail(new Error(`${url}: connection aborted`)));
    file.on('error', fail);
    file.on('finish', () => file.close(resolve));
    res.pipe(file);
}));

async function main() {
    fs.mkdirSync(outDir, { recursive: true });
    const matches = await getJson(`${API}/proMatches`);
    let done = 0;
    for (const m of matches) {
        if (done >= count) break;
        const dem = path.join(outDir, `${m.match_id}.dem`);
        if (fs.existsSync(dem)) {
            done++;
            continue;
        }
        try {
            const detail = await getJson(`${API}/matches/${m.match_id}`);
            if (!detail.replay_url) continue;
            const bz = `${dem}.bz2`;
            await download(detail.replay_url, bz);
            const r = spawnSync('bunzip2', [bz], { stdio: 'inherit' });
            if (r.status !== 0) throw new Error('bunzip2 failed');
            console.log(`fetched ${m.match_id}`);
            done++;
        } catch (e) {
            console.error(`skip ${m.match_id}: ${e.message}`);
        }
    }
    console.log(`${done} replays in ${outDir}`);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});

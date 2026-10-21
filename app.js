'use strict';

// ---------- Speicher ----------
// Playlist-Liste, Favoriten usw. liegen in localStorage,
// der (oft sehr grosse) M3U-Inhalt in IndexedDB.

const LS = {
  get(key, fallback) {
    try {
      const v = localStorage.getItem(key);
      return v === null ? fallback : JSON.parse(v);
    } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch {}
  },
};

const DB = (() => {
  let dbPromise;
  function open() {
    if (!dbPromise) {
      dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open('iptv', 1);
        req.onupgradeneeded = () => req.result.createObjectStore('playlists');
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    }
    return dbPromise;
  }
  async function run(mode, fn) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('playlists', mode);
      const req = fn(tx.objectStore('playlists'));
      tx.oncomplete = () => resolve(req && req.result);
      tx.onerror = () => reject(tx.error);
    });
  }
  return {
    get: (id) => run('readonly', (s) => s.get(id)),
    put: (id, text) => run('readwrite', (s) => s.put(text, id)),
    del: (id) => run('readwrite', (s) => s.delete(id)),
  };
})();

// ---------- M3U-Parser ----------

function parseAttrs(str) {
  const attrs = {};
  const re = /([\w-]+)="([^"]*)"/g;
  let m;
  while ((m = re.exec(str))) attrs[m[1].toLowerCase()] = m[2];
  return attrs;
}

function parseM3U(text) {
  const lines = text.replace(/^﻿/, '').split(/\r?\n/);
  const channels = [];
  let current = null;
  let extgrp = '';

  for (let raw of lines) {
    const line = raw.trim();
    if (!line) continue;

    if (line.startsWith('#EXTINF')) {
      const comma = findTitleComma(line);
      const meta = line.slice(0, comma);
      const attrs = parseAttrs(meta);
      const title = line.slice(comma + 1).trim();
      current = {
        name: title || attrs['tvg-name'] || 'Unbenannt',
        logo: attrs['tvg-logo'] || '',
        group: attrs['group-title'] || '',
      };
    } else if (line.startsWith('#EXTGRP:')) {
      extgrp = line.slice(8).trim();
    } else if (line.startsWith('#')) {
      continue;
    } else {
      const ch = current || { name: line.split('/').pop() || line, logo: '', group: '' };
      if (!ch.group && extgrp) ch.group = extgrp;
      ch.url = line;
      ch.id = line;
      channels.push(ch);
      current = null;
      extgrp = '';
    }
  }
  return channels;
}

// Komma, das den Titel einleitet (Kommas in "…"-Attributen ignorieren)
function findTitleComma(line) {
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') inQuotes = !inQuotes;
    else if (c === ',' && !inQuotes) return i;
  }
  return line.length;
}

// ---------- Zustand ----------

const state = {
  playlists: LS.get('playlists', []),        // [{id, name, url, count, updatedAt}]
  activeId: LS.get('activeId', null),
  favorites: new Set(LS.get('favorites', [])),
  channels: [],
  group: '★',                                 // ★ = Favoriten, '' = alle
  query: '',
  limit: 200,
  playing: null,
};

const ALL = '';
const FAV = '★';

const $ = (sel) => document.querySelector(sel);
const els = {
  list: $('#list'), groups: $('#groups'), search: $('#search'), empty: $('#empty'),
  currentName: $('#currentPlaylistName'),
  player: $('#player'), video: $('#video'), nowName: $('#nowName'), nowLogo: $('#nowLogo'),
  playerError: $('#playerError'), btnFav: $('#btnFav'),
  dlgPlaylists: $('#dlgPlaylists'), dlgAdd: $('#dlgAdd'), playlistList: $('#playlistList'),
  addName: $('#addName'), addUrl: $('#addUrl'), addFile: $('#addFile'), addText: $('#addText'),
  addStatus: $('#addStatus'), toast: $('#toast'),
};

function savePlaylists() {
  LS.set('playlists', state.playlists);
  LS.set('activeId', state.activeId);
}

function activePlaylist() {
  return state.playlists.find((p) => p.id === state.activeId) || null;
}

let toastTimer;
function toast(msg) {
  els.toast.textContent = msg;
  els.toast.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => els.toast.classList.add('hidden'), 3000);
}

// ---------- Laden ----------

async function fetchPlaylist(url) {
  if (location.protocol === 'https:' && url.startsWith('http://')) {
    // Browser blockieren http-Abrufe von https-Seiten (Mixed Content)
    throw new Error('MIXED');
  }
  const res = await fetch(url, { cache: 'no-store' });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const text = await res.text();
  if (!text.includes('#EXTINF') && !text.includes('#EXTM3U')) {
    throw new Error('Keine gültige M3U-Datei');
  }
  return text;
}

function describeFetchError(err) {
  if (err.message === 'MIXED') {
    return 'Der Link beginnt mit http:// – Safari lädt ihn hier nicht direkt. Lade die M3U-Datei herunter und wähle sie unten unter „Datei oder Text verwenden“ aus.';
  }
  if (err instanceof TypeError) {
    return 'Der Server erlaubt keinen direkten Abruf aus dem Browser (CORS). Lade die M3U-Datei herunter und wähle sie unten aus, oder füge den Inhalt ein.';
  }
  return 'Laden fehlgeschlagen: ' + err.message;
}

async function loadActive({ refresh = false } = {}) {
  const pl = activePlaylist();
  els.currentName.textContent = pl ? pl.name : 'Keine Playlist';
  if (!pl) {
    state.channels = [];
    render();
    return;
  }

  let text = refresh ? null : await DB.get(pl.id).catch(() => null);
  if (!text && pl.url) {
    try {
      text = await fetchPlaylist(pl.url);
      await DB.put(pl.id, text);
      pl.updatedAt = Date.now();
      if (refresh) toast('Playlist aktualisiert');
    } catch (err) {
      toast(describeFetchError(err));
      text = await DB.get(pl.id).catch(() => null);
    }
  } else if (refresh && !pl.url) {
    toast('Diese Playlist stammt aus einer Datei – bitte neu hinzufügen.');
    text = await DB.get(pl.id).catch(() => null);
  }

  state.channels = text ? parseM3U(text) : [];
  pl.count = state.channels.length;
  savePlaylists();

  const groups = new Set(state.channels.map((c) => c.group));
  if (state.group !== FAV && state.group !== ALL && !groups.has(state.group)) state.group = ALL;
  if (state.group === FAV && !state.channels.some((c) => state.favorites.has(c.id))) state.group = ALL;
  render();
}

// ---------- Darstellung ----------

function filtered() {
  const q = state.query.toLowerCase();
  return state.channels.filter((c) => {
    if (state.group === FAV && !state.favorites.has(c.id)) return false;
    if (state.group !== FAV && state.group !== ALL && c.group !== state.group) return false;
    if (q && !c.name.toLowerCase().includes(q)) return false;
    return true;
  });
}

function renderGroups() {
  const groups = [...new Set(state.channels.map((c) => c.group).filter(Boolean))];
  els.groups.replaceChildren();
  const make = (value, label) => {
    const b = document.createElement('button');
    b.textContent = label;
    b.className = state.group === value ? 'active' : '';
    b.onclick = () => { state.group = value; state.limit = 200; render(); };
    els.groups.append(b);
  };
  make(FAV, '★ Favoriten');
  make(ALL, 'Alle');
  groups.forEach((g) => make(g, g));
}

function logoEl(ch) {
  if (ch.logo) {
    const img = document.createElement('img');
    img.className = 'ch-logo';
    img.loading = 'lazy';
    img.alt = '';
    img.referrerPolicy = 'no-referrer';
    img.src = ch.logo;
    img.onerror = () => img.replaceWith(initialsEl(ch));
    return img;
  }
  return initialsEl(ch);
}

function initialsEl(ch) {
  const d = document.createElement('div');
  d.className = 'ch-logo';
  d.textContent = ch.name.replace(/[^\p{L}\p{N}]/gu, '').slice(0, 2).toUpperCase() || 'TV';
  return d;
}

function renderList() {
  const items = filtered();
  els.list.replaceChildren();

  const hasPlaylist = state.playlists.length > 0;
  els.empty.classList.toggle('hidden', hasPlaylist);
  if (!hasPlaylist) return;

  if (!items.length) {
    const p = document.createElement('p');
    p.className = 'empty';
    p.textContent = state.channels.length
      ? (state.group === FAV ? 'Noch keine Favoriten. Tippe im Player auf ☆.' : 'Keine Sender gefunden.')
      : 'Diese Playlist ist leer oder konnte nicht geladen werden.';
    els.list.append(p);
    return;
  }

  const frag = document.createDocumentFragment();
  for (const ch of items.slice(0, state.limit)) {
    const b = document.createElement('button');
    b.className = 'channel' + (state.playing && state.playing.id === ch.id ? ' playing' : '');
    const text = document.createElement('span');
    text.className = 'ch-text';
    const name = document.createElement('span');
    name.className = 'ch-name';
    name.textContent = ch.name;
    const group = document.createElement('span');
    group.className = 'ch-group';
    group.textContent = ch.group;
    text.append(name, group);
    b.append(logoEl(ch), text);
    if (state.favorites.has(ch.id)) {
      const star = document.createElement('span');
      star.className = 'ch-fav';
      star.textContent = '★';
      b.append(star);
    }
    b.onclick = () => play(ch);
    frag.append(b);
  }
  els.list.append(frag);

  if (items.length > state.limit) {
    const more = document.createElement('button');
    more.className = 'more';
    more.textContent = `Mehr anzeigen (${items.length - state.limit} weitere)`;
    more.onclick = () => { state.limit += 300; renderList(); };
    els.list.append(more);
  }
}

function render() {
  renderGroups();
  renderList();
}

// ---------- Player ----------

let hls = null;

function play(ch) {
  state.playing = ch;
  LS.set('lastChannel', ch.id);
  els.player.classList.remove('hidden');
  els.playerError.classList.add('hidden');
  els.nowName.textContent = ch.name;
  els.nowLogo.src = ch.logo || '';
  updateFavButton();
  renderList();

  const video = els.video;
  if (hls) { hls.destroy(); hls = null; }
  video.removeAttribute('src');

  const url = ch.url;
  const isHls = /\.m3u8(\?|$)/i.test(url);

  if (location.protocol === 'https:' && url.startsWith('http://')) {
    showPlayerError('Dieser Sender läuft über http:// und wird von Safari in der Web-App blockiert. Tippe auf „VLC“, um ihn in der VLC-App zu öffnen.');
  }

  if (video.canPlayType('application/vnd.apple.mpegurl')) {
    // iPhone/iPad/Safari: HLS nativ
    video.src = url;
  } else if (isHls && window.Hls && Hls.isSupported()) {
    hls = new Hls();
    hls.loadSource(url);
    hls.attachMedia(video);
    hls.on(Hls.Events.ERROR, (_, data) => {
      if (data.fatal) showPlayerError('Stream konnte nicht geladen werden. Versuche „VLC“.');
    });
  } else {
    video.src = url;
  }

  video.play().catch(() => {});
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function showPlayerError(msg) {
  els.playerError.textContent = msg;
  els.playerError.classList.remove('hidden');
}

els.video.addEventListener('error', () => {
  showPlayerError('Stream kann hier nicht abgespielt werden (Format oder Verbindung). Tippe auf „VLC“, um ihn in der VLC-App zu öffnen.');
});
els.video.addEventListener('playing', () => els.playerError.classList.add('hidden'));

function closePlayer() {
  if (hls) { hls.destroy(); hls = null; }
  els.video.pause();
  els.video.removeAttribute('src');
  els.video.load();
  els.player.classList.add('hidden');
  state.playing = null;
  renderList();
}

function updateFavButton() {
  const fav = state.playing && state.favorites.has(state.playing.id);
  els.btnFav.textContent = fav ? '★' : '☆';
  els.btnFav.style.color = fav ? '#ffc940' : '';
}

function toggleFav() {
  if (!state.playing) return;
  const id = state.playing.id;
  if (state.favorites.has(id)) state.favorites.delete(id);
  else state.favorites.add(id);
  LS.set('favorites', [...state.favorites]);
  updateFavButton();
  render();
}

function openInVlc() {
  if (!state.playing) return;
  const url = state.playing.url;
  location.href = 'vlc-x-callback://x-callback-url/stream?url=' + encodeURIComponent(url);
}

// ---------- Playlists verwalten ----------

function renderPlaylistDialog() {
  els.playlistList.replaceChildren();
  for (const pl of state.playlists) {
    const li = document.createElement('li');
    if (pl.id === state.activeId) li.className = 'active';
    const sel = document.createElement('button');
    sel.className = 'pl-select';
    const strong = document.createElement('strong');
    strong.textContent = pl.name;
    const small = document.createElement('small');
    small.textContent = `${pl.count ?? 0} Sender · ${pl.url || 'aus Datei'}`;
    sel.append(strong, small);
    sel.onclick = () => {
      state.activeId = pl.id;
      state.limit = 200;
      savePlaylists();
      els.dlgPlaylists.close();
      loadActive();
    };
    const del = document.createElement('button');
    del.className = 'pl-delete';
    del.textContent = 'Löschen';
    del.onclick = async () => {
      if (!confirm(`„${pl.name}“ löschen?`)) return;
      state.playlists = state.playlists.filter((p) => p.id !== pl.id);
      await DB.del(pl.id).catch(() => {});
      if (state.activeId === pl.id) state.activeId = state.playlists[0]?.id ?? null;
      savePlaylists();
      renderPlaylistDialog();
      loadActive();
    };
    li.append(sel, del);
    els.playlistList.append(li);
  }
}

function openAddDialog() {
  els.addName.value = '';
  els.addUrl.value = '';
  els.addFile.value = '';
  els.addText.value = '';
  setStatus('');
  if (els.dlgPlaylists.open) els.dlgPlaylists.close();
  els.dlgAdd.showModal();
}

function setStatus(msg, isError = false) {
  els.addStatus.textContent = msg;
  els.addStatus.classList.toggle('error', isError);
}

async function savePlaylist(e) {
  e.preventDefault();
  const url = els.addUrl.value.trim();
  const file = els.addFile.files[0];
  const pasted = els.addText.value.trim();
  let name = els.addName.value.trim();

  let text = null;
  try {
    if (file) {
      text = await file.text();
      name ||= file.name.replace(/\.m3u8?$/i, '');
    } else if (pasted) {
      text = pasted;
    } else if (url) {
      setStatus('Lade Playlist…');
      text = await fetchPlaylist(url);
    } else {
      setStatus('Bitte einen Link eingeben (oder Datei/Text wählen).', true);
      return;
    }
  } catch (err) {
    setStatus(describeFetchError(err), true);
    els.dlgAdd.querySelector('details').open = true;
    return;
  }

  const channels = parseM3U(text);
  if (!channels.length) {
    setStatus('In dieser Playlist wurden keine Sender gefunden.', true);
    return;
  }

  const id = 'pl_' + Date.now().toString(36);
  if (!name) {
    try { name = new URL(url).hostname; } catch { name = 'Playlist'; }
  }
  await DB.put(id, text);
  state.playlists.push({ id, name, url: url || '', count: channels.length, updatedAt: Date.now() });
  state.activeId = id;
  state.group = ALL;
  state.limit = 200;
  savePlaylists();
  els.dlgAdd.close();
  toast(`${channels.length} Sender geladen`);
  loadActive();
}

// ---------- Ereignisse ----------

$('#btnPlaylists').onclick = () => { renderPlaylistDialog(); els.dlgPlaylists.showModal(); };
$('#btnAdd').onclick = openAddDialog;
$('#btnAddFirst').onclick = openAddDialog;
$('#btnReload').onclick = () => loadActive({ refresh: true });
$('#btnClose').onclick = closePlayer;
$('#btnFav').onclick = toggleFav;
$('#btnVlc').onclick = openInVlc;
$('#formAdd').addEventListener('submit', savePlaylist);
document.querySelectorAll('[data-close]').forEach((b) => {
  b.onclick = () => b.closest('dialog').close();
});
document.querySelectorAll('dialog').forEach((d) => {
  d.addEventListener('click', (e) => { if (e.target === d) d.close(); });
});

let searchTimer;
els.search.addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    state.query = els.search.value.trim();
    state.limit = 200;
    renderList();
  }, 150);
});

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}

if (!state.activeId && state.playlists.length) state.activeId = state.playlists[0].id;
loadActive();

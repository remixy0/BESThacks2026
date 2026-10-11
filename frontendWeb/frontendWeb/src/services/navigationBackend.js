// Serwis integracji panelu administratora z backendem muzeum
// Zgodny 1:1 ze specyfikacją INTEGRATION.md (kontrakt z 10 października 2026)
// HTTP: http://{host}/api/auth/login, /api/auth/csrf, /api/auth/logout
// WebSocket: ws://{host}/ws/admin (sesja Cookie JSESSIONID, role ADMIN)

import { MUSEUM_METADATA, ROOMS } from '../data/museumLayout';

/**
 * Normalizacja adresu hosta (usuwa prefiksy http/ws i końcowe slashe,
 * uzupełnia domyślny port :8081 jeśli podano samo IP)
 */
export function normalizeServerHost(input) {
  if (!input || !input.trim()) return 'localhost:8081';
  let cleaned = input.trim();
  // Usuń prefiksy protokołów
  cleaned = cleaned.replace(/^(https?:\/\/|wss?:\/\/)/i, '');
  // Usuń końcowe ukośniki i ścieżki
  cleaned = cleaned.split('/')[0];
  // Jeśli podano samo IP / domenę bez portu, dopisz domyślny port 8081
  if (!cleaned.includes(':')) {
    cleaned = `${cleaned}:8081`;
  }
  return cleaned;
}

/**
 * Konwersja współrzędnych SVG (piksele/siatka 0..1066, 0..681)
 * na układ współrzędnych modelu w metrach (origin: -106.6, -68.2, krok: 0.2m)
 */
export function svgToWorld(svgX, svgY) {
  const worldX = MUSEUM_METADATA.origin.x + (svgX + 0.5) * MUSEUM_METADATA.cellSizeM;
  const worldY = MUSEUM_METADATA.origin.y + (svgY + 0.5) * MUSEUM_METADATA.cellSizeM;
  return {
    x: Number(worldX.toFixed(2)),
    y: Number(worldY.toFixed(2))
  };
}

/**
 * Konwersja układu współrzędnych w metrach na współrzędne SVG (piksele)
 */
export function worldToSvg(worldX, worldY) {
  const svgX = Math.round((worldX - MUSEUM_METADATA.origin.x) / MUSEUM_METADATA.cellSizeM - 0.5);
  const svgY = Math.round((worldY - MUSEUM_METADATA.origin.y) / MUSEUM_METADATA.cellSizeM - 0.5);
  return {
    x: Math.max(0, Math.min(MUSEUM_METADATA.width, svgX)),
    y: Math.max(0, Math.min(MUSEUM_METADATA.height, svgY))
  };
}

/**
 * Obliczenie dystansu w metrach między dwoma punktami
 */
export function distanceMeters(p1, p2) {
  if (!p1 || !p2) return 0;
  return Number(Math.hypot(p2.x - p1.x, p2.y - p1.y).toFixed(2));
}

/**
 * Wykrycie w której sali znajduje się dany punkt w metrach
 */
export function findRoomAtWorldCoords(worldX, worldY) {
  const svgCoords = worldToSvg(worldX, worldY);
  for (const room of ROOMS) {
    if (!room.points) continue;
    const pts = room.points.trim().split(' ').map(p => {
      const [x, y] = p.split(',').map(Number);
      return { x, y };
    });
    if (pointInPolygon(svgCoords.x, svgCoords.y, pts)) {
      return room;
    }
  }
  return null;
}

// Sprawdzenie punktu w wielokącie (Ray-casting)
function pointInPolygon(x, y, vs) {
  let inside = false;
  for (let i = 0, j = vs.length - 1; i < vs.length; j = i++) {
    const xi = vs[i].x, yi = vs[i].y;
    const xj = vs[j].x, yj = vs[j].y;
    const intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

/**
 * Główny klient integracji panelu administratora z backendem muzeum
 * Zgodny z INTEGRATION.md
 */
export class AdminBackendClient {
  constructor() {
    // Domyślny adres IP / host serwera z pamięci przeglądarki
    const savedHost = typeof window !== 'undefined' ? localStorage.getItem('museum_server_host') : null;
    this.host = normalizeServerHost(savedHost || 'localhost:8081');

    this.ws = null;
    this.status = 'disconnected'; // 'connected' | 'connecting' | 'disconnected'
    this.account = null; // zalogowane konto admina
    this.csrf = null;

    this.listeners = {
      status: new Set(),
      positions: new Set(),
      policy: new Set(),
      error: new Set(),
      log: new Set()
    };

    // Stan symulatora (offline fallback, gdy backend nie jest włączony)
    this.simState = {
      alarmActive: false,
      revision: 1,
      zones: [],
      users: []
    };

    this.reconnectTimer = null;
  }

  // Pobranie aktualnego adresu IP / hosta serwera
  getHost() {
    return this.host;
  }

  // Zmiana adresu IP / hosta serwera
  setHost(newHost) {
    const normalized = normalizeServerHost(newHost);
    if (this.host === normalized) return this.host;

    this.host = normalized;
    if (typeof window !== 'undefined') {
      try {
        localStorage.setItem('museum_server_host', normalized);
      } catch {}
    }

    this.log('SYS', `Zaktualizowano adres serwera na: ${this.host}`);

    // Jeśli połączenie było aktywne, zreconnectuj z nowym adresem
    if (this.ws) {
      try { this.ws.close(); } catch {}
      this.connect();
    }

    return this.host;
  }

  getHttpBase() {
    const isHttps = typeof window !== 'undefined' && window.location.protocol === 'https:';
    return `${isHttps ? 'https' : 'http'}://${this.host}`;
  }

  getWsUrl() {
    const isWss = typeof window !== 'undefined' && window.location.protocol === 'https:';
    return `${isWss ? 'wss' : 'ws'}://${this.host}/ws/admin`;
  }

  on(event, callback) {
    if (this.listeners[event]) {
      this.listeners[event].add(callback);
    }
    return () => this.listeners[event]?.delete(callback);
  }

  notify(event, data) {
    if (this.listeners[event]) {
      this.listeners[event].forEach(cb => {
        try { cb(data); } catch (err) { console.error(err); }
      });
    }
  }

  log(direction, data) {
    const entry = {
      id: `${Date.now()}-${Math.random().toString(36).substring(2, 6)}`,
      time: new Date().toLocaleTimeString(),
      direction, // 'TX' | 'RX' | 'SYS'
      data
    };
    this.notify('log', entry);
  }

  /**
   * Logowanie administratora przez HTTP zgodnie z INTEGRATION.md
   * 1. GET /api/auth/csrf -> odbiór tokenu CSRF i cookie sesji
   * 2. POST /api/auth/login z CSRF i credentials: "include"
   */
  async login(email, password) {
    const httpBase = this.getHttpBase();

    // 1. Pobierz CSRF
    let csrfData = null;
    try {
      const csrfRes = await fetch(`${httpBase}/api/auth/csrf`, {
        method: 'GET',
        credentials: 'include'
      });
      if (!csrfRes.ok) {
        throw new Error(`Błąd pobierania tokenu CSRF z ${httpBase} (HTTP ${csrfRes.status})`);
      }
      csrfData = await csrfRes.json();
      this.csrf = csrfData;
    } catch (err) {
      throw new Error(`Nie można połączyć się z serwerem ${httpBase}. Sprawdź czy backend jest uruchomiony.`);
    }

    const csrfHeader = csrfData.headerName || 'X-CSRF-TOKEN';
    const csrfToken = csrfData.token;

    // 2. Wykonaj logowanie POST /api/auth/login
    const loginRes = await fetch(`${httpBase}/api/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        [csrfHeader]: csrfToken
      },
      credentials: 'include',
      body: JSON.stringify({ email, password })
    });

    if (!loginRes.ok) {
      let detailMsg = `Błąd logowania (HTTP ${loginRes.status})`;
      try {
        const errJson = await loginRes.json();
        if (errJson.detail) detailMsg = errJson.detail;
        else if (errJson.title) detailMsg = errJson.title;
      } catch {}
      if (loginRes.status === 401) {
        detailMsg = 'Nieprawidłowy e-mail lub hasło.';
      } else if (loginRes.status === 403) {
        detailMsg = 'Brak uprawnień lub nieprawidłowy token CSRF.';
      }
      throw new Error(detailMsg);
    }

    const account = await loginRes.json();
    this.account = account;
    this.log('SYS', `Zalogowano pomyślnie konto: ${account.email} (${account.role || 'ADMIN'})`);

    // 3. Po udanym logowaniu HTTP otwórz WebSocket /ws/admin
    this.connect();

    return account;
  }

  /**
   * Wylogowanie administratora zgodnie z INTEGRATION.md
   */
  async logout() {
    const httpBase = this.getHttpBase();
    try {
      // Pobierz świeży CSRF przed logoutem (logowanie unieważnia stary)
      const csrfRes = await fetch(`${httpBase}/api/auth/csrf`, {
        method: 'GET',
        credentials: 'include'
      });
      if (csrfRes.ok) {
        const csrfData = await csrfRes.json();
        await fetch(`${httpBase}/api/auth/logout`, {
          method: 'POST',
          headers: {
            [csrfData.headerName || 'X-CSRF-TOKEN']: csrfData.token
          },
          credentials: 'include'
        });
      }
    } catch (err) {
      console.warn('Błąd podczas HTTP logout:', err);
    } finally {
      this.disconnect();
      this.account = null;
      this.csrf = null;
    }
  }

  /**
   * Otwarcie połączenia WebSocket do /ws/admin
   */
  connect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.ws) {
      try { this.ws.close(); } catch {}
      this.ws = null;
    }

    const wsUrl = this.getWsUrl();
    this.status = 'connecting';
    this.notify('status', this.status);
    this.log('SYS', `Łączenie z kanałem administratora ${wsUrl}...`);

    try {
      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        this.status = 'connected';
        this.notify('status', this.status);
        this.log('SYS', `Połączono z kanałem administratora: ${wsUrl}`);
        // Pobierz aktualny stan (snapshot)
        this.sendSnapshot();
      };

      this.ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          this.log('RX', msg);

          if (msg.type === 'positions') {
            // Pełny zestaw lokalizacji użytkowników z backendu: msg.users
            this.notify('positions', msg.users || []);
          } else if (msg.type === 'policy') {
            // Wspólny stan alarmu i stref wyłączonych: msg.alarmActive, msg.zones, msg.exits
            this.notify('policy', msg);
          } else if (msg.type === 'error') {
            this.notify('error', msg);
          }
        } catch (err) {
          console.error('Błąd parsowania wiadomości z /ws/admin:', err);
        }
      };

      this.ws.onerror = (err) => {
        this.log('SYS', `Błąd połączenia WebSocket na ${wsUrl}`);
      };

      this.ws.onclose = (event) => {
        this.status = 'disconnected';
        this.notify('status', this.status);
        this.log('SYS', `Rozłączono z ${wsUrl} (kod ${event.code})`);

        // Jeśli administrator jest zalogowany, ponów próbę za 6 sekund
        if (this.account) {
          this.reconnectTimer = setTimeout(() => {
            this.connect();
          }, 6000);
        }
      };
    } catch (err) {
      this.status = 'disconnected';
      this.notify('status', this.status);
      this.log('SYS', `Błąd inicjalizacji WebSocket: ${err.message}`);
    }
  }

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      try { this.ws.close(); } catch {}
      this.ws = null;
    }
    this.status = 'disconnected';
    this.notify('status', this.status);
  }

  /**
   * Bezpieczne wysłanie wiadomości przez WebSocket z fallbackiem symulacyjnym
   */
  send(payload) {
    this.log('TX', payload);
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
      return true;
    }
    return false;
  }

  /**
   * Żądanie pełnego snapshotu stanu (policy i positions)
   * Klient → backend: {"type":"snapshot"}
   */
  sendSnapshot() {
    const sent = this.send({ type: 'snapshot' });
    if (!sent) {
      // Offline fallback: rozsyłamy aktualny stan symulowany
      this.notify('policy', {
        type: 'policy',
        revision: this.simState.revision,
        alarmActive: this.simState.alarmActive,
        zones: this.simState.zones,
        exits: [{ x: 0.3, y: 59.9 }, { x: 0.1, y: -61.9 }]
      });
      this.notify('positions', this.simState.users);
    }
  }

  /**
   * Włączenie lub odwołanie alarmu pożarowego
   * Klient → backend: {"type":"alarm","active":true}
   */
  sendAlarm(active) {
    const boolActive = Boolean(active);
    const sent = this.send({ type: 'alarm', active: boolActive });
    if (!sent) {
      // Offline fallback
      this.simState.alarmActive = boolActive;
      this.simState.revision++;
      this.notify('policy', {
        type: 'policy',
        revision: this.simState.revision,
        alarmActive: boolActive,
        zones: this.simState.zones,
        exits: [{ x: 0.3, y: 59.9 }, { x: 0.1, y: -61.9 }]
      });
    }
  }

  /**
   * Dodanie wyłączonej strefy (prostokąta w metrach)
   * Klient → backend: {"type":"zone.add","minX":10,"minY":10,"maxX":14,"maxY":16}
   */
  sendAddZone(minX, minY, maxX, maxY) {
    const payload = {
      type: 'zone.add',
      minX: Number(minX.toFixed(2)),
      minY: Number(minY.toFixed(2)),
      maxX: Number(maxX.toFixed(2)),
      maxY: Number(maxY.toFixed(2))
    };

    const sent = this.send(payload);
    if (!sent) {
      // Offline fallback
      const newZone = {
        id: `zone-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
        minX: payload.minX,
        minY: payload.minY,
        maxX: payload.maxX,
        maxY: payload.maxY
      };
      this.simState.zones = [...this.simState.zones, newZone];
      this.simState.revision++;
      this.notify('policy', {
        type: 'policy',
        revision: this.simState.revision,
        alarmActive: this.simState.alarmActive,
        zones: this.simState.zones,
        exits: [{ x: 0.3, y: 59.9 }, { x: 0.1, y: -61.9 }]
      });
    }
  }

  /**
   * Usunięcie wyłączonej strefy po ID (UUID)
   * Klient → backend: {"type":"zone.remove","id":"..."}
   */
  sendRemoveZone(id) {
    const payload = { type: 'zone.remove', id };
    const sent = this.send(payload);
    if (!sent) {
      // Offline fallback
      this.simState.zones = this.simState.zones.filter(z => z.id !== id);
      this.simState.revision++;
      this.notify('policy', {
        type: 'policy',
        revision: this.simState.revision,
        alarmActive: this.simState.alarmActive,
        zones: this.simState.zones,
        exits: [{ x: 0.3, y: 59.9 }, { x: 0.1, y: -61.9 }]
      });
    }
  }

  /**
   * Pomocnicza metoda do lokalnej symulacji nowej pozycji użytkownika w trybie testowym
   */
  simulateUser(username, x, y) {
    const existingIdx = this.simState.users.findIndex(u => u.username === username);
    const userObj = {
      username,
      x: Number(x.toFixed(2)),
      y: Number(y.toFixed(2)),
      receivedAt: new Date().toISOString()
    };
    if (existingIdx >= 0) {
      this.simState.users[existingIdx] = userObj;
    } else {
      this.simState.users.push(userObj);
    }
    this.notify('positions', [...this.simState.users]);
  }
}

// Globalny singleton klienta backendu administratora
export const backendClient = new AdminBackendClient();
// Alias dla czytelności
export const adminBackendClient = backendClient;

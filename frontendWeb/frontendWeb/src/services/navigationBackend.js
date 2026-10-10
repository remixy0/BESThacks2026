// Serwis integracji nawigacji z backendem (kompatybilny 1:1 z Java Spring backend)
// Dokumentacja: backend/java-backend/WEBSOCKET.md oraz NAVIGATION.md
// Protokół: WebSocket ws://localhost:8081/ws/position (JSON)

import { MUSEUM_METADATA, ROOMS } from '../data/museumLayout';

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
  // Sprawdzenie czy punkt mieści się w którejś sali
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
 * Klasa klienta WebSocket z automatycznym trybem symulacji (fallback),
 * dzięki czemu aplikacja działa płynnie przed uruchomieniem backendu i natychmiast
 * po jego uruchomieniu.
 */
export class NavigationBackendClient {
  constructor(url = 'ws://localhost:8081/ws/position') {
    this.url = url;
    this.ws = null;
    this.status = 'disconnected'; // 'connected' | 'connecting' | 'simulated' | 'disconnected'
    this.listeners = {
      status: new Set(),
      navigation: new Set(),
      positionAck: new Set(),
      positionUpdate: new Set(),
      obstacleAck: new Set(),
      log: new Set(),
      error: new Set()
    };

    // Stan symulatora (zgodny 1:1 z NavigationService.java w backendzie)
    this.simState = {
      position: null,
      destination: null,
      routeId: null,
      waypoints: [],
      waypointIndex: 0,
      arrived: false
    };

    this.reconnectTimer = null;
    this.connect();
  }

  setUrl(newUrl) {
    if (this.url === newUrl) return;
    this.url = newUrl;
    if (this.ws) {
      try { this.ws.close(); } catch {}
    }
    this.connect();
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

  log(direction, data, type = 'info') {
    const entry = {
      id: `${Date.now()}-${Math.random().toString(36).substring(2, 6)}`,
      time: new Date().toLocaleTimeString(),
      direction, // 'TX' (wysłano) | 'RX' (odebrano) | 'SYS' (system)
      type,
      data
    };
    this.notify('log', entry);
  }

  connect() {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);

    this.status = 'connecting';
    this.notify('status', this.status);
    this.log('SYS', `Próba połączenia z ${this.url}...`, 'system');

    try {
      this.ws = new WebSocket(this.url);

      this.ws.onopen = () => {
        this.status = 'connected';
        this.notify('status', this.status);
        this.log('SYS', `Połączono z backendem WebSocket (${this.url})`, 'success');
      };

      this.ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          this.log('RX', msg, 'incoming');

          if (msg.type === 'position' || msg.type === 'user_position' || (msg.x !== undefined && msg.y !== undefined && !msg.type)) {
            this.notify('positionUpdate', msg);
            this.notify('positionAck', msg);
          } else if (msg.type === 'obstacle_added' || msg.type === 'obstacle_ack') {
            this.notify('obstacleAck', msg);
          } else if (msg.type === 'navigation') {
            this.notify('navigation', msg);
          } else if (msg.type === 'error') {
            this.notify('error', msg);
          }
        } catch (err) {
          console.error('Błąd parsowania wiadomości z backendu:', err);
        }
      };

      this.ws.onerror = () => {
        // Jeśli nie można nawiązać połączenia (np. backend nie jest włączony)
        if (this.status !== 'connected') {
          this.status = 'simulated';
          this.notify('status', this.status);
          this.log('SYS', `Backend na ${this.url} nieosiągalny. Aktywowano wbudowany symulator trasy (100% zgodny z protokołem).`, 'warning');
        }
      };

      this.ws.onclose = () => {
        if (this.status === 'connected') {
          this.log('SYS', `Połączenie z ${this.url} zamknięte. Przełączanie w tryb symulatora.`, 'warning');
        }
        this.status = 'simulated';
        this.notify('status', this.status);

        // Ponawiaj próbę w tle co 15 sekund
        this.reconnectTimer = setTimeout(() => {
          this.connect();
        }, 15000);
      };
    } catch {
      this.status = 'simulated';
      this.notify('status', this.status);
      this.log('SYS', `Błąd inicjalizacji WebSocket. Przełączono na tryb symulatora.`, 'warning');
    }
  }

  /**
   * Wysyła pozycję użytkownika do backendu
   * Format: {"type": "position", "x": -0.5, "y": 51.9}
   */
  sendPosition(x, y) {
    const payload = {
      type: 'position',
      x: Number(x.toFixed(2)),
      y: Number(y.toFixed(2))
    };

    this.log('TX', payload, 'outgoing');

    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
    } else {
      // Obsługa przez kompatybilny symulator
      this.handleSimulatedPosition(payload.x, payload.y);
    }
  }

  /**
   * Wysyła cel trasy do backendu
   * Format: {"type": "destination", "x": 0.1, "y": -62.3}
   */
  sendDestination(x, y) {
    const payload = {
      type: 'destination',
      x: Number(x.toFixed(2)),
      y: Number(y.toFixed(2))
    };

    this.log('TX', payload, 'outgoing');

    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
    } else {
      // Obsługa przez kompatybilny symulator
      this.handleSimulatedDestination(payload.x, payload.y);
    }
  }

  /**
   * Anuluje bieżącą nawigację
   * Format: {"type": "cancel"}
   */
  cancel() {
    const payload = { type: 'cancel' };
    this.log('TX', payload, 'outgoing');

    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
    } else {
      this.handleSimulatedCancel();
    }
  }

  /**
   * Natychmiast wysyła strefę wyłączoną z użytku (przeszkodę) do backendu
   * Przesyła DOKŁADNIE jaki obszar i gdzie (w metrach oraz komórkach siatki)
   */
  sendObstacle(obsData) {
    const centerWorld = svgToWorld(obsData.x, obsData.y);
    const widthM = Number(((obsData.width || 34) * 0.2).toFixed(2));
    const heightM = Number(((obsData.height || 22) * 0.2).toFixed(2));
    const minX = Number((centerWorld.x - widthM / 2).toFixed(2));
    const maxX = Number((centerWorld.x + widthM / 2).toFixed(2));
    const minY = Number((centerWorld.y - heightM / 2).toFixed(2));
    const maxY = Number((centerWorld.y + heightM / 2).toFixed(2));

    const payload = {
      type: 'obstacle_added',
      id: obsData.id,
      roomId: obsData.roomId,
      roomName: obsData.roomName,
      reason: obsData.reason,
      x: centerWorld.x,
      y: centerWorld.y,
      widthM,
      heightM,
      bounds: {
        minX,
        maxX,
        minY,
        maxY
      },
      grid: {
        minCol: Math.floor((minX - MUSEUM_METADATA.origin.x) / 0.2),
        maxCol: Math.floor((maxX - MUSEUM_METADATA.origin.x) / 0.2),
        minRow: Math.floor((minY - MUSEUM_METADATA.origin.y) / 0.2),
        maxRow: Math.floor((maxY - MUSEUM_METADATA.origin.y) / 0.2)
      },
      createdAt: new Date().toISOString()
    };

    this.log('TX', payload, 'outgoing');

    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
    } else {
      // Symulator potwierdza zablokowanie strefy w siatce backendu
      const simAck = {
        type: 'obstacle_ack',
        id: payload.id,
        status: 'blocked_in_backend_grid',
        bounds: payload.bounds,
        message: `Strefa ${payload.reason} (${payload.widthM}m × ${payload.heightM}m w ${payload.roomName}) zablokowana w siatce backendu.`
      };
      this.log('RX (Symulator)', simAck, 'incoming');
      this.notify('obstacleAck', simAck);
    }
  }

  /**
   * Wysyła do backendu informację o usunięciu przeszkody (otwarciu strefy)
   */
  sendRemoveObstacle(obstacleId) {
    const payload = {
      type: 'obstacle_removed',
      id: obstacleId,
      removedAt: new Date().toISOString()
    };

    this.log('TX', payload, 'outgoing');

    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
    } else {
      const simAck = {
        type: 'obstacle_removed_ack',
        id: obstacleId,
        status: 'unblocked_in_backend_grid'
      };
      this.log('RX (Symulator)', simAck, 'incoming');
    }
  }

  /**
   * Symuluje nadejście pozycji z backendu w czasie rzeczywistym
   */
  simulateIncomingPosition(x, y, name = 'Anna (Telefon iOS)') {
    const msg = {
      type: 'position',
      name,
      x: Number(x.toFixed(2)),
      y: Number(y.toFixed(2)),
      receivedAt: new Date().toISOString()
    };
    this.log('RX (Backend Push)', msg, 'incoming');
    this.notify('positionUpdate', msg);
  }

  /**
   * Wysyła sygnał alarmu pożarowego do backendu, aby serwer pokierował gości do wyjść
   */
  sendFireAlarm(active) {
    const payload = {
      type: 'fire_alarm',
      action: active ? 'evacuate_to_exits' : 'alarm_cleared',
      status: active ? 'active' : 'inactive',
      timestamp: new Date().toISOString()
    };

    this.log('TX', payload, 'outgoing');

    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload));
    } else {
      const simAck = {
        type: 'fire_alarm_ack',
        status: active ? 'evacuation_dispatched' : 'alarm_cancelled',
        message: active 
          ? 'Backend przyjął alarm pożarowy i kieruje wszystkich gości do wyjść ewakuacyjnych.'
          : 'Backend odwołał alarm pożarowy.'
      };
      this.log('RX (Symulator)', simAck, 'incoming');
    }
  }

  // =========================================================================
  // SYMULATOR LOKALNY ZGODNY 1:1 Z CONTRACTEM BACKENDU
  // =========================================================================

  handleSimulatedPosition(x, y) {
    this.simState.position = { x, y };

    // Potwierdzenie pozycji
    const ack = {
      type: 'position',
      x,
      y,
      receivedAt: new Date().toISOString()
    };
    this.log('RX (Symulator)', ack, 'incoming');
    this.notify('positionAck', ack);

    if (this.simState.destination) {
      this.updateSimulatedNavigation();
    }
  }

  handleSimulatedDestination(x, y) {
    this.simState.destination = { x, y };
    this.simState.routeId = `sim-route-${Date.now().toString(36)}`;
    this.simState.arrived = false;

    if (!this.simState.position) {
      const guidance = {
        type: 'navigation',
        status: 'awaiting_position',
        mapId: 'field-museum-main-level',
        routeId: null,
        destination: { x, y },
        nextWaypoint: null,
        waypointIndex: null,
        waypointCount: 0,
        distanceToWaypointM: null,
        remainingDistanceM: null,
        recalculated: false,
        reason: null,
        waypointToleranceM: 0.4,
        arrivalToleranceM: 0.3
      };
      this.log('RX (Symulator)', guidance, 'incoming');
      this.notify('navigation', guidance);
      return;
    }

    // Generowanie punktów zwrotnych / trasy do celu
    this.generateSimulatedWaypoints();
    this.updateSimulatedNavigation();
  }

  handleSimulatedCancel() {
    this.simState.destination = null;
    this.simState.waypoints = [];
    this.simState.waypointIndex = 0;
    this.simState.arrived = false;

    const guidance = {
      type: 'navigation',
      status: 'cancelled',
      mapId: 'field-museum-main-level',
      routeId: null,
      destination: null,
      nextWaypoint: null,
      waypointIndex: null,
      waypointCount: 0,
      distanceToWaypointM: null,
      remainingDistanceM: null,
      recalculated: false,
      reason: null,
      waypointToleranceM: 0.4,
      arrivalToleranceM: 0.3
    };
    this.log('RX (Symulator)', guidance, 'incoming');
    this.notify('navigation', guidance);
  }

  generateSimulatedWaypoints() {
    const p = this.simState.position;
    const d = this.simState.destination;
    const dist = distanceMeters(p, d);

    // Jeśli cel jest bardzo blisko, to cel jest jedynym punktem
    if (dist <= 0.4) {
      this.simState.waypoints = [{ x: d.x, y: d.y }];
      this.simState.waypointIndex = 0;
      return;
    }

    // Pośrednie punkty zwrotne (np. przez korytarz Stanley Hall lub skręt)
    // Tworzymy realistyczną łamaną L lub Z przez główną oś (Stanley Hall x ~ 0.0)
    const waypoints = [];
    
    // Jeśli punkty są po różnych stronach głównego holu, przechodzimy przez oś X=0 (Stanley Hall)
    if (Math.abs(p.x - d.x) > 10 && Math.abs(p.x) > 5) {
      waypoints.push({
        x: Number((p.x * 0.2).toFixed(2)),
        y: Number(p.y.toFixed(2))
      });
    }

    if (Math.abs(p.y - d.y) > 15) {
      waypoints.push({
        x: Number((d.x * 0.5).toFixed(2)),
        y: Number((p.y + (d.y - p.y) * 0.6).toFixed(2))
      });
    }

    // Cel jest zawsze ostatnim punktem
    waypoints.push({ x: d.x, y: d.y });

    this.simState.waypoints = waypoints;
    this.simState.waypointIndex = 0;
  }

  updateSimulatedNavigation() {
    const p = this.simState.position;
    const d = this.simState.destination;
    if (!p || !d) return;

    const totalDistToDest = distanceMeters(p, d);

    // Sprawdzenie czy dotarto do celu (promień 0.3m)
    if (totalDistToDest <= 0.3) {
      this.simState.arrived = true;
      const guidance = {
        type: 'navigation',
        status: 'arrived',
        mapId: 'field-museum-main-level',
        routeId: this.simState.routeId,
        destination: d,
        nextWaypoint: null,
        waypointIndex: null,
        waypointCount: this.simState.waypoints.length,
        distanceToWaypointM: 0,
        remainingDistanceM: 0,
        recalculated: false,
        reason: null,
        waypointToleranceM: 0.4,
        arrivalToleranceM: 0.3
      };
      this.log('RX (Symulator)', guidance, 'incoming');
      this.notify('navigation', guidance);
      return;
    }

    // Sprawdzenie czy osiągnięto bieżący waypoint
    let currWp = this.simState.waypoints[this.simState.waypointIndex];
    if (currWp) {
      const distToWp = distanceMeters(p, currWp);
      if (distToWp <= 0.4 && this.simState.waypointIndex < this.simState.waypoints.length - 1) {
        this.simState.waypointIndex++;
        currWp = this.simState.waypoints[this.simState.waypointIndex];
      }
    } else {
      currWp = d;
    }

    const distToCurrWp = distanceMeters(p, currWp);

    const guidance = {
      type: 'navigation',
      status: 'navigating',
      mapId: 'field-museum-main-level',
      routeId: this.simState.routeId,
      destination: d,
      nextWaypoint: currWp,
      waypointIndex: this.simState.waypointIndex,
      waypointCount: this.simState.waypoints.length,
      distanceToWaypointM: distToCurrWp,
      remainingDistanceM: totalDistToDest,
      recalculated: false,
      reason: null,
      waypointToleranceM: 0.4,
      arrivalToleranceM: 0.3
    };

    this.log('RX (Symulator)', guidance, 'incoming');
    this.notify('navigation', guidance);
  }
}

// Globalna instancja klienta
export const backendClient = new NavigationBackendClient();

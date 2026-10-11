import React, { useState, useEffect, useRef } from 'react';
import { SAMPLE_PROBLEMS, DEFAULT_HAZARDS, ROOMS, MUSEUM_METADATA } from './data/museumLayout';
import MuseumMap from './components/MuseumMap';
import VisitorSidebar from './components/VisitorSidebar';
import LoginScreen from './components/LoginScreen';
import {
  backendClient,
  worldToSvg,
  findRoomAtWorldCoords
} from './services/navigationBackend';
import { Server, CheckCircle2, AlertTriangle, RefreshCw, X, Shield, Activity } from 'lucide-react';
import './App.css';

function App() {
  // Stan logowania użytkownika
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [loggedInUser, setLoggedInUser] = useState('');

  // Stan lokalizacji gości odebranych z backendu (/ws/admin "positions")
  const [visitors, setVisitors] = useState([]);
  // Stan wyłączonych stref odebranych z backendu (/ws/admin "policy")
  const [obstacles, setObstacles] = useState([]);
  const [activeHazardType, setActiveHazardType] = useState('wet_floor');
  const [customHazardText, setCustomHazardText] = useState('');
  const [isFireActive, setIsFireActive] = useState(false);
  const [selectedVisitorId, setSelectedVisitorId] = useState(null);
  const [toastMessage, setToastMessage] = useState(null);

  // Stan połączenia i konfiguracji adresu serwera
  const [serverHost, setServerHost] = useState(backendClient.getHost());
  const [backendStatus, setBackendStatus] = useState(backendClient.status);
  const [showServerModal, setShowServerModal] = useState(false);
  const [serverHostInput, setServerHostInput] = useState(backendClient.getHost());
  const [trafficLogs, setTrafficLogs] = useState([]);

  const selectedVisitorIdRef = useRef(selectedVisitorId);

  useEffect(() => {
    selectedVisitorIdRef.current = selectedVisitorId;
  }, [selectedVisitorId]);

  const showToast = (msg) => {
    setToastMessage(msg);
    setTimeout(() => {
      setToastMessage(null);
    }, 3500);
  };

  // Subskrypcja zdarzeń WebSocket administratora z backendu
  useEffect(() => {
    // 1. Odbiór aktualizacji statusu połączenia
    const unsubStatus = backendClient.on('status', (st) => {
      setBackendStatus(st);
    });

    // 2. Odbiór pełnego zestawu lokalizacji użytkowników z backendu: type "positions"
    const unsubPositions = backendClient.on('positions', (usersList) => {
      if (!Array.isArray(usersList)) return;

      const mappedVisitors = usersList.map((u) => {
        const worldX = typeof u.x === 'number' ? u.x : 0;
        const worldY = typeof u.y === 'number' ? u.y : 0;
        const svgCoords = worldToSvg(worldX, worldY);
        const room = findRoomAtWorldCoords(worldX, worldY) || ROOMS[0];

        return {
          id: u.username,
          name: u.username,
          room: room.id,
          x: svgCoords.x,
          y: svgCoords.y,
          worldX,
          worldY,
          receivedAt: u.receivedAt,
          navigationStatus: 'idle',
          problem: null
        };
      });

      setVisitors(mappedVisitors);
    });

    // 3. Odbiór stanu alarmu i wyłączonych stref: type "policy"
    const unsubPolicy = backendClient.on('policy', (policy) => {
      if (!policy) return;

      // Aktualizacja stanu alarmu
      if (typeof policy.alarmActive === 'boolean') {
        setIsFireActive(policy.alarmActive);
      }

      // Aktualizacja wyłączonych stref (zones)
      if (Array.isArray(policy.zones)) {
        const mappedObstacles = policy.zones.map((zone) => {
          const minX = Math.min(zone.minX, zone.maxX);
          const maxX = Math.max(zone.minX, zone.maxX);
          const minY = Math.min(zone.minY, zone.maxY);
          const maxY = Math.max(zone.minY, zone.maxY);

          // Konwersja metrów na współrzędne pikselowe SVG
          const svgMinX = Math.round((minX - MUSEUM_METADATA.origin.x) / MUSEUM_METADATA.cellSizeM);
          const svgMaxX = Math.round((maxX - MUSEUM_METADATA.origin.x) / MUSEUM_METADATA.cellSizeM);
          const svgMinY = Math.round((minY - MUSEUM_METADATA.origin.y) / MUSEUM_METADATA.cellSizeM);
          const svgMaxY = Math.round((maxY - MUSEUM_METADATA.origin.y) / MUSEUM_METADATA.cellSizeM);

          const width = Math.max(12, svgMaxX - svgMinX);
          const height = Math.max(12, svgMaxY - svgMinY);
          const centerX = Math.round((svgMinX + svgMaxX) / 2);
          const centerY = Math.round((svgMinY + svgMaxY) / 2);

          const centerWorldX = (minX + maxX) / 2;
          const centerWorldY = (minY + maxY) / 2;
          const room = findRoomAtWorldCoords(centerWorldX, centerWorldY) || ROOMS[0];

          return {
            id: zone.id,
            roomId: room.id,
            roomName: room.name,
            x: centerX,
            y: centerY,
            width,
            height,
            bounds: {
              minX,
              maxX,
              minY,
              maxY
            },
            reason: 'Strefa wyłączona',
            color: '#f59e0b'
          };
        });

        setObstacles(mappedObstacles);
      }
    });

    // 4. Logi komunikacji WebSocket
    const unsubLog = backendClient.on('log', (entry) => {
      setTrafficLogs(prev => [entry, ...prev.slice(0, 39)]);
    });

    return () => {
      unsubStatus();
      unsubPositions();
      unsubPolicy();
      unsubLog();
    };
  }, []);

  // Gdy użytkownik jest zalogowany, automatycznie upewnij się że WS jest podłączony i pobierz stan
  useEffect(() => {
    if (isLoggedIn) {
      if (backendClient.status === 'disconnected') {
        backendClient.connect();
      } else if (backendClient.status === 'connected') {
        backendClient.sendSnapshot();
      }
    }
  }, [isLoggedIn]);

  // Zgłoszenie problemu u danej osoby
  const handleTriggerProblem = (id) => {
    const randomProblem = SAMPLE_PROBLEMS[Math.floor(Math.random() * SAMPLE_PROBLEMS.length)];
    setVisitors(prev => prev.map(v => {
      if (v.id === id) {
        return { ...v, problem: randomProblem };
      }
      return v;
    }));
    showToast(`Zgłoszono problem: ${randomProblem}`);
  };

  // Rozwiązanie problemu u danej osoby
  const handleResolveProblem = (id) => {
    const target = visitors.find(v => v.id === id);
    setVisitors(prev => prev.map(v => {
      if (v.id === id) {
        return { ...v, problem: null };
      }
      return v;
    }));
    showToast(`Problem rozwiązany dla: ${target?.name || 'gościa'}`);
  };

  // Dodanie wyłączonej strefy (prostokąta w metrach) na mapie -> wysyłka {"type":"zone.add", ...}
  const handleAddObstacle = (obstacleData) => {
    // Oblicz współrzędne w metrach na podstawie narysowanych pikseli SVG
    const rawMinX = MUSEUM_METADATA.origin.x + obstacleData.minX * MUSEUM_METADATA.cellSizeM;
    const rawMaxX = MUSEUM_METADATA.origin.x + obstacleData.maxX * MUSEUM_METADATA.cellSizeM;
    const rawMinY = MUSEUM_METADATA.origin.y + obstacleData.minY * MUSEUM_METADATA.cellSizeM;
    const rawMaxY = MUSEUM_METADATA.origin.y + obstacleData.maxY * MUSEUM_METADATA.cellSizeM;

    let minX = Number(Math.min(rawMinX, rawMaxX).toFixed(2));
    let maxX = Number(Math.max(rawMinX, rawMaxX).toFixed(2));
    let minY = Number(Math.min(rawMinY, rawMaxY).toFixed(2));
    let maxY = Number(Math.max(rawMinY, rawMaxY).toFixed(2));

    // Zapewnienie minimalnego rozmiaru prostokąta (minX < maxX oraz minY < maxY)
    if (maxX - minX < 0.4) {
      maxX = Number((minX + 0.6).toFixed(2));
    }
    if (maxY - minY < 0.4) {
      maxY = Number((minY + 0.6).toFixed(2));
    }

    // Wysłanie komendy dodania strefy do serwera (backend przypisuje UUID i odsyła policy)
    backendClient.sendAddZone(minX, minY, maxX, maxY);
    // Zgodnie z wytycznymi użytkownika: brak powiadomienia toast po dodaniu strefy
  };

  // Usunięcie wyłączonej strefy -> wysyłka {"type":"zone.remove","id":...}
  const handleRemoveObstacle = (id) => {
    backendClient.sendRemoveZone(id);
    showToast('Usunięto strefę — obszar odblokowany.');
  };

  // Włączenie / wyłączenie alarmu pożarowego -> wysyłka {"type":"alarm","active":...}
  const handleToggleFire = () => {
    const nextState = !isFireActive;
    backendClient.sendAlarm(nextState);

    if (nextState) {
      showToast('Sygnał alarmu pożarowego wysłany do backendu');

      if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
        window.speechSynthesis.cancel();
        const msg = new SpeechSynthesisUtterance('Uwaga! Alarm pożarowy w Field Museum. Prosimy udać się do wyjść ewakuacyjnych.');
        msg.lang = 'pl-PL';
        window.speechSynthesis.speak(msg);
      }
    } else {
      showToast('Alarm pożarowy odwołany');

      if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
        window.speechSynthesis.cancel();
      }
    }
  };

  // Zmiana adresu hosta serwera w trakcie pracy
  const handleSaveServerHost = (e) => {
    e.preventDefault();
    const updated = backendClient.setHost(serverHostInput);
    setServerHost(updated);
    setServerHostInput(updated);
    showToast(`Zaktualizowano adres serwera: ${updated}`);
  };

  // Wylogowanie administratora
  const handleLogout = async () => {
    try {
      await backendClient.logout();
    } catch {}
    setIsLoggedIn(false);
    setVisitors([]);
    setObstacles([]);
    showToast('Wylogowano z panelu administratora');
  };

  // Jeśli użytkownik nie jest jeszcze zalogowany, wyświetl ekran logowania
  if (!isLoggedIn) {
    return (
      <LoginScreen
        onLoginSuccess={(user) => {
          setIsLoggedIn(true);
          setLoggedInUser(user);
          setServerHost(backendClient.getHost());
        }}
      />
    );
  }

  const isConnected = backendStatus === 'connected';
  const isConnecting = backendStatus === 'connecting';

  return (
    <div className={`app-root ${isFireActive ? 'fire-mode' : ''}`}>
      {/* Toast z powiadomieniem */}
      {toastMessage && (
        <div className="toast-notification">
          {toastMessage}
        </div>
      )}

      {/* Górny pasek nawigacji */}
      <header className="main-header">
        <div className="header-brand">
          <h1>Admin Panel</h1>
        </div>

        <div className="header-actions">
          {/* Przycisk statusu i konfiguracji serwera (zmienna IP) */}
          <button
            type="button"
            className={`btn-server-indicator ${backendStatus}`}
            onClick={() => {
              setServerHostInput(backendClient.getHost());
              setShowServerModal(true);
            }}
            title="Kliknij, aby zmienić adres IP serwera lub sprawdzić połączenie"
          >
            <span className={`server-status-dot ${backendStatus}`} />
            <Server size={14} className="server-btn-icon" />
            <span className="server-label">
              Serwer: <strong>{serverHost}</strong>
            </span>
          </button>

          {/* Plakietka zalogowanego użytkownika */}
          {loggedInUser && (
            <span className="badge-user-logged">
              {loggedInUser}
            </span>
          )}

          {/* Przycisk wylogowania */}
          <button
            type="button"
            className="btn-logout-header"
            onClick={handleLogout}
            title="Wyloguj się z panelu administratora"
          >
            Wyloguj
          </button>
        </div>
      </header>

      {/* Modal konfiguracji adresu IP / hosta serwera */}
      {showServerModal && (
        <div className="ws-modal-backdrop" onClick={() => setShowServerModal(false)}>
          <div className="ws-modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="ws-modal-header">
              <div className="modal-title-with-icon">
                <Server size={20} color="#38bdf8" />
                <h3>Konfiguracja połączenia z serwerem</h3>
              </div>
              <button
                type="button"
                className="btn-close-modal"
                onClick={() => setShowServerModal(false)}
                aria-label="Zamknij"
              >
                <X size={18} />
              </button>
            </div>

            <div className="ws-modal-body">
              {/* Formularz zmiany adresu IP serwera */}
              <form onSubmit={handleSaveServerHost} className="server-config-form">
                <label htmlFor="modal-server-input">Adres serwera backendu (IP / Host:Port):</label>
                <div className="server-input-row">
                  <input
                    id="modal-server-input"
                    type="text"
                    value={serverHostInput}
                    onChange={(e) => setServerHostInput(e.target.value)}
                    placeholder="np. 192.168.1.50:8081 lub localhost:8081"
                    className="input-ws-url"
                  />
                  <button type="submit" className="btn-ws-reconnect">
                    Zapisz i połącz
                  </button>
                </div>
                <span className="server-config-hint">
                  Zmienna konfiguracji serwera jest zapisywana lokalnie i używana dla wszystkich zapytań HTTP i WebSocket (/ws/admin).
                </span>
              </form>

              {/* Podsumowanie stanu połączenia */}
              <div className="ws-status-summary">
                <div className="status-item">
                  <span className="status-label">Status połączenia:</span>
                  <span className={`status-badge ${backendStatus}`}>
                    {isConnected ? 'Połączono (Online)' : isConnecting ? 'Łączenie...' : 'Rozłączono (Offline/Symulacja)'}
                  </span>
                </div>
                <div className="status-item">
                  <span className="status-label">Kanał WebSocket:</span>
                  <code>{backendClient.getWsUrl()}</code>
                </div>
              </div>

              {/* Przyciski operacyjne */}
              <div className="ws-test-buttons-row">
                <button
                  type="button"
                  className="btn-test-action"
                  onClick={() => {
                    backendClient.sendSnapshot();
                    showToast('Wysłano zapytanie o stan (snapshot) do serwera');
                  }}
                  title="Wysyła ramkę {'type':'snapshot'} do backendu"
                >
                  <RefreshCw size={14} />
                  Pobierz stan z serwera (snapshot)
                </button>
                <button
                  type="button"
                  className="btn-test-action"
                  onClick={() => {
                    backendClient.simulateUser('demo@fieldmuseum.org', 0.2, 5.0);
                    showToast('Dodano pozycję testową demo@fieldmuseum.org (0.2m, 5.0m)');
                  }}
                  title="Symuluje zgłoszenie pozycji użytkownika"
                >
                  <Activity size={14} />
                  Symuluj pozycję testową
                </button>
              </div>

              {/* Podgląd ramek JSON komunikacji w czasie rzeczywistym */}
              <div className="ws-traffic-feed-header">
                <strong>Dziennik komunikacji z serwerem (TX = wysłano, RX = odebrano, SYS = system):</strong>
              </div>
              <div className="ws-traffic-terminal">
                {trafficLogs.length === 0 ? (
                  <div className="traffic-empty">
                    Brak zdarzeń. Oczekiwanie na ramki z serwera lub akcje administratora.
                  </div>
                ) : (
                  trafficLogs.map(log => (
                    <div key={log.id} className={`log-entry direction-${log.direction.toLowerCase()}`}>
                      <span className="log-badge">{log.direction}</span>
                      <span className="log-time">[{log.time}]</span>
                      <pre className="log-payload">
                        {typeof log.data === 'object' ? JSON.stringify(log.data, null, 2) : log.data}
                      </pre>
                    </div>
                  ))
                )}
              </div>
            </div>

            <div className="ws-modal-footer">
              <span className="ws-footer-hint">
                Zgodne w 100% z <code>INTEGRATION.md</code> (kontrakt panelu administratora).
              </span>
              <button
                type="button"
                className="btn-close-modal-footer"
                onClick={() => setShowServerModal(false)}
              >
                Zamknij
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Główny widok: Mapa + Panel boczny */}
      <div className="main-content">
        <div className="map-column">
          <MuseumMap
            visitors={visitors}
            obstacles={obstacles}
            onAddObstacle={handleAddObstacle}
            onRemoveObstacle={handleRemoveObstacle}
            activeHazardType={activeHazardType}
            onSelectHazardType={setActiveHazardType}
            customHazardText={customHazardText}
            onChangeCustomHazardText={setCustomHazardText}
            isFireActive={isFireActive}
            selectedVisitorId={selectedVisitorId}
            onSelectVisitor={setSelectedVisitorId}
          />
        </div>

        <div className="sidebar-column">
          <VisitorSidebar
            visitors={visitors}
            obstacles={obstacles}
            onRemoveObstacle={handleRemoveObstacle}
            onTriggerProblem={handleTriggerProblem}
            onResolveProblem={handleResolveProblem}
            isFireActive={isFireActive}
            onToggleFire={handleToggleFire}
            selectedVisitorId={selectedVisitorId}
            onSelectVisitor={setSelectedVisitorId}
          />
        </div>
      </div>
    </div>
  );
}

export default App;

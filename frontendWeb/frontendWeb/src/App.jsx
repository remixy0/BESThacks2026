import React, { useState, useEffect, useRef } from 'react';
import { SAMPLE_PROBLEMS, DEFAULT_HAZARDS, ROOMS } from './data/museumLayout';
import MuseumMap from './components/MuseumMap';
import VisitorSidebar from './components/VisitorSidebar';
import LoginScreen from './components/LoginScreen';
import {
  backendClient,
  svgToWorld,
  worldToSvg,
  findRoomAtWorldCoords
} from './services/navigationBackend';
import './App.css';

function App() {
  // Stan logowania użytkownika
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [loggedInUser, setLoggedInUser] = useState('');

  const [visitors, setVisitors] = useState([]);
  // Lista aktywnych przeszkód (małe prostokąty w salach)
  const [obstacles, setObstacles] = useState([]);
  const [activeHazardType, setActiveHazardType] = useState('wet_floor');
  const [customHazardText, setCustomHazardText] = useState('');
  const [isFireActive, setIsFireActive] = useState(false);
  const [selectedVisitorId, setSelectedVisitorId] = useState(null);
  const [toastMessage, setToastMessage] = useState(null);

  // Stan połączenia z backendem (WebSocket)
  const [backendStatus, setBackendStatus] = useState(backendClient.status);
  const [trafficLogs, setTrafficLogs] = useState([]);
  const [showWsConsole, setShowWsConsole] = useState(false);
  const [wsUrlInput, setWsUrlInput] = useState(backendClient.url);

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

  // Subskrypcja wiadomości i statusu WebSocket z backendu
  useEffect(() => {
    // 1. Odbiór wskazówek nawigacyjnych trasy z backendu
    const unsubNav = backendClient.on('navigation', (guidance) => {
      setVisitors(prev => prev.map(v => {
        const isTarget = v.id === selectedVisitorIdRef.current || (v.destination && guidance.destination && Math.abs(v.destination.x - guidance.destination.x) < 0.2);
        if (!isTarget) return v;

        let nextWp = null;
        if (guidance.nextWaypoint) {
          const svgWp = worldToSvg(guidance.nextWaypoint.x, guidance.nextWaypoint.y);
          nextWp = {
            x: guidance.nextWaypoint.x,
            y: guidance.nextWaypoint.y,
            svgX: svgWp.x,
            svgY: svgWp.y
          };
        }

        return {
          ...v,
          navigationStatus: guidance.status,
          nextWaypoint: nextWp,
          distanceToWaypointM: guidance.distanceToWaypointM,
          remainingDistanceM: guidance.remainingDistanceM,
          routeId: guidance.routeId
        };
      }));

      if (guidance.status === 'arrived') {
        showToast('Gość dotarł do celu!');
      } else if (guidance.status === 'blocked') {
        showToast(`Trasa zablokowana: ${guidance.reason || 'Brak ścieżki'}`);
      }
    });

    // 2. ODBIÓR AKTUALNEJ POZYCJI OSOBY NA BIEŻĄCO Z BACKENDU!
    const unsubPos = backendClient.on('positionUpdate', (posMsg) => {
      if (typeof posMsg.x !== 'number' || typeof posMsg.y !== 'number') return;
      const worldX = posMsg.x;
      const worldY = posMsg.y;
      const svgCoords = worldToSvg(worldX, worldY);
      const room = findRoomAtWorldCoords(worldX, worldY) || ROOMS[0];

      setVisitors(prev => {
        const targetId = posMsg.userId || posMsg.id;
        const exists = prev.find(v => (targetId && v.id === targetId) || (!targetId && v.id === selectedVisitorIdRef.current));

        if (exists) {
          return prev.map(v => {
            if (v.id === exists.id) {
              return {
                ...v,
                x: svgCoords.x,
                y: svgCoords.y,
                worldX,
                worldY,
                room: room.id
              };
            }
            return v;
          });
        }

        // Gdy brak jeszcze gościa na liście, automatycznie tworzymy reprezentację osoby z backendu
        const newVisitor = {
          id: targetId || Date.now(),
          name: posMsg.name || 'Gość (Live Backend)',
          room: room.id,
          x: svgCoords.x,
          y: svgCoords.y,
          worldX,
          worldY,
          destination: null,
          nextWaypoint: null,
          navigationStatus: 'idle',
          distanceToWaypointM: null,
          remainingDistanceM: null,
          problem: null
        };
        return [newVisitor, ...prev];
      });

      showToast(`Backend przesłał pozycję: (${worldX}m, ${worldY}m w sali ${room.name})`);
    });

    const unsubObsAck = backendClient.on('obstacleAck', () => {
      // Potwierdzenie z backendu bez powiadomienia na ekranie
    });

    const unsubStatus = backendClient.on('status', (st) => {
      setBackendStatus(st);
    });

    const unsubLog = backendClient.on('log', (logEntry) => {
      setTrafficLogs(prev => [logEntry, ...prev.slice(0, 19)]);
    });

    return () => {
      unsubNav();
      unsubPos();
      unsubObsAck();
      unsubStatus();
      unsubLog();
    };
  }, []);



  // Zgłoszenie losowego problemu u danej osoby
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
    showToast(`Problem rozwiązany dla: ${target?.name || 'gościa'}!`);
  };

  // Wstawianie małego prostokąta przeszkody w narysowanym miejscu sali
  const handleAddObstacle = (obstacleData) => {
    let reason = 'Mokra podłoga';
    let icon = '';
    let color = '#f59e0b';

    if (activeHazardType === 'custom' && customHazardText.trim()) {
      reason = customHazardText.trim();
      icon = '';
      color = '#38bdf8';
    } else {
      const preset = DEFAULT_HAZARDS.find(h => h.id === activeHazardType) || DEFAULT_HAZARDS[0];
      reason = preset.name;
      icon = '';
      color = preset.color;
    }

    const centerWorld = svgToWorld(obstacleData.x, obstacleData.y);
    const widthM = Number(((obstacleData.width || 34) * 0.2).toFixed(2));
    const heightM = Number(((obstacleData.height || 22) * 0.2).toFixed(2));
    const minX = Number((centerWorld.x - widthM / 2).toFixed(2));
    const maxX = Number((centerWorld.x + widthM / 2).toFixed(2));
    const minY = Number((centerWorld.y - heightM / 2).toFixed(2));
    const maxY = Number((centerWorld.y + heightM / 2).toFixed(2));

    const newObs = {
      id: `obs-${Date.now()}-${Math.random().toString(36).substring(2, 6)}`,
      roomId: obstacleData.roomId,
      roomName: obstacleData.roomName,
      x: obstacleData.x,
      y: obstacleData.y,
      worldX: centerWorld.x,
      worldY: centerWorld.y,
      width: Math.round(obstacleData.width || 34),
      height: Math.round(obstacleData.height || 22),
      widthM,
      heightM,
      bounds: { minX, maxX, minY, maxY },
      reason,
      icon,
      color
    };

    setObstacles(prev => [...prev, newObs]);

    // NATYCHMIAST PRZESYŁAMY DOKŁADNE DANE STREFY WYŁĄCZONEJ DO BACKENDU!
    backendClient.sendObstacle(newObs);
  };

  // Usunięcie przeszkody (otwarcie strefy)
  const handleRemoveObstacle = (id) => {
    setObstacles(prev => prev.filter(o => o.id !== id));
    // Informujemy backend o otwarciu obszaru:
    backendClient.sendRemoveObstacle(id);
    showToast('Usunięto strefę — obszar odblokowany.');
  };

  // Włączenie / wyłączenie alarmu pożarowego (Sygnał do backendu – to serwer kieruje gości)
  const handleToggleFire = () => {
    if (!isFireActive) {
      setIsFireActive(true);
      // Wysyłamy sygnał do backendu – to backend wyznacza trasy ewakuacji dla gości!
      backendClient.sendFireAlarm(true);
      showToast('Sygnał alarmu pożarowego wysłany do backendu! Serwer kieruje gości do wyjść.');

      // Komunikat głosowy
      if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
        window.speechSynthesis.cancel();
        const msg = new SpeechSynthesisUtterance('Uwaga! Alarm pożarowy w Field Museum. Prosimy udać się do wyjść ewakuacyjnych.');
        msg.lang = 'pl-PL';
        window.speechSynthesis.speak(msg);
      }
    } else {
      setIsFireActive(false);
      // Informujemy backend o odwołaniu alarmu
      backendClient.sendFireAlarm(false);
      showToast('Alarm pożarowy odwołany — wysłano sygnał do backendu.');

      if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
        window.speechSynthesis.cancel();
      }
    }
  };

  // Jeśli użytkownik nie jest jeszcze zalogowany, wyświetl ekran logowania
  if (!isLoggedIn) {
    return (
      <LoginScreen
        onLoginSuccess={(user) => {
          setIsLoggedIn(true);
          setLoggedInUser(user);
        }}
      />
    );
  }

  return (
    <div className={`app-root ${isFireActive ? 'fire-mode' : ''}`}>
      {/* Toast z powiadomieniem */}
      {toastMessage && (
        <div className="toast-notification">
          {toastMessage}
        </div>
      )}

      {/* Górny pasek */}
      <header className="main-header">
        <div className="header-brand">
          <h1>Admin Panel</h1>
        </div>

        <div className="header-actions">
          {loggedInUser && (
            <span className="badge-user-logged">{loggedInUser}</span>
          )}
          <button
            type="button"
            className="btn-logout-header"
            onClick={() => {
              setIsLoggedIn(false);
              showToast('Wylogowano z panelu');
            }}
            title="Wyloguj się z panelu administratora"
          >
            Wyloguj
          </button>
        </div>
      </header>

      {/* Modal: Konsola komunikacji WebSocket z backendem */}
      {showWsConsole && (
        <div className="ws-modal-backdrop" onClick={() => setShowWsConsole(false)}>
          <div className="ws-modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="ws-modal-header">
              <h3>Konsola komunikacji z backendem (WebSocket)</h3>
              <button
                type="button"
                className="btn-close-modal"
                onClick={() => setShowWsConsole(false)}
                aria-label="Zamknij"
              >
                &times;
              </button>
            </div>

            <div className="ws-modal-body">
              <div className="ws-config-bar">
                <label>Adres WebSocket:</label>
                <input
                  type="text"
                  value={wsUrlInput}
                  onChange={(e) => setWsUrlInput(e.target.value)}
                  placeholder="ws://localhost:8081/ws/position"
                  className="input-ws-url"
                />
                <button
                  type="button"
                  className="btn-ws-reconnect"
                  onClick={() => backendClient.setUrl(wsUrlInput)}
                >
                  Połącz
                </button>
              </div>

              <div className="ws-status-summary">
                <span>Status połączenia: <strong>{backendStatus}</strong></span>
                <span>Protokół: <code>ws://localhost:8081/ws/position (JSON)</code></span>
              </div>

              <div className="ws-test-buttons-row">
                <button
                  type="button"
                  className="btn-test-action"
                  onClick={() => {
                    backendClient.simulateIncomingPosition(-0.5, 42.0, 'Anna (Telefon iOS)');
                    showToast('Symulacja: Backend przysłał aktualizację pozycji Anny (-0.5m, 42.0m)');
                  }}
                  title="Symuluje nadejście pozycji z backendu w czasie rzeczywistym"
                >
                  Symuluj: Backend przesyła ruch Anny (-0.5m, 42.0m)
                </button>
                <button
                  type="button"
                  className="btn-test-action"
                  onClick={() => {
                    backendClient.simulateIncomingPosition(-58.0, 7.5, 'Jan (Czujnik UWB)');
                    showToast('Symulacja: Backend przysłał nową osobę Jana w sali Africa (-58.0m, 7.5m)');
                  }}
                  title="Symuluje zgłoszenie nowej osoby przez backend"
                >
                  Symuluj: Backend przesyła Jana w Africa (-58.0m, 7.5m)
                </button>
              </div>

              <div className="ws-traffic-feed-header">
                <strong>Ostatnie ramki JSON w czasie rzeczywistym (TX = wysłano, RX = odebrano):</strong>
              </div>
              <div className="ws-traffic-terminal">
                {trafficLogs.length === 0 ? (
                  <div className="traffic-empty">Brak wiadomości. Oczekiwanie na ramki JSON z backendu lub dodanie strefy wyłączonej.</div>
                ) : (
                  trafficLogs.map(log => (
                    <div key={log.id} className={`log-entry direction-${log.direction.toLowerCase()}`}>
                      <span className="log-badge">{log.direction}</span>
                      <span className="log-time">[{log.time}]</span>
                      <pre className="log-payload">{typeof log.data === 'object' ? JSON.stringify(log.data, null, 2) : log.data}</pre>
                    </div>
                  ))
                )}
              </div>
            </div>

            <div className="ws-modal-footer">
              <span className="ws-footer-hint">
                Zgodne w 100% z <code>WEBSOCKET.md</code> i <code>NAVIGATION.md</code> w repozytorium backendu.
              </span>
              <button
                type="button"
                className="btn-close-modal-footer"
                onClick={() => setShowWsConsole(false)}
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

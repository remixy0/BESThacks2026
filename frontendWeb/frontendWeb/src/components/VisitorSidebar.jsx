import React from 'react';
import { ROOMS } from '../data/museumLayout';

export default function VisitorSidebar({
  visitors = [],
  obstacles = [],
  onRemoveObstacle,
  onTriggerProblem,
  onResolveProblem,
  isFireActive,
  onToggleFire,
  selectedVisitorId,
  onSelectVisitor
}) {
  return (
    <div className="sidebar-container">
      {/* Nagłówek panelu */}
      <div className="sidebar-header">
        <h2>🏛️ Monitor Bezpieczeństwa</h2>
        <p>Podgląd gości na żywo & Zarządzanie wyłączeniami stref</p>
      </div>

      {/* Przycisk alarmu pożarowego */}
      <div className="fire-alert-box">
        <button
          type="button"
          className={`fire-button ${isFireActive ? 'active' : ''}`}
          onClick={onToggleFire}
        >
          {isFireActive ? '🧯 Wyłącz alarm pożarowy' : '🔥 ALARM POŻAROWY — NADAJ EWAKUACJĘ'}
        </button>
        {isFireActive && (
          <p className="fire-hint">🚨 Sygnał ewakuacji nadany do wszystkich urządzeń gości!</p>
        )}
      </div>

      {/* Okno: Aktywne wyłączenia i przeszkody (Główna rola administratora) */}
      <div className="closures-section">
        <div className="closures-header">
          <h4>🚧 Wyłączone strefy ({obstacles.length})</h4>
          <span className="closures-sub">
            Wysyłane od razu do backendu, aby urządzenia gości omijały te obszary
          </span>
        </div>

        {obstacles.length > 0 ? (
          <div className="active-closures-list">
            {obstacles.map(obs => (
              <div key={obs.id} className="active-closure-item" style={{ borderLeftColor: obs.color }}>
                <div className="closure-item-info">
                  <strong>{obs.icon} {obs.reason}</strong>
                  <span style={{ fontSize: '11px', color: '#cbd5e1' }}>
                    Sala: <strong>{obs.roomName}</strong>
                  </span>
                  <span style={{ fontSize: '10.5px', color: 'var(--text-muted)' }}>
                    Wymiary: <strong>{((obs.width || 34) * 0.2).toFixed(1)}m × {((obs.height || 22) * 0.2).toFixed(1)}m</strong>
                  </span>
                  {obs.bounds && (
                    <span style={{ fontSize: '9px', color: '#38bdf8', fontFamily: 'monospace' }}>
                      Granice: X [{obs.bounds.minX}m .. {obs.bounds.maxX}m], Y [{obs.bounds.minY}m .. {obs.bounds.maxY}m]
                    </span>
                  )}
                </div>
                <button
                  type="button"
                  className="btn-open-room"
                  onClick={() => onRemoveObstacle && onRemoveObstacle(obs.id)}
                  title="Usuń tę przeszkodę i odblokuj obszar w backendzie"
                >
                  ✕ Usuń
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div className="empty-closures-hint">
            Brak zablokowanych stref. Aby wyłączyć fragment sali z użytku, <strong>narysuj prostokąt myszką na mapie</strong>.
          </div>
        )}
      </div>

      {/* Sekcja: Pasywny podgląd obecnych gości na żywo */}
      <div className="visitors-top-bar">
        <h3>👥 Goście w muzeum ({visitors.length})</h3>
        <span className="live-pulse-badge">🔴 Podgląd live</span>
      </div>
      <div className="visitors-sub-hint">
        Lokalizacje i obecność gości są pobierane automatycznie w czasie rzeczywistym z backendu.
      </div>

      {/* Lista gości na żywo */}
      <div className="visitors-list">
        {visitors.length === 0 ? (
          <div className="empty-list">
            Brak aktywnych gości. Nowe osoby pojawią się automatycznie na mapie, gdy zalogują się w muzeum.
          </div>
        ) : (
          visitors.map(vis => {
            const hasProblem = !!vis.problem;
            const isSelected = selectedVisitorId === vis.id;
            const room = ROOMS.find(r => r.id === vis.room);

            return (
              <div 
                key={vis.id} 
                className={`visitor-card ${hasProblem ? 'has-problem' : ''} ${isSelected ? 'selected' : ''}`}
                onClick={() => onSelectVisitor && onSelectVisitor(vis.id)}
                title="Kliknij, aby podświetlić gościa na mapie"
              >
                <div className="visitor-card-header">
                  <strong>{vis.name} {isSelected ? '🎯' : ''}</strong>
                  <span className="visitor-live-tag">🟢 Na żywo</span>
                </div>

                <div className="visitor-room-display">
                  <span>Sala:</span>
                  <strong>{room ? room.name : vis.room}</strong>
                </div>

                <div className="visitor-coords-display">
                  <span>Pozycja na mapie (metry):</span>
                  <code>X: {(vis.worldX ?? 0).toFixed(2)}m, Y: {(vis.worldY ?? 0).toFixed(2)}m</code>
                </div>

                {vis.destination && (
                  <div className="visitor-dest-passive">
                    <span>Cel wybrany w telefonie:</span>
                    <strong>🏁 {vis.destination.name || 'Wybrany punkt'}</strong>
                  </div>
                )}

                {/* Sekcja problemu u danej osoby (SOS / awaria) */}
                {hasProblem ? (
                  <div className="problem-alert-box">
                    <p className="problem-text">⚠️ <strong>Zgłoszony problem:</strong> {vis.problem}</p>
                    <button
                      type="button"
                      className="btn-resolve"
                      onClick={(e) => {
                        e.stopPropagation();
                        onResolveProblem(vis.id);
                      }}
                    >
                      ✓ Oznacz jako rozwiązany
                    </button>
                  </div>
                ) : (
                  <button
                    type="button"
                    className="btn-report-problem"
                    onClick={(e) => {
                      e.stopPropagation();
                      onTriggerProblem(vis.id);
                    }}
                  >
                    ⚠️ Zgłoś problem u tego gościa
                  </button>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}

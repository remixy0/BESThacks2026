import React, { useState, useRef, useEffect } from 'react';
import { 
  ROOMS, 
  POINTS_OF_INTEREST, 
  DOORS, 
  MUSEUM_METADATA, 
  DEFAULT_HAZARDS 
} from '../data/museumLayout';
import { getRoomLayoutPositions } from '../utils/mapLayoutUtils';

// Funkcja dzieląca oficjalną nazwę sali na linie (przeniesienia do nowej linii bez zmiany żadnej litery!)
function getRoomTextLines(name) {
  if (!name) return [];

  if (name === 'Apsáalooke Women and Warriors') {
    return ['Apsáalooke', 'Women and', 'Warriors'];
  }
  if (name === 'Inside Ancient Egypt') {
    return ['Inside', 'Ancient Egypt'];
  }
  if (name === 'What Is an Animal?') {
    return ['What Is', 'an Animal?'];
  }
  if (name === 'Mammals of Africa') {
    return ['Mammals', 'of Africa'];
  }
  if (name === 'Pawnee Earth Lodge') {
    return ['Pawnee', 'Earth Lodge'];
  }
  if (name === 'Stanley Field Hall') {
    return ['Stanley', 'Field Hall'];
  }
  if (name === 'Bird Habitats') {
    return ['Bird', 'Habitats'];
  }
  if (name === 'Plant Medicine') {
    return ['Plant', 'Medicine'];
  }
  if (name === 'Museum Store') {
    return ['Museum', 'Store'];
  }
  if (name === "Founders' Room") {
    return ["Founders'", "Room"];
  }
  if (name === 'Field Bistro') {
    return ['Field', 'Bistro'];
  }
  if (name === 'Ancient Americas') {
    return ['Ancient', 'Americas'];
  }
  if (name === 'South Entrance') {
    return ['South', 'Entrance'];
  }
  if (name === 'North Entrance') {
    return ['North', 'Entrance'];
  }
  if (name === 'Science Hub') {
    return ['Science', 'Hub'];
  }
  if (name === 'Coat Check') {
    return ['Coat', 'Check'];
  }

  // Automatyczny podział wielowyrazowych nazw
  if (name.length > 12 && name.includes(' ')) {
    const words = name.split(' ');
    const mid = Math.ceil(words.length / 2);
    return [words.slice(0, mid).join(' '), words.slice(mid).join(' ')];
  }

  return [name];
}

// Zmniejszanie liter w zależności od rozmiaru pomieszczenia, aby tekst idealnie się mieścił
function getRoomFontSize(roomId) {
  if (['rice', 'sci_hub', 'Space', 'Room', 'StaffOnly', 'StaffOnly_4', 'founders'].includes(roomId)) {
    return '7.5';
  }
  if (['reptiles', 'StaffOnly_2', 'StaffOnly_3', 'StaffOnly_5', 'StaffOnly_6', 'coat_check', 'Room_3', 'Room_4', 'mastaba'].includes(roomId)) {
    return '8.5';
  }
  if (['south_entrance', 'north_entrance'].includes(roomId)) {
    return '9.5';
  }
  if (roomId === 'stanley_hall') {
    return '12.5';
  }
  return '9.5';
}


// Czyste oznaczenie tekstowe dla obiektów bez użycia emotek
function getPoiLabel(poi) {
  if (poi.kind === 'entrance') return 'WE';
  if (poi.kind === 'exhibit') return 'EK';
  const n = (poi.name || '').toLowerCase();
  if (n.includes('restroom')) return 'WC';
  if (n.includes('elevator')) return 'WIN';
  if (n.includes('stairs')) return 'SCH';
  if (n.includes('store')) return 'SKL';
  if (n.includes('atm')) return 'ATM';
  return 'POI';
}

export default function MuseumMap({
  visitors,
  obstacles = [],
  onAddObstacle,
  onRemoveObstacle,
  activeHazardType = 'wet_floor',
  onSelectHazardType,
  customHazardText = '',
  onChangeCustomHazardText,
  isFireActive,
  selectedVisitorId,
  onSelectVisitor
}) {
  // Ustalenie aktywnego powodu przeszkody (bez emotek)
  let activeReason = {
    name: 'Mokra podłoga',
    color: '#f59e0b'
  };

  if (activeHazardType === 'custom' && customHazardText.trim()) {
    activeReason = {
      name: customHazardText.trim(),
      color: '#38bdf8'
    };
  } else {
    const preset = DEFAULT_HAZARDS.find(h => h.id === activeHazardType) || DEFAULT_HAZARDS[0];
    activeReason = {
      name: preset.name,
      color: preset.color
    };
  }

  const svgRef = useRef(null);
  const hazardPickerRef = useRef(null);
  const [drawingBox, setDrawingBox] = useState(null);
  const [showHazardMenu, setShowHazardMenu] = useState(false);

  // Zamykanie menu po kliknięciu poza obszarem wyboru
  useEffect(() => {
    if (!showHazardMenu) return;
    const handleClickOutside = (e) => {
      if (hazardPickerRef.current && !hazardPickerRef.current.contains(e.target)) {
        setShowHazardMenu(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [showHazardMenu]);

  // Pobranie współrzędnych kursora w przestrzeni SVG (0..1066, 0..681)
  const getSvgCoordinates = (e) => {
    const svg = svgRef.current;
    if (!svg || !svg.createSVGPoint) return null;
    const pt = svg.createSVGPoint();
    pt.x = e.clientX;
    pt.y = e.clientY;
    const svgP = pt.matrixTransform(svg.getScreenCTM().inverse());
    return {
      x: Math.round(svgP.x),
      y: Math.round(svgP.y)
    };
  };

  // Rozpoczęcie rysowania prostokąta przeszkody po naciśnięciu myszki w sali
  const handlePointerDown = (e, room) => {
    if (e.button !== 0) return;
    const coords = getSvgCoordinates(e);
    if (!coords) return;

    if (svgRef.current && svgRef.current.setPointerCapture) {
      try {
        svgRef.current.setPointerCapture(e.pointerId);
      } catch {}
    }

    setDrawingBox({
      startX: coords.x,
      startY: coords.y,
      currentX: coords.x,
      currentY: coords.y,
      room,
      pointerId: e.pointerId
    });
  };

  // Płynne aktualizowanie rozmiaru rysowanego prostokąta w czasie rzeczywistym
  const handlePointerMove = (e) => {
    if (!drawingBox) return;
    const coords = getSvgCoordinates(e);
    if (!coords) return;

    setDrawingBox(prev => prev ? {
      ...prev,
      currentX: coords.x,
      currentY: coords.y
    } : null);
  };

  // Zakończenie rysowania – wstawienie przeszkody o DOKŁADNIE narysowanym rozmiarze
  const handlePointerUp = (e) => {
    if (!drawingBox) return;
    const coords = getSvgCoordinates(e) || { x: drawingBox.currentX, y: drawingBox.currentY };

    if (svgRef.current && svgRef.current.releasePointerCapture && drawingBox.pointerId !== undefined) {
      try {
        svgRef.current.releasePointerCapture(drawingBox.pointerId);
      } catch {}
    }

    const minX = Math.min(drawingBox.startX, coords.x);
    const maxX = Math.max(drawingBox.startX, coords.x);
    const minY = Math.min(drawingBox.startY, coords.y);
    const maxY = Math.max(drawingBox.startY, coords.y);
    const rawW = maxX - minX;
    const rawH = maxY - minY;

    const room = drawingBox.room || ROOMS[0];

    // Jeśli użytkownik tylko kliknął (ruch < 6px) -> wstawiamy domyślny prostokąt 34x22
    if (rawW < 6 && rawH < 6) {
      if (onAddObstacle) {
        onAddObstacle({
          roomId: room.id,
          roomName: room.name,
          x: drawingBox.startX,
          y: drawingBox.startY,
          width: 34,
          height: 22
        });
      }
    } else {
      // Użytkownik narysował prostokąt o DOKŁADNIE wybranym przez siebie rozmiarze!
      const width = Math.max(4, rawW);
      const height = Math.max(4, rawH);
      const centerX = Math.round(minX + width / 2);
      const centerY = Math.round(minY + height / 2);

      if (onAddObstacle) {
        onAddObstacle({
          roomId: room.id,
          roomName: room.name,
          x: centerX,
          y: centerY,
          width,
          height
        });
      }
    }

    setDrawingBox(null);
  };

  const handlePointerCancel = () => {
    if (drawingBox && svgRef.current && svgRef.current.releasePointerCapture && drawingBox.pointerId !== undefined) {
      try {
        svgRef.current.releasePointerCapture(drawingBox.pointerId);
      } catch {}
    }
    setDrawingBox(null);
  };

  return (
    <div className="map-wrapper">
      <div className="map-header-bar">
        <div>
          <h3>{MUSEUM_METADATA.name}</h3>
          <span className="map-subtitle">
            {MUSEUM_METADATA.subtitle}
          </span>
        </div>

        {/* Przycisk z plusikiem po prawej stronie okna mapy rozwijający opcje przeszkód */}
        <div className="hazard-picker-container" ref={hazardPickerRef}>
          <button
            type="button"
            className={`btn-add-obstacle-toggle ${showHazardMenu ? 'active' : ''}`}
            onClick={() => setShowHazardMenu(prev => !prev)}
            title="Wstaw przeszkodę — kliknij, aby wybrać typ przeszkody"
          >
            <span className="plus-icon">+</span>
            <span>Wstaw przeszkodę</span>
          </button>

          {showHazardMenu && (
            <div className="hazard-dropdown-menu">
              <div className="hazard-dropdown-header">Wybierz typ przeszkody:</div>
              <div className="hazard-chips-column">
                {DEFAULT_HAZARDS.map(h => {
                  const isActive = activeHazardType === h.id;
                  return (
                    <button
                      key={h.id}
                      type="button"
                      className={`hazard-chip-dropdown ${isActive ? 'active' : ''}`}
                      style={{
                        borderColor: isActive ? h.color : 'transparent',
                        backgroundColor: isActive ? `${h.color}30` : 'rgba(255,255,255,0.05)',
                        color: isActive ? '#ffffff' : '#cbd5e1'
                      }}
                      onClick={() => {
                        if (onSelectHazardType) onSelectHazardType(h.id);
                        if (onChangeCustomHazardText) onChangeCustomHazardText('');
                        setShowHazardMenu(false);
                      }}
                      title={`Wybierz powód: ${h.name}`}
                    >
                      <span className="hazard-dot" style={{ backgroundColor: h.color }} />
                      <span>{h.name}</span>
                    </button>
                  );
                })}

                <div className="custom-hazard-box-dropdown">
                  <input
                    type="text"
                    className={`input-custom-hazard ${activeHazardType === 'custom' && customHazardText ? 'active' : ''}`}
                    placeholder="Wpisz inny powód..."
                    value={customHazardText}
                    onChange={(e) => {
                      const val = e.target.value;
                      if (onChangeCustomHazardText) onChangeCustomHazardText(val);
                      if (onSelectHazardType) {
                        if (val.trim()) {
                          onSelectHazardType('custom');
                        } else {
                          onSelectHazardType('wet_floor');
                        }
                      }
                    }}
                    onFocus={() => {
                      if (customHazardText.trim() && onSelectHazardType) {
                        onSelectHazardType('custom');
                      }
                    }}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        setShowHazardMenu(false);
                      }
                    }}
                  />
                </div>
              </div>
              <div className="hazard-dropdown-hint">
                Kliknij lub przeciągnij myszką po sali na mapie, aby wstawić prostokąt przeszkody.
              </div>
            </div>
          )}
        </div>
      </div>

      <div className="svg-container">
        <svg 
          ref={svgRef}
          viewBox={`0 0 ${MUSEUM_METADATA.width} ${MUSEUM_METADATA.height}`} 
          className="museum-svg"
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerCancel={handlePointerCancel}
        >
          {/* Tło i obrys zewnętrzny gmachu Field Museum */}
          <rect 
            x="10" 
            y="10" 
            width={MUSEUM_METADATA.width - 20} 
            height={MUSEUM_METADATA.height - 20} 
            rx="20" 
            fill="#090d16" 
            stroke="#1e293b" 
            strokeWidth="3" 
          />

          {/* ======================================================== */}
          {/* WARSTWA 1: Poligony wszystkich sal (podkład / tło)        */}
          {/* Sala NIE jest wyłączana – goście mogą do niej wejść       */}
          {/* i omijać małe prostokąty przeszkód wewnątrz strefy!       */}
          {/* ======================================================== */}
          <g className="rooms-layer">
            {ROOMS.map(room => {
              const isExit = room.isEmergencyExit || room.isExit;
              const isStanley = room.id === 'stanley_hall';

              const fillColor = isExit 
                ? '#14532d' 
                : isStanley 
                  ? '#172554' 
                  : '#0f172a';

              const strokeColor = isExit 
                ? '#22c55e' 
                : isStanley 
                  ? '#3b82f6' 
                  : '#334155';

              return (
                <polygon
                  key={room.id}
                  points={room.points}
                  fill={fillColor}
                  stroke={strokeColor}
                  strokeWidth={isStanley ? 2.5 : 1.5}
                  onPointerDown={(e) => handlePointerDown(e, room)}
                  className="room-polygon"
                  style={{ cursor: 'crosshair' }}
                >
                  <title>
                    {`${room.name} — kliknij lub przeciągnij, aby narysować prostokąt przeszkody (${activeReason.name})`}
                  </title>
                </polygon>
              );
            })}
          </g>

          {/* ======================================================== */}
          {/* WARSTWA 2: Wszystkie 84 drzwi z pliku json               */}
          {/* ======================================================== */}
          <g className="doors-layer" pointerEvents="none">
            {DOORS.map(d => (
              <circle
                key={d.id}
                cx={d.x}
                cy={d.y}
                r={2.5}
                fill="#475569"
                stroke="#0f172a"
                strokeWidth="0.5"
                opacity="0.8"
              >
                <title>{`Drzwi: ${d.id} (szerokość: ${d.widthM}m)`}</title>
              </circle>
            ))}
          </g>

          {/* ======================================================== */}
          {/* WARSTWA 3: Linie i strzałki ewakuacyjne (alarm pożarowy) */}
          {/* ======================================================== */}
          {isFireActive && (
            <g className="fire-evacuation-arrows">
              {/* Ze skrzydeł do Stanley Hall */}
              <line x1="180" y1="350" x2="534" y2="350" stroke="#22c55e" strokeWidth="6" strokeDasharray="10 8" className="fire-dash" />
              <line x1="880" y1="350" x2="534" y2="350" stroke="#22c55e" strokeWidth="6" strokeDasharray="10 8" className="fire-dash" />
              {/* Do North Entrance */}
              <line x1="534" y1="350" x2="534" y2="50" stroke="#22c55e" strokeWidth="7" strokeDasharray="10 8" className="fire-dash" />
              <polygon points="534,30 520,55 548,55" fill="#22c55e" />
              {/* Do South Entrance */}
              <line x1="534" y1="350" x2="534" y2="620" stroke="#22c55e" strokeWidth="7" strokeDasharray="10 8" className="fire-dash" />
              <polygon points="534,645 520,620 548,620" fill="#22c55e" />
            </g>
          )}

          {/* ======================================================== */}
          {/* WARSTWA 4: Wszystkie obiekty POI W KWADRATACH (25 sztuk) */}
          {/* Obiekty są w KWADRATACH, aby LUDZIE w KÓŁKACH się wyróżniali! */}
          {/* Rysowane PRZED napisami sal, aby ich nie zasłaniały!      */}
          {/* ======================================================== */}
          <g className="poi-layer" pointerEvents="none">
            {POINTS_OF_INTEREST.map(poi => {
              const isExhibit = poi.kind === 'exhibit';
              const isEntrance = poi.kind === 'entrance';
              const boxSize = isExhibit ? 22 : 18;
              const boxR = isExhibit ? 4 : 3;
              const boxBorder = isExhibit ? '#38bdf8' : isEntrance ? '#22c55e' : '#94a3b8';
              const boxFill = isExhibit ? 'rgba(15, 23, 42, 0.94)' : 'rgba(15, 23, 42, 0.88)';

              // Podpis tekstowy wyłącznie dla głównych obiektów w otwartym holu (nie kolidują z nazwami sal)
              const showSubtitle = isExhibit && ['POI_maximo', 'POI_elephants', 'POI_totems', 'POI_tsavo_lions', 'POI_mask'].includes(poi.id);

              return (
                <g key={poi.id} transform={`translate(${poi.x}, ${poi.y})`}>
                  <title>{`${poi.name} (${poi.kind})`}</title>

                  {/* Kwadrat tła dla eksponatu/obiektu (wyróżnia go od okrągłych ludzi!) */}
                  <rect 
                    x={-boxSize / 2} 
                    y={-boxSize / 2} 
                    width={boxSize} 
                    height={boxSize} 
                    rx={boxR} 
                    fill={boxFill} 
                    stroke={boxBorder} 
                    strokeWidth={isExhibit ? 1.5 : 1} 
                  />

                  {/* Oznaczenie tekstowe obiektu wewnątrz kwadratu (bez emotek) */}
                  <text 
                    x="0" 
                    y="0.5" 
                    textAnchor="middle" 
                    dominantBaseline="central" 
                    fontSize={isExhibit ? 8.5 : 7.5}
                    fill={isExhibit ? '#38bdf8' : isEntrance ? '#4ade80' : '#cbd5e1'}
                    fontWeight="bold"
                  >
                    {getPoiLabel(poi)}
                  </text>

                  {/* Podpis tekstowy dla głównych eksponatów */}
                  {showSubtitle && (
                    <text
                      x="0"
                      y="18"
                      textAnchor="middle"
                      fill="#38bdf8"
                      fontSize="7.5"
                      fontWeight="bold"
                      style={{
                        paintOrder: 'stroke fill',
                        stroke: '#080d1a',
                        strokeWidth: '2.5px',
                        strokeLinejoin: 'round'
                      }}
                    >
                      {poi.name}
                    </text>
                  )}
                </g>
              );
            })}
          </g>

          {/* ======================================================== */}
          {/* WARSTWA 5: Małe prostokąty przeszkód w salach            */}
          {/* Małe strefy ominięcia (mokra podłoga, uszkodzenia, itp.)  */}
          {/* ======================================================== */}
          <g className="obstacles-layer">
            {obstacles.map(obs => {
              const w = obs.width || 34;
              const h = obs.height || 22;

              return (
                <g
                  key={obs.id}
                  transform={`translate(${obs.x}, ${obs.y})`}
                  onPointerDown={(e) => e.stopPropagation()}
                  onClick={(e) => {
                    e.stopPropagation();
                    if (onRemoveObstacle) onRemoveObstacle(obs.id);
                  }}
                  className="obstacle-group"
                  style={{ cursor: 'pointer' }}
                >
                  <title>{`${obs.reason} w sali ${obs.roomName} — kliknij, aby usunąć przeszkodę`}</title>

                  {/* Cień pod małym prostokątem */}
                  <rect
                    x={-w / 2 + 1}
                    y={-h / 2 + 1}
                    width={w}
                    height={h}
                    rx="4"
                    fill="rgba(0,0,0,0.5)"
                  />

                  {/* Mały prostokąt przeszkody z taśmą ostrzegawczą */}
                  <rect
                    x={-w / 2}
                    y={-h / 2}
                    width={w}
                    height={h}
                    rx="4"
                    fill={`${obs.color}28`}
                    stroke={obs.color}
                    strokeWidth="1.8"
                    strokeDasharray="4 2"
                  />

                  {/* Znak ostrzegawczy w środku małego prostokąta */}
                  <text
                    x="0"
                    y="1"
                    textAnchor="middle"
                    dominantBaseline="central"
                    fontSize="10"
                    fontWeight="bold"
                    fill={obs.color}
                  >
                    !
                  </text>

                  {/* Podpis z nazwą przeszkody pod prostokątem */}
                  <text
                    x="0"
                    y={h / 2 + 8}
                    textAnchor="middle"
                    fill={obs.color}
                    fontSize="7"
                    fontWeight="bold"
                    style={{
                      paintOrder: 'stroke fill',
                      stroke: '#080d1a',
                      strokeWidth: '2.5px',
                      strokeLinejoin: 'round',
                      userSelect: 'none'
                    }}
                  >
                    {obs.reason}
                  </text>
                </g>
              );
            })}
          </g>

          {/* ======================================================== */}
          {/* WARSTWA 6: Etykiety i nazwy sal (ZAWSZE NA WIERZCHU!)    */}
          {/* Renderowane na wierzchu POI i ścian z obrysem halo       */}
          {/* ======================================================== */}
          <g className="labels-layer" pointerEvents="none">
            {ROOMS.map(room => {
              const lines = getRoomTextLines(room.name);
              const fontSize = getRoomFontSize(room.id);
              const pos = getRoomLayoutPositions(room, false);

              return (
                <text
                  key={`label-${room.id}`}
                  x={pos.labelX}
                  y={pos.labelY}
                  textAnchor="middle"
                  fill="#ffffff"
                  fontSize={fontSize}
                  fontWeight="bold"
                  style={{
                    paintOrder: 'stroke fill',
                    stroke: '#080d1a',
                    strokeWidth: '3.5px',
                    strokeLinejoin: 'round',
                    userSelect: 'none'
                  }}
                >
                  {lines.map((line, idx) => {
                    const dy = idx === 0 ? `${-((lines.length - 1) * 0.55)}em` : '1.15em';
                    return (
                      <tspan
                        key={`${room.id}-${line}`}
                        x={pos.labelX}
                        dy={dy}
                      >
                        {line}
                      </tspan>
                    );
                  })}
                </text>
              );
            })}
          </g>

          {/* ======================================================== */}
          {/* WARSTWA 6.5: Nawigacja backendu (Kolejny punkt & Trasa) */}
          {/* Wyświetla kolejny punkt z backendu (nextWaypoint)        */}
          {/* ======================================================== */}
          <g className="navigation-layer" pointerEvents="none">
            {visitors.map(vis => {
              if (!vis.destination && !vis.nextWaypoint) return null;

              const room = ROOMS.find(r => r.id === vis.room) || ROOMS[0];
              const roomVisitors = visitors.filter(v => v.room === room.id);
              const visIndexInRoom = roomVisitors.findIndex(v => v.id === vis.id);
              const total = roomVisitors.length;
              const offset = (visIndexInRoom - (total - 1) / 2) * 26;
              const pos = getRoomLayoutPositions(room, false);

              const startX = vis.x !== undefined ? vis.x : (pos.visitorBaseX + offset);
              const startY = vis.y !== undefined ? vis.y : pos.visitorBaseY;

              const nextWp = vis.nextWaypoint;
              const dest = vis.destination;
              const isSelected = selectedVisitorId === vis.id;

              return (
                <g key={`nav-${vis.id}`} opacity={isSelected ? 1 : 0.75}>
                  {/* Linia od gościa do kolejnego punktu wskazanego przez backend */}
                  {nextWp && (
                    <>
                      <line
                        x1={startX}
                        y1={startY}
                        x2={nextWp.svgX}
                        y2={nextWp.svgY}
                        stroke="#38bdf8"
                        strokeWidth="3.5"
                        strokeDasharray="6 4"
                        strokeLinecap="round"
                        className="nav-active-line"
                      />
                      {/* Dalsza linia pomocnicza do celu końcowego */}
                      {dest && dest.svgX !== undefined && (
                        <line
                          x1={nextWp.svgX}
                          y1={nextWp.svgY}
                          x2={dest.svgX}
                          y2={dest.svgY}
                          stroke="#0284c7"
                          strokeWidth="2"
                          strokeDasharray="4 4"
                          strokeOpacity="0.6"
                        />
                      )}
                      {/* Pulsujący wskaźnik KOLEJNEGO PUNKTU (nextWaypoint) */}
                      <g transform={`translate(${nextWp.svgX}, ${nextWp.svgY})`}>
                        <circle cx="0" cy="0" r="16" fill="rgba(56, 189, 248, 0.2)" stroke="#38bdf8" strokeWidth="1.5" className="nav-pulse-ring" />
                        <circle cx="0" cy="0" r="8" fill="#0284c7" stroke="#ffffff" strokeWidth="2" />
                        <circle cx="0" cy="0" r="3" fill="#ffffff" />
                        {/* Plakietka z odległością w metrach */}
                        <g transform="translate(0, -18)">
                          <rect x="-48" y="-9" width="96" height="18" rx="4" fill="#0f172a" stroke="#38bdf8" strokeWidth="1.2" />
                          <text x="0" y="1" textAnchor="middle" dominantBaseline="middle" fill="#38bdf8" fontSize="8" fontWeight="bold">
                            Kolejny punkt: {(vis.distanceToWaypointM || 0).toFixed(1)}m
                          </text>
                        </g>
                      </g>
                    </>
                  )}

                  {/* Wskaźnik celu końcowego (destination) */}
                  {dest && dest.svgX !== undefined && (
                    <g transform={`translate(${dest.svgX}, ${dest.svgY})`}>
                      <circle cx="0" cy="0" r="16" fill="rgba(34, 197, 94, 0.2)" stroke="#22c55e" strokeWidth="2" />
                      <circle cx="0" cy="0" r="8" fill="#16a34a" stroke="#ffffff" strokeWidth="2" />
                      <text x="0" y="0.5" textAnchor="middle" dominantBaseline="central" fontSize="6.5" fontWeight="bold" fill="#ffffff">CEL</text>
                      <g transform="translate(0, 19)">
                        <rect x="-45" y="-8" width="90" height="16" rx="4" fill="#0f172a" stroke="#22c55e" strokeWidth="1.2" />
                        <text x="0" y="1" textAnchor="middle" dominantBaseline="middle" fill="#22c55e" fontSize="7.5" fontWeight="bold">
                          {dest.name ? `Cel: ${dest.name}` : 'Cel trasy'}
                        </text>
                      </g>
                    </g>
                  )}
                </g>
              );
            })}
          </g>

          {/* ======================================================== */}
          {/* WARSTWA 7: Awatary gości W KÓŁKACH (NA SAMYM SZCZYCIE!)  */}
          {/* Osoby są w KÓŁKACH z białym obrysem — wyraźnie się odróżniają! */}
          {/* Nigdy nie zasłaniają napisów pokoi dzięki strefom pozycji! */}
          {/* ======================================================== */}
          <g className="visitors-layer">
            {visitors.map(vis => {
              const room = ROOMS.find(r => r.id === vis.room) || ROOMS[0];
              const roomVisitors = visitors.filter(v => v.room === room.id);
              const visIndexInRoom = roomVisitors.findIndex(v => v.id === vis.id);
              const total = roomVisitors.length;
              const offset = (visIndexInRoom - (total - 1) / 2) * 26;

              const pos = getRoomLayoutPositions(room, false);
              const posX = vis.x !== undefined ? vis.x : (pos.visitorBaseX + offset);
              const posY = vis.y !== undefined ? vis.y : pos.visitorBaseY;
              const hasProblem = Boolean(vis.problem);
              const isSelected = selectedVisitorId === vis.id;

              return (
                <g
                  key={vis.id}
                  transform={`translate(${posX}, ${posY})`}
                  onPointerDown={(e) => e.stopPropagation()}
                  onClick={(e) => {
                    e.stopPropagation();
                    onSelectVisitor(vis.id);
                  }}
                  className={`visitor-pin ${hasProblem ? 'has-problem' : ''}`}
                  style={{ cursor: 'pointer' }}
                >
                  <title>{vis.name} {hasProblem ? `(Problem: ${vis.problem})` : ''}</title>

                  {/* Poświata / cień pod postacią człowieka */}
                  <circle cx="0" cy="0" r="13" fill="rgba(0,0,0,0.6)" />

                  {/* KÓŁKO awatara gościa (wyróżnia człowieka od kwadratowych eksponatów!) */}
                  <circle
                    cx="0"
                    cy="0"
                    r="11"
                    fill={hasProblem ? '#ef4444' : isSelected ? '#3b82f6' : '#6366f1'}
                    stroke="#ffffff"
                    strokeWidth={isSelected ? 2.5 : 1.5}
                  />

                  {/* Inicjały gościa */}
                  <text
                    x="0"
                    y="3.5"
                    textAnchor="middle"
                    fill="#ffffff"
                    fontSize="8.5"
                    fontWeight="bold"
                  >
                    {vis.name.split(' ').map(n => n[0]).join('').substring(0, 2)}
                  </text>

                  {/* Imię gościa z wyraźnym obrysem halo */}
                  <text
                    x="0"
                    y="18"
                    textAnchor="middle"
                    fill={hasProblem ? '#fca5a5' : '#cbd5e1'}
                    fontSize="8"
                    fontWeight="600"
                    style={{
                      paintOrder: 'stroke fill',
                      stroke: '#080d1a',
                      strokeWidth: '2.5px',
                      strokeLinejoin: 'round'
                    }}
                  >
                    {vis.name.split(' ')[0]}
                  </text>

                  {/* Alert w razie problemu u gościa (bez emotki) */}
                  {hasProblem && (
                    <g transform="translate(8, -8)">
                      <circle cx="0" cy="0" r="5.5" fill="#ef4444" stroke="#ffffff" strokeWidth="1" />
                      <text x="0" y="0.5" textAnchor="middle" dominantBaseline="central" fill="#ffffff" fontSize="7.5" fontWeight="bold">!</text>
                    </g>
                  )}
                </g>
              );
            })}
          </g>

          {/* ======================================================== */}
          {/* WARSTWA PODGLĄDU RYSOWANEGO PROSTOKĄTA (NA ŻYWO)         */}
          {/* ======================================================== */}
          {drawingBox && (() => {
            const minX = Math.min(drawingBox.startX, drawingBox.currentX);
            const maxX = Math.max(drawingBox.startX, drawingBox.currentX);
            const minY = Math.min(drawingBox.startY, drawingBox.currentY);
            const maxY = Math.max(drawingBox.startY, drawingBox.currentY);
            const w = Math.max(4, maxX - minX);
            const h = Math.max(4, maxY - minY);
            const metersW = (w * 0.2).toFixed(1);
            const metersH = (h * 0.2).toFixed(1);

            return (
              <g className="drawing-preview-layer" pointerEvents="none">
                {/* Podgląd rysowanego prostokąta z ostrzegawczą taśmą */}
                <rect
                  x={minX}
                  y={minY}
                  width={w}
                  height={h}
                  rx="4"
                  fill={`${activeReason.color}35`}
                  stroke={activeReason.color}
                  strokeWidth="2"
                  strokeDasharray="5 3"
                />

                {/* Znak ostrzegawczy w środku rysowanego prostokąta */}
                {w >= 14 && h >= 14 && (
                  <text
                    x={minX + w / 2}
                    y={minY + h / 2}
                    textAnchor="middle"
                    dominantBaseline="central"
                    fill={activeReason.color}
                    fontSize={Math.min(14, Math.max(9, Math.min(w, h) - 4))}
                    fontWeight="bold"
                  >
                    !
                  </text>
                )}

                {/* Pigułka z wymiarami w metrach na żywo */}
                <g transform={`translate(${minX + w / 2}, ${Math.max(14, minY - 10)})`}>
                  <rect
                    x="-36"
                    y="-8"
                    width="72"
                    height="16"
                    rx="4"
                    fill="#0f172a"
                    stroke={activeReason.color}
                    strokeWidth="1.2"
                  />
                  <text
                    x="0"
                    y="1"
                    textAnchor="middle"
                    dominantBaseline="middle"
                    fill="#ffffff"
                    fontSize="8"
                    fontWeight="bold"
                  >
                    {metersW}m × {metersH}m
                  </text>
                </g>
              </g>
            );
          })()}
        </svg>
      </div>
    </div>
  );
}

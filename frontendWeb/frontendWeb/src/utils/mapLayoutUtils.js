import { ROOMS } from '../data/museumLayout';

// Prekalkulacja wymiarów sal (wielokąty / points)
export const ROOM_BOUNDS = ROOMS.reduce((acc, room) => {
  const pts = room.points.trim().split(/\s+/).map(p => {
    const [x, y] = p.split(',').map(Number);
    return { x, y };
  });
  const xs = pts.map(p => p.x);
  const ys = pts.map(p => p.y);
  acc[room.id] = {
    w: Math.max(...xs) - Math.min(...xs),
    h: Math.max(...ys) - Math.min(...ys)
  };
  return acc;
}, {});

// Wyznacza pozycje tak, aby kółka gości i plakietki wyłączenia NIGDY nie zasłaniały napisów sal
export function getRoomLayoutPositions(room, isClosed) {
  const bounds = ROOM_BOUNDS[room.id] || { w: 100, h: 80 };
  const isCompact = bounds.h <= 48;

  // W niskich salach (wysokość <= 48px) rozdzielamy poziomo:
  // Etykieta sali i plakietka po lewej, goście po prawej
  if (isCompact) {
    return {
      labelX: room.center.x - 18,
      labelY: isClosed ? room.center.y - 6 : room.center.y,
      badgeX: room.center.x - 18,
      badgeY: room.center.y + 7,
      visitorBaseX: room.center.x + 22,
      visitorBaseY: room.center.y
    };
  }

  // W standardowych wysokich salach rozdzielamy pionowo (bufor bezpieczeństwa > 15px):
  // - Etykieta sali w górnej strefie
  // - Plakietka zagrożenia na środku (gdy zamknięta)
  // - Kółka gości w dolnej strefie
  return {
    labelX: room.center.x,
    labelY: isClosed ? room.center.y - 18 : room.center.y - 12,
    badgeX: room.center.x,
    badgeY: room.center.y,
    visitorBaseX: room.center.x,
    visitorBaseY: isClosed ? room.center.y + 18 : room.center.y + 14
  };
}

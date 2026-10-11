import React, { useState } from 'react';
import { Lock, User, Shield, AlertCircle, Eye, EyeOff, Server } from 'lucide-react';
import { backendClient } from '../services/navigationBackend';

export default function LoginScreen({ onLoginSuccess }) {
  const [serverHost, setServerHost] = useState(backendClient.getHost() || 'localhost:8081');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [errorMessage, setErrorMessage] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [canOfflineBypass, setCanOfflineBypass] = useState(false);

  const handleServerChange = (e) => {
    const val = e.target.value;
    setServerHost(val);
    backendClient.setHost(val);
    if (errorMessage) setErrorMessage('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!username.trim() || !password.trim()) {
      setErrorMessage('Wprowadź login (email) oraz hasło');
      return;
    }

    setIsLoading(true);
    setErrorMessage('');
    setCanOfflineBypass(false);

    try {
      // Zapisz aktualny adres serwera przed logowaniem
      backendClient.setHost(serverHost);

      // Wywołanie autentykacji HTTP (GET /api/auth/csrf + POST /api/auth/login)
      await backendClient.login(username.trim(), password);

      setIsLoading(false);
      onLoginSuccess(username.trim());
    } catch (err) {
      setIsLoading(false);
      const msg = err?.message || 'Błąd logowania do serwera.';
      setErrorMessage(msg);
      // Umożliwiamy wejście offline w przypadku braku połączenia z backendem
      setCanOfflineBypass(true);
    }
  };

  // Wejście w trybie demonstracyjnym / offline (gdy backend nie jest jeszcze uruchomiony)
  const handleOfflineLogin = () => {
    backendClient.setHost(serverHost);
    backendClient.account = { email: username.trim() || 'admin@fieldmuseum.org', role: 'ADMIN' };
    onLoginSuccess(username.trim() || 'admin@fieldmuseum.org');
  };

  return (
    <div className="login-backdrop">
      <div className="login-card">
        {/* Ikona i nagłówek panelu */}
        <div className="login-card-header">
          <div className="login-logo-circle">
            <Shield size={36} color="#38bdf8" />
          </div>
          <h2>Monitor Bezpieczeństwa Muzeum</h2>
          <p className="login-subtitle">Panel Administratora</p>
        </div>

        {/* Komunikat o błędzie logowania */}
        {errorMessage && (
          <div className="login-error-alert" role="alert">
            <AlertCircle size={20} className="error-icon" />
            <div className="error-text-container">
              <span>{errorMessage}</span>
              {canOfflineBypass && (
                <button
                  type="button"
                  className="btn-offline-bypass"
                  onClick={handleOfflineLogin}
                >
                  Kontynuuj w trybie symulacji (offline)
                </button>
              )}
            </div>
          </div>
        )}

        {/* Formularz logowania */}
        <form onSubmit={handleSubmit} className="login-form" noValidate>
          {/* Pole Adres serwera */}
          <div className="login-form-group">
            <label htmlFor="login-server-host">Adres serwera (IP / Host:Port):</label>
            <div className="login-input-wrapper">
              <Server size={18} className="input-icon" aria-hidden="true" />
              <input
                id="login-server-host"
                type="text"
                className="login-input"
                placeholder="np. 192.168.1.100:8081 lub localhost:8081"
                value={serverHost}
                onChange={handleServerChange}
                disabled={isLoading}
              />
            </div>
            <span className="login-input-subhint">
              Domyślny port backendu to :8081. Adres jest zapamiętywany.
            </span>
          </div>

          {/* Pole Login */}
          <div className="login-form-group">
            <label htmlFor="login-username">E-mail / Login:</label>
            <div className="login-input-wrapper">
              <User size={18} className="input-icon" aria-hidden="true" />
              <input
                id="login-username"
                type="text"
                className={`login-input ${errorMessage && !username.trim() ? 'input-error' : ''}`}
                placeholder="admin@fieldmuseum.org"
                value={username}
                onChange={(e) => {
                  setUsername(e.target.value);
                  if (errorMessage) setErrorMessage('');
                }}
                disabled={isLoading}
                autoFocus
                autoComplete="username"
              />
            </div>
          </div>

          {/* Pole Hasło */}
          <div className="login-form-group">
            <label htmlFor="login-password">Hasło:</label>
            <div className="login-input-wrapper">
              <Lock size={18} className="input-icon" aria-hidden="true" />
              <input
                id="login-password"
                type={showPassword ? 'text' : 'password'}
                className={`login-input ${errorMessage && !password.trim() ? 'input-error' : ''}`}
                placeholder="Wpisz hasło..."
                value={password}
                onChange={(e) => {
                  setPassword(e.target.value);
                  if (errorMessage) setErrorMessage('');
                }}
                disabled={isLoading}
                autoComplete="current-password"
              />
              <button
                type="button"
                className="btn-toggle-password"
                onClick={() => setShowPassword(!showPassword)}
                title={showPassword ? 'Ukryj hasło' : 'Pokaż hasło'}
                aria-label={showPassword ? 'Ukryj hasło' : 'Pokaż hasło'}
                disabled={isLoading}
              >
                {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>

          {/* Przycisk Zaloguj */}
          <button type="submit" className="btn-login-submit" disabled={isLoading}>
            {isLoading ? 'Łączenie z serwerem...' : 'Zaloguj'}
          </button>
        </form>
      </div>
    </div>
  );
}

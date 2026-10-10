import React, { useState } from 'react';
import { Lock, User, Shield, AlertCircle, Eye, EyeOff } from 'lucide-react';

export default function LoginScreen({ onLoginSuccess }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [errorMessage, setErrorMessage] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  const handleSubmit = (e) => {
    e.preventDefault();

    // Sprawdzenie: jeśli login LUB hasło są puste -> błąd
    if (!username.trim() || !password.trim()) {
      setErrorMessage('Nieprawidłowe logowanie, spróbuj ponownie');
      return;
    }

    // Jeśli cokolwiek wpisano w oba pola -> sukces logowania
    setErrorMessage('');
    onLoginSuccess(username.trim());
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
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Formularz logowania */}
        <form onSubmit={handleSubmit} className="login-form" noValidate>
          {/* Pole Login */}
          <div className="login-form-group">
            <label htmlFor="login-username">Login:</label>
            <div className="login-input-wrapper">
              <User size={18} className="input-icon" aria-hidden="true" />
              <input
                id="login-username"
                type="text"
                className={`login-input ${errorMessage && !username.trim() ? 'input-error' : ''}`}
                placeholder="Wpisz login..."
                value={username}
                onChange={(e) => {
                  setUsername(e.target.value);
                  if (errorMessage) setErrorMessage('');
                }}
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
                autoComplete="current-password"
              />
              <button
                type="button"
                className="btn-toggle-password"
                onClick={() => setShowPassword(!showPassword)}
                title={showPassword ? 'Ukryj hasło' : 'Pokaż hasło'}
                aria-label={showPassword ? 'Ukryj hasło' : 'Pokaż hasło'}
              >
                {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>

          {/* Przycisk Zaloguj */}
          <button type="submit" className="btn-login-submit">
            Zaloguj
          </button>
        </form>

        <div className="login-footer-hint">
          <span>🔒 Bezpieczne logowanie do systemu dyspozytorskiego</span>
        </div>
      </div>
    </div>
  );
}

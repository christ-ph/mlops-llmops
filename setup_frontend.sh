#!/usr/bin/env bash
# setup_frontend.sh
# Crée un frontend React + Vite + Tailwind connecté à l'API Docker.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"

if [ -d "$FRONTEND_DIR/src" ]; then
  echo "⏭  Le frontend existe déjà."
  exit 0
fi

mkdir -p "$FRONTEND_DIR/src/api" "$FRONTEND_DIR/src/pages" "$FRONTEND_DIR/src/components"

# 1. package.json
cat > "$FRONTEND_DIR/package.json" <<'EOF'
{
  "name": "mlops-frontend",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "axios": "^1.7.2",
    "lucide-react": "^0.400.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.24.0",
    "recharts": "^2.12.7"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.3.1",
    "autoprefixer": "^10.4.19",
    "postcss": "^8.4.39",
    "tailwindcss": "^3.4.4",
    "vite": "^5.3.1"
  }
}
EOF

# 2. vite.config.js (Proxy vers l'API)
cat > "$FRONTEND_DIR/vite.config.js" <<'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      }
    }
  }
})
EOF

# 3. Tailwind
cat > "$FRONTEND_DIR/tailwind.config.js" <<'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
EOF
cat > "$FRONTEND_DIR/postcss.config.js" <<'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF
cat > "$FRONTEND_DIR/src/index.css" <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

# 4. index.html
cat > "$FRONTEND_DIR/index.html" <<'EOF'
<!doctype html>
<html lang="fr">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>MLOps Platform</title>
  </head>
  <body class="bg-gray-50 text-gray-900">
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

# 5. main.jsx
cat > "$FRONTEND_DIR/src/main.jsx" <<'EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>,
)
EOF

# 6. App.jsx (Navigation)
cat > "$FRONTEND_DIR/src/App.jsx" <<'EOF'
import { Routes, Route, Link, useLocation } from 'react-router-dom'
import { Activity, LayoutDashboard, PlaySquare } from 'lucide-react'
import Dashboard from './pages/Dashboard'
import Predict from './pages/Predict'

export default function App() {
  const location = useLocation();
  const navItems = [
    { path: '/', label: 'Dashboard', icon: LayoutDashboard },
    { path: '/predict', label: 'Prédiction', icon: PlaySquare },
  ];

  return (
    <div className="min-h-screen flex flex-col">
      <header className="bg-white border-b border-gray-200 px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-2 text-blue-600 font-bold text-xl">
          <Activity className="w-6 h-6" />
          <span>AI ModelOps</span>
        </div>
        <nav className="flex gap-4">
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = location.pathname === item.path;
            return (
              <Link key={item.path} to={item.path} className={`flex items-center gap-2 px-3 py-2 rounded-md transition-colors ${isActive ? 'bg-blue-50 text-blue-700' : 'text-gray-600 hover:bg-gray-100'}`}>
                <Icon className="w-4 h-4" />
                {item.label}
              </Link>
            )
          })}
        </nav>
      </header>
      <main className="flex-1 p-6 max-w-6xl mx-auto w-full">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/predict" element={<Predict />} />
        </Routes>
      </main>
    </div>
  )
}
EOF

# 7. client API
cat > "$FRONTEND_DIR/src/api/client.js" <<'EOF'
import axios from 'axios';

export const api = axios.create({
  baseURL: '/api/v1',
  headers: { 'Content-Type': 'application/json' }
});
EOF

# 8. Dashboard
cat > "$FRONTEND_DIR/src/pages/Dashboard.jsx" <<'EOF'
import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { CheckCircle2 } from 'lucide-react';

export default function Dashboard() {
  const [meta, setMeta] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    api.get('/predict/metadata')
      .then(res => setMeta(res.data))
      .catch(err => setError("Impossible de joindre l'API Docker. Vérifiez qu'elle tourne sur le port 8000."));
  }, []);

  if (error) return <div className="p-4 bg-red-50 text-red-700 rounded-md">{error}</div>;
  if (!meta) return <div>Chargement...</div>;

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold">Modèle Champion</h2>
      
      <div className="bg-white p-6 rounded-xl shadow-sm border border-gray-200">
        <div className="flex items-center gap-3 mb-4">
          <span className="bg-green-100 text-green-800 px-3 py-1 rounded-full text-sm font-semibold flex items-center gap-1">
            <CheckCircle2 className="w-4 h-4" /> En production
          </span>
          <span className="text-gray-500 text-sm">Version {meta.version}</span>
        </div>
        <h3 className="text-xl font-semibold text-gray-800">{meta.model_name}</h3>
        <p className="text-gray-500 text-sm mb-6">Alias : {meta.alias}</p>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {Object.entries(meta.metrics).map(([key, value]) => (
            <div key={key} className="bg-gray-50 p-4 rounded-lg">
              <p className="text-sm text-gray-500 font-medium">{key}</p>
              <p className="text-2xl font-bold text-gray-900">{value.toFixed(4)}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="bg-white p-6 rounded-xl shadow-sm border border-gray-200">
        <h3 className="text-lg font-semibold mb-2">Features attendues ({meta.features.length})</h3>
        <div className="flex flex-wrap gap-2">
          {meta.features.map(f => (
            <span key={f} className="bg-blue-50 text-blue-700 px-2 py-1 rounded text-xs">{f}</span>
          ))}
        </div>
      </div>
    </div>
  );
}
EOF

# 9. Predict
cat > "$FRONTEND_DIR/src/pages/Predict.jsx" <<'EOF'
import { useState } from 'react';
import { api } from '../api/client';
import { Loader2 } from 'lucide-react';

const DEFAULT_DATA = {
  "mean radius": 17.99, "mean texture": 10.38, "mean perimeter": 122.8, "mean area": 1001.0,
  "mean smoothness": 0.1184, "mean compactness": 0.2776, "mean concavity": 0.3001,
  "mean concave points": 0.1471, "mean symmetry": 0.2419, "mean fractal dimension": 0.07871,
  "radius error": 1.095, "texture error": 0.9053, "perimeter error": 8.589, "area error": 153.4,
  "smoothness error": 0.006399, "compactness error": 0.04904, "concavity error": 0.05373,
  "concave points error": 0.01587, "symmetry error": 0.03003, "fractal dimension error": 0.006193,
  "worst radius": 25.38, "worst texture": 17.33, "worst perimeter": 184.6, "worst area": 2019.0,
  "worst smoothness": 0.1622, "worst compactness": 0.6656, "worst concavity": 0.7119,
  "worst concave points": 0.2654, "worst symmetry": 0.4601, "worst fractal dimension": 0.1189
};

export default function Predict() {
  const [jsonInput, setJsonInput] = useState(JSON.stringify(DEFAULT_DATA, null, 2));
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handlePredict = async () => {
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      const parsed = JSON.parse(jsonInput);
      const res = await api.post('/predict', { records: [parsed] });
      setResult(res.data);
    } catch (err) {
      if (err instanceof SyntaxError) {
        setError("JSON invalide. Vérifiez la syntaxe.");
      } else {
        setError(err.response?.data?.error?.message || "Erreur de prédiction");
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div className="space-y-4">
        <h2 className="text-2xl font-bold">Données d'entrée</h2>
        <p className="text-gray-500 text-sm">Modifiez le JSON ci-dessous avec les features du patient, puis lancez la prédiction.</p>
        <textarea
          className="w-full h-96 p-4 font-mono text-sm bg-gray-900 text-green-400 rounded-xl focus:ring-2 focus:ring-blue-500 outline-none"
          value={jsonInput}
          onChange={(e) => setJsonInput(e.target.value)}
        />
        <button
          onClick={handlePredict}
          disabled={loading}
          className="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 rounded-xl flex justify-center items-center gap-2 transition-colors disabled:opacity-50"
        >
          {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : null}
          {loading ? 'Calcul en cours...' : 'Lancer la prédiction'}
        </button>
      </div>

      <div className="space-y-4">
        <h2 className="text-2xl font-bold">Résultat</h2>
        {error && <div className="p-4 bg-red-50 text-red-700 rounded-xl">{error}</div>}
        
        {result && (
          <div className={`p-6 rounded-xl border-2 ${result.predictions[0] === 0 ? 'bg-red-50 border-red-200' : 'bg-green-50 border-green-200'}`}>
            <h3 className="text-gray-600 font-medium mb-2">Classe prédite</h3>
            <p className={`text-4xl font-extrabold ${result.predictions[0] === 0 ? 'text-red-600' : 'text-green-600'}`}>
              {result.predictions[0] === 0 ? 'Maligne (0)' : 'Bénigne (1)'}
            </p>
            
            <div className="mt-6">
              <h3 className="text-gray-600 font-medium mb-2">Probabilités</h3>
              <div className="space-y-2">
                <div>
                  <div className="flex justify-between text-sm mb-1"><span>Maligne (0)</span><span>{(result.probabilities[0][0] * 100).toFixed(2)}%</span></div>
                  <div className="w-full bg-gray-200 rounded-full h-2"><div className="bg-red-500 h-2 rounded-full" style={{width: `${result.probabilities[0][0] * 100}%`}}></div></div>
                </div>
                <div>
                  <div className="flex justify-between text-sm mb-1"><span>Bénigne (1)</span><span>{(result.probabilities[0][1] * 100).toFixed(2)}%</span></div>
                  <div className="w-full bg-gray-200 rounded-full h-2"><div className="bg-green-500 h-2 rounded-full" style={{width: `${result.probabilities[0][1] * 100}%`}}></div></div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
EOF

echo "✔ Frontend créé avec succès dans frontend/"
echo ""
echo "Pour lancer le frontend :"
echo "  cd frontend"
echo "  npm install"
echo "  npm run dev"
echo ""
echo "Puis ouvrez http://localhost:5173"

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

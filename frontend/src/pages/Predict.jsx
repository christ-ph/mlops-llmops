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

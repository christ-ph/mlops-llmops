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

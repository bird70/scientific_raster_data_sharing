import { ErrorBoundary } from './components/ErrorBoundary'
import { ToastContainer } from './components/ToastContainer'
import { useToast } from './hooks/useToast'
import { AppRoutes } from './routes'
import './App.css'

function App() {
  const { toasts, removeToast } = useToast()

  return (
    <ErrorBoundary>
      {/* Skip links for keyboard navigation */}
      <a href="#main-content" className="skip-link">
        Skip to main content
      </a>
      <a href="#map-container" className="skip-link">
        Skip to map
      </a>
      
      <AppRoutes />
      <ToastContainer toasts={toasts} onClose={removeToast} />
    </ErrorBoundary>
  )
}

export default App

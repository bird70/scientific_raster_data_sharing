import { ErrorBoundary } from './components/ErrorBoundary'
import { ToastContainer } from './components/ToastContainer'
import { useToast } from './hooks/useToast'
import { AppRoutes } from './routes'
import './App.css'

function App() {
  const { toasts, removeToast } = useToast()

  return (
    <ErrorBoundary>
      <AppRoutes />
      <ToastContainer toasts={toasts} onClose={removeToast} />
    </ErrorBoundary>
  )
}

export default App

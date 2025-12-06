import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ToastContainer } from './components/ToastContainer';
import { Layout } from './components/Layout';
import { Explorer } from './pages/Explorer';
import { About } from './pages/About';
import { useToast } from './hooks/useToast';
import './App.css';

function App() {
  const { toasts, removeToast } = useToast();

  return (
    <ErrorBoundary>
      <BrowserRouter>
        <Layout>
          <Routes>
            <Route path="/" element={<Explorer />} />
            <Route path="/about" element={<About />} />
          </Routes>
        </Layout>
        <ToastContainer toasts={toasts} onClose={removeToast} />
      </BrowserRouter>
    </ErrorBoundary>
  );
}

export default App;

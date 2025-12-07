import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { Layout } from './components/Layout'
import { Explorer } from './pages/Explorer'
import { About } from './pages/About'
import { Browse } from './pages/Browse'

export function AppRoutes() {
  return (
    <BrowserRouter>
      <Layout>
        <Routes>
          <Route path="/" element={<Explorer />} />
          <Route path="/browse" element={<Browse />} />
          <Route path="/about" element={<About />} />
          <Route path="*" element={<Explorer />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  )
}
